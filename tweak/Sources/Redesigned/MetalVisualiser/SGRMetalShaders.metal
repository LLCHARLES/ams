// SGRMetalShaders.metal
//
// Metal 视觉器的着色器。移植自 spoti.pw 0.51.0-beta.1 的二进制规格。
//
// 二进制里提取到的原始结构:
//   pipeline ×4      kawase / blend / warp / tint
//   着色器入口       chromaPresentVertex / chromaPresentFragment
//   Frame uniform    resolution focus tilt textAspect color0_ color1_ color2_ accent
//   频谱纹理         256 x 2, 行0 = 127 频段, 行1 = 255 dB 级
//   纹理输入         cover / sound / previous
//   sampler          chromaSampler
//
// 流体数学(二进制原式):
//   ((uv - focus) * resolution) / (0.5 * min(w, h))
//
// 频谱采样(二进制原式):
//   p = clamp(x, 0, 1) * 127; i = min(int(p), 126); mix(a, b, p - i)
//
// 算法:Kawase 模糊(Kawase 2009 公开算法)—— 多级降采样 + 升采样,
//       只用双线性采样,无可分离卷积核。逐帧实时渲染,故选它而非高斯。
//
// 与原实现无代码关联: 这是依据上述规格的独立实现。

#include <metal_stdlib>
using namespace metal;

// ============================================================================
// Uniform
// ============================================================================

struct Frame {
    float2 resolution;   // 绘制目标尺寸(px)
    float2 focus;        // 焦点 [0,1],流体中心
    float2 tilt;         // 倾斜(陀螺仪/头动)[0,1]
    float4 textAspect;
    float4 color0_;
    float4 color1_;
    float4 color2_;
    float4 accent;       // 强调色(取自封面)
};

struct Params {
    float  flowAmount;    // 径向流动强度
    float  audioAmount;   // 音频驱动强度
    float  edgeSmooth;    // 边缘平滑
    float  saturation;    // 饱和度增益
    float  brightness;    // 亮度增益
    float  zoom;          // 基础放大
    float  time;          // 累积秒数
    uint   spectrumBands; // 频段数
    // 构图 —— 与 vitrine 的 SGRFluid.m 同一套参数。四张副本各自旋转、错落分布,重叠处看起来在流动。
    float  warp;          // 副本中心离可见区中点的远近,以及上三张的不透明度
    float  shadeFrom;     // 压暗带的起点(可见区高度的比例)
    float  shadeAlpha;    // 压暗带底端的黑度
    float  coverScale;    // 副本边长占可见区长边的倍数
    float2 visibleTopLeft;// 可见区在整屏里的左上角(uv),播放器不在全屏时需要
    float2 visibleSize;   // 可见区尺寸(uv)
};

/// 四张副本的边长(可见区长边的倍数)与中心(x, y),与 SGRFluid.m 的 kCopy 同一组数。
/// 顺序与那边一致,便于对照:两张顺时针、两张逆时针,速度各不相同。
inline float4 chromaCopyShape(int i) {
    // side, x, y, turn(秒;负值反向)
    if (i == 0) return float4(2.2, 0.25, 0.20, 46.0);
    if (i == 1) return float4(2.0, 0.80, 0.35, -61.0);
    if (i == 2) return float4(2.4, 0.30, 0.75, 73.0);
    return            float4(1.8, 0.70, 0.85, -54.0);
}

// A constexpr sampler is built in the device address space and may only carry addressing and
// filtering, not max_anisotropy — that one needs a MTLSamplerState made by the host. The
// functions below therefore take the sampler as a parameter, and the host passes the state it
// built in -[SGRMetalVisualiser buildPipelines].
typedef sampler SGGSampler;

// ============================================================================
// 频谱采样 — 256x2
// ============================================================================

/// 行 0 = 频段,行 1 = dB 级。相邻之间线性插值。
///
/// The spectrum is a bound texture, so it is named here rather than reached through the sampler:
/// a sampler filters and reads through one, it does not hold pixels. `texture2d<float>::sample`
/// takes the texture first, then the sampler, then the coordinate.
inline float spectrumRow(texture2d<float> spec, sampler smp, float x, int row) {
    float maxX = (row == 0) ? 127.0 : 255.0;
    float p = clamp(x, 0.0, 1.0) * maxX;
    int i = min(int(p), int(maxX) - 1);
    float4 a = spec.sample(smp, float2(float(i)     / maxX, (float)row));
    float4 b = spec.sample(smp, float2(float(i + 1) / maxX, (float)row));
    return mix(a.r, b.r, p - float(i));
}

inline float chromaSpectrum(texture2d<float> spec, sampler smp, float slot) {
    return spectrumRow(spec, smp, slot, 0);
}

inline float chromaWave(texture2d<float> spec, sampler smp, float x) {
    return spectrumRow(spec, smp, x, 1);
}

/// 整体能量,驱动画面呼吸
inline float chromaEnergy(texture2d<float> spec, sampler smp) {
    return chromaSpectrum(spec, smp, 0.06) * 0.5 + chromaSpectrum(spec, smp, 0.50) * 0.3 + chromaSpectrum(spec, smp, 0.85) * 0.2;
}

// ============================================================================
// 流体:以焦点为中心的径向扭曲
// ============================================================================

inline float2 chromaPoint(float2 uv, Frame frame) {
    float2 d = (uv - frame.focus) * frame.resolution;
    float r = 0.5 * min(frame.resolution.x, frame.resolution.y);
    return d / max(r, 1.0);
}

inline float2 chromaTurn(float2 uv, Frame frame, Params p, float energy) {
    float2 pt = chromaPoint(uv, frame);

    // 低频能量越大,中心放大越明显
    float breathe = 1.0 + p.audioAmount * energy * 0.22;

    float2 tiltDir = (frame.tilt - 0.5) * 2.0;

    // 极坐标 + 时间相位 + 径向正弦
    float r = length(pt);
    float a = atan2(pt.y, pt.x);
    float swirl = sin(r * 2.4 - p.time * 1.1 + a * 0.8) * p.flowAmount * 0.06;

    float2 rotated;
    rotated.x = pt.x * cos(swirl) - pt.y * sin(swirl);
    rotated.y = pt.x * sin(swirl) + pt.y * cos(swirl);

    rotated *= breathe;
    rotated += tiltDir * p.flowAmount * r * 0.05;

    return rotated * (0.5 * min(frame.resolution.x, frame.resolution.y))
           / frame.resolution + frame.focus;
}

// ============================================================================
// Kawase 模糊
// ============================================================================

// Kawase samples a texture, so it takes the texture and the sampler rather than a bare sampler:
// a sampler cannot read a pixel on its own.
inline float4 kawaseDown(texture2d<float> tex, sampler smp, float2 uv, float2 halfPixel) {
    float4 sum = float4(0.0);
    sum += tex.sample(smp, uv + float2(-halfPixel.x, -halfPixel.y));
    sum += tex.sample(smp, uv + float2( halfPixel.x, -halfPixel.y));
    sum += tex.sample(smp, uv + float2(-halfPixel.x,  halfPixel.y));
    sum += tex.sample(smp, uv + float2( halfPixel.x,  halfPixel.y));
    return sum * 0.25;
}

inline float4 kawaseUp(texture2d<float> tex, sampler smp, float2 uv, float2 halfPixel) {
    float2 o = halfPixel * 1.5;
    float4 sum = float4(0.0);
    sum += tex.sample(smp, uv) * 1.0;
    sum += tex.sample(smp, uv + float2(-o.x, 0.0)) * 2.0;
    sum += tex.sample(smp, uv + float2( o.x, 0.0)) * 2.0;
    sum += tex.sample(smp, uv + float2(0.0, -o.y)) * 2.0;
    sum += tex.sample(smp, uv + float2(0.0,  o.y)) * 2.0;
    return sum / 9.0;
}

// ============================================================================
// Pass 1:主渲染
// ============================================================================

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut chromaPresentVertex(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1.0, -3.0), float2(-1.0, 1.0), float2(3.0, 1.0) };
    float2 uv[3]  = { float2( 0.0,  2.0), float2( 0.0, 0.0), float2(2.0, 0.0) };
    VertexOut o;
    o.position = float4(pos[vid], 0.0, 1.0);
    o.uv = uv[vid];
    return o;
}

fragment float4 chromaPresentFragment(VertexOut in [[stage_in]],
                                      texture2d<float> coverTex    [[texture(0)]],
                                      texture2d<float> previousTex [[texture(1)]],
                                      texture2d<float> soundTex    [[texture(2)]],
                                      constant Frame&  frame       [[buffer(0)]],
                                      constant Params&  p          [[buffer(1)]],
                                      sampler           smp         [[sampler(0)]]) {
    float energy = chromaEnergy(soundTex, smp);

    float band = chromaSpectrum(soundTex, smp, in.uv.y);
    float wave = chromaWave(soundTex, smp, in.uv.x);

    // 构图与 SGRFluid.m 对齐:四张各自旋转的封面副本,边长是可见区长边的 2 倍上下,
    // 中心按 kCopy 的 (x, y) 错落;warp 决定中心离可见区中点多远(为 0 时四张重合,
    // 就是一张原地转的静态图)。副本远大于屏幕,所以大部分时候只看到其中一块。
    float2 visTL   = p.visibleTopLeft;
    float2 visSize = max(p.visibleSize, float2(1e-4));
    float2 visMid  = visTL + visSize * 0.5;
    // 可见区的长边换算到 uv ——副本的边长以它为 1。
    float  longer  = max(visSize.x, visSize.y);
    float2 aspect  = float2(visSize.x / longer, visSize.y / longer);

    float3 rgb = float3(0.0);
    float  acc = 0.0;

    for (int i = 0; i < 4; i++) {
        float4 shape = chromaCopyShape(i);
        // 第 0 张铺满,上三张的不透明度随 warp 长出来(与 SGRFluid.m 的 kOverOpacity 同思路)。
        float opacity = (i == 0) ? 1.0 : 0.7 * p.warp;
        if (opacity <= 0.001) { continue; }

        float2 centre = visMid + visSize * (shape.yz - 0.5) * p.warp;
        float  side   = longer * shape.x * p.coverScale;

        // 该副本转过的角度:一圈 shape.w 秒,方向由正负决定。
        float turns  = p.time / shape.w;
        float  angle = turns * 2.0 * 3.14159265;
        float2 rel    = in.uv - centre;
        rel = float2(rel.x / aspect.y, rel.y / aspect.x);
        float2 turned = float2(rel.x * cos(angle) - rel.y * sin(angle),
                               rel.x * sin(angle) + rel.y * cos(angle));
        float2 copyUV = turned * (longer / side) + 0.5;

        // 音频驱动的径向扰动,叠加在旋转之上。chromaTurn 带的是呼吸、倾斜与涡旋 ——
        // 拖动封面时的流动感靠它,所以保留:副本的旋转是 SGRFluid.m 的构图,径向扭曲是本实现自己的。
        float2 radial = chromaTurn(in.uv, frame, p, energy) * p.flowAmount * 0.5;
        copyUV += radial;

        // 副本比屏幕大得多,取样时绕回(镜像),和 contentsGravity = aspectFill 的效果一致。
        float2 wrapped = fract(copyUV + 0.5) - 0.5;
        float4 cover = coverTex.sample(smp, wrapped + 0.5);

        float4 base = mix(frame.color0_, frame.color1_, clamp(band * 1.2, 0.0, 1.0));
        base = mix(base, frame.color2_, clamp(wave * 0.5, 0.0, 1.0));

        float3 c = cover.rgb * mix(float3(1.0), base.rgb, 0.35);
        c = mix(c, frame.accent.rgb, p.audioAmount * band * 0.45);

        rgb += c * opacity;
        acc += opacity;
    }

    rgb = (acc > 0.0) ? rgb / acc : float3(0.0);

    float lum = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    rgb = mix(float3(lum), rgb, p.saturation);
    rgb *= p.brightness;

    // 边缘淡出
    float2 e = abs(in.uv - 0.5) * 2.0;
    float edge = 1.0 - smoothstep(0.85, 1.0, max(e.x, e.y)) * p.edgeSmooth;

    // 与上一帧混合(对应二进制的 blend pipeline)
    float3 prev = previousTex.sample(smp, in.uv).rgb;
    rgb = mix(prev, rgb, edge * 0.22 + 0.78);

    // 底部压暗带 —— SGRFluid.m 的 kShadeFrom / kShadeAlpha,盖在控制条下面让白字可读。
    // 起点按可见区的高度算,和那边一致:播放器不在全屏时压暗跟着可见区走。
    float inVisible = (in.uv.y - visTL.y) / visSize.y;
    float shade = smoothstep(p.shadeFrom, 1.0, inVisible) * p.shadeAlpha;
    rgb = mix(rgb, float3(0.0), clamp(shade, 0.0, 1.0));

    return float4(rgb, 1.0);
}

// ============================================================================
// Pass 2: Kawase 双向
// ============================================================================

struct BlurInOut {
    float4 position [[position]];
    float2 uv;
};

vertex BlurInOut blitVertex(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1.0, -3.0), float2(-1.0, 1.0), float2(3.0, 1.0) };
    float2 uv[3]  = { float2( 0.0,  2.0), float2( 0.0, 0.0), float2(2.0, 0.0) };
    BlurInOut o;
    o.position = float4(pos[vid], 0.0, 1.0);
    o.uv = uv[vid];
    return o;
}

fragment float4 kawaseDownFragment(BlurInOut in [[stage_in]],
                                   texture2d<float> src [[texture(0)]],
                                   constant float2&  srcSize [[buffer(0)]],
                                   sampler           smp   [[sampler(0)]]) {
    return kawaseDown(src, smp, in.uv, 0.5 / srcSize);
}

fragment float4 kawaseUpFragment(BlurInOut in [[stage_in]],
                                 texture2d<float> src [[texture(0)]],
                                 constant float2&  srcSize [[buffer(0)]],
                                 sampler           smp   [[sampler(0)]]) {
    return kawaseUp(src, smp, in.uv, 0.5 / srcSize);
}

// ============================================================================
// Pass 3: 最终合成 + 歌词
// ============================================================================

fragment float4 compositeFragment(BlurInOut in [[stage_in]],
                                  texture2d<float> blurred [[texture(0)]],
                                  texture2d<float> textTex [[texture(1)]],
                                  texture2d<float> soundTex [[texture(2)]],
                                  constant Frame&  frame [[buffer(0)]],
                                  constant Params& p     [[buffer(1)]],
                                  sampler           smp   [[sampler(0)]]) {
    float3 bg = blurred.sample(smp, in.uv).rgb;

    // 歌词直接进 GPU,所以能随节拍发光
    float2 tuv = in.uv;
    tuv.y = 1.0 - tuv.y;
    float4 txt = textTex.sample(smp, tuv);

    float band = chromaSpectrum(soundTex, smp, tuv.y);
    float glow = txt.a * (0.55 + band * p.audioAmount * 0.9);

    float3 outRGB = bg;
    float region = smoothstep(0.05, 0.35, in.uv.y) * (1.0 - smoothstep(0.72, 0.98, in.uv.y));
    outRGB = mix(outRGB, outRGB * 0.42, region * 0.75);

    outRGB += frame.accent.rgb * glow * 0.55;
    outRGB += float3(glow) * glow * 0.35;

    return float4(outRGB, 1.0);
}
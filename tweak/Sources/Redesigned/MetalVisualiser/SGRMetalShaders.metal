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

// 封面模糊半径的上限,以封面纹理的比例计(0..1 的 uv)。vitrine 是在 128px 的封面上用
// 10px 的高斯半径 —— 纹理的 7.8% —— 所以 0.08 是它的等价。比这更小的半径在画面上
// 就只是柔化,而不是"模糊的背景"。
constant float kTextureBlurRadius = 0.08;

// ---------------------------------------------------------------------------
// 锁屏那幅画的构图(SGFluidClip.m)。播放页的动态封面照它来。
// ---------------------------------------------------------------------------
// 每张副本绕静止角左右的摆幅(弧度),以及中心绕小圆的漂移(clip 宽/高的比例)。
constant float kCopySway = 0.35, kCopyDrift = 0.06;
// SGFluidClip.m 的 kLoopSeconds:摆动八秒跑完一圈,位置和角度完全复原,所以循环没有接缝。
constant float kLoopSeconds = 8.0;
// clip 是 3:4(宽 = 高 × 0.75)。锁屏把它铺满屏幕、两侧裁掉,所以 kCopy 的比例相对的是这块
// 比屏幕宽的画布 —— 在可见区里算,位置会和锁屏差一截。
constant float kClipAspect = 0.75;
// 封面本身:边长占 clip 宽的 kCoverSide(0.5,由 SGLockScreenCoverArtworkScale 传进来),
// 中心在 clip 高度的 45%,圆角 0.035×边长,阴影偏移 0.02×边长、模糊 0.08×边长、黑 50%。
constant float kArtCenterY = 0.45, kArtCorner = 0.035;
constant float kArtShadowBlur = 0.08, kArtShadowOffset = 0.02, kArtShadowAlpha = 0.5;
// 封面自己压掉的亮度:SGRFluid.m 和 SGFluidClip.m 都在模糊之后用 CIColorControls 减 0.08,
// 两套都这么做,所以这不是哪一套的特征,是封面该有的色调。
constant float kCoverBrightness = -0.08;

/// 圆角矩形的有符号距离:小于 0 在内部。SD 取绝对值的一半边长再退掉圆角。
inline float chromaRoundRect(float2 p, float halfSide, float radius) {
    float2 d = abs(p) - halfSide + radius;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

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
    float  edgeSmooth;    // 边缘淡出强度
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
    float  blurAmount;    // 0 = 清晰封面,1 = SGRFluid.m 那样的全糊
    // 封面本身画进画面时,它的边长占 clip 宽度的比例(SGLockScreenCoverArtworkScale,默认 0.5)。
    float  coverArtScale;
};

/// 四张副本的静止角与不透明度 —— SGFluidClip.m 的 kCopy 比 SGRFluid.m 多这两个字段,
/// 前三个(side / x / y)两个文件是同一组数,所以这里只补这两个。
inline float2 chromaCopyRest(int i) {
    // opacity, angle(弧度)
    if (i == 0) return float2(1.0, 0.0);
    if (i == 1) return float2(0.7, 1.1);
    if (i == 2) return float2(0.7, 2.3);
    return            float2(0.7, 4.0);
}

/// 四张副本的边长(可见区长边的倍数)与中心(x, y)。SGRFluid.m 的 kCopy 与 SGFluidClip.m 的
/// kCopy 前三个字段是同一组数 —— 后者多一个静止角和一个不透明度,在 chromaCopyRest 里。
/// 顺序与两个文件一致,便于对照。
inline float3 chromaCopyShape(int i) {
    // side, x, y
    if (i == 0) return float3(2.2, 0.25, 0.20);
    if (i == 1) return float3(2.0, 0.80, 0.35);
    if (i == 2) return float3(2.4, 0.30, 0.75);
    return            float3(1.8, 0.70, 0.85);
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
                                      texture2d<float> textTex     [[texture(3)]],
                                      constant Frame&  frame       [[buffer(0)]],
                                      constant Params&  p          [[buffer(1)]],
                                      sampler           smp         [[sampler(0)]]) {
    float energy = chromaEnergy(soundTex, smp);

    float band = chromaSpectrum(soundTex, smp, in.uv.y);
    float wave = chromaWave(soundTex, smp, in.uv.x);

    // 构图照**锁屏**那幅画来(SGFluidClip.m),不是照播放页的 SGRFluid.m —— 两者是两套设计:
    //
    //   SGRFluid.m     副本连续旋转(一圈 46~73 秒),上三张不透明度随 Warp,压暗 0.45/0.55,
    //                  不画封面(播放页那个方形封面是 Spotify 自己的)。
    //   SGFluidClip.m  副本只**摆动** ±0.35 弧度,停在各自的静止角(0 / 1.1 / 2.3 / 4.0),
    //                  不透明度固定 1.0 / 0.7 / 0.7 / 0.7,中心各绕一个小圆漂移(kDrift 0.06,
    //                  每张错开四分之一圈),压暗 0.55/0.45,而且**把封面本身画在画面中心**。
    //
    // 坐标空间也不同。锁屏的 clip 是 3:4,系统把它铺满屏幕、两侧裁掉,所以 kCopy 的比例是相对
    // 那块**比屏幕宽**的画布的;在可见区(屏幕)里算,位置就对不上。这里按 clip 来:高度取可见高,
    // 宽度 = 高度 × 0.75,水平居中,超出屏幕的部分正好被裁掉 —— 和锁屏看到的构图一致。
    float2 visTL   = p.visibleTopLeft;
    float2 visSize = max(p.visibleSize, float2(1e-4));
    float2 visMid  = visTL + visSize * 0.5;

    float2 px    = in.uv * frame.resolution;                   // 当前像素
    float2 midPx = visMid * frame.resolution;

    float  clipH   = visSize.y * frame.resolution.y;           // clip 高 = 可见高(系统按高铺满)
    float  clipW   = clipH * kClipAspect;                      // 3:4 → 宽 = 高 × 0.75,比屏幕宽
    float2 clipTL  = float2(midPx.x - clipW * 0.5, visTL.y * frame.resolution.y);
    float  longerPx = max(clipW, clipH);                       // SGFluidClip.m 的 longer

    float3 rgb = float3(0.0);
    float  acc = 0.0;

    for (int i = 0; i < 4; i++) {
        float3 shape = chromaCopyShape(i);      // side, x, y —— 两个文件是同一组数
        float2 rest  = chromaCopyRest(i);       // 不透明度, 静止角
        float  opacity = rest.x;
        if (opacity <= 0.001) { continue; }

        // 摆动相位:八秒一圈,每张错开四分之一圈,所以四张不会同步。
        float turn = 2.0 * 3.14159265 * (p.time / kLoopSeconds) + i * 1.5707963268;

        // 位置:clip 里的 kCopy 比例,再加绕一个小圆的漂移(kDrift)。
        // warp 只缩放「离中点多远」:为 1 时与 SGFluidClip.m 逐字相同,为 0 时四张重合。
        float2 centreShare = float2(shape.y, shape.z) + kCopyDrift * float2(cos(turn), sin(turn));
        float2 centrePx = clipTL + float2(clipW, clipH) * (0.5 + (centreShare - 0.5) * p.warp);
        // 尺寸:clip 长边 × kCopy 的边长比例 × coverScale(为 1 时与锁屏相同)。
        float  sidePx   = longerPx * shape.x * p.coverScale;

        // 只摆动,不连转:停在各自的静止角上,左右各摆 kCopySway,方向逐张交替。
        float  angle = rest.y + (i % 2 ? -kCopySway : kCopySway) * sin(turn);
        float2 rel    = px - centrePx;
        float2 turned = float2(rel.x * cos(angle) - rel.y * sin(angle),
                               rel.x * sin(angle) + rel.y * cos(angle));
        // 正方形副本:像素偏移按边长归一化,加半边得到 0..1 的取样坐标。
        float2 copyUV = turned / sidePx + 0.5;

        // 音频驱动的径向扰动,叠加在旋转之上。用 chromaPoint:它是纯偏移(相对焦点的
        // 像素距离 / 半长边),而任何返回完整 uv 的函数当偏移用会让画面跟着 focus 漂移。
        // 低频能量越大推得越远。
        float2 radial = chromaPoint(in.uv, frame) * p.flowAmount * (0.35 + energy * 0.65)
                      / max(longerPx, 1.0);
        copyUV += radial;

        // 取样坐标以副本中心为 0.5。副本远大于屏幕,所以大部分点落在 0..1 之外 ——
        // clamp 到边缘,和 aspectFill 一样:封面被拉大铺满正方形副本,副本露在屏幕外的
        // 那部分只是这个副本自己的画面。
        float4 cover = coverTex.sample(smp, clamp(copyUV, 0.0, 1.0));

        // 模糊在这里做,半径以**封面纹理的比例**计,不是屏幕像素 —— 这是"看起来像模糊"
        // 与"看起来像被放大的封面"之间的全部差别。
        //
        // vitrine 把封面缩到 128px,再用 10px 半径的高斯,即纹理的 ~7.8%;这边的 copyUV 是
        // 0..1 的方形纹理坐标,同样的比例就是 0.078 uv。早先用的是 1/resolution,在 1024px
        // 的纹理上只有 0.8 个像素 —— 等于没糊,于是"副本是屏幕的 2.2 倍、只显示封面中间
        // 45%"这件事就直接暴露成了"封面被放大"。
        //
        // 采样点固定,不随分辨率变:半径是封面自己的尺度,与屏幕多大无关。
        float rad = max(p.blurAmount, 0.02) * kTextureBlurRadius;
        float2 px1 = float2(rad, rad);
        float3 blurred = cover.rgb * 0.20;
        blurred += coverTex.sample(smp, clamp(copyUV + float2( px1.x,  0.0), 0.0, 1.0)).rgb * 0.10;
        blurred += coverTex.sample(smp, clamp(copyUV + float2(-px1.x,  0.0), 0.0, 1.0)).rgb * 0.10;
        blurred += coverTex.sample(smp, clamp(copyUV + float2( 0.0,  px1.y), 0.0, 1.0)).rgb * 0.10;
        blurred += coverTex.sample(smp, clamp(copyUV + float2( 0.0, -px1.y), 0.0, 1.0)).rgb * 0.10;
        blurred += coverTex.sample(smp, clamp(copyUV + px1, 0.0, 1.0)).rgb * 0.0675;
        blurred += coverTex.sample(smp, clamp(copyUV - px1, 0.0, 1.0)).rgb * 0.0675;
        blurred += coverTex.sample(smp, clamp(copyUV + float2( px1.x, -px1.y), 0.0, 1.0)).rgb * 0.0675;
        blurred += coverTex.sample(smp, clamp(copyUV + float2(-px1.x,  px1.y), 0.0, 1.0)).rgb * 0.0675;
        blurred += coverTex.sample(smp, clamp(copyUV + float2( px1.x,  px1.y), 0.0, 1.0)).rgb * 0.0675;
        blurred += coverTex.sample(smp, clamp(copyUV + float2(-px1.x, -px1.y), 0.0, 1.0)).rgb * 0.0675;
        blurred += coverTex.sample(smp, clamp(copyUV + float2( px1.x * 2.0, 0.0), 0.0, 1.0)).rgb * 0.035;
        blurred += coverTex.sample(smp, clamp(copyUV + float2(-px1.x * 2.0, 0.0), 0.0, 1.0)).rgb * 0.035;
        blurred += coverTex.sample(smp, clamp(copyUV + float2( 0.0,  px1.y * 2.0), 0.0, 1.0)).rgb * 0.035;
        blurred += coverTex.sample(smp, clamp(copyUV + float2( 0.0, -px1.y * 2.0), 0.0, 1.0)).rgb * 0.035;
        // 三步归一化:上面权重和为 0.2+0.4+0.405+0.14 = 1.145,除回来保持亮度。
        blurred /= 1.145;

        float4 base = mix(frame.color0_, frame.color1_, clamp(band * 1.2, 0.0, 1.0));
        base = mix(base, frame.color2_, clamp(wave * 0.5, 0.0, 1.0));

        // blur 的强度:0 是清晰的封面,1 是 SGRFluid.m 那样的全糊。
        float3 c = mix(cover.rgb, blurred, p.blurAmount);
        c *= mix(float3(1.0), base.rgb, 0.35);
        c = mix(c, frame.accent.rgb, p.audioAmount * band * 0.45);

        // 层叠而非平均:SGRFluid.m 里四张是四个 CALayer,后画的盖在先画的上面,
        // 只有自己的 opacity 参与混合。累加再除以总权重会把四张都摊平 —— 重叠处
        // 本该是上层那张的颜色,而不是四张的平均。
        if (i == 0) {
            rgb = c;
            acc = 1.0;
        } else {
            float a = clamp(opacity, 0.0, 1.0);
            rgb = mix(rgb, c, a);
            acc = mix(acc, 1.0, a);
        }
    }

    if (acc <= 0.0) { rgb = float3(0.0); }

    float lum = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    rgb = mix(float3(lum), rgb, p.saturation);
    // 先后与 CIColorControls 一致:饱和度之后减亮度,滑块的增益再乘上去(默认 100 → ×1)。
    rgb += kCoverBrightness;
    rgb *= p.brightness;

    // 边缘淡出
    float2 e = abs(in.uv - 0.5) * 2.0;
    float edge = 1.0 - smoothstep(0.85, 1.0, max(e.x, e.y)) * p.edgeSmooth;

    // 与上一帧混合(对应二进制的 blend pipeline)
    float3 prev = previousTex.sample(smp, in.uv).rgb;
    rgb = mix(prev, rgb, edge * 0.22 + 0.78);

    // 底部压暗带。值取锁屏那套(SGFluidClip.m 的 kShadeFrom 0.55 / kShadeAlpha 0.45),
    // 不是播放页 SGRFluid.m 的 0.45/0.55 —— 两边压暗的起点和深度本来就不同。
    float inVisible = (in.uv.y - visTL.y) / visSize.y;
    float shade = smoothstep(p.shadeFrom, 1.0, inVisible) * p.shadeAlpha;
    rgb = mix(rgb, float3(0.0), clamp(shade, 0.0, 1.0));

    // 封面本身 —— 锁屏那幅画的中心,也是「动态封面」指的东西。SGRFluid.m 不画它(播放页那个方形
    // 封面是 Spotify 自己的),SGFluidClip.m 画,而位置、大小、圆角、阴影就是 coverFrame / newCover
    // 那一组数:边长 = clip 宽的 kCoverSide,水平居中,中心在 clip 高度的 45%。
    // 用 clip 宽而不是可见宽来算,屏幕上看到的比例才和锁屏一致。
    float  artSide = clipW * p.coverArtScale;
    float2 artMid  = float2(clipTL.x + clipW * 0.5, clipTL.y + clipH * kArtCenterY);
    float2 artRel  = px - artMid;
    float  artHalf = artSide * 0.5;
    float  artCornerPx = artSide * kArtCorner;

    // 阴影:模糊 0.08×边长,向下偏 0.02×边长,黑 50%(newCover 的 CGContextSetShadowWithColor)。
    float  shadowEdge = max(artSide * kArtShadowBlur, 1.0);
    float  sdShadow = chromaRoundRect(artRel - float2(0.0, artSide * kArtShadowOffset), artHalf, artCornerPx);
    float  shadowA = clamp(0.5 - sdShadow / (2.0 * shadowEdge), 0.0, 1.0) * kArtShadowAlpha;
    rgb = mix(rgb, float3(0.0), shadowA);

    // 封面本体,清晰的。纹理在 ObjC 侧已经 aspectFill 进正方形,所以正方形坐标直接取样。
    float  sdArt   = chromaRoundRect(artRel, artHalf, artCornerPx);
    float  artMask = clamp(0.5 - sdArt / 1.5, 0.0, 1.0);
    float4 art = coverTex.sample(smp, clamp(artRel / max(artSide, 1.0) + 0.5, 0.0, 1.0));
    rgb = mix(rgb, art.rgb, artMask);

    // 歌词叠上来。合成也曾是独立的一 pass,但那时主渲染写进的是 512px 的中转纹理;
    // 现在主渲染直接写屏幕,歌词就在同一个 fragment 里叠,少一遍全屏带宽。
    float2 tuv = in.uv;
    tuv.y = 1.0 - tuv.y;
    float4 txt = textTex.sample(smp, tuv);
    if (txt.a > 0.0) {
        // 歌词所在的那段压暗一点,和白字拉开对比 —— 和原来 compositeFragment 里那步一样。
        float region = smoothstep(0.05, 0.35, in.uv.y) * (1.0 - smoothstep(0.72, 0.98, in.uv.y));
        rgb = mix(rgb, rgb * 0.42, region * 0.75);
        // 随节拍发光:这正是歌词走 GPU 而不是 UILabel 的原因。
        float glow = txt.a * (0.55 + band * p.audioAmount * 0.9);
        rgb += frame.accent.rgb * glow * 0.55;
        rgb += float3(glow) * glow * 0.35;
    }

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
    // 已并入 chromaPresentFragment:主渲染现在直接写 drawable,不再经由 512px 的中转纹理
    // (那会把封面放大五倍,只看得见中间一块)。歌词也在那一个 fragment 里叠上去,
    // 所以这里保留一个恒黑的结果,万一还有调用者也不会画出错误的东西。
    return float4(0.0, 0.0, 0.0, 1.0);
}
// Official QQ Music: word-timed QRC and line-timed LRC from QQ Music's public musicu interface
// (u.y.qq.com/cgi-bin/musicu.fcg). The QRC payload is triple-DES encrypted with a nonstandard
// operation and zlib-compressed; SGQQQRCDecrypt (ported from WXRIW/QQMusicDecoder, MIT) reverses
// the cipher and zlib inflates it. Parsing, cleaning and matching ride on SpotifyGlass's shared
// karaoke helpers so the lines match every other source — this is the project's second QQ Music
// source, registered under the "qqmusic" key; the original third-party (落月 / api.vkeys.cn) source
// lives in Luoyue.m under the "luoyue" key.
//
// QQ Music keeps its songs behind their own ids, so a track is searched for by title and lead
// artist (the closest recording by singer, within a few seconds of the track length, is taken), and
// the lyric endpoint answers qrc (word timing), lrc (line timing), trans (a Chinese LRC sheet) and
// roma (a romanisation, itself QRC). The translation is applied when Chinese (or Any) is asked for.
#import "Core/SGCore.h"
#import "LyricsSources.h"
#import <stdint.h>
#import <string.h>
#import <zlib.h>

#pragma mark - QRC decoder (WXRIW/QQMusicDecoder DESHelper.cs, MIT, Copyright (c) 2023 WXRIW)

// QQ Music QRC uses a DES variant; platform TripleDES does not decode its payload.
// Original project: https://github.com/WXRIW/QQMusicDecoder
void SGQQQRCDecrypt(const uint8_t *input, size_t length, uint8_t *output);

typedef uint32_t uint;
typedef uint8_t byte;
enum { ENCRYPT = 1, DECRYPT = 0 };

static uint BITNUM(const byte *a, int b, int c)
{
    return (uint)((a[(b) / 32 * 4 + 3 - (b) % 32 / 8] >> (7 - (b % 8))) & 0x01) << (c);
}

static byte BITNUMINTR(uint a, int b, int c)
{
    return (byte)((((a) >> (31 - (b))) & 0x00000001) << (c));
}

static uint BITNUMINTL(uint a, int b, int c)
{
    return ((((a) << (b)) & 0x80000000) >> (c));
}

static uint SBOXBIT(byte a)
{
    return (uint)(((a) & 0x20) | (((a) & 0x1f) >> 1) | (((a) & 0x01) << 4));
}

static const byte sbox1[64] = {
    14,  4, 13,  1,   2, 15,  11,  8,   3, 10,   6, 12,   5,  9,   0,  7,
     0, 15,  7,  4,  14,  2,  13,  1,  10,  6,  12, 11,   9,  5,   3,  8,
     4,  1, 14,  8,  13,  6,   2, 11,  15, 12,   9,  7,   3, 10,   5,  0,
    15, 12,  8,  2,   4,  9,   1,  7,   5, 11,   3, 14,  10,  0,   6, 13
};

static const byte sbox2[64] = {
    15,  1,  8, 14,   6, 11,   3,  4,   9,  7,   2, 13,  12,  0,   5, 10,
     3, 13,  4,  7,  15,  2,   8, 15,  12,  0,   1, 10,   6,  9,  11,  5,
     0, 14,  7, 11,  10,  4,  13,  1,   5,  8,  12,  6,   9,  3,   2, 15,
    13,  8, 10,  1,   3, 15,   4,  2,  11,  6,   7, 12,   0,  5,  14,  9
};

static const byte sbox3[64] = {
    10,  0,  9, 14,   6,  3,  15,  5,   1, 13,  12,  7,  11,  4,   2,  8,
    13,  7,  0,  9,   3,  4,   6, 10,   2,  8,   5, 14,  12, 11,  15,  1,
    13,  6,  4,  9,   8, 15,   3,  0,  11,  1,   2, 12,   5, 10,  14,  7,
     1, 10, 13,  0,   6,  9,   8,  7,   4, 15,  14,  3,  11,  5,   2, 12
};

static const byte sbox4[64] = {
     7, 13, 14,  3,   0,  6,   9, 10,   1,  2,   8,  5,  11, 12,   4, 15,
    13,  8, 11,  5,   6, 15,   0,  3,   4,  7,   2, 12,   1, 10,  14,  9,
    10,  6,  9,  0,  12, 11,   7, 13,  15,  1,   3, 14,   5,  2,   8,  4,
     3, 15,  0,  6,  10, 10,  13,  8,   9,  4,   5, 11,  12,  7,   2, 14
};

static const byte sbox5[64] = {
     2, 12,  4,  1,   7, 10,  11,  6,   8,  5,   3, 15,  13,  0,  14,  9,
    14, 11,  2, 12,   4,  7,  13,  1,   5,  0,  15, 10,   3,  9,   8,  6,
     4,  2,  1, 11,  10, 13,   7,  8,  15,  9,  12,  5,   6,  3,   0, 14,
    11,  8, 12,  7,   1, 14,   2, 13,   6, 15,   0,  9,  10,  4,   5,  3
};

static const byte sbox6[64] = {
    12,  1, 10, 15,   9,  2,   6,  8,   0, 13,   3,  4,  14,  7,   5, 11,
    10, 15,  4,  2,   7, 12,   9,  5,   6,  1,  13, 14,   0, 11,   3,  8,
     9, 14, 15,  5,   2,  8,  12,  3,   7,  0,   4, 10,   1, 13,  11,  6,
     4,  3,  2, 12,   9,  5,  15, 10,  11, 14,   1,  7,   6,  0,   8, 13
};

static const byte sbox7[64] = {
     4, 11,  2, 14, 15,  0,   8, 13,   3, 12,   9,  7,   5, 10,   6,  1,
    13,  0, 11,  7,   4,  9,   1, 10,  14,  3,   5, 12,   2, 15,   8,  6,
     1,  4, 11, 13,  12,  3,   7, 14,  10, 15,   6,  8,   0,  5,   9,  2,
     6, 11, 13,  8,   1,  4,  10,  7,   9,  5,   0, 15,  14,  2,   3, 12
};

static const byte sbox8[64] = {
    13,  2,  8,  4,   6, 15,  11,  1,  10,  9,   3, 14,   5,  0,  12,  7,
     1, 15, 13,  8,  10,  3,   7,  4,  12,  5,   6, 11,   0, 14,   9,  2,
     7, 11,  4,  1,   9, 12,  14,  2,   0,  6,  10, 13,  15,  3,   5,  8,
     2,  1, 14,  7,   4, 10,   8, 13,  15, 12,   9,  0,   3,  5,   6, 11
};

static void KeySchedule(const byte *key, byte schedule[16][6], uint mode)
{
    uint i, j, toGen, C, D;
    const uint key_rnd_shift[] = { 1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1 };
    const uint key_perm_c[] = { 56, 48, 40, 32, 24, 16, 8, 0, 57, 49, 41, 33, 25, 17,
        9,1,58,50,42,34,26,18,10,2,59,51,43,35 };
    const uint key_perm_d[] = { 62,54,46,38,30,22,14,6,61,53,45,37,29,21,
        13,5,60,52,44,36,28,20,12,4,27,19,11,3 };
    const uint key_compression[] = { 13,16,10,23,0,4,2,27,14,5,20,9,
        22,18,11,3,25,7,15,6,26,19,12,1,
        40,51,30,36,46,54,29,39,50,44,32,47,
        43,48,38,55,33,52,45,41,49,35,28,31 };

    for (i = 0, j = 31, C = 0; i < 28; ++i, --j)
        C |= BITNUM(key, (int)key_perm_c[i], (int)j);

    for (i = 0, j = 31, D = 0; i < 28; ++i, --j)
        D |= BITNUM(key, (int)key_perm_d[i], (int)j);

    for (i = 0; i < 16; ++i)
    {
        C = ((C << (int)key_rnd_shift[i]) | (C >> (28 - (int)key_rnd_shift[i]))) & 0xfffffff0;
        D = ((D << (int)key_rnd_shift[i]) | (D >> (28 - (int)key_rnd_shift[i]))) & 0xfffffff0;

        if (mode == DECRYPT)
            toGen = 15 - i;
        else
            toGen = i;

        for (j = 0; j < 6; ++j)
            schedule[toGen][j] = 0;

        for (j = 0; j < 24; ++j)
            schedule[toGen][j / 8] |= BITNUMINTR(C, (int)key_compression[j], (int)(7 - (j % 8)));

        for (; j < 48; ++j)
            schedule[toGen][j / 8] |= BITNUMINTR(D, (int)key_compression[j] - 27, (int)(7 - (j % 8)));
    }
}

static void IP(uint state[2], const byte input[8])
{
    state[0] = BITNUM(input, 57, 31) | BITNUM(input, 49, 30) | BITNUM(input, 41, 29) | BITNUM(input, 33, 28) |
        BITNUM(input, 25, 27) | BITNUM(input, 17, 26) | BITNUM(input, 9, 25) | BITNUM(input, 1, 24) |
        BITNUM(input, 59, 23) | BITNUM(input, 51, 22) | BITNUM(input, 43, 21) | BITNUM(input, 35, 20) |
        BITNUM(input, 27, 19) | BITNUM(input, 19, 18) | BITNUM(input, 11, 17) | BITNUM(input, 3, 16) |
        BITNUM(input, 61, 15) | BITNUM(input, 53, 14) | BITNUM(input, 45, 13) | BITNUM(input, 37, 12) |
        BITNUM(input, 29, 11) | BITNUM(input, 21, 10) | BITNUM(input, 13, 9) | BITNUM(input, 5, 8) |
        BITNUM(input, 63, 7) | BITNUM(input, 55, 6) | BITNUM(input, 47, 5) | BITNUM(input, 39, 4) |
        BITNUM(input, 31, 3) | BITNUM(input, 23, 2) | BITNUM(input, 15, 1) | BITNUM(input, 7, 0);

    state[1] = BITNUM(input, 56, 31) | BITNUM(input, 48, 30) | BITNUM(input, 40, 29) | BITNUM(input, 32, 28) |
        BITNUM(input, 24, 27) | BITNUM(input, 16, 26) | BITNUM(input, 8, 25) | BITNUM(input, 0, 24) |
        BITNUM(input, 58, 23) | BITNUM(input, 50, 22) | BITNUM(input, 42, 21) | BITNUM(input, 34, 20) |
        BITNUM(input, 26, 19) | BITNUM(input, 18, 18) | BITNUM(input, 10, 17) | BITNUM(input, 2, 16) |
        BITNUM(input, 60, 15) | BITNUM(input, 52, 14) | BITNUM(input, 44, 13) | BITNUM(input, 36, 12) |
        BITNUM(input, 28, 11) | BITNUM(input, 20, 10) | BITNUM(input, 12, 9) | BITNUM(input, 4, 8) |
        BITNUM(input, 62, 7) | BITNUM(input, 54, 6) | BITNUM(input, 46, 5) | BITNUM(input, 38, 4) |
        BITNUM(input, 30, 3) | BITNUM(input, 22, 2) | BITNUM(input, 14, 1) | BITNUM(input, 6, 0);
}

static void InvIP(uint state[2], byte input[8])
{
    input[3] = (byte)(BITNUMINTR(state[1], 7, 7) | BITNUMINTR(state[0], 7, 6) | BITNUMINTR(state[1], 15, 5) |
        BITNUMINTR(state[0], 15, 4) | BITNUMINTR(state[1], 23, 3) | BITNUMINTR(state[0], 23, 2) |
        BITNUMINTR(state[1], 31, 1) | BITNUMINTR(state[0], 31, 0));

    input[2] = (byte)(BITNUMINTR(state[1], 6, 7) | BITNUMINTR(state[0], 6, 6) | BITNUMINTR(state[1], 14, 5) |
        BITNUMINTR(state[0], 14, 4) | BITNUMINTR(state[1], 22, 3) | BITNUMINTR(state[0], 22, 2) |
        BITNUMINTR(state[1], 30, 1) | BITNUMINTR(state[0], 30, 0));

    input[1] = (byte)(BITNUMINTR(state[1], 5, 7) | BITNUMINTR(state[0], 5, 6) | BITNUMINTR(state[1], 13, 5) |
        BITNUMINTR(state[0], 13, 4) | BITNUMINTR(state[1], 21, 3) | BITNUMINTR(state[0], 21, 2) |
        BITNUMINTR(state[1], 29, 1) | BITNUMINTR(state[0], 29, 0));

    input[0] = (byte)(BITNUMINTR(state[1], 4, 7) | BITNUMINTR(state[0], 4, 6) | BITNUMINTR(state[1], 12, 5) |
        BITNUMINTR(state[0], 12, 4) | BITNUMINTR(state[1], 20, 3) | BITNUMINTR(state[0], 20, 2) |
        BITNUMINTR(state[1], 28, 1) | BITNUMINTR(state[0], 28, 0));

    input[7] = (byte)(BITNUMINTR(state[1], 3, 7) | BITNUMINTR(state[0], 3, 6) | BITNUMINTR(state[1], 11, 5) |
        BITNUMINTR(state[0], 11, 4) | BITNUMINTR(state[1], 19, 3) | BITNUMINTR(state[0], 19, 2) |
        BITNUMINTR(state[1], 27, 1) | BITNUMINTR(state[0], 27, 0));

    input[6] = (byte)(BITNUMINTR(state[1], 2, 7) | BITNUMINTR(state[0], 2, 6) | BITNUMINTR(state[1], 10, 5) |
        BITNUMINTR(state[0], 10, 4) | BITNUMINTR(state[1], 18, 3) | BITNUMINTR(state[0], 18, 2) |
        BITNUMINTR(state[1], 26, 1) | BITNUMINTR(state[0], 26, 0));

    input[5] = (byte)(BITNUMINTR(state[1], 1, 7) | BITNUMINTR(state[0], 1, 6) | BITNUMINTR(state[1], 9, 5) |
        BITNUMINTR(state[0], 9, 4) | BITNUMINTR(state[1], 17, 3) | BITNUMINTR(state[0], 17, 2) |
        BITNUMINTR(state[1], 25, 1) | BITNUMINTR(state[0], 25, 0));

    input[4] = (byte)(BITNUMINTR(state[1], 0, 7) | BITNUMINTR(state[0], 0, 6) | BITNUMINTR(state[1], 8, 5) |
        BITNUMINTR(state[0], 8, 4) | BITNUMINTR(state[1], 16, 3) | BITNUMINTR(state[0], 16, 2) |
        BITNUMINTR(state[1], 24, 1) | BITNUMINTR(state[0], 24, 0));
}

static uint F(uint state, const byte key[6])
{
    byte lrgstate[6] = {0};
    uint t1, t2;

    t1 = BITNUMINTL(state, 31, 0) | ((state & 0xf0000000) >> 1) | BITNUMINTL(state, 4, 5) |
        BITNUMINTL(state, 3, 6) | ((state & 0x0f000000) >> 3) | BITNUMINTL(state, 8, 11) |
        BITNUMINTL(state, 7, 12) | ((state & 0x00f00000) >> 5) | BITNUMINTL(state, 12, 17) |
        BITNUMINTL(state, 11, 18) | ((state & 0x000f0000) >> 7) | BITNUMINTL(state, 16, 23);

    t2 = BITNUMINTL(state, 15, 0) | ((state & 0x0000f000) << 15) | BITNUMINTL(state, 20, 5) |
        BITNUMINTL(state, 19, 6) | ((state & 0x00000f00) << 13) | BITNUMINTL(state, 24, 11) |
        BITNUMINTL(state, 23, 12) | ((state & 0x000000f0) << 11) | BITNUMINTL(state, 28, 17) |
        BITNUMINTL(state, 27, 18) | ((state & 0x0000000f) << 9) | BITNUMINTL(state, 0, 23);

    lrgstate[0] = (byte)((t1 >> 24) & 0x000000ff);
    lrgstate[1] = (byte)((t1 >> 16) & 0x000000ff);
    lrgstate[2] = (byte)((t1 >> 8) & 0x000000ff);
    lrgstate[3] = (byte)((t2 >> 24) & 0x000000ff);
    lrgstate[4] = (byte)((t2 >> 16) & 0x000000ff);
    lrgstate[5] = (byte)((t2 >> 8) & 0x000000ff);

    lrgstate[0] ^= key[0];
    lrgstate[1] ^= key[1];
    lrgstate[2] ^= key[2];
    lrgstate[3] ^= key[3];
    lrgstate[4] ^= key[4];
    lrgstate[5] ^= key[5];

    state = (uint)((sbox1[SBOXBIT((byte)(lrgstate[0] >> 2))] << 28) |
        (sbox2[SBOXBIT((byte)(((lrgstate[0] & 0x03) << 4) | (lrgstate[1] >> 4)))] << 24) |
        (sbox3[SBOXBIT((byte)(((lrgstate[1] & 0x0f) << 2) | (lrgstate[2] >> 6)))] << 20) |
        (sbox4[SBOXBIT((byte)(lrgstate[2] & 0x3f))] << 16) |
        (sbox5[SBOXBIT((byte)(lrgstate[3] >> 2))] << 12) |
        (sbox6[SBOXBIT((byte)(((lrgstate[3] & 0x03) << 4) | (lrgstate[4] >> 4)))] << 8) |
        (sbox7[SBOXBIT((byte)(((lrgstate[4] & 0x0f) << 2) | (lrgstate[5] >> 6)))] << 4) |
        sbox8[SBOXBIT((byte)(lrgstate[5] & 0x3f))]);

    state = BITNUMINTL(state, 15, 0) | BITNUMINTL(state, 6, 1) | BITNUMINTL(state, 19, 2) |
        BITNUMINTL(state, 20, 3) | BITNUMINTL(state, 28, 4) | BITNUMINTL(state, 11, 5) |
        BITNUMINTL(state, 27, 6) | BITNUMINTL(state, 16, 7) | BITNUMINTL(state, 0, 8) |
        BITNUMINTL(state, 14, 9) | BITNUMINTL(state, 22, 10) | BITNUMINTL(state, 25, 11) |
        BITNUMINTL(state, 4, 12) | BITNUMINTL(state, 17, 13) | BITNUMINTL(state, 30, 14) |
        BITNUMINTL(state, 9, 15) | BITNUMINTL(state, 1, 16) | BITNUMINTL(state, 7, 17) |
        BITNUMINTL(state, 23, 18) | BITNUMINTL(state, 13, 19) | BITNUMINTL(state, 31, 20) |
        BITNUMINTL(state, 26, 21) | BITNUMINTL(state, 2, 22) | BITNUMINTL(state, 8, 23) |
        BITNUMINTL(state, 18, 24) | BITNUMINTL(state, 12, 25) | BITNUMINTL(state, 29, 26) |
        BITNUMINTL(state, 5, 27) | BITNUMINTL(state, 21, 28) | BITNUMINTL(state, 10, 29) |
        BITNUMINTL(state, 3, 30) | BITNUMINTL(state, 24, 31);

    return (state);
}

static void Crypt(const byte input[8], byte output[8], byte key[16][6])
{
    uint state[2] = {0};
    uint idx, t;

    IP(state, input);

    for (idx = 0; idx < 15; ++idx)
    {
        t = state[1];
        state[1] = F(state[1], key[idx]) ^ state[0];
        state[0] = t;
    }

    state[0] = F(state[1], key[15]) ^ state[0];

    InvIP(state, output);
}
static void TripleDESKeySetup(const byte *key, byte schedule[3][16][6], uint mode)
{
    if (mode == ENCRYPT)
    {
        KeySchedule(key, schedule[0], mode);
        KeySchedule(key + 8, schedule[1], DECRYPT);
        KeySchedule(key + 16, schedule[2], mode);
    }
    else /*if (mode == DES_DECRYPT*/
    {
        KeySchedule(key, schedule[2], mode);
        KeySchedule(key + 8, schedule[1], ENCRYPT);
        KeySchedule(key + 16, schedule[0], mode);
    }
}
static void TripleDESCrypt(const byte input[8], byte output[8], byte key[3][16][6])
{
    Crypt(input, output, key[0]);
    Crypt(output, output, key[1]);
    Crypt(output, output, key[2]);
}

void SGQQQRCDecrypt(const uint8_t *input, size_t length, uint8_t *output) {
    if (!input || !output || length % 8) return;
    static const byte qqKey[] = "!@#)(*$%123ZXC!@!@#)(NHL";
    byte schedule[3][16][6];
    TripleDESKeySetup(qqKey, schedule, DECRYPT);
    for (size_t i = 0; i < length; i += 8) {
        byte block[8];
        TripleDESCrypt(input + i, block, schedule);
        memcpy(output + i, block, 8);
    }
}

#pragma mark - the requests

static NSString *const kMusicu = @"https://u.y.qq.com/cgi-bin/musicu.fcg";

static NSDictionary<NSString *, NSString *> *qqHeaders(void) {
    return @{@"Referer": @"https://y.qq.com/", @"User-Agent": @"Mozilla/5.0", @"Accept": @"application/json"};
}

// Whether a line carries a colon (Chinese or English), used to catch credit lines.
static BOOL containsColon(NSString *text) {
    return [text containsString:@":"] || [text containsString:@"："];
}

// Whether a line carries a bracket pair ([] or 【】), a leftover tag.
static BOOL containsBracketTag(NSString *text) {
    return ([text containsString:@"["] && [text containsString:@"]"])
        || ([text containsString:@"【"] && [text containsString:@"】"]);
}

// Whether a line carries a paren pair (() or （）), a credit annotation.
static BOOL containsParenPair(NSString *text) {
    return ([text containsString:@"("] && [text containsString:@")"])
        || ([text containsString:@"（"] && [text containsString:@"）"]);
}

// Whether a line is a copyright / license warning QQ Music sometimes carries.
static BOOL isLicenseWarning(NSString *text) {
    if (!text.length) return NO;
    static NSArray<NSString *> *special;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ special = @[@"文曲大模型", @"享有本翻译作品的著作权"]; });
    for (NSString *kw in special) if ([text containsString:kw]) return YES;
    static NSArray<NSString *> *tokens;
    static dispatch_once_t once2;
    dispatch_once(&once2, ^{ tokens = @[@"未经", @"许可", @"授权", @"不得", @"请勿", @"使用", @"版权", @"翻唱"]; });
    NSInteger count = 0;
    for (NSString *t in tokens) if ([text containsString:t]) count++;
    return count >= 3;
}

// The eight-step filter the lrclib proxy's get.js runs, ported to SGKaraokeLine arrays. Strips credit
// lines, metadata tags, copyright warnings, empty rows and "//" markers so only sung lines remain.
static NSArray<SGKaraokeLine *> *filterKaraokeLines(NSArray<SGKaraokeLine *> *lines) {
    if (!lines.count) return lines;
    NSMutableArray<SGKaraokeLine *> *f = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) {
        NSString *text = SGKaraokeLineText(line);
        if (!text.length) continue;
        if ([text isEqualToString:@"//"]) continue;
        if (containsBracketTag(text)) continue;
        if (isLicenseWarning(text)) continue;
        [f addObject:line];
    }
    // 1) First three: drop lines with '-' (song-title rows).
    NSUInteger limit = MIN(3, f.count);
    for (NSUInteger i = 0; i < limit && i < f.count; ) {
        if ([SGKaraokeLineText(f[i]) containsString:@"-"]) { [f removeObjectAtIndex:i]; limit = MIN(3, f.count); }
        else i++;
    }
    // 2) First three: drop lines with a colon (词：/曲： rows).
    BOOL removedColon = NO;
    limit = MIN(3, f.count);
    for (NSUInteger i = 0; i < limit && i < f.count; ) {
        if (containsColon(SGKaraokeLineText(f[i]))) { [f removeObjectAtIndex:i]; removedColon = YES; limit = MIN(3, f.count); }
        else i++;
    }
    // 3) Drop the leading run of colon lines: all of it if step 2 removed one, else only ≥2.
    NSUInteger leading = 0;
    while (leading < f.count && containsColon(SGKaraokeLineText(f[leading]))) leading++;
    if ((removedColon && leading >= 1) || (!removedColon && leading >= 2)) {
        [f removeObjectsInRange:NSMakeRange(0, leading)];
    }
    // 4) Drop any run of ≥2 consecutive colon lines further in.
    NSMutableArray<SGKaraokeLine *> *g = [NSMutableArray array];
    NSUInteger i = 0;
    while (i < f.count) {
        if (containsColon(SGKaraokeLineText(f[i]))) {
            NSUInteger j = i;
            while (j < f.count && containsColon(SGKaraokeLineText(f[j]))) j++;
            if (j - i >= 2) i = j;
            else { [g addObject:f[i]]; i++; }
        } else { [g addObject:f[i]]; i++; }
    }
    f = g;
    // 5) First two: drop lines with a paren pair (credit annotations).
    limit = MIN(2, f.count);
    for (NSUInteger i = 0; i < limit && i < f.count; ) {
        if (containsParenPair(SGKaraokeLineText(f[i]))) { [f removeObjectAtIndex:i]; limit = MIN(2, f.count); }
        else i++;
    }
    return f.count ? f : nil;
}

// [00:34.30] Look — the same LRC shape LRCLIB serves, parsed the same way. A line may be stamped
// more than once when it is sung more than once. QQ Music marks an absent translation with "//";
// those are skipped so a blank never shows as a translation line.
static NSArray<SGKaraokeLine *> *linesFromLRC(NSString *lrc) {
    static NSRegularExpression *stamp;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        stamp = [NSRegularExpression regularExpressionWithPattern:@"\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]" options:0 error:nil];
    });
    NSMutableArray<NSDictionary *> *stamped = [NSMutableArray array];
    for (NSString *row in [lrc componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSArray<NSTextCheckingResult *> *found = [stamp matchesInString:row options:0 range:NSMakeRange(0, row.length)];
        NSUInteger end = 0;
        NSMutableArray<NSNumber *> *at = [NSMutableArray array];
        for (NSTextCheckingResult *match in found) {
            if (match.range.location != end) break;
            end = NSMaxRange(match.range);
            NSInteger minutes = [row substringWithRange:[match rangeAtIndex:1]].integerValue;
            NSInteger seconds = [row substringWithRange:[match rangeAtIndex:2]].integerValue;
            NSInteger fraction = 0;
            NSRange part = [match rangeAtIndex:3];
            if (part.location != NSNotFound) {
                NSString *digits = [row substringWithRange:part];
                fraction = digits.integerValue * (digits.length == 1 ? 100 : digits.length == 2 ? 10 : 1);
            }
            [at addObject:@((minutes * 60 + seconds) * 1000 + fraction)];
        }
        if (!at.count) continue;
        NSString *text = [[row substringFromIndex:end] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([text isEqualToString:@"//"]) continue;
        for (NSNumber *ms in at) [stamped addObject:@{@"ms": ms, @"text": text}];
    }
    if (!stamped.count) return nil;
    [stamped sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"ms"] compare:b[@"ms"]];
    }];
    NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSDictionary *row in stamped) {
        [starts addObject:row[@"ms"]];
        [texts addObject:row[@"text"]];
    }
    return filterKaraokeLines(SGKaraokeEstimatedLines(starts, texts));
}

// [lineStart,lineLength]word (absoluteWordStart,wordLength)next (start,length) — the QRC shape, a
// triple-DES-encrypted, zlib-compressed sheet. Each word's text sits before its (start,length) stamp;
// a space before a token belongs to the preceding word, as YRC does not.
static NSString *qrcBody(NSString *xml);  // defined below; pulls LyricContent out of the decrypted XML
static NSArray<SGKaraokeLine *> *linesFromQRC(NSString *xml) {
    NSString *body = qrcBody(xml);
    if (!body.length) return nil;
    static NSRegularExpression *header, *part;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        header = [NSRegularExpression regularExpressionWithPattern:@"^\\[(\\d+),(\\d+)\\]" options:0 error:nil];
        part = [NSRegularExpression regularExpressionWithPattern:@"\\((\\d+),(\\d+)\\)" options:0 error:nil];
    });
    NSMutableArray<SGKaraokeLine *> *lines = [NSMutableArray array];
    for (NSString *rawRow in [body componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *row = [rawRow stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSTextCheckingResult *head = [header firstMatchInString:row options:0 range:NSMakeRange(0, row.length)];
        if (!head) continue;
        NSInteger lineStart = [row substringWithRange:[head rangeAtIndex:1]].integerValue;
        NSInteger lineLength = [row substringWithRange:[head rangeAtIndex:2]].integerValue;
        if (lineStart < 0 || lineStart > 36000000 || lineLength < 0 || lineLength > 600000) continue;
        NSArray<NSTextCheckingResult *> *parts = [part matchesInString:row options:0
            range:NSMakeRange(NSMaxRange(head.range), row.length - NSMaxRange(head.range))];
        NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
        SGKaraokeWord *open = nil;
        BOOL spaced = YES;
        NSUInteger from = NSMaxRange(head.range);
        for (NSTextCheckingResult *match in parts) {
            NSString *raw = [row substringWithRange:NSMakeRange(from, match.range.location - from)];
            NSString *text = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSInteger start = [row substringWithRange:[match rangeAtIndex:1]].integerValue;
            NSInteger length = [row substringWithRange:[match rangeAtIndex:2]].integerValue;
            from = NSMaxRange(match.range);
            if (start < 0 || start > 36000000 || length < 0 || length > 600000) continue;
            NSInteger end = start + MAX((NSInteger)1, length);
            BOOL unspaced = SGKaraokeUnspacedScript(text);
            if (text.length && open && !spaced && !unspaced) {
                open.text = [open.text stringByAppendingString:text];
                open.end = MAX(open.end, end);
            } else if (text.length) {
                SGKaraokeWord *word = [SGKaraokeWord new];
                word.text = text;
                word.start = start;
                word.end = end;
                word.joined = !spaced;
                [words addObject:word];
                open = unspaced ? nil : word;
            }
            spaced = raw.length > text.length || !text.length;
            if (spaced) open = nil;
        }
        if (!words.count) continue;
        SGKaraokeLine *line = [SGKaraokeLine new];
        line.words = words;
        // The word clock is the singing clock; drive scrolling from the words, not the padded header.
        line.start = words.firstObject.start;
        line.end = words.lastObject.end;
        [lines addObject:line];
    }
    return filterKaraokeLines(lines);
}

// The translation is an LRC sheet with its own timestamps, in Chinese. Each translated line is
// lined up with the closest original by start time and set on the line.
static void applyTranslation(SGLyricsResult *lyrics, NSString *translatedLRC) {
    if (!lyrics || !lyrics.karaokeLines.count) return;
    NSArray<SGKaraokeLine *> *translated = linesFromLRC(translatedLRC);
    if (!translated.count) return;
    for (SGKaraokeLine *line in lyrics.karaokeLines) {
        NSUInteger best = 0;
        NSInteger minDiff = NSIntegerMax;
        for (NSUInteger i = 0; i < translated.count; i++) {
            NSInteger diff = labs(line.start - translated[i].start);
            if (diff < minDiff) { minDiff = diff; best = i; }
        }
        NSString *text = SGKaraokeLineText(translated[best]);
        if (text.length && ![text isEqualToString:SGKaraokeLineText(line)]) line.translation = text;
    }
}

// The romanisation is a QRC sheet spelt in the Latin alphabet — the sound of a CJK line. Each roma
// line is lined up with the closest original by start time, and its own words (already timed) become
// the line's pronunciation, shown only when the redesign's Pronunciation switch is on.
static void applyPronunciationFromQRC(SGLyricsResult *lyrics, NSString *romaQRC) {
    if (!lyrics || !lyrics.karaokeLines.count) return;
    NSArray<SGKaraokeLine *> *roma = linesFromQRC(romaQRC);
    if (!roma.count) return;
    for (SGKaraokeLine *line in lyrics.karaokeLines) {
        NSUInteger best = 0;
        NSInteger minDiff = NSIntegerMax;
        for (NSUInteger i = 0; i < roma.count; i++) {
            NSInteger diff = labs(line.start - roma[i].start);
            if (diff < minDiff) { minDiff = diff; best = i; }
        }
        NSString *said = SGKaraokeLineText(roma[best]);
        if (!said.length || [said isEqualToString:SGKaraokeLineText(line)]) continue;
        SGKaraokeLine *spoken = [SGKaraokeLine new];
        spoken.words = roma[best].words;
        spoken.start = line.start;
        spoken.end = MAX(line.end, roma[best].end);
        spoken.align = line.align;
        line.pronunciation = spoken;
    }
}

static NSString *decoded(NSDictionary *data, NSString *key) {
    NSString *encoded = [data[key] isKindOfClass:NSString.class] ? data[key] : nil;
    NSData *bytes = encoded.length ? [[NSData alloc] initWithBase64EncodedString:encoded options:0] : nil;
    return bytes ? [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding] : nil;
}

static NSString *decodedQRCKey(NSDictionary *data, NSString *key) {
    NSString *hex = [data[key] isKindOfClass:NSString.class] ? data[key] : nil;
    if (!hex.length || hex.length > 2 * 1024 * 1024 || hex.length % 16) return nil;
    NSMutableData *encrypted = [NSMutableData dataWithLength:hex.length / 2];
    const char *source = hex.UTF8String;
    if (!source || strlen(source) != hex.length) return nil;
    uint8_t *bytes = encrypted.mutableBytes;
    for (NSUInteger i = 0; i < encrypted.length; i++) {
        int hi = source[2 * i], lo = source[2 * i + 1];
        hi = hi >= '0' && hi <= '9' ? hi - '0' : hi >= 'A' && hi <= 'F' ? hi - 'A' + 10 : hi >= 'a' && hi <= 'f' ? hi - 'a' + 10 : -1;
        lo = lo >= '0' && lo <= '9' ? lo - '0' : lo >= 'A' && lo <= 'F' ? lo - 'A' + 10 : lo >= 'a' && lo <= 'f' ? lo - 'a' + 10 : -1;
        if (hi < 0 || lo < 0) return nil;
        bytes[i] = (uint8_t)((hi << 4) | lo);
    }
    NSMutableData *plain = [NSMutableData dataWithLength:encrypted.length];
    SGQQQRCDecrypt(encrypted.bytes, encrypted.length, plain.mutableBytes);
    NSMutableData *inflated = [NSMutableData dataWithLength:1024 * 1024];
    uLongf length = (uLongf)inflated.length;
    if (uncompress(inflated.mutableBytes, &length, plain.bytes, (uLong)plain.length) != Z_OK) return nil;
    return [[NSString alloc] initWithBytes:inflated.bytes length:(NSUInteger)length encoding:NSUTF8StringEncoding];
}

// Pulls the LyricContent="..." attribute out of the decrypted QRC XML, unescaping the entities that
// encode its newlines and angle brackets.
static NSString *qrcBody(NSString *xml) {
    NSRange attr = [xml rangeOfString:@"LyricContent=\""];
    if (attr.location == NSNotFound) return [xml hasPrefix:@"["] ? xml : nil;
    NSUInteger start = NSMaxRange(attr);
    NSRange end = [xml rangeOfString:@"\"" options:0 range:NSMakeRange(start, xml.length - start)];
    if (end.location == NSNotFound) return nil;
    NSString *body = [xml substringWithRange:NSMakeRange(start, end.location - start)];
    for (NSArray<NSString *> *pair in @[@[@"&quot;", @"\""], @[@"&apos;", @"'"],
                                       @[@"&lt;", @"<"], @[@"&gt;", @">"],
                                       @[@"&#10;", @"\n"], @[@"&#xA;", @"\n"], @[@"&amp;", @"&"]]) {
        body = [body stringByReplacingOccurrencesOfString:pair[0] withString:pair[1]];
    }
    return body;
}

static SGLyricsResult *resultForLines(NSArray<SGKaraokeLine *> *lines) {
    if (!lines.count) return nil;
    SGLyricsResult *result = [SGLyricsResult new];
    result.synced = YES;
    result.wordTimed = lines.firstObject.words.count > 0;
    result.karaokeLines = lines;
    NSArray<NSNumber *> *starts;
    NSArray<NSString *> *texts;
    SGLyricsPageLines(lines, &starts, &texts);
    result.starts = starts;
    result.texts = texts;
    return result;
}

static NSString *qqSingers(NSDictionary *song) {
    id singer = song[@"singer"];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    if ([singer isKindOfClass:NSArray.class]) {
        for (NSDictionary *s in singer) {
            id name = s[@"name"];
            if ([name isKindOfClass:NSString.class] && [name length]) [names addObject:name];
        }
    } else if ([singer isKindOfClass:NSString.class] && [singer length]) {
        [names addObject:singer];
    }
    return [names componentsJoinedByString:@", "];
}

static void lyricReply(NSNumber *songID, BOOL translation, BOOL qrc, void (^done)(NSDictionary *data)) {
    NSDictionary *request = @{@"music.musichallSong.PlayLyricInfo.GetPlayLyricInfo": @{
        @"method": @"GetPlayLyricInfo", @"module": @"music.musichallSong.PlayLyricInfo",
        @"param": @{@"crypt": @0, @"qrc": qrc ? @1 : @0, @"trans": translation ? @1 : @0, @"roma": @1, @"songID": songID}}};
    SGLyricsPostJSON([NSURL URLWithString:kMusicu], qqHeaders(), request, ^(id root) {
        id value = [root isKindOfClass:NSDictionary.class]
            ? root[@"music.musichallSong.PlayLyricInfo.GetPlayLyricInfo"] : nil;
        NSDictionary *reply = [value isKindOfClass:NSDictionary.class] ? value : nil;
        NSDictionary *data = [reply[@"data"] isKindOfClass:NSDictionary.class] ? reply[@"data"] : nil;
        done(data);
    });
}

static void searchKeyword(NSString *keyword, void (^done)(NSArray<NSDictionary *> *list)) {
    NSDictionary *request = @{
        @"comm": @{@"ct": @"19", @"cv": @"1859", @"uin": @"0"},
        @"req": @{@"method": @"DoSearchForQQMusicDesktop", @"module": @"music.search.SearchCgiService",
                  @"param": @{@"grp": @1, @"num_per_page": @40, @"page_num": @1,
                               @"query": keyword, @"search_type": @0}}
    };
    SGLyricsPostJSON([NSURL URLWithString:kMusicu], qqHeaders(), request, ^(id root) {
        id value = [root isKindOfClass:NSDictionary.class] ? root[@"req"] : nil;
        NSDictionary *requestReply = [value isKindOfClass:NSDictionary.class] ? value : nil;
        NSDictionary *data = [requestReply[@"data"] isKindOfClass:NSDictionary.class] ? requestReply[@"data"] : nil;
        NSDictionary *body = [data[@"body"] isKindOfClass:NSDictionary.class] ? data[@"body"] : nil;
        NSDictionary *song = [body[@"song"] isKindOfClass:NSDictionary.class] ? body[@"song"] : nil;
        NSArray *list = [song[@"list"] isKindOfClass:NSArray.class] ? song[@"list"] : @[];
        SGLog(@"qqmusic: search '%@' returned %lu candidates", keyword, (unsigned long)list.count);
        done(list);
    });
}

static void lyricFor(NSNumber *songID, void (^done)(SGLyricsResult *)) {
    lyricReply(songID, YES, YES, ^(NSDictionary *data) {
        NSString *xml = decodedQRCKey(data, @"lyric");
        NSArray<SGKaraokeLine *> *lines = xml ? linesFromQRC(xml) : nil;
        SGLyricsResult *result = lines.count ? resultForLines(lines) : nil;
        if (result) {
            NSString *trans = decoded(data, @"trans");
            if (trans.length) {
                NSString *lang = SGLyricsTranslationLanguage();
                if (!lang.length || [lang hasPrefix:@"zh"]) applyTranslation(result, trans);
            }
            NSString *romaXML = decodedQRCKey(data, @"roma");
            if (romaXML.length) applyPronunciationFromQRC(result, romaXML);
            SGLog(@"qqmusic: QRC decoded %lu word timed lines for %@", (unsigned long)lines.count, songID);
            done(result);
            return;
        }
        SGLog(@"qqmusic: QRC unavailable for %@; trying LRC", songID);
        lyricReply(songID, YES, NO, ^(NSDictionary *lrcData) {
            NSString *lrc = decoded(lrcData, @"lyric");
            NSArray<SGKaraokeLine *> *lrcLines = lrc.length ? linesFromLRC(lrc) : nil;
            SGLyricsResult *lrcResult = lrcLines.count ? resultForLines(lrcLines) : nil;
            if (lrcResult) {
                NSString *trans = decoded(lrcData, @"trans");
                if (trans.length) {
                    NSString *lang = SGLyricsTranslationLanguage();
                    if (!lang.length || [lang hasPrefix:@"zh"]) applyTranslation(lrcResult, trans);
                }
                SGLog(@"qqmusic: LRC decoded %lu line timed lines for %@", (unsigned long)lrcLines.count, songID);
            }
            done(lrcResult);
        });
    });
}

SGLyricsAsk SGQQMusicAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    NSString *lead = [query.artist componentsSeparatedByString:@" feat"].firstObject.lowercaseString;
    NSString *title = query.title;
    NSInteger seconds = query.seconds;
    if (!title.length || !lead.length) { done(nil); return; }
    NSString *keyword = [NSString stringWithFormat:@"%@ %@", title, lead];
    searchKeyword(keyword, ^(NSArray<NSDictionary *> *list) {
        NSMutableArray<NSDictionary *> *fitting = [NSMutableArray array];
        for (NSDictionary *song in list) {
            if (![song isKindOfClass:NSDictionary.class]) continue;
            NSString *singers = qqSingers(song).lowercaseString;
            BOOL artistOK = singers.length && ([singers containsString:lead] || [lead containsString:singers]);
            NSInteger interval = [song[@"interval"] respondsToSelector:@selector(integerValue)]
                ? [song[@"interval"] integerValue] : 0;
            BOOL timeOK = seconds <= 0 || interval <= 0 || labs(interval - seconds) <= 8;
            if (artistOK && timeOK) [fitting addObject:song];
        }
        if (!fitting.count) {
            // No singer match — fall back to the first result, on the bet that QQ Music's search
            // ranks the title's best known recording first.
            if (list.count) [fitting addObject:[list firstObject]];
            else { SGLog(@"qqmusic: no recording of %@", title); done(nil); return; }
        }
        [fitting sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSString *as = qqSingers(a).lowercaseString;
            NSString *bs = qqSingers(b).lowercaseString;
            BOOL aMatch = as.length && ([as containsString:lead] || [lead containsString:as]);
            BOOL bMatch = bs.length && ([bs containsString:lead] || [lead containsString:bs]);
            if (aMatch != bMatch) return aMatch ? NSOrderedAscending : NSOrderedDescending;
            NSInteger ai = [a[@"interval"] respondsToSelector:@selector(integerValue)] ? [a[@"interval"] integerValue] : 0;
            NSInteger bi = [b[@"interval"] respondsToSelector:@selector(integerValue)] ? [b[@"interval"] integerValue] : 0;
            NSInteger ag = seconds > 0 && ai > 0 ? labs(ai - seconds) : NSIntegerMax;
            NSInteger bg = seconds > 0 && bi > 0 ? labs(bi - seconds) : NSIntegerMax;
            if (ag != bg) return ag < bg ? NSOrderedAscending : NSOrderedDescending;
            return NSOrderedSame;
        }];
        NSArray *ids = [[fitting valueForKey:@"id"] subarrayWithRange:NSMakeRange(0, MIN(fitting.count, 3))];
        // Try up to three recordings until one has lyrics. Recurses into itself, so a weak reference
        // breaks the ARC retain cycle a __block capture would make.
        __block NSUInteger index = 0;
        __block void (^tryNext)(void) = nil;
        __weak void (^weakTryNext)(void) = nil;
        void (^finish)(SGLyricsResult *) = ^(SGLyricsResult *r) {
            if (r) { r.title = query.title; r.artist = query.artist; }
            done(r);
        };
        tryNext = ^{
            if (index >= ids.count) { finish(nil); return; }
            NSNumber *songID = ids[index];
            index++;
            lyricFor(songID, ^(SGLyricsResult *result) {
                if (result) finish(result);
                else {
                    void (^strong)(void) = weakTryNext;
                    if (strong) strong();
                }
            });
        };
        weakTryNext = tryNext;
        tryNext();
    });
};

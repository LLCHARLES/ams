#import "EmbeddedLyrics.h"
#import "LocalLyrics.h"
#import "Core/SGLocalize.h"
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

// A separate total metadata budget lets us pass artwork, descriptors and other metadata
// without treating them as lyric text. FLAC blocks and MP4 media atoms are skipped by offset.
enum { textLimit = SGLyricsImportMaxBytes, readBudget = 8 << 20, maxEntries = 16384 };
typedef struct { int fd; off_t end; NSUInteger left, entries; } Reader;
typedef struct { const uint8_t *p; NSUInteger n; } Span;

static NSData *get(Reader *r, off_t at, NSUInteger n) {
    if (at < 0 || at > r->end || n > (uint64_t)(r->end-at) || n > r->left) return nil;
    NSMutableData *d = [NSMutableData dataWithLength:n];
    if (pread(r->fd, d.mutableBytes, n, at) != (ssize_t)n) return nil;
    r->left -= n;
    return d;
}
static uint32_t be(const uint8_t *p, int n) {
    uint32_t v = 0;
    while (n--) v = (v << 8) | *p++;
    return v;
}
static uint32_t safeSize(const uint8_t *p) {
    if ((p[0]|p[1]|p[2]|p[3]) & 0x80) return UINT32_MAX;
    return p[0]<<21 | p[1]<<14 | p[2]<<7 | p[3];
}
static BOOL skip(Span *s, NSUInteger n) {
    if (n > s->n) return NO;
    s->p += n; s->n -= n;
    return YES;
}
static NSString *decode(Span s, NSStringEncoding *enc) {
    if (*enc == NSUTF16StringEncoding && s.n >= 2) {
        if (be(s.p,2) == 0xfffe) *enc = NSUTF16LittleEndianStringEncoding;
        else if (be(s.p,2) == 0xfeff) *enc = NSUTF16BigEndianStringEncoding;
    }
    if ((*enc == NSUTF16LittleEndianStringEncoding && s.n >= 2 && be(s.p,2) == 0xfffe) ||
        (*enc == NSUTF16BigEndianStringEncoding && s.n >= 2 && be(s.p,2) == 0xfeff)) skip(&s,2);
    return [[NSString alloc] initWithBytes:s.p length:s.n encoding:*enc];
}
static NSString *terminated(Span *s, NSStringEncoding *enc, BOOL wide) {
    NSUInteger step = wide ? 2 : 1;
    for (NSUInteger i = 0; i + step <= s->n; i += step) {
        if (s->p[i] || (wide && s->p[i+1])) continue;
        NSString *text = decode((Span){s->p,i}, enc);
        skip(s,i+step);
        return text;
    }
    return nil;
}
static SGLyricsResult *textResult(NSString *text) {
    if (!text.length || [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > textLimit) return nil;
    SGImportedLyrics *sheet = SGImportedLyricsFromText(text, nil);
    if (!sheet) return nil;
    SGLyricsResult *r = [SGLyricsResult new];
    r.synced = sheet.synced; r.karaokeLines = sheet.lines; r.starts = sheet.starts; r.texts = sheet.texts;
    return r;
}
static SGLyricsResult *id3Lyrics(Span s, BOOL synced) {
    static const NSStringEncoding encs[] = {NSISOLatin1StringEncoding, NSUTF16StringEncoding,
                                           NSUTF16BigEndianStringEncoding, NSUTF8StringEncoding};
    if (s.n < (synced ? 6 : 4) || s.p[0] > 3) return nil;
    NSStringEncoding enc = encs[s.p[0]];
    BOOL wide = s.p[0] == 1 || s.p[0] == 2;
    if (synced && (s.p[4] != 2 || s.p[5] > 1)) return nil; // milliseconds, lyrics or unspecified
    skip(&s,synced ? 6 : 4);
    if (!terminated(&s,&enc,wide)) return nil; // descriptor (may establish UTF-16 byte order)
    if (!synced) {
        while (s.n >= (wide ? 2u : 1u) && !s.p[s.n-1] && (!wide || !s.p[s.n-2])) s.n -= wide ? 2 : 1;
        return s.n <= textLimit ? textResult(decode(s,&enc)) : nil;
    }
    NSMutableArray *starts = [NSMutableArray array], *texts = [NSMutableArray array];
    NSUInteger bytes = 0, rawBytes = 0, chars = 0;
    while (s.n) {
        NSUInteger before = s.n;
        NSString *line = terminated(&s,&enc,wide);
        if (!line || s.n < 4 || starts.count >= SGFileLyricsMaxLines || line.length > SGFileLyricsMaxCharacters - chars) return nil;
        chars += line.length;
        rawBytes += before - s.n - (wide ? 2 : 1);
        bytes += [line lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (bytes > textLimit || rawBytes > textLimit) return nil;
        if (line.length) { [starts addObject:@(be(s.p,4))]; [texts addObject:line]; }
        skip(&s,4);
    }
    if (!texts.count) return nil;
    NSArray *lines = SGKaraokeEstimatedLines(starts,texts);
    if (!lines.count) return nil;
    SGLyricsResult *r = [SGLyricsResult new];
    r.synced = YES; r.karaokeLines = lines; r.starts = starts; r.texts = texts;
    return r;
}
static NSData *unstuff(Span s) {
    NSMutableData *d = [NSMutableData dataWithLength:s.n];
    uint8_t *out = d.mutableBytes;
    NSUInteger j = 0;
    for (NSUInteger i = 0; i < s.n; i++) {
        out[j++] = s.p[i];
        if (s.p[i] == 0xff && i+1 < s.n && !s.p[i+1]) i++;
    }
    d.length = j;
    return d;
}
// v2.2/v2.3 tag-wide unsync encodes even the headers. Their sizes count decoded
// bytes, so those tags must advance sequentially. All other skips cost no reads.
typedef struct {
    Reader *r;
    off_t at, end;
    BOOL unsync, afterFF;
    uint8_t buffer[4096];
    NSUInteger pos, len;
} ID3Cursor;

static BOOL take(ID3Cursor *c, NSUInteger n, uint8_t *out) {
    if (n > (uint64_t)(c->end - c->at)) return NO;
    if (!c->unsync) {
        if (out) {
            if (n > c->r->left || pread(c->r->fd,out,n,c->at) != (ssize_t)n) return NO;
            c->r->left -= n;
        }
        c->at += n;
        return YES;
    }
    while (n) {
        if (c->pos == c->len) {
            NSUInteger size = MIN(sizeof(c->buffer), MIN(c->r->left,(NSUInteger)(c->end-c->at)));
            if (!size || pread(c->r->fd,c->buffer,size,c->at) != (ssize_t)size) return NO;
            c->pos = 0; c->len = size; c->r->left -= size;
        }
        uint8_t byte = c->buffer[c->pos++];
        c->at++;
        if (c->afterFF && !byte) { c->afterFF = NO; continue; }
        c->afterFF = byte == 0xff;
        if (out) *out++ = byte;
        n--;
    }
    return YES;
}
static SGLyricsResult *id3(Reader *r, const uint8_t *h) {
    int v = h[3], flags = h[5];
    if (v < 2 || v > 4 || (v == 2 && (flags & 0x40))) return nil;
    NSUInteger size = safeSize(h+6);
    if (size == UINT32_MAX || size > r->end-10) return nil;
    ID3Cursor cursor = {.r=r, .at=10, .end=10+(off_t)size, .unsync=v < 4 && (flags & 0x80)};
    if (flags & 0x40) {
        uint8_t field[4];
        if (!take(&cursor,4,field)) return nil;
        NSUInteger ext = v == 4 ? safeSize(field) : (NSUInteger)be(field,4)+4;
        if (ext < 4 || !take(&cursor,ext-4,NULL)) return nil;
    }
    SGLyricsResult *best = nil;
    NSUInteger header = v == 2 ? 6 : 10;
    uint8_t p[10];
    while (r->entries++ < maxEntries && take(&cursor,header,p) && *p) {
        BOOL synced = !memcmp(p,v == 2 ? "SLT" : "SYLT",v == 2 ? 3 : 4);
        BOOL plain = !memcmp(p,v == 2 ? "ULT" : "USLT",v == 2 ? 3 : 4);
        NSUInteger n = v == 2 ? be(p+3,3) : v == 3 ? be(p+4,4) : safeSize(p+4);
        unsigned format = v == 2 ? 0 : p[9];
        if (n > cursor.end-cursor.at) break;
        if (!(plain || synced) || (format & (v == 4 ? 0x0c : 0xc0)) || n > r->left+cursor.len-cursor.pos) {
            if (!take(&cursor,n,NULL)) break;
            continue;
        }
        NSMutableData * __attribute__((objc_precise_lifetime)) data = [NSMutableData dataWithLength:n];
        if (!take(&cursor,n,data.mutableBytes)) break;
        Span frame = {data.bytes,n};
        NSData * __attribute__((objc_precise_lifetime)) decoded = nil;
        if (v == 4 && ((flags & 0x80) || (format & 2))) {
            decoded = unstuff(frame); frame = (Span){decoded.bytes,decoded.length};
        }
        if ((format & (v == 4 ? 0x40 : 0x20)) && !skip(&frame,1)) continue;
        if (v == 4 && (format & 1) && !skip(&frame,4)) continue;
        SGLyricsResult *item = id3Lyrics(frame,synced);
        if (item.synced) return item;
        best = best ?: item;
    }
    return best;
}
static BOOL little(Span *s, uint32_t *out) {
    if (s->n < 4) return NO;
    *out = s->p[0] | (uint32_t)s->p[1]<<8 | (uint32_t)s->p[2]<<16 | (uint32_t)s->p[3]<<24;
    return skip(s,4);
}
static SGLyricsResult *comments(Span s) {
    uint32_t n,count;
    if (!little(&s,&n) || !skip(&s,n) || !little(&s,&count) || count > maxEntries) return nil;
    SGLyricsResult *best = nil;
    for (uint32_t i = 0; i < count; i++) {
        if (!little(&s,&n) || n > s.n) break;
        const uint8_t *p = s.p;
        skip(&s,n);
        NSUInteger prefix = n >= 7 && !strncasecmp((const char *)p,"LYRICS=",7) ? 7 :
            n >= 15 && !strncasecmp((const char *)p,"UNSYNCEDLYRICS=",15) ? 15 : 0;
        if (!prefix || n-prefix > textLimit) continue;
        SGLyricsResult *item = textResult([[NSString alloc] initWithBytes:p+prefix length:n-prefix encoding:NSUTF8StringEncoding]);
        if (item.synced) return item;
        best = best ?: item;
    }
    return best;
}
static SGLyricsResult *flac(Reader *r) {
    for (off_t at = 4; at < r->end && r->entries++ < maxEntries;) {
        NSData * __attribute__((objc_precise_lifetime)) block = get(r,at,4);
        if (!block) break;
        const uint8_t *p = block.bytes;
        NSUInteger n = be(p+1,3);
        if ((p[0] & 127) == 4) {
            NSData * __attribute__((objc_precise_lifetime)) data = get(r,at+4,n);
            return comments((Span){data.bytes,data.length});
        }
        if (p[0] & 128 || n > r->end-at-4) break;
        at += 4+n;
    }
    return nil;
}
// Follow only the iTunes metadata hierarchy; do not scan mdat for four-character matches.
static SGLyricsResult *atoms(Reader *r, off_t at, off_t end, unsigned level) {
    static const char *const path[] = {"moov","udta","meta","ilst","\xa9lyr","data"};
    while (end-at >= 8 && r->entries++ < maxEntries) {
        NSData * __attribute__((objc_precise_lifetime)) box = get(r,at,8);
        if (!box) break;
        const uint8_t *p = box.bytes;
        uint64_t size = be(p,4);
        NSUInteger head = 8;
        if (size == 1) {
            NSData * __attribute__((objc_precise_lifetime)) ext = get(r,at+8,8);
            if (!ext) break;
            const uint8_t *q = ext.bytes;
            size = (uint64_t)be(q,4)<<32 | be(q+4,4); head += 8;
        } else if (!size) size = end-at;
        if (size < head || size > (uint64_t)(end-at)) break;
        unsigned step = level;
        if (level == 1 && !memcmp(p+4,"meta",4)) step++; // moov/meta without udta
        if (!memcmp(p+4,path[step],4)) {
            if (step == 5 && size >= head+8 && size-head-8 <= textLimit) {
                NSData * __attribute__((objc_precise_lifetime)) value = get(r,at+head,size-head);
                if (!value) return nil;
                const uint8_t *v = value.bytes;
                uint32_t type = be(v,4);
                if (type == 1 || type == 2) return textResult([[NSString alloc] initWithBytes:v+8 length:value.length-8
                    encoding:type == 1 ? NSUTF8StringEncoding : NSUTF16BigEndianStringEncoding]);
            } else if (step < 5) {
                SGLyricsResult *found = atoms(r,at+head+(step == 2 ? 4 : 0),at+size,step+1);
                if (found) return found;
            }
        }
        at += size;
    }
    return nil;
}
SGLyricsResult *SGEmbeddedLyrics(NSString *path) {
    if (![path isAbsolutePath]) return nil;
    int fd = open(path.fileSystemRepresentation,O_RDONLY|O_CLOEXEC|O_NOFOLLOW|O_NONBLOCK);
    if (fd < 0) return nil;
    struct stat st;
    SGLyricsResult *result = nil;
    if (!fstat(fd,&st) && S_ISREG(st.st_mode)) {
        Reader reader = {fd,st.st_size,readBudget,0};
        NSData * __attribute__((objc_precise_lifetime)) header = get(&reader,0,10);
        const uint8_t *h = header.bytes;
        if (h && !memcmp(h,"ID3",3)) result = id3(&reader,h);
        else if (h && !memcmp(h,"fLaC",4)) result = flac(&reader);
        else if (h && !memcmp(h+4,"ftyp",4)) result = atoms(&reader,0,st.st_size,0);
    }
    close(fd);
    if (result) {
        result.provider = SGL(@"settings.locallyrics.embedded.credit", @"From the file");
        for (SGKaraokeLine *line in result.karaokeLines) line.fileOwned = YES;
    }
    return result;
}

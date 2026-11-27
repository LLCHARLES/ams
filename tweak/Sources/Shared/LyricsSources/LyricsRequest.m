#import "LyricsSources.h"

BOOL SGLyricsReplyFailed(NSURLResponse *response, NSError *error) {
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    return error || (status && (status < 200 || status >= 300) && status != 404);
}

@implementation SGLyricsRequestContext {
    BOOL _failed;
    BOOL _nameSearchFailed;
    SGLyricsAsk _emptyNameSearch;
    NSMutableArray<NSURLSessionTask *> *_tasks;
    BOOL _cancelled;
    BOOL _finished;
    NSMutableArray<dispatch_block_t> *_cancellations;
}
- (BOOL)failed { @synchronized (self) { return _failed; } }
- (BOOL)cancelled { @synchronized (self) { return _cancelled; } }
- (SGLyricsAsk)emptyNameSearch { @synchronized (self) { return _nameSearchFailed ? nil : _emptyNameSearch; } }
- (void)setEmptyNameSearch:(SGLyricsAsk)search { @synchronized (self) { _emptyNameSearch = [search copy]; } }
- (void)noteFailure:(BOOL)failed { if (failed) @synchronized (self) { _failed = YES; } }
- (void)trackTask:(NSURLSessionTask *)task {
    BOOL cancelled;
    @synchronized (self) {
        cancelled = _cancelled || _finished;
        if (!cancelled) {
            if (!_tasks) _tasks = [NSMutableArray array];
            [_tasks addObject:task];
        }
    }
    if (cancelled) [task cancel];
}
- (void)cancelRequests {
    NSArray *tasks;
    NSArray<dispatch_block_t> *actions;
    @synchronized (self) {
        if (_cancelled || _finished) return;
        _cancelled = YES;
        _failed = YES;
        tasks = [_tasks copy];
        _tasks = nil;
        actions = [_cancellations copy];
        _cancellations = nil;
    }
    for (NSURLSessionTask *task in tasks) [task cancel];
    for (dispatch_block_t action in actions) action();
}
- (void)onCancel:(dispatch_block_t)action {
    BOOL cancelled;
    @synchronized (self) {
        cancelled = _cancelled;
        if (!cancelled && !_finished) {
            if (!_cancellations) _cancellations = [NSMutableArray array];
            [_cancellations addObject:[action copy]];
        }
    }
    if (cancelled) action();
}
- (void)finishRequests {
    @synchronized (self) {
        _finished = YES;
        _tasks = nil;
        _cancellations = nil;
    }
}
- (void)noteResponse:(NSURLResponse *)response error:(NSError *)error {
    [self noteFailure:SGLyricsReplyFailed(response, error)];
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    if (error || (status && (status < 200 || status >= 300) && status != 404))
        @synchronized (self) { _nameSearchFailed = YES; }
    if (!error && status == 429) {
        NSString *value = [(NSHTTPURLResponse *)response valueForHTTPHeaderField:@"Retry-After"];
        NSTimeInterval now = NSDate.date.timeIntervalSince1970, deadline = now + 60;
        if (value.length) {
            NSScanner *scanner = [NSScanner scannerWithString:value];
            long long seconds;
            if ([scanner scanLongLong:&seconds] && scanner.isAtEnd && seconds >= 0) deadline = now + seconds;
            else {
                NSDateFormatter *format = NSDateFormatter.new;
                format.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
                format.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss zzz";
                NSDate *date = [format dateFromString:value];
                if (date) deadline = date.timeIntervalSince1970;
            }
        }
        self.rateLimitUntil = MAX(now + 1, deadline);
    }
}
@end

@implementation SGLyricsLease {
    BOOL _retired;
}
- (void)invalidate { @synchronized (self) { _retired = YES; } }
- (BOOL)isCurrent { @synchronized (self) { return !_retired; } }
@end

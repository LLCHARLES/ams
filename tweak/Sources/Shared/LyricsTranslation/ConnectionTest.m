#import "Core/SGCore.h"
#import "AIServicesInternal.h"
#import "ConnectionTest.h"

static NSString *const kSampleSentence = @"The sky is blue.";
// The model list can run past a translation's 512 KiB; this is the same limit the model page sends with.
static const NSUInteger kModelListLimit = 8 * 1024 * 1024;

@implementation SGTranslationConnectionReport
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _reachable = _authenticated = _models = _translated = SGConnectionFactUnknown;
    return self;
}
@end

static NSString *factName(SGConnectionFact fact) {
    return fact == SGConnectionFactYes ? @"yes" : fact == SGConnectionFactNo ? @"no" : @"unknown";
}

// Only fixed labels and numeric observations. Models and arbitrary NSError domains can contain secrets.
static NSString *diagnosticLine(SGTranslationConnectionReport *report, NSInteger status, NSError *error, NSString *extra) {
    NSMutableArray *parts = [NSMutableArray array];
    SGConnectionCheck stage = report.stage;
    NSString *name = stage == SGConnectionCheckConfiguration ? @"configuration"
        : stage == SGConnectionCheckConnection ? @"connection"
        : stage == SGConnectionCheckAuthentication ? @"authentication"
        : stage == SGConnectionCheckModels ? @"models" : @"translation";
    [parts addObject:[@"stage=" stringByAppendingString:name]];
    [parts addObject:[@"http=" stringByAppendingString:status > 0 ? [NSString stringWithFormat:@"%ld", (long)status] : @"none"]];
    if (error) {
        NSString *domain = [@[NSURLErrorDomain, NSCocoaErrorDomain, NSPOSIXErrorDomain, NSOSStatusErrorDomain] containsObject:error.domain] ? error.domain : @"other";
        [parts addObject:[@"error=" stringByAppendingFormat:@"%@/%ld", domain, (long)error.code]];
    }
    [parts addObject:[NSString stringWithFormat:@"reachable=%@ authenticated=%@ models=%@ translated=%@",
        factName(report.reachable), factName(report.authenticated), factName(report.models), factName(report.translated)]];
    if (extra.length) [parts addObject:extra];
    return [parts componentsJoinedByString:@" "];
}

static NSURLRequest *testRequest(SGConnectionTestKind kind, NSString **problem) {
    if (kind == SGConnectionTestModels) return SGOpenAIModelsRequest(problem);
    NSString *prompt = SGLyricsTranslationPrompt(@[kSampleSentence], SGLyricsGeminiLanguage());
    if (!prompt) { *problem = SGL(@"settings.translation.openai.error.settings", @"Check the translation service's base URL and model in Lyrics › Translation & AI."); return nil; }
    return SGOpenAIRequest(SGLyricsTranslationInstruction(), prompt, SGLyricsReplyJSON, problem);
}

// Validate only the sample's shape. No response content enters the report, even on success.
static BOOL validSample(NSString *text) {
    return [text isKindOfClass:NSString.class] && text.length <= 512 &&
        [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
}

@interface SGTranslationConnectionTest ()
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, copy) NSURLRequest *request;
@property (nonatomic, copy) NSArray *observers;
@property (nonatomic, copy) void (^done)(SGTranslationConnectionReport *);
@property (nonatomic) SGConnectionTestKind kind;
@property (nonatomic) BOOL cancelled;
@end
@implementation SGTranslationConnectionTest
- (void)removeObservers {
    for (id observer in self.observers) [NSNotificationCenter.defaultCenter removeObserver:observer];
    self.observers = nil;
}
- (void)dealloc { for (id observer in _observers) [NSNotificationCenter.defaultCenter removeObserver:observer]; }
- (void)cancel {
    self.cancelled = YES;
    [self.task cancel]; self.task = nil; self.request = nil; self.done = nil;
    [self removeObservers];
}
- (BOOL)matchesConfiguration {
    NSString *problem = nil;
    NSURLRequest *now = testRequest(self.kind, &problem);
    return now && [now.URL isEqual:self.request.URL] &&
        (now.HTTPBody == self.request.HTTPBody || [now.HTTPBody isEqual:self.request.HTTPBody]) &&
        [[now valueForHTTPHeaderField:@"Authorization"] isEqual:[self.request valueForHTTPHeaderField:@"Authorization"]];
}
- (void)complete:(SGTranslationConnectionReport *)report {
    if (self.cancelled || !self.done) return;
    void (^done)(SGTranslationConnectionReport *) = self.done;
    self.done = nil; self.task = nil; self.request = nil;
    [self removeObservers];
    done(report);
}
- (void)failBeforeSending:(NSString *)problem {
    SGTranslationConnectionReport *report = [SGTranslationConnectionReport new];
    report.stage = SGConnectionCheckConfiguration;
    report.problem = problem ?: SGL(@"settings.translation.openai.error.settings", @"Check the translation service's base URL and model in Lyrics › Translation & AI.");
    report.diagnostic = diagnosticLine(report, 0, nil, @"sent=no");
    dispatch_async(dispatch_get_main_queue(), ^{ [self complete:report]; });
}
- (void)start {
    NSString *problem = nil;
    self.request = testRequest(self.kind, &problem);
    if (!self.request) { [self failBeforeSending:problem]; return; }
    __weak SGTranslationConnectionTest *weakSelf = self;
    NSMutableArray *observers = [NSMutableArray array];
    for (NSNotificationName name in @[SGLyricsTranslationServiceSettingsDidChangeNotification, SGLyricsTranslationsDidChangeNotification]) {
        [observers addObject:[NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            void (^check)(void) = ^{ SGTranslationConnectionTest *test = weakSelf; if (test && ![test matchesConfiguration]) [test cancel]; };
            if (NSThread.isMainThread) check(); else dispatch_async(dispatch_get_main_queue(), check);
        }]];
    }
    self.observers = observers;
    BOOL models = self.kind == SGConnectionTestModels;
    NSUInteger limit = models ? kModelListLimit : 512 * 1024;
    void (^finished)(NSData *, NSInteger, NSError *) = ^(NSData *data, NSInteger status, NSError *error) {
        if (self.cancelled || !self.done) return;
        if (![self matchesConfiguration]) { [self cancel]; return; }
        SGTranslationConnectionReport *report = [SGTranslationConnectionReport new];
        if (status <= 0) {
            report.stage = SGConnectionCheckConnection;
            report.reachable = error ? SGConnectionFactNo : SGConnectionFactUnknown;
            report.problem = error ? SGLyricsAIConnectionProblem(error)
                : SGL(@"settings.translation.openai.error.unreachable", @"The translation service could not be reached.");
            report.diagnostic = diagnosticLine(report, status, error, @"sent=yes");
            [self complete:report];
            return;
        }
        // Any HTTP reply, even a refusal, proves the transport reached the service.
        report.reachable = SGConnectionFactYes;
        if (status == 401 || status == 403) {
            report.stage = SGConnectionCheckAuthentication;
            report.authenticated = SGConnectionFactNo;
            report.problem = SGL(@"settings.translation.openai.error.keyinvalid", @"The translation service turned the key down. Check it in Lyrics › Translation & AI.");
        } else if (status == 429 || (status >= 500 && status <= 599)) {
            report.stage = models ? SGConnectionCheckModels : SGConnectionCheckTranslation;
            report.problem = SGL(@"settings.translation.openai.error.busy", @"The translation service is busy right now. Try again in a minute.");
        } else if (error) {
            // HTTP headers prove reachability even if the body was too large, unreadable or interrupted.
            report.stage = models ? SGConnectionCheckModels : SGConnectionCheckTranslation;
            if (!models) report.translated = SGConnectionFactNo;
            report.problem = models
                ? SGL(@"settings.translation.models.error.unreadable", @"The model list could not be read. Enter a model by hand.")
                : SGL(@"settings.translation.openai.error.unreadable", @"The translation service's answer could not be read. Try again.");
        } else if (models) {
            report.stage = SGConnectionCheckModels;
            if (status == 200) {
                id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
                NSArray *list = SGLyricsAIModelsIn(SGLyricsAIOpenAI, root);
                if (list) {
                    report.models = SGConnectionFactYes;
                } else {
                    report.models = SGConnectionFactUnknown;
                    report.problem = SGL(@"settings.translation.models.error.unreadable", @"The model list could not be read. Enter a model by hand.");
                }
            } else if (status == 404 || status == 405) {
                // No model list is not proof that a chat request would fail; say so instead of guessing.
                report.models = SGConnectionFactUnknown;
                report.authenticated = SGConnectionFactUnknown;
                report.problem = SGL(@"settings.translation.openai.test.nomodels", @"This service does not list its models. The connection works; try Test translation to check the model itself.");
            } else {
                report.models = SGConnectionFactNo;
                report.problem = [NSString stringWithFormat:SGL(@"settings.translation.openai.test.modelstatus", @"The model list was refused (%ld). Check the address and model in Lyrics › Translation & AI."), (long)status];
            }
        } else {
            report.stage = SGConnectionCheckTranslation;
            if (status == 200) {
                id root = data && data.length <= 512 * 1024 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
                NSArray *answer = SGOpenAIReplyIn(root, 1, SGLyricsReplyIndexed);
                if (validSample(answer.firstObject)) {
                    report.translated = SGConnectionFactYes;
                } else {
                    report.translated = SGConnectionFactNo;
                    report.problem = SGL(@"settings.translation.openai.error.unreadable", @"The translation service's answer could not be read. Try again.");
                }
            } else if (status == 400 || status == 404 || status == 405) {
                report.translated = SGConnectionFactNo;
                report.models = SGConnectionFactNo;
                report.authenticated = SGConnectionFactUnknown;
                report.problem = SGL(@"settings.translation.openai.error.settings", @"Check the translation service's base URL and model in Lyrics › Translation & AI.");
            } else {
                report.translated = SGConnectionFactNo;
                report.problem = [NSString stringWithFormat:SGL(@"settings.translation.openai.error.status", @"The service did not translate the song (%ld)."), (long)status];
            }
        }
        if (!report.problem && report.translated != SGConnectionFactYes && !(models && report.models == SGConnectionFactYes)) {
            report.problem = SGL(@"settings.translation.openai.error.unreadable", @"The translation service's answer could not be read. Try again.");
        }
        report.diagnostic = diagnosticLine(report, status, error, @"sent=yes");
        [self complete:report];
    };
    self.task = models ? SGLyricsTranslationSendOnceUpTo(self.request, limit, finished)
                       : SGLyricsTranslationSendOnce(self.request, finished);
}
@end
SGTranslationConnectionTest *SGTestOpenAIConnection(SGConnectionTestKind kind, void (^done)(SGTranslationConnectionReport *)) {
    SGTranslationConnectionTest *test = [SGTranslationConnectionTest new];
    test.kind = kind;
    test.done = done;
    [test start];
    return test;
}

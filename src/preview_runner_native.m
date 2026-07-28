#import <AppKit/AppKit.h>

static NSString *const APIKey = @"AIzaSyDYduyE8CvW-Fm5lBwTsV8JrChA_hjs8Qo";
static NSString *const ProjectID = @"bytehelper-c7794";

static id FirestoreValue(id value) {
  if (!value) return @{@"nullValue": [NSNull null]};
  if ([value isKindOfClass:[NSString class]]) return @{@"stringValue": value};
  if ([value isKindOfClass:[NSNumber class]]) return @{@"doubleValue": value};
  if ([value isKindOfClass:[NSDate class]]) {
    NSDateFormatter *fmt = [NSDateFormatter new]; fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; fmt.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0]; fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    return @{@"timestampValue": [fmt stringFromDate:value]};
  }
  if ([value isKindOfClass:[NSDictionary class]]) {
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    for (NSString *key in value) fields[key] = FirestoreValue(value[key]);
    return @{@"mapValue": @{@"fields": fields}};
  }
  return @{@"stringValue": [value description]};
}
static id NativeValue(NSDictionary *value) {
  if (value[@"stringValue"]) return value[@"stringValue"];
  if (value[@"doubleValue"]) return value[@"doubleValue"];
  if (value[@"integerValue"]) return @([value[@"integerValue"] doubleValue]);
  if (value[@"timestampValue"]) return value[@"timestampValue"];
  if (value[@"mapValue"]) { NSMutableDictionary *out = [NSMutableDictionary dictionary]; for (NSString *key in value[@"mapValue"][@"fields"] ?: @{}) out[key] = NativeValue(value[@"mapValue"][@"fields"][key]); return out; }
  return nil;
}
static NSURL *FirestoreURL(NSString *path, NSArray<NSString *> *mask) {
  NSString *base = [NSString stringWithFormat:@"https://firestore.googleapis.com/v1/projects/%@/databases/(default)/documents/%@?key=%@", ProjectID, path, APIKey];
  NSMutableString *url = [base mutableCopy];
  NSCharacterSet *safe = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
  NSCharacterSet *simple = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"];
  for (NSString *field in mask) {
    NSString *fieldPath = ([field rangeOfCharacterFromSet:[simple invertedSet]].location == NSNotFound) ? field : [NSString stringWithFormat:@"`%@`", [field stringByReplacingOccurrencesOfString:@"`" withString:@"\\`"]];
    [url appendFormat:@"&updateMask.fieldPaths=%@", [fieldPath stringByAddingPercentEncodingWithAllowedCharacters:safe]];
  }
  return [NSURL URLWithString:url];
}
static NSDictionary *GetDocument(NSString *path, NSError **outError) {
  dispatch_semaphore_t sem = dispatch_semaphore_create(0); __block NSData *data = nil; __block NSURLResponse *response = nil; __block NSError *error = nil;
  [[[NSURLSession sharedSession] dataTaskWithURL:FirestoreURL(path, @[]) completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) { data=d; response=r; error=e; dispatch_semaphore_signal(sem); }] resume];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER); if (error) { if (outError) *outError = error; return @{}; }
  NSInteger status = [(NSHTTPURLResponse *)response statusCode]; if (status == 404) return @{}; if (status < 200 || status >= 300) { if (outError) *outError = [NSError errorWithDomain:@"Firestore" code:status userInfo:@{NSLocalizedDescriptionKey: [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"Firestore read failed"}]; return @{}; }
  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:outError]; NSMutableDictionary *out = [NSMutableDictionary dictionary]; for (NSString *key in json[@"fields"] ?: @{}) out[key] = NativeValue(json[@"fields"][key]); return out;
}
static BOOL PatchDocument(NSString *path, NSDictionary *payload, NSError **outError) {
  NSMutableDictionary *fields = [NSMutableDictionary dictionary]; for (NSString *key in payload) fields[key] = FirestoreValue(payload[key]);
  NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"fields": fields} options:0 error:outError];
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:FirestoreURL(path, payload.allKeys)]; request.HTTPMethod = @"PATCH"; request.HTTPBody = body; [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
  dispatch_semaphore_t sem = dispatch_semaphore_create(0); __block NSData *data = nil; __block NSURLResponse *response = nil; __block NSError *error = nil;
  [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) { data=d; response=r; error=e; dispatch_semaphore_signal(sem); }] resume];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER); if (error) { if (outError) *outError = error; return NO; }
  NSInteger status = [(NSHTTPURLResponse *)response statusCode]; if (status < 200 || status >= 300) { if (outError) *outError = [NSError errorWithDomain:@"Firestore" code:status userInfo:@{NSLocalizedDescriptionKey: [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"Firestore write failed"}]; return NO; } return YES;
}
static void UpdateHistory(NSString *appName) {
  NSDictionary *doc = GetDocument(@"LatestHistory/History", nil); NSMutableDictionary *hist = [NSMutableDictionary dictionaryWithDictionary:doc[@"hist"] ?: @{}]; NSDate *now = NSDate.date; NSDate *cutoff = [now dateByAddingTimeInterval:-7*24*60*60];
  NSDateFormatter *iso = [NSDateFormatter new]; iso.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; iso.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
  for (NSString *key in [hist.allKeys copy]) { NSDate *date = [iso dateFromString:hist[key][@"timestamp"] ?: @""]; if (!date || [date compare:cutoff] == NSOrderedAscending) [hist removeObjectForKey:key]; }
  NSDateFormatter *tf = [NSDateFormatter new]; tf.dateFormat = @"h:mm a"; NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"MMMM d"; NSString *stamp = [iso stringFromDate:now];
  hist[stamp] = @{@"text": [NSString stringWithFormat:@"%@ was run at %@ on %@", appName, [tf stringFromDate:now], [df stringFromDate:now]], @"timestamp": stamp};
  PatchDocument(@"LatestHistory/History", @{@"hist": hist}, nil);
}
static void SetPercent(NSString *kind, double value) { PatchDocument([NSString stringWithFormat:@"Percent/%@", kind], @{@"%": @(value)}, nil); }

@interface RunnerDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property NSTextView *logView;
@property NSArray<NSString *> *threads;
@property NSMutableDictionary *seen;
@end

@implementation RunnerDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]; self.seen = [NSMutableDictionary dictionary]; self.threads = [self parseThreads]; [self buildWindow]; UpdateHistory(@"Preview Runner"); [NSApp activateIgnoringOtherApps:YES]; [NSTimer scheduledTimerWithTimeInterval:1.5 target:self selector:@selector(poll:) userInfo:nil repeats:YES];
}
- (NSArray *)parseThreads {
  NSArray *args = NSProcessInfo.processInfo.arguments; if ([args containsObject:@"--all"]) return @[@"Thread1", @"Thread2"]; NSUInteger idx = [args indexOfObject:@"--thread"]; if (idx != NSNotFound && idx + 1 < args.count) return @[args[idx+1]]; return @[@"Thread1"];
}
- (void)buildWindow {
  self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(180, 180, 760, 480) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO]; self.window.title = @"Preview Runner";
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 442, 736, 24)]; label.stringValue = [NSString stringWithFormat:@"Watching %@", [self.threads componentsJoinedByString:@", "]]; label.bezeled = NO; label.drawsBackground = NO; label.editable = NO; [self.window.contentView addSubview:label];
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 12, 736, 420)]; self.logView = [[NSTextView alloc] initWithFrame:scroll.bounds]; self.logView.font = [NSFont fontWithName:@"Menlo" size:12]; self.logView.editable = NO; scroll.documentView = self.logView; scroll.hasVerticalScroller = YES; [self.window.contentView addSubview:scroll]; [self.window makeKeyAndOrderFront:nil];
}
- (void)log:(NSString *)message { dispatch_async(dispatch_get_main_queue(), ^{ self.logView.string = [self.logView.string stringByAppendingFormat:@"[%@] %@\n", [NSDateFormatter localizedStringFromDate:NSDate.date dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle], message]; [self.logView scrollRangeToVisible:NSMakeRange(self.logView.string.length, 0)]; }); }
- (NSString *)stripPreviewBlocks:(NSString *)source {
  NSMutableString *out = [NSMutableString string]; NSArray *lines = [source componentsSeparatedByString:@"\n"]; BOOL skipping = NO; NSInteger depth = 0;
  for (NSString *line in lines) {
    if (!skipping && [line rangeOfString:@"#Preview"].location != NSNotFound) { skipping = YES; depth = 0; }
    if (skipping) {
      for (NSUInteger i=0; i<line.length; i++) { unichar c=[line characterAtIndex:i]; if (c=='{') depth++; if (c=='}') depth--; }
      if (depth <= 0 && [line rangeOfString:@"}"].location != NSNotFound) skipping = NO;
      continue;
    }
    [out appendFormat:@"%@\n", line];
  }
  return out;
}
- (NSDictionary *)compileAndValidate:(NSString *)source appName:(NSString *)appName {
  SetPercent(@"Compile", 3);
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"swiftui-preview-%@", NSUUID.UUID.UUIDString]]; [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *sourcePath = [dir stringByAppendingPathComponent:@"Preview.swift"]; NSString *exe = [dir stringByAppendingPathComponent:@"PreviewApp"]; NSString *cache = [dir stringByAppendingPathComponent:@"module-cache"]; [[NSFileManager defaultManager] createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:nil];
  SetPercent(@"Compile", 8);
  NSString *stripped = [self stripPreviewBlocks:source];
  SetPercent(@"Compile", 14);
  NSString *hosted = [stripped stringByAppendingString:@"\n\n@main\nstruct PreviewHostApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}\n"];
  [hosted writeToFile:sourcePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
  SetPercent(@"Compile", 22);
  NSTask *compile = [NSTask new]; compile.launchPath = @"/usr/bin/swiftc"; compile.arguments = @[@"-parse-as-library", @"-module-cache-path", cache, sourcePath, @"-o", exe]; NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy]; env[@"CLANG_MODULE_CACHE_PATH"] = cache; compile.environment = env;
  NSPipe *outPipe = [NSPipe pipe]; NSPipe *errPipe = [NSPipe pipe]; compile.standardOutput = outPipe; compile.standardError = errPipe; NSDate *start = NSDate.date; [compile launch];
  SetPercent(@"Compile", 30);
  double lastReported = 30;
  while (compile.isRunning && [NSDate.date timeIntervalSinceDate:start] < 75) {
    double elapsed = [NSDate.date timeIntervalSinceDate:start];
    double next = MIN(94, 30 + (elapsed / 75.0) * 64.0);
    if (next - lastReported >= 2) { SetPercent(@"Compile", next); lastReported = next; }
    [NSThread sleepForTimeInterval:0.15];
  }
  if (compile.isRunning) { [compile terminate]; SetPercent(@"Compile", 100); return @{@"ok": @NO, @"preview": @"SwiftUI compile timed out.", @"error": @""}; }
  NSString *compilerOut = [[NSString alloc] initWithData:[outPipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding] ?: @"";
  NSString *compilerErr = [[NSString alloc] initWithData:[errPipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding] ?: @"";
  if (compile.terminationStatus != 0) { SetPercent(@"Compile", 100); return @{@"ok": @NO, @"preview": compilerOut.length ? compilerOut : @"SwiftUI compile failed.", @"error": compilerErr}; }
  SetPercent(@"Compile", 100);
  return @{@"ok": @YES, @"preview": @"Ready for preview", @"error": @""};
}
- (void)poll:(NSTimer *)timer {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    for (NSString *thread in self.threads) {
      NSError *error = nil; NSDictionary *remote = GetDocument([NSString stringWithFormat:@"Threads/%@", thread], &error); if (error) { [self log:[NSString stringWithFormat:@"%@: %@", thread, error.localizedDescription]]; continue; }
      NSString *requestID = remote[@"requestId"]; NSString *source = remote[@"send"]; if (!requestID.length || !source.length || [self.seen[thread] isEqualToString:requestID]) continue; self.seen[thread] = requestID;
      NSString *appName = remote[@"appName"] ?: @"SwiftUI App"; [self log:[NSString stringWithFormat:@"%@: compiling raw SwiftUI source for %@", thread, appName]]; PatchDocument([NSString stringWithFormat:@"Threads/%@", thread], @{@"status": @"running", @"startedAt": NSDate.date}, nil);
      NSDictionary *result = [self compileAndValidate:source appName:appName]; BOOL ok = [result[@"ok"] boolValue];
      PatchDocument([NSString stringWithFormat:@"Threads/%@", thread], @{@"status": ok ? @"complete" : @"error", @"preview": result[@"preview"] ?: @"", @"error": result[@"error"] ?: @"", @"completedAt": NSDate.date}, nil); if (ok) UpdateHistory(appName); [self log:[NSString stringWithFormat:@"%@: %@", thread, ok ? @"complete" : @"error"]];
    }
  });
}
@end

int main(int argc, const char *argv[]) {
  if (argc > 1 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"))) {
    puts("Preview Runner\n\nUsage:\n  ~/cmds/preview_runner [--thread Thread1]\n  ~/cmds/preview_runner --all\n\nNative NSApplication runner. Silently compiles raw SwiftUI source with swiftc and writes status back to Firestore.");
    return 0;
  }
  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    RunnerDelegate *delegate = [RunnerDelegate new];
    app.delegate = delegate;
    [app run];
  }
  return 0;
}

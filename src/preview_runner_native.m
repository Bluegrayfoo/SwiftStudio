#import <AppKit/AppKit.h>
#import <float.h>
#import <math.h>

static NSString *const APIKey = @"AIzaSyDYduyE8CvW-Fm5lBwTsV8JrChA_hjs8Qo";
static NSString *const ProjectID = @"bytehelper-c7794";

static NSColor *Blue(void) { return [NSColor colorWithCalibratedRed:0.02 green:0.18 blue:1.0 alpha:1.0]; }
static NSColor *DarkRow(void) { return [NSColor colorWithCalibratedWhite:0.27 alpha:1.0]; }
static NSFont *TitleFont(CGFloat size) { return [NSFont fontWithName:@"Georgia-Bold" size:size] ?: [NSFont boldSystemFontOfSize:size]; }
static NSFont *MonoFont(CGFloat size) { return [NSFont fontWithName:@"Menlo-Bold" size:size] ?: [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightBold]; }

static id FirestoreValue(id value) {
  if (!value) return @{@"nullValue": [NSNull null]};
  if ([value isKindOfClass:[NSString class]]) return @{@"stringValue": value};
  if ([value isKindOfClass:[NSNumber class]] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return @{@"booleanValue": value};
  if ([value isKindOfClass:[NSNumber class]]) return @{@"doubleValue": value};
  if ([value isKindOfClass:[NSDate class]]) {
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
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
  if (value[@"booleanValue"]) return value[@"booleanValue"];
  if (value[@"doubleValue"]) return value[@"doubleValue"];
  if (value[@"integerValue"]) return @([value[@"integerValue"] doubleValue]);
  if (value[@"timestampValue"]) return value[@"timestampValue"];
  if (value[@"mapValue"]) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSDictionary *fields = value[@"mapValue"][@"fields"] ?: @{};
    for (NSString *key in fields) out[key] = NativeValue(fields[key]);
    return out;
  }
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
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  __block NSData *data = nil;
  __block NSURLResponse *response = nil;
  __block NSError *error = nil;
  [[[NSURLSession sharedSession] dataTaskWithURL:FirestoreURL(path, @[]) completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
    data = d; response = r; error = e; dispatch_semaphore_signal(sem);
  }] resume];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
  if (error) { if (outError) *outError = error; return @{}; }
  NSInteger status = [(NSHTTPURLResponse *)response statusCode];
  if (status == 404) return @{};
  if (status < 200 || status >= 300) {
    if (outError) *outError = [NSError errorWithDomain:@"Firestore" code:status userInfo:@{NSLocalizedDescriptionKey: [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"Firestore read failed"}];
    return @{};
  }
  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:outError];
  NSMutableDictionary *out = [NSMutableDictionary dictionary];
  for (NSString *key in json[@"fields"] ?: @{}) out[key] = NativeValue(json[@"fields"][key]);
  return out;
}

static BOOL PatchDocument(NSString *path, NSDictionary *payload, NSError **outError) {
  NSMutableDictionary *fields = [NSMutableDictionary dictionary];
  for (NSString *key in payload) fields[key] = FirestoreValue(payload[key]);
  NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"fields": fields} options:0 error:outError];
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:FirestoreURL(path, payload.allKeys)];
  request.HTTPMethod = @"PATCH";
  request.HTTPBody = body;
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  __block NSData *data = nil;
  __block NSURLResponse *response = nil;
  __block NSError *error = nil;
  [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
    data = d; response = r; error = e; dispatch_semaphore_signal(sem);
  }] resume];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
  if (error) { if (outError) *outError = error; return NO; }
  NSInteger status = [(NSHTTPURLResponse *)response statusCode];
  if (status < 200 || status >= 300) {
    if (outError) *outError = [NSError errorWithDomain:@"Firestore" code:status userInfo:@{NSLocalizedDescriptionKey: [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"Firestore write failed"}];
    return NO;
  }
  return YES;
}

static void SetPercent(NSString *kind, double value) {
  static NSMutableDictionary *lastValues = nil;
  static NSMutableDictionary *lastTimes = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    lastValues = [NSMutableDictionary dictionary];
    lastTimes = [NSMutableDictionary dictionary];
  });
  @synchronized (lastValues) {
    NSNumber *lastValueNumber = lastValues[kind];
    NSDate *lastTime = lastTimes[kind];
    double lastValue = lastValueNumber ? lastValueNumber.doubleValue : -1000.0;
    NSTimeInterval age = lastTime ? -lastTime.timeIntervalSinceNow : DBL_MAX;
    BOOL importantEdge = value <= 1.0 || value >= 100.0 || !lastValueNumber;
    if (!importantEdge && fabs(value - lastValue) < 5.0 && age < 1.5) return;
    lastValues[kind] = @(value);
    lastTimes[kind] = NSDate.date;
  }
  PatchDocument([NSString stringWithFormat:@"Percent/%@", kind], @{@"%": @(value)}, nil);
}

static void UpdateHistory(NSString *appName) {
  NSDictionary *doc = GetDocument(@"LatestHistory/History", nil);
  NSMutableDictionary *hist = [NSMutableDictionary dictionaryWithDictionary:doc[@"hist"] ?: @{}];
  NSDate *now = NSDate.date;
  NSDate *cutoff = [now dateByAddingTimeInterval:-7 * 24 * 60 * 60];
  NSDateFormatter *iso = [NSDateFormatter new];
  iso.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
  iso.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
  for (NSString *key in [hist.allKeys copy]) {
    NSDate *date = [iso dateFromString:hist[key][@"timestamp"] ?: @""];
    if (!date || [date compare:cutoff] == NSOrderedAscending) [hist removeObjectForKey:key];
  }
  NSDateFormatter *tf = [NSDateFormatter new]; tf.dateFormat = @"h:mm a";
  NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"MMMM d";
  NSString *stamp = [iso stringFromDate:now];
  hist[stamp] = @{@"text": [NSString stringWithFormat:@"%@ was run at %@ on %@", appName, [tf stringFromDate:now], [df stringFromDate:now]], @"timestamp": stamp};
  PatchDocument(@"LatestHistory/History", @{@"hist": hist}, nil);
}

static NSString *StripPreviewBlocks(NSString *source) {
  NSMutableString *out = [NSMutableString string];
  NSArray *lines = [source componentsSeparatedByString:@"\n"];
  BOOL skipping = NO;
  NSInteger depth = 0;
  for (NSString *line in lines) {
    if (!skipping && [line rangeOfString:@"#Preview"].location != NSNotFound) { skipping = YES; depth = 0; }
    if (skipping) {
      for (NSUInteger i = 0; i < line.length; i++) {
        unichar c = [line characterAtIndex:i];
        if (c == '{') depth++;
        if (c == '}') depth--;
      }
      if (depth <= 0 && [line rangeOfString:@"}"].location != NSNotFound) skipping = NO;
      continue;
    }
    [out appendFormat:@"%@\n", line];
  }
  return out;
}

static NSDictionary *RunBuildTask(NSArray<NSString *> *arguments, NSString *cache, NSTimeInterval timeout, double progressStart, double progressEnd) {
  NSTask *task = [NSTask new];
  task.launchPath = arguments.firstObject;
  task.arguments = [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)];
  NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
  env[@"CLANG_MODULE_CACHE_PATH"] = cache;
  task.environment = env;
  NSPipe *outPipe = [NSPipe pipe];
  NSPipe *errPipe = [NSPipe pipe];
  task.standardOutput = outPipe;
  task.standardError = errPipe;
  NSDate *start = NSDate.date;
  [task launch];
  double lastReported = progressStart;
  SetPercent(@"Compile", progressStart);
  while (task.isRunning && [NSDate.date timeIntervalSinceDate:start] < timeout) {
    double elapsed = [NSDate.date timeIntervalSinceDate:start];
    double next = MIN(progressEnd, progressStart + (elapsed / timeout) * (progressEnd - progressStart));
    if (next - lastReported >= 2) { SetPercent(@"Compile", next); lastReported = next; }
    [NSThread sleepForTimeInterval:0.15];
  }
  if (task.isRunning) {
    [task terminate];
    return @{@"ok": @NO, @"out": @"", @"err": @"SwiftUI compile timed out."};
  }
  NSString *out = [[NSString alloc] initWithData:[outPipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding] ?: @"";
  NSString *err = [[NSString alloc] initWithData:[errPipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding] ?: @"";
  return @{@"ok": @(task.terminationStatus == 0), @"out": out, @"err": err};
}

static NSDictionary *CompileExecutable(NSString *source, NSString *requestID, NSString *previewArch) {
  SetPercent(@"Compile", 3);
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"swiftstudio-compile-%@", NSUUID.UUID.UUIDString]];
  [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *sourcePath = [dir stringByAppendingPathComponent:@"Preview.swift"];
  NSString *safeID = [[requestID componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@"-"];
  NSString *exeName = [NSString stringWithFormat:@"SwiftStudioPreview-%@.dylib", safeID];
  NSString *exePath = [dir stringByAppendingPathComponent:exeName];
  BOOL requestedX86 = [previewArch isEqualToString:@"x86_64"];
  BOOL requestedArm = [previewArch isEqualToString:@"arm64"];
  if (!requestedX86 && !requestedArm) previewArch = @"universal";
  NSString *cacheRoot = [@"~/cmds/.swiftstudio-module-cache" stringByExpandingTildeInPath];
  NSString *cache = [cacheRoot stringByAppendingPathComponent:previewArch];
  [[NSFileManager defaultManager] createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:nil];
  SetPercent(@"Compile", 10);
  NSString *hosted = [NSString stringWithFormat:@"import SwiftUI\nimport AppKit\n%@\n\n@_cdecl(\"SwiftStudioCreatePreviewView\")\npublic func SwiftStudioCreatePreviewView() -> UnsafeMutableRawPointer {\n    let view = NSHostingView(rootView: ContentView())\n    view.wantsLayer = true\n    view.layer?.backgroundColor = NSColor.black.cgColor\n    return Unmanaged.passRetained(view).toOpaque()\n}\n", StripPreviewBlocks(source)];
  [hosted writeToFile:sourcePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
  SetPercent(@"Compile", 22);
  NSMutableArray<NSString *> *archs = [NSMutableArray array];
  if (requestedX86) [archs addObject:@"x86_64"];
  else if (requestedArm) [archs addObject:@"arm64"];
  else [archs addObjectsFromArray:@[@"x86_64", @"arm64"]];
  NSMutableArray<NSString *> *slicePaths = [NSMutableArray array];
  NSMutableString *allOut = [NSMutableString string];
  NSMutableString *allErr = [NSMutableString string];
  for (NSUInteger i = 0; i < archs.count; i++) {
    NSString *arch = archs[i];
    NSString *target = [arch isEqualToString:@"x86_64"] ? @"x86_64-apple-macos12.0" : @"arm64-apple-macos12.0";
    NSString *archCache = [cacheRoot stringByAppendingPathComponent:arch];
    [[NSFileManager defaultManager] createDirectoryAtPath:archCache withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *slicePath = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.dylib", safeID, arch]];
    double startProgress = 30 + ((double)i / MAX(1.0, (double)archs.count)) * 56.0;
    double endProgress = 30 + (((double)i + 1.0) / MAX(1.0, (double)archs.count)) * 56.0;
    NSDictionary *slice = RunBuildTask(@[@"/usr/bin/swiftc", @"-emit-library", @"-parse-as-library", @"-target", target, @"-module-cache-path", archCache, sourcePath, @"-o", slicePath], archCache, 75, startProgress, endProgress);
    [allOut appendString:slice[@"out"] ?: @""];
    [allErr appendString:slice[@"err"] ?: @""];
    if (![slice[@"ok"] boolValue]) {
      SetPercent(@"Compile", 100);
      return @{@"ok": @NO, @"preview": allOut.length ? allOut : @"SwiftUI compile failed.", @"error": allErr};
    }
    [slicePaths addObject:slicePath];
  }
  if (slicePaths.count == 1) {
    [[NSFileManager defaultManager] moveItemAtPath:slicePaths.firstObject toPath:exePath error:nil];
  } else {
    NSMutableArray<NSString *> *lipoArgs = [NSMutableArray arrayWithArray:@[@"/usr/bin/lipo", @"-create"]];
    [lipoArgs addObjectsFromArray:slicePaths];
    [lipoArgs addObjectsFromArray:@[@"-output", exePath]];
    NSDictionary *lipo = RunBuildTask(lipoArgs, cache, 20, 88, 96);
    if (![lipo[@"ok"] boolValue]) {
      SetPercent(@"Compile", 100);
      return @{@"ok": @NO, @"preview": lipo[@"out"] ?: @"Could not combine preview library architectures.", @"error": lipo[@"err"] ?: @""};
    }
  }
  SetPercent(@"Compile", 100);
  return @{@"ok": @YES, @"preview": @"Compiled preview library for Studio", @"error": @"", @"executablePath": exePath, @"executableName": exeName};
}

static BOOL ContainsRegex(NSString *text, NSString *pattern) {
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
  return [regex firstMatchInString:text ?: @"" options:0 range:NSMakeRange(0, (text ?: @"").length)] != nil;
}

static NSString *RunFishySyntaxSummary(NSString *source) {
  NSString *helper = [@"~/cmds/fishy_syntax" stringByExpandingTildeInPath];
  if (![NSFileManager.defaultManager isExecutableFileAtPath:helper]) return @"";
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"swiftstudio-fish-suggest-%@", NSUUID.UUID.UUIDString]];
  [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *path = [dir stringByAppendingPathComponent:@"ContentView.swift"];
  [source writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
  NSTask *task = [NSTask new]; task.launchPath = helper; task.arguments = @[path];
  NSPipe *pipe = [NSPipe pipe]; task.standardOutput = pipe; task.standardError = pipe;
  @try { [task launch]; [task waitUntilExit]; } @catch (NSException *exception) { [NSFileManager.defaultManager removeItemAtPath:dir error:nil]; return @""; }
  NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
  [NSFileManager.defaultManager removeItemAtPath:dir error:nil];
  NSDictionary *json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  if (![json isKindOfClass:NSDictionary.class]) return @"";
  NSArray *diagnostics = [json[@"diagnostics"] isKindOfClass:NSArray.class] ? json[@"diagnostics"] : @[];
  if (!diagnostics.count) return @"SwiftSyntax parsed this file cleanly.";
  NSMutableArray *out = [NSMutableArray array];
  NSUInteger limit = MIN((NSUInteger)3, diagnostics.count);
  for (NSUInteger i = 0; i < limit; i++) {
    NSDictionary *diag = diagnostics[i];
    if (![diag isKindOfClass:NSDictionary.class]) continue;
    [out addObject:[NSString stringWithFormat:@"Line %@:%@ %@", diag[@"line"] ?: @0, diag[@"column"] ?: @0, diag[@"message"] ?: @"parser issue"]];
  }
  return [out componentsJoinedByString:@"\n"];
}

static NSString *FishySuggestionsForSource(NSString *source, NSString *fileName) {
  NSMutableArray<NSString *> *tips = [NSMutableArray array];
  NSString *syntax = RunFishySyntaxSummary(source);
  if (syntax.length) [tips addObject:syntax];
  if ([source containsString:@"!"]) [tips addObject:@"Avoid force-unwraps when optional binding or a default value would work."];
  if (ContainsRegex(source, @"while\\s+(true|1)\\b")) [tips addObject:@"Avoid while true loops unless they have a clear cancellation path."];
  NSArray *lines = [source componentsSeparatedByString:@"\n"];
  NSUInteger longLines = 0, vars = 0, states = 0;
  NSMutableDictionary<NSString *, NSNumber *> *lineCounts = [NSMutableDictionary dictionary];
  for (NSString *line in lines) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (line.length > 110) longLines++;
    if ([trimmed hasPrefix:@"var "]) vars++;
    if ([trimmed containsString:@"@State"]) states++;
    if (trimmed.length) lineCounts[trimmed] = @([lineCounts[trimmed] integerValue] + 1);
  }
  if (longLines) [tips addObject:@"Split very long lines so the view is easier to scan."];
  if (vars >= 3) [tips addObject:@"Check whether some var values can be let constants or computed from one source of truth."];
  if (states >= 3) [tips addObject:@"You may be able to combine related @State values into one small model value."];
  for (NSString *line in lineCounts) {
    if ([lineCounts[line] integerValue] >= 3 && ([line hasPrefix:@"Text("] || [line hasPrefix:@"Image("] || [line hasPrefix:@"Button("])) {
      [tips addObject:@"Repeated SwiftUI rows could become a small reusable view or a ForEach."];
      break;
    }
  }
  if (!tips.count) [tips addObject:@"No major style or efficiency issues jumped out."];
  return [NSString stringWithFormat:@"🐠: Suggestions for %@\n- %@", fileName ?: @"ContentView", [tips componentsJoinedByString:@"\n- "]];
}

static NSDictionary *UploadExecutableChunks(NSString *thread, NSString *requestID, NSString *exePath, NSString *exeName, NSError **outError) {
  SetPercent(@"Run", 5);
  NSData *data = [NSData dataWithContentsOfFile:exePath options:0 error:outError];
  if (!data) return nil;
  NSString *base64 = [data base64EncodedStringWithOptions:0];
  NSUInteger chunkSize = 900000;
  NSUInteger count = (base64.length + chunkSize - 1) / chunkSize;
  for (NSUInteger i = 0; i < count; i++) {
    NSUInteger start = i * chunkSize;
    NSUInteger length = MIN(chunkSize, base64.length - start);
    NSString *chunk = [base64 substringWithRange:NSMakeRange(start, length)];
    NSString *chunkPath = [NSString stringWithFormat:@"Threads/%@/Compiled/%@-%04lu", thread, requestID, (unsigned long)i];
    BOOL ok = PatchDocument(chunkPath, @{@"requestId": requestID, @"index": @(i), @"data": chunk}, outError);
    if (!ok) return nil;
    double uploadProgress = 5.0 + (((double)i + 1.0) / MAX(1.0, (double)count)) * 39.0;
    SetPercent(@"Run", uploadProgress);
  }
  return @{
    @"compiledRequestId": requestID,
    @"compiledChunkCount": @(count),
    @"compiledSize": @(data.length),
    @"compiledExecutableName": exeName ?: [NSString stringWithFormat:@"SwiftStudioPreview-%@", requestID],
    @"compiledAt": NSDate.date
  };
}

static NSArray<NSString *> *ParseThreads(int argc, const char *argv[]) {
  NSMutableArray *args = [NSMutableArray array];
  for (int i = 0; i < argc; i++) [args addObject:[NSString stringWithUTF8String:argv[i]]];
  if ([args containsObject:@"--all"]) return @[@"Thread1", @"Thread2"];
  NSUInteger idx = [args indexOfObject:@"--thread"];
  if (idx != NSNotFound && idx + 1 < args.count) return @[args[idx + 1]];
  return @[@"Thread1"];
}

@interface RunnerDelegate : NSObject <NSApplicationDelegate, NSTextViewDelegate>
@property NSWindow *window;
@property NSView *root;
@property NSMutableArray<NSView *> *dynamicViews;
@property NSTextView *logView;
@property NSMutableString *logText;
@property NSArray<NSString *> *threads;
@property NSMutableDictionary *seen;
@property NSString *lastIncomingShareID;
@property NSMutableDictionary *incomingProject;
@property NSMutableDictionary *store;
@property NSString *activeProjectID;
@property NSString *activeFileID;
@property NSMutableDictionary *editingProject;
@property BOOL editingSharedProject;
@property NSTextView *editor;
@property NSMutableDictionary<NSString *, NSButton *> *projectRows;
@property BOOL applyingHighlight;
@property NSImage *swiftLogo;
@property NSString *runnerNoticeText;
@property BOOL runnerNoticeRed;
@property NSString *screenMode;
@property NSString *lastFishRequestID;
@end

@implementation RunnerDelegate
- (NSString *)docsPath { return [@"~/cmds/swift_studio_projects.json" stringByExpandingTildeInPath]; }
- (void)applicationDidFinishLaunching:(NSNotification *)n {
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  self.dynamicViews = [NSMutableArray array];
  self.logText = [NSMutableString string];
  self.seen = [NSMutableDictionary dictionary];
  self.projectRows = [NSMutableDictionary dictionary];
  self.swiftLogo = [[NSImage alloc] initWithContentsOfFile:[@"~/cmds/swiftlogo.png" stringByExpandingTildeInPath]];
  [self buildWindow];
  [self showLog];
  UpdateHistory(@"Preview Runner");
  [self appendLog:[NSString stringWithFormat:@"Watching %@", [self.threads componentsJoinedByString:@", "]]];
  [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(checkProjectShare:) userInfo:nil repeats:YES];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [self watchThreads]; });
  [NSApp activateIgnoringOtherApps:YES];
}
- (void)buildWindow {
  self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(120,100,1050,690) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  self.window.title = @"Preview Runner";
  self.root = [[NSView alloc] initWithFrame:self.window.contentView.bounds];
  self.root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.root.wantsLayer = YES;
  self.root.layer.backgroundColor = NSColor.blackColor.CGColor;
  self.window.contentView = self.root;
  [self.window makeKeyAndOrderFront:nil];
}
- (void)clearDynamic { for (NSView *view in self.dynamicViews) [view removeFromSuperview]; [self.dynamicViews removeAllObjects]; }
- (NSTextField *)label:(NSString *)text frame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color {
  NSTextField *f = [[NSTextField alloc] initWithFrame:frame]; f.stringValue = text ?: @""; f.font = font; f.textColor = color; f.bezeled = NO; f.drawsBackground = NO; f.editable = NO; f.selectable = NO; [self.dynamicViews addObject:f]; [self.root addSubview:f]; return f;
}
- (NSButton *)button:(NSString *)title frame:(NSRect)frame action:(SEL)action blue:(BOOL)blue {
  NSButton *b = [[NSButton alloc] initWithFrame:frame]; b.title = title; b.font = TitleFont(frame.size.height * 0.48); b.bezelStyle = NSBezelStyleRegularSquare; b.bordered = NO; b.target = self; b.action = action; b.wantsLayer = YES; b.layer.cornerRadius = frame.size.height / 2; b.layer.backgroundColor = (blue ? Blue() : DarkRow()).CGColor; [b setContentTintColor:NSColor.whiteColor]; [self.dynamicViews addObject:b]; [self.root addSubview:b]; return b;
}
- (NSButton *)redButton:(NSString *)title frame:(NSRect)frame action:(SEL)action {
  NSButton *b = [self button:title frame:frame action:action blue:NO];
  b.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.70 green:0.06 blue:0.06 alpha:1.0].CGColor;
  return b;
}
- (void)addLine:(NSRect)frame { NSBox *box = [[NSBox alloc] initWithFrame:frame]; box.boxType = NSBoxCustom; box.borderColor = NSColor.whiteColor; box.fillColor = NSColor.whiteColor; [self.dynamicViews addObject:box]; [self.root addSubview:box]; }
- (void)tuneScrollView:(NSScrollView *)scrollView { scrollView.hasVerticalScroller = YES; scrollView.autohidesScrollers = NO; scrollView.verticalLineScroll = 10; scrollView.verticalPageScroll = 80; scrollView.scrollerStyle = NSScrollerStyleOverlay; }
- (void)addSharedProjectNoticeIfNeeded {
  if (!self.incomingProject && !self.runnerNoticeText.length) return;
  NSRect b = self.root.bounds;
  CGFloat w = self.incomingProject ? 440 : 260, h = 66, x = MAX(18, (b.size.width - w) / 2), y = MAX(76, b.size.height - 158);
  NSView *card = [[NSView alloc] initWithFrame:NSMakeRect(x, y, w, h)];
  card.wantsLayer = YES;
  card.layer.backgroundColor = (self.runnerNoticeRed ? [NSColor colorWithCalibratedRed:0.62 green:0.04 blue:0.04 alpha:0.97] : [NSColor colorWithCalibratedWhite:0.28 alpha:0.96]).CGColor;
  card.layer.cornerRadius = 12;
  card.layer.borderColor = [NSColor colorWithCalibratedWhite:0.55 alpha:1.0].CGColor;
  card.layer.borderWidth = 1;
  NSTextField *message = [[NSTextField alloc] initWithFrame:NSMakeRect(18, 17, self.incomingProject ? w - 226 : w - 36, 32)];
  message.stringValue = self.runnerNoticeText.length ? self.runnerNoticeText : @"Project shared";
  message.font = TitleFont(22);
  message.textColor = NSColor.whiteColor;
  message.bezeled = NO;
  message.drawsBackground = NO;
  message.editable = NO;
  message.selectable = NO;
  [card addSubview:message];
  if (self.incomingProject) {
    NSButton *decline = [[NSButton alloc] initWithFrame:NSMakeRect(w - 204, 14, 86, 38)];
    decline.title = @"Decline";
    decline.font = TitleFont(18);
    decline.bezelStyle = NSBezelStyleRegularSquare;
    decline.bordered = NO;
    decline.target = self;
    decline.action = @selector(declineIncomingProject:);
    decline.wantsLayer = YES;
    decline.layer.cornerRadius = 19;
    decline.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.70 green:0.06 blue:0.06 alpha:1.0].CGColor;
    [decline setContentTintColor:NSColor.whiteColor];
    [card addSubview:decline];
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(w - 106, 14, 86, 38)];
    button.title = @"Accept";
    button.font = TitleFont(20);
    button.bezelStyle = NSBezelStyleRegularSquare;
    button.bordered = NO;
    button.target = self;
    button.action = @selector(openIncomingProject:);
    button.wantsLayer = YES;
    button.layer.cornerRadius = 19;
    button.layer.backgroundColor = Blue().CGColor;
    [button setContentTintColor:NSColor.whiteColor];
    [card addSubview:button];
  }
  [self.dynamicViews addObject:card];
  [self.root addSubview:card positioned:NSWindowAbove relativeTo:nil];
}
- (void)appendLog:(NSString *)line {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self.logText) self.logText = [NSMutableString string];
    if (line.length) [self.logText appendFormat:@"%@\n", line];
    if (self.logView) { self.logView.string = self.logText; [self.logView scrollRangeToVisible:NSMakeRange(self.logView.string.length, 0)]; }
  });
}
- (void)showLog {
  self.screenMode = @"log"; [self clearDynamic]; self.editor = nil; NSRect b = self.root.bounds;
  [self label:@"Preview Runner" frame:NSMakeRect(0,b.size.height-78,b.size.width,60) font:TitleFont(42) color:NSColor.whiteColor].alignment = NSTextAlignmentCenter;
  [self button:@"Enter studio" frame:NSMakeRect(18,b.size.height-62,170,42) action:@selector(enterStudio:) blue:YES];
  [self addLine:NSMakeRect(0,b.size.height-86,b.size.width,2)];
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(18,18,b.size.width-36,b.size.height-170)];
  scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; scroll.hasVerticalScroller = YES; scroll.autohidesScrollers = NO; scroll.verticalLineScroll = 10; scroll.verticalPageScroll = 80; scroll.wantsLayer = YES; scroll.layer.backgroundColor = NSColor.blackColor.CGColor;
  self.logView = [[NSTextView alloc] initWithFrame:scroll.bounds]; self.logView.font = MonoFont(18); self.logView.textColor = NSColor.whiteColor; self.logView.backgroundColor = NSColor.blackColor; self.logView.editable = NO; self.logView.string = self.logText ?: @"";
  scroll.documentView = self.logView; [self.dynamicViews addObject:scroll]; [self.root addSubview:scroll];
  [self addSharedProjectNoticeIfNeeded];
}
- (void)checkProjectShare:(id)sender {
  NSError *error = nil; NSDictionary *doc = GetDocument(@"Threads/ProjectShare", &error);
  if (error || ![doc[@"status"] isEqualToString:@"project_shared"]) return;
  NSString *requestID = doc[@"requestId"]; NSDictionary *project = doc[@"project"];
  if (!requestID.length || !project || [requestID isEqualToString:self.lastIncomingShareID]) return;
  self.lastIncomingShareID = requestID; self.incomingProject = [project mutableCopy];
  self.runnerNoticeText = @"Project shared";
  self.runnerNoticeRed = NO;
  PatchDocument(@"Threads/ProjectShare", @{@"status":@"", @"requestId":requestID, @"project":@{}, @"clearedAt":NSDate.date}, nil);
  [self redrawCurrentScreen];
}
- (void)checkFishRequest {
  NSError *error = nil;
  NSDictionary *doc = GetDocument(@"Threads/Fishy", &error);
  if (error) { [self appendLog:[NSString stringWithFormat:@"Fishy request read failed: %@", error.localizedDescription]]; return; }
  NSString *requestID = doc[@"requestId"] ?: @"";
  NSString *status = doc[@"status"] ?: @"";
  if (!requestID.length || ![status isEqualToString:@"queued"] || [self.lastFishRequestID isEqualToString:requestID]) return;
  self.lastFishRequestID = requestID;
  NSString *fileName = doc[@"fileName"] ?: @"ContentView";
  [self appendLog:[NSString stringWithFormat:@"Fishy: suggesting for %@", fileName]];
  PatchDocument(@"Threads/Fishy", @{@"status":@"running", @"startedAt":NSDate.date}, nil);
  NSString *result = FishySuggestionsForSource(doc[@"source"] ?: @"", fileName);
  PatchDocument(@"Threads/Fishy", @{@"status":@"complete", @"requestId":requestID, @"result":result, @"error":@"", @"completedAt":NSDate.date}, nil);
  [self appendLog:@"Fishy: suggestions complete"];
}
- (void)redrawCurrentScreen {
  if ([self.screenMode isEqualToString:@"editor"] && self.editingProject) [self showEditorWithPreview:!self.editingSharedProject];
  else if ([self.screenMode isEqualToString:@"projects"]) [self showProjectsPage];
  else [self showLog];
}
- (void)loadStore {
  NSData *data = [NSData dataWithContentsOfFile:self.docsPath];
  if (data) self.store = [[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] mutableCopy];
  if (!self.store) self.store = [@{@"activeProject":@"", @"projects":[NSMutableDictionary dictionary]} mutableCopy];
  if (![self.store[@"projects"] count]) {
    self.store[@"projects"][@"myapp"] = [@{@"name":@"MyApp", @"updatedAt":@(NSDate.date.timeIntervalSince1970), @"activeFile":@"ContentView", @"files":[@{@"ContentView":[@{@"name":@"ContentView", @"code":@"import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        Text(\"Hello\")\n    }\n}\n\n#Preview {\n    ContentView()\n}\n"} mutableCopy]} mutableCopy]} mutableCopy];
    self.store[@"activeProject"] = @"myapp";
  }
  self.activeProjectID = self.store[@"activeProject"] ?: [[self.store[@"projects"] allKeys] firstObject];
}
- (void)saveStore { NSData *data = [NSJSONSerialization dataWithJSONObject:self.store options:NSJSONWritingPrettyPrinted error:nil]; [data writeToFile:self.docsPath atomically:YES]; }
- (NSArray *)projectIDs { return [[self.store[@"projects"] allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]; }
- (NSArray *)fileIDsForProject:(NSDictionary *)project { return [[project[@"files"] allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]; }
- (NSMutableDictionary *)activeLocalProject { return self.store[@"projects"][self.activeProjectID]; }
- (NSMutableDictionary *)currentFile { return self.editingProject[@"files"][self.activeFileID]; }
- (void)enterStudio:(id)sender { [self loadStore]; [self showProjectsPage]; }
- (void)showProjectsPage {
  self.screenMode = @"projects"; [self clearDynamic]; [self.projectRows removeAllObjects]; self.editor = nil; self.editingProject = nil; NSRect b = self.root.bounds;
  [self label:@"SwiftStudio" frame:NSMakeRect(0,b.size.height-82,b.size.width,64) font:TitleFont(48) color:NSColor.whiteColor].alignment = NSTextAlignmentCenter;
  [self addLine:NSMakeRect(0,b.size.height-92,b.size.width,2)];
  [self button:@"Back to log" frame:NSMakeRect(18,b.size.height-70,156,42) action:@selector(backToLogButton:) blue:YES];
  CGFloat y = b.size.height - 178;
  for (NSString *pid in self.projectIDs) {
    NSDictionary *p = self.store[@"projects"][pid]; BOOL selected = [pid isEqualToString:self.activeProjectID];
    NSButton *row = [self button:@"" frame:NSMakeRect(8,y,b.size.width-16,64) action:@selector(selectProject:) blue:NO]; row.identifier = pid; row.layer.backgroundColor = selected ? Blue().CGColor : DarkRow().CGColor; row.layer.cornerRadius = 16; self.projectRows[pid] = row;
    [self label:p[@"name"] ?: pid frame:NSMakeRect(26,y+13,360,42) font:TitleFont(39) color:NSColor.whiteColor];
    NSButton *hit = [self button:@"" frame:row.frame action:@selector(selectProject:) blue:NO]; hit.identifier = pid; hit.layer.backgroundColor = NSColor.clearColor.CGColor; hit.layer.opacity = 0.01;
    y -= 88;
  }
  [self button:@"Open" frame:NSMakeRect(18,18,100,38) action:@selector(openLocalProject:) blue:YES];
  [self button:@"Share" frame:NSMakeRect(130,18,120,38) action:@selector(shareLocalProject:) blue:YES];
  [self button:@"+" frame:NSMakeRect(262,18,38,38) action:@selector(newProject:) blue:YES];
  [self button:@"Rename" frame:NSMakeRect(312,18,120,38) action:@selector(renameLocalProject:) blue:YES];
  [self redButton:@"Delete" frame:NSMakeRect(444,18,106,38) action:@selector(deleteLocalProject:)];
  [self addSharedProjectNoticeIfNeeded];
}
- (void)selectProject:(NSButton *)sender { self.activeProjectID = sender.identifier; self.store[@"activeProject"] = self.activeProjectID; for (NSString *pid in self.projectRows) self.projectRows[pid].layer.backgroundColor = ([pid isEqualToString:self.activeProjectID] ? Blue() : DarkRow()).CGColor; [self saveStore]; }
- (void)openIncomingProject:(id)sender {
  self.editingProject = [self.incomingProject mutableCopy];
  self.editingSharedProject = YES;
  self.activeFileID = self.editingProject[@"activeFile"] ?: [self fileIDsForProject:self.editingProject].firstObject;
  self.incomingProject = nil;
  self.runnerNoticeText = nil;
  self.runnerNoticeRed = NO;
  [self showEditorWithPreview:NO];
}
- (void)declineIncomingProject:(id)sender {
  self.incomingProject = nil;
  self.runnerNoticeText = @"Declined";
  self.runnerNoticeRed = YES;
  [self redrawCurrentScreen];
  [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(clearRunnerNotice:) userInfo:nil repeats:NO];
}
- (void)clearRunnerNotice:(id)sender {
  if (!self.runnerNoticeRed) return;
  self.runnerNoticeText = nil;
  self.runnerNoticeRed = NO;
  [self redrawCurrentScreen];
}
- (void)newProject:(id)sender {
  [self loadStore];
  NSString *pid = [NSString stringWithFormat:@"project-%.0f", NSDate.date.timeIntervalSince1970];
  NSString *name = [NSString stringWithFormat:@"MyApp%lu", (unsigned long)self.projectIDs.count + 1];
  self.store[@"projects"][pid] = [@{@"name":name, @"updatedAt":@(NSDate.date.timeIntervalSince1970), @"activeFile":@"ContentView", @"files":[@{@"ContentView":[@{@"name":@"ContentView", @"code":@"import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        Text(\"Hello\")\n    }\n}\n\n#Preview {\n    ContentView()\n}\n"} mutableCopy]} mutableCopy]} mutableCopy];
  self.activeProjectID = pid;
  self.store[@"activeProject"] = pid;
  [self saveStore];
  [self showProjectsPage];
}
- (void)renameLocalProject:(id)sender {
  [self loadStore];
  NSMutableDictionary *project = [self activeLocalProject]; if (!project) return;
  NSAlert *alert = [NSAlert new]; alert.messageText = @"Rename project";
  NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,260,28)];
  input.stringValue = project[@"name"] ?: @"";
  alert.accessoryView = input; [alert addButtonWithTitle:@"Rename"]; [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] != NSAlertFirstButtonReturn || !input.stringValue.length) return;
  project[@"name"] = input.stringValue; project[@"updatedAt"] = @(NSDate.date.timeIntervalSince1970);
  [self saveStore]; [self showProjectsPage];
}
- (void)deleteLocalProject:(id)sender {
  [self loadStore];
  NSMutableDictionary *project = [self activeLocalProject]; if (!project) return;
  NSAlert *alert = [NSAlert new];
  alert.messageText = [NSString stringWithFormat:@"Attention: Are you sure you want to delete '%@'?", project[@"name"] ?: @"Project"];
  [alert addButtonWithTitle:@"Delete"]; [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] != NSAlertFirstButtonReturn) return;
  [self.store[@"projects"] removeObjectForKey:self.activeProjectID];
  self.activeProjectID = self.projectIDs.firstObject;
  self.store[@"activeProject"] = self.activeProjectID ?: @"";
  if (!self.activeProjectID.length) { [self newProject:nil]; return; }
  [self saveStore]; [self showProjectsPage];
}
- (void)openLocalProject:(id)sender {
  self.editingProject = [self activeLocalProject];
  self.editingSharedProject = NO;
  self.activeFileID = self.editingProject[@"activeFile"] ?: [self fileIDsForProject:self.editingProject].firstObject;
  [self showEditorWithPreview:YES];
}
- (void)showEditorWithPreview:(BOOL)preview {
  self.screenMode = @"editor"; [self clearDynamic]; NSRect b = self.root.bounds; CGFloat leftW = 244, headerY = MAX(590, b.size.height - 91), contentTop = headerY - 19;
  CGFloat editorX = 264, editorY = 18, editorW = MAX(260, b.size.width - editorX - 44), editorH = MAX(220, contentTop - editorY);
  [self button:@"<" frame:NSMakeRect(18,headerY+26,32,32) action:(self.editingSharedProject ? @selector(backToLogButton:) : @selector(enterStudio:)) blue:YES];
  [self label:self.editingProject[@"name"] ?: @"Project" frame:NSMakeRect(64,headerY+6,230,58) font:TitleFont(42) color:NSColor.whiteColor];
  if (preview) [self button:@"Send" frame:NSMakeRect(310,headerY+16,120,44) action:@selector(sendLocalPreview:) blue:YES];
  [self button:@"Share" frame:NSMakeRect(preview ? 442 : 310,headerY+16,120,44) action:(self.editingSharedProject ? @selector(sendBackToStudio:) : @selector(shareLocalProject:)) blue:YES];
  [self button:@"Rename" frame:NSMakeRect(preview ? 574 : 442,headerY+16,120,44) action:@selector(renameEditingProject:) blue:YES];
  [self button:@"Rename File" frame:NSMakeRect(preview ? 706 : 574,headerY+16,150,44) action:@selector(renameEditingFile:) blue:YES];
  [self addLine:NSMakeRect(0,headerY,b.size.width,2)]; [self addLine:NSMakeRect(leftW,0,2,headerY)];
  CGFloat y = contentTop - 30; for (NSString *fid in [self fileIDsForProject:self.editingProject]) { NSDictionary *f = self.editingProject[@"files"][fid]; if (self.swiftLogo) { NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(10,y-1,32,28)]; iv.image = self.swiftLogo; [self.dynamicViews addObject:iv]; [self.root addSubview:iv]; } [self label:f[@"name"] ?: fid frame:NSMakeRect(54,y,175,27) font:MonoFont(21) color:NSColor.whiteColor]; NSButton *hit = [self button:@"" frame:NSMakeRect(0,y-4,240,34) action:@selector(selectFile:) blue:NO]; hit.identifier = fid; hit.layer.backgroundColor = ([fid isEqualToString:self.activeFileID] ? Blue() : NSColor.clearColor).CGColor; hit.layer.opacity = [fid isEqualToString:self.activeFileID] ? 0.35 : 0.0; y -= 36; }
  [self button:@"+" frame:NSMakeRect(18,18,32,32) action:@selector(newFile:) blue:YES];
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(editorX,editorY,editorW,editorH)];
  scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; scroll.borderType = NSNoBorder; [self tuneScrollView:scroll]; scroll.wantsLayer = YES; scroll.layer.backgroundColor = NSColor.blackColor.CGColor;
  self.editor = [[NSTextView alloc] initWithFrame:scroll.bounds]; self.editor.font = MonoFont(19); self.editor.textColor = NSColor.whiteColor; self.editor.backgroundColor = NSColor.blackColor; self.editor.insertionPointColor = NSColor.whiteColor; self.editor.automaticQuoteSubstitutionEnabled = NO; self.editor.automaticDashSubstitutionEnabled = NO; self.editor.automaticTextReplacementEnabled = NO; self.editor.allowsUndo = YES; self.editor.delegate = self; self.editor.string = [self currentFile][@"code"] ?: @"";
  scroll.documentView = self.editor; [self.dynamicViews addObject:scroll]; [self.root addSubview:scroll]; [self applySyntaxHighlighting];
  [self addSharedProjectNoticeIfNeeded];
}
- (void)editorChangedProgrammatically {
  [self saveEditingProject];
  [self applySyntaxHighlighting];
}
- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)replacementString {
  if (textView != self.editor) return YES;
  NSString *text = textView.string ?: @"";
  if ([replacementString isEqualToString:@"{"]) {
    NSRange currentLineRange = [text lineRangeForRange:NSMakeRange(MIN(range.location, text.length), 0)];
    NSString *currentLine = [text substringWithRange:NSMakeRange(currentLineRange.location, MIN(currentLineRange.length, text.length - currentLineRange.location))];
    NSMutableString *targetIndent = [NSMutableString string];
    for (NSUInteger i = 0; i < currentLine.length; i++) { unichar c = [currentLine characterAtIndex:i]; if (c == ' ' || c == '\t') [targetIndent appendFormat:@"%C", c]; else break; }
    [targetIndent appendString:@"    "];
    [textView.textStorage replaceCharactersInRange:range withString:@"{"];
    NSUInteger cursor = range.location + 1;
    NSString *updated = textView.string ?: @"";
    if (cursor < updated.length && [updated characterAtIndex:cursor] == '\n') {
      NSUInteger scan = cursor + 1;
      NSUInteger sourceIndentLength = NSNotFound;
      while (scan < textView.string.length) {
        NSString *currentText = textView.string ?: @"";
        NSRange lineRange = [currentText lineRangeForRange:NSMakeRange(scan, 0)];
        NSString *lineText = [currentText substringWithRange:NSMakeRange(lineRange.location, MIN(lineRange.length, currentText.length - lineRange.location))];
        NSString *trimmed = [lineText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!trimmed.length) { scan = NSMaxRange(lineRange); continue; }
        if ([trimmed hasPrefix:@"}"]) break;
        NSUInteger existingIndentLength = 0;
        while (existingIndentLength < lineText.length) { unichar c = [lineText characterAtIndex:existingIndentLength]; if (c == ' ' || c == '\t') existingIndentLength++; else break; }
        if (sourceIndentLength == NSNotFound) sourceIndentLength = existingIndentLength;
        if (existingIndentLength != sourceIndentLength) break;
        [textView.textStorage replaceCharactersInRange:NSMakeRange(lineRange.location, existingIndentLength) withString:targetIndent];
        scan = lineRange.location + targetIndent.length + (lineRange.length - existingIndentLength);
      }
    }
    [textView setSelectedRange:NSMakeRange(cursor, 0)];
    [self editorChangedProgrammatically];
    return NO;
  }
  if ([replacementString isEqualToString:@"}"]) {
    NSRange lineRange = [text lineRangeForRange:NSMakeRange(MIN(range.location, text.length), 0)];
    NSString *beforeCursor = [text substringWithRange:NSMakeRange(lineRange.location, MIN(range.location, text.length) - lineRange.location)];
    if ([[beforeCursor stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] length] == 0 && beforeCursor.length >= 4) {
      NSUInteger remove = MIN((NSUInteger)4, beforeCursor.length);
      NSRange replace = NSMakeRange(lineRange.location + beforeCursor.length - remove, remove + range.length);
      [textView.textStorage replaceCharactersInRange:replace withString:@"}"];
      [textView setSelectedRange:NSMakeRange(replace.location + 1, 0)];
      [self editorChangedProgrammatically];
      return NO;
    }
    return YES;
  }
  if (![replacementString isEqualToString:@"\n"]) return YES;
  NSRange lineRange = [text lineRangeForRange:NSMakeRange(MIN(range.location, text.length), 0)];
  NSString *line = [text substringWithRange:NSMakeRange(lineRange.location, MIN(lineRange.length, text.length - lineRange.location))];
  NSMutableString *indent = [NSMutableString string];
  for (NSUInteger i = 0; i < line.length; i++) { unichar c = [line characterAtIndex:i]; if (c == ' ' || c == '\t') [indent appendFormat:@"%C", c]; else break; }
  if (range.location > 0 && [[text substringWithRange:NSMakeRange(range.location - 1, 1)] isEqualToString:@"{"]) [indent appendString:@"    "];
  NSString *insert = [@"\n" stringByAppendingString:indent];
  [textView.textStorage replaceCharactersInRange:range withString:insert];
  [textView setSelectedRange:NSMakeRange(range.location + insert.length, 0)];
  [self editorChangedProgrammatically];
  return NO;
}
- (void)colorPattern:(NSString *)pattern color:(NSColor *)color inString:(NSString *)text {
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
  [regex enumerateMatchesInString:text options:0 range:NSMakeRange(0, text.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
    if (result.range.location != NSNotFound) [self.editor.textStorage addAttribute:NSForegroundColorAttributeName value:color range:result.range];
  }];
}
- (void)colorPattern:(NSString *)pattern capture:(NSUInteger)capture color:(NSColor *)color inString:(NSString *)text {
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
  [regex enumerateMatchesInString:text options:0 range:NSMakeRange(0, text.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
    if (capture < result.numberOfRanges) {
      NSRange r = [result rangeAtIndex:capture];
      if (r.location != NSNotFound && NSMaxRange(r) <= text.length) [self.editor.textStorage addAttribute:NSForegroundColorAttributeName value:color range:r];
    }
  }];
}
- (void)applySyntaxHighlighting {
  if (!self.editor || self.applyingHighlight) return;
  self.applyingHighlight = YES;
  NSRange selected = self.editor.selectedRange;
  NSString *text = self.editor.string ?: @"";
  NSDictionary *base = @{NSForegroundColorAttributeName: NSColor.whiteColor, NSFontAttributeName: MonoFont(19)};
  [self.editor.textStorage setAttributes:base range:NSMakeRange(0, text.length)];
  NSColor *pink = [NSColor colorWithCalibratedRed:1.0 green:0.24 blue:0.72 alpha:1.0];
  NSColor *blue = [NSColor colorWithCalibratedRed:0.28 green:0.62 blue:1.0 alpha:1.0];
  NSColor *cyan = [NSColor colorWithCalibratedRed:0.15 green:0.95 blue:1.0 alpha:1.0];
  NSColor *green = [NSColor colorWithCalibratedRed:0.35 green:1.0 blue:0.45 alpha:1.0];
  NSColor *red = [NSColor colorWithCalibratedRed:1.0 green:0.25 blue:0.25 alpha:1.0];
  NSColor *orange = [NSColor colorWithCalibratedRed:1.0 green:0.52 blue:0.12 alpha:1.0];
  [self colorPattern:@"\\b(import|struct|class|enum|protocol|extension|func|var|let|if|else|for|while|return|switch|case|default|private|public|internal|static|some|false|true|nil|in|where)\\b" color:pink inString:text];
  [self colorPattern:@"#[A-Za-z_][A-Za-z0-9_]*" color:blue inString:text];
  [self colorPattern:@"#(if|elseif|else|endif)\\b[^\\n]*" color:orange inString:text];
  [self colorPattern:@"@[A-Za-z_][A-Za-z0-9_]*" color:blue inString:text];
  [self colorPattern:@"[(,]\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*:" capture:1 color:blue inString:text];
  [self colorPattern:@"\\.[A-Za-z_][A-Za-z0-9_]*" color:blue inString:text];
  [self colorPattern:@"\\$[A-Za-z_][A-Za-z0-9_]*" color:green inString:text];
  NSRegularExpression *vars = [NSRegularExpression regularExpressionWithPattern:@"\\b(var|let)\\s+([A-Za-z_][A-Za-z0-9_]*)" options:0 error:nil];
  [vars enumerateMatchesInString:text options:0 range:NSMakeRange(0, text.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
    NSRange nameRange = [result rangeAtIndex:2];
    if (nameRange.location == NSNotFound || NSMaxRange(nameRange) > text.length) return;
    NSString *name = [text substringWithRange:nameRange];
    [self colorPattern:[NSString stringWithFormat:@"\\b%@\\b", name] color:green inString:text];
  }];
  [self colorPattern:@"\\b([A-Z][A-Za-z0-9_]*)\\s*(?=\\()" capture:1 color:green inString:text];
  [self colorPattern:@"\\b(Text|VStack|HStack|ZStack|List|Button|Image|Spacer|ScrollView|NavigationStack|Form|Section|Toggle|Slider|TextField|Rectangle|RoundedRectangle|Circle|ForEach)\\b" color:blue inString:text];
  [self colorPattern:@"\\b(Int|Double|Float|String|Bool|Void|View|Scene|App|Color|Font|Binding|State|ObservedObject|EnvironmentObject|CGFloat|NSApplication)\\b" color:blue inString:text];
  [self colorPattern:@"\\b(var|let)\\s+([A-Za-z_][A-Za-z0-9_]*)" capture:2 color:cyan inString:text];
  [self colorPattern:@"\\b(struct|class|enum|protocol|func)\\s+([A-Za-z_][A-Za-z0-9_]*)" capture:2 color:cyan inString:text];
  [self colorPattern:@"\"([^\"\\\\]|\\\\.)*\"" color:red inString:text];
  [self colorPattern:@"//[^\\n]*" color:green inString:text];
  [self.editor setSelectedRange:NSMakeRange(MIN(selected.location, text.length), MIN(selected.length, text.length - MIN(selected.location, text.length)))];
  self.applyingHighlight = NO;
}
- (void)textDidChange:(NSNotification *)n { [self saveEditingProject]; [self applySyntaxHighlighting]; }
- (void)saveEditingProject { if (!self.activeFileID.length || !self.editor) return; [self currentFile][@"code"] = self.editor.string ?: @""; self.editingProject[@"updatedAt"] = @(NSDate.date.timeIntervalSince1970); self.editingProject[@"activeFile"] = self.activeFileID; if (!self.editingSharedProject) [self saveStore]; }
- (void)selectFile:(NSButton *)sender { [self saveEditingProject]; self.activeFileID = sender.identifier; self.editingProject[@"activeFile"] = self.activeFileID; if (!self.editingSharedProject) [self saveStore]; [self showEditorWithPreview:!self.editingSharedProject]; }
- (void)newFile:(id)sender { [self saveEditingProject]; NSString *fid = [NSString stringWithFormat:@"File%lu", (unsigned long)[self fileIDsForProject:self.editingProject].count + 1]; self.editingProject[@"files"][fid] = [@{@"name":fid, @"code":@"import SwiftUI\n"} mutableCopy]; self.activeFileID = fid; self.editingProject[@"activeFile"] = fid; self.editingProject[@"updatedAt"] = @(NSDate.date.timeIntervalSince1970); if (!self.editingSharedProject) [self saveStore]; [self showEditorWithPreview:!self.editingSharedProject]; }
- (void)renameEditingProject:(id)sender {
  NSAlert *alert = [NSAlert new]; alert.messageText = @"Rename project";
  NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,260,28)];
  input.stringValue = self.editingProject[@"name"] ?: @"";
  alert.accessoryView = input; [alert addButtonWithTitle:@"Rename"]; [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] != NSAlertFirstButtonReturn || !input.stringValue.length) return;
  self.editingProject[@"name"] = input.stringValue; self.editingProject[@"updatedAt"] = @(NSDate.date.timeIntervalSince1970);
  if (!self.editingSharedProject) [self saveStore];
  [self showEditorWithPreview:!self.editingSharedProject];
}
- (void)renameEditingFile:(id)sender {
  [self saveEditingProject]; if (!self.activeFileID.length) return;
  NSAlert *alert = [NSAlert new]; alert.messageText = @"Rename file";
  NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,260,28)];
  input.stringValue = [self currentFile][@"name"] ?: self.activeFileID;
  alert.accessoryView = input; [alert addButtonWithTitle:@"Rename"]; [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] != NSAlertFirstButtonReturn || !input.stringValue.length) return;
  NSString *base = [[input.stringValue componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@""];
  if (!base.length) base = @"File";
  NSString *newID = base; NSUInteger suffix = 2; NSMutableDictionary *files = self.editingProject[@"files"];
  while (files[newID] && ![newID isEqualToString:self.activeFileID]) newID = [NSString stringWithFormat:@"%@%lu", base, (unsigned long)suffix++];
  NSMutableDictionary *renamed = [[self currentFile] mutableCopy]; renamed[@"name"] = input.stringValue;
  [files removeObjectForKey:self.activeFileID]; files[newID] = renamed; self.activeFileID = newID; self.editingProject[@"activeFile"] = newID;
  if (!self.editingSharedProject) [self saveStore];
  [self showEditorWithPreview:!self.editingSharedProject];
}
- (NSString *)combinedSourceForProject:(NSDictionary *)project {
  NSMutableString *source = [NSMutableString string]; for (NSString *fid in [self fileIDsForProject:project]) [source appendFormat:@"\n// %@.swift\n%@\n", fid, project[@"files"][fid][@"code"] ?: @""]; return source;
}
- (void)sendLocalPreview:(id)sender {
  [self saveEditingProject]; NSString *requestID = [NSString stringWithFormat:@"runner-%.0f", NSDate.date.timeIntervalSince1970 * 1000]; NSError *error = nil;
  BOOL ok = PatchDocument([NSString stringWithFormat:@"Threads/%@", self.threads.firstObject ?: @"Thread1"], @{@"send":[self combinedSourceForProject:self.editingProject], @"appName":self.editingProject[@"name"] ?: @"SwiftUI App", @"requestId":requestID, @"previewArch":@"", @"compileOnly":@NO, @"status":@"queued", @"preview":@"", @"error":@"", @"sentAt":NSDate.date, @"compiledRequestId":@"", @"compiledChunkCount":@0, @"compiledSize":@0}, &error);
  [self appendLog:ok ? @"Sent preview job" : [NSString stringWithFormat:@"Preview send failed: %@", error.localizedDescription ?: @"Firestore write failed"]];
}
- (void)sendBackToStudio:(id)sender {
  [self saveEditingProject]; NSString *requestID = [NSString stringWithFormat:@"runner-return-%.0f", NSDate.date.timeIntervalSince1970 * 1000]; NSError *error = nil;
  BOOL ok = PatchDocument(@"Threads/ProjectReturn", @{@"status":@"sent_back", @"requestId":requestID, @"project":self.editingProject, @"sentAt":NSDate.date}, &error);
  if (!ok) [self appendLog:[NSString stringWithFormat:@"Send back failed: %@", error.localizedDescription ?: @"Firestore write failed"]];
  [self backToLog:nil];
}
- (void)shareLocalProject:(id)sender {
  [self saveEditingProject]; NSDictionary *project = self.editingProject ?: [self activeLocalProject]; if (!project) return;
  NSString *requestID = [NSString stringWithFormat:@"runner-share-%.0f", NSDate.date.timeIntervalSince1970 * 1000]; NSError *error = nil;
  NSString *status = self.editingSharedProject ? @"sent_back" : @"add_to_projects";
  BOOL ok = PatchDocument(@"Threads/ProjectReturn", @{@"status":status, @"requestId":requestID, @"project":project, @"sentAt":NSDate.date}, &error);
  if (!ok) [self appendLog:[NSString stringWithFormat:@"Share failed: %@", error.localizedDescription ?: @"Firestore write failed"]];
}
- (void)backToLogButton:(id)sender { [self saveEditingProject]; self.editor = nil; self.editingProject = nil; self.editingSharedProject = NO; [self showLog]; }
- (void)backToLog:(id)sender { [self backToLogButton:sender]; }
- (void)watchThreads {
  while (YES) {
    [self checkFishRequest];
    for (NSString *thread in self.threads) {
      NSError *error = nil;
      NSDictionary *remote = GetDocument([NSString stringWithFormat:@"Threads/%@", thread], &error);
      if (error) { [self appendLog:[NSString stringWithFormat:@"%@: %@", thread, error.localizedDescription]]; continue; }
      NSString *requestID = remote[@"requestId"]; NSString *source = remote[@"send"];
      if (!requestID.length || !source.length || [self.seen[thread] isEqualToString:requestID]) continue;
      self.seen[thread] = requestID;
      NSString *appName = remote[@"appName"] ?: @"SwiftUI App";
      BOOL compileOnly = [remote[@"compileOnly"] boolValue];
      [self appendLog:[NSString stringWithFormat:@"%@: Compiling...", appName]];
      SetPercent(@"Compile", 1); SetPercent(@"Run", 0);
      PatchDocument([NSString stringWithFormat:@"Threads/%@", thread], @{@"status": @"running", @"startedAt": NSDate.date}, nil);
      NSDictionary *result = CompileExecutable(source, requestID, remote[@"previewArch"] ?: @"");
      BOOL ok = [result[@"ok"] boolValue]; NSDictionary *compiledMetadata = @{};
      if (ok && compileOnly) {
        compiledMetadata = @{@"compiledRequestId":requestID, @"compiledChunkCount":@0, @"compiledSize":@0, @"compiledAt":NSDate.date};
      } else if (ok) {
        NSError *uploadError = nil; compiledMetadata = UploadExecutableChunks(thread, requestID, result[@"executablePath"], result[@"executableName"], &uploadError);
        ok = compiledMetadata != nil;
        if (!ok) result = @{@"ok": @NO, @"preview": @"Compiled preview library upload failed.", @"error": uploadError.localizedDescription ?: @""};
      }
      NSMutableDictionary *finalPayload = [@{@"status": ok ? @"complete" : @"error", @"preview": result[@"preview"] ?: @"", @"error": result[@"error"] ?: @"", @"completedAt": NSDate.date} mutableCopy];
      [finalPayload addEntriesFromDictionary:compiledMetadata];
      PatchDocument([NSString stringWithFormat:@"Threads/%@", thread], finalPayload, nil);
      if (ok) UpdateHistory(appName);
      [self appendLog:[NSString stringWithFormat:@"%@: %@", appName, ok ? @"complete" : @"error"]];
      if ([result[@"error"] length]) [self appendLog:result[@"error"]];
    }
    [NSThread sleepForTimeInterval:2.0];
  }
}
@end

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc > 1 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"))) {
      puts("Preview Runner\n\nUsage:\n  ~/cmds/preview_runner [--thread Thread1]\n  ~/cmds/preview_runner --all\n\nNative NSApplication runner. Compiles SwiftUI preview jobs, logs progress, and can exchange projects with SwiftStudio.");
      return 0;
    }
    NSApplication *app = NSApplication.sharedApplication;
    RunnerDelegate *delegate = [RunnerDelegate new];
    delegate.threads = ParseThreads(argc, argv);
    app.delegate = delegate;
    [app run];
  }
}

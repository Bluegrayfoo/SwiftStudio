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
@end

@implementation RunnerDelegate
- (NSString *)docsPath { return [@"~/cmds/swift_studio_projects.json" stringByExpandingTildeInPath]; }
- (void)applicationDidFinishLaunching:(NSNotification *)n {
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  self.dynamicViews = [NSMutableArray array];
  self.logText = [NSMutableString string];
  self.seen = [NSMutableDictionary dictionary];
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
- (void)addLine:(NSRect)frame { NSBox *box = [[NSBox alloc] initWithFrame:frame]; box.boxType = NSBoxCustom; box.borderColor = NSColor.whiteColor; box.fillColor = NSColor.whiteColor; [self.dynamicViews addObject:box]; [self.root addSubview:box]; }
- (void)appendLog:(NSString *)line {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self.logText) self.logText = [NSMutableString string];
    if (line.length) [self.logText appendFormat:@"%@\n", line];
    if (self.logView) { self.logView.string = self.logText; [self.logView scrollRangeToVisible:NSMakeRange(self.logView.string.length, 0)]; }
  });
}
- (void)showLog {
  [self clearDynamic]; self.editor = nil; NSRect b = self.root.bounds;
  [self label:@"Preview Runner" frame:NSMakeRect(0,b.size.height-78,b.size.width,60) font:TitleFont(42) color:NSColor.whiteColor].alignment = NSTextAlignmentCenter;
  [self button:@"Enter studio" frame:NSMakeRect(18,b.size.height-62,170,42) action:@selector(enterStudio:) blue:YES];
  [self addLine:NSMakeRect(0,b.size.height-86,b.size.width,2)];
  if (self.incomingProject) {
    [self label:@"Project shared" frame:NSMakeRect(32,b.size.height-136,220,34) font:TitleFont(24) color:NSColor.whiteColor];
    [self button:@"Open" frame:NSMakeRect(260,b.size.height-140,100,38) action:@selector(openIncomingProject:) blue:YES];
  }
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(18,18,b.size.width-36,b.size.height-170)];
  scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; scroll.hasVerticalScroller = YES; scroll.autohidesScrollers = NO; scroll.verticalLineScroll = 10; scroll.verticalPageScroll = 80; scroll.wantsLayer = YES; scroll.layer.backgroundColor = NSColor.blackColor.CGColor;
  self.logView = [[NSTextView alloc] initWithFrame:scroll.bounds]; self.logView.font = MonoFont(18); self.logView.textColor = NSColor.whiteColor; self.logView.backgroundColor = NSColor.blackColor; self.logView.editable = NO; self.logView.string = self.logText ?: @"";
  scroll.documentView = self.logView; [self.dynamicViews addObject:scroll]; [self.root addSubview:scroll];
}
- (void)checkProjectShare:(id)sender {
  NSError *error = nil; NSDictionary *doc = GetDocument(@"Threads/ProjectShare", &error);
  if (error || ![doc[@"status"] isEqualToString:@"project_shared"]) return;
  NSString *requestID = doc[@"requestId"]; NSDictionary *project = doc[@"project"];
  if (!requestID.length || !project || [requestID isEqualToString:self.lastIncomingShareID]) return;
  self.lastIncomingShareID = requestID; self.incomingProject = [project mutableCopy];
  [self appendLog:@"Project shared"];
  if (!self.editor) [self showLog];
}
- (void)loadStore {
  NSData *data = [NSData dataWithContentsOfFile:self.docsPath];
  if (data) self.store = [[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] mutableCopy];
  if (!self.store) self.store = [@{@"activeProject":@"", @"projects":[NSMutableDictionary dictionary]} mutableCopy];
  self.activeProjectID = self.store[@"activeProject"] ?: [[self.store[@"projects"] allKeys] firstObject];
}
- (void)saveStore { NSData *data = [NSJSONSerialization dataWithJSONObject:self.store options:NSJSONWritingPrettyPrinted error:nil]; [data writeToFile:self.docsPath atomically:YES]; }
- (NSArray *)projectIDs { return [[self.store[@"projects"] allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]; }
- (NSArray *)fileIDsForProject:(NSDictionary *)project { return [[project[@"files"] allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]; }
- (NSMutableDictionary *)activeLocalProject { return self.store[@"projects"][self.activeProjectID]; }
- (void)enterStudio:(id)sender { [self loadStore]; [self showProjectsPage]; }
- (void)showProjectsPage {
  [self clearDynamic]; self.editor = nil; NSRect b = self.root.bounds;
  [self button:@"Back to log" frame:NSMakeRect(18,b.size.height-62,150,42) action:@selector(backToLog:) blue:YES];
  [self label:@"SwiftStudio" frame:NSMakeRect(0,b.size.height-78,b.size.width,60) font:TitleFont(42) color:NSColor.whiteColor].alignment = NSTextAlignmentCenter;
  [self addLine:NSMakeRect(0,b.size.height-86,b.size.width,2)];
  CGFloat y = b.size.height - 160;
  for (NSString *pid in self.projectIDs) {
    NSDictionary *p = self.store[@"projects"][pid]; BOOL selected = [pid isEqualToString:self.activeProjectID];
    NSButton *row = [self button:@"" frame:NSMakeRect(18,y,b.size.width-36,58) action:@selector(selectProject:) blue:NO]; row.identifier = pid; row.layer.backgroundColor = selected ? Blue().CGColor : DarkRow().CGColor; row.layer.cornerRadius = 14;
    [self label:p[@"name"] ?: pid frame:NSMakeRect(38,y+10,360,38) font:TitleFont(32) color:NSColor.whiteColor];
    y -= 76;
  }
  [self button:@"Open" frame:NSMakeRect(18,18,100,38) action:@selector(openLocalProject:) blue:YES];
  [self button:@"Share" frame:NSMakeRect(130,18,120,38) action:@selector(shareLocalProject:) blue:YES];
}
- (void)selectProject:(NSButton *)sender { self.activeProjectID = sender.identifier; self.store[@"activeProject"] = self.activeProjectID; [self saveStore]; [self showProjectsPage]; }
- (void)openIncomingProject:(id)sender {
  self.editingProject = [self.incomingProject mutableCopy];
  self.editingSharedProject = YES;
  self.activeFileID = self.editingProject[@"activeFile"] ?: [self fileIDsForProject:self.editingProject].firstObject;
  [self showEditorWithPreview:NO];
}
- (void)openLocalProject:(id)sender {
  self.editingProject = [self activeLocalProject];
  self.editingSharedProject = NO;
  self.activeFileID = self.editingProject[@"activeFile"] ?: [self fileIDsForProject:self.editingProject].firstObject;
  [self showEditorWithPreview:YES];
}
- (void)showEditorWithPreview:(BOOL)preview {
  [self clearDynamic]; NSRect b = self.root.bounds; CGFloat headerY = b.size.height - 86; CGFloat leftW = 250;
  [self button:@"<" frame:NSMakeRect(18,headerY+26,32,32) action:(self.editingSharedProject ? @selector(backToLog:) : @selector(enterStudio:)) blue:YES];
  [self label:self.editingProject[@"name"] ?: @"Project" frame:NSMakeRect(64,headerY+6,230,58) font:TitleFont(38) color:NSColor.whiteColor];
  if (preview) [self button:@"Send" frame:NSMakeRect(310,headerY+16,120,44) action:@selector(sendLocalPreview:) blue:YES];
  [self button:(self.editingSharedProject ? @"Send" : @"Share") frame:NSMakeRect(preview ? 442 : 310,headerY+16,120,44) action:(self.editingSharedProject ? @selector(sendBackToStudio:) : @selector(shareLocalProject:)) blue:YES];
  [self addLine:NSMakeRect(0,headerY,b.size.width,2)]; [self addLine:NSMakeRect(leftW,0,2,headerY)];
  CGFloat y = headerY - 42; for (NSString *fid in [self fileIDsForProject:self.editingProject]) { NSDictionary *f = self.editingProject[@"files"][fid]; [self label:f[@"name"] ?: fid frame:NSMakeRect(20,y,190,28) font:MonoFont(20) color:NSColor.whiteColor]; y -= 36; }
  NSString *code = self.editingProject[@"files"][self.activeFileID][@"code"] ?: @"";
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(leftW+16,18,b.size.width-leftW-34,headerY-36)];
  scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; scroll.hasVerticalScroller = YES; scroll.autohidesScrollers = NO; scroll.verticalLineScroll = 10; scroll.verticalPageScroll = 80;
  self.editor = [[NSTextView alloc] initWithFrame:scroll.bounds]; self.editor.font = MonoFont(18); self.editor.textColor = NSColor.whiteColor; self.editor.backgroundColor = NSColor.blackColor; self.editor.insertionPointColor = NSColor.whiteColor; self.editor.delegate = self; self.editor.string = code;
  scroll.documentView = self.editor; [self.dynamicViews addObject:scroll]; [self.root addSubview:scroll];
}
- (void)textDidChange:(NSNotification *)n { if (!self.activeFileID.length) return; self.editingProject[@"files"][self.activeFileID][@"code"] = self.editor.string ?: @""; self.editingProject[@"updatedAt"] = @(NSDate.date.timeIntervalSince1970); if (!self.editingSharedProject) [self saveStore]; }
- (void)saveEditingProject { if (!self.activeFileID.length || !self.editor) return; self.editingProject[@"files"][self.activeFileID][@"code"] = self.editor.string ?: @""; self.editingProject[@"updatedAt"] = @(NSDate.date.timeIntervalSince1970); if (!self.editingSharedProject) [self saveStore]; }
- (NSString *)combinedSourceForProject:(NSDictionary *)project {
  NSMutableString *source = [NSMutableString string]; for (NSString *fid in [self fileIDsForProject:project]) [source appendFormat:@"\n// %@.swift\n%@\n", fid, project[@"files"][fid][@"code"] ?: @""]; return source;
}
- (void)sendLocalPreview:(id)sender {
  [self saveEditingProject]; NSString *requestID = [NSString stringWithFormat:@"runner-%.0f", NSDate.date.timeIntervalSince1970 * 1000]; NSError *error = nil;
  BOOL ok = PatchDocument([NSString stringWithFormat:@"Threads/%@", self.threads.firstObject ?: @"Thread1"], @{@"send":[self combinedSourceForProject:self.editingProject], @"appName":self.editingProject[@"name"] ?: @"SwiftUI App", @"requestId":requestID, @"previewArch":@"", @"status":@"queued", @"preview":@"", @"error":@"", @"sentAt":NSDate.date, @"compiledRequestId":@"", @"compiledChunkCount":@0, @"compiledSize":@0}, &error);
  [self appendLog:ok ? @"Sent preview job" : [NSString stringWithFormat:@"Preview send failed: %@", error.localizedDescription ?: @"Firestore write failed"]];
}
- (void)sendBackToStudio:(id)sender {
  [self saveEditingProject]; NSString *requestID = [NSString stringWithFormat:@"runner-return-%.0f", NSDate.date.timeIntervalSince1970 * 1000]; NSError *error = nil;
  BOOL ok = PatchDocument(@"Threads/ProjectReturn", @{@"status":@"sent_back", @"requestId":requestID, @"project":self.editingProject, @"sentAt":NSDate.date}, &error);
  [self appendLog:ok ? @"Project sent back" : [NSString stringWithFormat:@"Send back failed: %@", error.localizedDescription ?: @"Firestore write failed"]];
  [self backToLog:nil];
}
- (void)shareLocalProject:(id)sender {
  [self saveEditingProject]; NSDictionary *project = self.editingProject ?: [self activeLocalProject]; if (!project) return;
  NSString *requestID = [NSString stringWithFormat:@"runner-share-%.0f", NSDate.date.timeIntervalSince1970 * 1000]; NSError *error = nil;
  BOOL ok = PatchDocument(@"Threads/ProjectReturn", @{@"status":@"add_to_projects", @"requestId":requestID, @"project":project, @"sentAt":NSDate.date}, &error);
  [self appendLog:ok ? @"Add to projects" : [NSString stringWithFormat:@"Share failed: %@", error.localizedDescription ?: @"Firestore write failed"]];
}
- (void)backToLog:(id)sender { [self showLog]; }
- (void)watchThreads {
  while (YES) {
    for (NSString *thread in self.threads) {
      NSError *error = nil;
      NSDictionary *remote = GetDocument([NSString stringWithFormat:@"Threads/%@", thread], &error);
      if (error) { [self appendLog:[NSString stringWithFormat:@"%@: %@", thread, error.localizedDescription]]; continue; }
      NSString *requestID = remote[@"requestId"]; NSString *source = remote[@"send"];
      if (!requestID.length || !source.length || [self.seen[thread] isEqualToString:requestID]) continue;
      self.seen[thread] = requestID;
      NSString *appName = remote[@"appName"] ?: @"SwiftUI App";
      [self appendLog:[NSString stringWithFormat:@"%@: Compiling...", appName]];
      SetPercent(@"Compile", 1); SetPercent(@"Run", 0);
      PatchDocument([NSString stringWithFormat:@"Threads/%@", thread], @{@"status": @"running", @"startedAt": NSDate.date}, nil);
      NSDictionary *result = CompileExecutable(source, requestID, remote[@"previewArch"] ?: @"");
      BOOL ok = [result[@"ok"] boolValue]; NSDictionary *compiledMetadata = @{};
      if (ok) {
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

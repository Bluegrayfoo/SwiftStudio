#import <Foundation/Foundation.h>

static NSString *const APIKey = @"AIzaSyDYduyE8CvW-Fm5lBwTsV8JrChA_hjs8Qo";
static NSString *const ProjectID = @"bytehelper-c7794";

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

static NSDictionary *CompileExecutable(NSString *source, NSString *requestID) {
  SetPercent(@"Compile", 3);
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"swiftstudio-compile-%@", NSUUID.UUID.UUIDString]];
  [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *sourcePath = [dir stringByAppendingPathComponent:@"Preview.swift"];
  NSString *exeName = [NSString stringWithFormat:@"SwiftStudioPreview-%@", requestID];
  exeName = [[exeName componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@"-"];
  NSString *exePath = [dir stringByAppendingPathComponent:exeName];
  NSString *cache = [@"~/cmds/.swiftstudio-module-cache" stringByExpandingTildeInPath];
  [[NSFileManager defaultManager] createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:nil];
  SetPercent(@"Compile", 10);
  NSString *hosted = [NSString stringWithFormat:@"import AppKit\n%@\n\n@main\nstruct PreviewHostApp: App {\n    init() {\n        NSApplication.shared.activate(ignoringOtherApps: true)\n    }\n\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}\n", StripPreviewBlocks(source)];
  [hosted writeToFile:sourcePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
  SetPercent(@"Compile", 22);
  NSTask *compile = [NSTask new];
  compile.launchPath = @"/usr/bin/swiftc";
  compile.arguments = @[@"-parse-as-library", @"-module-cache-path", cache, sourcePath, @"-o", exePath];
  NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
  env[@"CLANG_MODULE_CACHE_PATH"] = cache;
  compile.environment = env;
  NSPipe *outPipe = [NSPipe pipe];
  NSPipe *errPipe = [NSPipe pipe];
  compile.standardOutput = outPipe;
  compile.standardError = errPipe;
  NSDate *start = NSDate.date;
  [compile launch];
  SetPercent(@"Compile", 30);
  double lastReported = 30;
  while (compile.isRunning && [NSDate.date timeIntervalSinceDate:start] < 75) {
    double elapsed = [NSDate.date timeIntervalSinceDate:start];
    double next = MIN(96, 30 + (elapsed / 75.0) * 66.0);
    if (next - lastReported >= 2) { SetPercent(@"Compile", next); lastReported = next; }
    [NSThread sleepForTimeInterval:0.15];
  }
  if (compile.isRunning) {
    [compile terminate];
    SetPercent(@"Compile", 100);
    return @{@"ok": @NO, @"preview": @"SwiftUI compile timed out.", @"error": @""};
  }
  NSString *compilerOut = [[NSString alloc] initWithData:[outPipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding] ?: @"";
  NSString *compilerErr = [[NSString alloc] initWithData:[errPipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding] ?: @"";
  SetPercent(@"Compile", 100);
  if (compile.terminationStatus != 0) {
    return @{@"ok": @NO, @"preview": compilerOut.length ? compilerOut : @"SwiftUI compile failed.", @"error": compilerErr};
  }
  return @{@"ok": @YES, @"preview": @"Compiled executable for Studio", @"error": @"", @"executablePath": exePath, @"executableName": exeName};
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

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc > 1 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"))) {
      puts("Preview Runner\n\nUsage:\n  ~/cmds/preview_runner [--thread Thread1]\n  ~/cmds/preview_runner --all\n\nHeadless runner. Silently compiles raw SwiftUI source and writes status back to Firestore. It never opens a preview window.");
      return 0;
    }
    NSArray<NSString *> *threads = ParseThreads(argc, argv);
    NSMutableDictionary *seen = [NSMutableDictionary dictionary];
    UpdateHistory(@"Preview Runner");
    printf("Watching %s. This runner is headless and will not open preview windows.\n", [[threads componentsJoinedByString:@", "] UTF8String]);
    while (YES) {
      for (NSString *thread in threads) {
        NSError *error = nil;
        NSDictionary *remote = GetDocument([NSString stringWithFormat:@"Threads/%@", thread], &error);
        if (error) { fprintf(stderr, "%s: %s\n", thread.UTF8String, error.localizedDescription.UTF8String); continue; }
        NSString *requestID = remote[@"requestId"];
        NSString *source = remote[@"send"];
        if (!requestID.length || !source.length || [seen[thread] isEqualToString:requestID]) continue;
        seen[thread] = requestID;
        NSString *appName = remote[@"appName"] ?: @"SwiftUI App";
        SetPercent(@"Run", 0);
        PatchDocument([NSString stringWithFormat:@"Threads/%@", thread], @{@"status": @"running", @"startedAt": NSDate.date}, nil);
        NSDictionary *result = CompileExecutable(source, requestID);
        BOOL ok = [result[@"ok"] boolValue];
        NSDictionary *compiledMetadata = @{};
        if (ok) {
          NSError *uploadError = nil;
          compiledMetadata = UploadExecutableChunks(thread, requestID, result[@"executablePath"], result[@"executableName"], &uploadError);
          ok = compiledMetadata != nil;
          if (!ok) result = @{@"ok": @NO, @"preview": @"Compiled executable upload failed.", @"error": uploadError.localizedDescription ?: @""};
        }
        NSMutableDictionary *finalPayload = [@{@"status": ok ? @"complete" : @"error", @"preview": result[@"preview"] ?: @"", @"error": result[@"error"] ?: @"", @"completedAt": NSDate.date} mutableCopy];
        [finalPayload addEntriesFromDictionary:compiledMetadata];
        PatchDocument([NSString stringWithFormat:@"Threads/%@", thread], finalPayload, nil);
        if (ok) UpdateHistory(appName);
        printf("%s: %s\n", thread.UTF8String, ok ? "complete" : "error");
      }
      [NSThread sleepForTimeInterval:0.5];
    }
  }
}

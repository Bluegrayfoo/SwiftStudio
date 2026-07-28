#import <AppKit/AppKit.h>
#import <float.h>

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
  if (value[@"mapValue"]) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSDictionary *fields = value[@"mapValue"][@"fields"] ?: @{};
    for (NSString *key in fields) out[key] = NativeValue(fields[key]);
    return out;
  }
  return nil;
}

static NSString *PercentEncode(NSString *text) {
  return [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"]];
}

static NSString *FieldPath(NSString *field) {
  NSCharacterSet *simple = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"];
  if ([field rangeOfCharacterFromSet:[simple invertedSet]].location == NSNotFound) return field;
  return [NSString stringWithFormat:@"`%@`", [field stringByReplacingOccurrencesOfString:@"`" withString:@"\\`"]];
}

static NSURL *FirestoreURL(NSString *path, NSArray<NSString *> *mask) {
  NSString *base = [NSString stringWithFormat:@"https://firestore.googleapis.com/v1/projects/%@/databases/(default)/documents/%@?key=%@", ProjectID, path, APIKey];
  NSMutableString *url = [base mutableCopy];
  for (NSString *field in mask) [url appendFormat:@"&updateMask.fieldPaths=%@", PercentEncode(FieldPath(field))];
  return [NSURL URLWithString:url];
}

static NSDictionary *GetDocument(NSString *path, NSError **outError) {
  dispatch_semaphore_t sem = dispatch_semaphore_create(0); __block NSData *data = nil; __block NSURLResponse *response = nil; __block NSError *error = nil;
  [[[NSURLSession sharedSession] dataTaskWithURL:FirestoreURL(path, @[]) completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) { data=d; response=r; error=e; dispatch_semaphore_signal(sem); }] resume];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER); if (error) { if (outError) *outError = error; return @{}; }
  NSInteger status = [(NSHTTPURLResponse *)response statusCode]; if (status == 404) return @{}; if (status < 200 || status >= 300) { if (outError) *outError = [NSError errorWithDomain:@"Firestore" code:status userInfo:@{NSLocalizedDescriptionKey:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"Firestore read failed"}]; return @{}; }
  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:outError]; NSMutableDictionary *out = [NSMutableDictionary dictionary]; for (NSString *key in json[@"fields"] ?: @{}) out[key] = NativeValue(json[@"fields"][key]); return out;
}

static BOOL PatchDocument(NSString *path, NSDictionary *payload, NSError **outError) {
  NSMutableDictionary *fields = [NSMutableDictionary dictionary]; for (NSString *key in payload) fields[key] = FirestoreValue(payload[key]);
  NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"fields": fields} options:0 error:outError];
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:FirestoreURL(path, payload.allKeys)]; request.HTTPMethod = @"PATCH"; request.HTTPBody = body; [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
  dispatch_semaphore_t sem = dispatch_semaphore_create(0); __block NSData *data = nil; __block NSURLResponse *response = nil; __block NSError *error = nil;
  [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) { data=d; response=r; error=e; dispatch_semaphore_signal(sem); }] resume];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER); if (error) { if (outError) *outError = error; return NO; }
  NSInteger status = [(NSHTTPURLResponse *)response statusCode]; if (status < 200 || status >= 300) { if (outError) *outError = [NSError errorWithDomain:@"Firestore" code:status userInfo:@{NSLocalizedDescriptionKey:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"Firestore write failed"}]; return NO; } return YES;
}

static void SetPercent(NSString *kind, double value) { PatchDocument([NSString stringWithFormat:@"Percent/%@", kind], @{@"%": @(value)}, nil); }

static void UpdateHistory(NSString *appName) {
  NSDictionary *doc = GetDocument(@"LatestHistory/History", nil); NSMutableDictionary *hist = [NSMutableDictionary dictionaryWithDictionary:doc[@"hist"] ?: @{}]; NSDate *now = NSDate.date; NSDate *cutoff = [now dateByAddingTimeInterval:-7*24*60*60];
  NSDateFormatter *iso = [NSDateFormatter new]; iso.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; iso.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
  for (NSString *key in [hist.allKeys copy]) { NSDate *date = [iso dateFromString:hist[key][@"timestamp"] ?: @""]; if (!date || [date compare:cutoff] == NSOrderedAscending) [hist removeObjectForKey:key]; }
  NSDateFormatter *tf = [NSDateFormatter new]; tf.dateFormat = @"h:mm a"; NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"MMMM d"; NSString *stamp = [iso stringFromDate:now];
  hist[stamp] = @{@"text":[NSString stringWithFormat:@"%@ was run at %@ on %@", appName, [tf stringFromDate:now], [df stringFromDate:now]], @"timestamp":stamp}; PatchDocument(@"LatestHistory/History", @{@"hist":hist}, nil);
}

@interface StudioDelegate : NSObject <NSApplicationDelegate, NSTextViewDelegate>
@property NSWindow *window;
@property NSView *root;
@property NSMutableDictionary *store;
@property NSString *activeProjectID;
@property NSString *activeFileID;
@property NSString *pendingRequestID;
@property NSString *initialThread;
@property NSMutableArray<NSView *> *dynamicViews;
@property NSMutableDictionary<NSString *, NSTextField *> *ageLabels;
@property NSTextView *editor;
@property NSTextView *console;
@property NSMutableString *consoleLog;
@property NSImage *swiftLogo;
@property BOOL showingProject;
@end

@implementation StudioDelegate
- (NSString *)docsPath { return [@"~/cmds/swift_studio_projects.json" stringByExpandingTildeInPath]; }
- (void)applicationDidFinishLaunching:(NSNotification *)n {
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]; self.dynamicViews = [NSMutableArray array]; self.ageLabels = [NSMutableDictionary dictionary]; self.consoleLog = [NSMutableString string]; self.swiftLogo = [[NSImage alloc] initWithContentsOfFile:[@"~/cmds/swiftlogo.png" stringByExpandingTildeInPath]];
  [self loadStore]; [self buildWindow]; [self showMain]; UpdateHistory(@"SwiftStudio"); [NSApp activateIgnoringOtherApps:YES];
  [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(refreshAgeLabels:) userInfo:nil repeats:YES];
}
- (void)loadStore {
  NSData *data = [NSData dataWithContentsOfFile:self.docsPath];
  if (data) self.store = [[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] mutableCopy];
  if (!self.store) {
    NSMutableDictionary *files = [@{@"ContentView": [@{@"name":@"ContentView", @"code":@"import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        Text(\"Hello\")\n    }\n}\n\n#Preview {\n    ContentView()\n}\n"} mutableCopy], @"MyApp": [@{@"name":@"MyApp", @"code":@"// This file is listed for the project. The runner hosts ContentView automatically.\n"} mutableCopy]} mutableCopy];
    self.store = [@{@"activeProject":@"myapp", @"projects":[@{@"myapp":[@{@"name":@"MyApp", @"updatedAt":@([NSDate.date timeIntervalSince1970]-86400), @"activeFile":@"ContentView", @"files":files} mutableCopy], @"other":[@{@"name":@"MyOtherApp", @"updatedAt":@([NSDate.date timeIntervalSince1970]-35*86400), @"activeFile":@"ContentView", @"files":[files mutableCopy]} mutableCopy]} mutableCopy]} mutableCopy];
  }
  self.activeProjectID = self.store[@"activeProject"] ?: @"myapp";
}
- (void)saveStore { NSData *data = [NSJSONSerialization dataWithJSONObject:self.store options:NSJSONWritingPrettyPrinted error:nil]; [data writeToFile:self.docsPath atomically:YES]; }
- (NSMutableDictionary *)project { return self.store[@"projects"][self.activeProjectID]; }
- (NSMutableDictionary *)file { return [self project][@"files"][self.activeFileID]; }
- (NSArray *)projectIDs { return [[self.store[@"projects"] allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]; }
- (NSArray *)fileIDs { return [[[self project][@"files"] allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]; }
- (void)buildWindow {
  self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(80,80,1176,765) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO]; self.window.title = @"SwiftStudio";
  self.root = [[NSView alloc] initWithFrame:self.window.contentView.bounds]; self.root.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable; self.root.wantsLayer = YES; self.root.layer.backgroundColor = NSColor.blackColor.CGColor; self.window.contentView = self.root; [self.window makeKeyAndOrderFront:nil];
}
- (NSTextField *)label:(NSString *)text frame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color {
  NSTextField *f = [[NSTextField alloc] initWithFrame:frame]; f.stringValue = text ?: @""; f.font = font; f.textColor = color; f.bezeled = NO; f.drawsBackground = NO; f.editable = NO; f.selectable = NO; [self.dynamicViews addObject:f]; [self.root addSubview:f]; return f;
}
- (NSButton *)button:(NSString *)title frame:(NSRect)frame action:(SEL)action blue:(BOOL)blue {
  NSButton *b = [[NSButton alloc] initWithFrame:frame]; b.title = title; b.font = TitleFont(frame.size.height * 0.55); b.bezelStyle = NSBezelStyleRegularSquare; b.bordered = NO; b.target = self; b.action = action; b.wantsLayer = YES; b.layer.cornerRadius = frame.size.height/2; b.layer.backgroundColor = (blue ? Blue() : NSColor.clearColor).CGColor; [b setContentTintColor:NSColor.whiteColor]; [self.dynamicViews addObject:b]; [self.root addSubview:b]; return b;
}
- (void)clearDynamic { for (NSView *v in self.dynamicViews) [v removeFromSuperview]; [self.dynamicViews removeAllObjects]; }
- (void)addLine:(NSRect)frame { NSBox *box = [[NSBox alloc] initWithFrame:frame]; box.boxType = NSBoxCustom; box.borderColor = NSColor.whiteColor; box.fillColor = NSColor.whiteColor; [self.dynamicViews addObject:box]; [self.root addSubview:box]; }
- (NSString *)relativeAge:(NSNumber *)stamp {
  double seconds = MAX(0, NSDate.date.timeIntervalSince1970 - stamp.doubleValue);
  if (seconds < 60) return @"now";
  if (seconds < 3600) return [NSString stringWithFormat:@"%.0fm ago", floor(seconds / 60)];
  if (seconds < 86400) return [NSString stringWithFormat:@"%.0fh ago", floor(seconds / 3600)];
  if (seconds < 7 * 86400) return [NSString stringWithFormat:@"%.0fd ago", floor(seconds / 86400)];
  return [NSString stringWithFormat:@"%.0fw ago", floor(seconds / (7 * 86400))];
}
- (void)refreshAgeLabels:(id)sender {
  if (self.showingProject) return;
  for (NSString *pid in self.ageLabels) {
    NSTextField *label = self.ageLabels[pid];
    label.stringValue = [self relativeAge:self.store[@"projects"][pid][@"updatedAt"] ?: @(NSDate.date.timeIntervalSince1970)];
  }
}
- (void)showMain {
  self.showingProject = NO; [self clearDynamic]; [self.ageLabels removeAllObjects]; [self label:@"SwiftStudio" frame:NSMakeRect(0,680,1176,72) font:TitleFont(48) color:NSColor.whiteColor].alignment = NSTextAlignmentCenter; [self addLine:NSMakeRect(0,665,1176,2)];
  CGFloat y = 580; for (NSString *pid in self.projectIDs) {
    NSDictionary *p = self.store[@"projects"][pid]; BOOL selected = [pid isEqualToString:self.activeProjectID]; NSButton *row = [self button:@"" frame:NSMakeRect(8,y,1160,64) action:@selector(selectProject:) blue:NO]; row.identifier = pid; row.layer.backgroundColor = (selected ? Blue() : DarkRow()).CGColor; row.layer.cornerRadius = 16;
    [self label:p[@"name"] frame:NSMakeRect(26,y+13,360,42) font:TitleFont(39) color:NSColor.whiteColor];
    NSTextField *age = [self label:[self relativeAge:p[@"updatedAt"]] frame:NSMakeRect(390,y+22,160,26) font:TitleFont(20) color:NSColor.lightGrayColor];
    self.ageLabels[pid] = age; y -= 88;
  }
  [self button:@"+" frame:NSMakeRect(16,18,36,36) action:@selector(newProject:) blue:YES];
  [self button:@"Open" frame:NSMakeRect(62,18,96,36) action:@selector(openSelectedProject:) blue:YES];
  [self button:@"Rename" frame:NSMakeRect(168,18,130,36) action:@selector(renameProject:) blue:YES];
}
- (void)selectProject:(NSButton *)sender { self.activeProjectID = sender.identifier; self.store[@"activeProject"] = self.activeProjectID; [self saveStore]; [self showMain]; }
- (void)openSelectedProject:(id)sender { self.activeFileID = [self project][@"activeFile"] ?: self.fileIDs.firstObject; [self saveStore]; [self showProject]; }
- (void)renameProject:(id)sender {
  NSAlert *alert = [NSAlert new]; alert.messageText = @"Rename project";
  NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,260,28)];
  input.stringValue = [self project][@"name"] ?: @"";
  alert.accessoryView = input; [alert addButtonWithTitle:@"Rename"]; [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] == NSAlertFirstButtonReturn && input.stringValue.length) {
    [self project][@"name"] = input.stringValue;
    [self project][@"updatedAt"] = @(NSDate.date.timeIntervalSince1970);
    [self saveStore]; [self showMain];
  }
}
- (void)newProject:(id)sender {
  NSString *pid = [NSString stringWithFormat:@"project-%.0f", NSDate.date.timeIntervalSince1970]; NSString *name = [NSString stringWithFormat:@"MyApp%lu", (unsigned long)self.projectIDs.count + 1];
  self.store[@"projects"][pid] = [@{@"name":name, @"updatedAt":@(NSDate.date.timeIntervalSince1970), @"activeFile":@"ContentView", @"files":[@{@"ContentView":[@{@"name":@"ContentView", @"code":@"import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        Text(\"Hello\")\n    }\n}\n\n#Preview {\n    ContentView()\n}\n"} mutableCopy]} mutableCopy]} mutableCopy];
  self.activeProjectID = pid; self.store[@"activeProject"] = pid; [self saveStore]; [self showMain];
}
- (void)showProject {
  self.showingProject = YES; [self clearDynamic]; [self.ageLabels removeAllObjects]; NSDictionary *p = [self project]; if (!self.activeFileID) self.activeFileID = p[@"activeFile"] ?: self.fileIDs.firstObject;
  [self button:@"<" frame:NSMakeRect(18,700,32,32) action:@selector(back:) blue:YES]; [self label:p[@"name"] frame:NSMakeRect(64,680,210,58) font:TitleFont(42) color:NSColor.whiteColor]; [self button:@"Send" frame:NSMakeRect(245,690,190,44) action:@selector(sendForPreview:) blue:YES]; [self button:@"Rename" frame:NSMakeRect(448,690,130,44) action:@selector(renameProjectInEditor:) blue:YES]; [self addLine:NSMakeRect(0,674,1176,2)]; [self addLine:NSMakeRect(244,0,2,674)]; [self addLine:NSMakeRect(246,155,930,2)];
  CGFloat y = 625; for (NSString *fid in self.fileIDs) { NSDictionary *f = [self project][@"files"][fid]; if (self.swiftLogo) { NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(10,y-1,32,28)]; iv.image = self.swiftLogo; [self.dynamicViews addObject:iv]; [self.root addSubview:iv]; } [self label:f[@"name"] frame:NSMakeRect(54,y,175,27) font:MonoFont(21) color:NSColor.whiteColor]; NSButton *hit = [self button:@"" frame:NSMakeRect(0,y-4,240,34) action:@selector(selectFile:) blue:NO]; hit.identifier = fid; hit.layer.backgroundColor = ([fid isEqualToString:self.activeFileID] ? Blue() : NSColor.clearColor).CGColor; hit.layer.opacity = [fid isEqualToString:self.activeFileID] ? 0.35 : 0.0; y -= 36; }
  [self button:@"+" frame:NSMakeRect(18,18,32,32) action:@selector(newFile:) blue:YES];
  NSScrollView *editScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(264,165,890,490)]; editScroll.borderType = NSNoBorder; editScroll.hasVerticalScroller = YES; editScroll.wantsLayer = YES; editScroll.layer.backgroundColor = NSColor.blackColor.CGColor;
  self.editor = [[NSTextView alloc] initWithFrame:editScroll.bounds]; self.editor.font = MonoFont(19); self.editor.textColor = NSColor.whiteColor; self.editor.backgroundColor = NSColor.blackColor; self.editor.insertionPointColor = NSColor.whiteColor; self.editor.automaticQuoteSubstitutionEnabled = NO; self.editor.delegate = self; self.editor.string = [self file][@"code"] ?: @""; editScroll.documentView = self.editor; [self.dynamicViews addObject:editScroll]; [self.root addSubview:editScroll];
  NSScrollView *consoleScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(264,16,890,126)]; consoleScroll.hasVerticalScroller = YES; consoleScroll.autohidesScrollers = NO; consoleScroll.wantsLayer = YES; consoleScroll.layer.backgroundColor = NSColor.blackColor.CGColor; self.console = [[NSTextView alloc] initWithFrame:consoleScroll.bounds]; self.console.font = MonoFont(19); self.console.textColor = NSColor.whiteColor; self.console.backgroundColor = NSColor.blackColor; self.console.editable = NO; self.console.verticallyResizable = YES; self.console.maxSize = NSMakeSize(FLT_MAX, FLT_MAX); consoleScroll.documentView = self.console; [self.dynamicViews addObject:consoleScroll]; [self.root addSubview:consoleScroll]; [self refreshConsole:nil];
}
- (void)textDidChange:(NSNotification *)n { [self file][@"code"] = self.editor.string ?: @""; [self project][@"updatedAt"] = @(NSDate.date.timeIntervalSince1970); [self saveStore]; }
- (void)saveEditor { [self file][@"code"] = self.editor.string ?: @""; [self project][@"updatedAt"] = @(NSDate.date.timeIntervalSince1970); [self saveStore]; }
- (void)back:(id)sender { [self saveEditor]; [self showMain]; }
- (void)renameProjectInEditor:(id)sender { [self saveEditor]; [self renameProject:sender]; [self showProject]; }
- (void)selectFile:(NSButton *)sender { [self saveEditor]; self.activeFileID = sender.identifier; [self project][@"activeFile"] = self.activeFileID; [self saveStore]; [self showProject]; }
- (void)newFile:(id)sender { NSString *fid = [NSString stringWithFormat:@"File%lu", (unsigned long)self.fileIDs.count + 1]; [self project][@"files"][fid] = [@{@"name":fid, @"code":@"import SwiftUI\n"} mutableCopy]; self.activeFileID = fid; [self project][@"activeFile"] = fid; [self saveStore]; [self showProject]; }
- (NSString *)combinedSource {
  NSMutableString *source = [NSMutableString string]; for (NSString *fid in self.fileIDs) { [source appendFormat:@"\n// %@.swift\n%@\n", fid, [self project][@"files"][fid][@"code"] ?: @""]; } return source;
}
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
- (BOOL)openPreviewWindowWithSource:(NSString *)source errorText:(NSString **)errorText {
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"swiftstudio-preview-%@", NSUUID.UUID.UUIDString]];
  [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *sourcePath = [dir stringByAppendingPathComponent:@"Preview.swift"];
  NSString *exe = [dir stringByAppendingPathComponent:@"PreviewApp"];
  NSString *cache = [dir stringByAppendingPathComponent:@"module-cache"];
  [[NSFileManager defaultManager] createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *hosted = [[self stripPreviewBlocks:source] stringByAppendingString:@"\n\n@main\nstruct PreviewHostApp: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}\n"];
  [hosted writeToFile:sourcePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
  NSTask *compile = [NSTask new]; compile.launchPath = @"/usr/bin/swiftc"; compile.arguments = @[@"-parse-as-library", @"-module-cache-path", cache, sourcePath, @"-o", exe];
  NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy]; env[@"CLANG_MODULE_CACHE_PATH"] = cache; compile.environment = env;
  NSPipe *outPipe = [NSPipe pipe]; NSPipe *errPipe = [NSPipe pipe]; compile.standardOutput = outPipe; compile.standardError = errPipe; NSDate *start = NSDate.date; [compile launch];
  while (compile.isRunning && [NSDate.date timeIntervalSinceDate:start] < 75) [NSThread sleepForTimeInterval:0.15];
  if (compile.isRunning) { [compile terminate]; if (errorText) *errorText = @"Preview window compile timed out."; return NO; }
  NSString *compilerOut = [[NSString alloc] initWithData:[outPipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding] ?: @"";
  NSString *compilerErr = [[NSString alloc] initWithData:[errPipe.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding] ?: @"";
  if (compile.terminationStatus != 0) { if (errorText) *errorText = compilerErr.length ? compilerErr : (compilerOut.length ? compilerOut : @"Preview window compile failed."); return NO; }
  NSTask *run = [NSTask new]; run.launchPath = exe; run.standardOutput = [NSPipe pipe]; run.standardError = [NSPipe pipe]; [run launch];
  return YES;
}
- (NSString *)bar:(double)value { NSInteger fill = (NSInteger)round(MAX(0, MIN(100, value)) * 15.0 / 100.0); NSMutableString *s = [@"[" mutableCopy]; for (NSInteger i=0;i<fill;i++) [s appendString:@"="]; [s appendString:@">"]; for (NSInteger i=fill;i<15;i++) [s appendString:@" "]; [s appendString:@"]"]; return s; }
- (void)appendConsole:(NSString *)line { if (!self.consoleLog) self.consoleLog = [NSMutableString string]; if (line.length) [self.consoleLog appendFormat:@"%@\n", line]; [self refreshConsole:nil]; }
- (void)refreshConsole:(id)sender {
  if (!self.console) return;
  if (!self.pendingRequestID) { self.console.string = self.consoleLog ?: @""; [self.console scrollRangeToVisible:NSMakeRange(self.console.string.length, 0)]; return; }
  double send = [GetDocument(@"Percent/Send", nil)[@"%"] doubleValue]; double compile = [GetDocument(@"Percent/Compile", nil)[@"%"] doubleValue];
  NSMutableString *text = [NSMutableString stringWithFormat:@"Sending...%@ %.0f%%\nCompiling...%@ %.0f%%\n", [self bar:send], send, [self bar:compile], compile];
  [text appendString:self.consoleLog ?: @""];
  self.console.string = text;
  [self.console scrollRangeToVisible:NSMakeRange(self.console.string.length, 0)];
}
- (void)sendForPreview:(id)sender {
  [self saveEditor]; self.pendingRequestID = [NSString stringWithFormat:@"%.0f", NSDate.date.timeIntervalSince1970 * 1000]; SetPercent(@"Send", 5); SetPercent(@"Compile", 0); [self refreshConsole:nil];
  NSDictionary *p = [self project]; NSError *error = nil;
  SetPercent(@"Send", 35);
  NSString *source = [self combinedSource];
  SetPercent(@"Send", 70);
  BOOL ok = PatchDocument([NSString stringWithFormat:@"Threads/%@", self.initialThread ?: @"Thread1"], @{@"send":source, @"appName":p[@"name"] ?: @"SwiftUI App", @"requestId":self.pendingRequestID, @"status":@"queued", @"preview":@"", @"error":@"", @"sentAt":NSDate.date}, &error);
  SetPercent(@"Send", ok ? 100 : 0); [self refreshConsole:nil]; if (!ok) { [self appendConsole:[NSString stringWithFormat:@"Send failed: %@", error.localizedDescription]]; self.pendingRequestID = nil; [self refreshConsole:nil]; return; }
  [NSTimer scheduledTimerWithTimeInterval:1.2 target:self selector:@selector(checkPreview:) userInfo:nil repeats:NO];
}
- (void)checkPreview:(id)sender {
  NSDictionary *doc = GetDocument([NSString stringWithFormat:@"Threads/%@", self.initialThread ?: @"Thread1"], nil); [self refreshConsole:nil];
  if (self.pendingRequestID && ![doc[@"requestId"] isEqualToString:self.pendingRequestID]) { [NSTimer scheduledTimerWithTimeInterval:1.2 target:self selector:@selector(checkPreview:) userInfo:nil repeats:NO]; return; }
  NSString *status = doc[@"status"] ?: @""; if ([status isEqualToString:@"complete"] || [status isEqualToString:@"error"]) {
    if ([status isEqualToString:@"complete"]) {
      NSString *errorText = nil;
      if ([self openPreviewWindowWithSource:[self combinedSource] errorText:&errorText]) [self appendConsole:@"Opened preview window"];
      else [self appendConsole:errorText ?: @"Could not open preview window"];
    } else {
      if ([doc[@"preview"] length]) [self appendConsole:doc[@"preview"]];
    }
    if ([doc[@"error"] length]) [self appendConsole:doc[@"error"]]; self.pendingRequestID = nil; [self refreshConsole:nil]; return; }
  [NSTimer scheduledTimerWithTimeInterval:1.2 target:self selector:@selector(checkPreview:) userInfo:nil repeats:NO];
}
@end

int main(int argc, const char *argv[]) {
  if (argc > 1 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"))) { puts("SwiftStudio\n\nUsage:\n  ~/cmds/code_studio [--thread Thread1]\n\nNative NSApplication Studio. Sends raw SwiftUI source to Firestore and displays Send/Compile percentages."); return 0; }
  @autoreleasepool { NSApplication *app = NSApplication.sharedApplication; StudioDelegate *delegate = [StudioDelegate new]; delegate.initialThread = @"Thread1"; for (int i=1;i+1<argc;i++) if (!strcmp(argv[i],"--thread")) delegate.initialThread = [NSString stringWithUTF8String:argv[i+1]]; app.delegate = delegate; [app run]; }
  return 0;
}

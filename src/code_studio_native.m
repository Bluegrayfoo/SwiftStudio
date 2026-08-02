#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <float.h>
#import <math.h>
#import <sys/stat.h>

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
    NSDateFormatter *fmt = [NSDateFormatter new]; fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; fmt.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0]; fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    return @{@"timestampValue": [fmt stringFromDate:value]};
  }
  if ([value isKindOfClass:[NSDictionary class]]) {
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    for (NSString *key in value) fields[key] = FirestoreValue(value[key]);
    return @{@"mapValue": @{@"fields": fields}};
  }
  if ([value isKindOfClass:[NSArray class]]) {
    NSMutableArray *values = [NSMutableArray array];
    for (id item in (NSArray *)value) [values addObject:FirestoreValue(item)];
    return @{@"arrayValue": @{@"values": values}};
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
  if (value[@"arrayValue"]) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *item in value[@"arrayValue"][@"values"] ?: @[]) {
      id native = NativeValue(item);
      if (native) [out addObject:native];
    }
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

static NSString *ProcessArch(void) {
#if defined(__x86_64__)
  return @"x86_64";
#elif defined(__arm64__)
  return @"arm64";
#else
  return @"native";
#endif
}

static void UpdateHistory(NSString *appName) {
  NSDictionary *doc = GetDocument(@"LatestHistory/History", nil); NSMutableDictionary *hist = [NSMutableDictionary dictionaryWithDictionary:doc[@"hist"] ?: @{}]; NSDate *now = NSDate.date; NSDate *cutoff = [now dateByAddingTimeInterval:-7*24*60*60];
  NSDateFormatter *iso = [NSDateFormatter new]; iso.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; iso.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
  for (NSString *key in [hist.allKeys copy]) { NSDate *date = [iso dateFromString:hist[key][@"timestamp"] ?: @""]; if (!date || [date compare:cutoff] == NSOrderedAscending) [hist removeObjectForKey:key]; }
  NSDateFormatter *tf = [NSDateFormatter new]; tf.dateFormat = @"h:mm a"; NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"MMMM d"; NSString *stamp = [iso stringFromDate:now];
  hist[stamp] = @{@"text":[NSString stringWithFormat:@"%@ was run at %@ on %@", appName, [tf stringFromDate:now], [df stringFromDate:now]], @"timestamp":stamp}; PatchDocument(@"LatestHistory/History", @{@"hist":hist}, nil);
}

@interface StudioDelegate : NSObject <NSApplicationDelegate, NSTextViewDelegate, NSWindowDelegate>
@property NSWindow *window;
@property NSView *root;
@property NSMutableDictionary *store;
@property NSString *activeProjectID;
@property NSString *activeFileID;
@property NSString *pendingRequestID;
@property NSString *initialThread;
@property NSMutableArray<NSView *> *dynamicViews;
@property NSMutableDictionary<NSString *, NSTextField *> *ageLabels;
@property NSMutableDictionary<NSString *, NSButton *> *projectRows;
@property NSTextView *editor;
@property NSTextView *console;
@property NSMutableString *consoleLog;
@property NSUInteger consoleInputStart;
@property BOOL updatingConsoleProgrammatically;
@property BOOL keepConsoleLogForNextSend;
@property BOOL compileOnlyRequest;
@property BOOL terminalJobPending;
@property NSImage *swiftLogo;
@property BOOL showingProject;
@property BOOL openingPreview;
@property double lastSendPercent;
@property double lastCompilePercent;
@property double lastRunPercent;
@property NSDate *lastPercentFetchAt;
@property NSTask *previewTask;
@property BOOL applyingHighlight;
@property BOOL previewPaneCollapsed;
@property BOOL previewPaneWide;
@property NSRect previewPaneFrame;
@property NSView *previewContainerView;
@property NSView *previewContentView;
@property NSWindow *previewWindow;
@property void *previewLibraryHandle;
@property NSString *lastIncomingShareID;
@property NSMutableDictionary *incomingSharedProject;
@property NSString *incomingShareMessage;
@property NSString *incomingShareStatus;
@property NSMutableArray<NSView *> *floatingPreviewControls;
@property BOOL fishyPanelMode;
@property NSString *fishyBubbleText;
@property BOOL showingChat;
@property BOOL showingTemplatePicker;
@property NSArray *chatMessages;
@property NSString *lastChatSignature;
@property NSTextView *chatInput;
@property NSTextView *chatCodeInput;
@property NSString *chatDraftText;
@property NSString *chatDraftCode;
@property BOOL chatComposerHasCode;
@property NSView *chatTranscriptView;
@property NSTextField *chatPlaceholder;
@property id shortcutMonitor;
@end

@implementation StudioDelegate
- (NSString *)docsPath { return [@"~/cmds/swift_studio_projects.json" stringByExpandingTildeInPath]; }
- (void)applicationDidFinishLaunching:(NSNotification *)n {
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]; self.dynamicViews = [NSMutableArray array]; self.ageLabels = [NSMutableDictionary dictionary]; self.projectRows = [NSMutableDictionary dictionary]; self.consoleLog = [NSMutableString string]; self.previewPaneCollapsed = YES; self.swiftLogo = [[NSImage alloc] initWithContentsOfFile:[@"~/cmds/swiftlogo.png" stringByExpandingTildeInPath]];
  [self loadStore]; [self buildWindow]; [self showMain]; UpdateHistory(@"SwiftStudio"); [NSApp activateIgnoringOtherApps:YES];
  __weak StudioDelegate *weakSelf = self;
  self.shortcutMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
    return [weakSelf handleShortcutEvent:event] ? nil : event;
  }];
  [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(refreshAgeLabels:) userInfo:nil repeats:YES];
  [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updatePreviewPlacement:) userInfo:nil repeats:YES];
  [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(checkIncomingProjectShare:) userInfo:nil repeats:YES];
  [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(refreshChatIfOpen:) userInfo:nil repeats:YES];
}
- (void)applicationWillTerminate:(NSNotification *)notification { if (self.shortcutMonitor) [NSEvent removeMonitor:self.shortcutMonitor]; self.shortcutMonitor = nil; }
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
  self.window.delegate = self;
  self.root = [[NSView alloc] initWithFrame:self.window.contentView.bounds]; self.root.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable; self.root.wantsLayer = YES; self.root.layer.backgroundColor = NSColor.blackColor.CGColor; self.window.contentView = self.root; [self.window makeKeyAndOrderFront:nil];
}
- (NSTextField *)label:(NSString *)text frame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color {
  NSTextField *f = [[NSTextField alloc] initWithFrame:frame]; f.stringValue = text ?: @""; f.font = font; f.textColor = color; f.bezeled = NO; f.drawsBackground = NO; f.editable = NO; f.selectable = NO; [self.dynamicViews addObject:f]; [self.root addSubview:f]; return f;
}
- (NSButton *)button:(NSString *)title frame:(NSRect)frame action:(SEL)action blue:(BOOL)blue {
  NSButton *b = [[NSButton alloc] initWithFrame:frame]; b.title = title; b.font = TitleFont(frame.size.height * 0.55); b.bezelStyle = NSBezelStyleRegularSquare; b.bordered = NO; b.target = self; b.action = action; b.wantsLayer = YES; b.layer.cornerRadius = frame.size.height/2; b.layer.backgroundColor = (blue ? Blue() : NSColor.clearColor).CGColor; [b setContentTintColor:NSColor.whiteColor]; [self.dynamicViews addObject:b]; [self.root addSubview:b]; return b;
}
- (NSButton *)redButton:(NSString *)title frame:(NSRect)frame action:(SEL)action {
  NSButton *b = [self button:title frame:frame action:action blue:NO];
  b.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.78 green:0.05 blue:0.06 alpha:1.0].CGColor;
  return b;
}
- (void)tuneScrollView:(NSScrollView *)scrollView {
  scrollView.hasVerticalScroller = YES;
  scrollView.autohidesScrollers = NO;
  scrollView.verticalLineScroll = 10;
  scrollView.verticalPageScroll = 80;
  scrollView.scrollerStyle = NSScrollerStyleOverlay;
}
- (void)clearDynamic { for (NSView *v in self.dynamicViews) [v removeFromSuperview]; [self.dynamicViews removeAllObjects]; }
- (void)addLine:(NSRect)frame { NSBox *box = [[NSBox alloc] initWithFrame:frame]; box.boxType = NSBoxCustom; box.borderColor = NSColor.whiteColor; box.fillColor = NSColor.whiteColor; [self.dynamicViews addObject:box]; [self.root addSubview:box]; }
- (void)addBorderOverlay:(NSRect)frame {
  NSView *border = [[NSView alloc] initWithFrame:NSIntegralRect(NSInsetRect(frame, 1, 1))];
  border.wantsLayer = YES;
  border.layer.backgroundColor = NSColor.clearColor.CGColor;
  border.layer.borderColor = NSColor.whiteColor.CGColor;
  border.layer.borderWidth = 2;
  [self.dynamicViews addObject:border];
  [self.root addSubview:border positioned:NSWindowAbove relativeTo:nil];
}
- (NSString *)terminalPrompt { return @"noah@swift-studio ∫ "; }
- (void)appendPromptToConsoleLog {
  if (!self.consoleLog) self.consoleLog = [NSMutableString string];
  NSString *prompt = [self terminalPrompt];
  if (![self.consoleLog hasSuffix:prompt]) [self.consoleLog appendString:prompt];
}
- (void)showConsoleText:(NSString *)text inputAtEnd:(BOOL)inputAtEnd {
  if (!self.console) return;
  self.updatingConsoleProgrammatically = YES;
  self.console.string = text ?: @"";
  if (self.fishyPanelMode) {
    NSDictionary *base = @{NSForegroundColorAttributeName:NSColor.whiteColor, NSFontAttributeName:MonoFont(19)};
    [self.console.textStorage setAttributes:base range:NSMakeRange(0, self.console.string.length)];
    NSColor *cyan = [NSColor colorWithCalibratedRed:0.05 green:1.0 blue:1.0 alpha:1.0];
    NSColor *green = [NSColor colorWithCalibratedRed:0.2 green:1.0 blue:0.2 alpha:1.0];
    NSColor *blue = [NSColor colorWithCalibratedRed:0.24 green:0.52 blue:1.0 alpha:1.0];
    [self colorConsolePattern:@"Fishy" color:NSColor.whiteColor font:TitleFont(40)];
    [self colorConsolePattern:@"SwiftStudio" color:blue font:TitleFont(38)];
    [self colorConsolePattern:@"</>[^\\n]*" color:cyan font:MonoFont(19)];
    [self colorConsolePattern:@"Edited [^\\n]*" color:cyan font:MonoFont(19)];
  }
  self.consoleInputStart = inputAtEnd ? self.console.string.length : self.consoleInputStart;
  self.console.editable = YES;
  self.console.selectable = YES;
  if (self.fishyPanelMode) {
    [self.console setSelectedRange:NSMakeRange(0, 0)];
    [self.console scrollToBeginningOfDocument:nil];
    dispatch_async(dispatch_get_main_queue(), ^{ [self.console scrollToBeginningOfDocument:nil]; });
  } else {
    [self.console setSelectedRange:NSMakeRange(self.console.string.length, 0)];
    [self.console scrollRangeToVisible:NSMakeRange(self.console.string.length, 0)];
  }
  self.updatingConsoleProgrammatically = NO;
}
- (void)colorConsolePattern:(NSString *)pattern color:(NSColor *)color font:(NSFont *)font {
  if (!self.console.string.length) return;
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
  [regex enumerateMatchesInString:self.console.string options:0 range:NSMakeRange(0, self.console.string.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
    if (result.range.location == NSNotFound) return;
    [self.console.textStorage addAttribute:NSForegroundColorAttributeName value:color range:result.range];
    [self.console.textStorage addAttribute:NSFontAttributeName value:font range:result.range];
  }];
}
- (NSString *)projectIDMatchingName:(NSString *)name {
  if (!name.length) return nil;
  for (NSString *pid in self.projectIDs) {
    NSString *projectName = self.store[@"projects"][pid][@"name"] ?: @"";
    if ([projectName isEqualToString:name]) return pid;
  }
  return nil;
}
- (NSString *)uniqueProjectName:(NSString *)name {
  NSString *base = name.length ? name : @"SharedProject";
  NSString *candidate = base;
  NSUInteger suffix = 2;
  BOOL exists = YES;
  while (exists) {
    exists = NO;
    for (NSString *pid in self.projectIDs) {
      NSString *projectName = self.store[@"projects"][pid][@"name"] ?: @"";
      if ([projectName isEqualToString:candidate]) { exists = YES; break; }
    }
    if (exists) candidate = [NSString stringWithFormat:@"%@ %lu", base, (unsigned long)suffix++];
  }
  return candidate;
}
- (NSString *)projectIDForNewProjectName:(NSString *)name {
  NSString *base = [[(name.length ? name : @"SharedProject") componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@""];
  if (!base.length) base = @"SharedProject";
  NSString *pid = [base lowercaseString];
  NSUInteger suffix = 2;
  while (self.store[@"projects"][pid]) pid = [NSString stringWithFormat:@"%@%lu", [base lowercaseString], (unsigned long)suffix++];
  return pid;
}
- (void)addNoticeCardIfNeeded {
  if (!self.incomingSharedProject) return;
  NSRect b = self.root.bounds;
  BOOL returnedProject = [self.incomingShareStatus isEqualToString:@"sent_back"];
  CGFloat w = returnedProject ? 560 : 440, h = 66, x = MAX(18, (b.size.width - w) / 2), y = MAX(76, b.size.height - 158);
  NSView *card = [[NSView alloc] initWithFrame:NSMakeRect(x, y, w, h)];
  card.wantsLayer = YES;
  card.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.28 alpha:0.96].CGColor;
  card.layer.cornerRadius = 12;
  card.layer.borderColor = [NSColor colorWithCalibratedWhite:0.55 alpha:1.0].CGColor;
  card.layer.borderWidth = 1;
  NSTextField *message = [[NSTextField alloc] initWithFrame:NSMakeRect(18, 17, returnedProject ? w - 348 : w - 226, 32)];
  message.stringValue = self.incomingShareMessage ?: @"Project sent back";
  message.font = TitleFont(22);
  message.textColor = NSColor.whiteColor;
  message.bezeled = NO;
  message.drawsBackground = NO;
  message.editable = NO;
  message.selectable = NO;
  [card addSubview:message];
  NSButton *decline = [[NSButton alloc] initWithFrame:NSMakeRect(returnedProject ? w - 326 : w - 204, 14, 86, 38)];
  decline.title = @"Decline";
  decline.font = TitleFont(18);
  decline.bezelStyle = NSBezelStyleRegularSquare;
  decline.bordered = NO;
  decline.target = self;
  decline.action = @selector(declineSharedProject:);
  decline.wantsLayer = YES;
  decline.layer.cornerRadius = 19;
  decline.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.70 green:0.06 blue:0.06 alpha:1.0].CGColor;
  [decline setContentTintColor:NSColor.whiteColor];
  [card addSubview:decline];
  if (returnedProject) {
    NSButton *add = [[NSButton alloc] initWithFrame:NSMakeRect(w - 228, 14, 122, 38)];
    add.title = @"Add to projects";
    add.font = TitleFont(15);
    add.bezelStyle = NSBezelStyleRegularSquare;
    add.bordered = NO;
    add.target = self;
    add.action = @selector(addIncomingProjectToProjects:);
    add.wantsLayer = YES;
    add.layer.cornerRadius = 19;
    add.layer.backgroundColor = Blue().CGColor;
    [add setContentTintColor:NSColor.whiteColor];
    [card addSubview:add];
  }
  NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(w - 96, 14, 76, 38)];
  button.title = [self.incomingShareMessage isEqualToString:@"Add to projects"] ? @"+" : @"Include";
  button.font = TitleFont(21);
  button.bezelStyle = NSBezelStyleRegularSquare;
  button.bordered = NO;
  button.target = self;
  button.action = [self.incomingShareStatus isEqualToString:@"add_to_projects"] ? @selector(addIncomingProjectToProjects:) : @selector(includeSharedProject:);
  button.wantsLayer = YES;
  button.layer.cornerRadius = 19;
  button.layer.backgroundColor = Blue().CGColor;
  [button setContentTintColor:NSColor.whiteColor];
  [card addSubview:button];
  [self.dynamicViews addObject:card];
  [self.root addSubview:card positioned:NSWindowAbove relativeTo:nil];
}
- (BOOL)isFullScreen { return (self.window.styleMask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen; }
- (BOOL)previewPaneVisible { return [self isFullScreen] && !self.previewPaneCollapsed; }
- (void)redrawCurrentPage {
  if (self.showingChat) [self showChatPage];
  else if (self.showingTemplatePicker) [self showTemplatePicker];
  else if (self.showingProject) [self showProject];
  else [self showMain];
}
- (void)updatePreviewPlacement:(id)sender { [self placePreviewContent]; }
- (void)windowDidResize:(NSNotification *)notification { if (self.showingProject) [self saveEditor]; [self redrawCurrentPage]; [self placePreviewContent]; }
- (void)windowDidEnterFullScreen:(NSNotification *)notification { self.previewPaneCollapsed = NO; [self redrawCurrentPage]; [self placePreviewContent]; }
- (void)windowDidExitFullScreen:(NSNotification *)notification { [self redrawCurrentPage]; [self placePreviewContent]; }
- (BOOL)handleShortcutEvent:(NSEvent *)event {
  NSString *key = event.charactersIgnoringModifiers.lowercaseString ?: @"";
  NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
  BOOL command = (flags & NSEventModifierFlagCommand) != 0;
  BOOL control = (flags & NSEventModifierFlagControl) != 0;
  BOOL shift = (flags & NSEventModifierFlagShift) != 0;
  BOOL option = (flags & NSEventModifierFlagOption) != 0;
  if (command && !control && !option) {
    SEL action = nil;
    if ([key isEqualToString:@"c"]) action = @selector(copy:);
    else if ([key isEqualToString:@"v"]) action = @selector(paste:);
    else if ([key isEqualToString:@"z"] && shift) action = @selector(redo:);
    else if ([key isEqualToString:@"z"]) action = @selector(undo:);
    if (action) {
      [NSApp sendAction:action to:nil from:self];
      return YES;
    }
  }
  if (control && [key isEqualToString:@"p"] && self.showingProject) {
    if (shift && !option) {
      [self toggleWidePreviewShortcut:nil];
      return YES;
    }
    if (option && !shift) {
      [self toggleNormalPreviewShortcut:nil];
      return YES;
    }
    if (!shift && !option) {
      [self togglePreviewPane:nil];
      return YES;
    }
  }
  return NO;
}
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
  self.showingChat = NO; self.showingTemplatePicker = NO; self.showingProject = NO; [self clearDynamic]; [self.ageLabels removeAllObjects]; [self.projectRows removeAllObjects];
  NSRect b = self.root.bounds;
  CGFloat headerY = MAX(98, b.size.height - 86);
  NSTextField *title = [self label:@"SwiftStudio" frame:NSMakeRect(0,headerY,b.size.width,72) font:TitleFont(48) color:NSColor.whiteColor];
  title.alignment = NSTextAlignmentCenter;
  [self addLine:NSMakeRect(0,headerY-10,b.size.width,2)];

  CGFloat controlsH = 70;
  CGFloat listY = controlsH + 14;
  CGFloat listH = MAX(120, headerY - 36 - listY);
  NSScrollView *projectScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,listY,b.size.width,listH)];
  projectScroll.borderType = NSNoBorder;
  projectScroll.hasVerticalScroller = YES;
  projectScroll.drawsBackground = NO;
  [self tuneScrollView:projectScroll];
  CGFloat rowW = MAX(360, b.size.width - 20);
  CGFloat contentH = MAX(listH, self.projectIDs.count * 88 + 12);
  NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0,0,b.size.width,contentH)];
  CGFloat y = contentH - 76;
  for (NSString *pid in self.projectIDs) {
    NSDictionary *p = self.store[@"projects"][pid];
    BOOL selected = [pid isEqualToString:self.activeProjectID];
    NSButton *row = [[NSButton alloc] initWithFrame:NSMakeRect(10,y,rowW,64)];
    row.title = @"";
    row.bordered = NO;
    row.target = self;
    row.action = @selector(selectProject:);
    row.identifier = pid;
    row.wantsLayer = YES;
    row.layer.backgroundColor = (selected ? Blue() : DarkRow()).CGColor;
    row.layer.cornerRadius = 16;
    [content addSubview:row];
    self.projectRows[pid] = row;

    NSTextField *name = [[NSTextField alloc] initWithFrame:NSMakeRect(28,y+13,MIN(360,rowW-210),42)];
    name.stringValue = p[@"name"] ?: @"Project";
    name.font = TitleFont(39);
    name.textColor = NSColor.whiteColor;
    name.bezeled = NO; name.drawsBackground = NO; name.editable = NO; name.selectable = NO;
    [content addSubview:name];

    NSTextField *age = [[NSTextField alloc] initWithFrame:NSMakeRect(MIN(390,rowW-170),y+22,160,26)];
    age.stringValue = [self relativeAge:p[@"updatedAt"]];
    age.font = TitleFont(20);
    age.textColor = NSColor.lightGrayColor;
    age.bezeled = NO; age.drawsBackground = NO; age.editable = NO; age.selectable = NO;
    [content addSubview:age];
    self.ageLabels[pid] = age;
    y -= 88;
  }
  projectScroll.documentView = content;
  [self.dynamicViews addObject:projectScroll];
  [self.root addSubview:projectScroll];
  if (contentH > listH) [[projectScroll contentView] scrollToPoint:NSMakePoint(0, contentH - listH)];

  [self button:@"+" frame:NSMakeRect(16,18,36,36) action:@selector(newProject:) blue:YES];
  [self button:@"Open" frame:NSMakeRect(62,18,96,36) action:@selector(openSelectedProject:) blue:YES];
  [self button:@"Rename" frame:NSMakeRect(168,18,130,36) action:@selector(renameProject:) blue:YES];
  [self redButton:@"Delete" frame:NSMakeRect(308,18,118,36) action:@selector(deleteProject:)];
  [self button:@"Add project from template" frame:NSMakeRect(438,18,MIN(330,MAX(250,b.size.width-456)),36) action:@selector(showTemplatePicker) blue:YES];
  [self addNoticeCardIfNeeded];
}
- (NSArray *)loadChatMessages {
  NSError *error = nil;
  NSDictionary *doc = GetDocument(@"Threads/Chat", &error);
  return [doc[@"messages"] isKindOfClass:[NSArray class]] ? doc[@"messages"] : @[];
}
- (void)saveChatMessageText:(NSString *)text code:(NSString *)code {
  NSString *body = text ?: @"";
  if (!body.length && !code.length) return;
  NSMutableArray *messages = [[self loadChatMessages] mutableCopy];
  NSString *messageID = [NSString stringWithFormat:@"studio-chat-%.0f", NSDate.date.timeIntervalSince1970 * 1000];
  NSMutableDictionary *message = [@{@"id":messageID, @"sender":@"studio", @"text":body, @"sentAt":NSDate.date} mutableCopy];
  if (code.length) message[@"code"] = code;
  [messages addObject:message];
  while (messages.count > 80) [messages removeObjectAtIndex:0];
  PatchDocument(@"Threads/Chat", @{@"messages":messages, @"updatedAt":NSDate.date}, nil);
  self.chatMessages = messages;
}
- (void)addChatBubble:(NSDictionary *)message y:(CGFloat *)y maxWidth:(CGFloat)maxWidth {
  BOOL mine = [message[@"sender"] isEqualToString:@"studio"];
  NSString *text = message[@"text"] ?: @"";
  NSString *code = message[@"code"] ?: @"";
  CGFloat bubbleW = MIN(520, maxWidth * 0.58);
  CGFloat x = mine ? maxWidth - bubbleW - 26 : 26;
  CGFloat codeH = code.length ? 92 : 0;
  CGFloat textH = MAX(34, MIN(110, 24 + ceil(text.length / 31.0) * 24));
  CGFloat h = textH + codeH + 20;
  NSView *card = [[NSView alloc] initWithFrame:NSMakeRect(x, *y - h, bubbleW, h)];
  card.wantsLayer = YES;
  card.layer.backgroundColor = (mine ? Blue() : [NSColor colorWithCalibratedWhite:0.58 alpha:1.0]).CGColor;
  card.layer.cornerRadius = 16;
  NSTextField *body = [[NSTextField alloc] initWithFrame:NSMakeRect(16, h - textH - 8, bubbleW - 32, textH)];
  body.stringValue = text.length ? text : @"Code";
  body.font = TitleFont(19);
  body.textColor = NSColor.whiteColor;
  body.bezeled = NO; body.drawsBackground = NO; body.editable = NO; body.selectable = NO;
  [card addSubview:body];
  if (code.length) {
    NSView *codeBox = [[NSView alloc] initWithFrame:NSMakeRect(16, 16, bubbleW - 32, 76)];
    codeBox.wantsLayer = YES; codeBox.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.35 alpha:1.0].CGColor; codeBox.layer.cornerRadius = 12;
    NSTextField *header = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 47, bubbleW - 64, 22)];
    header.stringValue = @"</>  Swift"; header.font = MonoFont(16); header.textColor = [NSColor colorWithCalibratedWhite:0.78 alpha:1.0]; header.bezeled = NO; header.drawsBackground = NO; header.editable = NO; header.selectable = NO;
    [codeBox addSubview:header];
    NSBox *line = [[NSBox alloc] initWithFrame:NSMakeRect(0, 44, bubbleW - 32, 2)]; line.boxType = NSBoxCustom; line.borderColor = [NSColor colorWithCalibratedWhite:0.78 alpha:1.0]; line.fillColor = [NSColor colorWithCalibratedWhite:0.78 alpha:1.0]; [codeBox addSubview:line];
    NSString *snippet = code.length > 42 ? [[code substringToIndex:42] stringByAppendingString:@"..."] : code;
    NSTextField *snippetField = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 12, bubbleW - 64, 24)];
    snippetField.stringValue = [[snippet componentsSeparatedByString:@"\n"] firstObject] ?: @"some code"; snippetField.font = MonoFont(15); snippetField.textColor = NSColor.whiteColor; snippetField.bezeled = NO; snippetField.drawsBackground = NO; snippetField.editable = NO; snippetField.selectable = NO;
    [codeBox addSubview:snippetField];
    [card addSubview:codeBox];
  }
  if (self.chatTranscriptView) {
    [self.chatTranscriptView addSubview:card];
  } else {
    [self.dynamicViews addObject:card];
    [self.root addSubview:card];
  }
  *y -= h + 18;
}
- (void)showChatPage {
  self.showingChat = YES; self.showingProject = NO;
  [self saveEditor]; [self clearDynamic];
  self.editor = nil;
  self.console = nil;
  NSRect b = self.root.bounds;
  self.chatMessages = [self loadChatMessages];
  [self button:@"<" frame:NSMakeRect(18,b.size.height-88,54,54) action:@selector(closeChatPage:) blue:YES];
  [self label:@"Chat" frame:NSMakeRect(92,b.size.height-92,250,68) font:TitleFont(46) color:NSColor.whiteColor];
  CGFloat composerH = self.chatComposerHasCode ? 178 : 56;
  CGFloat transcriptY = composerH + 86;
  CGFloat transcriptH = MAX(120, b.size.height - transcriptY - 130);
  CGFloat transcriptW = b.size.width - 36;
  NSScrollView *transcriptScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(18, transcriptY, transcriptW, transcriptH)];
  [self tuneScrollView:transcriptScroll];
  transcriptScroll.drawsBackground = NO;
  transcriptScroll.borderType = NSNoBorder;
  CGFloat docH = MAX(transcriptH, 24 + self.chatMessages.count * 150);
  self.chatTranscriptView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, transcriptW, docH)];
  self.chatTranscriptView.wantsLayer = YES;
  self.chatTranscriptView.layer.backgroundColor = NSColor.blackColor.CGColor;
  transcriptScroll.documentView = self.chatTranscriptView;
  [self.dynamicViews addObject:transcriptScroll];
  [self.root addSubview:transcriptScroll];
  CGFloat y = docH - 18;
  for (NSDictionary *message in self.chatMessages) [self addChatBubble:message y:&y maxWidth:transcriptW];
  [transcriptScroll.contentView scrollToPoint:NSMakePoint(0, 0)];
  [self button:@"</> Code box" frame:NSMakeRect(18,composerH+34,170,38) action:@selector(addChatCodeBox:) blue:YES];
  NSView *input = [[NSView alloc] initWithFrame:NSMakeRect(18,18,b.size.width-100,composerH)];
  input.wantsLayer = YES; input.layer.backgroundColor = NSColor.blackColor.CGColor; input.layer.cornerRadius = 18; input.layer.borderColor = NSColor.whiteColor.CGColor; input.layer.borderWidth = 2;
  NSScrollView *messageScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(18, self.chatComposerHasCode ? composerH - 60 : 8, input.frame.size.width - 36, 44)];
  messageScroll.borderType = NSNoBorder; messageScroll.hasVerticalScroller = NO; messageScroll.drawsBackground = NO;
  self.chatInput = [[NSTextView alloc] initWithFrame:messageScroll.bounds];
  self.chatInput.font = TitleFont(20); self.chatInput.textColor = NSColor.whiteColor; self.chatInput.backgroundColor = NSColor.clearColor; self.chatInput.drawsBackground = NO; self.chatInput.insertionPointColor = NSColor.whiteColor; self.chatInput.string = self.chatDraftText ?: @""; self.chatInput.delegate = self; self.chatInput.allowsUndo = YES; self.chatInput.automaticQuoteSubstitutionEnabled = NO; self.chatInput.automaticDashSubstitutionEnabled = NO; self.chatInput.automaticTextReplacementEnabled = NO;
  self.chatPlaceholder = [[NSTextField alloc] initWithFrame:NSMakeRect(22, self.chatComposerHasCode ? composerH - 48 : 14, input.frame.size.width-44,30)];
  self.chatPlaceholder.stringValue = @"Type your message here..."; self.chatPlaceholder.font = TitleFont(20); self.chatPlaceholder.textColor = [NSColor colorWithCalibratedWhite:0.72 alpha:1.0]; self.chatPlaceholder.bezeled = NO; self.chatPlaceholder.drawsBackground = NO; self.chatPlaceholder.editable = NO; self.chatPlaceholder.selectable = NO; self.chatPlaceholder.hidden = self.chatInput.string.length > 0;
  [input addSubview:self.chatPlaceholder];
  messageScroll.documentView = self.chatInput; [input addSubview:messageScroll];
  if (self.chatComposerHasCode) {
    NSView *codeShell = [[NSView alloc] initWithFrame:NSMakeRect(18, 14, input.frame.size.width - 36, composerH - 82)];
    codeShell.wantsLayer = YES; codeShell.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.35 alpha:1.0].CGColor; codeShell.layer.cornerRadius = 12;
    NSTextField *header = [[NSTextField alloc] initWithFrame:NSMakeRect(16, codeShell.frame.size.height - 30, codeShell.frame.size.width - 32, 22)];
    header.stringValue = @"</>  Swift"; header.font = MonoFont(16); header.textColor = [NSColor colorWithCalibratedWhite:0.78 alpha:1.0]; header.bezeled = NO; header.drawsBackground = NO; header.editable = NO; header.selectable = NO; [codeShell addSubview:header];
    NSScrollView *codeScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 10, codeShell.frame.size.width - 24, codeShell.frame.size.height - 44)];
    codeScroll.borderType = NSNoBorder; codeScroll.hasVerticalScroller = YES; codeScroll.drawsBackground = NO;
    self.chatCodeInput = [[NSTextView alloc] initWithFrame:codeScroll.bounds];
    self.chatCodeInput.font = MonoFont(15); self.chatCodeInput.textColor = NSColor.whiteColor; self.chatCodeInput.backgroundColor = [NSColor colorWithCalibratedWhite:0.35 alpha:1.0]; self.chatCodeInput.insertionPointColor = NSColor.whiteColor; self.chatCodeInput.string = self.chatDraftCode ?: @""; self.chatCodeInput.delegate = self; self.chatCodeInput.allowsUndo = YES; self.chatCodeInput.automaticQuoteSubstitutionEnabled = NO; self.chatCodeInput.automaticDashSubstitutionEnabled = NO; self.chatCodeInput.automaticTextReplacementEnabled = NO;
    codeScroll.documentView = self.chatCodeInput; [codeShell addSubview:codeScroll]; [input addSubview:codeShell];
  } else {
    self.chatCodeInput = nil;
  }
  [self.dynamicViews addObject:input]; [self.root addSubview:input];
  [self button:@"->" frame:NSMakeRect(b.size.width-70,18,52,52) action:@selector(sendChatMessage:) blue:YES];
  [self addNoticeCardIfNeeded];
}
- (void)closeChatPage:(id)sender { [self showProject]; }
- (void)sendChatMessage:(id)sender {
  self.chatDraftText = self.chatInput.string ?: @"";
  self.chatDraftCode = self.chatCodeInput.string ?: @"";
  [self saveChatMessageText:self.chatDraftText code:(self.chatComposerHasCode ? self.chatDraftCode : nil)];
  self.chatDraftText = nil;
  self.chatDraftCode = nil;
  self.chatComposerHasCode = NO;
  [self showChatPage];
}
- (void)addChatCodeBox:(id)sender {
  self.chatDraftText = self.chatInput.string ?: self.chatDraftText ?: @"";
  if (!self.chatComposerHasCode) self.chatDraftCode = @"";
  else self.chatDraftCode = self.chatCodeInput.string ?: self.chatDraftCode ?: @"";
  self.chatComposerHasCode = YES;
  [self showChatPage];
}
- (void)refreshChatIfOpen:(id)sender {
  if (!self.showingChat) return;
  if (self.window.firstResponder == self.chatInput || self.window.firstResponder == self.chatCodeInput) return;
  NSArray *messages = [self loadChatMessages];
  NSData *data = [NSJSONSerialization dataWithJSONObject:messages options:0 error:nil];
  NSString *signature = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
  if (self.lastChatSignature && [self.lastChatSignature isEqualToString:signature]) return;
  self.lastChatSignature = signature;
  [self showChatPage];
}
- (void)checkIncomingProjectShare:(id)sender {
  NSError *error = nil;
  NSDictionary *doc = GetDocument(@"Threads/ProjectReturn", &error);
  if (error || ![doc[@"status"] length]) return;
  NSString *requestID = doc[@"requestId"];
  NSDictionary *project = doc[@"project"];
  if (!requestID.length || !project || [requestID isEqualToString:self.lastIncomingShareID]) return;
  self.lastIncomingShareID = requestID;
  self.incomingSharedProject = [project mutableCopy];
  self.incomingShareStatus = doc[@"status"] ?: @"sent_back";
  self.incomingShareMessage = [doc[@"status"] isEqualToString:@"add_to_projects"] ? @"Add to projects" : @"Project sent back";
  PatchDocument(@"Threads/ProjectReturn", @{@"status":@"", @"requestId":requestID, @"project":@{}, @"clearedAt":NSDate.date}, nil);
  [self redrawCurrentPage];
}
- (void)includeSharedProject:(id)sender {
  if (!self.incomingSharedProject) return;
  NSString *incomingName = self.incomingSharedProject[@"name"] ?: @"SharedProject";
  NSMutableDictionary *project = [self.incomingSharedProject mutableCopy];
  project[@"updatedAt"] = @(NSDate.date.timeIntervalSince1970);
  if (!project[@"activeFile"]) project[@"activeFile"] = [project[@"files"] allKeys].firstObject ?: @"ContentView";
  NSString *pid = [self projectIDMatchingName:incomingName];
  if (!pid.length) pid = [self projectIDForNewProjectName:incomingName];
  self.store[@"projects"][pid] = project;
  self.activeProjectID = pid;
  self.store[@"activeProject"] = pid;
  self.incomingSharedProject = nil;
  self.incomingShareMessage = nil;
  self.incomingShareStatus = nil;
  [self saveStore];
  [self redrawCurrentPage];
}
- (void)addIncomingProjectToProjects:(id)sender {
  if (!self.incomingSharedProject) return;
  NSMutableDictionary *project = [self.incomingSharedProject mutableCopy];
  project[@"name"] = [self uniqueProjectName:project[@"name"] ?: @"SharedProject"];
  project[@"updatedAt"] = @(NSDate.date.timeIntervalSince1970);
  if (!project[@"activeFile"]) project[@"activeFile"] = [project[@"files"] allKeys].firstObject ?: @"ContentView";
  NSString *pid = [self projectIDForNewProjectName:project[@"name"]];
  self.store[@"projects"][pid] = project;
  self.activeProjectID = pid;
  self.store[@"activeProject"] = pid;
  self.incomingSharedProject = nil;
  self.incomingShareMessage = nil;
  self.incomingShareStatus = nil;
  [self saveStore];
  [self redrawCurrentPage];
}
- (void)declineSharedProject:(id)sender {
  self.incomingSharedProject = nil;
  self.incomingShareMessage = nil;
  self.incomingShareStatus = nil;
  [self redrawCurrentPage];
}
- (void)selectProject:(NSButton *)sender {
  self.activeProjectID = sender.identifier;
  self.store[@"activeProject"] = self.activeProjectID;
  for (NSString *pid in self.projectRows) self.projectRows[pid].layer.backgroundColor = ([pid isEqualToString:self.activeProjectID] ? Blue() : DarkRow()).CGColor;
  [self saveStore];
}
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
- (void)deleteProject:(id)sender {
  NSString *name = [self project][@"name"] ?: @"Project";
  NSAlert *alert = [NSAlert new];
  alert.messageText = [NSString stringWithFormat:@"Attention: Are you sure you want to delete '%@'?", name];
  [alert addButtonWithTitle:@"Delete"];
  [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] != NSAlertFirstButtonReturn) return;
  [self.store[@"projects"] removeObjectForKey:self.activeProjectID];
  NSString *next = self.projectIDs.firstObject;
  if (!next.length) {
    [self newProject:nil];
    return;
  }
  self.activeProjectID = next;
  self.store[@"activeProject"] = next;
  [self saveStore];
  [self showMain];
}
- (void)newProject:(id)sender {
  NSString *pid = [NSString stringWithFormat:@"project-%.0f", NSDate.date.timeIntervalSince1970]; NSString *name = [NSString stringWithFormat:@"MyApp%lu", (unsigned long)self.projectIDs.count + 1];
  self.store[@"projects"][pid] = [@{@"name":name, @"updatedAt":@(NSDate.date.timeIntervalSince1970), @"activeFile":@"ContentView", @"files":[@{@"ContentView":[@{@"name":@"ContentView", @"code":@"import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        Text(\"Hello\")\n    }\n}\n\n#Preview {\n    ContentView()\n}\n"} mutableCopy]} mutableCopy]} mutableCopy];
  self.activeProjectID = pid; self.store[@"activeProject"] = pid; [self saveStore]; [self showMain];
}
- (void)showTemplatePicker {
  self.showingChat = NO; self.showingProject = NO; self.showingTemplatePicker = YES; [self clearDynamic]; [self.ageLabels removeAllObjects]; [self.projectRows removeAllObjects];
  NSRect b = self.root.bounds;
  [self button:@"<" frame:NSMakeRect(18,b.size.height-88,54,54) action:@selector(showMain) blue:YES];
  [self label:@"Templates" frame:NSMakeRect(92,b.size.height-92,320,68) font:TitleFont(46) color:NSColor.whiteColor];
  [self addLine:NSMakeRect(0,b.size.height-102,b.size.width,2)];
  NSArray *rows = @[
    @{@"id":@"mercury", @"title":@"Mercury", @"detail":@"Image background from ~/studioimages/mercury.heic"},
    @{@"id":@"wood", @"title":@"Wood", @"detail":@"Image background from ~/studioimages/wood.jpeg"},
    @{@"id":@"elegant", @"title":@"Elegant", @"detail":@"Blue, purple, pink, and orange AngularGradient"},
    @{@"id":@"cleanWebsite", @"title":@"Clean website", @"detail":@"White website background with a clean top header"},
    @{@"id":@"navBar", @"title":@"Nav bar", @"detail":@"Gray website background with a compact nav header"}
  ];
  CGFloat y = b.size.height - 190;
  for (NSDictionary *rowInfo in rows) {
    NSView *rowBackground = [[NSView alloc] initWithFrame:NSMakeRect(18,y,b.size.width-36,78)];
    rowBackground.wantsLayer = YES;
    rowBackground.layer.backgroundColor = DarkRow().CGColor;
    rowBackground.layer.cornerRadius = 16;
    [self.dynamicViews addObject:rowBackground];
    [self.root addSubview:rowBackground];
    [self label:rowInfo[@"title"] frame:NSMakeRect(42,y+28,240,36) font:TitleFont(32) color:NSColor.whiteColor];
    [self label:rowInfo[@"detail"] frame:NSMakeRect(286,y+30,b.size.width-340,28) font:MonoFont(16) color:NSColor.lightGrayColor];
    NSButton *row = [self button:@"" frame:NSMakeRect(0,y-8,b.size.width,94) action:@selector(createTemplateProjectFromButton:) blue:NO];
    row.identifier = rowInfo[@"id"];
    row.layer.backgroundColor = NSColor.clearColor.CGColor;
    row.layer.opacity = 0.01;
    [self.root addSubview:row positioned:NSWindowAbove relativeTo:nil];
    y -= 98;
  }
  [self addNoticeCardIfNeeded];
}
- (NSString *)templateContentViewCode {
  return @"import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        TemplateView()\n    }\n}\n\n#Preview {\n    ContentView()\n}\n";
}
- (NSString *)templateContentViewCodeForKind:(NSString *)kind {
  if ([kind isEqualToString:@"cleanWebsite"]) {
    return @"import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        TemplateView(\n            title: \"Starry eyes\",\n            titleImage: \"star.fill\",\n            topButtons: [\n                TopButton(\"About Us\") {\n                    NestedTemplateView(\n                        title: \"About Us\",\n                        titleImage: \"star.fill\",\n                        subtitles: [Subtitle(\"We build simple, bright pages with a clean structure.\")],\n                        cards: [\n                            Card(title: \"Mission\", status: \"OPEN\") {\n                                Text(\"Write your About Us content here.\")\n                            }\n                        ],\n                        order: \"subtitle1;cards\"\n                    )\n                },\n                TopButton(\"Products\") {\n                    NestedTemplateView(\n                        title: \"Products\",\n                        titleImage: \"shippingbox.fill\",\n                        subtitles: [Subtitle(\"Showcase the things you make.\")],\n                        cards: [\n                            Card(title: \"Product\", status: \"NEW\") {\n                                Text(\"Add product details here.\")\n                            }\n                        ],\n                        order: \"subtitle1;cards\"\n                    )\n                },\n                TopButton(\"Donate\") {\n                    NestedTemplateView(\n                        title: \"Donate\",\n                        titleImage: \"heart.fill\",\n                        subtitles: [Subtitle(\"Support the work.\")],\n                        cards: [\n                            Card(title: \"Gift\", status: \"THANKS\") {\n                                Text(\"Add donation copy here.\")\n                            }\n                        ],\n                        order: \"subtitle1;cards\"\n                    )\n                }\n            ],\n            subtitles: [Subtitle(\"A clean website starter.\")],\n            cards: [Card(title: \"Welcome\", status: \"READY\")],\n            order: \"subtitle1;cards\"\n        )\n    }\n}\n\n#Preview {\n    ContentView()\n}\n";
  }
  if ([kind isEqualToString:@"navBar"]) {
    return @"import SwiftUI\n\nstruct ContentView: View {\n    var body: some View {\n        TemplateView(\n            title: \"Protect Fish L.C.C\",\n            titleImage: \"fish.fill\",\n            topButtons: [\n                TopButton(\"Home\") {\n                    NestedTemplateView(\n                        title: \"Home\",\n                        titleImage: \"house.fill\",\n                        subtitles: [Subtitle(\"Welcome to the home page.\")],\n                        cards: [\n                            Card(title: \"News\", status: \"LIVE\") {\n                                Text(\"Add homepage content here.\")\n                            }\n                        ],\n                        order: \"subtitle1;cards\"\n                    )\n                },\n                TopButton(\"Our mission\") {\n                    NestedTemplateView(\n                        title: \"Our mission\",\n                        titleImage: \"leaf.fill\",\n                        subtitles: [Subtitle(\"Protecting water, habitats, and the fish that live there.\")],\n                        cards: [\n                            Card(title: \"Action\", status: \"NOW\") {\n                                Text(\"Write your mission details here.\")\n                            }\n                        ],\n                        order: \"subtitle1;cards\"\n                    )\n                }\n            ],\n            subtitles: [Subtitle(\"A compact navigation starter.\")],\n            cards: [Card(title: \"Welcome\", status: \"READY\")],\n            order: \"subtitle1;cards\"\n        )\n    }\n}\n\n#Preview {\n    ContentView()\n}\n";
  }
  return [self templateContentViewCode];
}
- (NSString *)templateViewCodeForKind:(NSString *)kind {
  NSString *background = @"elegant";
  if ([kind isEqualToString:@"mercury"]) background = @"mercury";
  else if ([kind isEqualToString:@"wood"]) background = @"wood";
  else if ([kind isEqualToString:@"cleanWebsite"]) background = @"cleanWebsite";
  else if ([kind isEqualToString:@"navBar"]) background = @"navBar";
  return [NSString stringWithFormat:
@"import SwiftUI\nimport AppKit\n\nstruct TopButton: Identifiable {\n    let id = UUID()\n    let title: String\n    let content: AnyView\n\n    init<Content: View>(_ title: String, @ViewBuilder content: () -> Content) {\n        self.title = title\n        self.content = AnyView(content())\n    }\n}\n\nstruct Subtitle: Identifiable {\n    let id = UUID()\n    let text: String\n\n    init(_ text: String) {\n        self.text = text\n    }\n}\n\nstruct Card: Identifiable {\n    let id = UUID()\n    var title: String\n    var status: String?\n    let content: AnyView\n\n    init(title: String, status: String? = nil) {\n        self.title = title\n        self.status = status\n        self.content = AnyView(Text(title))\n    }\n\n    init<Content: View>(title: String, status: String? = nil, @ViewBuilder content: () -> Content) {\n        self.title = title\n        self.status = status\n        self.content = AnyView(content())\n    }\n}\n\nstruct PiChart: Identifiable {\n    let id = UUID()\n    var values: [Double]\n    var colors: [Color]\n\n    init(values: [Double] = [35, 25, 20, 20], colors: [Color] = [.blue, .purple, .pink, .orange]) {\n        self.values = values\n        self.colors = colors\n    }\n}\n\nstruct NestedTemplateView: View {\n    var title: String\n    var titleImage: String\n    var topButtons: [TopButton]\n    var subtitles: [Subtitle]\n    var cards: [Card]\n    var piCharts: [PiChart]\n    var order: String\n    var headerColor: Color?\n\n    init(\n        title: String = \"Hello\",\n        titleImage: String = \"square\",\n        topButtons: [TopButton] = [],\n        subtitles: [Subtitle] = [Subtitle(\"Something\")],\n        cards: [Card] = [Card(title: \"Something\", status: \"Something\")],\n        piCharts: [PiChart] = [PiChart()],\n        order: String = \"subtitle1;cards;piChart1\",\n        headerColor: Color? = nil\n    ) {\n        self.title = title\n        self.titleImage = titleImage\n        self.topButtons = topButtons\n        self.subtitles = subtitles\n        self.cards = cards\n        self.piCharts = piCharts\n        self.order = order\n        self.headerColor = headerColor\n    }\n\n    var body: some View {\n        TemplateView(\n            title: title,\n            titleImage: titleImage,\n            topButtons: topButtons,\n            subtitles: subtitles,\n            cards: cards,\n            piCharts: piCharts,\n            order: order,\n            backgroundStyle: \"nested\",\n            headerColor: headerColor\n        )\n    }\n}\n\nstruct TemplateView: View {\n    var title: String\n    var titleImage: String\n    var topButtons: [TopButton]\n    var subtitles: [Subtitle]\n    var cards: [Card]\n    var piCharts: [PiChart]\n    var order: String\n    var backgroundStyle: String\n    var headerColor: Color?\n    @State private var selectedTopButton = 0\n    @State private var openedCardID: UUID?\n\n    init(\n        title: String = \"Hello\",\n        titleImage: String = \"square\",\n        topButtons: [TopButton] = [],\n        subtitles: [Subtitle] = [Subtitle(\"Something\")],\n        cards: [Card] = [Card(title: \"Something\", status: \"Something\")],\n        piCharts: [PiChart] = [PiChart()],\n        order: String = \"subtitle1;cards;piChart1\",\n        backgroundStyle: String = \"%@\",\n        headerColor: Color? = nil\n    ) {\n        self.title = title\n        self.titleImage = titleImage\n        self.topButtons = topButtons\n        self.subtitles = subtitles\n        self.cards = cards\n        self.piCharts = piCharts\n        self.order = order\n        self.backgroundStyle = backgroundStyle\n        self.headerColor = headerColor\n    }\n\n    var isCleanWebsite: Bool { backgroundStyle == \"cleanWebsite\" }\n    var isNavBar: Bool { backgroundStyle == \"navBar\" }\n    var isLightStyle: Bool { isCleanWebsite || isNavBar }\n    var templateTextColor: Color { isLightStyle ? .black : .white }\n\n    var body: some View {\n        ZStack(alignment: .topLeading) {\n            TemplateBackground(style: backgroundStyle)\n            ScrollView {\n                VStack(alignment: .leading, spacing: 24) {\n                    header\n                    pageContent\n                        .padding(isNavBar ? EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22) : EdgeInsets())\n                }\n                .padding(isNavBar ? EdgeInsets(top: 0, leading: 0, bottom: 22, trailing: 0) : EdgeInsets(top: 22, leading: 22, bottom: 22, trailing: 22))\n                .frame(maxWidth: .infinity, alignment: .leading)\n            }\n        }\n        .frame(maxWidth: .infinity, maxHeight: .infinity)\n        .clipped()\n    }\n\n    @ViewBuilder var header: some View {\n        if isCleanWebsite {\n            cleanWebsiteHeader\n        } else if isNavBar {\n            navBarHeader\n        } else {\n            overlayHeader\n        }\n    }\n\n    var overlayHeader: some View {\n        HStack(alignment: .center, spacing: 14) {\n            Image(systemName: titleImage)\n                .foregroundStyle(.white)\n                .font(.system(size: 42, weight: .semibold))\n                .frame(width: 50, height: 50)\n            Text(title)\n                .foregroundStyle(.white)\n                .font(.system(size: 40, weight: .bold, design: .rounded))\n                .lineLimit(1)\n                .minimumScaleFactor(0.55)\n            ForEach(topButtons.indices, id: \\.self) { index in\n                headerButton(index: index, textColor: .white, selectedTextColor: .black, underlineColor: .clear, usesPill: true, usesUnderline: false)\n            }\n        }\n    }\n\n    var cleanWebsiteHeader: some View {\n        VStack(spacing: 10) {\n            HStack(alignment: .center, spacing: 14) {\n                Image(systemName: titleImage)\n                    .foregroundStyle(.black)\n                    .font(.system(size: 46, weight: .bold))\n                    .frame(width: 54, height: 54)\n                Text(title)\n                    .foregroundStyle(.black)\n                    .font(.system(size: 32, weight: .regular, design: .rounded))\n                    .lineLimit(1)\n                    .minimumScaleFactor(0.55)\n                Spacer(minLength: 20)\n                ForEach(topButtons.indices, id: \\.self) { index in\n                    headerButton(index: index, textColor: .black, selectedTextColor: .black, underlineColor: .blue, usesPill: false, usesUnderline: true)\n                }\n            }\n            Rectangle()\n                .fill(Color.blue)\n                .frame(height: 3)\n        }\n        .padding(.horizontal, 16)\n        .padding(.vertical, 12)\n        .background(headerColor ?? Color.white)\n        .frame(maxWidth: .infinity, alignment: .leading)\n    }\n\n    var navBarHeader: some View {\n        HStack(alignment: .center, spacing: 16) {\n            Image(systemName: titleImage)\n                .foregroundStyle(.black)\n                .font(.system(size: 34, weight: .semibold))\n                .frame(width: 42, height: 42)\n            Text(title)\n                .foregroundStyle(.black)\n                .font(.system(size: 32, weight: .regular, design: .rounded))\n                .lineLimit(1)\n                .minimumScaleFactor(0.55)\n            ForEach(topButtons.indices, id: \\.self) { index in\n                headerButton(index: index, textColor: .red, selectedTextColor: .red, underlineColor: .red, usesPill: false, usesUnderline: true)\n            }\n            Spacer(minLength: 0)\n        }\n        .padding(.horizontal, 18)\n        .padding(.vertical, 13)\n        .background(headerColor ?? Color.green)\n        .frame(maxWidth: .infinity, alignment: .leading)\n    }\n\n    func headerButton(index: Int, textColor: Color, selectedTextColor: Color, underlineColor: Color, usesPill: Bool, usesUnderline: Bool) -> some View {\n        Button(topButtons[index].title) {\n            selectedTopButton = index\n            openedCardID = nil\n        }\n        .font(.system(size: usesPill ? 21 : 28, weight: .regular, design: .rounded))\n        .foregroundStyle(selectedTopButton == index ? selectedTextColor : textColor)\n        .padding(.horizontal, usesPill && selectedTopButton == index ? 18 : 8)\n        .padding(.vertical, usesPill && selectedTopButton == index ? 9 : 5)\n        .background(usesPill && selectedTopButton == index ? Color.white : Color.clear)\n        .clipShape(Capsule())\n        .overlay(alignment: .bottom) {\n            if usesUnderline {\n                Rectangle()\n                    .fill(underlineColor)\n                    .frame(height: selectedTopButton == index ? 3 : 2)\n                    .padding(.horizontal, 6)\n            }\n        }\n        .contentShape(Rectangle())\n        .buttonStyle(.plain)\n    }\n\n    @ViewBuilder var pageContent: some View {\n        if let id = openedCardID, let card = cards.first(where: { $0.id == id }) {\n            cardDetailPage(card)\n        } else if topButtons.indices.contains(selectedTopButton) {\n            topButtons[selectedTopButton].content\n                .foregroundStyle(templateTextColor)\n                .frame(maxWidth: .infinity, alignment: .leading)\n        } else {\n            defaultContent\n        }\n    }\n\n    var defaultContent: some View {\n        VStack(alignment: .leading, spacing: 24) {\n            orderedContent\n        }\n    }\n\n    func cardDetailPage(_ card: Card) -> some View {\n        VStack(alignment: .leading, spacing: 18) {\n            Button {\n                openedCardID = nil\n            } label: {\n                Text(\"<\")\n                    .font(.system(size: 26, weight: .bold, design: .rounded))\n                    .frame(width: 42, height: 42)\n                    .background(Color.blue)\n                    .clipShape(Circle())\n            }\n            .buttonStyle(.plain)\n\n            VStack(alignment: .leading, spacing: 14) {\n                Text(card.title)\n                    .foregroundStyle(templateTextColor)\n                    .font(.system(size: 32, weight: .bold, design: .rounded))\n                card.content\n                    .foregroundStyle(templateTextColor)\n                    .font(.system(size: 21, weight: .semibold, design: .rounded))\n                    .frame(maxWidth: .infinity, alignment: .leading)\n            }\n            .padding(22)\n            .frame(maxWidth: 680, alignment: .leading)\n            .background(Color.gray.opacity(0.72))\n            .clipShape(RoundedRectangle(cornerRadius: 18))\n        }\n    }\n\n    var orderedContent: some View {\n        VStack(alignment: .leading, spacing: 24) {\n            ForEach(orderTokens, id: \\.self) { token in\n                section(for: token)\n            }\n        }\n    }\n\n    var orderTokens: [String] {\n        order.split(separator: \";\").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }\n    }\n\n    @ViewBuilder func section(for token: String) -> some View {\n        if token.hasPrefix(\"subtitle\"), let index = numericSuffix(token), subtitles.indices.contains(index - 1) {\n            Text(subtitles[index - 1].text)\n                .foregroundStyle(templateTextColor)\n                .font(.system(size: 26, weight: .bold, design: .rounded))\n        } else if token == \"cards\" {\n            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], alignment: .leading, spacing: 16) {\n                ForEach(cards) { card in\n                    Button {\n                        openedCardID = card.id\n                    } label: {\n                        TemplateCardView(card: card, textColor: templateTextColor)\n                    }\n                    .buttonStyle(.plain)\n                    .contentShape(RoundedRectangle(cornerRadius: 18))\n                }\n            }\n            .frame(maxWidth: 680, alignment: .leading)\n        } else if token.hasPrefix(\"piChart\"), let index = numericSuffix(token), piCharts.indices.contains(index - 1) {\n            PiChartView(chart: piCharts[index - 1])\n                .frame(width: 160, height: 160)\n        }\n    }\n\n    func numericSuffix(_ token: String) -> Int? {\n        let digits = token.reversed().prefix { $0.isNumber }.reversed()\n        return Int(String(digits))\n    }\n}\n\nstruct TemplateCardView: View {\n    var card: Card\n    var textColor: Color = .white\n\n    var body: some View {\n        VStack(alignment: .leading) {\n            Text(card.title)\n                .foregroundStyle(textColor)\n                .font(.system(size: 28, weight: .regular, design: .rounded))\n                .lineLimit(2)\n                .minimumScaleFactor(0.75)\n                .frame(maxWidth: .infinity, alignment: .leading)\n            Spacer()\n            if let status = card.status, !status.isEmpty {\n                Text(status)\n                    .font(.system(size: 15, weight: .bold, design: .monospaced))\n                    .lineLimit(1)\n                    .minimumScaleFactor(0.7)\n                    .padding(.horizontal, 12)\n                    .padding(.vertical, 7)\n                    .frame(maxWidth: .infinity)\n                    .background(Color(red: 0.78, green: 0.24, blue: 0.14))\n                    .overlay(Capsule().stroke(Color.orange, lineWidth: 2))\n                    .clipShape(Capsule())\n            }\n        }\n        .padding(16)\n        .frame(width: 190, height: 210)\n        .background(Color.gray.opacity(0.82))\n        .clipShape(RoundedRectangle(cornerRadius: 18))\n    }\n}\n\nstruct PiChartView: View {\n    var chart: PiChart\n\n    var total: Double { max(chart.values.reduce(0, +), 0.001) }\n\n    var body: some View {\n        ZStack {\n            if chart.colors.isEmpty {\n                Circle().fill(Color.gray.opacity(0.8))\n            } else {\n                ForEach(chart.values.indices, id: \\.self) { index in\n                    PieSlice(startAngle: startAngle(for: index), endAngle: endAngle(for: index))\n                        .fill(chart.colors[index %% chart.colors.count])\n                }\n            }\n        }\n        .clipShape(Circle())\n    }\n\n    func startAngle(for index: Int) -> Angle {\n        Angle(degrees: chart.values.prefix(index).reduce(0, +) / total * 360 - 90)\n    }\n\n    func endAngle(for index: Int) -> Angle {\n        Angle(degrees: chart.values.prefix(index + 1).reduce(0, +) / total * 360 - 90)\n    }\n}\n\nstruct PieSlice: Shape {\n    var startAngle: Angle\n    var endAngle: Angle\n\n    func path(in rect: CGRect) -> Path {\n        var path = Path()\n        let center = CGPoint(x: rect.midX, y: rect.midY)\n        path.move(to: center)\n        path.addArc(center: center, radius: min(rect.width, rect.height) / 2, startAngle: startAngle, endAngle: endAngle, clockwise: false)\n        path.closeSubpath()\n        return path\n    }\n}\n\nstruct TemplateBackground: View {\n    var style: String\n\n    var body: some View {\n        GeometryReader { geometry in\n            Group {\n                if style == \"nested\" {\n                    Color.clear\n                } else if style == \"cleanWebsite\" {\n                    Color.white\n                        .frame(width: geometry.size.width, height: geometry.size.height)\n                } else if style == \"navBar\" {\n                    Color.gray.opacity(0.28)\n                        .frame(width: geometry.size.width, height: geometry.size.height)\n                } else if style == \"mercury\" {\n                    imageBackground(path: \"~/studioimages/mercury.heic\", size: geometry.size)\n                } else if style == \"wood\" {\n                    imageBackground(path: \"~/studioimages/wood.jpeg\", size: geometry.size)\n                } else {\n                    AngularGradient(colors: [.blue, .purple, .pink, .orange], center: .center)\n                        .frame(width: geometry.size.width, height: geometry.size.height)\n                }\n            }\n            .frame(width: geometry.size.width, height: geometry.size.height)\n            .clipped()\n        }\n        .clipped()\n    }\n\n    @ViewBuilder func imageBackground(path: String, size: CGSize) -> some View {\n        let expanded = NSString(string: path).expandingTildeInPath\n        if let image = NSImage(contentsOfFile: expanded) {\n            Image(nsImage: image)\n                .resizable()\n                .scaledToFill()\n                .frame(width: size.width, height: size.height)\n                .clipped()\n                .overlay(Color.black.opacity(0.35))\n        } else {\n            Color.black\n                .frame(width: size.width, height: size.height)\n        }\n    }\n}\n\n", background];
}
- (void)createTemplateProjectFromButton:(NSButton *)sender {
  NSString *kind = sender.identifier ?: @"elegant";
  NSString *displayKind = kind.capitalizedString;
  if ([kind isEqualToString:@"cleanWebsite"]) displayKind = @"Clean Website";
  else if ([kind isEqualToString:@"navBar"]) displayKind = @"Nav Bar";
  NSString *baseName = [NSString stringWithFormat:@"%@ Template", displayKind.length ? displayKind : @"Elegant"];
  NSString *name = [self uniqueProjectName:baseName];
  NSString *pid = [self projectIDForNewProjectName:name];
  NSMutableDictionary *files = [@{
    @"ContentView": [@{@"name":@"ContentView", @"code":[self templateContentViewCodeForKind:kind]} mutableCopy],
    @"TemplateView": [@{@"name":@"TemplateView", @"code":[self templateViewCodeForKind:kind]} mutableCopy]
  } mutableCopy];
  self.store[@"projects"][pid] = [@{@"name":name, @"updatedAt":@(NSDate.date.timeIntervalSince1970), @"activeFile":@"ContentView", @"files":files} mutableCopy];
  self.activeProjectID = pid;
  self.activeFileID = @"ContentView";
  self.store[@"activeProject"] = pid;
  self.showingTemplatePicker = NO;
  [self saveStore];
  [self showProject];
}
- (void)showProject {
  self.showingChat = NO; self.showingTemplatePicker = NO; self.showingProject = YES; [self clearDynamic]; [self.ageLabels removeAllObjects]; self.floatingPreviewControls = [NSMutableArray array]; NSDictionary *p = [self project]; if (!self.activeFileID) self.activeFileID = p[@"activeFile"] ?: self.fileIDs.firstObject;
  NSRect b = self.root.bounds;
  CGFloat leftW = 244, headerY = MAX(674, b.size.height - 91), contentTop = headerY - 19, consoleH = self.fishyPanelMode ? 332 : 126;
  BOOL previewVisible = [self previewPaneVisible];
  CGFloat sideBarW = (previewVisible && self.previewPaneWide) ? 46 : 0;
  CGFloat editorX = 264, consoleY = self.fishyPanelMode ? 0 : 16, contentBottom = self.fishyPanelMode ? consoleH + 16 : consoleY, editorY = contentBottom + 23;
  CGFloat consoleX = self.fishyPanelMode ? 0 : editorX;
  CGFloat previewW = 0, editorW = MAX(260, b.size.width - editorX - 44);
  CGFloat consoleW = self.fishyPanelMode ? b.size.width : editorW;
  if (previewVisible && self.previewPaneWide) {
    previewW = MAX(260, b.size.width - leftW - sideBarW - 38);
    editorW = 0;
    self.previewPaneFrame = NSMakeRect(leftW + sideBarW + 16, contentBottom, previewW, contentTop - contentBottom);
  } else if (previewVisible) {
    previewW = MAX(330, MIN(520, b.size.width * 0.32));
    CGFloat rightEdge = b.size.width - 22 - previewW;
    editorW = MAX(260, rightEdge - editorX - 16);
    previewW = MIN(previewW, MAX(260, b.size.width - (editorX + editorW + 16) - 22));
    self.previewPaneFrame = NSMakeRect(editorX + editorW + 16, contentBottom, previewW, contentTop - contentBottom);
  } else {
    self.previewPaneFrame = NSZeroRect;
  }
  CGFloat editorH = MAX(220, contentTop - editorY);
  CGFloat bottomButtonY = self.fishyPanelMode ? consoleH + 18 : 18;
  [self button:@"<" frame:NSMakeRect(18,headerY+26,32,32) action:@selector(back:) blue:YES]; [self label:p[@"name"] frame:NSMakeRect(64,headerY+6,210,58) font:TitleFont(42) color:NSColor.whiteColor]; [self button:@"Send" frame:NSMakeRect(245,headerY+16,145,44) action:@selector(sendForPreview:) blue:YES]; [self button:@"Share" frame:NSMakeRect(402,headerY+16,130,44) action:@selector(shareProject:) blue:YES]; [self redButton:@"Stop" frame:NSMakeRect(544,headerY+16,100,44) action:@selector(stopPreview:)]; [self button:@"Rename" frame:NSMakeRect(656,headerY+16,120,44) action:@selector(renameProjectInEditor:) blue:YES]; [self button:@"Rename File" frame:NSMakeRect(788,headerY+16,150,44) action:@selector(renameFile:) blue:YES]; [self addLine:NSMakeRect(0,headerY,b.size.width,2)]; [self addLine:NSMakeRect(leftW,self.fishyPanelMode ? consoleH : 0,2,headerY - (self.fishyPanelMode ? consoleH : 0))];
  if (previewVisible) {
    CGFloat dividerX = self.previewPaneFrame.origin.x - 9 - sideBarW;
    if (self.previewPaneWide) {
      [self addLine:NSMakeRect(dividerX, 0, 2, headerY)];
      NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(dividerX + 2, 0, sideBarW, headerY)];
      bar.wantsLayer = YES; bar.layer.backgroundColor = DarkRow().CGColor;
      [self.dynamicViews addObject:bar]; [self.root addSubview:bar];
      NSButton *normal = [self button:@">|>" frame:NSMakeRect(dividerX + 7, headerY - 48, 36, 32) action:@selector(normalPreviewPane:) blue:YES];
      NSButton *collapse = [self button:@">|" frame:NSMakeRect(dividerX + 7, headerY - 88, 36, 32) action:@selector(collapsePreviewPane:) blue:YES];
      [self.floatingPreviewControls addObject:normal]; [self.floatingPreviewControls addObject:collapse];
    } else {
      NSButton *wide = [self button:@"|<" frame:NSMakeRect(self.previewPaneFrame.origin.x - 55, headerY - 48, 42, 34) action:@selector(widenPreviewPane:) blue:YES];
      [self.floatingPreviewControls addObject:wide];
    }
    self.previewContainerView = [[NSView alloc] initWithFrame:self.previewPaneFrame]; self.previewContainerView.wantsLayer = YES; self.previewContainerView.layer.backgroundColor = NSColor.blackColor.CGColor; self.previewContainerView.layer.borderColor = NSColor.whiteColor.CGColor; self.previewContainerView.layer.borderWidth = 0; [self.dynamicViews addObject:self.previewContainerView]; [self.root addSubview:self.previewContainerView];
    if (!self.previewContentView) {
      NSTextField *waiting = [[NSTextField alloc] initWithFrame:NSMakeRect(20, self.previewPaneFrame.size.height - 46, self.previewPaneFrame.size.width - 40, 28)];
      waiting.stringValue = @"Waiting for preview";
      waiting.font = MonoFont(18);
      waiting.textColor = NSColor.whiteColor;
      waiting.bezeled = NO;
      waiting.drawsBackground = NO;
      waiting.editable = NO;
      waiting.selectable = NO;
      [self.previewContainerView addSubview:waiting];
    }
  } else { self.previewContainerView = nil; }
  CGFloat fileListBottom = bottomButtonY + 46;
  CGFloat fileListH = MAX(80, contentTop - fileListBottom - 10);
  NSScrollView *fileScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,fileListBottom,leftW,fileListH)];
  fileScroll.borderType = NSNoBorder;
  fileScroll.hasVerticalScroller = YES;
  fileScroll.drawsBackground = NO;
  [self tuneScrollView:fileScroll];
  CGFloat fileContentH = MAX(fileListH, self.fileIDs.count * 38 + 10);
  NSView *fileContent = [[NSView alloc] initWithFrame:NSMakeRect(0,0,leftW,fileContentH)];
  CGFloat fileY = fileContentH - 36;
  for (NSString *fid in self.fileIDs) {
    NSDictionary *f = [self project][@"files"][fid];
    BOOL selectedFile = [fid isEqualToString:self.activeFileID];
    NSButton *hit = [[NSButton alloc] initWithFrame:NSMakeRect(0,fileY-4,leftW-4,34)];
    hit.title = @"";
    hit.bordered = NO;
    hit.target = self;
    hit.action = @selector(selectFile:);
    hit.identifier = fid;
    hit.wantsLayer = YES;
    hit.layer.backgroundColor = (selectedFile ? Blue() : NSColor.clearColor).CGColor;
    hit.layer.opacity = selectedFile ? 0.35 : 0.01;
    hit.layer.cornerRadius = 12;
    [fileContent addSubview:hit];
    if (self.swiftLogo) {
      NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(10,fileY-1,32,28)];
      iv.image = self.swiftLogo;
      [fileContent addSubview:iv];
    }
    NSTextField *fileName = [[NSTextField alloc] initWithFrame:NSMakeRect(54,fileY,175,27)];
    fileName.stringValue = f[@"name"] ?: fid;
    fileName.font = MonoFont(21);
    fileName.textColor = NSColor.whiteColor;
    fileName.bezeled = NO; fileName.drawsBackground = NO; fileName.editable = NO; fileName.selectable = NO;
    [fileContent addSubview:fileName];
    fileY -= 38;
  }
  fileScroll.documentView = fileContent;
  [self.dynamicViews addObject:fileScroll];
  [self.root addSubview:fileScroll];
  if (fileContentH > fileListH) [[fileScroll contentView] scrollToPoint:NSMakePoint(0, fileContentH - fileListH)];
  [self button:@"+" frame:NSMakeRect(18,bottomButtonY,32,32) action:@selector(newFile:) blue:YES]; [self button:(previewVisible ? @"<" : @">") frame:NSMakeRect(58,bottomButtonY,32,32) action:@selector(togglePreviewPane:) blue:YES];
  if (!self.previewPaneWide) {
    NSScrollView *editScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(editorX,editorY,editorW,editorH)]; editScroll.borderType = NSNoBorder; [self tuneScrollView:editScroll]; editScroll.wantsLayer = YES; editScroll.layer.backgroundColor = NSColor.blackColor.CGColor;
    self.editor = [[NSTextView alloc] initWithFrame:editScroll.bounds]; self.editor.font = MonoFont(19); self.editor.textColor = NSColor.whiteColor; self.editor.backgroundColor = NSColor.blackColor; self.editor.insertionPointColor = NSColor.whiteColor; self.editor.automaticQuoteSubstitutionEnabled = NO; self.editor.automaticDashSubstitutionEnabled = NO; self.editor.automaticTextReplacementEnabled = NO; self.editor.allowsUndo = YES; self.editor.delegate = self; self.editor.string = [self file][@"code"] ?: @""; editScroll.documentView = self.editor; [self.dynamicViews addObject:editScroll]; [self.root addSubview:editScroll]; [self applySyntaxHighlighting];
    NSScrollView *consoleScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(consoleX,consoleY,consoleW,consoleH)]; [self tuneScrollView:consoleScroll]; consoleScroll.wantsLayer = YES; consoleScroll.layer.backgroundColor = (self.fishyPanelMode ? [NSColor colorWithCalibratedWhite:0.17 alpha:1.0] : NSColor.blackColor).CGColor; self.console = [[NSTextView alloc] initWithFrame:consoleScroll.bounds]; self.console.textContainerInset = self.fishyPanelMode ? NSMakeSize(18, 16) : NSMakeSize(0, 0); self.console.font = MonoFont(19); self.console.textColor = NSColor.whiteColor; self.console.backgroundColor = self.fishyPanelMode ? [NSColor colorWithCalibratedWhite:0.17 alpha:1.0] : NSColor.blackColor; self.console.insertionPointColor = NSColor.whiteColor; self.console.editable = YES; self.console.delegate = self; self.console.allowsUndo = YES; self.console.automaticQuoteSubstitutionEnabled = NO; self.console.automaticDashSubstitutionEnabled = NO; self.console.automaticTextReplacementEnabled = NO; self.console.verticallyResizable = YES; self.console.maxSize = NSMakeSize(FLT_MAX, FLT_MAX); consoleScroll.documentView = self.console; [self.dynamicViews addObject:consoleScroll]; [self.root addSubview:consoleScroll]; [self addLine:self.fishyPanelMode ? NSMakeRect(0,consoleH,b.size.width,2) : NSMakeRect(editorX,consoleY + consoleH,editorW,2)]; [self refreshConsole:nil];
    if (self.fishyPanelMode && self.fishyBubbleText.length) {
      NSButton *closeFishy = [self redButton:@"x" frame:NSMakeRect(consoleX + 14, consoleY + consoleH - 48, 34, 34) action:@selector(closeFishyPanel:)];
      [self.root addSubview:closeFishy positioned:NSWindowAbove relativeTo:nil];
      CGFloat bubbleW = MIN(560, MAX(320, consoleW * 0.34));
      NSTextField *bubble = [[NSTextField alloc] initWithFrame:NSMakeRect(consoleX + consoleW - bubbleW - 18, consoleY + consoleH - 64, bubbleW, 38)];
      bubble.stringValue = self.fishyBubbleText;
      bubble.font = MonoFont(17);
      bubble.textColor = NSColor.whiteColor;
      bubble.alignment = NSTextAlignmentCenter;
      bubble.bezeled = NO;
      bubble.drawsBackground = NO;
      bubble.editable = NO;
      bubble.selectable = NO;
      bubble.wantsLayer = YES;
      bubble.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.43 alpha:1.0].CGColor;
      bubble.layer.cornerRadius = 18;
      [self.dynamicViews addObject:bubble];
      [self.root addSubview:bubble positioned:NSWindowAbove relativeTo:nil];
    }
  }
  [self placePreviewContent];
  if (previewVisible) [self addBorderOverlay:self.previewPaneFrame];
  for (NSView *control in self.floatingPreviewControls) [self.root addSubview:control positioned:NSWindowAbove relativeTo:nil];
  [self addNoticeCardIfNeeded];
}
- (void)editorChangedProgrammatically {
  [self file][@"code"] = self.editor.string ?: @"";
  [self project][@"updatedAt"] = @(NSDate.date.timeIntervalSince1970);
  [self saveStore];
  [self applySyntaxHighlighting];
}
- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)replacementString {
  if (textView == self.console) {
    if (self.updatingConsoleProgrammatically) return YES;
    if (range.location < self.consoleInputStart) return NO;
    if ([replacementString isEqualToString:@"\n"]) {
      NSString *text = self.console.string ?: @"";
      NSString *command = @"";
      if (self.consoleInputStart <= text.length) command = [[text substringFromIndex:self.consoleInputStart] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if (!self.consoleLog) self.consoleLog = [NSMutableString string];
      self.consoleLog = [text mutableCopy];
      [self.consoleLog appendString:@"\n"];
      [self runTerminalCommand:command];
      return NO;
    }
    return YES;
  }
  if (textView != self.editor) return YES;
  NSString *text = textView.string ?: @"";
  if ([replacementString isEqualToString:@"{"]) {
    NSRange currentLineRange = [text lineRangeForRange:NSMakeRange(MIN(range.location, text.length), 0)];
    NSString *currentLine = [text substringWithRange:NSMakeRange(currentLineRange.location, MIN(currentLineRange.length, text.length - currentLineRange.location))];
    NSMutableString *targetIndent = [NSMutableString string];
    for (NSUInteger i = 0; i < currentLine.length; i++) {
      unichar c = [currentLine characterAtIndex:i];
      if (c == ' ' || c == '\t') [targetIndent appendFormat:@"%C", c]; else break;
    }
    [targetIndent appendString:@"    "];
    [textView.textStorage replaceCharactersInRange:range withString:@"{"];
    NSUInteger cursor = range.location + 1;
    NSString *updated = textView.string ?: @"";
    if (cursor < updated.length && [updated characterAtIndex:cursor] == '\n') {
      NSUInteger nextLineStart = cursor + 1;
      if (nextLineStart >= updated.length) {
        [textView setSelectedRange:NSMakeRange(cursor, 0)];
        [self editorChangedProgrammatically];
        return NO;
      }
      NSUInteger scan = nextLineStart;
      NSUInteger sourceIndentLength = NSNotFound;
      while (scan < textView.string.length) {
        NSString *currentText = textView.string ?: @"";
        NSRange lineRange = [currentText lineRangeForRange:NSMakeRange(scan, 0)];
        NSString *lineText = [currentText substringWithRange:NSMakeRange(lineRange.location, MIN(lineRange.length, currentText.length - lineRange.location))];
        NSString *trimmed = [lineText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!trimmed.length) { scan = NSMaxRange(lineRange); continue; }
        if ([trimmed hasPrefix:@"}"]) break;
        NSUInteger existingIndentLength = 0;
        while (existingIndentLength < lineText.length) {
          unichar c = [lineText characterAtIndex:existingIndentLength];
          if (c == ' ' || c == '\t') existingIndentLength++; else break;
        }
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
  for (NSUInteger i = 0; i < line.length; i++) {
    unichar c = [line characterAtIndex:i];
    if (c == ' ' || c == '\t') [indent appendFormat:@"%C", c]; else break;
  }
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
- (void)textDidChange:(NSNotification *)n {
  if (n.object == self.chatInput) { self.chatDraftText = self.chatInput.string ?: @""; self.chatPlaceholder.hidden = self.chatDraftText.length > 0; return; }
  if (n.object == self.chatCodeInput) { self.chatDraftCode = self.chatCodeInput.string ?: @""; return; }
  if (n.object != self.editor) return;
  [self file][@"code"] = self.editor.string ?: @"";
  [self project][@"updatedAt"] = @(NSDate.date.timeIntervalSince1970);
  [self saveStore];
  [self applySyntaxHighlighting];
}
- (void)saveEditor { if (!self.editor) return; [self file][@"code"] = self.editor.string ?: @""; [self project][@"updatedAt"] = @(NSDate.date.timeIntervalSince1970); [self saveStore]; }
- (void)back:(id)sender { [self saveEditor]; [self showMain]; }
- (void)renameProjectInEditor:(id)sender { [self saveEditor]; [self renameProject:sender]; [self showProject]; }
- (void)selectFile:(NSButton *)sender { [self saveEditor]; self.activeFileID = sender.identifier; [self project][@"activeFile"] = self.activeFileID; [self saveStore]; [self showProject]; }
- (void)newFile:(id)sender { NSString *fid = [NSString stringWithFormat:@"File%lu", (unsigned long)self.fileIDs.count + 1]; [self project][@"files"][fid] = [@{@"name":fid, @"code":@"import SwiftUI\n"} mutableCopy]; self.activeFileID = fid; [self project][@"activeFile"] = fid; [self saveStore]; [self showProject]; }
- (NSString *)fishCurrentCode { [self saveEditor]; return [self file][@"code"] ?: @""; }
- (void)fishSetCurrentCode:(NSString *)code {
  if (!code) return;
  [self file][@"code"] = code;
  [self project][@"updatedAt"] = @(NSDate.date.timeIntervalSince1970);
  [self saveStore];
  if (self.editor) {
    NSRange selected = self.editor.selectedRange;
    self.editor.string = code;
    [self applySyntaxHighlighting];
    [self.editor setSelectedRange:NSMakeRange(MIN(selected.location, code.length), 0)];
  }
}
- (NSString *)fishTrimRight:(NSString *)line {
  NSUInteger end = line.length;
  while (end > 0) {
    unichar c = [line characterAtIndex:end - 1];
    if (c == ' ' || c == '\t' || c == '\r') end--; else break;
  }
  return [line substringToIndex:end];
}
- (NSDictionary *)fishBraceCountsInLine:(NSString *)line {
  NSInteger opens = 0, closes = 0;
  BOOL inString = NO, escaped = NO, inComment = NO;
  for (NSUInteger i = 0; i < line.length; i++) {
    unichar c = [line characterAtIndex:i];
    unichar next = i + 1 < line.length ? [line characterAtIndex:i + 1] : 0;
    if (inComment) break;
    if (inString) {
      if (escaped) escaped = NO;
      else if (c == '\\') escaped = YES;
      else if (c == '"') inString = NO;
      continue;
    }
    if (c == '/' && next == '/') { inComment = YES; i++; continue; }
    if (c == '"') { inString = YES; continue; }
    if (c == '{') opens++;
    else if (c == '}') closes++;
  }
  return @{@"opens":@(opens), @"closes":@(closes)};
}
- (NSString *)fishBraceSpacedCode:(NSString *)code {
  NSMutableArray *out = [NSMutableArray array];
  for (NSString *rawLine in [code componentsSeparatedByString:@"\n"]) {
    NSString *line = [self fishTrimRight:rawLine];
    NSMutableString *next = [NSMutableString string];
    BOOL inString = NO, escaped = NO, inComment = NO;
    for (NSUInteger i = 0; i < line.length; i++) {
      unichar c = [line characterAtIndex:i];
      unichar prev = next.length ? [next characterAtIndex:next.length - 1] : 0;
      unichar ahead = i + 1 < line.length ? [line characterAtIndex:i + 1] : 0;
      if (inComment) { [next appendFormat:@"%C", c]; continue; }
      if (inString) {
        [next appendFormat:@"%C", c];
        if (escaped) escaped = NO;
        else if (c == '\\') escaped = YES;
        else if (c == '"') inString = NO;
        continue;
      }
      if (c == '/' && ahead == '/') { inComment = YES; [next appendString:@"//"]; i++; continue; }
      if (c == '"') { inString = YES; [next appendFormat:@"%C", c]; continue; }
      if (c == '{' && next.length && prev != ' ' && prev != '\t' && prev != '\n') [next appendString:@" "];
      [next appendFormat:@"%C", c];
    }
    [out addObject:next];
  }
  return [out componentsJoinedByString:@"\n"];
}
- (NSString *)fishIndentedCode:(NSString *)code {
  NSMutableArray *out = [NSMutableArray array];
  NSInteger depth = 0;
  for (NSString *rawLine in [[self fishBraceSpacedCode:code] componentsSeparatedByString:@"\n"]) {
    NSString *trimmedRight = [self fishTrimRight:rawLine];
    NSString *trimmed = [trimmedRight stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!trimmed.length) { [out addObject:@""]; continue; }
    NSUInteger leadingClosers = 0;
    while (leadingClosers < trimmed.length && [trimmed characterAtIndex:leadingClosers] == '}') leadingClosers++;
    NSInteger lineDepth = MAX(0, depth - (NSInteger)leadingClosers);
    NSMutableString *indent = [NSMutableString string];
    for (NSInteger i = 0; i < lineDepth; i++) [indent appendString:@"    "];
    [out addObject:[indent stringByAppendingString:trimmed]];
    NSDictionary *counts = [self fishBraceCountsInLine:trimmed];
    depth = MAX(0, depth + [counts[@"opens"] integerValue] - [counts[@"closes"] integerValue]);
  }
  return [out componentsJoinedByString:@"\n"];
}
- (NSString *)fishSwiftFormatCode:(NSString *)code used:(BOOL *)used {
  if (used) *used = NO;
  NSString *toolRoot = [@"~/fishytool/swift-format" stringByExpandingTildeInPath];
  NSString *releaseBinary = [toolRoot stringByAppendingPathComponent:@".build/release/swift-format"];
  NSString *debugBinary = [toolRoot stringByAppendingPathComponent:@".build/debug/swift-format"];
  NSString *packageFile = [toolRoot stringByAppendingPathComponent:@"Package.swift"];
  NSFileManager *fm = NSFileManager.defaultManager;
  BOOL useSwiftRun = NO;
  NSString *launchPath = nil;
  NSArray *baseArgs = nil;
  if ([fm isExecutableFileAtPath:releaseBinary]) {
    launchPath = releaseBinary;
    baseArgs = @[@"format", @"-i"];
  } else if ([fm isExecutableFileAtPath:debugBinary]) {
    launchPath = debugBinary;
    baseArgs = @[@"format", @"-i"];
  } else if ([fm fileExistsAtPath:packageFile]) {
    useSwiftRun = YES;
    launchPath = @"/usr/bin/xcrun";
    baseArgs = @[@"swift", @"run", @"--package-path", toolRoot, @"swift-format", @"format", @"-i"];
  } else {
    return nil;
  }
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"swiftstudio-format-%.0f", NSDate.date.timeIntervalSince1970 * 1000]];
  [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *path = [dir stringByAppendingPathComponent:@"ContentView.swift"];
  if (![code writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]) return nil;
  NSTask *task = [NSTask new];
  task.launchPath = launchPath;
  NSMutableArray *args = [baseArgs mutableCopy];
  [args addObject:path];
  task.arguments = args;
  if (useSwiftRun) task.currentDirectoryPath = toolRoot;
  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;
  task.standardError = pipe;
  @try {
    [task launch];
    [task waitUntilExit];
  } @catch (NSException *exception) {
    [fm removeItemAtPath:dir error:nil];
    return nil;
  }
  NSString *formatted = task.terminationStatus == 0 ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
  [fm removeItemAtPath:dir error:nil];
  if (!formatted.length) return nil;
  if (used) *used = YES;
  return formatted;
}
- (NSString *)fishBestFormattedCode:(NSString *)code usedSwiftFormat:(BOOL *)usedSwiftFormat {
  BOOL used = NO;
  NSString *formatted = [self fishSwiftFormatCode:code used:&used];
  if (usedSwiftFormat) *usedSwiftFormat = used;
  return formatted ?: [self fishIndentedCode:code];
}
- (void)fishCleanup:(BOOL)deep {
  NSString *before = [self fishCurrentCode];
  BOOL usedSwiftFormat = NO;
  NSString *after = [self fishBestFormattedCode:before usedSwiftFormat:&usedSwiftFormat];
  if (deep) {
    while ([after containsString:@"\n\n\n"]) after = [after stringByReplacingOccurrencesOfString:@"\n\n\n" withString:@"\n\n"];
  }
  [self fishSetCurrentCode:after];
  NSString *fileName = [self file][@"name"] ?: self.activeFileID ?: @"ContentView";
  [self.consoleLog appendFormat:@"🐠: Cleaned %@\n", fileName];
  [self appendPromptToConsoleLog];
  [self refreshConsole:nil];
}
- (NSString *)fishMovePreviewMacroOutsideTypeInCode:(NSString *)code actions:(NSMutableArray<NSString *> *)actions changedLines:(NSUInteger *)changedLines {
  NSRange previewRange = [code rangeOfString:@"#Preview"];
  if (previewRange.location == NSNotFound) return code;
  NSArray<NSString *> *rawLines = [code componentsSeparatedByString:@"\n"];
  NSMutableArray<NSString *> *lines = [rawLines mutableCopy];
  NSInteger typeLine = -1, previewLine = -1, typeDepth = 0, typeEndLine = -1;
  BOOL inType = NO;
  for (NSUInteger i = 0; i < lines.count; i++) {
    NSString *trimmed = [lines[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSDictionary *counts = [self fishBraceCountsInLine:lines[i]];
    if (!inType && ([trimmed hasPrefix:@"struct "] || [trimmed hasPrefix:@"class "]) && [trimmed containsString:@": View"]) {
      inType = YES;
      typeLine = (NSInteger)i;
      typeDepth = [counts[@"opens"] integerValue] - [counts[@"closes"] integerValue];
      continue;
    }
    if (inType) {
      if ([trimmed hasPrefix:@"#Preview"]) previewLine = (NSInteger)i;
      typeDepth += [counts[@"opens"] integerValue] - [counts[@"closes"] integerValue];
      if (typeDepth <= 0) {
        typeEndLine = (NSInteger)i;
        break;
      }
    }
  }
  if (typeLine < 0 || previewLine < 0 || typeEndLine < 0 || previewLine > typeEndLine) return code;
  NSInteger previewDepth = 0, previewEndLine = -1;
  for (NSInteger i = previewLine; i < (NSInteger)lines.count; i++) {
    NSDictionary *counts = [self fishBraceCountsInLine:lines[(NSUInteger)i]];
    previewDepth += [counts[@"opens"] integerValue] - [counts[@"closes"] integerValue];
    if (i > previewLine && previewDepth <= 0) { previewEndLine = i; break; }
  }
  if (previewEndLine < previewLine) return code;
  NSArray *previewBlock = [lines subarrayWithRange:NSMakeRange((NSUInteger)previewLine, (NSUInteger)(previewEndLine - previewLine + 1))];
  [lines removeObjectsInRange:NSMakeRange((NSUInteger)previewLine, (NSUInteger)(previewEndLine - previewLine + 1))];
  NSInteger adjustedTypeEndLine = typeEndLine - (previewEndLine - previewLine + 1);
  while (adjustedTypeEndLine > 0 && [lines[(NSUInteger)adjustedTypeEndLine - 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length == 0) {
    [lines removeObjectAtIndex:(NSUInteger)adjustedTypeEndLine - 1];
    adjustedTypeEndLine--;
  }
  NSMutableArray *cleanPreview = [NSMutableArray array];
  for (NSString *line in previewBlock) [cleanPreview addObject:[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
  NSUInteger insertIndex = MIN((NSUInteger)adjustedTypeEndLine + 1, lines.count);
  [lines insertObject:@"" atIndex:insertIndex++];
  for (NSString *line in cleanPreview) [lines insertObject:line atIndex:insertIndex++];
  if (changedLines) (*changedLines)++;
  [actions addObject:@"I moved #Preview outside the SwiftUI view type."];
  return [self fishIndentedCode:[lines componentsJoinedByString:@"\n"]];
}
- (NSInteger)fishCountCharacter:(unichar)needle inString:(NSString *)text {
  NSInteger count = 0;
  for (NSUInteger i = 0; i < text.length; i++) if ([text characterAtIndex:i] == needle) count++;
  return count;
}
- (NSInteger)fishEditDistance:(NSString *)a to:(NSString *)b limit:(NSInteger)limit {
  if (labs((long)a.length - (long)b.length) > limit) return limit + 1;
  NSMutableArray<NSNumber *> *prev = [NSMutableArray array];
  for (NSUInteger j = 0; j <= b.length; j++) [prev addObject:@(j)];
  for (NSUInteger i = 1; i <= a.length; i++) {
    NSMutableArray<NSNumber *> *row = [NSMutableArray arrayWithObject:@(i)];
    NSInteger best = i;
    unichar ca = [a characterAtIndex:i - 1];
    for (NSUInteger j = 1; j <= b.length; j++) {
      unichar cb = [b characterAtIndex:j - 1];
      NSInteger cost = ca == cb ? 0 : 1;
      NSInteger del = prev[j].integerValue + 1;
      NSInteger ins = row[j - 1].integerValue + 1;
      NSInteger sub = prev[j - 1].integerValue + cost;
      NSInteger v = MIN(MIN(del, ins), sub);
      [row addObject:@(v)];
      best = MIN(best, v);
    }
    if (best > limit) return limit + 1;
    prev = row;
  }
  return prev.lastObject.integerValue;
}
- (NSString *)fishClosestToken:(NSString *)token from:(NSArray<NSString *> *)known maxDistance:(NSInteger)maxDistance {
  NSString *best = nil;
  NSInteger bestDistance = maxDistance + 1;
  for (NSString *candidate in known) {
    NSInteger distance = [self fishEditDistance:token to:candidate limit:maxDistance];
    if (distance < bestDistance) { bestDistance = distance; best = candidate; }
  }
  return bestDistance <= maxDistance ? best : nil;
}
- (NSArray<NSString *> *)fishKnownSwiftTokens {
  return @[@"import", @"SwiftUI", @"State", @"private", @"var", @"let", @"Bool", @"false", @"true", @"some", @"body", @"View", @"systemName", @"imageScale", @"foregroundStyle", @"tint", @"padding", @"Preview", @"ContentView", @"toggle", @"Text", @"Image", @"Toggle", @"VStack", @"HStack", @"ZStack", @"Color", @"red", @"blue", @"green", @"black", @"white"];
}
- (NSString *)fishApplyFuzzyCorrectionsToLine:(NSString *)line actions:(NSMutableArray<NSString *> *)actions {
  NSString *next = line ?: @"";
  NSDictionary *exact = @{
    @"SwLiuftUI": @"SwiftUI", @"SwLuftUI": @"SwiftUI", @"SwLiuft": @"SwiftUI",
    @"Vaew": @"View", @"Veiw": @"View", @"Vew": @"View",
    @"Previen": @"Preview", @"Preveiw": @"Preview",
    @"KontentVeen": @"ContentView", @"KontentView": @"ContentView", @"SontentVeew": @"ContentView", @"SontentView": @"ContentView", @"ContentVeew": @"ContentView",
    @"bnack": @"black", @"brack": @"black", @"blak": @"black"
  };
  for (NSString *bad in exact) {
    if ([next containsString:bad]) {
      next = [next stringByReplacingOccurrencesOfString:bad withString:exact[bad]];
      [actions addObject:[NSString stringWithFormat:@"I corrected %@ to %@.", bad, exact[bad]]];
    }
  }
  NSString *trimmed = [next stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
  if ([trimmed hasPrefix:@"//"] && [trimmed containsString:@"#Preview"]) {
    NSRange comment = [next rangeOfString:@"//"];
    if (comment.location != NSNotFound) {
      next = [[next substringToIndex:comment.location] stringByAppendingString:[[next substringFromIndex:NSMaxRange(comment)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
      [actions addObject:@"I restored the commented #Preview macro."];
    }
  }
  NSMutableString *out = [NSMutableString string];
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"[A-Za-z_][A-Za-z0-9_]*" options:0 error:nil];
  NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:next options:0 range:NSMakeRange(0, next.length)];
  NSUInteger cursor = 0;
  BOOL inString = NO;
  NSSet *knownSet = [NSSet setWithArray:[self fishKnownSwiftTokens]];
  for (NSTextCheckingResult *match in matches) {
    NSRange r = match.range;
    for (NSUInteger i = cursor; i < r.location; i++) {
      unichar c = [next characterAtIndex:i];
      [out appendFormat:@"%C", c];
      if (c == '"' && (i == 0 || [next characterAtIndex:i - 1] != '\\')) inString = !inString;
    }
    NSString *token = [next substringWithRange:r];
    NSString *replacement = token;
    if (!inString && ![knownSet containsObject:token] && token.length >= 4) {
      BOOL swiftish = [trimmed hasPrefix:@"import "] || [trimmed containsString:@"#"] || [trimmed containsString:@":"] || [trimmed containsString:@"."] || [token rangeOfString:@"view" options:NSCaseInsensitiveSearch].location != NSNotFound || [token rangeOfString:@"swift" options:NSCaseInsensitiveSearch].location != NSNotFound || [token rangeOfString:@"preview" options:NSCaseInsensitiveSearch].location != NSNotFound;
      NSInteger limit = token.length >= 8 ? 3 : 2;
      NSString *closest = swiftish ? [self fishClosestToken:token from:[self fishKnownSwiftTokens] maxDistance:limit] : nil;
      if (closest && ![closest isEqualToString:token]) {
        replacement = closest;
        [actions addObject:[NSString stringWithFormat:@"I corrected %@ to %@.", token, closest]];
      }
    }
    [out appendString:replacement];
    cursor = NSMaxRange(r);
  }
  if (cursor < next.length) [out appendString:[next substringFromIndex:cursor]];
  return out;
}
- (BOOL)fishLooksLikeSwiftUIImport:(NSString *)line {
  NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
  if (![trimmed hasPrefix:@"import "] && ![trimmed hasPrefix:@"ilmport "]) return NO;
  NSString *module = [[trimmed substringFromIndex:([trimmed hasPrefix:@"ilmport "] ? 8 : 7)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
  if ([module isEqualToString:@"SwiftUI"]) return NO;
  NSSet *knownTypos = [NSSet setWithArray:@[@"SwiftUIL", @"SwifttUI", @"SwiftUi", @"SwilftUI", @"SwfitUI", @"SwiiftUI", @"SwiftU", @"SwiftUII", @"SwLiuftUI", @"SwLuftUI"]];
  if ([knownTypos containsObject:module]) return YES;
  if ([self fishEditDistance:module to:@"SwiftUI" limit:4] <= 4) return YES;
  NSString *lower = module.lowercaseString;
  return [lower containsString:@"swift"] && ([lower containsString:@"ui"] || [lower hasSuffix:@"u"]);
}
- (NSString *)fishFirstUsefulCompilerLine:(NSString *)output {
  for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([trimmed containsString:@"error:"] || [trimmed containsString:@"warning:"]) return trimmed;
  }
  NSString *trimmed = [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return trimmed.length ? trimmed : @"Swift did not print an error.";
}
- (NSString *)fishCodeForTypecheck:(NSString *)source {
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
- (NSDictionary *)fishCompileCode:(NSString *)code {
  NSDate *started = NSDate.date;
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"swiftstudio-fishy-%.0f", NSDate.date.timeIntervalSince1970 * 1000]];
  [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *path = [dir stringByAppendingPathComponent:@"ContentView.swift"];
  NSError *writeError = nil;
  NSString *typecheckCode = [self fishCodeForTypecheck:code];
  if (![typecheckCode writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
    return @{@"ok":@NO, @"seconds":@(MAX(1, ceil(-started.timeIntervalSinceNow))), @"output":writeError.localizedDescription ?: @"Could not write temporary Swift file."};
  }
  NSTask *task = [NSTask new];
  task.launchPath = @"/usr/bin/xcrun";
  task.arguments = @[@"swiftc", @"-typecheck", path];
  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;
  task.standardError = pipe;
  @try {
    [task launch];
    [task waitUntilExit];
  } @catch (NSException *exception) {
    return @{@"ok":@NO, @"seconds":@(MAX(1, ceil(-started.timeIntervalSinceNow))), @"output":@"Could not run swiftc. Install Xcode Command Line Tools with xcode-select --install."};
  }
  NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
  NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
  NSInteger seconds = MAX(1, (NSInteger)ceil(-started.timeIntervalSinceNow));
  [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
  return @{@"ok":@(task.terminationStatus == 0), @"seconds":@(seconds), @"output":output};
}
- (NSString *)fishImplementedCodeFromCode:(NSString *)code actions:(NSMutableArray<NSString *> *)actions changedLines:(NSUInteger *)changedLines {
  NSArray *beforeLines = [code componentsSeparatedByString:@"\n"];
  NSMutableArray *lines = [NSMutableArray array];
  for (NSString *rawLine in beforeLines) {
    NSString *line = rawLine;
    NSString *original = line;
    line = [self fishApplyFuzzyCorrectionsToLine:line actions:actions];
    NSString *trimmedBeforeExactFixes = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if ([trimmedBeforeExactFixes isEqualToString:@"import Foundatione"]) {
      line = [line stringByReplacingOccurrencesOfString:@"Foundatione" withString:@"Foundation"];
      [actions addObject:@"I fixed the misspelled Foundation import."];
    }
    if ([trimmedBeforeExactFixes isEqualToString:@"import Swfit"]) {
      line = [line stringByReplacingOccurrencesOfString:@"Swfit" withString:@"SwiftUI"];
      [actions addObject:@"I fixed the misspelled SwiftUI import."];
    }
    if ([trimmedBeforeExactFixes hasPrefix:@"clas "]) {
      NSRange r = [line rangeOfString:@"clas "];
      if (r.location != NSNotFound) line = [line stringByReplacingCharactersInRange:r withString:@"class "];
      [actions addObject:@"I changed clas to class."];
    }
    if ([line containsString:@"prinnt("]) {
      line = [line stringByReplacingOccurrencesOfString:@"prinnt(" withString:@"print("];
      [actions addObject:@"I changed prinnt to print."];
    }
    if ([self fishLooksLikeSwiftUIImport:line]) {
      NSString *leading = @"";
      for (NSUInteger i = 0; i < line.length; i++) {
        unichar c = [line characterAtIndex:i];
        if (c == ' ' || c == '\t') leading = [leading stringByAppendingFormat:@"%C", c]; else break;
      }
      line = [leading stringByAppendingString:@"import SwiftUI"];
      [actions addObject:@"I fixed the SwiftUI import so Swift can find the module."];
    }
    NSDictionary *replacements = @{
      @"@Spate": @"@State",
      @" vaer ": @" var ",
      @": Bokol": @": Bool",
      @"= faelse": @"= false",
      @"import SwLiuftUI": @"import SwiftUI",
      @"systeemName:": @"systemName:",
      @": some Vaew": @": some View",
      @".foregroundstyle": @".foregroundStyle",
      @".feurgrondStile": @".foregroundStyle",
      @".feurgrondStyle": @".foregroundStyle",
      @".feurgondStyle": @".foregroundStyle",
      @".feurgoundStyle": @".foregroundStyle",
      @".foregondStyle": @".foregroundStyle",
      @".foregroundStlye": @".foregroundStyle",
      @".tit": @".tint",
      @"#Pneview": @"#Preview",
      @"#Previen": @"#Preview",
      @"CondentView": @"ContentView",
      @"KontentVeen": @"ContentView",
      @"KontentView": @"ContentView",
      @"SontentVeew": @"ContentView",
      @"SontentView": @"ContentView",
      @"ContentVeew": @"ContentView",
      @"Color.bnack": @"Color.black",
      @"Color.brack": @"Color.black",
      @"Color.blak": @"Color.black",
      @"toggsle": @"toggle"
    };
    for (NSString *bad in replacements) {
      if ([line containsString:bad]) {
        line = [line stringByReplacingOccurrencesOfString:bad withString:replacements[bad]];
        [actions addObject:[NSString stringWithFormat:@"I corrected %@ to %@.", bad, replacements[bad]]];
      }
    }
    if ([line containsString:@"letvar"]) {
      line = [line stringByReplacingOccurrencesOfString:@"letvar" withString:@"var"];
      [actions addObject:@"I split the merged let/var keyword into a valid var declaration."];
    }
    if ([line containsString:@"var body:  some View"]) {
      line = [line stringByReplacingOccurrencesOfString:@"var body:  some View" withString:@"var body: some View"];
      [actions addObject:@"I fixed the extra space in the body declaration."];
    }
    if ([line containsString:@"$Preview"]) {
      line = [line stringByReplacingOccurrencesOfString:@"$Preview" withString:@"#Preview"];
      [actions addObject:@"I changed $Preview to the Swift macro #Preview."];
    }
    if ([line containsString:@"#Macro"]) {
      line = [line stringByReplacingOccurrencesOfString:@"#Macro" withString:@"#Preview"];
      [actions addObject:@"I changed #Macro to #Preview."];
    }
    if ([line containsString:@"Colorred"]) {
      line = [line stringByReplacingOccurrencesOfString:@"Colorred" withString:@"Color.red"];
      [actions addObject:@"I changed Colorred to Color.red."];
    }
    if ([line containsString:@"ContentViewsssss"]) {
      line = [line stringByReplacingOccurrencesOfString:@"ContentViewsssss" withString:@"ContentView"];
      [actions addObject:@"I changed ContentViewsssss() to ContentView()."];
    }
    if ([line containsString:@"ContentView(s)"]) {
      line = [line stringByReplacingOccurrencesOfString:@"ContentView(s)" withString:@"ContentView()"];
      [actions addObject:@"I removed the extra preview argument from ContentView()."];
    }
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if ([trimmed hasPrefix:@"//"] && [trimmed containsString:@"#Preview"]) {
      NSRange comment = [line rangeOfString:@"//"];
      if (comment.location != NSNotFound) {
        line = [[line substringToIndex:comment.location] stringByAppendingString:[[line substringFromIndex:NSMaxRange(comment)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
        [actions addObject:@"I restored the commented #Preview macro."];
      }
    }
    trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if ([trimmed isEqualToString:@".imageScale.large)"]) {
      line = [line stringByReplacingOccurrencesOfString:@".imageScale.large)" withString:@".imageScale(.large)"];
      [actions addObject:@"I changed imageScale.large) to imageScale(.large)."];
    }
    if ([trimmed isEqualToString:@"padding()"] || [trimmed isEqualToString:@".padding"]) {
      NSString *leading = [line substringToIndex:[line rangeOfString:trimmed].location];
      line = [leading stringByAppendingString:@".padding()"];
      [actions addObject:@"I fixed padding into a SwiftUI modifier call."];
    }
    if ([trimmed hasPrefix:@"Toggle("] && [self fishCountCharacter:'(' inString:line] > [self fishCountCharacter:')' inString:line]) {
      line = [line stringByAppendingString:@")"];
      [actions addObject:@"I closed the Toggle call."];
    }
    if ([trimmed hasPrefix:@"Text("] && [self fishCountCharacter:'"' inString:line] % 2 == 1) {
      if ([line hasSuffix:@")"]) line = [line substringToIndex:line.length - 1];
      line = [line stringByAppendingString:@"\")"];
      [actions addObject:@"I closed the unfinished Text string."];
    }
    if ([trimmed containsString:@".foregroundStyle("] && [self fishCountCharacter:'(' inString:line] > [self fishCountCharacter:')' inString:line]) {
      line = [line stringByAppendingString:@")"];
      [actions addObject:@"I closed the foregroundStyle call."];
    }
    if (![line isEqualToString:original] && changedLines) (*changedLines)++;
    [lines addObject:line];
  }
  NSInteger parenBalance = 0;
  for (NSString *line in lines) parenBalance += [self fishCountCharacter:'(' inString:line] - [self fishCountCharacter:')' inString:line];
  if (parenBalance < 0) {
    NSMutableArray *cleaned = [NSMutableArray array];
    NSInteger extraClosers = -parenBalance;
    for (NSString *line in lines) {
      NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if (extraClosers > 0 && [trimmed isEqualToString:@")"]) {
        extraClosers--;
        if (changedLines) (*changedLines)++;
        [actions addObject:@"I removed an extra standalone closing parenthesis."];
        continue;
      }
      [cleaned addObject:line];
    }
    lines = cleaned;
  }
  NSInteger braceBalance = 0;
  for (NSString *line in lines) {
    NSDictionary *counts = [self fishBraceCountsInLine:line];
    braceBalance += [counts[@"opens"] integerValue] - [counts[@"closes"] integerValue];
  }
  while (braceBalance > 0) {
    [lines addObject:@"}"];
    braceBalance--;
    if (changedLines) (*changedLines)++;
    [actions addObject:@"Swift expected another closing brace, so I added one at the end of the file."];
  }
  NSString *implemented = [self fishIndentedCode:[lines componentsJoinedByString:@"\n"]];
  if ([implemented containsString:@"Text(\"Hello\")\n        .foregroundStyle(Color.red)"]) {
    implemented = [implemented stringByReplacingOccurrencesOfString:@"Text(\"Hello\")\n        .foregroundStyle(Color.red)" withString:@"Text(\"Hello\")\n            .foregroundStyle(Color.red)"];
    if (changedLines) (*changedLines)++;
    [actions addObject:@"I attached the foregroundStyle modifier to the Text view inside body."];
  }
  return implemented;
}
- (NSString *)fishRepairViewConformanceInCode:(NSString *)code actions:(NSMutableArray<NSString *> *)actions changedLines:(NSUInteger *)changedLines {
  if (![code containsString:@"struct ContentView: View"] || ![code containsString:@"var body: some View"]) return code;
  NSMutableArray *lines = [[code componentsSeparatedByString:@"\n"] mutableCopy];
  BOOL inBody = NO;
  NSInteger bodyDepth = 0;
  BOOL changed = NO;
  for (NSUInteger i = 0; i < lines.count; i++) {
    NSString *line = lines[i];
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if ([trimmed hasPrefix:@"var body: some View"]) {
      inBody = YES;
      NSDictionary *counts = [self fishBraceCountsInLine:line];
      bodyDepth = [counts[@"opens"] integerValue] - [counts[@"closes"] integerValue];
      continue;
    }
    if (inBody) {
      NSDictionary *counts = [self fishBraceCountsInLine:line];
      bodyDepth += [counts[@"opens"] integerValue] - [counts[@"closes"] integerValue];
      if ([trimmed hasPrefix:@"."] && ![line hasPrefix:@"            "]) {
        lines[i] = [@"            " stringByAppendingString:trimmed];
        changed = YES;
      }
      if (bodyDepth <= 0) inBody = NO;
    }
  }
  if (!changed) return code;
  if (changedLines) (*changedLines)++;
  [actions addObject:@"Swift said ContentView did not conform to View, so I normalized the body/modifier structure."];
  return [self fishIndentedCode:[lines componentsJoinedByString:@"\n"]];
}
- (NSArray<NSString *> *)fishQuotedCompilerSymbols:(NSString *)output {
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"'([^']+)'" options:0 error:nil];
  NSArray *matches = [regex matchesInString:output ?: @"" options:0 range:NSMakeRange(0, (output ?: @"").length)];
  NSMutableArray *symbols = [NSMutableArray array];
  for (NSTextCheckingResult *match in matches) {
    NSRange r = [match rangeAtIndex:1];
    if (r.location != NSNotFound) [symbols addObject:[output substringWithRange:r]];
  }
  return symbols;
}
- (NSString *)fishReplacingIdentifier:(NSString *)bad with:(NSString *)good inCode:(NSString *)code changed:(BOOL *)changed {
  NSString *pattern = [NSString stringWithFormat:@"\\b%@\\b", [NSRegularExpression escapedPatternForString:bad]];
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
  NSString *next = [regex stringByReplacingMatchesInString:code options:0 range:NSMakeRange(0, code.length) withTemplate:good];
  if (![next isEqualToString:code] && changed) *changed = YES;
  return next;
}
- (NSString *)fishRepairLineShapesInCode:(NSString *)code actions:(NSMutableArray<NSString *> *)actions changedLines:(NSUInteger *)changedLines {
  NSMutableArray *lines = [[code componentsSeparatedByString:@"\n"] mutableCopy];
  BOOL changed = NO;
  for (NSUInteger i = 0; i < lines.count; i++) {
    NSString *line = lines[i];
    NSString *original = line;
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if ([trimmed hasPrefix:@".imageScale."]) {
      line = [line stringByReplacingOccurrencesOfString:@".imageScale." withString:@".imageScale(."];
      if (![line containsString:@")"]) line = [line stringByAppendingString:@")"];
      else if (![line containsString:@".imageScale(."]) line = [line stringByReplacingOccurrencesOfString:@")" withString:@")"];
      [actions addObject:@"I turned imageScale into a normal SwiftUI modifier call."];
    }
    if ([trimmed hasPrefix:@"Text("] && [self fishCountCharacter:'"' inString:line] % 2 == 1) {
      while ([line hasSuffix:@")"]) line = [line substringToIndex:line.length - 1];
      line = [line stringByAppendingString:@"\")"];
      [actions addObject:@"I closed the unfinished Text string."];
    }
    if (([trimmed hasPrefix:@"Image("] || [trimmed hasPrefix:@"Toggle("]) && [self fishCountCharacter:'(' inString:line] > [self fishCountCharacter:')' inString:line]) {
      line = [line stringByAppendingString:@")"];
      [actions addObject:@"I closed an unfinished SwiftUI call."];
    }
    if ([trimmed containsString:@"feurgrondStile"] || [trimmed containsString:@"feurgrondStyle"] || [trimmed containsString:@"feurgondStyle"] || [trimmed containsString:@"feurgoundStyle"] || [trimmed containsString:@"foregondStyle"] || [trimmed containsString:@"foregroundStlye"] || [trimmed containsString:@"foregreundStyle"] || [trimmed containsString:@"foregroundstyle"]) {
      line = [line stringByReplacingOccurrencesOfString:@"feurgrondStile" withString:@"foregroundStyle"];
      line = [line stringByReplacingOccurrencesOfString:@"feurgrondStyle" withString:@"foregroundStyle"];
      line = [line stringByReplacingOccurrencesOfString:@"feurgondStyle" withString:@"foregroundStyle"];
      line = [line stringByReplacingOccurrencesOfString:@"feurgoundStyle" withString:@"foregroundStyle"];
      line = [line stringByReplacingOccurrencesOfString:@"foregondStyle" withString:@"foregroundStyle"];
      line = [line stringByReplacingOccurrencesOfString:@"foregroundStlye" withString:@"foregroundStyle"];
      line = [line stringByReplacingOccurrencesOfString:@"foregreundStyle" withString:@"foregroundStyle"];
      line = [line stringByReplacingOccurrencesOfString:@"foregroundstyle" withString:@"foregroundStyle"];
      [actions addObject:@"I fixed a misspelled foregroundStyle modifier."];
    }
    if ([line containsString:@"Color.bnack"] || [line containsString:@"Color.brack"] || [line containsString:@"Color.blak"]) {
      line = [line stringByReplacingOccurrencesOfString:@"Color.bnack" withString:@"Color.black"];
      line = [line stringByReplacingOccurrencesOfString:@"Color.brack" withString:@"Color.black"];
      line = [line stringByReplacingOccurrencesOfString:@"Color.blak" withString:@"Color.black"];
      [actions addObject:@"I fixed a misspelled Color.black."];
    }
    if (([trimmed containsString:@".foregroundStyle("] || [trimmed containsString:@".background("] || [trimmed containsString:@".font("] || [trimmed containsString:@".frame("] || [trimmed containsString:@".padding("] || [trimmed containsString:@".imageScale("]) && [self fishCountCharacter:'(' inString:line] > [self fishCountCharacter:')' inString:line]) {
      line = [line stringByAppendingString:@")"];
      [actions addObject:@"I closed an unfinished SwiftUI modifier call."];
    }
    if ([trimmed isEqualToString:@"padding"] || [trimmed isEqualToString:@"padding()"] || [trimmed isEqualToString:@".padding"]) {
      NSString *leading = [line substringToIndex:[line rangeOfString:trimmed].location];
      line = [leading stringByAppendingString:@".padding()"];
      [actions addObject:@"I changed padding into the SwiftUI modifier .padding()."];
    }
    if (![line isEqualToString:original]) {
      lines[i] = line;
      changed = YES;
      if (changedLines) (*changedLines)++;
    }
  }
  return changed ? [self fishIndentedCode:[lines componentsJoinedByString:@"\n"]] : code;
}
- (NSString *)fishRepairUsingCompilerOutput:(NSString *)code output:(NSString *)output actions:(NSMutableArray<NSString *> *)actions changedLines:(NSUInteger *)changedLines {
  if (!output.length) return code;
  NSString *next = code;
  BOOL changed = NO;
  if ([output containsString:@"no such module"]) {
    NSString *before = next;
    next = [next stringByReplacingOccurrencesOfString:@"import SwiftUIL" withString:@"import SwiftUI"];
    next = [next stringByReplacingOccurrencesOfString:@"import SwifttUI" withString:@"import SwiftUI"];
    next = [next stringByReplacingOccurrencesOfString:@"import SwiftUi" withString:@"import SwiftUI"];
    next = [next stringByReplacingOccurrencesOfString:@"import SwilftUI" withString:@"import SwiftUI"];
    next = [next stringByReplacingOccurrencesOfString:@"import SwfitUI" withString:@"import SwiftUI"];
    next = [next stringByReplacingOccurrencesOfString:@"import Swfit" withString:@"import SwiftUI"];
    next = [next stringByReplacingOccurrencesOfString:@"import Foundatione" withString:@"import Foundation"];
    if (![next isEqualToString:before]) {
      changed = YES;
      [actions addObject:@"I fixed a misspelled import exactly, without renaming other code."];
    }
  }
  if ([output containsString:@"unterminated string literal"] || [output containsString:@"expected ')'"] || [output containsString:@"expected member name following '.'"]) {
    NSString *repaired = [self fishRepairLineShapesInCode:next actions:actions changedLines:changedLines];
    if (![repaired isEqualToString:next]) { next = repaired; changed = YES; }
  }
  if ([output containsString:@"does not conform to protocol 'View'"]) {
    NSString *repaired = [self fishRepairViewConformanceInCode:next actions:actions changedLines:changedLines];
    if (![repaired isEqualToString:next]) { next = repaired; changed = YES; }
  }
  if ([output containsString:@"expected '}'"] || [output containsString:@"expected declaration"]) {
    NSString *repaired = [self fishImplementedCodeFromCode:next actions:actions changedLines:changedLines];
    if (![repaired isEqualToString:next]) { next = repaired; changed = YES; }
  }
  return changed ? [self fishIndentedCode:next] : code;
}
- (void)fishySetPanelText:(NSString *)text {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self.consoleLog) self.consoleLog = [NSMutableString string];
    [self.consoleLog appendString:text ?: @""];
    [self refreshConsole:nil];
  });
}
- (void)fishyImplement {
  self.fishyPanelMode = NO;
  self.fishyBubbleText = nil;
  if (!self.consoleLog) self.consoleLog = [NSMutableString string];
  [self.consoleLog appendString:@"🐠: Implementing changes...\n"];
  [self refreshConsole:nil];
  NSString *source = [self fishCurrentCode];
  BOOL localApplied = NO;
  NSMutableArray<NSString *> *localActions = [NSMutableArray array];
  NSUInteger localChangedLines = 0;
  BOOL usedLocalFormat = NO;
  NSString *cleanedSource = [self fishBestFormattedCode:source usedSwiftFormat:&usedLocalFormat];
  if (cleanedSource.length && ![cleanedSource isEqualToString:source]) {
    source = cleanedSource;
    localApplied = YES;
  }
  NSString *lineRepaired = [self fishRepairLineShapesInCode:source actions:localActions changedLines:&localChangedLines];
  if (lineRepaired.length && ![lineRepaired isEqualToString:source]) {
    source = lineRepaired;
    localApplied = YES;
  }
  NSString *implementedRepaired = [self fishImplementedCodeFromCode:source actions:localActions changedLines:&localChangedLines];
  if (implementedRepaired.length && ![implementedRepaired isEqualToString:source]) {
    source = implementedRepaired;
    localApplied = YES;
  }
  NSString *previewMoved = [self fishMovePreviewMacroOutsideTypeInCode:source actions:localActions changedLines:&localChangedLines];
  if (previewMoved.length && ![previewMoved isEqualToString:source]) {
    source = previewMoved;
    localApplied = YES;
  }
  if (localApplied) {
    [self fishSetCurrentCode:source];
  }
  NSString *fileName = [self file][@"name"] ?: self.activeFileID ?: @"ContentView";
  NSString *requestID = [NSString stringWithFormat:@"fish-implement-%.0f", NSDate.date.timeIntervalSince1970 * 1000];
  NSError *error = nil;
  BOOL ok = PatchDocument(@"Threads/Fishy", @{@"status":@"queued", @"kind":@"implement", @"requestId":requestID, @"source":source, @"fileName":fileName, @"appName":[self project][@"name"] ?: @"SwiftUI App", @"sentAt":NSDate.date, @"result":@"", @"resultCode":@"", @"error":@""}, &error);
  if (!ok) {
    NSRange pending = [self.consoleLog rangeOfString:@"🐠: Implementing changes...\n" options:NSBackwardsSearch];
    NSString *failed = [NSString stringWithFormat:@"🐠: Implement failed: %@\n", error.localizedDescription ?: @"Firestore write failed"];
    if (pending.location != NSNotFound) [self.consoleLog replaceCharactersInRange:pending withString:failed]; else [self.consoleLog appendString:failed];
    [self appendPromptToConsoleLog];
    [self refreshConsole:nil];
    return;
  }
  self.terminalJobPending = YES;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSString *resultCode = nil;
    NSString *resultMessage = nil;
    NSString *failure = nil;
    for (NSUInteger i = 0; i < 60; i++) {
      [NSThread sleepForTimeInterval:1.0];
      NSError *readError = nil;
      NSDictionary *doc = GetDocument(@"Threads/Fishy", &readError);
      if (readError) { failure = readError.localizedDescription; continue; }
      if (![doc[@"requestId"] isEqualToString:requestID]) continue;
      NSString *status = doc[@"status"] ?: @"";
      if ([status isEqualToString:@"complete"]) { resultCode = doc[@"resultCode"] ?: @""; resultMessage = doc[@"result"] ?: @""; break; }
      if ([status isEqualToString:@"error"]) { failure = doc[@"error"] ?: @"Runner could not implement changes."; break; }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      self.terminalJobPending = NO;
      if (resultCode.length) [self fishSetCurrentCode:resultCode];
      self.fishyPanelMode = NO;
      self.fishyBubbleText = nil;
      if (!self.consoleLog) self.consoleLog = [NSMutableString string];
      NSRange pending = [self.consoleLog rangeOfString:@"🐠: Implementing changes...\n" options:NSBackwardsSearch];
      NSString *done = nil;
      if (resultCode.length || localApplied) {
        done = @"🐠: Implemented changes.\n";
      } else {
        done = [NSString stringWithFormat:@"🐠: %@\n", failure ?: (resultMessage.length ? resultMessage : @"Runner did not answer.")];
      }
      if (pending.location != NSNotFound) {
        [self.consoleLog replaceCharactersInRange:pending withString:done];
      } else {
        [self.consoleLog appendString:done];
      }
      [self appendPromptToConsoleLog];
      [self refreshConsole:nil];
    });
  });
}
- (void)closeFishyPanel:(id)sender {
  self.fishyPanelMode = NO;
  self.fishyBubbleText = nil;
  [self appendPromptToConsoleLog];
  [self showProject];
}
- (void)fishSuggest {
  NSString *source = [self fishCurrentCode];
  NSString *fileName = [self file][@"name"] ?: self.activeFileID ?: @"ContentView";
  NSString *requestID = [NSString stringWithFormat:@"fish-%.0f", NSDate.date.timeIntervalSince1970 * 1000];
  NSError *error = nil;
  BOOL ok = PatchDocument(@"Threads/Fishy", @{@"status":@"queued", @"kind":@"suggest", @"requestId":requestID, @"source":source, @"fileName":fileName, @"appName":[self project][@"name"] ?: @"SwiftUI App", @"sentAt":NSDate.date, @"result":@"", @"error":@""}, &error);
  if (!ok) {
    self.terminalJobPending = NO;
    [self.consoleLog appendFormat:@"🐠: Suggest failed: %@\n", error.localizedDescription ?: @"Firestore write failed"];
    [self appendPromptToConsoleLog];
    [self refreshConsole:nil];
    return;
  }
  if (!self.consoleLog) self.consoleLog = [NSMutableString string];
  self.terminalJobPending = YES;
  [self.consoleLog appendString:@"🐠: Asking preview runner for suggestions...\n"];
  [self refreshConsole:nil];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSString *result = nil;
    NSString *failure = nil;
    for (NSUInteger i = 0; i < 45; i++) {
      [NSThread sleepForTimeInterval:1.0];
      NSError *readError = nil;
      NSDictionary *doc = GetDocument(@"Threads/Fishy", &readError);
      if (readError) { failure = readError.localizedDescription; continue; }
      if (![doc[@"requestId"] isEqualToString:requestID]) continue;
      NSString *status = doc[@"status"] ?: @"";
      if ([status isEqualToString:@"complete"]) { result = doc[@"result"] ?: @"🐠: No suggestions."; break; }
      if ([status isEqualToString:@"error"]) { failure = doc[@"error"] ?: @"Runner could not make suggestions."; break; }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!self.consoleLog) self.consoleLog = [NSMutableString string];
      self.terminalJobPending = NO;
      NSRange pending = [self.consoleLog rangeOfString:@"🐠: Asking preview runner for suggestions...\n" options:NSBackwardsSearch];
      if (pending.location != NSNotFound) [self.consoleLog deleteCharactersInRange:pending];
      [self.consoleLog appendFormat:@"%@\n", result ?: [NSString stringWithFormat:@"🐠: %@", failure ?: @"Runner did not answer."]];
      [self appendPromptToConsoleLog];
      [self refreshConsole:nil];
    });
  });
}
- (void)runTerminalCommand:(NSString *)command {
  if (!command.length) { [self appendPromptToConsoleLog]; [self refreshConsole:nil]; return; }
  if ([command containsString:@";"]) {
    NSArray<NSString *> *parts = [command componentsSeparatedByString:@";"];
    for (NSString *part in parts) {
      NSString *trimmed = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if (trimmed.length) [self runTerminalCommand:trimmed];
    }
    return;
  }
  if ([command isEqualToString:@"studio run"]) {
    self.fishyPanelMode = NO;
    [self.consoleLog appendString:@"Running program\n"];
    self.keepConsoleLogForNextSend = YES;
    self.compileOnlyRequest = NO;
    [self sendForPreview:nil];
    return;
  }
  if ([command isEqualToString:@"studio compile"]) {
    self.fishyPanelMode = NO;
    [self.consoleLog appendString:@"Compiling program\n"];
    self.keepConsoleLogForNextSend = YES;
    self.compileOnlyRequest = YES;
    [self sendForPreview:nil];
    return;
  }
  if ([command isEqualToString:@"studio share"]) {
    self.fishyPanelMode = NO;
    [self.consoleLog appendString:@"Sharing program\n"];
    [self shareProject:nil];
    [self appendPromptToConsoleLog];
    [self refreshConsole:nil];
    return;
  }
  if ([command isEqualToString:@"studio stop"]) {
    self.fishyPanelMode = NO;
    [self stopPreview:nil];
    return;
  }
  if ([command isEqualToString:@"studio chat"]) {
    self.fishyPanelMode = NO;
    [self showChatPage];
    return;
  }
  if ([command isEqualToString:@"fish cleanup"]) {
    self.fishyPanelMode = NO;
    [self fishCleanup:NO];
    return;
  }
  if ([command isEqualToString:@"fish suggest"]) {
    self.fishyPanelMode = NO;
    [self fishSuggest];
    return;
  }
  if ([command isEqualToString:@"fish implement"]) {
    [self fishyImplement];
    return;
  }
  [self.consoleLog appendString:@"studioterm: no such command\n"];
  [self appendPromptToConsoleLog];
  [self refreshConsole:nil];
}
- (void)shareProject:(id)sender {
  [self saveEditor];
  NSString *requestID = [NSString stringWithFormat:@"studio-%.0f", NSDate.date.timeIntervalSince1970 * 1000];
  NSError *error = nil;
  BOOL ok = PatchDocument(@"Threads/ProjectShare", @{@"status":@"project_shared", @"requestId":requestID, @"sender":@"studio", @"project":[self project], @"sentAt":NSDate.date}, &error);
  if (!ok) [self appendConsole:[NSString stringWithFormat:@"Share failed: %@", error.localizedDescription ?: @"Firestore write failed"]];
}
- (void)togglePreviewPane:(id)sender { self.previewPaneCollapsed = !self.previewPaneCollapsed; if (self.previewPaneCollapsed) self.previewPaneWide = NO; [self showProject]; [self placePreviewContent]; }
- (void)widenPreviewPane:(id)sender { self.previewPaneCollapsed = NO; self.previewPaneWide = YES; [self showProject]; [self placePreviewContent]; }
- (void)normalPreviewPane:(id)sender { self.previewPaneCollapsed = NO; self.previewPaneWide = NO; [self showProject]; [self placePreviewContent]; }
- (void)collapsePreviewPane:(id)sender { self.previewPaneCollapsed = YES; self.previewPaneWide = NO; [self showProject]; [self placePreviewContent]; }
- (void)toggleWidePreviewShortcut:(id)sender { self.previewPaneCollapsed = NO; self.previewPaneWide = !self.previewPaneWide; [self showProject]; [self placePreviewContent]; }
- (void)toggleNormalPreviewShortcut:(id)sender { if (!self.previewPaneCollapsed && !self.previewPaneWide) self.previewPaneCollapsed = YES; else { self.previewPaneCollapsed = NO; self.previewPaneWide = NO; } [self showProject]; [self placePreviewContent]; }
- (void)clearPreviewSilently {
  if (self.previewTask && self.previewTask.running) [self.previewTask terminate];
  self.previewTask = nil;
  @try {
    NSTask *kill = [NSTask new];
    kill.launchPath = @"/usr/bin/pkill";
    kill.arguments = @[@"-f", @"SwiftStudioPreview"];
    [kill launch];
  } @catch (NSException *exception) {}
  [self.previewContentView removeFromSuperview];
  self.previewContentView = nil;
  [self.previewWindow close];
  self.previewWindow = nil;
  if (self.previewLibraryHandle) dlclose(self.previewLibraryHandle);
  self.previewLibraryHandle = nil;
  self.openingPreview = NO;
}
- (void)stopPreview:(id)sender {
  [self clearPreviewSilently];
  self.pendingRequestID = nil;
  self.compileOnlyRequest = NO;
  self.lastSendPercent = 0;
  self.lastCompilePercent = 0;
  self.lastRunPercent = 0;
  [self appendConsole:@"Stopped preview"];
  if (self.showingProject) [self showProject];
}
- (void)renameFile:(id)sender {
  [self saveEditor];
  if (!self.activeFileID.length) return;
  NSAlert *alert = [NSAlert new]; alert.messageText = @"Rename file";
  NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,260,28)];
  input.stringValue = [self file][@"name"] ?: self.activeFileID;
  alert.accessoryView = input; [alert addButtonWithTitle:@"Rename"]; [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] != NSAlertFirstButtonReturn || !input.stringValue.length) return;
  NSString *base = [[input.stringValue componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@""];
  if (!base.length) base = @"File";
  NSString *newID = base;
  NSUInteger suffix = 2;
  NSMutableDictionary *files = [self project][@"files"];
  while (files[newID] && ![newID isEqualToString:self.activeFileID]) newID = [NSString stringWithFormat:@"%@%lu", base, (unsigned long)suffix++];
  NSMutableDictionary *renamed = [[self file] mutableCopy];
  renamed[@"name"] = input.stringValue;
  [files removeObjectForKey:self.activeFileID];
  files[newID] = renamed;
  self.activeFileID = newID;
  [self project][@"activeFile"] = newID;
  [self project][@"updatedAt"] = @(NSDate.date.timeIntervalSince1970);
  [self saveStore]; [self showProject];
}
- (NSString *)combinedSource {
  NSMutableString *source = [NSMutableString string]; for (NSString *fid in self.fileIDs) { [source appendFormat:@"\n// %@.swift\n%@\n", fid, [self project][@"files"][fid][@"code"] ?: @""]; } return source;
}
- (void)placePreviewContent {
  if (!self.previewContentView) return;
  BOOL inlinePreview = [self previewPaneVisible] && self.previewContainerView;
  [self.previewContentView removeFromSuperview];
  if (inlinePreview) {
    [self.previewWindow orderOut:nil];
    self.previewContentView.frame = self.previewContainerView.bounds;
    self.previewContentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.previewContainerView addSubview:self.previewContentView];
    return;
  }
  if (!self.previewWindow) {
    self.previewWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(160,120,480,420) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.previewWindow.title = @"SwiftStudio Preview";
    self.previewWindow.releasedWhenClosed = NO;
    self.previewWindow.contentView = [[NSView alloc] initWithFrame:self.previewWindow.contentView.bounds];
    self.previewWindow.contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  }
  NSView *host = self.previewWindow.contentView;
  self.previewContentView.frame = host.bounds;
  self.previewContentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [host addSubview:self.previewContentView];
  [self.previewWindow makeKeyAndOrderFront:nil];
}
- (BOOL)openPreviewWindowFromCompiledDocument:(NSDictionary *)doc errorText:(NSString **)errorText {
  NSString *requestID = doc[@"compiledRequestId"];
  NSNumber *chunkCountNumber = doc[@"compiledChunkCount"];
  if (self.pendingRequestID.length && ![requestID isEqualToString:self.pendingRequestID]) {
    if (errorText) *errorText = @"Compiled preview did not match this send request.";
    return NO;
  }
  if (!requestID.length || !chunkCountNumber) {
    if (errorText) *errorText = @"Runner did not send a compiled preview library.";
    return NO;
  }
  NSInteger chunkCount = chunkCountNumber.integerValue;
  if (chunkCount <= 0) {
    if (errorText) *errorText = @"Compiled preview library had no chunks.";
    return NO;
  }
  SetPercent(@"Run", 50);
  dispatch_async(dispatch_get_main_queue(), ^{ [self refreshConsole:nil]; });
  NSString *thread = self.initialThread ?: @"Thread1";
  NSMutableArray *chunks = [NSMutableArray arrayWithCapacity:(NSUInteger)chunkCount];
  for (NSInteger i = 0; i < chunkCount; i++) [chunks addObject:[NSNull null]];
  __block NSString *downloadError = nil;
  __block NSInteger completedChunks = 0;
  __block double lastDownloadReported = 50.0;
  dispatch_group_t group = dispatch_group_create();
  for (NSInteger i = 0; i < chunkCount; i++) {
    dispatch_group_enter(group);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSError *error = nil;
      NSString *chunkPath = [NSString stringWithFormat:@"Threads/%@/Compiled/%@-%04ld", thread, requestID, (long)i];
      NSDictionary *chunk = GetDocument(chunkPath, &error);
      __block BOOL shouldRefresh = NO;
      @synchronized (chunks) {
        if (error && !downloadError) downloadError = error.localizedDescription;
        NSString *data = chunk[@"data"];
        if (!error && !data.length && !downloadError) downloadError = [NSString stringWithFormat:@"Missing compiled preview library chunk %ld.", (long)i];
        if (data.length) chunks[(NSUInteger)i] = data;
        completedChunks++;
        double downloadProgress = 45.0 + (((double)completedChunks) / MAX(1.0, (double)chunkCount)) * 20.0;
        double next = MAX(50.0, downloadProgress);
        if (next - lastDownloadReported >= 5.0 || completedChunks == chunkCount) {
          lastDownloadReported = next;
          SetPercent(@"Run", next);
          shouldRefresh = YES;
        }
      }
      if (shouldRefresh) dispatch_async(dispatch_get_main_queue(), ^{ [self refreshConsole:nil]; });
      dispatch_group_leave(group);
    });
  }
  dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
  if (downloadError.length) {
    if (errorText) *errorText = downloadError;
    return NO;
  }
  SetPercent(@"Run", 70);
  dispatch_async(dispatch_get_main_queue(), ^{ [self refreshConsole:nil]; });
  NSMutableString *base64 = [NSMutableString string];
  for (NSInteger i = 0; i < chunkCount; i++) {
    id chunk = chunks[(NSUInteger)i];
    if (![chunk isKindOfClass:[NSString class]]) {
      if (errorText) *errorText = [NSString stringWithFormat:@"Missing compiled preview library chunk %ld.", (long)i];
      return NO;
    }
    [base64 appendString:chunk];
  }
  NSData *exeData = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
  if (!exeData.length) {
    if (errorText) *errorText = @"Could not decode compiled executable.";
    return NO;
  }
  SetPercent(@"Run", 78);
  dispatch_async(dispatch_get_main_queue(), ^{ [self refreshConsole:nil]; });
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"swiftstudio-preview-current"];
  [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *exeName = doc[@"compiledExecutableName"];
  if (!exeName.length) exeName = [NSString stringWithFormat:@"SwiftStudioPreview-%@", requestID];
  exeName = [[exeName componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@"-"];
  NSString *exe = [dir stringByAppendingPathComponent:exeName];
  NSError *writeError = nil;
  if (![exeData writeToFile:exe options:NSDataWritingAtomic error:&writeError]) {
    if (errorText) *errorText = writeError.localizedDescription;
    return NO;
  }
  SetPercent(@"Run", 85);
  dispatch_async(dispatch_get_main_queue(), ^{ [self refreshConsole:nil]; });
  chmod(exe.fileSystemRepresentation, 0700);
  SetPercent(@"Run", 90);
  dispatch_async(dispatch_get_main_queue(), ^{ [self refreshConsole:nil]; });
  __block BOOL launched = NO;
  __block NSString *launchError = nil;
  dispatch_semaphore_t launchedSem = dispatch_semaphore_create(0);
  dispatch_async(dispatch_get_main_queue(), ^{
    [NSApp activateIgnoringOtherApps:YES];
    @try {
      SetPercent(@"Run", 95);
      [self refreshConsole:nil];
      [self clearPreviewSilently];
      void *handle = dlopen(exe.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
      if (!handle) {
        launchError = [NSString stringWithUTF8String:dlerror() ?: "Could not load preview library."];
      } else {
        void *symbol = dlsym(handle, "SwiftStudioCreatePreviewView");
        if (!symbol) {
          launchError = [NSString stringWithUTF8String:dlerror() ?: "Preview library did not contain a view factory."];
        } else {
          typedef void *(*Factory)(void);
          void *rawView = ((Factory)symbol)();
          self.previewContentView = (__bridge_transfer NSView *)rawView;
          self.previewLibraryHandle = handle;
          [self placePreviewContent];
          launched = self.previewContentView != nil;
        }
      }
      [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateAllWindows];
      if (launched) SetPercent(@"Run", 100);
      if (!launched && !launchError) launchError = @"Preview view could not be created.";
    } @catch (NSException *exception) {
      launchError = exception.reason ?: @"Preview library launch failed.";
    }
    dispatch_semaphore_signal(launchedSem);
  });
  dispatch_semaphore_wait(launchedSem, DISPATCH_TIME_FOREVER);
  if (!launched && errorText) *errorText = launchError ?: @"Preview library launch failed.";
  return launched;
}
- (NSString *)bar:(double)value { NSInteger fill = (NSInteger)round(MAX(0, MIN(100, value)) * 15.0 / 100.0); NSMutableString *s = [@"[" mutableCopy]; for (NSInteger i=0;i<fill;i++) [s appendString:@"="]; [s appendString:@">"]; for (NSInteger i=fill;i<15;i++) [s appendString:@" "]; [s appendString:@"]"]; return s; }
- (void)appendConsole:(NSString *)line { if (!self.consoleLog) self.consoleLog = [NSMutableString string]; if (line.length) [self.consoleLog appendFormat:@"%@\n", line]; [self refreshConsole:nil]; }
- (void)refreshConsole:(id)sender {
  if (!self.console) return;
  if (!self.pendingRequestID && !self.terminalJobPending) {
    [self appendPromptToConsoleLog];
    [self showConsoleText:self.consoleLog inputAtEnd:YES];
    return;
  }
  if (!self.pendingRequestID && self.terminalJobPending) {
    [self showConsoleText:self.consoleLog inputAtEnd:YES];
    return;
  }
  NSTimeInterval age = self.lastPercentFetchAt ? -self.lastPercentFetchAt.timeIntervalSinceNow : DBL_MAX;
  if (age >= 1.25) {
    double send = [GetDocument(@"Percent/Send", nil)[@"%"] doubleValue];
    double compile = [GetDocument(@"Percent/Compile", nil)[@"%"] doubleValue];
    double run = [GetDocument(@"Percent/Run", nil)[@"%"] doubleValue];
    self.lastSendPercent = MAX(self.lastSendPercent, send);
    self.lastCompilePercent = MAX(self.lastCompilePercent, compile);
    self.lastRunPercent = MAX(self.lastRunPercent, run);
    self.lastPercentFetchAt = NSDate.date;
  }
  double send = self.lastSendPercent;
  double compile = self.lastCompilePercent;
  double run = self.lastRunPercent;
  NSMutableString *text = self.compileOnlyRequest
    ? [NSMutableString stringWithFormat:@"Sending...%@ %.0f%%\nCompiling...%@ %.0f%%\n", [self bar:send], send, [self bar:compile], compile]
    : [NSMutableString stringWithFormat:@"Sending...%@ %.0f%%\nCompiling...%@ %.0f%%\nRunning...%@ %.0f%%\n", [self bar:send], send, [self bar:compile], compile, [self bar:run], run];
  [text appendString:self.consoleLog ?: @""];
  [self showConsoleText:text inputAtEnd:YES];
}
- (void)sendForPreview:(id)sender {
  if (sender) self.compileOnlyRequest = NO;
  BOOL compileOnly = self.compileOnlyRequest;
  [self saveEditor]; if (self.keepConsoleLogForNextSend) self.keepConsoleLogForNextSend = NO; else self.consoleLog = [NSMutableString string]; self.pendingRequestID = [NSString stringWithFormat:@"%.0f", NSDate.date.timeIntervalSince1970 * 1000]; self.lastSendPercent = 5; self.lastCompilePercent = 0; self.lastRunPercent = 0; self.lastPercentFetchAt = NSDate.date; SetPercent(@"Send", 5); SetPercent(@"Compile", 0); SetPercent(@"Run", 0); [self refreshConsole:nil];
  NSDictionary *p = [self project]; NSError *error = nil;
  self.lastSendPercent = 35; SetPercent(@"Send", 35);
  NSString *source = [self combinedSource];
  self.lastSendPercent = 70; SetPercent(@"Send", 70);
  BOOL ok = PatchDocument([NSString stringWithFormat:@"Threads/%@", self.initialThread ?: @"Thread1"], @{@"send":source, @"appName":p[@"name"] ?: @"SwiftUI App", @"requestId":self.pendingRequestID, @"previewArch":ProcessArch(), @"compileOnly":@(compileOnly), @"status":@"queued", @"preview":@"", @"error":@"", @"sentAt":NSDate.date, @"compiledRequestId":@"", @"compiledChunkCount":@0, @"compiledSize":@0}, &error);
  self.lastSendPercent = ok ? 100 : 0; SetPercent(@"Send", ok ? 100 : 0); [self refreshConsole:nil]; if (!ok) { [self appendConsole:[NSString stringWithFormat:@"Send failed: %@", error.localizedDescription]]; self.pendingRequestID = nil; self.compileOnlyRequest = NO; [self appendPromptToConsoleLog]; [self refreshConsole:nil]; return; }
  [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkPreview:) userInfo:nil repeats:NO];
}
- (void)checkPreview:(id)sender {
  NSDictionary *doc = GetDocument([NSString stringWithFormat:@"Threads/%@", self.initialThread ?: @"Thread1"], nil); [self refreshConsole:nil];
  if (self.pendingRequestID && ![doc[@"requestId"] isEqualToString:self.pendingRequestID]) { [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkPreview:) userInfo:nil repeats:NO]; return; }
  NSString *status = doc[@"status"] ?: @""; if ([status isEqualToString:@"complete"] || [status isEqualToString:@"error"]) {
    if ([status isEqualToString:@"complete"]) {
      if (self.compileOnlyRequest) {
        if ([doc[@"preview"] length]) [self appendConsole:doc[@"preview"]];
        [self appendConsole:@"Compile complete"];
        self.pendingRequestID = nil;
        self.compileOnlyRequest = NO;
        self.lastSendPercent = 0;
        self.lastCompilePercent = 0;
        self.lastRunPercent = 0;
        [self appendPromptToConsoleLog];
        [self refreshConsole:nil];
        return;
      }
      NSString *compiledRequestID = doc[@"compiledRequestId"];
      NSNumber *compiledChunkCount = doc[@"compiledChunkCount"];
      if (![compiledRequestID isEqualToString:self.pendingRequestID] || compiledChunkCount.integerValue <= 0) {
        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkPreview:) userInfo:nil repeats:NO];
        return;
      }
      if (self.openingPreview) return;
      self.openingPreview = YES;
      SetPercent(@"Compile", 100);
      SetPercent(@"Run", 50);
      [self refreshConsole:nil];
      NSDictionary *compiledDoc = [doc copy];
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *errorText = nil;
        BOOL opened = [self openPreviewWindowFromCompiledDocument:compiledDoc errorText:&errorText];
        dispatch_async(dispatch_get_main_queue(), ^{
          if (opened) [self appendConsole:@"Opened preview window"];
          else [self appendConsole:errorText ?: @"Could not open preview window"];
          if ([doc[@"error"] length]) [self appendConsole:doc[@"error"]];
          self.pendingRequestID = nil;
          self.openingPreview = NO;
          self.compileOnlyRequest = NO;
          self.lastSendPercent = 0;
          self.lastCompilePercent = 0;
          self.lastRunPercent = 0;
          [self appendPromptToConsoleLog];
          [self refreshConsole:nil];
        });
      });
      return;
    } else {
      if ([doc[@"preview"] length]) [self appendConsole:doc[@"preview"]];
    }
    if ([doc[@"error"] length]) [self appendConsole:doc[@"error"]]; self.pendingRequestID = nil; self.compileOnlyRequest = NO; self.lastSendPercent = 0; self.lastCompilePercent = 0; self.lastRunPercent = 0; [self appendPromptToConsoleLog]; [self refreshConsole:nil]; return; }
  [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkPreview:) userInfo:nil repeats:NO];
}
@end

int main(int argc, const char *argv[]) {
  if (argc > 1 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"))) { puts("SwiftStudio\n\nUsage:\n  ~/cmds/code_studio [--thread Thread1]\n\nNative NSApplication Studio. Sends raw SwiftUI source to Firestore and displays Send/Compile percentages."); return 0; }
  @autoreleasepool { NSApplication *app = NSApplication.sharedApplication; StudioDelegate *delegate = [StudioDelegate new]; delegate.initialThread = @"Thread1"; for (int i=1;i+1<argc;i++) if (!strcmp(argv[i],"--thread")) delegate.initialThread = [NSString stringWithUTF8String:argv[i+1]]; app.delegate = delegate; [app run]; }
  return 0;
}

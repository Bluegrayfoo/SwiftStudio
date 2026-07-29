#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <float.h>
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
@property NSTextView *editor;
@property NSTextView *console;
@property NSMutableString *consoleLog;
@property NSImage *swiftLogo;
@property BOOL showingProject;
@property BOOL openingPreview;
@property double lastSendPercent;
@property double lastCompilePercent;
@property double lastRunPercent;
@property NSTask *previewTask;
@property BOOL applyingHighlight;
@property BOOL previewPaneCollapsed;
@property BOOL previewPaneWide;
@property NSRect previewPaneFrame;
@property NSView *previewContainerView;
@property NSView *previewContentView;
@property NSWindow *previewWindow;
@property void *previewLibraryHandle;
@end

@implementation StudioDelegate
- (NSString *)docsPath { return [@"~/cmds/swift_studio_projects.json" stringByExpandingTildeInPath]; }
- (void)applicationDidFinishLaunching:(NSNotification *)n {
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]; self.dynamicViews = [NSMutableArray array]; self.ageLabels = [NSMutableDictionary dictionary]; self.consoleLog = [NSMutableString string]; self.previewPaneCollapsed = YES; self.swiftLogo = [[NSImage alloc] initWithContentsOfFile:[@"~/cmds/swiftlogo.png" stringByExpandingTildeInPath]];
  [self loadStore]; [self buildWindow]; [self showMain]; UpdateHistory(@"SwiftStudio"); [NSApp activateIgnoringOtherApps:YES];
  [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(refreshAgeLabels:) userInfo:nil repeats:YES];
  [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updatePreviewPlacement:) userInfo:nil repeats:YES];
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
- (BOOL)isFullScreen { return (self.window.styleMask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen; }
- (BOOL)previewPaneVisible { return [self isFullScreen] && !self.previewPaneCollapsed; }
- (void)updatePreviewPlacement:(id)sender { [self placePreviewContent]; }
- (void)windowDidResize:(NSNotification *)notification { if (self.showingProject) { [self saveEditor]; [self showProject]; } [self placePreviewContent]; }
- (void)windowDidEnterFullScreen:(NSNotification *)notification { self.previewPaneCollapsed = NO; if (self.showingProject) [self showProject]; [self placePreviewContent]; }
- (void)windowDidExitFullScreen:(NSNotification *)notification { if (self.showingProject) [self showProject]; [self placePreviewContent]; }
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
  [self redButton:@"Delete" frame:NSMakeRect(308,18,118,36) action:@selector(deleteProject:)];
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
- (void)showProject {
  self.showingProject = YES; [self clearDynamic]; [self.ageLabels removeAllObjects]; NSDictionary *p = [self project]; if (!self.activeFileID) self.activeFileID = p[@"activeFile"] ?: self.fileIDs.firstObject;
  NSRect b = self.root.bounds;
  CGFloat leftW = 244, headerY = MAX(674, b.size.height - 91), contentTop = headerY - 19, consoleH = 126;
  BOOL previewVisible = [self previewPaneVisible];
  CGFloat sideBarW = (previewVisible && self.previewPaneWide) ? 46 : 0;
  CGFloat editorX = 264, editorY = 165, consoleY = 16;
  CGFloat previewW = 0, editorW = MAX(260, b.size.width - editorX - 44);
  if (previewVisible && self.previewPaneWide) {
    previewW = MAX(260, b.size.width - leftW - sideBarW - 38);
    editorW = 0;
    self.previewPaneFrame = NSMakeRect(leftW + sideBarW + 16, consoleY, previewW, contentTop - consoleY);
  } else if (previewVisible) {
    previewW = MAX(330, MIN(520, b.size.width * 0.32));
    CGFloat rightEdge = b.size.width - 22 - previewW;
    editorW = MAX(260, rightEdge - editorX - 16);
    previewW = MIN(previewW, MAX(260, b.size.width - (editorX + editorW + 16) - 22));
    self.previewPaneFrame = NSMakeRect(editorX + editorW + 16, consoleY, previewW, contentTop - consoleY);
  } else {
    self.previewPaneFrame = NSZeroRect;
  }
  CGFloat editorH = MAX(220, contentTop - editorY);
  [self button:@"<" frame:NSMakeRect(18,headerY+26,32,32) action:@selector(back:) blue:YES]; [self label:p[@"name"] frame:NSMakeRect(64,headerY+6,210,58) font:TitleFont(42) color:NSColor.whiteColor]; [self button:@"Send" frame:NSMakeRect(245,headerY+16,190,44) action:@selector(sendForPreview:) blue:YES]; [self redButton:@"Stop" frame:NSMakeRect(448,headerY+16,112,44) action:@selector(stopPreview:)]; [self button:@"Rename" frame:NSMakeRect(572,headerY+16,130,44) action:@selector(renameProjectInEditor:) blue:YES]; [self button:@"Rename File" frame:NSMakeRect(714,headerY+16,170,44) action:@selector(renameFile:) blue:YES]; [self addLine:NSMakeRect(0,headerY,b.size.width,2)]; [self addLine:NSMakeRect(leftW,0,2,headerY)]; [self addLine:NSMakeRect(editorX,155,editorW,2)];
  if (previewVisible) {
    CGFloat dividerX = self.previewPaneFrame.origin.x - 9 - sideBarW;
    [self addLine:NSMakeRect(dividerX, 0, 2, headerY)];
    if (self.previewPaneWide) {
      NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(dividerX + 2, 0, sideBarW, headerY)];
      bar.wantsLayer = YES; bar.layer.backgroundColor = DarkRow().CGColor;
      [self.dynamicViews addObject:bar]; [self.root addSubview:bar];
      [self button:@">|>" frame:NSMakeRect(dividerX + 7, headerY - 70, 36, 32) action:@selector(normalPreviewPane:) blue:YES];
      [self button:@">|" frame:NSMakeRect(dividerX + 7, headerY - 112, 36, 32) action:@selector(collapsePreviewPane:) blue:YES];
    } else {
      [self button:@"|<" frame:NSMakeRect(self.previewPaneFrame.origin.x - 55, headerY + 15, 42, 34) action:@selector(widenPreviewPane:) blue:YES];
    }
    self.previewContainerView = [[NSView alloc] initWithFrame:self.previewPaneFrame]; self.previewContainerView.wantsLayer = YES; self.previewContainerView.layer.backgroundColor = NSColor.blackColor.CGColor; self.previewContainerView.layer.borderColor = NSColor.whiteColor.CGColor; self.previewContainerView.layer.borderWidth = 1; [self.dynamicViews addObject:self.previewContainerView]; [self.root addSubview:self.previewContainerView];
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
  CGFloat y = contentTop - 30; for (NSString *fid in self.fileIDs) { NSDictionary *f = [self project][@"files"][fid]; if (self.swiftLogo) { NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(10,y-1,32,28)]; iv.image = self.swiftLogo; [self.dynamicViews addObject:iv]; [self.root addSubview:iv]; } [self label:f[@"name"] frame:NSMakeRect(54,y,175,27) font:MonoFont(21) color:NSColor.whiteColor]; NSButton *hit = [self button:@"" frame:NSMakeRect(0,y-4,240,34) action:@selector(selectFile:) blue:NO]; hit.identifier = fid; hit.layer.backgroundColor = ([fid isEqualToString:self.activeFileID] ? Blue() : NSColor.clearColor).CGColor; hit.layer.opacity = [fid isEqualToString:self.activeFileID] ? 0.35 : 0.0; y -= 36; }
  [self button:@"+" frame:NSMakeRect(18,18,32,32) action:@selector(newFile:) blue:YES]; [self button:(previewVisible ? @"<" : @">") frame:NSMakeRect(58,18,32,32) action:@selector(togglePreviewPane:) blue:YES];
  if (!self.previewPaneWide) {
    NSScrollView *editScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(editorX,editorY,editorW,editorH)]; editScroll.borderType = NSNoBorder; [self tuneScrollView:editScroll]; editScroll.wantsLayer = YES; editScroll.layer.backgroundColor = NSColor.blackColor.CGColor;
    self.editor = [[NSTextView alloc] initWithFrame:editScroll.bounds]; self.editor.font = MonoFont(19); self.editor.textColor = NSColor.whiteColor; self.editor.backgroundColor = NSColor.blackColor; self.editor.insertionPointColor = NSColor.whiteColor; self.editor.automaticQuoteSubstitutionEnabled = NO; self.editor.automaticDashSubstitutionEnabled = NO; self.editor.automaticTextReplacementEnabled = NO; self.editor.allowsUndo = YES; self.editor.delegate = self; self.editor.string = [self file][@"code"] ?: @""; editScroll.documentView = self.editor; [self.dynamicViews addObject:editScroll]; [self.root addSubview:editScroll]; [self applySyntaxHighlighting];
    NSScrollView *consoleScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(editorX,consoleY,editorW,consoleH)]; [self tuneScrollView:consoleScroll]; consoleScroll.wantsLayer = YES; consoleScroll.layer.backgroundColor = NSColor.blackColor.CGColor; self.console = [[NSTextView alloc] initWithFrame:consoleScroll.bounds]; self.console.font = MonoFont(19); self.console.textColor = NSColor.whiteColor; self.console.backgroundColor = NSColor.blackColor; self.console.editable = NO; self.console.verticallyResizable = YES; self.console.maxSize = NSMakeSize(FLT_MAX, FLT_MAX); consoleScroll.documentView = self.console; [self.dynamicViews addObject:consoleScroll]; [self.root addSubview:consoleScroll]; [self refreshConsole:nil];
  }
  [self placePreviewContent];
}
- (void)editorChangedProgrammatically {
  [self file][@"code"] = self.editor.string ?: @"";
  [self project][@"updatedAt"] = @(NSDate.date.timeIntervalSince1970);
  [self saveStore];
  [self applySyntaxHighlighting];
}
- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)replacementString {
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
      NSRange nextLineRange = [updated lineRangeForRange:NSMakeRange(nextLineStart, 0)];
      if (nextLineRange.location == nextLineStart && nextLineRange.location < updated.length) {
        NSString *nextLine = [updated substringWithRange:NSMakeRange(nextLineRange.location, MIN(nextLineRange.length, updated.length - nextLineRange.location))];
        NSString *trimmed = [nextLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length && ![trimmed hasPrefix:@"}"]) {
          NSUInteger existingIndentLength = 0;
          while (existingIndentLength < nextLine.length) {
            unichar c = [nextLine characterAtIndex:existingIndentLength];
            if (c == ' ' || c == '\t') existingIndentLength++; else break;
          }
          [textView.textStorage replaceCharactersInRange:NSMakeRange(nextLineRange.location, existingIndentLength) withString:targetIndent];
        }
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
- (void)textDidChange:(NSNotification *)n { [self file][@"code"] = self.editor.string ?: @""; [self project][@"updatedAt"] = @(NSDate.date.timeIntervalSince1970); [self saveStore]; [self applySyntaxHighlighting]; }
- (void)saveEditor { if (!self.editor) return; [self file][@"code"] = self.editor.string ?: @""; [self project][@"updatedAt"] = @(NSDate.date.timeIntervalSince1970); [self saveStore]; }
- (void)back:(id)sender { [self saveEditor]; [self showMain]; }
- (void)renameProjectInEditor:(id)sender { [self saveEditor]; [self renameProject:sender]; [self showProject]; }
- (void)selectFile:(NSButton *)sender { [self saveEditor]; self.activeFileID = sender.identifier; [self project][@"activeFile"] = self.activeFileID; [self saveStore]; [self showProject]; }
- (void)newFile:(id)sender { NSString *fid = [NSString stringWithFormat:@"File%lu", (unsigned long)self.fileIDs.count + 1]; [self project][@"files"][fid] = [@{@"name":fid, @"code":@"import SwiftUI\n"} mutableCopy]; self.activeFileID = fid; [self project][@"activeFile"] = fid; [self saveStore]; [self showProject]; }
- (void)togglePreviewPane:(id)sender { self.previewPaneCollapsed = !self.previewPaneCollapsed; if (self.previewPaneCollapsed) self.previewPaneWide = NO; [self showProject]; [self placePreviewContent]; }
- (void)widenPreviewPane:(id)sender { self.previewPaneCollapsed = NO; self.previewPaneWide = YES; [self showProject]; [self placePreviewContent]; }
- (void)normalPreviewPane:(id)sender { self.previewPaneCollapsed = NO; self.previewPaneWide = NO; [self showProject]; [self placePreviewContent]; }
- (void)collapsePreviewPane:(id)sender { self.previewPaneCollapsed = YES; self.previewPaneWide = NO; [self showProject]; [self placePreviewContent]; }
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
  dispatch_group_t group = dispatch_group_create();
  for (NSInteger i = 0; i < chunkCount; i++) {
    dispatch_group_enter(group);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSError *error = nil;
      NSString *chunkPath = [NSString stringWithFormat:@"Threads/%@/Compiled/%@-%04ld", thread, requestID, (long)i];
      NSDictionary *chunk = GetDocument(chunkPath, &error);
      @synchronized (chunks) {
        if (error && !downloadError) downloadError = error.localizedDescription;
        NSString *data = chunk[@"data"];
        if (!error && !data.length && !downloadError) downloadError = [NSString stringWithFormat:@"Missing compiled preview library chunk %ld.", (long)i];
        if (data.length) chunks[(NSUInteger)i] = data;
        completedChunks++;
        double downloadProgress = 45.0 + (((double)completedChunks) / MAX(1.0, (double)chunkCount)) * 20.0;
        SetPercent(@"Run", MAX(50.0, downloadProgress));
      }
      dispatch_async(dispatch_get_main_queue(), ^{ [self refreshConsole:nil]; });
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
  if (!self.pendingRequestID) { self.console.string = self.consoleLog ?: @""; [self.console scrollRangeToVisible:NSMakeRange(self.console.string.length, 0)]; return; }
  double send = [GetDocument(@"Percent/Send", nil)[@"%"] doubleValue]; double compile = [GetDocument(@"Percent/Compile", nil)[@"%"] doubleValue]; double run = [GetDocument(@"Percent/Run", nil)[@"%"] doubleValue];
  self.lastSendPercent = MAX(self.lastSendPercent, send);
  self.lastCompilePercent = MAX(self.lastCompilePercent, compile);
  self.lastRunPercent = MAX(self.lastRunPercent, run);
  send = self.lastSendPercent;
  compile = self.lastCompilePercent;
  run = self.lastRunPercent;
  NSMutableString *text = [NSMutableString stringWithFormat:@"Sending...%@ %.0f%%\nCompiling...%@ %.0f%%\nRunning...%@ %.0f%%\n", [self bar:send], send, [self bar:compile], compile, [self bar:run], run];
  [text appendString:self.consoleLog ?: @""];
  self.console.string = text;
  [self.console scrollRangeToVisible:NSMakeRange(self.console.string.length, 0)];
}
- (void)sendForPreview:(id)sender {
  [self saveEditor]; self.consoleLog = [NSMutableString string]; self.pendingRequestID = [NSString stringWithFormat:@"%.0f", NSDate.date.timeIntervalSince1970 * 1000]; self.lastSendPercent = 0; self.lastCompilePercent = 0; self.lastRunPercent = 0; SetPercent(@"Send", 5); SetPercent(@"Compile", 0); SetPercent(@"Run", 0); [self refreshConsole:nil];
  NSDictionary *p = [self project]; NSError *error = nil;
  SetPercent(@"Send", 35);
  NSString *source = [self combinedSource];
  SetPercent(@"Send", 70);
  BOOL ok = PatchDocument([NSString stringWithFormat:@"Threads/%@", self.initialThread ?: @"Thread1"], @{@"send":source, @"appName":p[@"name"] ?: @"SwiftUI App", @"requestId":self.pendingRequestID, @"previewArch":ProcessArch(), @"status":@"queued", @"preview":@"", @"error":@"", @"sentAt":NSDate.date, @"compiledRequestId":@"", @"compiledChunkCount":@0, @"compiledSize":@0}, &error);
  SetPercent(@"Send", ok ? 100 : 0); [self refreshConsole:nil]; if (!ok) { [self appendConsole:[NSString stringWithFormat:@"Send failed: %@", error.localizedDescription]]; self.pendingRequestID = nil; [self refreshConsole:nil]; return; }
  [NSTimer scheduledTimerWithTimeInterval:0.35 target:self selector:@selector(checkPreview:) userInfo:nil repeats:NO];
}
- (void)checkPreview:(id)sender {
  NSDictionary *doc = GetDocument([NSString stringWithFormat:@"Threads/%@", self.initialThread ?: @"Thread1"], nil); [self refreshConsole:nil];
  if (self.pendingRequestID && ![doc[@"requestId"] isEqualToString:self.pendingRequestID]) { [NSTimer scheduledTimerWithTimeInterval:0.35 target:self selector:@selector(checkPreview:) userInfo:nil repeats:NO]; return; }
  NSString *status = doc[@"status"] ?: @""; if ([status isEqualToString:@"complete"] || [status isEqualToString:@"error"]) {
    if ([status isEqualToString:@"complete"]) {
      NSString *compiledRequestID = doc[@"compiledRequestId"];
      NSNumber *compiledChunkCount = doc[@"compiledChunkCount"];
      if (![compiledRequestID isEqualToString:self.pendingRequestID] || compiledChunkCount.integerValue <= 0) {
        [NSTimer scheduledTimerWithTimeInterval:0.35 target:self selector:@selector(checkPreview:) userInfo:nil repeats:NO];
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
          self.lastSendPercent = 0;
          self.lastCompilePercent = 0;
          self.lastRunPercent = 0;
          [self refreshConsole:nil];
        });
      });
      return;
    } else {
      if ([doc[@"preview"] length]) [self appendConsole:doc[@"preview"]];
    }
    if ([doc[@"error"] length]) [self appendConsole:doc[@"error"]]; self.pendingRequestID = nil; self.lastSendPercent = 0; self.lastCompilePercent = 0; self.lastRunPercent = 0; [self refreshConsole:nil]; return; }
  [NSTimer scheduledTimerWithTimeInterval:0.35 target:self selector:@selector(checkPreview:) userInfo:nil repeats:NO];
}
@end

int main(int argc, const char *argv[]) {
  if (argc > 1 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"))) { puts("SwiftStudio\n\nUsage:\n  ~/cmds/code_studio [--thread Thread1]\n\nNative NSApplication Studio. Sends raw SwiftUI source to Firestore and displays Send/Compile percentages."); return 0; }
  @autoreleasepool { NSApplication *app = NSApplication.sharedApplication; StudioDelegate *delegate = [StudioDelegate new]; delegate.initialThread = @"Thread1"; for (int i=1;i+1<argc;i++) if (!strcmp(argv[i],"--thread")) delegate.initialThread = [NSString stringWithUTF8String:argv[i+1]]; app.delegate = delegate; [app run]; }
  return 0;
}

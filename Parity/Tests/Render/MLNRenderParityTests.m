// Renders MapLibre Native render-test styles (metrics/integration/render-tests
// of the upstream release) through the public API, for Parity/compare.py to
// compare between implementations. It does not compare against the expected
// images: both implementations render with their own core, and only the
// differences between them matter here.
//
// Environment (passed by run.sh as TEST_RUNNER_…):
//   PARITY_RENDER_TESTS  the metrics/integration directory
//   PARITY_RENDER_LIST   a file of test ids ("fill-color/default"), or "all"
//   PARITY_RENDER_ONSCREEN_LIST  test ids to also render with an on-screen MLNMapView

#import "ParityMapTestCase.h"

@interface MLNRenderParityTests : XCTestCase <MLNMapViewDelegate>
@end

@implementation MLNRenderParityTests {
  XCTestExpectation *_rendered;
}

+ (NSArray<NSString *> *)testIdsFromList:(NSString *)list inDirectory:(NSString *)directory {
  if ([list isEqualToString:@"all"]) {
    NSMutableArray *ids = [NSMutableArray array];
    NSString *root = [directory stringByAppendingPathComponent:@"render-tests"];
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:root];
    for (NSString *path in enumerator) {
      if ([path.lastPathComponent isEqualToString:@"style.json"]) {
        [ids addObject:path.stringByDeletingLastPathComponent];
      }
    }
    return [ids sortedArrayUsingSelector:@selector(compare:)];
  }
  NSString *contents = [NSString stringWithContentsOfFile:list encoding:NSUTF8StringEncoding error:nil];
  NSMutableArray *ids = [NSMutableArray array];
  for (NSString *line in [contents componentsSeparatedByString:@"\n"]) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (trimmed.length && ![trimmed hasPrefix:@"#"]) {
      [ids addObject:trimmed];
    }
  }
  return ids;
}

/// Rewrites local:// URLs to file:// URLs in the integration directory.
+ (id)rewrite:(id)value directory:(NSString *)directory {
  if ([value isKindOfClass:[NSString class]] && [value hasPrefix:@"local://"]) {
    return [@"file://" stringByAppendingString:[directory stringByAppendingPathComponent:[value substringFromIndex:8]]];
  }
  if ([value isKindOfClass:[NSArray class]]) {
    NSMutableArray *array = [NSMutableArray array];
    for (id element in value) {
      [array addObject:[self rewrite:element directory:directory]];
    }
    return array;
  }
  if ([value isKindOfClass:[NSDictionary class]]) {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    [value enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
      dictionary[key] = [self rewrite:object directory:directory];
    }];
    return dictionary;
  }
  return value;
}

/// Why a render test cannot be rendered through the public API, or nil.
+ (NSString *)unsupportedReason:(NSDictionary *)style {
  NSDictionary *test = style[@"metadata"][@"test"];
  for (NSString *key in @[ @"debug", @"collisionDebug", @"showOverdrawInspector", @"localIdeographFontFamily",
                           @"crossSourceCollisions", @"axonometric", @"skew", @"queryGeometry", @"addFakeCanvas" ]) {
    if (test[key]) {
      return [@"uses metadata.test." stringByAppendingString:key];
    }
  }
  if (test[@"mapMode"] && ![test[@"mapMode"] isEqual:@"static"]) {
    return [NSString stringWithFormat:@"mapMode %@", test[@"mapMode"]];
  }
  for (id operation in test[@"operations"] ?: @[]) {
    if (![operation isKindOfClass:[NSArray class]] || ![[operation firstObject] isEqual:@"wait"]) {
      return [NSString stringWithFormat:@"operation %@", [operation isKindOfClass:[NSArray class]] ? [operation firstObject] : operation];
    }
  }
  return nil;
}

- (void)testRenderSnapshots {
  NSDictionary *environment = NSProcessInfo.processInfo.environment;
  NSString *directory = environment[@"PARITY_RENDER_TESTS"];
  NSString *list = environment[@"PARITY_RENDER_LIST"];
  if (!directory.length || !list.length) {
    NSLog(@"PARITY_RENDER_TESTS/PARITY_RENDER_LIST not set; skipping render parity.");
    return;
  }
  NSArray *onscreen = [self.class testIdsFromList:environment[@"PARITY_RENDER_ONSCREEN_LIST"] ?: @"" inDirectory:directory];
  NSMutableDictionary *results = [NSMutableDictionary dictionary];
  for (NSString *testId in [self.class testIdsFromList:list inDirectory:directory]) {
    @autoreleasepool {
      results[testId] = [self renderTest:testId directory:directory onscreen:[onscreen containsObject:testId]];
    }
  }
  [ParityRecorder writeJSON:results toFile:@"render/results.json"];
}

- (NSDictionary *)renderTest:(NSString *)testId directory:(NSString *)directory onscreen:(BOOL)renderOnscreen {
  NSString *stylePath = [[directory stringByAppendingPathComponent:@"render-tests"]
      stringByAppendingPathComponent:[testId stringByAppendingPathComponent:@"style.json"]];
  NSData *data = [NSData dataWithContentsOfFile:stylePath];
  NSDictionary *style = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  if (![style isKindOfClass:[NSDictionary class]]) {
    return @{@"status" : @"error", @"reason" : @"style.json missing or invalid"};
  }
  NSString *reason = [self.class unsupportedReason:style];
  if (reason) {
    return @{@"status" : @"skipped", @"reason" : reason};
  }
  NSDictionary *test = style[@"metadata"][@"test"];
  CGFloat width = [test[@"width"] ?: @512 doubleValue];
  CGFloat height = [test[@"height"] ?: @512 doubleValue];
  CGFloat pixelRatio = [test[@"pixelRatio"] ?: @1 doubleValue];

  NSDictionary *rewritten = [self.class rewrite:style directory:directory];
  NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                   [[testId stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
                                                       stringByAppendingPathExtension:@"json"]];
  [[NSJSONSerialization dataWithJSONObject:rewritten options:0 error:nil] writeToFile:tempPath atomically:YES];
  NSURL *styleURL = [NSURL fileURLWithPath:tempPath];

  NSArray *center = style[@"center"] ?: @[ @0, @0 ];
  MLNMapCamera *camera = [MLNMapCamera camera];
  camera.centerCoordinate = CLLocationCoordinate2DMake([center[1] doubleValue], [center[0] doubleValue]);
  camera.heading = [style[@"bearing"] ?: @0 doubleValue];
  camera.pitch = [style[@"pitch"] ?: @0 doubleValue];
  MLNMapSnapshotOptions *options = [[MLNMapSnapshotOptions alloc] initWithStyleURL:styleURL
                                                                           camera:camera
                                                                             size:CGSizeMake(width, height)];
  options.zoomLevel = [style[@"zoom"] ?: @0 doubleValue];
  options.scale = pixelRatio;

  NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:@{@"status" : @"rendered"}];
  MLNMapSnapshotter *snapshotter = [[MLNMapSnapshotter alloc] initWithOptions:options];
  XCTestExpectation *done = [self expectationWithDescription:testId];
  NSDate *start = [NSDate date];
  [snapshotter startWithCompletionHandler:^(MLNMapSnapshot *snapshot, NSError *error) {
    if (error) {
      result[@"status"] = @"error";
      result[@"reason"] = [NSString stringWithFormat:@"%@ %ld: %@", error.domain, (long)error.code, error.localizedDescription];
    } else {
      [ParityRecorder writeData:UIImagePNGRepresentation(snapshot.image)
                         toFile:[NSString stringWithFormat:@"render/snapshot/%@.png", testId]];
      result[@"imageSize"] = @[ @(snapshot.image.size.width * snapshot.image.scale), @(snapshot.image.size.height * snapshot.image.scale) ];
    }
    [done fulfill];
  }];
  XCTWaiterResult waited = [XCTWaiter waitForExpectations:@[ done ] timeout:15];
  if (waited != XCTWaiterResultCompleted) {
    [snapshotter cancel];
    result[@"status"] = @"timeout";
  }
  result[@"seconds"] = @(-[start timeIntervalSinceNow]);
  if (renderOnscreen) {
    result[@"onscreen"] = [self renderOnscreen:testId styleURL:styleURL style:style size:CGSizeMake(width, height)];
  }
  return result;
}

- (NSDictionary *)renderOnscreen:(NSString *)testId styleURL:(NSURL *)styleURL style:(NSDictionary *)style size:(CGSize)size {
  UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
  MLNMapView *mapView = [[MLNMapView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height) styleURL:styleURL];
  mapView.delegate = self;
  mapView.logoView.hidden = YES;
  mapView.attributionButton.hidden = YES;
  mapView.compassView.compassVisibility = MLNOrnamentVisibilityHidden;
  mapView.scaleBar.hidden = YES;
  NSArray *center = style[@"center"] ?: @[ @0, @0 ];
  [mapView setCenterCoordinate:CLLocationCoordinate2DMake([center[1] doubleValue], [center[0] doubleValue])
                     zoomLevel:[style[@"zoom"] ?: @0 doubleValue]
                     direction:[style[@"bearing"] ?: @0 doubleValue]
                      animated:NO];
  [window.rootViewController.view addSubview:mapView];
  _rendered = [self expectationWithDescription:[testId stringByAppendingString:@" on screen"]];
  XCTWaiterResult waited = [XCTWaiter waitForExpectations:@[ _rendered ] timeout:15];
  _rendered = nil;
  NSString *status = waited == XCTWaiterResultCompleted ? @"rendered" : @"timeout";
  UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
  format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
  UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:mapView.bounds format:format];
  UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
    [mapView drawViewHierarchyInRect:mapView.bounds afterScreenUpdates:YES];
  }];
  [ParityRecorder writeData:UIImagePNGRepresentation(image)
                     toFile:[NSString stringWithFormat:@"render/onscreen/%@.png", testId]];
  [mapView removeFromSuperview];
  return @{@"status" : status};
}

- (void)mapViewDidFinishRenderingMap:(MLNMapView *)mapView fullyRendered:(BOOL)fullyRendered {
  if (fullyRendered) {
    [_rendered fulfill];
    _rendered = nil;
  }
}

@end

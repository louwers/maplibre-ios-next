// Offline pack lifecycle against local tiles.

#import <XCTest/XCTest.h>

@import MapLibre;

#import "ParityRecorder.h"

@interface MLNOfflineTraceTests : XCTestCase
@property (nonatomic) ParityRecorder *recorder;
@end

@implementation MLNOfflineTraceTests

- (void)setUp {
  [super setUp];
  self.recorder = [ParityRecorder recorderForTest:self];
}

/// A style whose vector source points at a few local tiles of the upstream render tests.
- (NSURL *)localTileStyleURL {
  NSString *upstream = NSProcessInfo.processInfo.environment[@"PARITY_UPSTREAM"];
  NSString *tiles = upstream ? [upstream stringByAppendingPathComponent:@"metrics/integration/tiles"] : @"/missing";
  NSDictionary *style = @{
    @"version" : @8,
    @"sources" : @{
      @"vector" : @{@"type" : @"vector", @"tiles" : @[ [NSString stringWithFormat:@"file://%@/{z}-{x}-{y}.mvt", tiles] ], @"maxzoom" : @1}
    },
    @"layers" : @[ @{@"id" : @"water", @"type" : @"fill", @"source" : @"vector", @"source-layer" : @"water"} ],
  };
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"parity-offline-style.json"];
  [[NSJSONSerialization dataWithJSONObject:style options:0 error:nil] writeToFile:path atomically:YES];
  return [NSURL fileURLWithPath:path];
}

- (void)testPackLifecycle {
  MLNOfflineStorage *storage = MLNOfflineStorage.sharedOfflineStorage;
  // Upstream's MLNOfflineStorageTests delete the database file when they
  // finish; start from a fresh database, whatever ran before.
  XCTestExpectation *reset = [self expectationWithDescription:@"reset"];
  [storage resetDatabaseWithCompletionHandler:^(NSError *error) {
    [self.recorder record:@"resetError" value:error];
    [reset fulfill];
  }];
  [self waitForExpectations:@[ reset ] timeout:10];
  [storage reloadPacks];
  XCTestExpectation *loaded = [self keyValueObservingExpectationForObject:storage keyPath:@"packs" handler:^BOOL(id object, NSDictionary *change) {
    return storage.packs != nil;
  }];
  if (storage.packs) {
    [loaded fulfill];
  }
  [self waitForExpectations:@[ loaded ] timeout:10];
  for (MLNOfflinePack *pack in [storage.packs copy]) {
    XCTestExpectation *removed = [self expectationWithDescription:@"cleanup"];
    [storage removePack:pack withCompletionHandler:^(NSError *error) {
      [removed fulfill];
    }];
    [self waitForExpectations:@[ removed ] timeout:10];
  }
  [self.recorder record:@"packsBefore" value:@(storage.packs.count)];

  MLNTilePyramidOfflineRegion *region = [[MLNTilePyramidOfflineRegion alloc]
      initWithStyleURL:[self localTileStyleURL]
                bounds:MLNCoordinateBoundsMake(CLLocationCoordinate2DMake(-80, -170), CLLocationCoordinate2DMake(80, 170))
         fromZoomLevel:0
           toZoomLevel:1];
  NSData *context = [@"parity" dataUsingEncoding:NSUTF8StringEncoding];
  __block MLNOfflinePack *pack;
  XCTestExpectation *added = [self expectationWithDescription:@"added"];
  [storage addPackForRegion:region withContext:context completionHandler:^(MLNOfflinePack *newPack, NSError *error) {
    pack = newPack;
    [self.recorder record:@"addError" value:error];
    [added fulfill];
  }];
  [self waitForExpectations:@[ added ] timeout:10];
  [self.recorder record:@"state.added" value:@(pack.state)];
  [self.recorder record:@"context" value:[[NSString alloc] initWithData:pack.context encoding:NSUTF8StringEncoding]];
  [self.recorder record:@"region.class" value:NSStringFromClass([pack.region class])];

  NSMutableArray *states = [NSMutableArray array];
  XCTestExpectation *complete = [self expectationForNotification:MLNOfflinePackProgressChangedNotification object:pack handler:^BOOL(NSNotification *notification) {
    MLNOfflinePack *p = notification.object;
    NSNumber *state = @(p.state);
    if (![states.lastObject isEqual:state]) {
      [states addObject:state];
    }
    return p.state == MLNOfflinePackStateComplete;
  }];
  [pack resume];
  XCTWaiterResult result = [XCTWaiter waitForExpectations:@[ complete ] timeout:10];
  [self.recorder record:@"completed" value:@(result == XCTWaiterResultCompleted)];
  [self.recorder record:@"states" value:states];
  MLNOfflinePackProgress progress = pack.progress;
  [self.recorder record:@"progress" value:@{
    @"countOfResourcesCompleted" : @(progress.countOfResourcesCompleted),
    @"countOfResourcesExpected" : @(progress.countOfResourcesExpected),
    @"countOfTilesCompleted" : @(progress.countOfTilesCompleted),
    @"maximumResourcesExpected" : @(progress.maximumResourcesExpected),
  }];
  [self.recorder record:@"packsAfterAdd" value:@(storage.packs.count)];

  XCTestExpectation *removed = [self expectationWithDescription:@"removed"];
  [storage removePack:pack withCompletionHandler:^(NSError *error) {
    [self.recorder record:@"removeError" value:error];
    [removed fulfill];
  }];
  [self waitForExpectations:@[ removed ] timeout:10];
  [self.recorder record:@"state.removed" value:@(pack.state)];
  [self.recorder record:@"packsAfterRemove" value:@(storage.packs.count)];
}

@end

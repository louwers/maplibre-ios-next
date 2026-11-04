// Feature queries, feature state and clusters on the fixture style.

#import "ParityMapTestCase.h"

@interface MLNQueryTraceTests : ParityMapTestCase
@end

@implementation MLNQueryTraceTests

- (void)setUp {
  [super setUp];
  [self.mapView setCenterCoordinate:CLLocationCoordinate2DMake(52.2, 4.8) zoomLevel:7 animated:NO];
  [self waitForFullRender];
}

- (NSArray *)sorted:(NSArray *)features {
  return [features sortedArrayUsingComparator:^NSComparisonResult(id<MLNFeature> a, id<MLNFeature> b) {
    return [[a.identifier description] compare:[b.identifier description]];
  }];
}

- (void)testRenderedFeatures {
  CGPoint amsterdam = [self.mapView convertCoordinate:CLLocationCoordinate2DMake(52.37, 4.9) toPointToView:self.mapView];
  [self.recorder record:@"atPoint" value:[self sorted:[self.mapView visibleFeaturesAtPoint:amsterdam]]];
  [self.recorder record:@"atPointInLayer" value:[self sorted:[self.mapView visibleFeaturesAtPoint:amsterdam inStyleLayersWithIdentifiers:[NSSet setWithObject:@"cities"]]]];
  CGRect all = self.mapView.bounds;
  [self.recorder record:@"inRect" value:[self sorted:[self.mapView visibleFeaturesInRect:all]]];
  [self.recorder record:@"inRectFiltered" value:[self sorted:[self.mapView visibleFeaturesInRect:all inStyleLayersWithIdentifiers:[NSSet setWithObjects:@"cities", @"road", nil] predicate:[NSPredicate predicateWithFormat:@"kind == 'city' OR kind == 'road'"]]]];
}

- (void)testSourceFeatures {
  MLNShapeSource *points = (MLNShapeSource *)[self.mapView.style sourceWithIdentifier:@"points"];
  [self.recorder record:@"all" value:[self sorted:[points featuresMatchingPredicate:nil]]];
  [self.recorder record:@"filtered" value:[self sorted:[points featuresMatchingPredicate:[NSPredicate predicateWithFormat:@"rank > 1"]]]];
}

- (void)testFeatureState {
  MLNShapeSource *points = (MLNShapeSource *)[self.mapView.style sourceWithIdentifier:@"points"];
  [self.recorder record:@"set" value:@([points setFeatureStateForFeatureID:@"1" state:@{@"hover" : @YES, @"count" : @3}])];
  [self.recorder record:@"state" value:[points featureStateForFeatureID:@"1"]];
  [self.recorder record:@"removeKey" value:@([points removeFeatureStateForFeatureID:@"1" stateKey:@"hover"])];
  [self.recorder record:@"stateAfterRemovingKey" value:[points featureStateForFeatureID:@"1"]];
  [self.recorder record:@"reset" value:@([points resetFeatureStates])];
  [self.recorder record:@"stateAfterReset" value:[points featureStateForFeatureID:@"1"]];
}

- (void)testClusters {
  [self.mapView setCenterCoordinate:CLLocationCoordinate2DMake(50, 10) zoomLevel:5 animated:NO];
  [self waitForFullRender];
  MLNShapeSource *clustered = (MLNShapeSource *)[self.mapView.style sourceWithIdentifier:@"clustered"];
  NSArray *features = [self.mapView visibleFeaturesInRect:self.mapView.bounds inStyleLayersWithIdentifiers:[NSSet setWithObject:@"clusters"]];
  [self.recorder record:@"clusters" value:features];
  for (id<MLNFeature> feature in features) {
    if ([feature conformsToProtocol:@protocol(MLNCluster)]) {
      MLNPointFeatureCluster *cluster = (MLNPointFeatureCluster *)feature;
      [self.recorder record:@"cluster.identifier" value:@(cluster.clusterIdentifier)];
      [self.recorder record:@"cluster.count" value:@(cluster.clusterPointCount)];
      [self.recorder record:@"cluster.children" value:[clustered childrenOfCluster:cluster]];
      [self.recorder record:@"cluster.leaves" value:[clustered leavesOfCluster:cluster offset:0 limit:10]];
      [self.recorder record:@"cluster.expansionZoom" value:@([clustered zoomLevelForExpandingCluster:cluster])];
    }
  }
}

@end

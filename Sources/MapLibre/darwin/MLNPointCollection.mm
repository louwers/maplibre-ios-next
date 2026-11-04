// Based on platform/darwin/src/MLNPointCollection.mm at ios-v7.0.0

#import "MLNGeometry_Private.h"
#import "MLNLoggingConfiguration_Private.h"
#import "MLNPointCollection_Private.h"
#import "MLNLatLngBounds.h"
#import "NSArray+MLNAdditions.h"

#include <optional>
#include <vector>

NS_ASSUME_NONNULL_BEGIN

@implementation MLNPointCollection {
  std::optional<mln_lat_lng_bounds> _bounds;
  std::vector<CLLocationCoordinate2D> _coordinates;
}

+ (BOOL)supportsSecureCoding {
  return YES;
}

+ (instancetype)pointCollectionWithCoordinates:(const CLLocationCoordinate2D *)coords
                                         count:(NSUInteger)count {
  return [[self alloc] initWithCoordinates:coords count:count];
}

- (instancetype)initWithCoordinates:(const CLLocationCoordinate2D *)coords count:(NSUInteger)count {
  MLNLogDebug(@"Initializing with %lu coordinates.", (unsigned long)count);
  self = [super init];
  if (self) {
    _coordinates = {coords, coords + count};
  }
  return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)decoder {
  MLNLogInfo(@"Initializing with coder.O");
  if (self = [super initWithCoder:decoder]) {
    NSSet<Class> *coordinatesClasses =
        [NSSet setWithArray:@[ [NSDictionary class], [NSArray class] ]];
    NSArray *coordinates = [decoder decodeObjectOfClasses:coordinatesClasses forKey:@"coordinates"];
    _coordinates = [coordinates mgl_coordinates];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:[NSArray mgl_coordinatesFromCoordinates:_coordinates] forKey:@"coordinates"];
}

- (BOOL)isEqual:(id)other {
  if (self == other) return YES;
  if (![other isKindOfClass:[MLNPointCollection class]]) return NO;

  MLNPointCollection *otherCollection = (MLNPointCollection *)other;
  return ([super isEqual:other] &&
          ((![self geoJSONDictionary] && ![otherCollection geoJSONDictionary]) ||
           [[self geoJSONDictionary] isEqualToDictionary:[otherCollection geoJSONDictionary]]));
}

- (MLNCoordinateBounds)overlayBounds {
  if (!_bounds) {
    mln_lat_lng_bounds bounds = MLNLatLngBoundsEmpty();
    for (auto coordinate : _coordinates) {
      if (!MLNLocationCoordinate2DIsValid(coordinate)) {
        bounds = MLNLatLngBoundsEmpty();
        break;
      }
      MLNLatLngBoundsExtend(bounds, MLNLatLngFromLocationCoordinate2D(coordinate));
    }
    _bounds = bounds;
  }
  return MLNCoordinateBoundsFromLatLngBounds(*_bounds);
}

- (NSUInteger)pointCount {
  return _coordinates.size();
}

- (CLLocationCoordinate2D *)coordinates {
  return _coordinates.data();
}

- (CLLocationCoordinate2D)coordinate {
  MLNAssert([self pointCount] > 0, @"A multipoint must have coordinates");
  return _coordinates.at(0);
}

- (void)getCoordinates:(CLLocationCoordinate2D *)coords range:(NSRange)range {
  if (range.location + range.length > [self pointCount]) {
    [NSException
         raise:NSRangeException
        format:@"Invalid coordinate range %@ extends beyond current coordinate count of %ld",
               NSStringFromRange(range), (unsigned long)[self pointCount]];
  }

  std::copy(_coordinates.begin() + range.location, _coordinates.begin() + NSMaxRange(range),
            coords);
}

- (BOOL)intersectsOverlayBounds:(MLNCoordinateBounds)overlayBounds {
  return MLNCoordinateBoundsIntersectsCoordinateBounds(self.overlayBounds, overlayBounds);
}

- (id)geometryObject {
  NSMutableArray *coordinates = [[NSMutableArray alloc] initWithCapacity:self.pointCount];
  for (NSUInteger i = 0; i < self.pointCount; i++) {
    [coordinates addObject:@[ @(self.coordinates[i].longitude), @(self.coordinates[i].latitude) ]];
  }
  return @{@"type" : @"MultiPoint", @"coordinates" : coordinates};
}

- (NSDictionary *)geoJSONDictionary {
  NSMutableArray *coordinates = [[NSMutableArray alloc] initWithCapacity:self.pointCount];
  for (NSUInteger index = 0; index < self.pointCount; index++) {
    CLLocationCoordinate2D coordinate = self.coordinates[index];
    [coordinates addObject:@[ @(coordinate.longitude), @(coordinate.latitude) ]];
  }

  return @{@"type" : @"MultiPoint", @"coordinates" : coordinates};
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@: %p; count = %lu; bounds = %@>",
                                    NSStringFromClass([self class]), (void *)self,
                                    (unsigned long)[self pointCount],
                                    MLNStringFromCoordinateBounds(self.overlayBounds)];
}

@end

NS_ASSUME_NONNULL_END

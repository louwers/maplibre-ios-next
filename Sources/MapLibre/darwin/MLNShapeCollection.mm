// Based on platform/darwin/src/MLNShapeCollection.mm at ios-v7.0.0

#import "MLNShapeCollection.h"

#import "MLNFeature.h"
#import "MLNLoggingConfiguration_Private.h"
#import "MLNShape_Private.h"

@implementation MLNShapeCollection

+ (BOOL)supportsSecureCoding {
  return YES;
}

+ (instancetype)shapeCollectionWithShapes:(NSArray<MLNShape *> *)shapes {
  return [[self alloc] initWithShapes:shapes];
}

- (instancetype)initWithShapes:(NSArray<MLNShape *> *)shapes {
  MLNLogDebug(@"Initializing with %lu shapes.", (unsigned long)shapes.count);
  if (self = [super init]) {
    _shapes = shapes.copy;
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)decoder {
  MLNLogInfo(@"Initializing with coder.");
  if (self = [super initWithCoder:decoder]) {
    NSSet<Class> *shapeClasses =
        [NSSet setWithArray:@[ [NSDictionary class], [NSArray class], [MLNShape class] ]];
    _shapes = [decoder decodeObjectOfClasses:shapeClasses forKey:@"shapes"];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:_shapes forKey:@"shapes"];
}

- (BOOL)isEqual:(id)other {
  if (self == other) return YES;
  if (![other isKindOfClass:[MLNShapeCollection class]]) return NO;

  MLNShapeCollection *otherShapeCollection = other;
  return
      [super isEqual:otherShapeCollection] && [_shapes isEqualToArray:otherShapeCollection.shapes];
}

- (NSUInteger)hash {
  NSUInteger hash = [super hash];
  for (MLNShape *shape in _shapes) {
    hash += [shape hash];
  }
  return hash;
}

- (CLLocationCoordinate2D)coordinate {
  return _shapes.firstObject.coordinate;
}

- (NSDictionary *)geoJSONDictionary {
  return @{@"type" : @"GeometryCollection", @"geometries" : [self geometryCollection]};
}

- (NSArray *)geometryCollection {
  NSMutableArray *geometries = [[NSMutableArray alloc] initWithCapacity:self.shapes.count];
  for (id shape in self.shapes) {
    NSDictionary *geometry = [shape geoJSONDictionary];
    [geometries addObject:geometry];
  }
  return [geometries copy];
}

- (id)geometryObject {
  NSMutableArray *geometries = [[NSMutableArray alloc] initWithCapacity:self.shapes.count];
  for (MLNShape *shape in self.shapes) {
    [geometries addObject:[shape geometryObject]];
  }
  return @{@"type" : @"GeometryCollection", @"geometries" : geometries};
}

@end

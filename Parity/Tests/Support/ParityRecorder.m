#import "ParityRecorder.h"

#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>

@import MapLibre;

@implementation ParityRecorder {
  NSString *_suite;
  NSString *_test;
  NSUInteger _step;
}

+ (NSString *)outputDirectory {
  NSString *directory = NSProcessInfo.processInfo.environment[@"PARITY_OUT"];
  if (!directory.length) {
    directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"parity"];
  }
  [[NSFileManager defaultManager] createDirectoryAtPath:directory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
  return directory;
}

+ (void)writeData:(NSData *)data toFile:(NSString *)name {
  NSString *path = [[self outputDirectory] stringByAppendingPathComponent:name];
  [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
  [data writeToFile:path atomically:YES];
}

+ (void)writeJSON:(id)object toFile:(NSString *)name {
  NSData *data = [NSJSONSerialization dataWithJSONObject:[self normalize:object]
                                                 options:NSJSONWritingPrettyPrinted |
                                                         NSJSONWritingSortedKeys
                                                   error:nil];
  [self writeData:data toFile:name];
}

+ (instancetype)recorderForTest:(XCTestCase *)test {
  ParityRecorder *recorder = [[self alloc] init];
  recorder->_suite = NSStringFromClass([test class]);
  NSString *name = test.name;
  // "-[Suite testName]" -> "testName"
  NSRange space = [name rangeOfString:@" "];
  if (space.location != NSNotFound) {
    name = [[name substringFromIndex:space.location + 1] stringByTrimmingCharactersInSet:
                                                         [NSCharacterSet characterSetWithCharactersInString:@"]"]];
  }
  recorder->_test = name;
  return recorder;
}

static NSNumber *ParityNumber(double value) {
  if (isnan(value)) {
    return nil;
  }
  return @(value);
}

+ (id)normalize:(id)value {
  if (!value || value == [NSNull null]) {
    return [NSNull null];
  }
  if ([value isKindOfClass:[NSString class]]) {
    return value;
  }
  if ([value isKindOfClass:[NSNumber class]]) {
    double d = [value doubleValue];
    if (isnan(d)) {
      return @"NaN";
    }
    if (isinf(d)) {
      return d > 0 ? @"Infinity" : @"-Infinity";
    }
    return value;
  }
  if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSSet class]] ||
      [value isKindOfClass:[NSOrderedSet class]]) {
    NSMutableArray *array = [NSMutableArray array];
    for (id element in value) {
      [array addObject:[self normalize:element]];
    }
    if ([value isKindOfClass:[NSSet class]]) {
      [array sortUsingComparator:^NSComparisonResult(id a, id b) {
        return [[a description] compare:[b description]];
      }];
    }
    return array;
  }
  if ([value isKindOfClass:[NSDictionary class]]) {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    [value enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
      dictionary[[key description]] = [self normalize:object];
    }];
    return dictionary;
  }
  if ([value isKindOfClass:[UIColor class]]) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [(UIColor *)value getRed:&r green:&g blue:&b alpha:&a];
    return @{@"rgba" : @[ @(r), @(g), @(b), @(a) ]};
  }
  if ([value isKindOfClass:[NSExpression class]] || [value isKindOfClass:[NSPredicate class]]) {
    return @{@"description" : [value description]};
  }
  if ([value isKindOfClass:[NSError class]]) {
    NSError *error = value;
    return @{@"error" : @{@"domain" : error.domain, @"code" : @(error.code)}};
  }
  if ([value isKindOfClass:[NSException class]]) {
    NSException *exception = value;
    return @{@"exception" : @{@"name" : exception.name, @"reason" : exception.reason ?: @""}};
  }
  if ([value isKindOfClass:[NSURL class]]) {
    return [value absoluteString];
  }
  if ([value isKindOfClass:[NSData class]]) {
    return @{@"bytes" : @([value length])};
  }
  if ([value isKindOfClass:[NSValue class]]) {
    NSValue *boxed = value;
    const char *type = boxed.objCType;
    if (strcmp(type, @encode(CGPoint)) == 0) {
      CGPoint p = boxed.CGPointValue;
      return @{@"point" : @[ @(p.x), @(p.y) ]};
    }
    if (strcmp(type, @encode(CGSize)) == 0) {
      CGSize s = boxed.CGSizeValue;
      return @{@"size" : @[ @(s.width), @(s.height) ]};
    }
    if (strcmp(type, @encode(CGRect)) == 0) {
      CGRect r = boxed.CGRectValue;
      return @{@"rect" : @[ @(r.origin.x), @(r.origin.y), @(r.size.width), @(r.size.height) ]};
    }
    if (strcmp(type, @encode(CGVector)) == 0) {
      CGVector v = boxed.CGVectorValue;
      return @{@"vector" : @[ @(v.dx), @(v.dy) ]};
    }
    if (strcmp(type, @encode(UIEdgeInsets)) == 0) {
      UIEdgeInsets i = boxed.UIEdgeInsetsValue;
      return @{@"insets" : @[ @(i.top), @(i.left), @(i.bottom), @(i.right) ]};
    }
    if (strcmp(type, @encode(CLLocationCoordinate2D)) == 0) {
      CLLocationCoordinate2D c = boxed.MLNCoordinateValue;
      return @{@"coordinate" : @[ ParityNumber(c.latitude) ?: @"NaN", ParityNumber(c.longitude) ?: @"NaN" ]};
    }
    if (strcmp(type, @encode(MLNCoordinateBounds)) == 0) {
      MLNCoordinateBounds b = boxed.MLNCoordinateBoundsValue;
      return @{@"bounds" : @[ @(b.sw.latitude), @(b.sw.longitude), @(b.ne.latitude), @(b.ne.longitude) ]};
    }
    if (strcmp(type, @encode(MLNCoordinateSpan)) == 0) {
      MLNCoordinateSpan s = boxed.MLNCoordinateSpanValue;
      return @{@"span" : @[ @(s.latitudeDelta), @(s.longitudeDelta) ]};
    }
    if (strcmp(type, @encode(MLNTransition)) == 0) {
      MLNTransition t;
      [boxed getValue:&t];
      return @{@"transition" : @[ @(t.duration), @(t.delay) ]};
    }
    if (strcmp(type, @encode(MLNSphericalPosition)) == 0) {
      MLNSphericalPosition p;
      [boxed getValue:&p];
      return @{@"sphericalPosition" : @[ @(p.radial), @(p.azimuthal), @(p.polar) ]};
    }
    return @{@"value" : boxed.description, @"type" : @(type)};
  }
  if ([value isKindOfClass:[MLNMapCamera class]]) {
    MLNMapCamera *camera = value;
    return @{
      @"camera" : @{
        @"centerCoordinate" : [self normalize:[NSValue valueWithMLNCoordinate:camera.centerCoordinate]],
        @"altitude" : @(camera.altitude),
        @"heading" : @(camera.heading),
        @"pitch" : @(camera.pitch),
        @"viewingDistance" : @(camera.viewingDistance),
      }
    };
  }
  if ([value isKindOfClass:[MLNStyleLayer class]]) {
    MLNStyleLayer *layer = value;
    return @{@"layer" : @{@"class" : NSStringFromClass([layer class]), @"identifier" : layer.identifier}};
  }
  if ([value isKindOfClass:[MLNSource class]]) {
    MLNSource *source = value;
    return @{@"source" : @{@"class" : NSStringFromClass([source class]), @"identifier" : source.identifier}};
  }
  if ([value conformsToProtocol:@protocol(MLNFeature)]) {
    id<MLNFeature> feature = value;
    return @{
      @"feature" : @{
        @"class" : NSStringFromClass([(NSObject *)value class]),
        @"identifier" : [self normalize:feature.identifier],
        @"attributes" : [self normalize:feature.attributes],
        @"geoJSON" : [self normalize:feature.geoJSONDictionary],
      }
    };
  }
  if ([value isKindOfClass:[MLNShape class]]) {
    MLNShape *shape = value;
    NSData *data = [shape geoJSONDataUsingEncoding:NSUTF8StringEncoding];
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return @{@"shape" : @{@"class" : NSStringFromClass([shape class]), @"geoJSON" : [self normalize:json]}};
  }
  return @{@"object" : NSStringFromClass([value class]), @"description" : [value description] ?: @""};
}

- (void)record:(NSString *)key value:(id)value {
  NSDictionary *line = @{
    @"suite" : _suite,
    @"test" : _test,
    @"step" : @(_step++),
    @"key" : key,
    @"value" : [ParityRecorder normalize:value],
  };
  NSMutableData *data = [[NSJSONSerialization dataWithJSONObject:line
                                                         options:NSJSONWritingSortedKeys
                                                           error:nil] mutableCopy];
  [data appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
  NSString *path = [[ParityRecorder outputDirectory]
      stringByAppendingPathComponent:[NSString stringWithFormat:@"traces/%@.jsonl", _suite]];
  [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
  NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
  if (!handle) {
    [data writeToFile:path atomically:NO];
    return;
  }
  [handle seekToEndOfFile];
  [handle writeData:data];
  [handle closeFile];
}

- (void)record:(NSString *)key block:(id (^)(void))block {
  id value;
  @try {
    value = block();
  } @catch (NSException *exception) {
    value = exception;
  }
  [self record:key value:value];
}

@end

// Based on platform/darwin/src/MLNTilePyramidOfflineRegion.mm at ios-v7.0.0

#import "MLNTilePyramidOfflineRegion.h"

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#import <Cocoa/Cocoa.h>
#endif

#import "MLNGeometry_Private.h"
#import "MLNLoggingConfiguration_Private.h"
#import "MLNOfflineRegion_Private.h"
#import "MLNStyle.h"
#import "MLNTilePyramidOfflineRegion_Private.h"
#import "MLNFFI.h"

@interface MLNTilePyramidOfflineRegion () <MLNOfflineRegion_Private,
                                           MLNTilePyramidOfflineRegion_Private>

@end

@implementation MLNTilePyramidOfflineRegion {
  NSURL *_styleURL;
  // The UTF-8 style URL that mgl_offlineRegionDefinition points into.
  NSData *_definitionStyleURL;
}

@synthesize styleURL = _styleURL;
@synthesize includesIdeographicGlyphs = _includesIdeographicGlyphs;

- (NSDictionary *)offlineStartEventAttributes {
  return @{};
}

+ (BOOL)supportsSecureCoding {
  return YES;
}

- (instancetype)init {
  MLNLogInfo(@"Calling this initializer is not allowed.");
  [NSException raise:NSGenericException
              format:@"-[MLNTilePyramidOfflineRegion init] is unavailable. "
                     @"Use -initWithStyleURL:bounds:fromZoomLevel:toZoomLevel: instead."];
  return nil;
}

- (instancetype)initWithStyleURL:(NSURL *)styleURL
                          bounds:(MLNCoordinateBounds)bounds
                   fromZoomLevel:(double)minimumZoomLevel
                     toZoomLevel:(double)maximumZoomLevel {
  MLNLogDebug(@"Initializing styleURL: %@ bounds: %@ fromZoomLevel: %f toZoomLevel: %f", styleURL,
              MLNStringFromCoordinateBounds(bounds), minimumZoomLevel, maximumZoomLevel);
  if (self = [super init]) {
    if (!styleURL) {
      styleURL = [MLNStyle defaultStyleURL];
    }

    if (!styleURL.scheme) {
      [NSException raise:MLNInvalidStyleURLException
                  format:@"%@ does not support setting a relative file URL as the style URL. "
                         @"To download the online resources required by this style, "
                         @"specify a URL to an online copy of this style. "
                         @"For Mapbox-hosted styles, use the mapbox: scheme.",
                         NSStringFromClass([self class])];
    }

    _styleURL = styleURL;
    _bounds = bounds;
    _minimumZoomLevel = minimumZoomLevel;
    _maximumZoomLevel = maximumZoomLevel;
    _includesIdeographicGlyphs = NO;
  }
  return self;
}

- (instancetype)initWithOfflineRegionDefinition:
    (const mln_offline_tile_pyramid_region_definition *)definition {
  NSURL *styleURL = [NSURL URLWithString:MLNFFIStringFromBufferView(definition->style_url) ?: @""];
  MLNCoordinateBounds bounds = MLNCoordinateBoundsFromLatLngBounds(definition->bounds);
  MLNTilePyramidOfflineRegion *result = [self initWithStyleURL:styleURL
                                                        bounds:bounds
                                                 fromZoomLevel:definition->min_zoom
                                                   toZoomLevel:definition->max_zoom];
  result.includesIdeographicGlyphs = definition->include_ideographs;
  return result;
}

- (mln_offline_region_definition)mgl_offlineRegionDefinition {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  const float scaleFactor = [UIScreen instancesRespondToSelector:@selector(nativeScale)]
                                ? [[UIScreen mainScreen] nativeScale]
                                : [[UIScreen mainScreen] scale];
#elif TARGET_OS_MAC
  const float scaleFactor = [NSScreen mainScreen].backingScaleFactor;
#endif
  _definitionStyleURL = [_styleURL.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
  mln_offline_region_definition definition = {sizeof(mln_offline_region_definition)};
  definition.type = MLN_OFFLINE_REGION_DEFINITION_TILE_PYRAMID;
  mln_offline_tile_pyramid_region_definition &tilePyramid = definition.data.tile_pyramid;
  tilePyramid.style_url = {_definitionStyleURL.bytes, _definitionStyleURL.length};
  tilePyramid.bounds = MLNLatLngBoundsFromCoordinateBounds(_bounds);
  tilePyramid.min_zoom = _minimumZoomLevel;
  tilePyramid.max_zoom = _maximumZoomLevel;
  tilePyramid.pixel_ratio = scaleFactor;
  tilePyramid.include_ideographs = _includesIdeographicGlyphs;
  return definition;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
  MLNLogInfo(@"Initializing with coder.");
  NSURL *styleURL = [coder decodeObjectForKey:@"styleURL"];
  CLLocationCoordinate2D sw =
      CLLocationCoordinate2DMake([coder decodeDoubleForKey:@"southWestLatitude"],
                                 [coder decodeDoubleForKey:@"southWestLongitude"]);
  CLLocationCoordinate2D ne =
      CLLocationCoordinate2DMake([coder decodeDoubleForKey:@"northEastLatitude"],
                                 [coder decodeDoubleForKey:@"northEastLongitude"]);
  MLNCoordinateBounds bounds = MLNCoordinateBoundsMake(sw, ne);
  double minimumZoomLevel = [coder decodeDoubleForKey:@"minimumZoomLevel"];
  double maximumZoomLevel = [coder decodeDoubleForKey:@"maximumZoomLevel"];

  MLNTilePyramidOfflineRegion *result = [self initWithStyleURL:styleURL
                                                        bounds:bounds
                                                 fromZoomLevel:minimumZoomLevel
                                                   toZoomLevel:maximumZoomLevel];
  result.includesIdeographicGlyphs = [coder decodeBoolForKey:@"includesIdeographicGlyphs"];
  return result;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:_styleURL forKey:@"styleURL"];
  [coder encodeDouble:_bounds.sw.latitude forKey:@"southWestLatitude"];
  [coder encodeDouble:_bounds.sw.longitude forKey:@"southWestLongitude"];
  [coder encodeDouble:_bounds.ne.latitude forKey:@"northEastLatitude"];
  [coder encodeDouble:_bounds.ne.longitude forKey:@"northEastLongitude"];
  [coder encodeDouble:_maximumZoomLevel forKey:@"maximumZoomLevel"];
  [coder encodeDouble:_minimumZoomLevel forKey:@"minimumZoomLevel"];
  [coder encodeBool:_includesIdeographicGlyphs forKey:@"includesIdeographicGlyphs"];
}

- (id)copyWithZone:(nullable NSZone *)zone {
  MLNTilePyramidOfflineRegion *result =
      [[[self class] allocWithZone:zone] initWithStyleURL:_styleURL
                                                   bounds:_bounds
                                            fromZoomLevel:_minimumZoomLevel
                                              toZoomLevel:_maximumZoomLevel];
  result.includesIdeographicGlyphs = _includesIdeographicGlyphs;
  return result;
}

- (BOOL)isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  if (![other isKindOfClass:[self class]]) {
    return NO;
  }

  MLNTilePyramidOfflineRegion *otherRegion = other;
  return (_minimumZoomLevel == otherRegion->_minimumZoomLevel &&
          _maximumZoomLevel == otherRegion->_maximumZoomLevel &&
          MLNCoordinateBoundsEqualToCoordinateBounds(_bounds, otherRegion->_bounds) &&
          [_styleURL isEqual:otherRegion->_styleURL] &&
          _includesIdeographicGlyphs == otherRegion->_includesIdeographicGlyphs);
}

- (NSUInteger)hash {
  return (_styleURL.hash + @(_bounds.sw.latitude).hash + @(_bounds.sw.longitude).hash +
          @(_bounds.ne.latitude).hash + @(_bounds.ne.longitude).hash + @(_minimumZoomLevel).hash +
          @(_maximumZoomLevel).hash + @(_includesIdeographicGlyphs).hash);
}

@end

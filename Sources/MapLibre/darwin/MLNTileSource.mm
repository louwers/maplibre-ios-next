// Based on platform/darwin/src/MLNTileSource.mm at ios-v7.0.0

#import "MLNTileSource_Private.h"

#import "MLNAttributionInfo_Private.h"
#import "MLNGeometry_Private.h"
#import "MLNRasterDEMSource.h"
#import "MLNVectorTileSource.h"
#import "NSString+MLNAdditions.h"
#import "NSValue+MLNAdditions.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#import "MLNFFIMap+Style.h"
#import "MLNSource_Private.h"
#import "MLNStyle_Private.h"

const MLNTileSourceOption MLNTileSourceOptionMinimumZoomLevel =
    @"MLNTileSourceOptionMinimumZoomLevel";
const MLNTileSourceOption MLNTileSourceOptionMaximumZoomLevel =
    @"MLNTileSourceOptionMaximumZoomLevel";
const MLNTileSourceOption MLNTileSourceOptionCoordinateBounds =
    @"MLNTileSourceOptionCoordinateBounds";
const MLNTileSourceOption MLNTileSourceOptionAttributionHTMLString =
    @"MLNTileSourceOptionAttributionHTMLString";
const MLNTileSourceOption MLNTileSourceOptionAttributionInfos =
    @"MLNTileSourceOptionAttributionInfos";
const MLNTileSourceOption MLNTileSourceOptionTileCoordinateSystem =
    @"MLNTileSourceOptionTileCoordinateSystem";

@implementation MLNTileSource {
  // The style-spec source object of a pending source.
  NSDictionary *_sourceJSON;
}

- (instancetype)initWithPendingIdentifier:(NSString *)identifier sourceJSON:(NSDictionary *)json {
  if (self = [super initWithPendingIdentifier:identifier]) {
    _sourceJSON = [json copy];
  }
  return self;
}

- (NSDictionary *)mgl_sourceJSON {
  return _sourceJSON;
}

- (void)mgl_willDetachFromMap:(MLNFFIMap *)map {
  // A source of a loaded style has no configuration of its own; take the
  // style's so it can be added again.
  if (!_sourceJSON) {
    MLNFFISourceInfo *info = [map styleSourceWithIdentifier:self.identifier];
    if (info) {
      _sourceJSON = MLNTileSourceJSONFromSourceInfo(info);
    }
  }
}

- (MLNFFISourceInfo *)mgl_sourceInfo {
  MLNFFIMap *map = self.mgl_map;
  return map ? [map styleSourceWithIdentifier:self.identifier] : nil;
}

- (NSURL *)mgl_configurationURL {
  NSString *url;
  if (self.mgl_style) {
    url = self.mgl_sourceInfo.URL;
  } else {
    url = _sourceJSON[@"url"];
  }
  return url.length ? [NSURL URLWithString:url] : nil;
}

- (NSString *)mgl_attributionHTMLString {
  if (self.mgl_style) {
    MLNFFISourceInfo *info = self.mgl_sourceInfo;
    if (!(info.fields & MLN_STYLE_SOURCE_INFO_TILE_JSON)) {
      return nil;
    }
    return info.attribution ?: @"";
  }
  if (!_sourceJSON[@"tiles"]) {
    return nil;
  }
  return _sourceJSON[@"attribution"] ?: @"";
}

- (NSURL *)configurationURL {
  [NSException raise:MLNAbstractClassException format:@"MLNTileSource is an abstract class"];
  return nil;
}

- (NSArray<MLNAttributionInfo *> *)attributionInfos {
  return [self attributionInfosWithFontSize:0 linkColor:nil];
}

- (NSArray<MLNAttributionInfo *> *)attributionInfosWithFontSize:(CGFloat)fontSize
                                                      linkColor:(nullable MLNColor *)linkColor {
  return [MLNAttributionInfo attributionInfosFromHTMLString:self.attributionHTMLString
                                                   fontSize:fontSize
                                                  linkColor:linkColor];
}

- (NSString *)attributionHTMLString {
  [NSException raise:MLNAbstractClassException format:@"MLNTileSource is an abstract class"];
  return nil;
}

@end

NSMutableDictionary *MLNTileSourceJSONFromTileURLTemplates(
    NSArray<NSString *> *tileURLTemplates, NSDictionary<MLNTileSourceOption, id> *_Nullable options,
    NSString *sourceType) {
  NSMutableDictionary *tileSet = [NSMutableDictionary dictionary];

  tileSet[@"tiles"] = [tileURLTemplates copy];

  // set the minimum / maximum zoom range to the values specified by this class if they
  // were set. otherwise, use the core objects default values
  NSInteger minimumZoom = 0;
  NSInteger maximumZoom = 22;
  if (NSNumber *minimumZoomLevel = options[MLNTileSourceOptionMinimumZoomLevel]) {
    if (![minimumZoomLevel isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNTileSourceOptionMinimumZoomLevel must be set to an NSNumber."];
    }
    minimumZoom = (uint8_t)minimumZoomLevel.integerValue;
    tileSet[@"minzoom"] = @(minimumZoom);
  }
  if (NSNumber *maximumZoomLevel = options[MLNTileSourceOptionMaximumZoomLevel]) {
    if (![maximumZoomLevel isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNTileSourceOptionMinimumZoomLevel must be set to an NSNumber."];
    }
    maximumZoom = (uint8_t)maximumZoomLevel.integerValue;
    tileSet[@"maxzoom"] = @(maximumZoom);
  }
  if (minimumZoom > maximumZoom) {
    [NSException raise:NSInvalidArgumentException
                format:@"MLNTileSourceOptionMinimumZoomLevel must be less than "
                       @"MLNTileSourceOptionMaximumZoomLevel."];
  }

  if (NSValue *coordinateBounds = options[MLNTileSourceOptionCoordinateBounds]) {
    if (![coordinateBounds isKindOfClass:[NSValue class]] &&
        strcmp(coordinateBounds.objCType, @encode(MLNCoordinateBounds)) == 0) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNTileSourceOptionCoordinateBounds must be set to an NSValue "
                         @"containing an MLNCoordinateBounds."];
    }
    mln_lat_lng_bounds bounds =
        MLNLatLngBoundsFromCoordinateBounds(coordinateBounds.MLNCoordinateBoundsValue);
    tileSet[@"bounds"] = @[
      @(bounds.southwest.longitude), @(bounds.southwest.latitude), @(bounds.northeast.longitude),
      @(bounds.northeast.latitude)
    ];
  }

  if (NSString *attribution = options[MLNTileSourceOptionAttributionHTMLString]) {
    if (![attribution isKindOfClass:[NSString class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNTileSourceOptionAttributionHTMLString must be set to a string."];
    }
    tileSet[@"attribution"] = attribution;
  }

  if (NSArray *attributionInfos = options[MLNTileSourceOptionAttributionInfos]) {
    if (![attributionInfos isKindOfClass:[NSArray class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNTileSourceOptionAttributionInfos must be set to a string."];
    }

    NSAttributedString *attributedString =
        [MLNAttributionInfo attributedStringForAttributionInfos:attributionInfos];
#if TARGET_OS_IPHONE
    static NSString *const NSExcludedElementsDocumentAttribute = @"ExcludedElements";
#endif
    NSDictionary *documentAttributes = @{
      NSDocumentTypeDocumentAttribute : NSHTMLTextDocumentType,
      NSCharacterEncodingDocumentAttribute : @(NSUTF8StringEncoding),
      // The attribution string is meant to be a simple, inline fragment, not a full-fledged,
      // validating document.
      NSExcludedElementsDocumentAttribute :
          @[ @"XML", @"DOCTYPE", @"html", @"head", @"meta", @"title", @"style", @"body", @"p" ],
    };
    NSData *data = [attributedString dataFromRange:attributedString.mgl_wholeRange
                                documentAttributes:documentAttributes
                                             error:NULL];
    NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    tileSet[@"attribution"] = html ?: @"";
  }

  if (NSNumber *tileCoordinateSystemNumber = options[MLNTileSourceOptionTileCoordinateSystem]) {
    if (![tileCoordinateSystemNumber isKindOfClass:[NSValue class]]) {
      [NSException
           raise:NSInvalidArgumentException
          format:@"MLNTileSourceOptionTileCoordinateSystem must be set to an NSValue or NSNumber."];
    }
    MLNTileCoordinateSystem tileCoordinateSystem;
    [tileCoordinateSystemNumber getValue:&tileCoordinateSystem];
    switch (tileCoordinateSystem) {
      case MLNTileCoordinateSystemXYZ:
        tileSet[@"scheme"] = @"xyz";
        break;
      case MLNTileCoordinateSystemTMS:
        tileSet[@"scheme"] = @"tms";
        break;
    }
  }

  NSNumber *encodingNumber = options[MLNTileSourceOptionDEMEncoding];
  if (encodingNumber) {
    if (![encodingNumber isKindOfClass:[NSValue class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNTileSourceOptionDEMEncoding must be set to an NSValue or NSNumber."];
    }
    MLNDEMEncoding encoding;
    [encodingNumber getValue:&encoding];
    // Only raster-dem sources have this encoding; the core ignored it elsewhere.
    if ([sourceType isEqualToString:@"raster-dem"]) {
      switch (encoding) {
        case MLNDEMEncodingMapbox:
          tileSet[@"encoding"] = @"mapbox";
          break;
        case MLNDEMEncodingTerrarium:
          tileSet[@"encoding"] = @"terrarium";
          break;
      }
    }
  }

  encodingNumber = options[MLNVectorTileSourceOptionEncoding];
  if (encodingNumber) {
    if (![encodingNumber isKindOfClass:[NSValue class]]) {
      [NSException
           raise:NSInvalidArgumentException
          format:@"MLNTileSourceOptionVectorEncoding must be set to an NSValue or NSNumber."];
    }
    MLNVectorTileSourceEncoding encoding;
    [encodingNumber getValue:&encoding];
    // Only vector sources have this encoding; the core ignored it elsewhere.
    if ([sourceType isEqualToString:@"vector"]) {
      switch (encoding) {
        case MLNVectorTileSourceEncodingMapbox:
          tileSet[@"encoding"] = @"mvt";
          break;
        case MLNVectorTileSourceEncodingMLT:
          tileSet[@"encoding"] = @"mlt";
          break;
      }
    }
  }

  return tileSet;
}

NSDictionary *MLNTileSourceJSONFromSourceInfo(MLNFFISourceInfo *info) {
  NSMutableDictionary *json = [NSMutableDictionary dictionary];
  switch (info.type) {
    case MLN_STYLE_SOURCE_TYPE_VECTOR:
      json[@"type"] = @"vector";
      if (info.fields & MLN_STYLE_SOURCE_INFO_VECTOR_ENCODING) {
        json[@"encoding"] = info.vectorEncoding == MLN_STYLE_VECTOR_TILE_ENCODING_MLT ? @"mlt" : @"mvt";
      }
      break;
    case MLN_STYLE_SOURCE_TYPE_RASTER:
      json[@"type"] = @"raster";
      break;
    case MLN_STYLE_SOURCE_TYPE_RASTER_DEM:
      json[@"type"] = @"raster-dem";
      if (info.fields & MLN_STYLE_SOURCE_INFO_RASTER_ENCODING) {
        json[@"encoding"] =
            info.rasterEncoding == MLN_STYLE_RASTER_DEM_ENCODING_TERRARIUM ? @"terrarium" : @"mapbox";
      }
      break;
    default:
      return @{};
  }
  if (info.URL.length) {
    json[@"url"] = info.URL;
  } else if (info.fields & MLN_STYLE_SOURCE_INFO_TILE_JSON) {
    json[@"tiles"] = info.tileURLs;
    json[@"minzoom"] = @(info.minimumZoom);
    json[@"maxzoom"] = @(info.maximumZoom);
    json[@"scheme"] = info.scheme == MLN_STYLE_TILE_SCHEME_TMS ? @"tms" : @"xyz";
    if (info.attribution.length) {
      json[@"attribution"] = info.attribution;
    }
    if (info.fields & MLN_STYLE_SOURCE_INFO_BOUNDS) {
      json[@"bounds"] = @[
        @(info.bounds.southwest.longitude), @(info.bounds.southwest.latitude),
        @(info.bounds.northeast.longitude), @(info.bounds.northeast.latitude)
      ];
    }
  }
  if ((info.fields & MLN_STYLE_SOURCE_INFO_TILE_SIZE) && info.type != MLN_STYLE_SOURCE_TYPE_VECTOR) {
    json[@"tileSize"] = @(info.tileSize);
  }
  return json;
}

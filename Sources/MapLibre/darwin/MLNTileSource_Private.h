// Based on platform/darwin/src/MLNTileSource_Private.h at ios-v7.0.0

#import <CoreGraphics/CoreGraphics.h>

#import "MLNFoundation.h"
#import "MLNTileSource.h"

NS_ASSUME_NONNULL_BEGIN

@class MLNAttributionInfo;
@class MLNFFISourceInfo;

@interface MLNTileSource (Private)

/**
 An HTML string to be displayed as attribution when the map is shown to a user.

 The default value is `nil`. If the source is initialized with a configuration
 URL, this property is also `nil` until the configuration JSON file is loaded.
 */
@property (nonatomic, copy, nullable, readonly) NSString *attributionHTMLString;

/**
 A structured representation of the `attribution` property. The default value is
 `nil`.

 @param fontSize The default text size in points, or 0 to use the default.
 @param linkColor The default link color, or `nil` to use the default.
 */
- (NSArray<MLNAttributionInfo *> *)attributionInfosWithFontSize:(CGFloat)fontSize
                                                      linkColor:(nullable MLNColor *)linkColor;

/**
 Initializes a pending tile source with its style-spec source object. Classic
 created a core source from a URL or an mln::Tileset here.
 */
- (instancetype)initWithPendingIdentifier:(NSString *)identifier sourceJSON:(NSDictionary *)json;

/// The source as the style reports it while attached, else nil.
@property (nonatomic, readonly, nullable) MLNFFISourceInfo *mgl_sourceInfo;

/// The configuration URL the source was created with, as getURL() reported it.
@property (nonatomic, readonly, nullable) NSURL *mgl_configurationURL;

/// The tile set attribution, as getAttribution() reported it: nil until a tile
/// set exists (a configuration URL loads it), empty if it has none.
@property (nonatomic, readonly, nullable) NSString *mgl_attributionHTMLString;

@end

/**
 The tile set part of a style-spec source object for tile URL templates and
 options, as MLNTileSetFromTileURLTemplates() built an mln::Tileset: `tiles`,
 `minzoom`, `maxzoom`, `bounds`, `attribution`, `scheme` and `encoding`.
 `sourceType` is "vector", "raster" or "raster-dem" and selects which encoding
 option applies.
 */
MLN_EXPORT
NSMutableDictionary *MLNTileSourceJSONFromTileURLTemplates(
    NSArray<NSString *> *tileURLTemplates, NSDictionary<MLNTileSourceOption, id> *_Nullable options,
    NSString *sourceType);

/**
 A style-spec source object that recreates a tile source the C API describes,
 for adding a source of a loaded style again after it was removed.
 */
MLN_EXPORT
NSDictionary *MLNTileSourceJSONFromSourceInfo(MLNFFISourceInfo *info);

NS_ASSUME_NONNULL_END

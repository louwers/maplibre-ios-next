// Blocking style operations on a map, with results converted to Foundation
// types. Each returns the C API status; failures also carry its diagnostic.

#import "MLNFFI.h"

NS_ASSUME_NONNULL_BEGIN

/// One `mln_style_layer_info`.
@interface MLNFFILayerInfo : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *sourceIdentifier;
@property (nonatomic, copy) NSString *sourceLayerIdentifier;
@property (nonatomic) double minimumZoom;
@property (nonatomic) double maximumZoom;
@property (nonatomic) BOOL visible;
@end

/// One `mln_style_source_info`.
@interface MLNFFISourceInfo : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) mln_style_source_type type;
@property (nonatomic) mln_style_source_info_fields fields;
@property (nonatomic) BOOL isVolatile;
@property (nonatomic, copy, nullable) NSString *attribution;
@property (nonatomic, copy, nullable) NSString *URL;
@property (nonatomic, copy) NSArray<NSString *> *tileURLs;
@property (nonatomic) double minimumZoom;
@property (nonatomic) double maximumZoom;
@property (nonatomic) mln_style_tile_scheme scheme;
@property (nonatomic) mln_lat_lng_bounds bounds;
@property (nonatomic) uint32_t tileSize;
@property (nonatomic) mln_style_vector_tile_encoding vectorEncoding;
@property (nonatomic) mln_style_raster_dem_encoding rasterEncoding;
@end

/// One style image, as `mln_style_image_info` describes it.
@interface MLNFFIStyleImage : NSObject
@property (nonatomic) uint32_t width;
@property (nonatomic) uint32_t height;
/// Premultiplied RGBA8, tightly packed.
@property (nonatomic, copy) NSData *pixels;
@property (nonatomic) float pixelRatio;
@property (nonatomic) BOOL sdf;
@property (nonatomic, copy) NSArray<NSValue *> *stretchX;
@property (nonatomic, copy) NSArray<NSValue *> *stretchY;
@property (nonatomic) BOOL hasContent;
@property (nonatomic) mln_image_content content;
@end

typedef NSString *_Nullable MLNFFIMessage;

@interface MLNFFIMap (Style)

- (mln_status)loadStyleURL:(NSString *)URL message:(NSString *_Nullable *_Nullable)message;
- (mln_status)loadStyleJSON:(NSString *)JSON message:(NSString *_Nullable *_Nullable)message;
/// The style document as loaded, without later edits.
- (nullable NSString *)loadedStyleJSON;
- (nullable NSString *)styleURL;

- (nullable NSArray<MLNFFILayerInfo *> *)styleLayers;
- (nullable MLNFFILayerInfo *)styleLayerWithIdentifier:(NSString *)identifier;
/// The layer as a style-spec JSON object, or nil if it does not exist.
- (nullable NSDictionary *)styleLayerJSON:(NSString *)identifier;
- (mln_status)addStyleLayerJSON:(NSDictionary *)layer
                    belowLayer:(nullable NSString *)before
                       message:(NSString *_Nullable *_Nullable)message;
- (mln_status)removeStyleLayer:(NSString *)identifier message:(NSString *_Nullable *_Nullable)message;
- (mln_status)moveStyleLayer:(NSString *)identifier
                  belowLayer:(nullable NSString *)before
                     message:(NSString *_Nullable *_Nullable)message;
/// `value` is a JSON object; NSNull resets the property.
- (mln_status)setStyleLayerProperty:(NSString *)name
                              layer:(NSString *)identifier
                              value:(id)value
                            message:(NSString *_Nullable *_Nullable)message;
/// The property's JSON value; nil when undefined. `status` receives the status.
- (nullable id)styleLayerProperty:(NSString *)name
                            layer:(NSString *)identifier
                           status:(mln_status *_Nullable)status;

- (nullable NSArray<MLNFFISourceInfo *> *)styleSources;
- (nullable MLNFFISourceInfo *)styleSourceWithIdentifier:(NSString *)identifier;
- (mln_status)addStyleSourceJSON:(NSDictionary *)source
                      identifier:(NSString *)identifier
                         message:(NSString *_Nullable *_Nullable)message;
- (mln_status)removeStyleSource:(NSString *)identifier message:(NSString *_Nullable *_Nullable)message;

- (mln_status)setStyleImage:(NSString *)name
                     pixels:(NSData *)pixels
                      width:(uint32_t)width
                     height:(uint32_t)height
                    options:(const mln_style_image_options *)options
                    message:(NSString *_Nullable *_Nullable)message;
- (mln_status)removeStyleImage:(NSString *)name message:(NSString *_Nullable *_Nullable)message;
- (nullable MLNFFIStyleImage *)styleImageNamed:(NSString *)name;

- (mln_status)setStyleLightProperty:(NSString *)name
                              value:(id)value
                            message:(NSString *_Nullable *_Nullable)message;
- (nullable id)styleLightProperty:(NSString *)name;
- (mln_status)setStyleLightJSON:(NSDictionary *)light message:(NSString *_Nullable *_Nullable)message;

- (mln_style_transition_options)styleTransitionOptions;
- (mln_status)setStyleTransitionOptions:(mln_style_transition_options)options
                                message:(NSString *_Nullable *_Nullable)message;

- (nullable NSDictionary *)globalState;
- (mln_status)setGlobalStateProperty:(NSString *)name
                               value:(id)value
                             message:(NSString *_Nullable *_Nullable)message;

@end

NS_ASSUME_NONNULL_END

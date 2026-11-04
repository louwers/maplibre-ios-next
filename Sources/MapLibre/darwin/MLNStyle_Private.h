// Based on platform/darwin/src/MLNStyle_Private.h at ios-v7.0.0

#import "MLNStyle.h"

#import "MLNFillStyleLayer.h"
#import "MLNStyleLayer.h"

NS_ASSUME_NONNULL_BEGIN

@class MLNAttributionInfo;
@class MLNMapView;
@class MLNCustomStyleLayer;
@class MLNVectorTileSource;
@class MLNVectorStyleLayer;
@class MLNFFIMap;
@class MLNSource;

/// Layers and sources with this identifier prefix belong to the SDK itself
/// (annotations) and are hidden from the style's public lists.
FOUNDATION_EXTERN NSString *const MLNInternalStyleIdentifierPrefix;

/// What the style's owner (MLNMapView, MLNMapSnapshotter) provides to style
/// objects beyond the public MLNStylable protocol.
@protocol MLNFFIStylable <MLNStylable>
/// The render session that answers queries, or MLN_HANDLE_NULL.
@property (nonatomic, readonly) uint64_t mgl_renderSession;
/// Asks for a new frame after a change the map does not notice by itself.
- (void)mgl_setNeedsRerender;
@end

@interface MLNStyle (Private)

- (instancetype)initWithMap:(MLNFFIMap *)map stylable:(id<MLNStylable>)stylable;

@property (nonatomic, readonly, weak) id<MLNStylable> stylable;

/// The map whose style this is; nil once the style was replaced.
@property (nonatomic, readonly, nullable) MLNFFIMap *mgl_map;

- (nullable NSArray<MLNAttributionInfo *> *)attributionInfosWithFontSize:(CGFloat)fontSize
                                                               linkColor:
                                                                   (nullable MLNColor *)linkColor;
@property (nonatomic, readonly, strong)
    NSMutableDictionary<NSString *, MLNCustomStyleLayer *> *customLayers;
- (void)setStyleClasses:(NSArray<NSString *> *)appliedClasses
     transitionDuration:(NSTimeInterval)transitionDuration;

/// Invalidates every layer and source object of this style; called when the
/// map loads another style.
- (void)mgl_invalidate;

// Object identity, as classic kept it in the core objects' `peer`.
- (void)mgl_registerLayer:(MLNStyleLayer *)layer;
- (void)mgl_unregisterLayer:(MLNStyleLayer *)layer;
- (nullable MLNStyleLayer *)mgl_registeredLayerWithIdentifier:(NSString *)identifier;
- (void)mgl_registerSource:(MLNSource *)source;
- (void)mgl_unregisterSource:(MLNSource *)source;
- (nullable MLNSource *)mgl_registeredSourceWithIdentifier:(NSString *)identifier;

/// The layer to insert new top layers below: the lowest of the SDK's own
/// layers (annotations), which stay above the style's layers as the core's
/// annotation layers did. nil if there is none.
- (nullable NSString *)mgl_topInsertionLayerIdentifier;

/// Keeps a layer whose source is not in the style yet, and adds it when the
/// source is added. Classic's core accepted such layers; the C API does not.
- (void)mgl_deferLayer:(MLNStyleLayer *)layer
                  json:(NSDictionary *)json
            belowLayer:(nullable NSString *)before;
- (void)mgl_addDeferredLayersForSource:(NSString *)sourceIdentifier;

@end

@interface MLNStyle (MLNStreetsAdditions)

@property (nonatomic, readonly, copy) NSArray<MLNVectorStyleLayer *> *placeStyleLayers;
@property (nonatomic, readonly, copy) NSArray<MLNVectorStyleLayer *> *roadStyleLayers;

@end

NS_ASSUME_NONNULL_END

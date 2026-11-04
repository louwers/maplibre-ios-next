// Based on platform/darwin/src/MLNSource_Private.h at ios-v7.0.0
//
// Classic sources wrapped an mbgl::style::Source, owned by the source object
// until it was added to a style ("pending"). Here a pending source keeps its
// configuration in Objective-C and is serialized when it is added; an added
// source reads and writes its style's map through the C API.

#import "MLNSource.h"

#import "MLNFFIMap+Style.h"

NS_ASSUME_NONNULL_BEGIN

@protocol MLNStylable;
@class MLNStyle;

/**
 Assert that the style source is valid.

 This macro should be used at the beginning of any public-facing instance method
 of ``MLNSource`` and its subclasses. For private methods, an assertion is more appropriate.
 */
#define MLNAssertStyleSourceIsValid()                                            \
  do {                                                                           \
    if (!self.mgl_isValid) {                                                     \
      [NSException raise:MLNInvalidStyleSourceException                          \
                  format:@"This source got invalidated after the style change"]; \
    }                                                                            \
  } while (NO);

@class MLNMapView;

@interface MLNSource (Private)

/**
 Initializes a source object for a source that already exists in the style.
 */
- (instancetype)initWithIdentifier:(NSString *)identifier style:(MLNStyle *)style;

/// Whether the source was created by a concrete subclass (or came from a
/// style), so it can be added to a style. Classic checked for a core source.
@property (nonatomic, readonly) BOOL mgl_isConcrete;

/// NO once the style that held the source was replaced.
@property (nonatomic, readonly) BOOL mgl_isValid;

/**
 The stylable object whose style currently contains the source.

 If the source is not currently part of any stylable object’s style, this
 property is set to `nil`.
 */
@property (nonatomic, readonly, weak) id<MLNStylable> stylable;

/// The style that contains the source, or nil while pending.
@property (nonatomic, readonly, weak, nullable) MLNStyle *mgl_style;

/// The map of the style that contains the source, or nil while pending.
@property (nonatomic, readonly, nullable) MLNFFIMap *mgl_map;

/**
 Adds the pending source to the map. Subclasses override this to create
 themselves with the C API; the default adds `-mgl_sourceJSON`.
 */
- (mln_status)mgl_addToMap:(MLNFFIMap *)map message:(NSString *_Nullable *_Nullable)message;

/// The style-spec source object for a pending source. Subclasses override.
- (nullable NSDictionary *)mgl_sourceJSON;

/// Called after the source was added to a map, and after it was removed.
- (void)mgl_didAttachToMap:(nullable MLNFFIMap *)map;

/**
 Adds the source that this object represents to the stylable's style.

 Raises MLNRedundantSourceException if it was added already, and
 MLNRedundantSourceIdentifierException if the style has a source with its
 identifier.
 */
- (void)addToStylable:(id<MLNStylable>)stylable;

/**
 Removes the source from the stylable's style; it becomes pending again and
 can be added back.
 */
- (BOOL)removeFromStylable:(id<MLNStylable>)mapView error:(NSError *__nullable *__nullable)outError;

/// Called when the style that holds the source goes away.
- (void)mgl_invalidate;

/**
 Sets the state of a feature in this source. Shared implementation backing the
 public feature state methods exposed by ``MLNShapeSource`` and
 ``MLNVectorTileSource``.
 */
- (BOOL)mgl_setFeatureStateForSourceLayerID:(nullable NSString *)sourceLayerID
                                  featureID:(NSString *)featureID
                                      state:(NSDictionary<NSString *, id> *)state;

/**
 Gets the current state of a feature in this source. Shared implementation
 backing the public feature state methods exposed by ``MLNShapeSource`` and
 ``MLNVectorTileSource``.
 */
- (nullable NSDictionary<NSString *, id> *)mgl_featureStateForSourceLayerID:
                                               (nullable NSString *)sourceLayerID
                                                                  featureID:(NSString *)featureID;

/**
 Removes state from features in this source. Shared implementation backing the
 public feature state methods exposed by ``MLNShapeSource`` and
 ``MLNVectorTileSource``.
 */
- (BOOL)mgl_removeFeatureStateForSourceLayerID:(nullable NSString *)sourceLayerID
                                     featureID:(nullable NSString *)featureID
                                      stateKey:(nullable NSString *)stateKey;

@end

NS_ASSUME_NONNULL_END

// Based on platform/darwin/src/MLNStyleLayer_Private.h at ios-v7.0.0
//
// Classic layers wrapped an mbgl::style::Layer, owned by the layer object
// until it was added to a style ("pending") and by the style afterwards. Here
// a layer lives in a C API map either way: a pending layer in the hidden
// scratch map under an internal identifier, an added layer in its style's map.
// That way every property value is validated and normalized by the core, as it
// was when classic layers held a core layer.

#import <Foundation/Foundation.h>

#import "MLNFFIMap+Style.h"
#import "MLNStyleLayer.h"
#import "MLNStyleValue_Private.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Assert that the style layer is valid.

 This macro should be used at the beginning of any public-facing instance method
 of ``MLNStyleLayer`` and its subclasses. For private methods, an assertion is more appropriate.
 */
#define MLNAssertStyleLayerIsValid()                                                           \
  do {                                                                                         \
    if (!self.mgl_map) {                                                                       \
      [NSException raise:MLNInvalidStyleLayerException                                         \
                  format:@"Either this layer got invalidated after the style change or "       \
                         @"-[MLNStyle removeLayer:] has been called with this instance but "   \
                         @"another style layer instance was added with the same identifer. "   \
                         @"It is an error to send any message to this layer since  it cannot " \
                         @"be recovered after removal due to the identifier collision. "       \
                         @"Use unique identifiers for all layer instances including layers "   \
                         @"of different types."];                                              \
    }                                                                                          \
  } while (NO);

@class MLNStyle;

@interface MLNStyleLayer (Private)

/**
 Initializes a pending layer of the given style-spec type, which is not part of
 any style yet.
 */
- (instancetype)initWithIdentifier:(NSString *)identifier
                         layerType:(NSString *)layerType
                  sourceIdentifier:(nullable NSString *)sourceIdentifier;

/**
 Initializes a layer object for a layer that already exists in the style.
 */
- (instancetype)initWithIdentifier:(NSString *)identifier style:(MLNStyle *)style;

@property (nonatomic, readwrite, copy) NSString *identifier;

/// The map that holds the layer now (the scratch map while pending), or nil if
/// the layer is no longer valid.
@property (nonatomic, readonly, nullable) MLNFFIMap *mgl_map;

/// The identifier of the layer in `mgl_map`.
@property (nonatomic, readonly) NSString *mgl_mapLayerIdentifier;

@property (nonatomic, readonly, getter=mgl_isPending) BOOL mgl_pending;

/// The style that contains the layer, if any.
@property (nonatomic, readonly, weak, nullable) MLNStyle *mgl_style;

/**
 Adds the layer to the style below `otherLayer`. Raises if the layer was
 already added.
 */
- (void)addToStyle:(MLNStyle *)style belowLayer:(nullable MLNStyleLayer *)otherLayer;

/**
 Removes the layer from the style; it becomes pending again and can be added
 back.
 */
- (void)removeFromStyle:(MLNStyle *)style;

/// Called when the style that holds the layer goes away.
- (void)mgl_invalidate;

// Property access for the generated subclasses.

- (void)mgl_setExpression:(nullable NSExpression *)expression
              forProperty:(const MLNStylePropertyDescriptor *)descriptor;
- (nullable NSExpression *)mgl_expressionForProperty:(const MLNStylePropertyDescriptor *)descriptor;
- (void)mgl_setTransition:(MLNTransition)transition
              forProperty:(const MLNStylePropertyDescriptor *)descriptor;
- (MLNTransition)mgl_transitionForProperty:(const MLNStylePropertyDescriptor *)descriptor;

/// Sets a property by style-spec name to a JSON value; raises
/// NSInvalidArgumentException with `errorFormat` if the core rejects it.
- (void)mgl_setJSON:(id)json forProperty:(NSString *)name errorFormat:(NSString *)errorFormat;
- (nullable id)mgl_JSONForProperty:(NSString *)name;

/// The layer's identity and placement as the style reports it.
- (nullable MLNFFILayerInfo *)mgl_layerInfo;

@property (nonatomic, readonly, nullable) NSString *mgl_sourceIdentifier;
@property (nonatomic, nullable) NSString *mgl_sourceLayerIdentifier;
@property (nonatomic, nullable) NSPredicate *mgl_predicate;

@end

/// The layer's JSON with values the core serializes but does not parse back
/// (constant formatted text and images) rewritten, so it can be added to a map.
FOUNDATION_EXTERN NSDictionary *MLNReparsableLayerJSON(NSDictionary *layer);

/// The class that represents layers of the given style-spec type.
FOUNDATION_EXTERN Class MLNStyleLayerClassForType(NSString *type);

NS_ASSUME_NONNULL_END

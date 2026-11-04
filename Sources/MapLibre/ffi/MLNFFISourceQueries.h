// Source feature and feature extension queries for MLNShapeSource and
// MLNVectorTileSource. The C API answers them on the map view's render
// session, where classic asked the map view's mbgl::Renderer.

#import <Foundation/Foundation.h>

#import "MLNFeature.h"
#import "MLNSource.h"

NS_ASSUME_NONNULL_BEGIN

/**
 The features of the source's loaded tiles, as Renderer::querySourceFeatures
 returned them. Returns an empty array if the source is not on a map view with
 a render session. Raises NSInvalidArgumentException for an invalid predicate.
 */
FOUNDATION_EXTERN NSArray<id<MLNFeature>> *MLNFFIQuerySourceFeatures(
    MLNSource *source, NSSet<NSString *> *_Nullable sourceLayerIdentifiers,
    NSPredicate *_Nullable predicate);

/**
 The JSON result of a feature extension query (supercluster), as
 Renderer::queryFeatureExtensions returned it, or nil if the source is not on a
 map view with a render session or the query fails.
 */
FOUNDATION_EXTERN id _Nullable MLNFFIQueryFeatureExtension(MLNSource *source, NSDictionary *feature,
                                                           NSString *extension,
                                                           NSString *extensionField,
                                                           NSDictionary *_Nullable arguments);

NS_ASSUME_NONNULL_END

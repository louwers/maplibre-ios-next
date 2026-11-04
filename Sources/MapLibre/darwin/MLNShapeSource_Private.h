// Based on platform/darwin/src/MLNShapeSource_Private.h at ios-v7.0.0

#import "MLNFoundation.h"
#import "MLNShapeSource.h"

#import <MaplibreNativeC/maplibre_native_c.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The C API options for a GeoJSON source, with the storage that their buffer
 views borrow. Classic converted the options to mln::style::GeoJSONOptions.
 */
@interface MLNGeoJSONSourceOptions : NSObject

/// Valid while the receiver lives.
@property (nonatomic, readonly) mln_geo_json_source_options options;

/// Whether the options cluster point features.
@property (nonatomic, readonly) BOOL clusters;

@end

MLN_EXPORT
MLNGeoJSONSourceOptions *MLNGeoJSONOptionsFromDictionary(
    NSDictionary<MLNShapeSourceOption, id> *_Nullable options);

@interface MLNShapeSource (Private)

/**
 :nodoc:
 Debug log showing structure of an ``MLNFeature``. This method recurses in the case
 that the feature conforms to ``MLNCluster``. This method is used for testing and
 should be considered experimental, likely to be removed or changed in future
 releases.

 @param feature An object that conforms to the ``MLNFeature`` protocol.
 @param indent Used during recursion. Specify 0.
 */
- (void)debugRecursiveLogForFeature:(id<MLNFeature>)feature indent:(NSUInteger)indent;

@end

NS_ASSUME_NONNULL_END

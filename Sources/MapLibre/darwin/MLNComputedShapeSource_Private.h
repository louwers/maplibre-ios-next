// Based on platform/darwin/src/MLNComputedShapeSource_Private.h at ios-v7.0.0

#import "MLNComputedShapeSource.h"
#import "MLNFoundation.h"
#import "MLNTypes.h"

#import <MaplibreNativeC/maplibre_native_c.h>

NS_ASSUME_NONNULL_BEGIN

/// The C API options for the computed shape source options, without the
/// callbacks. Classic built mln::style::CustomGeometrySource::Options.
MLN_EXPORT
mln_custom_geometry_source_options MLNCustomGeometrySourceOptionsFromDictionary(
    NSDictionary<MLNShapeSourceOption, id> *_Nullable options);

NS_ASSUME_NONNULL_END

#import "MLNFFISourceQueries.h"

#import "MLNFFI.h"
#import "MLNGeoJSON.h"
#import "MLNLoggingConfiguration_Private.h"
#import "MLNMapView.h"
#import "MLNSource_Private.h"
#import "MLNStyle_Private.h"
#import "NSPredicate+MLNAdditions.h"

#include <vector>

static mln_render_session MLNFFIRenderSessionForSource(MLNSource *source) {
  id stylable = source.stylable;
  if (![stylable isKindOfClass:[MLNMapView class]] ||
      ![stylable respondsToSelector:@selector(mgl_renderSession)]) {
    return MLN_HANDLE_NULL;
  }
  return [(id<MLNFFIStylable>)stylable mgl_renderSession];
}

NSArray<id<MLNFeature>> *MLNFFIQuerySourceFeatures(MLNSource *source,
                                                   NSSet<NSString *> *sourceLayerIdentifiers,
                                                   NSPredicate *predicate) {
  MLNFFIMap *map = source.mgl_map;
  mln_render_session session = MLNFFIRenderSessionForSource(source);
  if (!map || session == MLN_HANDLE_NULL) {
    return @[];
  }

  NSString *filter = predicate ? MLNFFIJSONStringFromObject(predicate.mgl_jsonExpressionObject) : nil;
  NSArray<NSString *> *layerIdentifiers = sourceLayerIdentifiers.allObjects;
  NSString *identifier = source.identifier;
  NSMutableArray<NSDictionary *> *features = [NSMutableArray array];
  NSString *message;
  mln_status status = [map call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    std::vector<mln_buffer_view> layers;
    for (NSString *layer in layerIdentifiers) {
      layers.push_back(MLNFFIBufferView(layer));
    }
    mln_source_feature_query_options options = {sizeof(mln_source_feature_query_options)};
    if (layerIdentifiers) {
      options.fields = MLN_SOURCE_FEATURE_QUERY_OPTION_SOURCE_LAYER_IDS;
      options.source_layer_ids = layers.data();
      options.source_layer_id_count = layers.size();
    }
    options.filter = MLNFFIBufferView(filter);
    return mln_render_session_query_source_features(session, MLNFFIBufferView(identifier), &options,
                                                    completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        for (size_t i = 0; i < result->value_count; i++) {
          const mln_source_feature *feature =
              MLN_STRIDED_AT(mln_source_feature, result->value, result->value_size, i);
          id json = MLNFFIJSONObjectFromBufferView(feature->feature);
          if ([json isKindOfClass:[NSDictionary class]]) {
            [features addObject:json];
          }
        }
      }
      message:&message];

  if (status == MLN_STATUS_INVALID_ARGUMENT && filter) {
    [NSException raise:NSInvalidArgumentException format:@"Invalid filter value: %@", message];
  }
  if (status != MLN_STATUS_OK) {
    MLNLogError(@"Failed to query the features of source %@: %@", identifier, message);
    return @[];
  }
  return MLNFeaturesFromGeoJSONFeatures(features);
}

id MLNFFIQueryFeatureExtension(MLNSource *source, NSDictionary *feature, NSString *extension,
                               NSString *extensionField, NSDictionary *arguments) {
  MLNFFIMap *map = source.mgl_map;
  mln_render_session session = MLNFFIRenderSessionForSource(source);
  if (!map || session == MLN_HANDLE_NULL) {
    return nil;
  }

  NSString *featureJSON = MLNFFIJSONStringFromObject(feature);
  NSString *argumentsJSON = arguments.count ? MLNFFIJSONStringFromObject(arguments) : nil;
  NSString *identifier = source.identifier;
  __block id value;
  NSString *message;
  mln_status status = [map call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_render_session_query_feature_extensions(
        session, MLNFFIBufferView(identifier), MLNFFIBufferView(featureJSON),
        MLNFFIBufferView(extension), MLNFFIBufferView(extensionField),
        MLNFFIBufferView(argumentsJSON), completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        if (result->value) {
          value = MLNFFIJSONObjectFromBufferView(*(const mln_buffer_view *)result->value);
        }
      }
      message:&message];
  if (status != MLN_STATUS_OK) {
    MLNLogError(@"Failed to query %@ of a cluster in source %@: %@", extensionField, identifier,
                message);
    return nil;
  }
  return value;
}

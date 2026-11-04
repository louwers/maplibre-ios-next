#import "MLNFFIMap+Style.h"

@implementation MLNFFILayerInfo
@end

@implementation MLNFFISourceInfo
@end

@implementation MLNFFIStyleImage
@end

static MLNFFILayerInfo *MLNFFILayerInfoFromC(const mln_style_layer_info *info) {
  MLNFFILayerInfo *layer = [MLNFFILayerInfo new];
  layer.identifier = MLNFFIStringFromBufferView(info->id) ?: @"";
  layer.type = MLNFFIStringFromBufferView(info->type) ?: @"";
  layer.sourceIdentifier = MLNFFIStringFromBufferView(info->source_id) ?: @"";
  layer.sourceLayerIdentifier = MLNFFIStringFromBufferView(info->source_layer) ?: @"";
  layer.minimumZoom = info->min_zoom;
  layer.maximumZoom = info->max_zoom;
  layer.visible = info->visibility == MLN_STYLE_LAYER_VISIBILITY_VISIBLE;
  return layer;
}

static MLNFFISourceInfo *MLNFFISourceInfoFromC(const mln_style_source_info *info) {
  MLNFFISourceInfo *source = [MLNFFISourceInfo new];
  source.identifier = MLNFFIStringFromBufferView(info->id) ?: @"";
  source.type = info->type;
  source.fields = info->fields;
  source.isVolatile = info->is_volatile;
  source.attribution = MLNFFIStringFromBufferView(info->attribution);
  source.URL = MLNFFIStringFromBufferView(info->url);
  NSMutableArray *tileURLs = [NSMutableArray array];
  for (size_t i = 0; i < info->tile_json.tile_url_count; i++) {
    [tileURLs addObject:MLNFFIStringFromBufferView(info->tile_json.tile_urls[i]) ?: @""];
  }
  source.tileURLs = tileURLs;
  source.minimumZoom = info->tile_json.min_zoom;
  source.maximumZoom = info->tile_json.max_zoom;
  source.scheme = info->tile_json.scheme;
  source.bounds = info->bounds;
  source.tileSize = info->tile_size;
  source.vectorEncoding = info->vector_encoding;
  source.rasterEncoding = info->raster_encoding;
  return source;
}

@implementation MLNFFIMap (Style)

- (mln_status)loadStyleURL:(NSString *)URL message:(NSString **)message {
  mln_map map = self.handle;
  return [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_set_style_url(map, MLNFFIBufferView(URL), completion, diagnostic);
  }
            consume:nil
            message:message];
}

// Classic parsed a style JSON within the call and reported it loaded (or
// failed) before returning.
- (mln_status)loadStyleJSON:(NSString *)JSON message:(NSString **)message {
  mln_map map = self.handle;
  mln_runtime_event_flags types = self.synchronousEventTypes;
  self.synchronousEventTypes = types | MLN_RUNTIME_EVENT_FLAG_MAP_STYLE_LOADED |
                               MLN_RUNTIME_EVENT_FLAG_MAP_LOADING_FAILED |
                               MLN_RUNTIME_EVENT_FLAG_MAP_SPRITE_REQUESTED;
  mln_status status = [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_set_style_json(map, MLNFFIBufferView(JSON), completion, diagnostic);
  }
                         consume:nil
                         message:message];
  self.synchronousEventTypes = types;
  return status;
}

- (NSString *)loadedStyleJSON {
  mln_map map = self.handle;
  __block NSString *json;
  [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_get_loaded_style_json(map, completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        if (result->value) {
          json = MLNFFIStringFromBufferView(*(const mln_buffer_view *)result->value);
        }
      }
      message:nil];
  return json;
}

- (NSString *)styleURL {
  mln_map map = self.handle;
  __block NSString *url;
  [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_get_style_url(map, completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        if (result->value) {
          url = MLNFFIStringFromBufferView(*(const mln_buffer_view *)result->value);
        }
      }
      message:nil];
  return url;
}

// MARK: Layers

- (NSArray<MLNFFILayerInfo *> *)styleLayers {
  mln_map map = self.handle;
  __block NSMutableArray *layers;
  mln_status status = [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_list_style_layers(map, completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        layers = [NSMutableArray arrayWithCapacity:result->value_count];
        for (size_t i = 0; i < result->value_count; i++) {
          [layers addObject:MLNFFILayerInfoFromC(MLN_STRIDED_AT(mln_style_layer_info, result->value,
                                                                result->value_size, i))];
        }
      }
      message:nil];
  return status == MLN_STATUS_OK ? layers : nil;
}

- (MLNFFILayerInfo *)styleLayerWithIdentifier:(NSString *)identifier {
  mln_map map = self.handle;
  __block MLNFFILayerInfo *layer;
  [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_get_style_layer(map, MLNFFIBufferView(identifier), completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        if (result->value) {
          layer = MLNFFILayerInfoFromC((const mln_style_layer_info *)result->value);
        }
      }
      message:nil];
  return layer;
}

- (NSDictionary *)styleLayerJSON:(NSString *)identifier {
  mln_map map = self.handle;
  __block id json;
  [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_get_style_layer_json(map, MLNFFIBufferView(identifier), completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        if (result->value) {
          json = MLNFFIJSONObjectFromBufferView(*(const mln_buffer_view *)result->value);
        }
      }
      message:nil];
  return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

- (mln_status)addStyleLayerJSON:(NSDictionary *)layer
                    belowLayer:(NSString *)before
                       message:(NSString **)message {
  mln_map map = self.handle;
  NSString *json = MLNFFIJSONStringFromObject(layer);
  return [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_add_style_layer_json(map, MLNFFIBufferView(json), MLNFFIBufferView(before),
                                        completion, diagnostic);
  }
            consume:nil
            message:message];
}

- (mln_status)removeStyleLayer:(NSString *)identifier message:(NSString **)message {
  mln_map map = self.handle;
  return [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_remove_style_layer(map, MLNFFIBufferView(identifier), completion, diagnostic);
  }
            consume:nil
            message:message];
}

- (mln_status)moveStyleLayer:(NSString *)identifier
                  belowLayer:(NSString *)before
                     message:(NSString **)message {
  mln_map map = self.handle;
  return [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_move_style_layer(map, MLNFFIBufferView(identifier), MLNFFIBufferView(before),
                                    completion, diagnostic);
  }
            consume:nil
            message:message];
}

- (mln_status)setStyleLayerProperty:(NSString *)name
                              layer:(NSString *)identifier
                              value:(id)value
                            message:(NSString **)message {
  mln_map map = self.handle;
  NSString *json = MLNFFIJSONStringFromObject(value);
  return [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_set_style_layer_property(map, MLNFFIBufferView(identifier),
                                            MLNFFIBufferView(name), MLNFFIBufferView(json),
                                            completion, diagnostic);
  }
            consume:nil
            message:message];
}

- (id)styleLayerProperty:(NSString *)name layer:(NSString *)identifier status:(mln_status *)outStatus {
  mln_map map = self.handle;
  __block id json;
  mln_status status = [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_get_style_layer_property(map, MLNFFIBufferView(identifier),
                                            MLNFFIBufferView(name), completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        if (result->value) {
          json = MLNFFIJSONObjectFromBufferView(*(const mln_buffer_view *)result->value);
        }
      }
      message:nil];
  if (outStatus) {
    *outStatus = status;
  }
  return json;
}

// MARK: Sources

- (NSArray<MLNFFISourceInfo *> *)styleSources {
  mln_map map = self.handle;
  __block NSMutableArray *sources;
  mln_status status = [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_list_style_sources(map, completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        sources = [NSMutableArray arrayWithCapacity:result->value_count];
        for (size_t i = 0; i < result->value_count; i++) {
          [sources addObject:MLNFFISourceInfoFromC(MLN_STRIDED_AT(
                                 mln_style_source_info, result->value, result->value_size, i))];
        }
      }
      message:nil];
  return status == MLN_STATUS_OK ? sources : nil;
}

- (MLNFFISourceInfo *)styleSourceWithIdentifier:(NSString *)identifier {
  mln_map map = self.handle;
  __block MLNFFISourceInfo *source;
  [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_get_style_source(map, MLNFFIBufferView(identifier), completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        if (result->value) {
          source = MLNFFISourceInfoFromC((const mln_style_source_info *)result->value);
        }
      }
      message:nil];
  return source;
}

- (mln_status)addStyleSourceJSON:(NSDictionary *)source
                      identifier:(NSString *)identifier
                         message:(NSString **)message {
  mln_map map = self.handle;
  NSString *json = MLNFFIJSONStringFromObject(source);
  return [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_add_style_source_json(map, MLNFFIBufferView(identifier), MLNFFIBufferView(json),
                                         completion, diagnostic);
  }
            consume:nil
            message:message];
}

- (mln_status)removeStyleSource:(NSString *)identifier message:(NSString **)message {
  mln_map map = self.handle;
  return [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_remove_style_source(map, MLNFFIBufferView(identifier), completion, diagnostic);
  }
            consume:nil
            message:message];
}

// MARK: Images

- (mln_status)setStyleImage:(NSString *)name
                     pixels:(NSData *)pixels
                      width:(uint32_t)width
                     height:(uint32_t)height
                    options:(const mln_style_image_options *)options
                    message:(NSString **)message {
  mln_map map = self.handle;
  mln_premultiplied_rgba8_image image = {sizeof(mln_premultiplied_rgba8_image)};
  image.width = width;
  image.height = height;
  image.stride = width * 4;
  image.pixels = (const uint8_t *)pixels.bytes;
  image.byte_length = pixels.length;
  return [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_set_style_image(map, MLNFFIBufferView(name), &image, options, completion,
                                   diagnostic);
  }
            consume:nil
            message:message];
}

- (mln_status)removeStyleImage:(NSString *)name message:(NSString **)message {
  mln_map map = self.handle;
  return [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_remove_style_image(map, MLNFFIBufferView(name), completion, diagnostic);
  }
            consume:nil
            message:message];
}

- (MLNFFIStyleImage *)styleImageNamed:(NSString *)name {
  mln_map map = self.handle;
  __block MLNFFIStyleImage *image;
  [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_get_style_image(map, MLNFFIBufferView(name), completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        if (!result->value) {
          return;
        }
        const mln_style_image_info *info = (const mln_style_image_info *)result->value;
        image = [MLNFFIStyleImage new];
        image.width = info->width;
        image.height = info->height;
        image.pixels = MLNFFIDataFromBufferView(info->pixels) ?: [NSData data];
        image.pixelRatio = info->pixel_ratio;
        image.sdf = info->sdf;
        NSMutableArray *stretchX = [NSMutableArray array];
        for (size_t i = 0; i < info->stretch_x_count; i++) {
          [stretchX addObject:[NSValue valueWithBytes:&info->stretch_x[i]
                                             objCType:@encode(mln_image_stretch)]];
        }
        NSMutableArray *stretchY = [NSMutableArray array];
        for (size_t i = 0; i < info->stretch_y_count; i++) {
          [stretchY addObject:[NSValue valueWithBytes:&info->stretch_y[i]
                                             objCType:@encode(mln_image_stretch)]];
        }
        image.stretchX = stretchX;
        image.stretchY = stretchY;
        image.hasContent = (info->fields & MLN_STYLE_IMAGE_INFO_CONTENT) != 0;
        image.content = info->content;
      }
      message:nil];
  return image;
}

// MARK: Light, transitions, global state

- (mln_status)setStyleLightProperty:(NSString *)name value:(id)value message:(NSString **)message {
  mln_map map = self.handle;
  NSString *json = MLNFFIJSONStringFromObject(value);
  return [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_set_style_light_property(map, MLNFFIBufferView(name), MLNFFIBufferView(json),
                                            completion, diagnostic);
  }
            consume:nil
            message:message];
}

- (id)styleLightProperty:(NSString *)name {
  mln_map map = self.handle;
  __block id json;
  [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_get_style_light_property(map, MLNFFIBufferView(name), completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        if (result->value) {
          json = MLNFFIJSONObjectFromBufferView(*(const mln_buffer_view *)result->value);
        }
      }
      message:nil];
  return json;
}

- (mln_status)setStyleLightJSON:(NSDictionary *)light message:(NSString **)message {
  mln_map map = self.handle;
  NSString *json = MLNFFIJSONStringFromObject(light);
  return [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_set_style_light_json(map, MLNFFIBufferView(json), completion, diagnostic);
  }
            consume:nil
            message:message];
}

- (mln_style_transition_options)styleTransitionOptions {
  mln_map map = self.handle;
  __block mln_style_transition_options options = {sizeof(mln_style_transition_options)};
  [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_get_style_transition_options(map, completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        if (result->value) {
          options = *(const mln_style_transition_options *)result->value;
        }
      }
      message:nil];
  return options;
}

- (mln_status)setStyleTransitionOptions:(mln_style_transition_options)options
                                message:(NSString **)message {
  mln_map map = self.handle;
  options.size = sizeof(mln_style_transition_options);
  return [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_set_style_transition_options(map, &options, completion, diagnostic);
  }
            consume:nil
            message:message];
}

- (NSDictionary *)globalState {
  mln_map map = self.handle;
  __block id json;
  [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_get_global_state(map, completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        if (result->value) {
          json = MLNFFIJSONObjectFromBufferView(*(const mln_buffer_view *)result->value);
        }
      }
      message:nil];
  return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

- (mln_status)setGlobalStateProperty:(NSString *)name value:(id)value message:(NSString **)message {
  mln_map map = self.handle;
  NSString *json = MLNFFIJSONStringFromObject(value);
  return [self call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_set_global_state_property(map, MLNFFIBufferView(name), MLNFFIBufferView(json),
                                             completion, diagnostic);
  }
            consume:nil
            message:message];
}

@end

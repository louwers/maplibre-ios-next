// Based on platform/darwin/src/MLNSource.mm at ios-v7.0.0

#import "MLNSource_Private.h"

#import "MLNMapView.h"
#import "MLNStyleValue_Private.h"
#import "MLNStyle_Private.h"
#import "NSBundle+MLNAdditions.h"
#import "NSException+MLNAdditions.h"

const MLNExceptionName MLNInvalidStyleSourceException = @"MLNInvalidStyleSourceException";

@interface MLNSource ()

@property (nonatomic, readonly, weak) id<MLNStylable> stylable;

@end

@implementation MLNSource {
  // Created by a concrete subclass, or for a source of a loaded style. Classic
  // tested for a core source object instead.
  BOOL _concrete;
  BOOL _invalidated;
  __weak MLNStyle *_style;
}

- (instancetype)initWithIdentifier:(NSString *)identifier {
  if (self = [super init]) {
    _identifier = [identifier copy];
  }
  return self;
}

- (instancetype)initWithPendingIdentifier:(NSString *)identifier {
  if (self = [self initWithIdentifier:identifier]) {
    _concrete = YES;
  }
  return self;
}

- (instancetype)initWithIdentifier:(NSString *)identifier style:(MLNStyle *)style {
  if (self = [self initWithIdentifier:identifier]) {
    _concrete = YES;
    _style = style;
    _stylable = style.stylable;
  }
  return self;
}

- (BOOL)mgl_isConcrete {
  return _concrete;
}

- (BOOL)mgl_isValid {
  return _concrete && !_invalidated;
}

- (MLNStyle *)mgl_style {
  return _invalidated ? nil : _style;
}

- (MLNFFIMap *)mgl_map {
  return self.mgl_style.mgl_map;
}

- (void)mgl_invalidate {
  _invalidated = YES;
  _style = nil;
  _stylable = nil;
}

- (NSDictionary *)mgl_sourceJSON {
  return nil;
}

- (mln_status)mgl_addToMap:(MLNFFIMap *)map message:(NSString **)message {
  NSDictionary *json = [self mgl_sourceJSON];
  if (!json) {
    if (message) {
      *message = [NSString stringWithFormat:@"Source %@ cannot be added again: the C API cannot "
                                             @"read back the configuration of a source that came "
                                             @"from the style.",
                                            self.identifier];
    }
    return MLN_STATUS_UNSUPPORTED;
  }
  return [map addStyleSourceJSON:json identifier:self.identifier message:message];
}

- (void)mgl_didAttachToMap:(MLNFFIMap *)map {
}

- (void)mgl_willDetachFromMap:(MLNFFIMap *)map {
}

- (void)addToStylable:(id<MLNStylable>)stylable {
  if (!_concrete || _invalidated || _style) {
    [NSException raise:MLNRedundantSourceException
                format:@"This instance %@ was already added to %@. Adding the same source instance "
                        "to the style more than once is invalid.",
                       self, stylable.style];
  }

  MLNStyle *style = stylable.style;
  MLNFFIMap *map = style.mgl_map;
  NSString *message;
  mln_status status = [self mgl_addToMap:map message:&message];
  if (status != MLN_STATUS_OK) {
    [NSException raise:MLNRedundantSourceIdentifierException format:@"%@", message];
  }
  _stylable = stylable;
  _style = style;
  [style mgl_registerSource:self];
  [self mgl_didAttachToMap:map];
}

- (BOOL)removeFromStylable:(id<MLNStylable>)mapView
                     error:(NSError *__nullable *__nullable)outError {
  MLNAssertStyleSourceIsValid();
  BOOL removed = NO;

  MLNStyle *style = mapView.style;
  if (style && _style == style && [style mgl_registeredSourceWithIdentifier:self.identifier] == self) {
    MLNFFIMap *map = style.mgl_map;
    [self mgl_willDetachFromMap:map];
    NSString *message;
    mln_status status = [map removeStyleSource:self.identifier message:&message];

    if (status == MLN_STATUS_OK) {
      removed = YES;
      [style mgl_unregisterSource:self];
      _style = nil;
      _stylable = nil;
      [self mgl_didAttachToMap:nil];
    } else if (outError) {
      NSString *localizedDescription = [NSString
          stringWithFormat:
              NSLocalizedStringWithDefaultValue(
                  @"REMOVE_SRC_FAIL_IN_USE_FMT", @"Foundation", nil,
                  @"The source “%@” can’t be removed while it is in use.",
                  @"User-friendly error description; first placeholder is the source’s identifier"),
              self.identifier];

      *outError = [NSError errorWithDomain:MLNErrorDomain
                                      code:MLNErrorCodeSourceIsInUseCannotRemove
                                  userInfo:@{NSLocalizedDescriptionKey : localizedDescription}];
    }
  } else if (outError) {
    // TODO: Consider raising an exception here
    NSString *localizedDescription =
        [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(
                                       @"REMOVE_SRC_FAIL_MISMATCH_FMT", @"Foundation", nil,
                                       @"The source can’t be removed because its identifier, “%@”, "
                                       @"belongs to a different source in this style.",
                                       @"User-friendly error description"),
                                   self.identifier];

    *outError = [NSError errorWithDomain:MLNErrorDomain
                                    code:MLNErrorCodeSourceIdentifierMismatch
                                userInfo:@{NSLocalizedDescriptionKey : localizedDescription}];
  }

  return removed;
}

// MARK: - Feature state

/**
 The map the source is attached to, when it is attached to a map view. Classic
 kept feature state in the map view's renderer; the C API keeps it in the map,
 but only map views offered it, so snapshotters still do not.
 */
- (MLNFFIMap *)mgl_featureStateMap {
  if ([self.stylable isKindOfClass:[MLNMapView class]]) {
    return self.mgl_map;
  }
  return nil;
}

- (void)mgl_setNeedsRerender {
  id stylable = self.stylable;
  if ([stylable respondsToSelector:@selector(mgl_setNeedsRerender)]) {
    [(id<MLNFFIStylable>)stylable mgl_setNeedsRerender];
  }
}

- (BOOL)mgl_setFeatureStateForSourceLayerID:(nullable NSString *)sourceLayerID
                                  featureID:(NSString *)featureID
                                      state:(NSDictionary<NSString *, id> *)state {
  MLNAssertIsMainThread();
  MLNAssertStyleSourceIsValid();

  MLNFFIMap *map = self.mgl_featureStateMap;
  if (!map || !featureID || !state) {
    return NO;
  }

  NSString *json = MLNFFIJSONStringFromObject(MLNJSONObjectFromFoundationValue(state));
  NSString *identifier = self.identifier;
  mln_map handle = map.handle;
  [map perform:@"set feature state"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          mln_feature_state_selector selector = {sizeof(mln_feature_state_selector)};
          selector.fields = MLN_FEATURE_STATE_SELECTOR_FEATURE_ID;
          selector.source_id = MLNFFIBufferView(identifier);
          selector.source_layer_id = MLNFFIBufferView(sourceLayerID);
          selector.feature_id = MLNFFIBufferView(featureID);
          return mln_map_set_feature_state(handle, &selector, MLNFFIBufferView(json), completion,
                                           diagnostic);
        }];

  [self mgl_setNeedsRerender];
  return YES;
}

- (nullable NSDictionary<NSString *, id> *)mgl_featureStateForSourceLayerID:
                                               (nullable NSString *)sourceLayerID
                                                                  featureID:(NSString *)featureID {
  MLNAssertIsMainThread();
  MLNAssertStyleSourceIsValid();

  MLNFFIMap *map = self.mgl_featureStateMap;
  if (!map || !featureID) {
    return nil;
  }

  NSString *identifier = self.identifier;
  mln_map handle = map.handle;
  __block id state;
  [map call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    mln_feature_state_selector selector = {sizeof(mln_feature_state_selector)};
    selector.fields = MLN_FEATURE_STATE_SELECTOR_FEATURE_ID;
    selector.source_id = MLNFFIBufferView(identifier);
    selector.source_layer_id = MLNFFIBufferView(sourceLayerID);
    selector.feature_id = MLNFFIBufferView(featureID);
    return mln_map_get_feature_state(handle, &selector, completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        if (result->value) {
          state = MLNFFIJSONObjectFromBufferView(*(const mln_buffer_view *)result->value);
        }
      }
      message:nil];

  if (![state isKindOfClass:[NSDictionary class]] || ![(NSDictionary *)state count]) {
    return nil;
  }
  return [state copy];
}

- (BOOL)mgl_removeFeatureStateForSourceLayerID:(nullable NSString *)sourceLayerID
                                     featureID:(nullable NSString *)featureID
                                      stateKey:(nullable NSString *)stateKey {
  MLNAssertIsMainThread();
  MLNAssertStyleSourceIsValid();

  MLNFFIMap *map = self.mgl_featureStateMap;
  if (!map) {
    return NO;
  }

  NSString *identifier = self.identifier;
  mln_map handle = map.handle;
  [map perform:@"remove feature state"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          mln_feature_state_selector selector = {sizeof(mln_feature_state_selector)};
          selector.fields = featureID ? MLN_FEATURE_STATE_SELECTOR_FEATURE_ID : 0;
          selector.source_id = MLNFFIBufferView(identifier);
          selector.source_layer_id = MLNFFIBufferView(sourceLayerID);
          selector.feature_id = MLNFFIBufferView(featureID);
          selector.state_key = MLNFFIBufferView(stateKey);
          return mln_map_remove_feature_state(handle, &selector, completion, diagnostic);
        }];

  [self mgl_setNeedsRerender];
  return YES;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@: %p; identifier = %@>", NSStringFromClass([self class]),
                                    (void *)self, self.identifier];
}

@end

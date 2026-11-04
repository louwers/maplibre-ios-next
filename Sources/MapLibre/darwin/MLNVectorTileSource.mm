// Based on platform/darwin/src/MLNVectorTileSource.mm at ios-v7.0.0

#import "MLNVectorTileSource_Private.h"

#import "MLNFFISourceQueries.h"
#import "MLNLoggingConfiguration_Private.h"
#import "MLNMapView.h"
#import "MLNSource_Private.h"
#import "MLNStyle_Private.h"
#import "MLNTileSource_Private.h"

#import "NSPredicate+MLNAdditions.h"
#import "NSURL+MLNAdditions.h"

const MLNTileSourceOption MLNVectorTileSourceOptionEncoding = @"MLNVectorTileSourceOptionEncoding";

@implementation MLNVectorTileSource

- (instancetype)initWithIdentifier:(NSString *)identifier
                  configurationURL:(NSURL *)configurationURL {
  NSDictionary *source = @{
    @"type" : @"vector",
    @"url" : configurationURL.mgl_URLByStandardizingScheme.absoluteString ?: @"",
  };
  return self = [super initWithPendingIdentifier:identifier sourceJSON:source];
}

- (instancetype)initWithIdentifier:(NSString *)identifier
            configurationURLString:(NSString *)configurationURLString {
  NSDictionary *source = @{@"type" : @"vector", @"url" : configurationURLString ?: @""};

  return self = [super initWithPendingIdentifier:identifier sourceJSON:source];
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                  tileURLTemplates:(NSArray<NSString *> *)tileURLTemplates
                           options:(nullable NSDictionary<MLNTileSourceOption, id> *)options {
  NSMutableDictionary *source =
      MLNTileSourceJSONFromTileURLTemplates(tileURLTemplates, options, @"vector");
  source[@"type"] = @"vector";
  return self = [super initWithPendingIdentifier:identifier sourceJSON:source];
}

- (NSURL *)configurationURL {
  MLNAssertStyleSourceIsValid();
  return self.mgl_configurationURL;
}

- (NSString *)attributionHTMLString {
  if (!self.mgl_isValid) {
    MLNAssert(0, @"Source with identifier `%@` was invalidated after a style change",
              self.identifier);
    return nil;
  }

  return self.mgl_attributionHTMLString;
}

- (NSArray<id<MLNFeature>> *)
    featuresInSourceLayersWithIdentifiers:(NSSet<NSString *> *)sourceLayerIdentifiers
                                predicate:(nullable NSPredicate *)predicate {
  MLNAssertStyleSourceIsValid();
  if (![self.stylable isKindOfClass:[MLNMapView class]]) {
    return @[];
  }
  return MLNFFIQuerySourceFeatures(self, sourceLayerIdentifiers, predicate);
}

// MARK: - Managing Feature State

- (BOOL)setFeatureStateForSourceLayerID:(NSString *)sourceLayerID
                              featureID:(NSString *)featureID
                                  state:(NSDictionary<NSString *, id> *)state {
  return [self mgl_setFeatureStateForSourceLayerID:sourceLayerID featureID:featureID state:state];
}

- (nullable NSDictionary<NSString *, id> *)featureStateForSourceLayerID:(NSString *)sourceLayerID
                                                              featureID:(NSString *)featureID {
  return [self mgl_featureStateForSourceLayerID:sourceLayerID featureID:featureID];
}

- (BOOL)removeFeatureStateForSourceLayerID:(NSString *)sourceLayerID
                                 featureID:(nullable NSString *)featureID
                                  stateKey:(nullable NSString *)stateKey {
  return [self mgl_removeFeatureStateForSourceLayerID:sourceLayerID
                                            featureID:featureID
                                             stateKey:stateKey];
}

- (BOOL)removeFeatureStateForSourceLayerID:(NSString *)sourceLayerID
                                 featureID:(NSString *)featureID {
  return [self mgl_removeFeatureStateForSourceLayerID:sourceLayerID
                                            featureID:featureID
                                             stateKey:nil];
}

- (BOOL)resetFeatureStatesForSourceLayerID:(NSString *)sourceLayerID {
  return [self mgl_removeFeatureStateForSourceLayerID:sourceLayerID featureID:nil stateKey:nil];
}

@end

@implementation MLNVectorTileSource (Private)

/**
 An array of locale codes with dedicated name fields in the Mapbox Streets
 source.

 https://www.mapbox.com/vector-tiles/mapbox-streets-v8/
 */
static NSArray *const MLNMapboxStreetsLanguages = @[
  @"ar",
  @"de",
  @"en",
  @"es",
  @"fr",
  @"ja",
  @"ko",
  @"pt",
  @"ru",
  @"vi",
  @"zh-Hans",
  @"zh-Hant",
];

/**
 Like ``MLNMapboxStreetsLanguages``, but deanglicized for use with
 `+[NSBundle preferredLocalizationsFromArray:forPreferences:]`.
 */
static NSArray *const MLNMapboxStreetsAlternativeLanguages = @[
  @"mul",
  @"ar",
  @"de",
  @"es",
  @"fr",
  @"ja",
  @"ko",
  @"pt",
  @"ru",
  @"vi",
  @"zh-Hans",
  @"zh-Hant",
];

+ (NSSet<NSString *> *)mapboxStreetsLanguages {
  static dispatch_once_t onceToken;
  static NSSet<NSString *> *mapboxStreetsLanguages;
  dispatch_once(&onceToken, ^{
    mapboxStreetsLanguages = [NSSet setWithArray:MLNMapboxStreetsLanguages];
  });
  return mapboxStreetsLanguages;
}

+ (NSString *)preferredMapboxStreetsLanguage {
  return [self preferredMapboxStreetsLanguageForPreferences:[NSLocale preferredLanguages]];
}

+ (NSString *)preferredMapboxStreetsLanguageForPreferences:(NSArray<NSString *> *)preferencesArray {
  BOOL acceptsEnglish =
      [preferencesArray filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(
                                                                     NSString *_Nullable language,
                                                                     NSDictionary<NSString *, id>
                                                                         *_Nullable bindings) {
                          NSString *languageCode =
                              [NSLocale localeWithLocaleIdentifier:language].languageCode;

                          return [languageCode isEqualToString:@"en"];
                        }]]
          .count;

  NSArray<NSString *> *availableLanguages =
      acceptsEnglish ? MLNMapboxStreetsLanguages : MLNMapboxStreetsAlternativeLanguages;
  NSArray<NSString *> *preferredLanguages =
      [NSBundle preferredLocalizationsFromArray:availableLanguages forPreferences:preferencesArray];
  NSString *mostSpecificLanguage;
  for (NSString *language in preferredLanguages) {
    if (language.length > mostSpecificLanguage.length) {
      mostSpecificLanguage = language;
    }
  }
  return [mostSpecificLanguage isEqualToString:@"mul"] ? nil : mostSpecificLanguage;
}

- (BOOL)isMapboxStreets {
  NSURL *url = self.configurationURL;
  if (![url.scheme isEqualToString:@"mapbox"]) {
    return NO;
  }
  NSArray *identifiers = [url.host componentsSeparatedByString:@","];
  return [identifiers containsObject:@"mapbox.mapbox-streets-v8"] ||
         [identifiers containsObject:@"mapbox.mapbox-streets-v7"];
}

@end

// Based on platform/darwin/src/MLNSettings.mm at ios-v7.0.0

#import "MLNSettings_Private.h"
#import "NSBundle+MLNAdditions.h"

#if TARGET_OS_OSX
#import "NSProcessInfo+MLNAdditions.h"
#endif

@interface MLNSettings ()

@property (atomic) NSString *apiKey;
@property (atomic) MLNTileServerOptions *tileServerOptionsInternal;
@property (atomic) NSString *tileServerOptionsChangeToken;

@end

// The core's tile server configurations (src/mln/util/tile_server_options.cpp
// at ios-v7.0.0), as values.

static MLNDefaultStyle *MLNDefaultStyleMake(NSString *url, NSString *name, int version) {
  MLNDefaultStyle *style = [[MLNDefaultStyle alloc] init];
  style.url = [NSURL URLWithString:url];
  style.name = name;
  style.version = version;
  return style;
}

static MLNTileServerOptions *MLNTileServerOptionsMake(
    NSString *baseURL, NSString *uriSchemeAlias, NSString *apiKeyParameterName,
    NSArray<NSString *> *source, NSArray<NSString *> *style, NSArray<NSString *> *sprites,
    NSArray<NSString *> *glyphs, NSArray<NSString *> *tile, NSArray<MLNDefaultStyle *> *defaultStyles,
    NSString *defaultStyleName) {
  // Each template array holds template, domain name, and optionally a version prefix.
  MLNTileServerOptions *options = [[MLNTileServerOptions alloc] init];
  options.baseURL = baseURL;
  options.uriSchemeAlias = uriSchemeAlias;
  options.apiKeyParameterName = apiKeyParameterName;
  options.sourceTemplate = source[0];
  options.sourceDomainName = source[1];
  options.sourceVersionPrefix = source.count > 2 ? source[2] : nil;
  options.styleTemplate = style[0];
  options.styleDomainName = style[1];
  options.styleVersionPrefix = style.count > 2 ? style[2] : nil;
  options.spritesTemplate = sprites[0];
  options.spritesDomainName = sprites[1];
  options.spritesVersionPrefix = sprites.count > 2 ? sprites[2] : nil;
  options.glyphsTemplate = glyphs[0];
  options.glyphsDomainName = glyphs[1];
  options.glyphsVersionPrefix = glyphs.count > 2 ? glyphs[2] : nil;
  options.tileTemplate = tile[0];
  options.tileDomainName = tile[1];
  options.tileVersionPrefix = tile.count > 2 ? tile[2] : nil;
  options.defaultStyles = defaultStyles;
  for (MLNDefaultStyle *defaultStyle in defaultStyles) {
    if ([defaultStyle.name isEqualToString:defaultStyleName]) {
      options.defaultStyle = defaultStyle;
    }
  }
  return options;
}

static MLNTileServerOptions *MLNMapLibreTileServerConfiguration(void) {
  return MLNTileServerOptionsMake(
      @"https://demotiles.maplibre.org", @"maplibre", @"", @[ @"/tiles/{domain}.json", @"" ],
      @[ @"{path}.json", @"maps" ], @[ @"/{path}/sprite{scale}.{format}", @"" ],
      @[ @"/font/{fontstack}/{start}-{end}.pbf", @"fonts" ], @[ @"/{path}", @"tiles" ],
      @[ MLNDefaultStyleMake(@"maplibre://maps/style", @"Basic", 1) ], @"Basic");
}

static MLNTileServerOptions *MLNMapboxTileServerConfiguration(void) {
  return MLNTileServerOptionsMake(
      @"https://api.mapbox.com", @"mapbox", @"access_token", @[ @"/{domain}.json", @"", @"/v4" ],
      @[ @"/styles/v1{path}", @"styles" ],
      @[ @"/styles/v1{directory}{filename}/sprite{extension}", @"sprites" ],
      @[ @"/fonts/v1{path}", @"fonts" ], @[ @"{path}", @"tiles", @"/v4" ], @[
        MLNDefaultStyleMake(@"mapbox://styles/mapbox/streets-v11", @"Streets", 11),
        MLNDefaultStyleMake(@"mapbox://styles/mapbox/outdoors-v11", @"Outdoors", 11),
        MLNDefaultStyleMake(@"mapbox://styles/mapbox/light-v10", @"Light", 10),
        MLNDefaultStyleMake(@"mapbox://styles/mapbox/dark-v10", @"Dark", 10),
        MLNDefaultStyleMake(@"mapbox://styles/mapbox/satellite-v9", @"Satellite", 9),
        MLNDefaultStyleMake(@"mapbox://styles/mapbox/satellite-streets-v11", @"Satellite Streets",
                            11)
      ],
      @"Streets");
}

static MLNTileServerOptions *MLNMapTilerTileServerConfiguration(void) {
  return MLNTileServerOptionsMake(
      @"https://api.maptiler.com", @"maptiler", @"key", @[ @"/tiles{path}/tiles.json", @"sources" ],
      @[ @"/maps{path}/style.json", @"maps" ], @[ @"/maps{path}", @"sprites" ],
      @[ @"/fonts{path}", @"fonts" ], @[ @"{path}", @"tiles" ], @[
        MLNDefaultStyleMake(@"maptiler://maps/streets", @"Streets", 1),
        MLNDefaultStyleMake(@"maptiler://maps/outdoor", @"Outdoor", 1),
        MLNDefaultStyleMake(@"maptiler://maps/basic", @"Basic", 1),
        MLNDefaultStyleMake(@"maptiler://maps/bright", @"Bright", 1),
        MLNDefaultStyleMake(@"maptiler://maps/pastel", @"Pastel", 1),
        MLNDefaultStyleMake(@"maptiler://maps/hybrid", @"Satellite Hybrid", 1),
        MLNDefaultStyleMake(@"maptiler://maps/topo", @"Satellite Topo", 1)
      ],
      @"Streets");
}

static MLNDefaultStyle *MLNDefaultStyleCopy(MLNDefaultStyle *style) {
  return MLNDefaultStyleMake(style.url.absoluteString, style.name, style.version);
}

/// A deep copy, as mln::TileServerOptions::clone() made.
static MLNTileServerOptions *MLNTileServerOptionsCopy(MLNTileServerOptions *options) {
  MLNTileServerOptions *copy = [[MLNTileServerOptions alloc] init];
  copy.baseURL = options.baseURL;
  copy.uriSchemeAlias = options.uriSchemeAlias;
  copy.apiKeyParameterName = options.apiKeyParameterName;
  copy.sourceTemplate = options.sourceTemplate;
  copy.sourceDomainName = options.sourceDomainName;
  copy.sourceVersionPrefix = options.sourceVersionPrefix;
  copy.styleTemplate = options.styleTemplate;
  copy.styleDomainName = options.styleDomainName;
  copy.styleVersionPrefix = options.styleVersionPrefix;
  copy.spritesTemplate = options.spritesTemplate;
  copy.spritesDomainName = options.spritesDomainName;
  copy.spritesVersionPrefix = options.spritesVersionPrefix;
  copy.glyphsTemplate = options.glyphsTemplate;
  copy.glyphsDomainName = options.glyphsDomainName;
  copy.glyphsVersionPrefix = options.glyphsVersionPrefix;
  copy.tileTemplate = options.tileTemplate;
  copy.tileDomainName = options.tileDomainName;
  copy.tileVersionPrefix = options.tileVersionPrefix;
  NSMutableArray *styles = [NSMutableArray array];
  for (MLNDefaultStyle *style in options.defaultStyles) {
    MLNDefaultStyle *styleCopy = MLNDefaultStyleCopy(style);
    [styles addObject:styleCopy];
    if (style == options.defaultStyle ||
        (options.defaultStyle && [style.name isEqualToString:options.defaultStyle.name])) {
      copy.defaultStyle = styleCopy;
    }
  }
  copy.defaultStyles = styles;
  return copy;
}

@implementation MLNSettings

// MARK: - Internal

- (instancetype)init {
  if (self = [super init]) {
    self.tileServerOptionsInternal = MLNMapLibreTileServerConfiguration();
  }
  return self;
}

+ (void)load {
  // Read the initial configuration from Info.plist.
  NSString *apiKey = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"MLNApiKey"];
  if (apiKey.length) {
    self.apiKey = apiKey;
  }

  NSString *apiBaseURL = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"MLNTileServerBaseURL"];

  // If apiBaseURL is not a valid URL, [NSURL URLWithString:] will be `nil`.
  if (apiBaseURL.length && [NSURL URLWithString:apiBaseURL]) {
    [self setAPIBaseURL:[NSURL URLWithString:apiBaseURL]];
    [self tileServerOptionsChanged];
  }
}

+ (instancetype)sharedSettings {
#if TARGET_OS_OSX
  if (NSProcessInfo.processInfo.mgl_isInterfaceBuilderDesignablesAgent) {
    return nil;
  }
#endif

  static dispatch_once_t onceToken;
  static MLNSettings *_sharedSettings;
  void (^setupBlock)(void) = ^{
    dispatch_once(&onceToken, ^{
      _sharedSettings = [[self alloc] init];
    });
  };
  if (![[NSThread currentThread] isMainThread]) {
    dispatch_sync(dispatch_get_main_queue(), ^{
      setupBlock();
    });
  } else {
    setupBlock();
  }
  return _sharedSettings;
}

+ (void)setApiKey:(NSString *)apiKey {
  apiKey =
      [apiKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (!apiKey.length) {
    return;
  }

  [MLNSettings sharedSettings].apiKey = apiKey;
}

+ (NSString *)apiKey {
  return [MLNSettings sharedSettings].apiKey;
}

+ (void)setAPIBaseURL:(NSURL *)apiBaseURL {
  [MLNSettings sharedSettings].tileServerOptionsInternal.baseURL = apiBaseURL.absoluteString ?: @"";
}

+ (NSURL *)apiBaseURL {
  NSString *baseUrlNSStr = [MLNSettings sharedSettings].tileServerOptionsInternal.baseURL;
  NSURL *url = [NSURL URLWithString:baseUrlNSStr];
  return url;
}

+ (void)setTileServerOptionsInternal:(MLNTileServerOptions *)options {
  [MLNSettings sharedSettings].tileServerOptionsInternal = MLNTileServerOptionsCopy(options);
  [self tileServerOptionsChanged];
}

+ (MLNTileServerOptions *)tileServerOptionsInternal {
  return MLNTileServerOptionsCopy([MLNSettings sharedSettings].tileServerOptionsInternal);
}

+ (void)tileServerOptionsChanged {
  [MLNSettings sharedSettings].tileServerOptionsChangeToken = [[NSUUID UUID] UUIDString];
}

+ (void)useWellKnownTileServer:(MLNWellKnownTileServer)tileServer {
  switch (tileServer) {
    case MLNMapTiler:
      [MLNSettings setTileServerOptionsInternal:MLNMapTilerTileServerConfiguration()];
      break;
    case MLNMapLibre:
      [MLNSettings setTileServerOptionsInternal:MLNMapLibreTileServerConfiguration()];
      break;
    case MLNMapbox:
      [MLNSettings setTileServerOptionsInternal:MLNMapboxTileServerConfiguration()];
      break;
    default:
      [MLNSettings setTileServerOptionsInternal:MLNMapLibreTileServerConfiguration()];
  }
}

+ (void)setTileServerOptions:(MLNTileServerOptions *)options {
  // As classic, which built new mbgl::TileServerOptions: every template and
  // name is required (UTF8String of nil crashed there), the default styles are
  // copied, and the default style is looked up by name.
  MLNTileServerOptions *opts = MLNTileServerOptionsCopy(options);
  NSMutableArray<MLNDefaultStyle *> *defaultStyles = [NSMutableArray array];
  if (options.defaultStyles) {
    for (MLNDefaultStyle *objCStyle in options.defaultStyles) {
      [defaultStyles addObject:MLNDefaultStyleCopy(objCStyle)];
    }
  }
  opts.defaultStyles = defaultStyles;
  MLNDefaultStyle *defaultStyle;
  for (MLNDefaultStyle *style in defaultStyles) {
    if ([style.name isEqualToString:options.defaultStyle.name ?: @""]) {
      defaultStyle = style;
    }
  }
  [opts setValue:defaultStyle forKey:@"defaultStyle"];
  self.tileServerOptionsInternal = opts;
}

+ (MLNTileServerOptions *)tileServerOptions {
  MLNTileServerOptions *cppOpts = [MLNSettings sharedSettings].tileServerOptionsInternal;
  if (cppOpts) {
    MLNTileServerOptions *retVal = MLNTileServerOptionsCopy(cppOpts);
    // Classic reported the sprites, glyphs and tile version prefixes only when
    // the style had one.
    if (!cppOpts.styleVersionPrefix) {
      retVal.spritesVersionPrefix = nil;
      retVal.glyphsVersionPrefix = nil;
      retVal.tileVersionPrefix = nil;
    }
    return retVal;
  }
  return nil;
}

@end

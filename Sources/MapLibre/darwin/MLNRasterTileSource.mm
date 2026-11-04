// Based on platform/darwin/src/MLNRasterTileSource.mm at ios-v7.0.0

#import "MLNRasterTileSource_Private.h"

#import "MLNLoggingConfiguration_Private.h"
#import "MLNSource_Private.h"
#import "MLNTileSource_Private.h"
#import "NSURL+MLNAdditions.h"

const MLNTileSourceOption MLNTileSourceOptionTileSize = @"MLNTileSourceOptionTileSize";

static const CGFloat MLNRasterTileSourceClassicTileSize = 256;
static const CGFloat MLNRasterTileSourceRetinaTileSize = 512;

@implementation MLNRasterTileSource

- (instancetype)initWithIdentifier:(NSString *)identifier
                  configurationURL:(NSURL *)configurationURL {
  // The style specification default is 512, but 256 is the expected value for
  // any tile set that would be accessed through a mapbox: URL and therefore
  // any tile URL that this option currently affects.
  BOOL isMapboxURL =
      ([configurationURL.scheme isEqualToString:@"mapbox"] &&
       [configurationURL.host containsString:@"."] &&
       (!configurationURL.path.length || [configurationURL.path isEqualToString:@"/"]));
  CGFloat tileSize =
      isMapboxURL ? MLNRasterTileSourceClassicTileSize : MLNRasterTileSourceRetinaTileSize;
  return [self initWithIdentifier:identifier configurationURL:configurationURL tileSize:tileSize];
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                  configurationURL:(NSURL *)configurationURL
                          tileSize:(CGFloat)tileSize {
  NSString *configurationURLString = configurationURL.mgl_URLByStandardizingScheme.absoluteString;
  NSDictionary *source = @{
    @"type" : [[self class] mgl_sourceType],
    @"url" : configurationURLString ?: @"",
    @"tileSize" : @(uint16_t(round(tileSize))),
  };
  return self = [super initWithPendingIdentifier:identifier sourceJSON:source];
}

+ (NSString *)mgl_sourceType {
  return @"raster";
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                  tileURLTemplates:(NSArray<NSString *> *)tileURLTemplates
                           options:(nullable NSDictionary<MLNTileSourceOption, id> *)options {
  NSMutableDictionary *source =
      MLNTileSourceJSONFromTileURLTemplates(tileURLTemplates, options, [[self class] mgl_sourceType]);

  uint16_t tileSize = MLNRasterTileSourceRetinaTileSize;
  if (NSNumber *tileSizeNumber = options[MLNTileSourceOptionTileSize]) {
    if (![tileSizeNumber isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNTileSourceOptionTileSize must be set to an NSNumber."];
    }
    tileSize = static_cast<uint16_t>(round(tileSizeNumber.doubleValue));
  }

  source[@"type"] = [[self class] mgl_sourceType];
  source[@"tileSize"] = @(tileSize);
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

@end

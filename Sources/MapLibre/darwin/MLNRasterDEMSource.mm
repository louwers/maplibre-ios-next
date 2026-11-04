// Based on platform/darwin/src/MLNRasterDEMSource.mm at ios-v7.0.0

#import "MLNRasterDEMSource.h"

#import "MLNRasterTileSource_Private.h"
#import "NSURL+MLNAdditions.h"

const MLNTileSourceOption MLNTileSourceOptionDEMEncoding = @"MLNTileSourceOptionDEMEncoding";

@implementation MLNRasterDEMSource

+ (NSString *)mgl_sourceType {
  return @"raster-dem";
}

@end

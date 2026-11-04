// Based on platform/darwin/src/MLNRasterTileSource_Private.h at ios-v7.0.0

#import "MLNRasterTileSource.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLNRasterTileSource (Private)

/// The style-spec source type: "raster", or "raster-dem" for MLNRasterDEMSource.
/// Classic overrode -pendingSourceWithIdentifier:urlOrTileset:tileSize: instead.
@property (class, nonatomic, readonly) NSString *mgl_sourceType;

@end

NS_ASSUME_NONNULL_END

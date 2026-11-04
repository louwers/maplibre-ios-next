// Based on platform/darwin/src/MLNSettings_Private.h at ios-v7.0.0
//
// Classic kept an mbgl::TileServerOptions and passed it, with the API key, to
// every file source. The C API's runtime takes neither (it always uses the
// core's default, MapLibre tile server configuration), so the options are kept
// as an MLNTileServerOptions value and only reported back (C_API_GAPS.md).

#import "MLNSettings.h"
#import "MLNTileServerOptions.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLNSettings (Private)

@property (class, nonatomic, readonly) MLNSettings *sharedSettings;

@property (atomic, nullable) NSString *apiKey;
@property (atomic, readwrite, nullable) MLNTileServerOptions *tileServerOptionsInternal;
@property (atomic, readwrite, nullable) NSURL *apiBaseURL;
@property (atomic, nullable) NSString *tileServerOptionsChangeToken;

+ (void)tileServerOptionsChanged;

@end

NS_ASSUME_NONNULL_END

// Based on platform/darwin/src/MLNRenderingStats_Private.h at ios-v7.0.0
//
// Classic filled MLNRenderingStats from mbgl::gfx::RenderingStats. The C API
// reports only a frame's encoding and rendering time and its frame and draw
// call counts (mln_rendering_stats), and no rendered feature information, so
// the other properties stay zero (C_API_GAPS.md).

#import <MaplibreNativeC/maplibre_native_c.h>

#import "MLNRenderingStats.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLNRenderingStats (Private)

/// Takes the values the C API reports with a render-frame event.
- (void)mgl_setFFIStats:(mln_rendering_stats)stats;

@end

NS_ASSUME_NONNULL_END

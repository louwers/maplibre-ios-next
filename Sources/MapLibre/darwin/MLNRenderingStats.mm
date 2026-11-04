// Based on platform/darwin/src/MLNRenderingStats.mm at ios-v7.0.0

#import "MLNRenderingStats_Private.h"

#import <CoreGraphics/CoreGraphics.h>

// MLNOverscaledTileID, MLNSourceLayerID and MLNFeatureInfo were built from
// mbgl rendering stats' frameRenderedFeatures. The C API reports no rendered
// feature information, so nothing creates them; they keep their classic
// interface.

@implementation MLNOverscaledTileID
@end

@implementation MLNSourceLayerID

- (id)copyWithZone:(NSZone *)zone {
  MLNSourceLayerID *copy = [[[self class] allocWithZone:zone] init];
  if (copy) {
    copy->_sourceID = [_sourceID copyWithZone:zone];
    copy->_layerID = [_layerID copyWithZone:zone];
  }
  return copy;
}

@end

@implementation MLNFeatureInfo
@end

@implementation MLNRenderingStats

- (void)mgl_setFFIStats:(mln_rendering_stats)stats {
  _encodingTime = stats.encoding_time;
  _renderingTime = stats.rendering_time;
  _numFrames = static_cast<int>(stats.frame_count);
  _numDrawCalls = static_cast<int>(stats.draw_call_count);
  _totalDrawCalls = static_cast<int>(stats.total_draw_call_count);
}

@end

// Based on platform/darwin/src/MLNPluginStyleLayer.mm at ios-v7.0.0

#import "MLNPluginStyleLayer.h"
#import "MLNPluginLayer.h"
#import "MLNPluginStyleLayer_Private.h"

@implementation MLNPluginStyleLayer {
  MLNPluginLayer *_pluginLayer;
}

- (void)getStats {
}

- (MLNPluginLayer *)pluginLayer {
  return _pluginLayer;
}

- (MLNPluginLayer *)mgl_pluginLayer {
  return _pluginLayer;
}

- (void)setMgl_pluginLayer:(MLNPluginLayer *)pluginLayer {
  _pluginLayer = pluginLayer;
}

@end

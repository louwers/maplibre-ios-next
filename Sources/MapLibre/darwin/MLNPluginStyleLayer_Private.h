// Based on platform/darwin/src/MLNPluginStyleLayer_Private.h at ios-v7.0.0
//
// Classic registered a peer factory for each plugin layer type with the core.
// The C API's plugin interface (plugin.h) is a different, C-level ABI, so
// MLNPluginLayer subclasses cannot be registered (C_API_GAPS.md).

#pragma once

#import "MLNPluginStyleLayer.h"
#import "MLNStyleLayer_Private.h"

NS_ASSUME_NONNULL_BEGIN

@class MLNPluginLayer;

@interface MLNPluginStyleLayer (Private)

/// The plugin layer object for this style layer; classic kept it in the core
/// layer's platform reference.
@property (nonatomic, nullable) MLNPluginLayer *mgl_pluginLayer;

@end

NS_ASSUME_NONNULL_END

#import "MLNStyleSpec.h"

#import "MLNFFIMap+Style.h"
#import "MLNLoggingConfiguration_Private.h"

#include <os/lock.h>

static NSString *MLNDefaultsLayerIdentifier(NSString *layerType) {
  return [@"org.maplibre.next.defaults." stringByAppendingString:layerType];
}

/// Ensures the scratch map has a layer of the type to normalize defaults on.
static BOOL MLNEnsureDefaultsLayer(MLNFFIMap *scratch, NSString *layerType) {
  static NSMutableSet<NSString *> *created;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    created = [NSMutableSet set];
  });
  @synchronized(created) {
    if ([created containsObject:layerType]) {
      return YES;
    }
    [created addObject:layerType];
  }
  NSString *identifier = MLNDefaultsLayerIdentifier(layerType);
  NSMutableDictionary *layer = [@{@"id" : identifier, @"type" : layerType} mutableCopy];
  if (![layerType isEqualToString:@"background"]) {
    NSString *sourceIdentifier = [identifier stringByAppendingString:@".source"];
    NSDictionary *source;
    if ([layerType isEqualToString:@"raster"]) {
      source = @{@"type" : @"raster", @"tiles" : @[]};
    } else if ([layerType isEqualToString:@"hillshade"] || [layerType isEqualToString:@"color-relief"]) {
      source = @{@"type" : @"raster-dem", @"tiles" : @[]};
    } else {
      source = @{@"type" : @"geojson", @"data" : @{@"type" : @"FeatureCollection", @"features" : @[]}};
    }
    [scratch addStyleSourceJSON:source identifier:sourceIdentifier message:nil];
    layer[@"source"] = sourceIdentifier;
  }
  NSString *message;
  if ([scratch addStyleLayerJSON:layer belowLayer:nil message:&message] != MLN_STATUS_OK) {
    MLNLogError(@"Failed to create a %@ layer for default values: %@", layerType, message);
    return NO;
  }
  return YES;
}

id MLNStyleDefaultValueJSON(NSString *layerType, const MLNStylePropertyDescriptor *descriptor) {
  if (!descriptor->defaultJSON || !layerType.length) {
    return nil;
  }
  static NSMutableDictionary<NSString *, id> *cache;
  static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    cache = [NSMutableDictionary dictionary];
  });
  NSString *name = @(descriptor->name);
  NSString *key = [NSString stringWithFormat:@"%@/%@", layerType, name];
  os_unfair_lock_lock(&lock);
  id cached = cache[key];
  os_unfair_lock_unlock(&lock);
  if (cached) {
    return cached == [NSNull null] ? nil : cached;
  }

  NSData *data = [@(descriptor->defaultJSON) dataUsingEncoding:NSUTF8StringEncoding];
  id specDefault = [NSJSONSerialization JSONObjectWithData:data
                                                   options:NSJSONReadingFragmentsAllowed
                                                     error:nil];
  MLNFFIMap *scratch = [MLNFFIMap scratchMap];
  id normalized;
  if ([layerType isEqualToString:@"light"]) {
    if ([scratch setStyleLightProperty:name value:specDefault message:nil] == MLN_STATUS_OK) {
      normalized = [scratch styleLightProperty:name];
    }
  } else if (MLNEnsureDefaultsLayer(scratch, layerType)) {
    NSString *identifier = MLNDefaultsLayerIdentifier(layerType);
    if ([scratch setStyleLayerProperty:name layer:identifier value:specDefault message:nil] ==
        MLN_STATUS_OK) {
      normalized = [scratch styleLayerProperty:name layer:identifier status:nil];
      [scratch setStyleLayerProperty:name layer:identifier value:[NSNull null] message:nil];
    }
  }
  // Fall back to the spec's value if the core refused it.
  normalized = normalized ?: specDefault;

  os_unfair_lock_lock(&lock);
  cache[key] = normalized ?: [NSNull null];
  os_unfair_lock_unlock(&lock);
  return normalized;
}

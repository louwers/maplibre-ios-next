// Based on platform/darwin/src/NSBundle+MLNAdditions.mm at ios-v7.0.0

#import "NSBundle+MLNAdditions.h"

#import "MLNSettings.h"

const MLNExceptionName MLNBundleNotFoundException = @"MLNBundleNotFoundException";

@implementation NSBundle (MLNAdditions)

+ (instancetype)mgl_frameworkBundle {
#ifdef SWIFTPM_MODULE_BUNDLE
  // Built as a Swift package: SwiftPM copies the resources into a bundle of
  // their own and defines this accessor for it.
  return SWIFTPM_MODULE_BUNDLE;
#endif
  NSBundle *bundle = [self bundleForClass:[MLNSettings class]];

#ifndef MLN_CUSTOM_COMBINED_BUNDLE
  if (![bundle.infoDictionary[@"CFBundlePackageType"] isEqualToString:@"FMWK"]) {
    // For static frameworks, the bundle is the containing application
    // bundle but the resources are in Mapbox.bundle.
    NSString *bundlePath = [bundle pathForResource:@"Mapbox" ofType:@"bundle"];
    if (bundlePath) {
      bundle = [self bundleWithPath:bundlePath];
    } else {
      [NSException raise:MLNBundleNotFoundException
                  format:@"The MapLibre framework bundle could not be found. If using  MapLibre "
                         @"iOS as a static framework, make sure that MapLibre bundle is copied "
                         @"into the root of the app bundle."];
    }
  }
#endif

  return bundle;
}

+ (nullable NSString *)mgl_frameworkBundleIdentifier {
  return self.mgl_frameworkInfoDictionary[@"CFBundleIdentifier"];
}

+ (nullable NSDictionary<NSString *, id> *)mgl_frameworkInfoDictionary {
  NSBundle *bundle = self.mgl_frameworkBundle;
#ifdef SWIFTPM_MODULE_BUNDLE
  // A SwiftPM resource bundle carries no version; report the MapLibre iOS
  // version whose API this package implements, as the framework's
  // Info.plist did.
  NSMutableDictionary *info = [bundle.infoDictionary mutableCopy] ?: [NSMutableDictionary dictionary];
  if (![info[@"CFBundleShortVersionString"] length]) {
    info[@"CFBundleShortVersionString"] = @MLN_NEXT_API_VERSION;
  }
  return info;
#else
  return bundle.infoDictionary;
#endif
}

+ (nullable NSString *)mgl_applicationBundleIdentifier {
  return [NSBundle mainBundle].bundleIdentifier;
}

@end

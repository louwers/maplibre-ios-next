// Based on platform/ios/src/UIImage+MLNAdditions.mm at ios-v7.0.0
//
// The CGImage conversions are ported from platform/darwin/core/image.mm, which
// classic MapLibre iOS took from the core's platform code.

#import <UIKit/UIKit.h>

#import "UIImage+MLNAdditions.h"

#import "MLNFFIMap+Style.h"
#import "MLNLoggingConfiguration_Private.h"
#import "NSBundle+MLNAdditions.h"

#include <vector>

const MLNExceptionName MLNResourceNotFoundException = @"MLNResourceNotFoundException";

BOOL MLNEdgeInsetsIsZero(UIEdgeInsets edgeInsets) {
  return edgeInsets.left == 0 && edgeInsets.top == 0 && edgeInsets.right == 0 &&
         edgeInsets.bottom == 0;
}

/// CGImageCreateWithMLNPremultipliedImage
static CGImageRef MLNCGImageCreateWithPremultipliedPixels(NSData *pixels, size_t width,
                                                          size_t height) {
  constexpr const size_t bitsPerComponent = 8;
  constexpr const size_t bytesPerPixel = 4;
  constexpr const size_t bitsPerPixel = bitsPerComponent * bytesPerPixel;
  const size_t bytesPerRow = bytesPerPixel * width;
  if (!width || !height || pixels.length < bytesPerRow * height) {
    return nil;
  }

  CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
  if (!provider) {
    return nil;
  }

  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  if (!colorSpace) {
    CGDataProviderRelease(provider);
    return nil;
  }

  const auto bitmapInfo = static_cast<uint32_t>(kCGBitmapByteOrderDefault) |
                          static_cast<uint32_t>(kCGImageAlphaPremultipliedLast);

  CGImageRef image = CGImageCreate(width, height, bitsPerComponent, bitsPerPixel, bytesPerRow,
                                   colorSpace, bitmapInfo, provider, NULL, false,
                                   kCGRenderingIntentDefault);
  CGColorSpaceRelease(colorSpace);
  CGDataProviderRelease(provider);
  return image;
}

/// MLNPremultipliedImageFromCGImage
static NSData *MLNPremultipliedPixelsFromCGImage(CGImageRef src, size_t *outWidth,
                                                 size_t *outHeight) {
  const size_t width = CGImageGetWidth(src);
  const size_t height = CGImageGetHeight(src);
  *outWidth = width;
  *outHeight = height;

  constexpr const size_t bitsPerComponent = 8;
  constexpr const size_t bytesPerPixel = 4;
  const size_t bytesPerRow = bytesPerPixel * width;
  // Zeroed, as mln::PremultipliedImage's storage was.
  NSMutableData *pixels = [NSMutableData dataWithLength:bytesPerRow * height];

  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  if (!colorSpace) {
    [NSException raise:NSInternalInconsistencyException format:@"CGColorSpaceCreateDeviceRGB failed"];
  }

  const auto bitmapInfo = static_cast<uint32_t>(kCGBitmapByteOrderDefault) |
                          static_cast<uint32_t>(kCGImageAlphaPremultipliedLast);

  CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, bitsPerComponent,
                                               bytesPerRow, colorSpace, bitmapInfo);
  CGColorSpaceRelease(colorSpace);
  if (!context) {
    [NSException raise:NSInternalInconsistencyException format:@"CGBitmapContextCreate failed"];
  }

  CGContextSetBlendMode(context, kCGBlendModeCopy);
  CGContextDrawImage(context, CGRectMake(0, 0, width, height), src);
  CGContextRelease(context);

  return pixels;
}

@implementation MLNStyleImageData
@end

@implementation UIImage (MLNAdditions)

- (nullable instancetype)initWithMLNStyleImage:(MLNFFIStyleImage *)styleImage {
  CGImageRef image =
      MLNCGImageCreateWithPremultipliedPixels(styleImage.pixels, styleImage.width, styleImage.height);
  if (!image) {
    return nil;
  }

  CGFloat scale = styleImage.pixelRatio;
  BOOL stretches = styleImage.stretchX.count || styleImage.stretchY.count;
  if (self = [self initWithCGImage:image scale:scale orientation:UIImageOrientationUp]) {
    if (styleImage.sdf) {
      self = [self imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }

    if (styleImage.hasContent) {
      mln_image_content content = styleImage.content;
      UIEdgeInsets capInsets = UIEdgeInsetsMake(content.top / scale, content.left / scale,
                                                self.size.height - content.bottom / scale,
                                                self.size.width - content.right / scale);
      UIImageResizingMode resizingMode = UIImageResizingModeTile;
      if (stretches) {
        resizingMode = UIImageResizingModeStretch;
      }
      self = [self resizableImageWithCapInsets:capInsets resizingMode:resizingMode];
    }
    if (stretches) {
      self = [self resizableImageWithCapInsets:self.capInsets
                                  resizingMode:UIImageResizingModeStretch];
    }
  }
  CGImageRelease(image);
  return self;
}

- (nullable instancetype)initWithMLNPremultipliedImage:(NSData *)pixels
                                                 width:(size_t)width
                                                height:(size_t)height
                                                 scale:(CGFloat)scale {
  CGImageRef image = MLNCGImageCreateWithPremultipliedPixels(pixels, width, height);
  if (!image) {
    return nil;
  }

  self = [self initWithCGImage:image scale:scale orientation:UIImageOrientationUp];

  CGImageRelease(image);
  return self;
}

- (MLNStyleImageData *)mgl_styleImageData {
  MLNStyleImageData *data = [[MLNStyleImageData alloc] init];
  NSMutableArray<NSValue *> *stretchX = [NSMutableArray array];
  NSMutableArray<NSValue *> *stretchY = [NSMutableArray array];
  if (self.resizingMode == UIImageResizingModeStretch) {
    mln_image_stretch x = {
        static_cast<float>(self.capInsets.left * self.scale),
        static_cast<float>((self.size.width - self.capInsets.right) * self.scale),
    };
    mln_image_stretch y = {
        static_cast<float>(self.capInsets.top * self.scale),
        static_cast<float>((self.size.height - self.capInsets.bottom) * self.scale),
    };
    [stretchX addObject:[NSValue valueWithBytes:&x objCType:@encode(mln_image_stretch)]];
    [stretchY addObject:[NSValue valueWithBytes:&y objCType:@encode(mln_image_stretch)]];
  }
  data.stretchX = stretchX;
  data.stretchY = stretchY;

  if (!MLNEdgeInsetsIsZero(self.capInsets)) {
    data.hasContent = YES;
    data.content = (mln_image_content){
        .left = static_cast<float>(self.capInsets.left * self.scale),
        .top = static_cast<float>(self.capInsets.top * self.scale),
        .right = static_cast<float>((self.size.width - self.capInsets.right) * self.scale),
        .bottom = static_cast<float>((self.size.height - self.capInsets.bottom) * self.scale),
    };
  }

  data.sdf = self.renderingMode == UIImageRenderingModeAlwaysTemplate;
  data.pixelRatio = static_cast<float>(self.scale);
  size_t width = 0, height = 0;
  data.pixels = [self mgl_premultipliedImageWithWidth:&width height:&height];
  data.width = (uint32_t)width;
  data.height = (uint32_t)height;
  return data;
}

- (BOOL)mgl_addToMap:(MLNFFIMap *)map withName:(NSString *)name {
  MLNStyleImageData *data = self.mgl_styleImageData;

  std::vector<mln_image_stretch> stretchX, stretchY;
  for (NSValue *value in data.stretchX) {
    mln_image_stretch stretch;
    [value getValue:&stretch];
    stretchX.push_back(stretch);
  }
  for (NSValue *value in data.stretchY) {
    mln_image_stretch stretch;
    [value getValue:&stretch];
    stretchY.push_back(stretch);
  }

  mln_style_image_options options = {sizeof(mln_style_image_options)};
  options.fields = MLN_STYLE_IMAGE_OPTION_PIXEL_RATIO | MLN_STYLE_IMAGE_OPTION_SDF;
  options.pixel_ratio = data.pixelRatio;
  options.sdf = data.sdf;
  if (!stretchX.empty()) {
    options.fields |= MLN_STYLE_IMAGE_OPTION_STRETCH_X;
    options.stretch_x = stretchX.data();
    options.stretch_x_count = stretchX.size();
  }
  if (!stretchY.empty()) {
    options.fields |= MLN_STYLE_IMAGE_OPTION_STRETCH_Y;
    options.stretch_y = stretchY.data();
    options.stretch_y_count = stretchY.size();
  }
  if (data.hasContent) {
    options.fields |= MLN_STYLE_IMAGE_OPTION_CONTENT;
    options.content = data.content;
  }

  NSString *message;
  mln_status status = [map setStyleImage:name
                                  pixels:data.pixels
                                   width:data.width
                                  height:data.height
                                 options:&options
                                 message:&message];
  if (status != MLN_STATUS_OK) {
    MLNLogError(@"Failed to add image %@ to the style: %@", name, message);
    return NO;
  }
  return YES;
}

- (NSData *)mgl_premultipliedImageWithWidth:(size_t *)width height:(size_t *)height {
  return MLNPremultipliedPixelsFromCGImage(self.CGImage, width, height);
}

+ (UIImage *)mgl_resourceImageNamed:(NSString *)imageName {
  UIImage *image = [UIImage imageNamed:imageName
                              inBundle:[NSBundle mgl_frameworkBundle]
         compatibleWithTraitCollection:nil];

  if (!image) {
    [NSException
         raise:MLNResourceNotFoundException
        format:@"The resource named “%@” could not be found in the Mapbox framework bundle.",
               imageName];
  }

  return image;
}

+ (UIImage *)NormalizedImage:(UIImage *)sourceImage {
  CGSize scaledSize = CGSizeMake(sourceImage.size.width * sourceImage.scale,
                                 sourceImage.size.height * sourceImage.scale);
  UIGraphicsBeginImageContextWithOptions(scaledSize, NO, UIScreen.mainScreen.scale);
  [sourceImage drawInRect:(CGRect){.origin = CGPointZero, .size = scaledSize}];
  UIImage *normalizedImage = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return normalizedImage;
}

- (BOOL)isDataEqualTo:(UIImage *)otherImage {
  NSData *leftData = UIImagePNGRepresentation([UIImage NormalizedImage:self]);
  NSData *rightData = UIImagePNGRepresentation([UIImage NormalizedImage:otherImage]);
  return [leftData isEqualToData:rightData];
}

@end

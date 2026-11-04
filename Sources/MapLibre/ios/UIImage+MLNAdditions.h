// Based on platform/ios/src/UIImage+MLNAdditions.h at ios-v7.0.0

#import <UIKit/UIKit.h>

#import "MLNTypes.h"

#import <MaplibreNativeC/maplibre_native_c.h>

NS_ASSUME_NONNULL_BEGIN

@class MLNFFIMap;
@class MLNFFIStyleImage;

FOUNDATION_EXTERN MLN_EXPORT MLNExceptionName const MLNResourceNotFoundException;

/// A style image as the C API takes it: premultiplied RGBA8 pixels and options.
@interface MLNStyleImageData : NSObject
@property (nonatomic) uint32_t width;
@property (nonatomic) uint32_t height;
@property (nonatomic, copy) NSData *pixels;
@property (nonatomic) float pixelRatio;
@property (nonatomic) BOOL sdf;
@property (nonatomic, copy) NSArray<NSValue *> *stretchX;
@property (nonatomic, copy) NSArray<NSValue *> *stretchY;
@property (nonatomic) BOOL hasContent;
@property (nonatomic) mln_image_content content;
@end

@interface UIImage (MLNAdditions)

/// The image for a style image, as classic built it from an mln::style::Image.
- (nullable instancetype)initWithMLNStyleImage:(MLNFFIStyleImage *)styleImage;

/// The image for premultiplied RGBA8 pixels.
- (nullable instancetype)initWithMLNPremultipliedImage:(NSData *)pixels
                                                 width:(size_t)width
                                                height:(size_t)height
                                                 scale:(CGFloat)scale;

/// The style image for the receiver, as mgl_styleImageWithIdentifier: built it:
/// template images are SDF, cap insets become stretch areas and content.
- (MLNStyleImageData *)mgl_styleImageData;

/// Adds the receiver to the map's style under `name`.
- (BOOL)mgl_addToMap:(MLNFFIMap *)map withName:(NSString *)name;

/// Premultiplied RGBA8 pixels of the receiver at its scale.
- (NSData *)mgl_premultipliedImageWithWidth:(size_t *)width height:(size_t *)height;

+ (UIImage *)mgl_resourceImageNamed:(NSString *)imageName;

- (BOOL)isDataEqualTo:(UIImage *)otherImage;

@end

NS_ASSUME_NONNULL_END

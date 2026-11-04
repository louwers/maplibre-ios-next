// Based on platform/darwin/src/MLNImageSource.mm at ios-v7.0.0

#import "MLNImageSource.h"

#import "MLNGeometry_Private.h"
#import "MLNLoggingConfiguration_Private.h"
#import "MLNSource_Private.h"
#import "MLNTileSource_Private.h"
#import "NSURL+MLNAdditions.h"
#if TARGET_OS_IPHONE
#import "UIImage+MLNAdditions.h"
#else
#import "NSImage+MLNAdditions.h"
#endif

#import "MLNFFIMap+Style.h"
#import "MLNStyle_Private.h"

@interface MLNImageSource ()
- (instancetype)initWithIdentifier:(NSString *)identifier
                    coordinateQuad:(MLNCoordinateQuad)coordinateQuad NS_DESIGNATED_INITIALIZER;

@end

/// Premultiplied RGBA8 pixels for an image source, as the C API takes them.
/// Classic set an empty mln::PremultipliedImage for a nil image; the C API
/// refuses empty images, so a nil image becomes one transparent pixel.
static NSData *MLNImageSourcePixels(MLNImage *image, uint32_t *width, uint32_t *height) {
  if (image) {
    size_t w = 0, h = 0;
    NSData *pixels = [image mgl_premultipliedImageWithWidth:&w height:&h];
    if (w && h) {
      *width = (uint32_t)w;
      *height = (uint32_t)h;
      return pixels;
    }
  }
  *width = 1;
  *height = 1;
  return [NSMutableData dataWithLength:4];
}

@implementation MLNImageSource {
  // The configuration of a pending source.
  std::array<mln_lat_lng, 4> _coordinates;
  NSString *_pendingURL;
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                    coordinateQuad:(MLNCoordinateQuad)coordinateQuad {
  const auto coordsArray = MLNLatLngArrayFromCoordinateQuad(coordinateQuad);
  if (self = [super initWithPendingIdentifier:identifier]) {
    _coordinates = coordsArray;
  }
  return self;
}

- (mln_status)mgl_addToMap:(MLNFFIMap *)map message:(NSString **)message {
  mln_map handle = map.handle;
  NSString *identifier = self.identifier;
  std::array<mln_lat_lng, 4> coordinates = _coordinates;
  if (_pendingURL) {
    NSString *url = _pendingURL;
    return [map call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
      return mln_map_add_image_source_url(handle, MLNFFIBufferView(identifier), coordinates.data(),
                                          coordinates.size(), MLNFFIBufferView(url), completion,
                                          diagnostic);
    }
             consume:nil
             message:message];
  }
  uint32_t width, height;
  NSData *pixels = MLNImageSourcePixels(_image, &width, &height);
  return [map call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    mln_premultiplied_rgba8_image image = {sizeof(mln_premultiplied_rgba8_image)};
    image.width = width;
    image.height = height;
    image.stride = width * 4;
    image.pixels = (const uint8_t *)pixels.bytes;
    image.byte_length = pixels.length;
    return mln_map_add_image_source_image(handle, MLNFFIBufferView(identifier), coordinates.data(),
                                          coordinates.size(), &image, completion, diagnostic);
  }
           consume:nil
           message:message];
}

- (void)mgl_willDetachFromMap:(MLNFFIMap *)map {
  _coordinates = MLNLatLngArrayFromCoordinateQuad(self.coordinates);
  if (!_image && !_pendingURL) {
    NSString *url = [map styleSourceWithIdentifier:self.identifier].URL;
    _pendingURL = url.length ? url : nil;
  }
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                    coordinateQuad:(MLNCoordinateQuad)coordinateQuad
                               URL:(NSURL *)url {
  self = [self initWithIdentifier:identifier coordinateQuad:coordinateQuad];
  self.URL = url;
  return self;
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                    coordinateQuad:(MLNCoordinateQuad)coordinateQuad
                             image:(MLNImage *)image {
  self = [self initWithIdentifier:identifier coordinateQuad:coordinateQuad];
  self.image = image;

  return self;
}

- (NSURL *)URL {
  MLNAssertStyleSourceIsValid();
  NSString *url;
  if (self.mgl_style) {
    url = [self.mgl_map styleSourceWithIdentifier:self.identifier].URL;
  } else {
    url = _pendingURL;
  }
  return url.length ? [NSURL URLWithString:url] : nil;
}

- (void)setURL:(NSURL *)url {
  MLNAssertStyleSourceIsValid();
  if (url) {
    NSString *urlString = url.mgl_URLByStandardizingScheme.absoluteString;
    if (MLNFFIMap *map = self.mgl_map) {
      mln_map handle = map.handle;
      NSString *identifier = self.identifier;
      [map perform:@"set the URL of an image source"
            submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
              return mln_map_set_image_source_url(handle, MLNFFIBufferView(identifier),
                                                  MLNFFIBufferView(urlString), completion,
                                                  diagnostic);
            }];
    } else {
      _pendingURL = urlString;
    }
    _image = nil;
  } else {
    self.image = nil;
  }
}

- (void)setImage:(MLNImage *)image {
  MLNAssertStyleSourceIsValid();
  if (MLNFFIMap *map = self.mgl_map) {
    uint32_t width, height;
    NSData *pixels = MLNImageSourcePixels(image, &width, &height);
    mln_map handle = map.handle;
    NSString *identifier = self.identifier;
    [map perform:@"set the image of an image source"
          submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
            mln_premultiplied_rgba8_image rgba = {sizeof(mln_premultiplied_rgba8_image)};
            rgba.width = width;
            rgba.height = height;
            rgba.stride = width * 4;
            rgba.pixels = (const uint8_t *)pixels.bytes;
            rgba.byte_length = pixels.length;
            return mln_map_set_image_source_image(handle, MLNFFIBufferView(identifier), &rgba,
                                                  completion, diagnostic);
          }];
  } else {
    _pendingURL = nil;
  }
  _image = image;
}

- (MLNCoordinateQuad)coordinates {
  MLNAssertStyleSourceIsValid();
  MLNFFIMap *map = self.mgl_map;
  if (!map) {
    return MLNCoordinateQuadFromLatLngArray(_coordinates);
  }
  mln_map handle = map.handle;
  NSString *identifier = self.identifier;
  __block std::array<mln_lat_lng, 4> coordinates = _coordinates;
  [map call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_get_image_source_coordinates(handle, MLNFFIBufferView(identifier), completion,
                                                diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        for (size_t i = 0; i < 4 && i < result->value_count; i++) {
          coordinates[i] = *MLN_STRIDED_AT(mln_lat_lng, result->value, result->value_size, i);
        }
      }
      message:nil];
  return MLNCoordinateQuadFromLatLngArray(coordinates);
}

- (void)setCoordinates:(MLNCoordinateQuad)coordinateQuad {
  MLNAssertStyleSourceIsValid();
  std::array<mln_lat_lng, 4> coordinates = MLNLatLngArrayFromCoordinateQuad(coordinateQuad);
  MLNFFIMap *map = self.mgl_map;
  if (!map) {
    _coordinates = coordinates;
    return;
  }
  mln_map handle = map.handle;
  NSString *identifier = self.identifier;
  [map perform:@"set the coordinates of an image source"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_map_set_image_source_coordinates(handle, MLNFFIBufferView(identifier),
                                                      coordinates.data(), coordinates.size(),
                                                      completion, diagnostic);
        }];
}

- (NSString *)description {
  if (self.mgl_isValid) {
    return [NSString
        stringWithFormat:@"<%@: %p; identifier = %@; coordinates = %@; URL = %@; image = %@>",
                         NSStringFromClass([self class]), (void *)self, self.identifier,
                         MLNStringFromCoordinateQuad(self.coordinates), self.URL, self.image];
  } else {
    return [NSString
        stringWithFormat:
            @"<%@: %p; identifier = %@; coordinates = <unknown>; URL = <unknown>; image = %@>",
            NSStringFromClass([self class]), (void *)self, self.identifier, self.image];
  }
}

- (NSString *)attributionHTMLString {
  if (!self.mgl_isValid) {
    MLNAssert(0, @"Source with identifier `%@` was invalidated after a style change",
              self.identifier);
    return nil;
  }

  // Image sources have no tile set, so the core reported no attribution.
  NSString *attribution = [self.mgl_map styleSourceWithIdentifier:self.identifier].attribution;
  return attribution.length ? attribution : nil;
}

@end

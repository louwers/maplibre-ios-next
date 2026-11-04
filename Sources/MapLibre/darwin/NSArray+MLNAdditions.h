// Based on platform/darwin/src/NSArray+MLNAdditions.h at ios-v7.0.0

#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>

#include <vector>

@interface NSArray (MLNAdditions)

/**
 The array as a JSON array, as classic's std::vector<mln::Value> held it:
 nested dictionaries and arrays are converted recursively, and other values as
 `-[NSExpression mgl_constantJSONValue]` converts constants.
 */
- (NSArray *)mgl_vector;

/** Returns a string resulting from inserting a separator between each attributed string in the
 * array */
- (NSAttributedString *)mgl_attributedComponentsJoinedByString:(NSString *)separator;

/**
 Converts std::vector<CLLocationCoordinate> into an NSArray containing dictionary
 representations of coordinates with the following structure:
 [{"latitude": lat, "longitude": lng}]
 */
+ (NSArray *)mgl_coordinatesFromCoordinates:(std::vector<CLLocationCoordinate2D>)coords;

/**
 Converts the receiver into a std::vector<CLLocationCoordinate>.
 Receiver must conform to the following structure:
 [{"latitude": lat, "longitude": lng}]
 */
- (std::vector<CLLocationCoordinate2D>)mgl_coordinates;

@end

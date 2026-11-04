// Copied from platform/ios/test/MLNMockGestureRecognizers.h at ios-v7.0.0 by Parity/Tests/Upstream/import-upstream.py.
// See ADAPTATIONS.md before editing.

@import MapLibre;

#import <UIKit/UIKit.h>

@interface UIPinchGestureRecognizerMock : UIPinchGestureRecognizer
@property (nonatomic, readwrite) CGFloat velocity;
@property (nonatomic) CGPoint locationInViewOverride;
@property (nonatomic, readwrite) UIGestureRecognizerState state;
@end

@interface UIRotationGestureRecognizerMock : UIRotationGestureRecognizer
@property (nonatomic, readwrite) UIGestureRecognizerState state;
@end

@interface UITapGestureRecognizerMock : UITapGestureRecognizer
@property (strong, nonatomic) UIView *mockTappedView;
@property (assign) CGPoint mockTappedPoint;
@end

@interface UILongPressGestureRecognizerMock : UILongPressGestureRecognizer
@property (nonatomic, readwrite) UIGestureRecognizerState state;
@property (assign) CGPoint mockTappedPoint;
@end

@interface UIPanGestureRecognizerMock : UIPanGestureRecognizer
@property (nonatomic, readwrite) UIGestureRecognizerState state;
@property (assign) CGPoint firstFingerPoint;
@property (assign) CGPoint secondFingerPoint;
@property (nonatomic, readwrite) NSUInteger numberOfTouches;
@end

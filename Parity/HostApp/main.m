// A minimal app that hosts the parity tests. Tests that need a window put
// their views into the host's window, as MapLibre's own tests do.

#import <UIKit/UIKit.h>

@import MapLibre;

@interface ParityAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation ParityAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  UIViewController *root = [[UIViewController alloc] init];
  root.view.backgroundColor = UIColor.whiteColor;
  // Link the framework into the host, so hosted tests share its one copy.
  root.view.accessibilityIdentifier = NSStringFromClass([MLNMapView class]);
  self.window.rootViewController = root;
  [self.window makeKeyAndVisible];
  return YES;
}

@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([ParityAppDelegate class]));
  }
}

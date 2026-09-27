#import <UIKit/UIKit.h>

// Reads the DynamicIsland settings bundle's preferences (written by the
// Settings.app page) and exposes them to the tweak. Call -reload whenever
// the Darwin notification "com.yourname.dynamicisland/prefschanged" fires.
@interface DIPreferences : NSObject

+ (instancetype)shared;
- (void)reload;

@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) CGFloat scale;       // 0.7...1.3, default 1.0
@property (nonatomic, readonly) CGFloat opacity;     // 0.4...1.0, default 1.0
@property (nonatomic, readonly) CGFloat offsetX;     // -60...60 pt, default 0
@property (nonatomic, readonly) CGFloat offsetY;     // -20...20 pt, default 0
@property (nonatomic, readonly, strong) UIColor *pillColor; // compact + expanded-call background

@end

#import "DIPreferences.h"

static NSString * const kDIPrefsDomain = @"com.yourname.dynamicislandprefs";

static CGFloat DIPrefNumber(NSString *key, CGFloat fallback) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kDIPrefsDomain);
    if (!value) return fallback;

    CGFloat result = fallback;
    CFTypeID type = CFGetTypeID(value);
    if (type == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &result);
    } else if (type == CFBooleanGetTypeID()) {
        result = CFBooleanGetValue((CFBooleanRef)value) ? 1.0 : 0.0;
    }
    CFRelease(value);
    return result;
}

@implementation DIPreferences

+ (instancetype)shared {
    static DIPreferences *shared;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        shared = [self new];
        [shared reload];
    });
    return shared;
}

- (void)reload {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDIPrefsDomain);

    _enabled = DIPrefNumber(@"DIEnabled", 1) != 0;
    _scale   = DIPrefNumber(@"DIScale", 1.0);
    _opacity = DIPrefNumber(@"DIOpacity", 1.0);
    _offsetX = DIPrefNumber(@"DIOffsetX", 0);
    _offsetY = DIPrefNumber(@"DIOffsetY", 0);

    CGFloat r = DIPrefNumber(@"DIColorRed", 0) / 255.0;
    CGFloat g = DIPrefNumber(@"DIColorGreen", 0) / 255.0;
    CGFloat b = DIPrefNumber(@"DIColorBlue", 0) / 255.0;
    _pillColor = [UIColor colorWithRed:r green:g blue:b alpha:1.0];
}

@end

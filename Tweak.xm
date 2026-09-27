#import <UIKit/UIKit.h>
#import "DIActivity.h"
#import "DIActivityCenter.h"
#import "DynamicIslandWindow.h"
#import "DIPreferences.h"

#pragma mark - Private MediaRemote declarations
// MediaRemote.framework is already loaded inside SpringBoard; we're just
// declaring the symbols we call so the compiler/linker know their signatures.

typedef void (^DIMediaInfoHandler)(NSDictionary *information);
extern "C" void MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_queue_t queue);
extern "C" void MRMediaRemoteGetNowPlayingInfo(dispatch_queue_t queue, DIMediaInfoHandler completion);
extern NSString * const kMRMediaRemoteNowPlayingInfoDidChangeNotification;
extern NSString * const kMRMediaRemoteNowPlayingInfoTitle;
extern NSString * const kMRMediaRemoteNowPlayingInfoArtist;
extern NSString * const kMRMediaRemoteNowPlayingInfoIsPlaying;

static NSString * const kMediaActivityID = @"media";
static NSString * const kCallActivityID  = @"call";

#pragma mark - Media: only shown while something is actually playing

static void DIRefreshNowPlaying(void) {
    MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(NSDictionary *info) {
        NSString *title  = info[kMRMediaRemoteNowPlayingInfoTitle];
        NSString *artist = info[kMRMediaRemoteNowPlayingInfoArtist];
        BOOL playing = [info[kMRMediaRemoteNowPlayingInfoIsPlaying] boolValue];

        if (playing && title.length) {
            DIActivity *a = [DIActivity activityWithKind:DIActivityKindMedia identifier:kMediaActivityID];
            a.title = artist.length ? [NSString stringWithFormat:@"%@ · %@", title, artist] : title;
            a.symbolName = @"music.note";
            a.autoDismissAfter = 0; // stays up as long as it's playing
            [[DIActivityCenter sharedCenter] beginActivity:a];
        } else {
            // Short grace period so a brief pause/track-skip blip doesn't
            // make the island flicker off and back on.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(NSDictionary *recheck) {
                    if (![recheck[kMRMediaRemoteNowPlayingInfoIsPlaying] boolValue]) {
                        [[DIActivityCenter sharedCenter] endActivityWithIdentifier:kMediaActivityID];
                    }
                });
            });
        }
    });
}

#pragma mark - Incoming call example
// IMPORTANT: SBTelephonyManager's private selectors change across iOS
// versions. Class-dump SpringBoard on your target firmware and confirm the
// real class/method names before relying on this — treat it as a template.
// Swap in the caller's name from `call` once you've confirmed how to read it.

%hook SBTelephonyManager

- (void)_callDidBegin:(id)call {
    %orig;
    DIActivity *a = [DIActivity activityWithKind:DIActivityKindCall identifier:kCallActivityID];
    a.title = @"Incoming Call";
    a.showsCallActions = YES;
    a.isTimed = YES;
    a.referenceDate = [NSDate date];
    a.autoDismissAfter = 0;
    [[DIActivityCenter sharedCenter] beginActivity:a];
}

- (void)_callDidEnd:(id)call {
    %orig;
    [[DIActivityCenter sharedCenter] endActivityWithIdentifier:kCallActivityID];
}

%end

#pragma mark - Generic bridge for everything else (timer, navigation, AirDrop,
#pragma mark   recording, accessory...) — "and more" from the reference image.
// Darwin notifications carry no payload, so a sender writes a small plist
// here first, then pings this notification name.
//
// Example, from any hook/process on-device:
//
//   NSDictionary *state = @{ @"kind": @"timer", @"id": @"timer-1",
//                             @"text": @"Timer", @"symbol": @"timer",
//                             @"countdown_seconds": @(60) };
//   [state writeToFile:DI_STATE_PATH atomically:YES];
//   CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
//                                         CFSTR("com.yourname.dynamicisland/ping"), NULL, NULL, YES);
//
// To end it early: write @{ @"id": @"timer-1", @"end": @YES } and ping again.

#define DI_STATE_PATH  @"/var/mobile/Library/Caches/com.yourname.dynamicisland/state.plist"
#define DI_DARWIN_PING CFSTR("com.yourname.dynamicisland/ping")

static void DIHandlePing(CFNotificationCenterRef center, void *observer, CFStringRef name,
                          const void *object, CFDictionaryRef userInfo) {
    NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:DI_STATE_PATH];
    if (!state) return;

    NSString *identifier = state[@"id"] ?: (state[@"kind"] ?: @"generic");

    if ([state[@"end"] boolValue]) {
        [[DIActivityCenter sharedCenter] endActivityWithIdentifier:identifier];
        return;
    }

    NSString *kindName = state[@"kind"] ?: @"generic";
    DIActivityKind kind = DIActivityKindGeneric;
    if ([kindName isEqualToString:@"timer"])           kind = DIActivityKindTimer;
    else if ([kindName isEqualToString:@"navigation"]) kind = DIActivityKindNavigation;
    else if ([kindName isEqualToString:@"airdrop"])    kind = DIActivityKindAirDrop;
    else if ([kindName isEqualToString:@"recording"])  kind = DIActivityKindRecording;
    else if ([kindName isEqualToString:@"accessory"])  kind = DIActivityKindAccessory;

    DIActivity *a = [DIActivity activityWithKind:kind identifier:identifier];
    a.title = state[@"text"] ?: @"";
    a.symbolName = state[@"symbol"] ?: @"bell.fill";
    a.autoDismissAfter = [(state[@"duration"] ?: @3.0) doubleValue];
    if (state[@"countdown_seconds"]) {
        a.isTimed = YES;
        a.countsDown = YES;
        a.referenceDate = [NSDate dateWithTimeIntervalSinceNow:[state[@"countdown_seconds"] doubleValue]];
        a.autoDismissAfter = 0; // ends when the countdown/timer hook ends it explicitly
    }
    [[DIActivityCenter sharedCenter] beginActivity:a];
}

static void DIPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                            const void *object, CFDictionaryRef userInfo) {
    [[DIPreferences shared] reload];
    // Re-render whatever's currently on top so a toggle/slider takes effect
    // immediately, without waiting for the next activity change.
    [[DynamicIslandWindow sharedInstance] renderActivity:[[DIActivityCenter sharedCenter] topActivity] animated:YES];
}

%ctor {
    @autoreleasepool {
        [DIPreferences shared]; // load settings before anything can render
        [DynamicIslandWindow sharedInstance]; // warm up, stays invisible until an activity begins

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DIPrefsChanged,
                                         CFSTR("com.yourname.dynamicisland/prefschanged"), NULL,
                                         CFNotificationSuspensionBehaviorDeliverImmediately);

        MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_get_main_queue());
        [[NSNotificationCenter defaultCenter] addObserverForName:kMRMediaRemoteNowPlayingInfoDidChangeNotification
                                                           object:nil
                                                            queue:nil
                                                       usingBlock:^(NSNotification *note) {
            DIRefreshNowPlaying();
        }];

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DIHandlePing,
                                         DI_DARWIN_PING, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}

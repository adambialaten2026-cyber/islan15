#import "DynamicIslandWindow.h"
#import "DIActivityCenter.h"
#import "DIPreferences.h"

static const CGFloat kCompactHeight     = 36;
static const CGFloat kExpandedCallW     = 320;
static const CGFloat kExpandedCallH     = 66;
static const CGFloat kMinCompactWidth   = 96;
static const CGFloat kMaxCompactWidth   = 260;

@interface DynamicIslandWindow ()
@property (nonatomic, strong) UIView *pill;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *clockLabel;
@property (nonatomic, strong) UIView *progressTrack;
@property (nonatomic, strong) UIView *progressFill;
@property (nonatomic, strong) UIView *avatarBadge;
@property (nonatomic, strong) UIButton *declineButton;
@property (nonatomic, strong) UIButton *acceptButton;
@property (nonatomic, strong) DIActivity *currentActivity;
@property (nonatomic, strong) NSTimer *clockTimer;
@end

@implementation DynamicIslandWindow

+ (instancetype)sharedInstance {
    static DynamicIslandWindow *shared;
    static dispatch_once_t token;
    dispatch_once(&token, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super initWithFrame:UIScreen.mainScreen.bounds];
    if (self) {
        self.windowLevel = UIWindowLevelStatusBar + 1000;
        self.backgroundColor = UIColor.clearColor;
        self.hidden = NO;
        // Stays "on" so the call buttons can receive touches, but -hitTest:
        // below makes every other point pass straight through to whatever
        // is underneath, so normal use is never blocked.
        self.userInteractionEnabled = YES;

        [self _buildViews];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                  selector:@selector(_activityChanged:)
                                                      name:DIActivityCenterDidChangeNotification
                                                    object:nil];
    }
    return self;
}

#pragma mark - View construction

- (void)_buildViews {
    _pill = [UIView new];
    _pill.backgroundColor = UIColor.blackColor;
    _pill.clipsToBounds = YES;
    _pill.alpha = 0; // idle = fully invisible
    [self addSubview:_pill];

    _iconView = [UIImageView new];
    _iconView.tintColor = UIColor.whiteColor;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    [_pill addSubview:_iconView];

    _titleLabel = [UILabel new];
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_pill addSubview:_titleLabel];

    _clockLabel = [UILabel new];
    _clockLabel.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    _clockLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    _clockLabel.textAlignment = NSTextAlignmentRight;
    [_pill addSubview:_clockLabel];

    _progressTrack = [UIView new];
    _progressTrack.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25];
    _progressTrack.layer.cornerRadius = 1.5;
    _progressTrack.hidden = YES;
    [_pill addSubview:_progressTrack];

    _progressFill = [UIView new];
    _progressFill.backgroundColor = UIColor.whiteColor;
    _progressFill.layer.cornerRadius = 1.5;
    [_progressTrack addSubview:_progressFill];

    _avatarBadge = [UIView new];
    _avatarBadge.backgroundColor = [UIColor colorWithWhite:1 alpha:0.15];
    _avatarBadge.hidden = YES;
    [_pill addSubview:_avatarBadge];

    _declineButton = [self _circleButtonWithSymbol:@"phone.down.fill"
                                              color:[UIColor colorWithRed:1 green:0.23 blue:0.19 alpha:1]];
    _acceptButton  = [self _circleButtonWithSymbol:@"phone.fill"
                                              color:[UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1]];
    [_declineButton addTarget:self action:@selector(_declineTapped) forControlEvents:UIControlEventTouchUpInside];
    [_acceptButton addTarget:self action:@selector(_acceptTapped) forControlEvents:UIControlEventTouchUpInside];
    _declineButton.hidden = _acceptButton.hidden = YES;
    [_pill addSubview:_declineButton];
    [_pill addSubview:_acceptButton];
}

- (UIButton *)_circleButtonWithSymbol:(NSString *)symbol color:(UIColor *)color {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.backgroundColor = color;
    [b setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    b.tintColor = UIColor.whiteColor;
    return b;
}

#pragma mark - Hit testing: transparent except for live call buttons

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.currentActivity.showsCallActions || _declineButton.hidden) return nil;
    CGPoint p1 = [self convertPoint:point toView:_declineButton];
    CGPoint p2 = [self convertPoint:point toView:_acceptButton];
    if (CGRectContainsPoint(_declineButton.bounds, p1)) return _declineButton;
    if (CGRectContainsPoint(_acceptButton.bounds, p2))  return _acceptButton;
    return nil;
}

#pragma mark - Activity -> render

- (void)_activityChanged:(NSNotification *)note {
    [self renderActivity:note.object animated:YES];
}

- (void)renderActivity:(DIActivity *)activity animated:(BOOL)animated {
    dispatch_async(dispatch_get_main_queue(), ^{
        DIPreferences *prefs = [DIPreferences shared];
        if (!prefs.enabled) activity = nil; // hard off-switch, regardless of what's active

        self.currentActivity = activity;
        [self.clockTimer invalidate];
        self.clockTimer = nil;

        if (!activity) {
            [self _collapseAnimated:animated];
            return;
        }

        BOOL expanded = activity.showsCallActions;
        CGRect target = expanded ? [self _expandedCallFrame] : [self _compactFrameFor:activity];
        target.origin.x += prefs.offsetX;
        target.origin.y += prefs.offsetY;
        [self _applyContentForActivity:activity expanded:expanded];

        void (^apply)(void) = ^{
            self.pill.frame = target;
            self.pill.layer.cornerRadius = target.size.height / 2;
            self.pill.alpha = prefs.opacity;
            self.pill.transform = CGAffineTransformMakeScale(prefs.scale, prefs.scale);
            [self _layoutContentExpanded:expanded];
        };

        if (animated) {
            [UIView animateWithDuration:0.5
                                  delay:0
                 usingSpringWithDamping:0.78
                  initialSpringVelocity:0.4
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:apply
                             completion:nil];
        } else {
            apply();
        }

        if (activity.isTimed) {
            self.clockTimer = [NSTimer scheduledTimerWithTimeInterval:1
                                                                 target:self
                                                               selector:@selector(_tickClock)
                                                               userInfo:nil
                                                                repeats:YES];
            [self _tickClock];
        }
    });
}

#pragma mark - Sizing

- (CGRect)_compactFrameFor:(DIActivity *)activity {
    CGFloat textWidth = [activity.title sizeWithAttributes:@{NSFontAttributeName: _titleLabel.font}].width;
    CGFloat clockWidth = activity.isTimed ? 40 : 0;
    CGFloat width = 16 + 20 + 8 + textWidth + (clockWidth > 0 ? 8 + clockWidth : 0) + 14;
    width = MAX(kMinCompactWidth, MIN(kMaxCompactWidth, width));
    CGFloat topInset = MAX(UIApplication.sharedApplication.keyWindow.safeAreaInsets.top, 20);
    return CGRectMake((self.bounds.size.width - width) / 2, topInset - kCompactHeight - 3, width, kCompactHeight);
}

- (CGRect)_expandedCallFrame {
    CGFloat topInset = MAX(UIApplication.sharedApplication.keyWindow.safeAreaInsets.top, 20);
    return CGRectMake((self.bounds.size.width - kExpandedCallW) / 2, topInset - 4, kExpandedCallW, kExpandedCallH);
}

#pragma mark - Content

- (void)_applyContentForActivity:(DIActivity *)activity expanded:(BOOL)expanded {
    _pill.backgroundColor = [DIPreferences shared].pillColor;

    _titleLabel.text = activity.title;
    _titleLabel.font = expanded ? [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]
                                 : [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];

    _clockLabel.hidden = !activity.isTimed || expanded;
    _iconView.hidden = expanded;
    _iconView.image = activity.symbolName ? [UIImage systemImageNamed:activity.symbolName] : nil;
    _iconView.tintColor = activity.accentColor ?: UIColor.whiteColor;

    _avatarBadge.hidden = !expanded;
    _declineButton.hidden = _acceptButton.hidden = !expanded;
    _progressTrack.hidden = expanded || activity.progress < 0;
}

- (void)_layoutContentExpanded:(BOOL)expanded {
    CGSize s = _pill.bounds.size;

    if (expanded) {
        _avatarBadge.frame = CGRectMake(14, (s.height - 40) / 2, 40, 40);
        _avatarBadge.layer.cornerRadius = 20;
        _titleLabel.frame = CGRectMake(64, 10, s.width - 64 - 100, 20);
        _declineButton.frame = CGRectMake(s.width - 86, (s.height - 34) / 2, 34, 34);
        _acceptButton.frame  = CGRectMake(s.width - 44, (s.height - 34) / 2, 34, 34);
        _declineButton.layer.cornerRadius = _acceptButton.layer.cornerRadius = 17;
    } else {
        _iconView.frame = CGRectMake(12, (s.height - 20) / 2, 20, 20);
        CGFloat clockW = _clockLabel.hidden ? 0 : 40;
        _titleLabel.frame = CGRectMake(38, 0, s.width - 38 - clockW - 14, s.height);
        _clockLabel.frame = CGRectMake(s.width - 14 - clockW, 0, clockW, s.height);
        _progressTrack.frame = CGRectMake(38, s.height - 8, s.width - 38 - 14, 3);
        if (!_progressTrack.hidden && self.currentActivity.progress >= 0) {
            _progressFill.frame = CGRectMake(0, 0, _progressTrack.bounds.size.width * self.currentActivity.progress, 3);
        }
    }
}

- (void)_collapseAnimated:(BOOL)animated {
    void (^apply)(void) = ^{
        self.pill.alpha = 0;
        CGRect f = self.pill.frame;
        self.pill.frame = CGRectMake(CGRectGetMidX(f) - 4, CGRectGetMidY(f) - 4, 8, 8);
    };
    if (animated) {
        [UIView animateWithDuration:0.3 animations:apply];
    } else {
        apply();
    }
}

- (void)_tickClock {
    DIActivity *a = self.currentActivity;
    if (!a.referenceDate) return;
    NSTimeInterval interval = a.countsDown ? [a.referenceDate timeIntervalSinceNow]
                                            : -[a.referenceDate timeIntervalSinceNow];
    interval = MAX(0, interval);
    NSInteger m = (NSInteger)interval / 60, sec = (NSInteger)interval % 60;
    _clockLabel.text = [NSString stringWithFormat:@"%02ld:%02ld", (long)m, (long)sec];
}

#pragma mark - Call button actions
// These currently just clear the pill locally. Wiring them to really answer
// or decline the call requires calling into SpringBoard/CallKit's own
// private answer/decline method for your iOS version (find it with
// class-dump, same caveat as the call hook in Tweak.xm).

- (void)_acceptTapped {
    [[DIActivityCenter sharedCenter] endActivityWithIdentifier:self.currentActivity.identifier];
}

- (void)_declineTapped {
    [[DIActivityCenter sharedCenter] endActivityWithIdentifier:self.currentActivity.identifier];
}

@end

// 8ubah — Discord (iOS) local feature set (injected dylib)
// Pure Objective-C runtime + symbol-pointer rebinding: no Substrate / no Logos, works with Feather / ESign / Sideloadly injection.
// Features: mic voice changer, Stereo (play a file through the mic), voice isolation ALWAYS off (system VPIO/AGC + Discord's own
// Krisp / echo / noise / AGC engine options), chat background, quick messages, in-app diagnostics (Diag tab).
// UNTESTED on a device: class names are tunable from the Diag tab.

// =====================================================================================================================
// RULE FOR ANY AI / EDITOR THAT MODIFIES THIS FILE  (the owner asked for this, do not break it)
//   NO EXPLANATORY TEXT IN THE UI. Never add help / description / hint / tip / note / warning labels under a title, switch, slider,
//   button or inside a card, in ANY tab. Every control gets only its own SHORT name.
//   Allowed: short names; short live STATUS lines that show a current value ("Ready", "Saved: 3", "Default ✓"); toasts and alerts that
//   follow an action; text-field placeholders; error messages.
//   New feature? Put the explanation in your reply to the owner, never in the app. If you find an explanation label while editing, delete it.
// =====================================================================================================================
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <PhotosUI/PhotosUI.h>
#import <ImageIO/ImageIO.h>
#import <CommonCrypto/CommonDigest.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <math.h>
#include <ctype.h>
#include <strings.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreMedia/CoreMedia.h>
#import <os/lock.h>

#pragma mark - Config / storage

#define RY_CFG @"ry.cfg.v1"
#define RY_ROOM_DEFAULT @"ChatViewController" // matches DCDChatViewController, DiscordChat.ChatViewController and their containers; changeable in Diag

static NSMutableDictionary *gCfg;

static void RYLoad(void) {
    @try {
        NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:RY_CFG];
        gCfg = d ? [d mutableCopy] : [NSMutableDictionary new];
    } @catch (__unused id e) { gCfg = [NSMutableDictionary new]; }
}
static id CF(NSString *k, id def) { id v = gCfg[k]; return v ?: def; }
static void CS(NSString *k, id v) {
    if (v) gCfg[k] = v; else [gCfg removeObjectForKey:k];
    @try { [[NSUserDefaults standardUserDefaults] setObject:gCfg forKey:RY_CFG]; } @catch (__unused id e) {}
}
static NSString *RYDir(NSString *sub) {
    NSString *b = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"8ubah"] copy];
    if (sub) b = [b stringByAppendingPathComponent:sub];
    [[NSFileManager defaultManager] createDirectoryAtPath:b withIntermediateDirectories:YES attributes:nil error:nil];
    return b;
}

#pragma mark - Language / colours

static BOOL RYAr(void) {
    NSString *l = CF(@"lang", @"ar"); // Arabic-first default
    if ([l isEqual:@"ar"]) return YES;
    if ([l isEqual:@"en"]) return NO;
    return [[[NSLocale preferredLanguages].firstObject lowercaseString] hasPrefix:@"ar"];
}
#define T(ar, en) (RYAr() ? (ar) : (en))

static UIColor *RYHex(NSString *h) {
    if (![h isKindOfClass:NSString.class]) return UIColor.blackColor;
    NSString *s = [h stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned v = 0; [[NSScanner scannerWithString:s] scanHexInt:&v];
    return [UIColor colorWithRed:((v >> 16) & 255) / 255.0 green:((v >> 8) & 255) / 255.0 blue:(v & 255) / 255.0 alpha:1];
}
static NSString *RYHexFrom(UIColor *c) {
    CGFloat r = 0, g = 0, b = 0, a = 0; [c getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)round(r * 255), (int)round(g * 255), (int)round(b * 255)];
}
static NSArray *RYAccents(void) { return @[@"#7C5CFF", @"#2DD4BF", @"#F43F5E", @"#F59E0B", @"#3B82F6", @"#22C55E"]; }
static UIColor *RYAccent(void) {
    NSInteger i = [CF(@"accent", @0) integerValue];
    NSArray *a = RYAccents(); if (i < 0 || i >= (NSInteger)a.count) i = 0;
    return RYHex(a[i]);
}
#define RY_BG RYHex(@"#0E1014")
#define RY_CARD RYHex(@"#1A1D25")
#define RY_CARD2 RYHex(@"#252A35")
#define RY_MUTED RYHex(@"#8A90A0")

static NSString *RYHash(NSString *s) {
    NSData *d = [[@"8ubah|" stringByAppendingString:s ?: @""] dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char h[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(d.bytes, (CC_LONG)d.length, h);
    NSMutableString *o = [NSMutableString new];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [o appendFormat:@"%02x", h[i]];
    return o;
}
#pragma mark - Licence (key system; same server/repo as the Rave project)
// The Worker URL is stored XOR-scrambled, not as a plain string literal, so a "strings" scan of the
// binary (the exact technique used to find everything else in this file) doesn't just hand it over.
static NSString *RY_LIC_API_(void) {
    static const unsigned char enc[] = {0xBB,0xA7,0xA7,0xA3,0xA0,0xE9,0xFC,0xFC,0xB6,0xBE,0xA3,0xA7,0xAA,0xFE,0xBE,0xBC,
        0xBC,0xBD,0xFE,0xB0,0xE1,0xB5,0xE4,0xFD,0xBE,0xB1,0xBC,0xA6,0xA0,0xA0,0xBC,0xA6,0xBF,0xB2,0xE3,0xFD,0xA4,0xBC,
        0xA1,0xB8,0xB6,0xA1,0xA0,0xFD,0xB7,0xB6,0xA5};
    const uint8_t key = 0xD3;
    NSMutableString *o = [NSMutableString new];
    for (size_t i = 0; i < sizeof(enc); i++) [o appendFormat:@"%c", (char)(enc[i] ^ key)];
    return o;
}
#define RY_LIC_API RY_LIC_API_()
static NSString *RYDeviceId(void) {
    NSString *v = CF(@"devId", nil); if (v.length) return v;
    v = UIDevice.currentDevice.identifierForVendor.UUIDString ?: [NSUUID UUID].UUIDString;
    CS(@"devId", v); return v;
}
// The unlock state is not one plain BOOL. It is re-derived, independently, at every call site below
// (RYLocked and the effects gate) from the saved key hash + device id + a per-build salt, and compared
// against a signature written once at activation. Patching one call site to always say "unlocked" leaves
// the other — which reads the same derived value its own way — still locked.
#define RY_SALT 0xA17C3F9B5E2D8461ULL
static uint64_t RYFNV(const char *s) { uint64_t h = 1469598103934665603ULL; for (; *s; s++) { h ^= (unsigned char)*s; h *= 1099511628211ULL; } return h; }
static BOOL RYDerivedOK(const char *tag) {
    NSString *h = CF(@"licHash", nil); NSString *d = RYDeviceId();
    if (!h.length || !d.length || ![CF(@"unlocked", @NO) boolValue]) return NO;
    uint64_t v = RYFNV([[h stringByAppendingString:d] UTF8String]) ^ RY_SALT ^ RYFNV(tag);
    NSNumber *want = CF(@"licSig", nil);
    return want && (uint64_t)want.unsignedLongLongValue == (v ^ (RYFNV("sig") ^ RYFNV(tag)));
}
// A debugger/Frida gadget attached to the process (the common way to force a function to always return
// YES/NO at runtime without touching the file on disk) shows up as P_TRACED. We don't try to block it —
// we just stop trusting the derived unlock while it's attached.
static BOOL RYTraced(void) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc info; size_t sz = sizeof(info); memset(&info, 0, sz);
    if (sysctl(mib, 4, &info, &sz, NULL, 0) != 0) return NO;
    return (info.kp_proc.p_flag & P_TRACED) != 0;
}
// DYLD_INSERT_LIBRARIES is how Frida/Substrate-style tools commonly attach to a process from outside;
// a named pipe or loaded image matching a known hooking tool is the same kind of signal. None of this
// can be made airtight (an attacker can rename the library), but it costs them real effort to work around.
static BOOL RYHookedEnv(void) {
    if (getenv("DYLD_INSERT_LIBRARIES")) return YES;
    static NSArray<NSString *> *bad; static dispatch_once_t t;
    dispatch_once(&t, ^{ bad = @[@"FridaGadget", @"frida-agent", @"cynject", @"CydiaSubstrate", @"SubstrateLoader", @"libsubstitute", @"SSLKillSwitch"]; });
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char *nm = _dyld_get_image_name(i); if (!nm) continue;
        NSString *s = [NSString stringWithUTF8String:nm];
        for (NSString *b in bad) if ([s rangeOfString:b options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}
// RYTraced()/RYHookedEnv() are kept but NOT gated on below: the tool that injects this dylib on a
// non-jailbroken device (Feather/ESign/Sideloadly-style sideloading) commonly leaves the process under
// ptrace and/or DYLD_INSERT_LIBRARIES set for its OWN normal, legitimate injection — not an attacker.
// Gating features on those two checks caused a false positive that silently disabled every feature while
// still opening the panel (RYLocked only used RYDerivedOK), which is what broke the mic/BG/Stereo tabs.
static BOOL RYFeatureOK(const char *tag) { return RYDerivedOK(tag); }
static BOOL RYLocked(void) { return !RYDerivedOK("locked"); }

static void RYLicStore(BOOL ok, NSString *hash) {
    if (ok) {
        CS(@"licHash", hash); CS(@"unlocked", @YES); CS(@"licTs", @(NSDate.date.timeIntervalSince1970));
        uint64_t v = RYFNV([[hash stringByAppendingString:RYDeviceId()] UTF8String]) ^ RY_SALT ^ RYFNV("sig");
        CS(@"licSig", @(v));
    } else { CS(@"unlocked", @NO); }
}
// Activate with the key itself (not its hash — sending only the hash would let someone else claim the
// same key's device slot just by knowing the public keys.json hash).
static void RYLicActivate(NSString *key, void (^done)(BOOL ok, NSString *reason)) {
    NSString *k = [[key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    NSString *h = RYHash(k);
    NSURL *u = [NSURL URLWithString:[RY_LIC_API stringByAppendingString:@"/activate"]];
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:u];
    r.HTTPMethod = @"POST"; [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    r.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"key": k, @"device": RYDeviceId()} options:0 error:nil];
    [[[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
        BOOL ok = [j isKindOfClass:NSDictionary.class] && [j[@"ok"] boolValue];
        NSString *reason = e ? e.localizedDescription : (([j isKindOfClass:NSDictionary.class] ? j[@"reason"] : nil) ?: (d ? nil : @"no_response"));
        dispatch_async(dispatch_get_main_queue(), ^{ RYLicStore(ok, h); done(ok, reason); });
    }] resume];
}
// Silent background re-check of the key already saved on this device (no UI). Only a definite "no" from
// the server locks the panel back up — a network hiccup never locks out someone with a valid key.
static void RYLicRevalidate(void) {
    NSString *h = CF(@"licHash", nil); if (!h.length) return;
    NSString *u = [NSString stringWithFormat:@"%@/check?hash=%@&device=%@", RY_LIC_API, h, RYDeviceId()];
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:u] completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
        BOOL ok = [j isKindOfClass:NSDictionary.class] && [j[@"ok"] boolValue];
        if (ok) return;
        NSString *why = [j isKindOfClass:NSDictionary.class] ? j[@"reason"] : nil;
        if (![why isKindOfClass:NSString.class]) return;
        BOOL hard = [@[@"global_off", @"not_found", @"off", @"expired", @"device_mismatch"] containsObject:why];
        BOOL unbound = [why isEqualToString:@"not_bound"] && (NSDate.date.timeIntervalSince1970 - [CF(@"licTs", @0) doubleValue]) > 600;
        if (!hard && !unbound) return;
        dispatch_async(dispatch_get_main_queue(), ^{ CS(@"unlocked", @NO); });
    }] resume];
}


// session modes that switch the system echo canceller / noise suppressor / AGC on
static BOOL RYIsProcMode(NSString *m) {
    return [m isEqual:AVAudioSessionModeVoiceChat] || [m isEqual:AVAudioSessionModeVideoChat] || [m isEqual:AVAudioSessionModeGameChat] || [m isEqual:AVAudioSessionModeVoicePrompt];
}

#pragma mark - UI helpers

static UISemanticContentAttribute RYSem(void) { return RYAr() ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeForceLeftToRight; }

static UILabel *RYLabel(NSString *t, CGFloat sz, UIFontWeight w, UIColor *c) {
    UILabel *l = [UILabel new]; l.text = t; l.font = [UIFont systemFontOfSize:sz weight:w];
    l.textColor = c ?: UIColor.whiteColor; l.numberOfLines = 0; l.textAlignment = NSTextAlignmentNatural;
    l.semanticContentAttribute = RYSem();
    return l;
}
static UIButton *RYBtn(NSString *t, BOOL filled, void (^act)(void)) {
    UIButtonConfiguration *c = filled ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration grayButtonConfiguration];
    c.title = t; c.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    c.baseBackgroundColor = filled ? RYAccent() : RY_CARD2; c.baseForegroundColor = UIColor.whiteColor;
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:[UIAction actionWithHandler:^(UIAction *a) { if (act) act(); }]];
    b.semanticContentAttribute = RYSem();
    return b;
}
static UIStackView *RYVStack(NSArray *v, CGFloat sp) {
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:v]; s.axis = UILayoutConstraintAxisVertical; s.spacing = sp;
    s.semanticContentAttribute = RYSem(); return s;
}
static UIStackView *RYHStack(NSArray *v, CGFloat sp) {
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:v]; s.axis = UILayoutConstraintAxisHorizontal; s.spacing = sp;
    s.alignment = UIStackViewAlignmentCenter; s.semanticContentAttribute = RYSem(); return s;
}
static void RYPin(UIView *v, UIView *to, CGFloat pad) {
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [v.topAnchor constraintEqualToAnchor:to.topAnchor constant:pad], [v.bottomAnchor constraintEqualToAnchor:to.bottomAnchor constant:-pad],
        [v.leadingAnchor constraintEqualToAnchor:to.leadingAnchor constant:pad], [v.trailingAnchor constraintEqualToAnchor:to.trailingAnchor constant:-pad]]];
}
static UIView *RYCard(NSArray *views) {
    UIView *c = [UIView new]; c.backgroundColor = RY_CARD; c.layer.cornerRadius = 14;
    UIStackView *s = RYVStack(views, 10); [c addSubview:s]; RYPin(s, c, 12); return c;
}
static UIView *RYSlider(NSString *title, float mn, float mx, float val, void (^chg)(float)) {
    UILabel *l = RYLabel(title, 14, UIFontWeightMedium, nil);
    UISlider *s = [UISlider new]; s.minimumValue = mn; s.maximumValue = mx; s.value = val; s.minimumTrackTintColor = RYAccent();
    __weak UISlider *ws = s;
    [s addAction:[UIAction actionWithHandler:^(UIAction *a) { if (ws && chg) chg(ws.value); }] forControlEvents:UIControlEventValueChanged];
    return RYCard(@[l, s]);
}
static UIView *RYSliderV(NSString *title, NSString *unit, float mn, float mx, float val, BOOL logScale, int dec, void (^chg)(float)) {
    UILabel *l = RYLabel(@"", 14, UIFontWeightMedium, nil);
    UISlider *s = [UISlider new]; s.minimumTrackTintColor = RYAccent(); s.minimumValue = 0; s.maximumValue = 1;
    float (^toS)(float) = ^float(float v) { if (v < mn) v = mn; if (v > mx) v = mx; return logScale ? (logf(v) - logf(mn)) / (logf(mx) - logf(mn)) : (v - mn) / (mx - mn); };
    float (^fromS)(float) = ^float(float t) { float v = logScale ? expf(logf(mn) + t * (logf(mx) - logf(mn))) : mn + t * (mx - mn); return dec == 0 ? roundf(v) : v; };
    NSString *(^txt)(float) = ^NSString *(float v) { return [NSString stringWithFormat:@"%@: %.*f %@", title, dec, v, unit]; };
    s.value = toS(val); l.text = txt(val);
    __weak UISlider *ws = s; __weak UILabel *wl = l;
    [s addAction:[UIAction actionWithHandler:^(UIAction *a) { if (!ws) return; float v = fromS(ws.value); wl.text = txt(v); if (chg) chg(v); }] forControlEvents:UIControlEventValueChanged];
    return RYCard(@[l, s]);
}
static UIView *RYGrid(NSArray *views, int cols) {
    NSMutableArray *rows = [NSMutableArray new];
    for (NSUInteger i = 0; i < views.count; i += cols) {
        NSMutableArray *r = [NSMutableArray new];
        for (int j = 0; j < cols; j++) {
            NSUInteger k = i + j; [r addObject:k < views.count ? views[k] : [UIView new]];
        }
        UIStackView *h = RYHStack(r, 8); h.distribution = UIStackViewDistributionFillEqually; h.alignment = UIStackViewAlignmentFill; [rows addObject:h];
    }
    return RYVStack(rows, 8);
}
static UIImage *RYGradImage(NSString *pair) {
    NSArray *p = [pair componentsSeparatedByString:@","]; if (p.count < 2) return nil;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(80, 44)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGGradientRef g = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)@[(id)RYHex(p[0]).CGColor, (id)RYHex(p[1]).CGColor], NULL);
        CGContextDrawLinearGradient(ctx.CGContext, g, CGPointZero, CGPointMake(80, 44), 0);
        CGGradientRelease(g); CGColorSpaceRelease(cs);
    }];
}

static NSString *RYImgName(UIImage *im) {
    if (!im) return @"";
    @try { NSString *n = [im.imageAsset valueForKey:@"assetName"]; return n ?: @""; } @catch (__unused id e) { return @""; }
}
#pragma mark - View-controller discovery
#pragma mark - Visibility (hidden pre-loaded screens must not count as "on screen")

static BOOL RYVisibleMin(UIView *v, CGFloat minW, CGFloat minH) {
    if (!v.window) return NO;
    for (UIView *p = v; p; p = p.superview) if (p.hidden || p.alpha < 0.05) return NO;
    CGRect f = CGRectIntersection([v convertRect:v.bounds toView:nil], v.window.bounds);
    return !CGRectIsNull(f) && f.size.width > minW && f.size.height > minH;
}
static BOOL RYVisible(UIView *v) { return RYVisibleMin(v, 40, 40); }
static void RYScanAll(UIViewController *vc, NSString *needle, int d, NSMutableArray *out) {
    if (!vc || d > 14) return;
    if ([NSStringFromClass(vc.class) containsString:needle] && vc.isViewLoaded && vc.view.window) [out addObject:vc];
    for (UIViewController *c in vc.childViewControllers) RYScanAll(c, needle, d + 1, out);
    RYScanAll(vc.presentedViewController, needle, d + 1, out);
}


@class RYWindow;
static UIViewController *RYScan(UIViewController *vc, NSString *needle, int d) {
    if (!vc || d > 14) return nil;
    if ([NSStringFromClass(vc.class) containsString:needle] && vc.isViewLoaded && vc.view.window) return vc;
    for (UIViewController *c in vc.childViewControllers) { UIViewController *r = RYScan(c, needle, d + 1); if (r) return r; }
    return RYScan(vc.presentedViewController, needle, d + 1);
}
static NSArray<UIWindow *> *RYAppWindows(void) {
    NSMutableArray *a = [NSMutableArray new];
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) { if (![NSStringFromClass(w.class) isEqual:@"RYWindow"]) [a addObject:w]; }
    }
    return a;
}
static UIViewController *RYFindVC(NSString *needle) {
    if (!needle.length) return nil;
    for (UIWindow *w in RYAppWindows()) { UIViewController *r = RYScan(w.rootViewController, needle, 0); if (r) return r; }
    return nil;
}
static void RYDump(UIViewController *vc, int d, NSMutableString *o) {
    if (!vc || d > 14) return;
    [o appendFormat:@"%@%@\n", [@"" stringByPaddingToLength:d * 2 withString:@" " startingAtIndex:0], NSStringFromClass(vc.class)];
    for (UIViewController *c in vc.childViewControllers) RYDump(c, d + 1, o);
    RYDump(vc.presentedViewController, d + 1, o);
}


static void RYLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt); NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap]; va_end(ap);
    static NSDateFormatter *df; if (!df) { df = [NSDateFormatter new]; df.dateFormat = @"MM-dd HH:mm:ss"; }
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [df stringFromDate:NSDate.date], m];
    NSString *p = [RYDir(@"logs") stringByAppendingPathComponent:@"events.txt"];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
    if (!h) { [line writeToFile:p atomically:NO encoding:NSUTF8StringEncoding error:nil]; return; }
    if ([h seekToEndOfFile] > 60000) [h truncateFileAtOffset:0];
    [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile];
}
#pragma mark - Background view

@interface RYBGView : UIView
@property (nonatomic, strong) UIImageView *img;
@property (nonatomic, strong) CAGradientLayer *grad;
@property (nonatomic, strong) UIVisualEffectView *blur;
@property (nonatomic, strong) UIView *dim;
@property (nonatomic) NSInteger stamp;
- (void)apply;
@end
@implementation RYBGView
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.userInteractionEnabled = NO; self.clipsToBounds = YES;
        self.grad = [CAGradientLayer layer]; self.grad.startPoint = CGPointMake(0, 0); self.grad.endPoint = CGPointMake(1, 1); [self.layer addSublayer:self.grad];
        self.img = [UIImageView new]; self.img.contentMode = UIViewContentModeScaleAspectFill; self.img.clipsToBounds = YES; [self addSubview:self.img];
        self.blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]]; [self addSubview:self.blur];
        self.dim = [UIView new]; self.dim.backgroundColor = UIColor.blackColor; [self addSubview:self.dim];
    }
    return self;
}
- (void)layoutSubviews { [super layoutSubviews]; self.grad.frame = self.bounds; self.img.frame = self.bounds; self.blur.frame = self.bounds; self.dim.frame = self.bounds; }
- (void)apply {
    NSString *m = CF(@"bgMode", @"none"), *v = CF(@"bgValue", @"");
    self.img.hidden = YES; self.grad.hidden = YES; self.backgroundColor = UIColor.blackColor;
    if ([m isEqual:@"image"]) {
        UIImage *im = [UIImage imageWithContentsOfFile:[RYDir(nil) stringByAppendingPathComponent:@"bg.jpg"]];
        if (im) { self.img.image = im; self.img.hidden = NO; }
    } else if ([m isEqual:@"color"]) { self.backgroundColor = RYHex(v); }
    else if ([m isEqual:@"gradient"]) {
        NSArray *p = [v componentsSeparatedByString:@","];
        if (p.count >= 2) { self.grad.colors = @[(id)RYHex(p[0]).CGColor, (id)RYHex(p[1]).CGColor]; self.grad.hidden = NO; }
    }
    self.blur.alpha = [CF(@"blur", @0) floatValue] / 100.0;
    self.dim.alpha = [CF(@"dim", @30) floatValue] / 100.0 * 0.9;
}
@end

#pragma mark - Room helpers (see-through views, chat input, diagnostics)

static NSMapTable *gOrigBG;
static NSHashTable *gKeepClear; static BOOL gBgActive = NO; // views we made see-through stay see-through even when the app paints them again
static void (*orig_setBGC)(id, SEL, UIColor *);
static void RYSetBGC(id self, SEL _cmd, UIColor *c) {
    if (gBgActive && gKeepClear && c && [gKeepClear containsObject:self]) c = UIColor.clearColor;
    orig_setBGC(self, _cmd, c);
}
// RN / Discord views can paint straight onto the layer (or override setBackgroundColor: without calling UIView's), which skipped the hook above and
// let the black come back for up to half a second between two ticks. Hook the layer setter too: it catches every route.
static void (*orig_layerSetBGC)(id, SEL, CGColorRef);
static void RYLayerSetBGC(id self, SEL _cmd, CGColorRef c) {
    if (gBgActive && c && gKeepClear) {
        id d = ((CALayer *)self).delegate;
        if (d && [d isKindOfClass:UIView.class] && ((UIView *)d).layer == (CALayer *)self && [gKeepClear containsObject:d] && CGColorGetAlpha(c) > 0.001) c = UIColor.clearColor.CGColor;
    }
    orig_layerSetBGC(self, _cmd, c);
}
static void RYHookOwnBGC(Class c) {
    SEL s = @selector(setBackgroundColor:);
    Method m = class_getInstanceMethod(c, s); if (!m) return;
    IMP orig = method_getImplementation(m);
    void (^blk)(id, UIColor *) = ^(id me, UIColor *col) {
        if (gBgActive && col && gKeepClear && [gKeepClear containsObject:me]) col = UIColor.clearColor;
        ((void (*)(id, SEL, UIColor *))orig)(me, s, col);
    };
    method_setImplementation(m, imp_implementationWithBlock(blk));
}
static void RYInstallBGHook(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{
        Method m = class_getInstanceMethod(UIView.class, @selector(setBackgroundColor:)); if (!m) return;
        IMP viewImp = method_getImplementation(m);
        orig_setBGC = (void (*)(id, SEL, UIColor *))viewImp;
        method_setImplementation(m, (IMP)RYSetBGC);
        // every view class of the app that has its own setBackgroundColor: (it would skip the hook on UIView)
        unsigned int n = 0; const char *img = [NSBundle mainBundle].executablePath.fileSystemRepresentation;
        const char **names = img ? objc_copyClassNamesForImage(img, &n) : NULL;
        for (unsigned int i = 0; i < n; i++) {
            Class c = objc_getClass(names[i]); if (!c) continue;
            BOOL isView = NO; for (Class k = c; k; k = class_getSuperclass(k)) if (k == UIView.class) { isView = YES; break; }   // plain runtime walk: Swift root classes do not answer isSubclassOfClass:
            if (!isView) continue;
            Class sup = class_getSuperclass(c); if (!sup) continue;
            Method mc = class_getInstanceMethod(c, @selector(setBackgroundColor:)), ms = class_getInstanceMethod(sup, @selector(setBackgroundColor:));
            if (mc && ms && method_getImplementation(mc) != method_getImplementation(ms)) RYHookOwnBGC(c);
        }
        if (names) free(names);
        Method lm = class_getInstanceMethod(CALayer.class, @selector(setBackgroundColor:));
        if (lm) { orig_layerSetBGC = (void (*)(id, SEL, CGColorRef))method_getImplementation(lm); method_setImplementation(lm, (IMP)RYLayerSetBGC); }
    });
}
static BOOL RYSkipClass(UIView *v) {
    NSString *c = NSStringFromClass(v.class), *l = NSStringFromClass(v.layer.class);
    for (NSString *k in @[@"Video", @"Player", @"Metal", @"MTK", @"Camera", @"Preview", @"Flutter", @"WK", @"WebView", @"SampleBuffer"])
        if ([c containsString:k] || [l containsString:k]) return YES;
    return NO;
}
static void RYClear(UIView *v) {
    if (!gOrigBG) gOrigBG = [NSMapTable weakToStrongObjectsMapTable];
    if (!gKeepClear) gKeepClear = [NSHashTable weakObjectsHashTable];
    if (![gOrigBG objectForKey:v]) [gOrigBG setObject:(v.backgroundColor ?: (id)NSNull.null) forKey:v];
    [gKeepClear addObject:v];
    v.backgroundColor = UIColor.clearColor;
}
static void RYRestoreAll(void) {
    BOOL was = gBgActive; gBgActive = NO;
    for (UIView *v in [gOrigBG.keyEnumerator allObjects]) {
        id o = [gOrigBG objectForKey:v]; v.backgroundColor = [o isKindOfClass:UIColor.class] ? o : nil;
    }
    [gOrigBG removeAllObjects]; [gKeepClear removeAllObjects];
    gBgActive = was;
}
static BOOL RYHasBG(UIView *v) { return v.backgroundColor && CGColorGetAlpha(v.backgroundColor.CGColor) > 0.05; }
// highest full-screen container above the room view (the room VC's own view can be only a small part of the screen)
static UIView *RYFullHost(UIView *v) {
    UIWindow *w = v.window; if (!w) return v;
    UIView *best = v;
    for (UIView *p = v.superview; p && p != w; p = p.superview) {
        CGSize s = [p convertRect:p.bounds toView:w].size;
        if (s.width >= w.bounds.size.width * 0.9 && s.height >= w.bounds.size.height * 0.8) best = p;
    }
    return best;
}
static void RYClearBig(UIView *v, UIView *host, UIView *skip, int d) {
    if (d > 10) return;
    for (UIView *s in v.subviews) {
        if (s == skip || RYSkipClass(s)) continue;
        if (RYHasBG(s) && ![s isKindOfClass:UIImageView.class]) {
            CGRect f = [s convertRect:s.bounds toView:host];
            if (f.size.width >= host.bounds.size.width * 0.85 && f.size.height >= host.bounds.size.height * 0.4) RYClear(s);
        }
        RYClearBig(s, host, skip, d + 1);
    }
}

// any text control the chat bar may use: UITextField, UITextView, or a custom editor (YYTextView etc.) that adopts UIKeyInput
static BOOL RYIsInputClass(UIView *v) {
    if ([v isKindOfClass:UITextField.class]) return !((UITextField *)v).secureTextEntry;
    if ([v isKindOfClass:UITextView.class]) return ((UITextView *)v).isEditable;
    if (![v conformsToProtocol:@protocol(UIKeyInput)]) return NO;
    if ([v respondsToSelector:@selector(isSecureTextEntry)] && ((BOOL (*)(id, SEL))objc_msgSend)(v, @selector(isSecureTextEntry))) return NO;
    return YES;
}
static void RYCollectInputs(UIView *v, NSMutableArray *o, int d) {
    if (d > 140) return;
    if (RYIsInputClass(v) && !v.hidden && v.alpha > 0.01 && v.window && v.userInteractionEnabled) [o addObject:v];
    for (UIView *s in v.subviews) RYCollectInputs(s, o, d + 1);
}
// chat bars sit at the bottom: pick the lowest visible input
static UIView *RYBottomInput(UIView *root) {
    NSMutableArray *c = [NSMutableArray new]; RYCollectInputs(root, c, 0);
    UIView *best = nil; CGFloat by = -1e9;
    for (UIView *x in c) { CGFloat y = CGRectGetMaxY([x convertRect:x.bounds toView:nil]); if (y > by) { by = y; best = x; } }
    return best;
}
static id RYMsg0(id o, SEL s) { return [o respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil; }
static NSString *RYGetText(UIView *in) {
    id t = RYMsg0(in, @selector(text)); if ([t isKindOfClass:NSString.class]) return t;
    t = RYMsg0(in, @selector(attributedText)); if ([t isKindOfClass:NSAttributedString.class]) return [(NSAttributedString *)t string];
    return @"";
}
static void RYSetText(UIView *in, NSString *msg) {
    if ([in respondsToSelector:@selector(setText:)]) ((void (*)(id, SEL, id))objc_msgSend)(in, @selector(setText:), msg);
    else if ([in respondsToSelector:@selector(setAttributedText:)]) ((void (*)(id, SEL, id))objc_msgSend)(in, @selector(setAttributedText:), [[NSAttributedString alloc] initWithString:msg ?: @""]);
    id dl = RYMsg0(in, @selector(delegate));
    if ([in isKindOfClass:UITextField.class]) {
        UITextField *tf = (UITextField *)in;
        [tf sendActionsForControlEvents:UIControlEventEditingChanged];
        [NSNotificationCenter.defaultCenter postNotificationName:UITextFieldTextDidChangeNotification object:tf];
        if ([dl respondsToSelector:@selector(textFieldDidChangeSelection:)]) ((void (*)(id, SEL, id))objc_msgSend)(dl, @selector(textFieldDidChangeSelection:), tf);
    } else {
        if ([dl respondsToSelector:@selector(textViewDidChange:)]) ((void (*)(id, SEL, id))objc_msgSend)(dl, @selector(textViewDidChange:), in);
        if ([dl respondsToSelector:@selector(textViewDidChangeSelection:)]) ((void (*)(id, SEL, id))objc_msgSend)(dl, @selector(textViewDidChangeSelection:), in);
        [NSNotificationCenter.defaultCenter postNotificationName:UITextViewTextDidChangeNotification object:in];
    }
}
// a real edit through UIKeyInput (select all, replace): goes through the app's own change pipeline. Needs the app window to be key.
static BOOL RYTypeText(UIView *in, NSString *msg) {
    if (![in conformsToProtocol:@protocol(UIKeyInput)]) return NO;
    if (!in.isFirstResponder && ![in becomeFirstResponder]) return NO;
    if ([in conformsToProtocol:@protocol(UITextInput)]) {
        id<UITextInput> ti = (id<UITextInput>)in;
        UITextRange *all = [ti textRangeFromPosition:ti.beginningOfDocument toPosition:ti.endOfDocument];
        if (all) [ti replaceRange:all withText:@""];
    }
    [(id<UIKeyInput>)in insertText:msg];
    return YES;
}
static void RYPressReturn(UIView *in) {
    if ([in isKindOfClass:UITextField.class]) {
        UITextField *tf = (UITextField *)in;
        if ([tf.delegate respondsToSelector:@selector(textFieldShouldReturn:)]) [tf.delegate textFieldShouldReturn:tf];
        [tf sendActionsForControlEvents:UIControlEventEditingDidEndOnExit];
        [tf sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    } else {
        id dl = RYMsg0(in, @selector(delegate));
        if ([dl respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)])
            ((BOOL (*)(id, SEL, id, NSRange, id))objc_msgSend)(dl, @selector(textView:shouldChangeTextInRange:replacementText:), in, NSMakeRange(RYGetText(in).length, 0), @"\n");
    }
}
static void RYCollectCtl(UIView *v, NSMutableArray *o, int d) {
    if (d > 8) return;
    if ([v isKindOfClass:UIControl.class] && !v.hidden && v.alpha > 0.01 && ((UIControl *)v).enabled && v.window) [o addObject:v];
    for (UIView *s in v.subviews) RYCollectCtl(s, o, d + 1);
}
static NSString *RYCtlKey(UIControl *b) {
    NSMutableString *k = [NSMutableString new];
    [k appendFormat:@"%@|%@|", b.accessibilityLabel ?: @"", b.accessibilityIdentifier ?: @""];
    if ([b isKindOfClass:UIButton.class]) {
        UIButton *ub = (UIButton *)b;
        [k appendFormat:@"%@|%@|%@", [ub titleForState:UIControlStateNormal] ?: @"", ub.configuration.title ?: @"", RYImgName([ub imageForState:UIControlStateNormal])];
    }
    return k.lowercaseString;
}
// SwiftUI rows are not UIControls: reach their buttons through the accessibility tree
static void RYA11yCollect(id o, NSMutableArray *out, int d) {
    if (!o || d > 9) return;
    if ([o isKindOfClass:UIView.class]) {
        UIView *v = o; if (v.hidden) return;
        if (v.isAccessibilityElement) [out addObject:v];
        NSArray *e = v.accessibilityElements; if (e) for (id x in e) RYA11yCollect(x, out, d + 1);
        for (UIView *sv in v.subviews) RYA11yCollect(sv, out, d + 1);
    } else {
        if ([o isAccessibilityElement]) [out addObject:o];
        NSArray *e = [o accessibilityElements]; if (e) for (id x in e) RYA11yCollect(x, out, d + 1);
    }
}
static NSString *RYA11yKey(id e) {
    NSString *l = [e accessibilityLabel] ?: @"", *i = [e respondsToSelector:@selector(accessibilityIdentifier)] ? ([e accessibilityIdentifier] ?: @"") : @"";
    return [NSString stringWithFormat:@"%@|%@|%llu", l, i, (unsigned long long)[e accessibilityTraits]].lowercaseString;
}
static UIControl *RYSendBtnNear(UIView *in) {
    NSArray *good = @[@"send", @"إرسال", @"ارسال", @"submit", @"paperplane", @"paper_plane", @"arrow.up", @"arrow_up"];
    NSArray *bad = @[@"sticker", @"emoji", @"gif", @"mic", @"voice", @"camera", @"attach", @"photo", @"gift"];
    UIView *p = in;
    for (int i = 0; i < 6 && p.superview; i++) {
        p = p.superview;
        NSMutableArray *c = [NSMutableArray new]; RYCollectCtl(p, c, 0);
        for (UIControl *b in c) {
            if ((UIView *)b == in || [b isKindOfClass:UITextField.class]) continue;
            NSString *k = RYCtlKey(b); BOOL skip = NO;
            for (NSString *w in bad) if ([k containsString:w]) { skip = YES; break; }
            if (skip) continue;
            for (NSString *w in good) if ([k containsString:w]) return b;
        }
        if (p.bounds.size.height > 400) break;
    }
    return nil;
}


// fires a tap on a view that is not a UIControl: calls the targets of its tap gesture recognizers, which is what UIKit does on a real tap
static BOOL RYTapView(UIView *v) {
    int lvl = 0;
    for (UIView *p = v; p && lvl < 5; p = p.superview, lvl++) {
        if ([p isKindOfClass:UIControl.class] && ((UIControl *)p).enabled) { [(UIControl *)p sendActionsForControlEvents:UIControlEventTouchUpInside]; return YES; }
        BOOL did = NO;
        for (UIGestureRecognizer *g in p.gestureRecognizers) {
            if (![g isKindOfClass:UITapGestureRecognizer.class] || !g.enabled) continue;
            NSArray *ts = nil; @try { ts = [g valueForKey:@"targets"]; } @catch (__unused id e) { ts = nil; }
            for (id t in ts) {
                Ivar ta = class_getInstanceVariable([t class], "_target"), ac = class_getInstanceVariable([t class], "_action");
                if (!ta || !ac) continue;
                id target = object_getIvar(t, ta); SEL act = *(SEL *)((uint8_t *)(__bridge void *)t + ivar_getOffset(ac));
                if (target && act && [target respondsToSelector:act]) { ((void (*)(id, SEL, id))objc_msgSend)(target, act, g); did = YES; }
            }
        }
        if (did) return YES;
    }
    return NO;
}
static void RYWalk(UIView *v, int d, void (^blk)(UIView *, int)) { blk(v, d); for (UIView *s in v.subviews) RYWalk(s, d + 1, blk); }
static NSString *RYClip(NSString *s, NSUInteger n) {
    if (!s.length) return @"";
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return s.length > n ? [s substringToIndex:n] : s;
}
#pragma mark - Mic voice changer (changes what the others hear; three possible capture routes, each counted so we can see which one the app really uses)
typedef struct { const char *ar, *en; float semi; int mode; float echo; } RYPreset;
static const RYPreset kPresets[] = {
    {"عادي", "Normal", 0, 0, 0}, {"رجل عميق", "Deep man", -4, 0, 0}, {"وحش", "Monster", -9, 0, 0},
    {"فتاة", "Girl", 4, 0, 0}, {"طفل", "Kid", 7, 0, 0}, {"سنجاب", "Chipmunk", 11, 0, 0},
    {"روبوت", "Robot", 0, 1, 0}, {"ميجافون", "Megaphone", 0, 2, 0}, {"صدى", "Echo", 0, 0, 0.45f}, {"صدى عميق", "Deep echo", -4, 0, 0.4f}
};
#define RY_NPRESETS ((int)(sizeof(kPresets) / sizeof(kPresets[0])))
static volatile int gMicOn = 0, gMicMode = 0, gMicPreset = 0;
static volatile float gMicSemi = 0, gMicEcho = 0, gMicGain = 1;
static volatile long long gMicCallsA = 0, gMicCallsU = 0, gMicCallsT = 0, gMicProc = 0;
static volatile int gMicRebound = 0, gMicWrapped = 0, gMicTapInst = 0;
static volatile int gMicDist = 0, gMicRev = 0, gMonOn = 0;
static volatile int gMicMute = 0; // "سكر صوتي": hard-silences the mic no matter what else is on

// ---- Stereo: play an imported audio/video file through the mic instead of the real voice (kill-mic still overrides it, see RYMicFx)
static float *gStBuf = NULL; static long gStLen = 0; static double gStPos = 0, gStRate = 48000;
static volatile int gStOn = 0, gStLoop = 0; static float gStVol = 1.f; static volatile int gStLoading = 0;
static void RYStStop(void) { gStOn = 0; }
static double RYStDuration(void) { return gStLen > 1 ? (double)gStLen / gStRate : 0; } // seconds
static double RYStPosSec(void) { return gStRate > 0 ? gStPos / gStRate : 0; }          // seconds
static void RYStSeek(double seconds) {
    if (gStLen <= 1) return;
    double p = seconds * gStRate;
    if (p < 0) p = 0; if (p > gStLen - 1) p = gStLen - 1;
    gStPos = p;
}
static void RYStFree(void) { if (gStBuf) { free(gStBuf); gStBuf = NULL; } gStLen = 0; gStPos = 0; gStOn = 0; }
// linear-resampled playback into the real mic buffer: t[] is mono float32, c frames, sr is the real callback rate (gStRate is the decoded file's rate)
static inline void RYStFeed(float *t, int c, double sr) {
    if (!gStBuf || gStLen <= 1) { gStOn = 0; return; }
    double step = gStRate / (sr > 0 ? sr : gStRate);
    for (int i = 0; i < c; i++) {
        if (!gStOn) { t[i] = 0.f; continue; }
        long i0 = (long)gStPos;
        if (i0 >= gStLen - 1) {
            if (gStLoop) { gStPos = 0; i0 = 0; } else { gStOn = 0; t[i] = 0.f; continue; }
        }
        double frac = gStPos - (double)i0;
        float a = gStBuf[i0], b = gStBuf[MIN(i0 + 1, gStLen - 1)];
        t[i] = (a + (b - a) * (float)frac) * gStVol;
        gStPos += step;
    }
}
// decodes any file AVFoundation can open (mp3/mp4/mov/wav/m4a...) to mono float32 PCM, off the audio thread. 4-minute hard cap.
static void RYStDecode(NSURL *u, void (^done)(BOOL ok, NSString *msg)) {
    gStLoading = 1;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        AVAsset *asset = [AVAsset assetWithURL:u];
        NSArray<AVAssetTrack *> *tracks = [asset tracksWithMediaType:AVMediaTypeAudio];
        if (!tracks.count) { dispatch_async(dispatch_get_main_queue(), ^{ gStLoading = 0; done(NO, T(@"ما فيه صوت بالملف", @"No audio track in this file")); }); return; }
        NSError *err = nil; AVAssetReader *rd = [[AVAssetReader alloc] initWithAsset:asset error:&err];
        if (!rd) { dispatch_async(dispatch_get_main_queue(), ^{ gStLoading = 0; done(NO, err.localizedDescription ?: @"reader"); }); return; }
        const double rate = 48000;
        NSDictionary *settings = @{ AVFormatIDKey: @(kAudioFormatLinearPCM), AVSampleRateKey: @(rate), AVNumberOfChannelsKey: @1,
            AVLinearPCMBitDepthKey: @32, AVLinearPCMIsFloatKey: @YES, AVLinearPCMIsNonInterleaved: @NO, AVLinearPCMIsBigEndianKey: @NO };
        AVAssetReaderTrackOutput *out = [[AVAssetReaderTrackOutput alloc] initWithTrack:tracks.firstObject outputSettings:settings];
        if (![rd canAddOutput:out]) { dispatch_async(dispatch_get_main_queue(), ^{ gStLoading = 0; done(NO, T(@"صيغة غير مدعومة", @"Unsupported format")); }); return; }
        [rd addOutput:out];
        if (![rd startReading]) { dispatch_async(dispatch_get_main_queue(), ^{ gStLoading = 0; done(NO, rd.error.localizedDescription ?: @"start"); }); return; }
        long cap = (long)(rate * 240); // hard cap: 4 minutes of mono float32 (~3.8MB/min)
        float *buf = (float *)malloc(sizeof(float) * (size_t)cap); long len = 0; BOOL truncated = NO;
        CMSampleBufferRef sb;
        while (buf && rd.status == AVAssetReaderStatusReading && (sb = [out copyNextSampleBuffer])) {
            CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
            size_t totalLen = 0; char *ptr = NULL;
            if (bb && CMBlockBufferGetDataPointer(bb, 0, NULL, &totalLen, &ptr) == kCMBlockBufferNoErr && ptr) {
                long n = (long)(totalLen / sizeof(float));
                if (len + n > cap) { n = cap - len; truncated = YES; }
                if (n > 0) { memcpy(buf + len, ptr, (size_t)n * sizeof(float)); len += n; }
            }
            CFRelease(sb);
            if (len >= cap) break;
        }
        BOOL ok = buf != NULL && len > 0 && rd.status != AVAssetReaderStatusFailed;
        dispatch_async(dispatch_get_main_queue(), ^{
            gStLoading = 0;
            if (!ok) { if (buf) free(buf); done(NO, rd.error.localizedDescription ?: T(@"تعذرت القراءة", @"Could not decode")); return; }
            RYStFree();
            gStBuf = (float *)realloc(buf, sizeof(float) * (size_t)len); if (!gStBuf) gStBuf = buf;
            gStLen = len; gStPos = 0; gStRate = rate;
            done(YES, truncated ? T(@"جاهز (انقص لأول 4 دقايق)", @"Ready (trimmed to the first 4 minutes)") : T(@"جاهز", @"Ready"));
        });
    });
}

#define RY_FX_ON (RYFeatureOK("fx") && (gMicOn || gMicDist || gMicRev || gMicMute || gStOn))   // the "Silver" effects (amplifier, silver echo) work on their own, without the voice-changer switch; Stereo file playback also needs the pipeline live
enum { RV_DRY, RV_ELVL, RV_ESEND, RV_LLVL, RV_SIZE, RV_PRE, RV_DECAY, RV_DIFF, RV_SPIN, RV_WANDER, RV_HC, RV_EDAMP, RV_LDAMP, RV_LC, RV_LB, RV_BF, RV_N };
static const float kRvDef[RV_N] = {46, 69, 69, 69, 32, 100, 10, 0, 0, 40, 16000, 16000, 9400, 137, 100, 600}; // the Dragonfly Room Reverb values from the screenshot
static volatile float gRv[RV_N] = {46, 69, 69, 69, 32, 100, 10, 0, 0, 40, 16000, 16000, 9400, 137, 100, 600};
static volatile float gDistGain = 1000.f, gDistOut = 0.7f, gDistGate = 0.0018f; // amplifier: +60 dB, -3 dB out, gate at -55 dB
static char gMicFmt[96] = "-"; static char gMicLast[200] = "-"; static volatile long long gMicSkip = 0; static volatile double gMicHWRate = 48000;

#define RYM_BUF 8192      // pitch history (power of two)
#define RYM_ECHO 32768    // echo line (power of two)
typedef struct {
    float hist[RYM_BUF]; unsigned w; float d0, d1; float eb[RYM_ECHO]; unsigned ew; float ph, hpx, hpy, lp; double sr;
    float dcx, dcy, dlp, env;                                        // "amplifier" (distortion) state
    float cb[8][4096]; unsigned ci[8]; float cf[8]; float ab[4][1024]; unsigned ai[4]; // room reverb: 8 combs + 4 all-passes
    float pre[16384]; unsigned pw; float er[8192]; unsigned erw;      // pre-delay + early reflections
    float rlc, elp, olp, blp, lfo;                                    // reverb filters + modulation
} RYVS;
static RYVS gVS[3]; // 0 = AudioUnitRender, 1 = AUAudioUnit block, 2 = AVAudioEngine tap (separate state: they may run at the same time)


// ---- "Silver" effects. Windows VST plugins cannot run on an iPhone, so the same two effects are built in natively.
// amplifier (Plus Distortion style: input gain -> saturation -> output gain). The gain is at least +60 dB, so a gate keeps the room noise from being blown up.
static inline float RYDist(float x, RYVS *s) {
    float a = fabsf(x); s->env = a > s->env ? a : s->env * 0.9997f;
    float thr = gDistGate, gate = s->env < thr ? s->env / thr : 1.f; gate *= gate;      // below the threshold the input fades out
    float v = x * gDistGain;
    float y = 0.7f * tanhf(v * 2.2f + 0.1f) + 0.3f * fmaxf(-1.f, fminf(1.f, v * 3.f));
    float hp = y - s->dcx + 0.995f * s->dcy; s->dcx = y; s->dcy = hp;                  // DC blocker (the asymmetric clipping adds an offset)
    s->dlp += 0.55f * (hp - s->dlp);                                                    // takes the harshest fizz off
    return s->dlp * gDistOut * gate;
}
// room reverb modelled on Dragonfly Room Reverb (Freeverb3 style): early reflections + a late tail made of 8 combs and 4 all-passes.
// The coefficients are worked out once per audio block from the user's settings.
typedef struct { int L[8], apL[4], etl[8], pd; float fb[8], ld, ed, hc, lc, bf, apg, wdepth, spininc, dry, elv, esend, llv, lb; } RYRevC;
static const int kRvComb[8] = {1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617}, kRvAp[4] = {556, 441, 341, 225};
static const float kRvEt[8] = {0.007f, 0.011f, 0.017f, 0.023f, 0.031f, 0.041f, 0.053f, 0.067f}, kRvEg[8] = {.7f, .6f, .5f, .45f, .4f, .35f, .3f, .25f};
static inline float RYPole(float hz, double sr) { if (hz > 0.45f * (float)sr) hz = 0.45f * (float)sr; if (hz < 1.f) hz = 1.f; return expf(-6.2831853f * hz / (float)sr); }
static void RYRevPrep(RYRevC *c, double sr) {
    const float k = (float)(sr / 44100.0), sz = fmaxf(0.25f, gRv[RV_SIZE] / 32.f), decay = fmaxf(0.1f, gRv[RV_DECAY]);
    for (int i = 0; i < 8; i++) {
        int L = (int)(kRvComb[i] * k * sz); if (L > 4000) L = 4000; if (L < 32) L = 32; c->L[i] = L;
        float fb = powf(10.f, -3.f * (float)L / ((float)sr * decay)); c->fb[i] = fb > 0.9995f ? 0.9995f : fb;  // feedback that gives the chosen decay time (RT60)
        int e = (int)(kRvEt[i] * sz * (float)sr); c->etl[i] = e > 8190 ? 8190 : e;
    }
    for (int i = 0; i < 4; i++) { int L = (int)(kRvAp[i] * k); if (L > 1000) L = 1000; if (L < 8) L = 8; c->apL[i] = L; }
    int pd = (int)(gRv[RV_PRE] * 0.001 * sr); c->pd = pd > 16383 ? 16383 : (pd < 0 ? 0 : pd);
    c->ld = RYPole(gRv[RV_LDAMP], sr); c->ed = RYPole(gRv[RV_EDAMP], sr); c->hc = RYPole(gRv[RV_HC], sr); c->lc = RYPole(gRv[RV_LC], sr); c->bf = RYPole(gRv[RV_BF], sr);
    c->apg = 0.1f + 0.7f * gRv[RV_DIFF] * 0.01f; c->wdepth = gRv[RV_WANDER] * 0.01f * 24.f * k; c->spininc = 6.2831853f * gRv[RV_SPIN] / (float)sr;
    c->dry = gRv[RV_DRY] * 0.01f; c->elv = gRv[RV_ELVL] * 0.01f * 0.3f; c->esend = gRv[RV_ESEND] * 0.01f; c->llv = gRv[RV_LLVL] * 0.01f * 3.f; c->lb = gRv[RV_LB] * 0.01f;
}
static inline float RYRev(float x, RYVS *s, const RYRevC *c) {
    s->rlc = x * (1.f - c->lc) + s->rlc * c->lc; float xi = x - s->rlc;                  // low cut on what goes into the reverb
    s->pre[s->pw & 16383] = xi; float pin = s->pre[(s->pw - (unsigned)c->pd) & 16383]; s->pw++;
    s->er[s->erw & 8191] = xi; float e = 0;
    for (int j = 0; j < 8; j++) e += s->er[(s->erw - (unsigned)c->etl[j]) & 8191] * kRvEg[j];
    s->erw++; s->elp = e * (1.f - c->ed) + s->elp * c->ed; e = s->elp;                  // early damp
    float in = (pin + e * c->esend) * 0.015f, late = 0;
    s->lfo += c->spininc; if (s->lfo > 6.2831853f) s->lfo -= 6.2831853f;
    for (int i = 0; i < 8; i++) {
        float Lm = (float)c->L[i]; if (c->wdepth > 0.01f && c->spininc > 0.f) Lm += c->wdepth * sinf(s->lfo + 0.8f * (float)i);
        int Li = (int)Lm; float fr = Lm - (float)Li; unsigned wi = s->ci[i];
        float o = s->cb[i][(wi - (unsigned)Li) & 4095] * (1.f - fr) + s->cb[i][(wi - (unsigned)Li - 1u) & 4095] * fr;
        s->cf[i] = o * (1.f - c->ld) + s->cf[i] * c->ld;                                // late damp
        s->cb[i][wi & 4095] = in + s->cf[i] * c->fb[i]; s->ci[i] = wi + 1; late += o;
    }
    for (int a = 0; a < 4; a++) {
        unsigned wi = s->ai[a]; float b = s->ab[a][(wi - (unsigned)c->apL[a]) & 1023], o = -late + b;
        s->ab[a][wi & 1023] = late + b * c->apg; s->ai[a] = wi + 1; late = o;
    }
    s->blp = late * (1.f - c->bf) + s->blp * c->bf; late += s->blp * c->lb;             // low boost
    float wet = e * c->elv + late * c->llv;
    s->olp = wet * (1.f - c->hc) + s->olp * c->hc;                                       // high cut
    return x * c->dry + s->olp;
}
// pitch shift = two read taps on a delay line that slides at (1 - ratio) samples per sample, cross-faded with a Hann window
static void RYVoiceBlock(float *x, int n, double sr, RYVS *s) {
    if (s->sr != sr) { memset(s, 0, sizeof(RYVS)); s->sr = sr; s->d1 = (float)(0.016 * sr); }
    if (gMicMute) { memset(x, 0, (size_t)n * sizeof(float)); return; } // overrides everything else, on purpose
    const int W = (int)(0.032 * sr); const int revOn = gMicRev; RYRevC rc; if (revOn) RYRevPrep(&rc, sr);
    const int mst = gMicOn; // pitch / voice / echo / mic level belong to the main switch; amplifier and silver echo have their own
    const float semi = mst ? gMicSemi : 0.f, echo = mst ? gMicEcho : 0.f, gain = mst ? gMicGain : 1.f; const int mode = mst ? gMicMode : 0;
    const float dd = 1.f - powf(2.f, semi / 12.f);
    const BOOL pitch = fabsf(semi) > 0.05f;
    int ed = (int)(0.27 * sr); if (ed >= RYM_ECHO) ed = RYM_ECHO - 1;
    const float rph = (float)(2.0 * M_PI * 70.0 / sr);
    for (int i = 0; i < n; i++) {
        float in = x[i] * gain, y = in;
        if (pitch) {
            s->hist[s->w & (RYM_BUF - 1)] = in;
            float acc = 0; float *dk[2] = { &s->d0, &s->d1 };
            for (int k = 0; k < 2; k++) {
                float d = *dk[k]; int di = (int)d; float fr = d - (float)di;
                float v = s->hist[(s->w - (unsigned)di) & (RYM_BUF - 1)] * (1.f - fr) + s->hist[(s->w - (unsigned)di - 1) & (RYM_BUF - 1)] * fr;
                acc += v * (0.5f - 0.5f * cosf(6.2831853f * (d / (float)W)));
                d += dd; if (d >= (float)W) d -= (float)W; else if (d < 0.f) d += (float)W; *dk[k] = d;
            }
            y = acc; s->w++;
        }
        if (mode == 1) { float m = sinf(s->ph); s->ph += rph; if (s->ph > 6.2831853f) s->ph -= 6.2831853f; y = y * (0.25f + 0.75f * m) * 1.35f; }
        else if (mode == 2) { float hp = 0.95f * (s->hpy + y - s->hpx); s->hpx = y; s->hpy = hp; s->lp += 0.4f * (hp - s->lp); y = tanhf(s->lp * 3.0f); }
        if (gMicDist) y = RYDist(y, s);
        if (revOn) y = RYRev(y, s, &rc);
        if (echo > 0.01f) { float e = s->eb[(s->ew - (unsigned)ed) & (RYM_ECHO - 1)]; s->eb[s->ew & (RYM_ECHO - 1)] = y + e * 0.4f; s->ew++; y += e * echo; }
        if (y > 1.f) y = 1.f; else if (y < -1.f) y = -1.f;
        x[i] = y;
    }
}
// ---- monitor: hear your own processed voice (what the others hear) through the phone's output. A ring buffer is fed by the capture routes below.
static float gMonRing[65536]; static volatile unsigned gMonW = 0, gMonR = 0; static double gMonSR = 48000; static AVAudioEngine *gMonEng;
static volatile int gStMon = 1; // "hear the Stereo file myself": plays ONLY the file (not my voice) through the phone's output, in sync with what the room hears
static void RYMonPush(const float *x, int n, double sr) {
    gMonSR = sr; unsigned w = gMonW;
    for (int i = 0; i < n; i++) gMonRing[(w + (unsigned)i) & 65535] = x[i];
    __sync_synchronize(); gMonW = w + (unsigned)n;
}
static void RYMonFeed(const float *x, int n, double sr) { if (!gMonOn) return; RYMonPush(x, n, sr); }
static void RYMonEngineStop(void) {
    AVAudioEngine *e = gMonEng; gMonEng = nil;
    if (e) dispatch_async(dispatch_get_main_queue(), ^{ [e stop]; });
}
static void RYMonStop(void) {
    gMonOn = 0;
    if (gStMon && gStOn) return;   // the Stereo monitor is still using the engine
    RYMonEngineStop();
}
// starts the local-playback engine if it is not running yet (used by "Hear my voice" and by "Hear it myself" in the Stereo tab)
static void RYMonEngineStart(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gMonEng || !(gMonOn || (gStMon && gStOn))) return;
        AVAudioFormat *fmt = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:(gMonSR > 0 ? gMonSR : 48000) channels:1];
        __block BOOL primed = NO;
        AVAudioSourceNode *src = [[AVAudioSourceNode alloc] initWithFormat:fmt renderBlock:^OSStatus(BOOL *silence, const AudioTimeStamp *ts, AVAudioFrameCount frames, AudioBufferList *out) {
            float *o = (float *)out->mBuffers[0].mData; unsigned w = gMonW, r = gMonR, avail = w - r;
            if (!primed) { if (avail < 1200) { memset(o, 0, frames * sizeof(float)); return noErr; } primed = YES; }  // small cushion before the first sample
            if (avail > 9600) { r = w - 2400; avail = 2400; }                                                        // fell behind: jump back to ~50 ms
            unsigned take = avail < frames ? avail : frames;
            for (unsigned i = 0; i < take; i++) o[i] = gMonRing[(r + i) & 65535];
            if (take < frames) memset(o + take, 0, (frames - take) * sizeof(float));
            gMonR = r + take; return noErr;
        }];
        AVAudioEngine *e = [AVAudioEngine new];
        [e attachNode:src]; [e connect:src to:e.mainMixerNode format:fmt];
        NSError *err = nil;
        if (![e startAndReturnError:&err]) { RYLog(@"monitor start failed: %@", err); gMonOn = 0; return; }
        gMonEng = e;
        static dispatch_once_t once; dispatch_once(&once, ^{
            [NSNotificationCenter.defaultCenter addObserverForName:AVAudioEngineConfigurationChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
                AVAudioEngine *g = gMonEng; if ((gMonOn || (gStMon && gStOn)) && g && !g.isRunning) [g startAndReturnError:nil];
            }];
        });
    });
}
static void RYMonStart(void) { gMonOn = 1; gMonR = gMonW; RYMonEngineStart(); }
// start the Stereo file from the beginning, and (if enabled) start hearing it locally
static void RYStPlay(void) { if (!RYFeatureOK("stereo")) return; gStPos = 0; gMonR = gMonW; gStOn = 1; if (gStMon) RYMonEngineStart(); }
static void RYStMonSet(BOOL on) {
    gStMon = on ? 1 : 0; CS(@"stMon", @(on));
    if (on && gStOn) { gMonR = gMonW; RYMonEngineStart(); }
    else if (!on && !gMonOn) RYMonEngineStop();
}
static inline void RYMicFx(float *t, int c, double sr, RYVS *s) {
    gMonSR = sr; // remembered even while the monitor is off, so the engine starts at the real capture rate
    if (gStOn) {
        // "سكر صوتي" only has to silence YOUR voice, not the Stereo file: RYStFeed always runs here regardless of gMicMute,
        // and RYVoiceBlock (called below on tmp, your real voice) already zeroes itself out on its own when gMicMute is on.
        static __thread float tmp[8192]; int done = 0;
        while (done < c) {
            int n = MIN(c - done, 8192);
            memcpy(tmp, t + done, (size_t)n * sizeof(float));
            RYVoiceBlock(tmp, n, sr, s);                 // tmp = your real voice, exactly as it would normally sound (silence if muted)
            RYStFeed(t + done, n, sr);                    // t[] = the Stereo file, always at full clarity
            if (gStMon && !gMonOn) RYMonPush(t + done, n, sr); // I hear the file itself, at the same moment the room does (when "Hear my voice" is on, the mixed signal below is monitored instead)
            for (int i = 0; i < n; i++) { float v = t[done + i] + tmp[i] * 0.55f; t[done + i] = v > 1.f ? 1.f : (v < -1.f ? -1.f : v); }
            done += n;
        }
    } else if (gMicMute) { memset(t, 0, (size_t)c * sizeof(float)); } // no Stereo playing: muting the mic just means silence
    else if (RY_FX_ON) RYVoiceBlock(t, c, sr, s);
    if (gMonOn) RYMonFeed(t, c, sr);
}
// interleaved: channel 0 is processed and copied to the other channels
static void RYProcInter(void *data, BOOL isFloat, UInt32 frames, UInt32 ch, double sr, RYVS *s) {
    if (!data || !ch) return; float tmp[2048]; UInt32 done = 0;
    while (done < frames) {
        UInt32 c = frames - done; if (c > 2048) c = 2048;
        if (isFloat) {
            float *p = (float *)data + (size_t)done * ch;
            for (UInt32 j = 0; j < c; j++) tmp[j] = p[j * ch];
            RYMicFx(tmp, (int)c, sr, s);
            for (UInt32 j = 0; j < c; j++) for (UInt32 k = 0; k < ch; k++) p[j * ch + k] = tmp[j];
        } else {
            int16_t *p = (int16_t *)data + (size_t)done * ch;
            for (UInt32 j = 0; j < c; j++) tmp[j] = (float)p[j * ch] / 32768.f;
            RYMicFx(tmp, (int)c, sr, s);
            for (UInt32 j = 0; j < c; j++) { float v = tmp[j] * 32767.f; int16_t q = (int16_t)(v > 32767.f ? 32767 : v < -32768.f ? -32768 : v); for (UInt32 k = 0; k < ch; k++) p[j * ch + k] = q; }
        }
        done += c;
    }
    gMicProc += frames;
}
static void RYProcPlanar(void **planes, UInt32 np, BOOL isFloat, UInt32 frames, double sr, RYVS *s) {
    if (!np || !planes[0]) return; float tmp[2048]; UInt32 done = 0;
    while (done < frames) {
        UInt32 c = frames - done; if (c > 2048) c = 2048;
        if (isFloat) { float *p = (float *)planes[0] + done; for (UInt32 j = 0; j < c; j++) tmp[j] = p[j]; }
        else { int16_t *p = (int16_t *)planes[0] + done; for (UInt32 j = 0; j < c; j++) tmp[j] = (float)p[j] / 32768.f; }
        RYMicFx(tmp, (int)c, sr, s);
        for (UInt32 q = 0; q < np; q++) {
            if (!planes[q]) continue;
            if (isFloat) { float *p = (float *)planes[q] + done; for (UInt32 j = 0; j < c; j++) p[j] = tmp[j]; }
            else { int16_t *p = (int16_t *)planes[q] + done; for (UInt32 j = 0; j < c; j++) { float v = tmp[j] * 32767.f; p[j] = (int16_t)(v > 32767.f ? 32767 : v < -32768.f ? -32768 : v); } }
        }
        done += c;
    }
    gMicProc += frames;
}
// route A/U: raw buffers described by an AudioStreamBasicDescription
static void RYMicProcessASBD(const AudioStreamBasicDescription *f, UInt32 n, AudioBufferList *io, RYVS *s) {
    if (!f || !io || f->mFormatID != kAudioFormatLinearPCM || !io->mNumberBuffers) { gMicSkip++; return; }
    BOOL isFloat = (f->mFormatFlags & kAudioFormatFlagIsFloat) != 0, planar = (f->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    UInt32 bits = f->mBitsPerChannel, ch = f->mChannelsPerFrame ? f->mChannelsPerFrame : 1;
    if (!((isFloat && bits == 32) || (!isFloat && bits == 16))) { gMicSkip++; return; }
    double sr = f->mSampleRate > 0 ? f->mSampleRate : (gMicHWRate > 0 ? gMicHWRate : 48000);
    if (!planar) {
        AudioBuffer *b = &io->mBuffers[0]; UInt32 frames = b->mDataByteSize / (ch * (bits / 8)); if (frames > n) frames = n;
        RYProcInter(b->mData, isFloat, frames, ch, sr, s);
    } else {
        void *pl[8]; UInt32 np = io->mNumberBuffers > 8 ? 8 : io->mNumberBuffers; UInt32 frames = n;
        for (UInt32 q = 0; q < np; q++) { pl[q] = io->mBuffers[q].mData; UInt32 fq = io->mBuffers[q].mDataByteSize / (bits / 8); if (fq < frames) frames = fq; }
        RYProcPlanar(pl, np, isFloat, frames, sr, s);
    }
}
// ---- route A: the C function AudioUnitRender (the stock WebRTC capture path calls it on input bus 1)
static OSStatus (*orig_aurender)(AudioUnit, AudioUnitRenderActionFlags *, const AudioTimeStamp *, UInt32, UInt32, AudioBufferList *);
static OSStatus RYAURender(AudioUnit u, AudioUnitRenderActionFlags *fl, const AudioTimeStamp *ts, UInt32 bus, UInt32 n, AudioBufferList *io) {
    OSStatus r = orig_aurender ? orig_aurender(u, fl, ts, bus, n, io) : -50;
    if (r != noErr || bus != 1 || !io) return r;
    gMicCallsA++;
    if (!RY_FX_ON && !gMonOn) return r;
    static AudioUnit lastU; static AudioStreamBasicDescription f; static BOOL ok;
    if (u != lastU) {
        lastU = u; UInt32 sz = sizeof f; memset(&f, 0, sizeof f);
        ok = AudioUnitGetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &f, &sz) == noErr;
        snprintf(gMicFmt, sizeof gMicFmt, "A: %.0fHz %uch %ubit %s%s", f.mSampleRate, (unsigned)f.mChannelsPerFrame, (unsigned)f.mBitsPerChannel, (f.mFormatFlags & kAudioFormatFlagIsFloat) ? "float" : "int", (f.mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? " planar" : "");
    }
    if (ok) RYMicProcessASBD(&f, n, io, &gVS[0]);
    return r;
}
// ---- route U: AUAudioUnit.renderBlock (apps that drive an AUAudioUnit themselves, e.g. a custom RTCAudioDevice)
static NSMutableDictionary<NSString *, NSValue *> *gRBOrig;
// The format of the captured bus is NOT valid yet when the app asks for the block (it read 0Hz 0ch), so it is read later, off the render thread,
// and until it is known nothing is touched. If the unit never reports one, it is inferred from the buffer layout as a last resort.
typedef struct { AudioStreamBasicDescription f; volatile int have; volatile int tries; volatile int inferred; } RYUCtx;
static BOOL RYFmtFromAU(AUAudioUnit *au, AudioStreamBasicDescription *out) {
    @try {
        AUAudioUnitBusArray *ob = au.outputBusses;
        if (ob.count > 1) {
            const AudioStreamBasicDescription *p = ob[1].format.streamDescription;
            if (p && p->mFormatID == kAudioFormatLinearPCM && p->mSampleRate > 0 && p->mChannelsPerFrame && p->mBitsPerChannel) { *out = *p; return YES; }
        }
    } @catch (__unused id e) {}
    return NO;
}
// float32 audio is finite and within about +-1; int16 samples read as floats come out as NaN/huge or denormal-tiny values
static BOOL RYLooksFloat(const float *p, UInt32 count) {
    UInt32 bad = 0, tiny = 0; if (count > 256) count = 256;
    for (UInt32 i = 0; i < count; i++) { float v = p[i], a = fabsf(v); if (!(a <= 4.f)) bad++; else if (a != 0.f && a < 1e-6f) tiny++; }
    return bad == 0 && tiny == 0;
}
static BOOL RYFmtInfer(const AudioBufferList *io, UInt32 n, AudioStreamBasicDescription *o) {
    if (!n || !io->mNumberBuffers) return NO;
    const AudioBuffer *b0 = &io->mBuffers[0]; if (!b0->mData || b0->mDataByteSize < n || (b0->mDataByteSize % n)) return NO;
    memset(o, 0, sizeof *o); o->mFormatID = kAudioFormatLinearPCM; o->mSampleRate = gMicHWRate > 0 ? gMicHWRate : 48000;
    UInt32 nb = io->mNumberBuffers, per = b0->mDataByteSize / n, ch, sample;
    if (nb == 1) { ch = b0->mNumberChannels ? b0->mNumberChannels : 1; sample = per / ch; }
    else { ch = nb; sample = per; o->mFormatFlags |= kAudioFormatFlagIsNonInterleaved; }
    if (sample == 4 && nb == 1 && !RYLooksFloat((const float *)b0->mData, MIN(n * ch, b0->mDataByteSize / 4))) { sample = 2; ch *= 2; } // really 16-bit with more channels
    else if (sample == 4 && nb > 1 && !RYLooksFloat((const float *)b0->mData, MIN(n, b0->mDataByteSize / 4))) return NO;
    if (sample == 4) o->mFormatFlags |= kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    else if (sample == 2) o->mFormatFlags |= kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    else return NO;
    o->mChannelsPerFrame = ch; o->mBitsPerChannel = sample * 8; o->mFramesPerPacket = 1;
    o->mBytesPerFrame = (nb == 1) ? sample * ch : sample; o->mBytesPerPacket = o->mBytesPerFrame;
    return YES;
}
static void RYFmtText(const char *tag, const AudioStreamBasicDescription *f) {
    snprintf(gMicFmt, sizeof gMicFmt, "%s: %.0fHz %uch %ubit %s%s", tag, f->mSampleRate, (unsigned)f->mChannelsPerFrame, (unsigned)f->mBitsPerChannel, (f->mFormatFlags & kAudioFormatFlagIsFloat) ? "float" : "int", (f->mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? " planar" : "");
}
static AURenderBlock RYRBGetter(id self, SEL _cmd) {
    IMP o = NULL; for (Class k = object_getClass(self); k && !o; k = class_getSuperclass(k)) { NSValue *v = gRBOrig[NSStringFromClass(k)]; if (v) o = (IMP)[v pointerValue]; }
    AURenderBlock orig = o ? ((AURenderBlock (*)(id, SEL))o)(self, _cmd) : nil;
    if (!orig) return orig;
    BOOL cap = NO; @try { AUAudioUnit *au = (AUAudioUnit *)self; cap = (au.isInputEnabled || [NSStringFromClass(object_getClass(au)) containsString:@"IO"]) && au.outputBusses.count > 1; } @catch (__unused id e) {}
    if (!cap) return orig; // only units that really capture input
    gMicWrapped++;
    RYUCtx *cx = (RYUCtx *)calloc(1, sizeof(RYUCtx)); __weak AUAudioUnit *wau = (AUAudioUnit *)self;
    return [^AUAudioUnitStatus(AudioUnitRenderActionFlags *fl, const AudioTimeStamp *ts, AUAudioFrameCount n, NSInteger bus, AudioBufferList *io, AURenderPullInputBlock pull) {
        AUAudioUnitStatus r = orig(fl, ts, n, bus, io, pull);
        if (r != noErr || bus != 1 || !io) return r;
        long long calls = ++gMicCallsU;
        if (calls <= 3 || calls % 2000 == 0) snprintf(gMicLast, sizeof gMicLast, "frames=%u buffers=%u b0: ch=%u bytes=%u data=%d have=%d inferred=%d", (unsigned)n, (unsigned)io->mNumberBuffers, io->mNumberBuffers ? (unsigned)io->mBuffers[0].mNumberChannels : 0, io->mNumberBuffers ? (unsigned)io->mBuffers[0].mDataByteSize : 0, io->mNumberBuffers ? io->mBuffers[0].mData != NULL : 0, cx->have, cx->inferred);
        if (!RY_FX_ON && !gMonOn) return r;
        AudioStreamBasicDescription f;
        if (cx->have) f = cx->f;
        else {
            int t = cx->tries++;
            if (t % 100 == 0) { // ask the unit for its real format, away from the audio thread; until then the buffer layout is used (no waiting)
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                    AUAudioUnit *au = wau; AudioStreamBasicDescription g;
                    if (au && RYFmtFromAU(au, &g)) { cx->f = g; cx->inferred = 0; cx->have = 1; RYFmtText("U", &g); }
                });
            }
            if (!RYFmtInfer(io, n, &f)) { gMicSkip++; return r; }
            if (t == 0) { cx->inferred = 1; RYFmtText("U(inferred)", &f); }
        }
        RYMicProcessASBD(&f, n, io, &gVS[1]);
        return r;
    } copy];
}
static void RYInstallRB(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{ gRBOrig = [NSMutableDictionary new]; });
    Class base = NSClassFromString(@"AUAudioUnit"); if (!base) return;
    SEL sel = @selector(renderBlock);
    unsigned cnt = 0; Class *all = objc_copyClassList(&cnt);
    for (unsigned i = 0; i < cnt; i++) {
        Class c = all[i], k = c; BOOL isAU = NO;
        for (; k; k = class_getSuperclass(k)) if (k == base) { isAU = YES; break; }
        if (!isAU) continue;
        NSString *nm = NSStringFromClass(c); if (gRBOrig[nm]) continue;
        Method m = class_getInstanceMethod(c, sel); if (!m) continue;
        Class sup = class_getSuperclass(c); Method sm = sup ? class_getInstanceMethod(sup, sel) : NULL;
        if (c != base && m == sm) continue; // inherited, the class that really defines it gets patched
        IMP cur = method_getImplementation(m); if (cur == (IMP)RYRBGetter) continue;
        gRBOrig[nm] = [NSValue valueWithPointer:(const void *)cur];
        class_replaceMethod(c, sel, (IMP)RYRBGetter, method_getTypeEncoding(m));
    }
    free(all);
}
// ---- route T: AVAudioEngine input-node tap (the buffer is changed before the app's own block sees it)
typedef void (^RYTapBlock)(AVAudioPCMBuffer *, AVAudioTime *);
static void (*orig_tap)(id, SEL, AVAudioNodeBus, AVAudioFrameCount, AVAudioFormat *, RYTapBlock);
static void RYTapProcess(AVAudioPCMBuffer *b) {
    AVAudioFormat *f = b.format; UInt32 n = b.frameLength, ch = f.channelCount; if (!n || !ch) return;
    if (b.floatChannelData) {
        float *const *cd = b.floatChannelData;
        if (f.isInterleaved) RYProcInter(cd[0], YES, n, ch, f.sampleRate, &gVS[2]);
        else { void *pl[8]; UInt32 np = ch > 8 ? 8 : ch; for (UInt32 q = 0; q < np; q++) pl[q] = cd[q]; RYProcPlanar(pl, np, YES, n, f.sampleRate, &gVS[2]); }
    } else if (b.int16ChannelData) {
        int16_t *const *cd = b.int16ChannelData;
        if (f.isInterleaved) RYProcInter(cd[0], NO, n, ch, f.sampleRate, &gVS[2]);
        else { void *pl[8]; UInt32 np = ch > 8 ? 8 : ch; for (UInt32 q = 0; q < np; q++) pl[q] = cd[q]; RYProcPlanar(pl, np, NO, n, f.sampleRate, &gVS[2]); }
    }
}
static void RYTapInstall(id self, SEL _cmd, AVAudioNodeBus bus, AVAudioFrameCount size, AVAudioFormat *fmt, RYTapBlock blk) {
    RYTapBlock w = blk;
    if (blk && [self isKindOfClass:[AVAudioInputNode class]]) {
        gMicTapInst++;
        w = [^(AVAudioPCMBuffer *b, AVAudioTime *t) { gMicCallsT++; if (RY_FX_ON || gMonOn) RYTapProcess(b); blk(b, t); } copy];
    }
    orig_tap(self, _cmd, bus, size, fmt, w);
}
static void RYInstallTapHook(void) {
    Method m = class_getInstanceMethod([AVAudioNode class], @selector(installTapOnBus:bufferSize:format:block:));
    if (!m || orig_tap) return;
    orig_tap = (void (*)(id, SEL, AVAudioNodeBus, AVAudioFrameCount, AVAudioFormat *, RYTapBlock))method_getImplementation(m);
    method_setImplementation(m, (IMP)RYTapInstall);
}

// ---- remove the app's audio "isolation" (system voice processing, session mode, WebRTC noise/echo/AGC) so loud or effected voice is not ducked or muted
static volatile int gIsoSess = 0, gIsoVP = 0, gIsoRTC = 0, gIsoOn = 0;
static volatile long long gIsoSessN = 0, gIsoVPN = 0, gIsoVPFail = 0, gIsoEngN = 0, gIsoRTCN = 0;
// (1) the AVAudioSession mode: VoiceChat / VideoChat switch the system echo canceller, noise suppressor and AGC on
static BOOL (*orig_setMode)(id, SEL, NSString *, NSError **);
static BOOL RYSetMode(id self, SEL _cmd, NSString *m, NSError **e) { if (gIsoSess && RYIsProcMode(m) && !UIScreen.mainScreen.isCaptured) { gIsoSessN++; m = AVAudioSessionModeDefault; } return orig_setMode(self, _cmd, m, e); }
static BOOL (*orig_setCatMode)(id, SEL, NSString *, NSString *, NSUInteger, NSError **);
static BOOL RYSetCatMode(id self, SEL _cmd, NSString *c, NSString *m, NSUInteger o, NSError **e) { if (gIsoSess && RYIsProcMode(m) && !UIScreen.mainScreen.isCaptured) { gIsoSessN++; m = AVAudioSessionModeDefault; } return orig_setCatMode(self, _cmd, c, m, o, e); }
static BOOL (*orig_setCatModeRS)(id, SEL, NSString *, NSString *, NSUInteger, NSUInteger, NSError **);
static BOOL RYSetCatModeRS(id self, SEL _cmd, NSString *c, NSString *m, NSUInteger rs, NSUInteger o, NSError **e) { if (gIsoSess && RYIsProcMode(m) && !UIScreen.mainScreen.isCaptured) { gIsoSessN++; m = AVAudioSessionModeDefault; } return orig_setCatModeRS(self, _cmd, c, m, rs, o, e); }
static void RYIsoApplySession(void) { if (!gIsoSess) return; dispatch_async(dispatch_get_main_queue(), ^{ [AVAudioSession.sharedInstance setMode:AVAudioSessionModeDefault error:nil]; }); }
// (2) the voice-processing audio unit (VPIO): switch its processing off (properties 2100 = bypass, 2101 = AGC) before it initialises / starts
static OSStatus (*orig_auinit)(AudioUnit); static OSStatus (*orig_austart)(AudioUnit);
static void RYBypassVP(AudioUnit u) {
    if (!gIsoVP || !u) return; UInt32 one = 1, zero = 0;
    OSStatus a = AudioUnitSetProperty(u, 2100, kAudioUnitScope_Global, 0, &one, sizeof one);
    AudioUnitSetProperty(u, 2101, kAudioUnitScope_Global, 0, &zero, sizeof zero);
    if (a == noErr) gIsoVPN++; else gIsoVPFail++;
}
static OSStatus RYAUInit(AudioUnit u) { RYBypassVP(u); return orig_auinit ? orig_auinit(u) : -50; }
static OSStatus RYAUStart(AudioUnit u) { RYBypassVP(u); return orig_austart ? orig_austart(u) : -50; }
static BOOL (*orig_setVPE)(id, SEL, BOOL, NSError **);
static BOOL RYSetVPE(id self, SEL _cmd, BOOL on, NSError **e) { if (gIsoVP && on) { gIsoEngN++; on = NO; } return orig_setVPE(self, _cmd, on, e); }
// (3) WebRTC's own software processing: the constraints the app passes when it creates the microphone source
static id (*orig_rtcinit)(id, SEL, NSDictionary *, NSDictionary *);
static id RYRTCInit(id self, SEL _cmd, NSDictionary *m, NSDictionary *o) {
    if (gIsoRTC) {
        NSArray *keys = @[@"googEchoCancellation", @"googEchoCancellation2", @"googDAEchoCancellation", @"googAutoGainControl", @"googAutoGainControl2", @"googNoiseSuppression", @"googNoiseSuppression2", @"googHighpassFilter", @"googTypingNoiseDetection", @"echoCancellation", @"noiseSuppression", @"autoGainControl"];
        NSMutableDictionary *mm = [m mutableCopy] ?: [NSMutableDictionary new], *oo = [o mutableCopy] ?: [NSMutableDictionary new];
        for (NSString *k in keys) { if (mm[k]) mm[k] = @"false"; oo[k] = @"false"; }
        gIsoRTCN++; m = mm; o = oo;
    }
    return orig_rtcinit(self, _cmd, m, o);
}
static void RYInstallIso(void) {
    static BOOL done; if (done) return; done = YES;
    Class S = [AVAudioSession class]; Method m;
    if ((m = class_getInstanceMethod(S, @selector(setMode:error:)))) { orig_setMode = (void *)method_getImplementation(m); method_setImplementation(m, (IMP)RYSetMode); }
    if ((m = class_getInstanceMethod(S, @selector(setCategory:mode:options:error:)))) { orig_setCatMode = (void *)method_getImplementation(m); method_setImplementation(m, (IMP)RYSetCatMode); }
    if ((m = class_getInstanceMethod(S, @selector(setCategory:mode:routeSharingPolicy:options:error:)))) { orig_setCatModeRS = (void *)method_getImplementation(m); method_setImplementation(m, (IMP)RYSetCatModeRS); }
    if ((m = class_getInstanceMethod([AVAudioIONode class], @selector(setVoiceProcessingEnabled:error:)))) { orig_setVPE = (void *)method_getImplementation(m); method_setImplementation(m, (IMP)RYSetVPE); }
    unsigned cnt = 0; Class *all = objc_copyClassList(&cnt);
    for (unsigned i = 0; i < cnt && !orig_rtcinit; i++) {
        if (![NSStringFromClass(all[i]) hasSuffix:@"RTCMediaConstraints"]) continue;
        SEL sel = NSSelectorFromString(@"initWithMandatoryConstraints:optionalConstraints:");
        Method mm = class_getInstanceMethod(all[i], sel); if (!mm) continue;
        orig_rtcinit = (void *)method_getImplementation(mm); method_setImplementation(mm, (IMP)RYRTCInit);
    }
    free(all);
}
// ---- settings
static void RYMicLoad(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ double r = AVAudioSession.sharedInstance.sampleRate; if (r > 0) gMicHWRate = r; });
    gMicOn = [CF(@"micOn", @NO) boolValue]; gMicPreset = [CF(@"micPreset", @0) intValue]; gMicSemi = [CF(@"micSemi", @0) floatValue];
    gMicMode = [CF(@"micMode", @0) intValue]; gMicEcho = [CF(@"micEcho", @0) floatValue]; gMicGain = [CF(@"micGain", @1) floatValue];
    gMicDist = [CF(@"micDist", @NO) boolValue]; gMicRev = [CF(@"micRev", @NO) boolValue]; gMicMute = 0; // never restore "on": always starts unmuted so it's never silently stuck
    gStLoop = [CF(@"stLoop", @NO) boolValue]; gStVol = [CF(@"stVol", @1.0) floatValue]; gStMon = [CF(@"stMon", @YES) boolValue];
    { NSArray *rc = CF(@"revCfg", nil); // the saved echo settings only count if they were saved with the current defaults (version 2); otherwise start from the Dragonfly values
      if ([CF(@"revCfgVer", @0) intValue] == 2 && [rc isKindOfClass:NSArray.class] && rc.count == RV_N) for (int i = 0; i < RV_N; i++) gRv[i] = [rc[i] floatValue];
      else { NSMutableArray *d = [NSMutableArray new]; for (int i = 0; i < RV_N; i++) { gRv[i] = kRvDef[i]; [d addObject:@(kRvDef[i])]; } CS(@"revCfg", d); CS(@"revCfgVer", @2); } }
    gDistGain = powf(10.f, [CF(@"distDb", @60) floatValue] / 20.f); gDistOut = powf(10.f, [CF(@"distOutDb", @-3) floatValue] / 20.f); gDistGate = powf(10.f, [CF(@"distGateDb", @-55) floatValue] / 20.f);
    gIsoOn = [CF(@"isoOn", @YES) boolValue]; gIsoSess = gIsoVP = gIsoRTC = gIsoOn ? 1 : 0; // switch in the Mic tab
}
static void RYMicSetOn(BOOL on) { gMicOn = on; CS(@"micOn", @(on)); }
static void RYMicSetDist(BOOL on) { gMicDist = on; CS(@"micDist", @(on)); }
static void RYMicSetRev(BOOL on) { gMicRev = on; CS(@"micRev", @(on)); }
static void RYMicSetMute(BOOL on) { gMicMute = on; } // not persisted on purpose (see RYInit note)
static void RYRevSave(void) { NSMutableArray *a = [NSMutableArray new]; for (int i = 0; i < RV_N; i++) [a addObject:@(gRv[i])]; CS(@"revCfg", a); CS(@"revCfgVer", @2); }
static BOOL RYRevIsDefault(void) { for (int i = 0; i < RV_N; i++) if (fabsf(gRv[i] - kRvDef[i]) > 0.0005f) return NO; return YES; }
static NSString *RYRevStateText(void) { return RYRevIsDefault() ? T(@"الافتراضي ✓", @"Default ✓") : T(@"معدّل", @"Changed"); }
static void RYIsoPushNow(void);
static void RYMicSetIso(BOOL on) {
    gIsoOn = on ? 1 : 0; gIsoSess = gIsoVP = gIsoRTC = gIsoOn; CS(@"isoOn", @(on));
    if (on) { RYIsoApplySession(); RYIsoPushNow(); }
}
static void RYIsoSave(void) { CS(@"isoSess", @(gIsoSess != 0)); CS(@"isoVP", @(gIsoVP != 0)); CS(@"isoRTC", @(gIsoRTC != 0)); }
static void RYMicApplyPreset(int i) {
    if (i < 0 || i >= RY_NPRESETS) return; const RYPreset *p = &kPresets[i];
    gMicPreset = i; gMicSemi = p->semi; gMicMode = p->mode; gMicEcho = p->echo;
    CS(@"micPreset", @(i)); CS(@"micSemi", @(p->semi)); CS(@"micMode", @(p->mode)); CS(@"micEcho", @(p->echo));
}
static NSString *RYMicStatus(void) {
    long long calls = gMicCallsA + gMicCallsU + gMicCallsT;
    if (!calls) return T(@"لسا ما التقطت المايك. ادخل صوت الغرفة وافتح المايك، وبعدها تظهر الحالة هنا.", @"No microphone data seen yet. Join voice in a room and unmute; the status shows up here.");
    NSString *route = gMicCallsA ? @"A" : gMicCallsU ? @"U" : @"T";
    if (!RY_FX_ON) return [NSString stringWithFormat:T(@"المايك مرصود ✓ (مسار %@)، المغيّر مطفي.", @"Microphone detected ✓ (route %@), changer is off."), route];
    return [NSString stringWithFormat:T(@"يشتغل ✓ (مسار %@، إطارات معالجة: %lld)", @"Working ✓ (route %@, frames processed: %lld)"), route, (long long)gMicProc];
}
static NSString *RYMicStatus2(void) {
    NSString *iso = (gIsoSess || gIsoVP || gIsoRTC) ? [NSString stringWithFormat:T(@"\nإزالة العوازل: جلسة %lld، VPIO %lld (فشل %lld)، WebRTC %lld", @"\nIsolation removal: session %lld, VPIO %lld (failed %lld), WebRTC %lld"), gIsoSessN, gIsoVPN, gIsoVPFail, gIsoRTCN] : @"";
    return [RYMicStatus() stringByAppendingString:iso];
}
static NSString *RYMicReport(void) {
    return [NSString stringWithFormat:@"mic voice changer\non=%d preset=%d semi=%.1f mode=%d echo=%.2f gain=%.2f dist=%d reverb=%d monitor=%d\nroute A (AudioUnitRender bus 1): calls=%lld, images rebound=%d\nroute U (AUAudioUnit renderBlock): calls=%lld, blocks wrapped=%d\nroute T (AVAudioEngine input tap): calls=%lld, taps installed=%d\nframes processed=%lld (skipped calls=%lld)\nformat=%s\nlast buffer: %s\nhw sample rate=%.0f\nisolation removal: session=%d (forced %lld) vpio=%d (bypassed %lld, failed %lld, engine %lld) webrtc=%d (rewritten %lld)\n",
        gMicOn, gMicPreset, gMicSemi, gMicMode, gMicEcho, gMicGain, gMicDist, gMicRev, gMonOn, gMicCallsA, gMicRebound, gMicCallsU, gMicWrapped, gMicCallsT, gMicTapInst, (long long)gMicProc, (long long)gMicSkip, gMicFmt, gMicLast, gMicHWRate, gIsoSess, gIsoSessN, gIsoVP, gIsoVPN, gIsoVPFail, gIsoEngN, gIsoRTC, gIsoRTCN];
}

// minimal symbol-pointer rebinding (same idea as fishhook)
static void RYRebindImage(const struct mach_header *mh, intptr_t slide) {
    if (!mh || mh->magic != MH_MAGIC_64) return;
    Dl_info di; if (dladdr(mh, &di) && di.dli_fname && (strncmp(di.dli_fname, "/usr/lib", 8) == 0 || strncmp(di.dli_fname, "/System", 7) == 0 || strstr(di.dli_fname, "libsystem"))) return;
    const struct mach_header_64 *h = (const struct mach_header_64 *)mh;
    const struct symtab_command *st = NULL; const struct dysymtab_command *dy = NULL; const struct segment_command_64 *le = NULL;
    const uint8_t *c = (const uint8_t *)(h + 1);
    for (uint32_t i = 0; i < h->ncmds; i++, c += ((const struct load_command *)c)->cmdsize) {
        const struct load_command *lc = (const struct load_command *)c;
        if (lc->cmd == LC_SYMTAB) st = (const struct symtab_command *)lc;
        else if (lc->cmd == LC_DYSYMTAB) dy = (const struct dysymtab_command *)lc;
        else if (lc->cmd == LC_SEGMENT_64 && strcmp(((const struct segment_command_64 *)lc)->segname, SEG_LINKEDIT) == 0) le = (const struct segment_command_64 *)lc;
    }
    if (!st || !dy || !le || !dy->nindirectsyms) return;
    uintptr_t base = (uintptr_t)slide + le->vmaddr - le->fileoff;
    const struct nlist_64 *syms = (const struct nlist_64 *)(base + st->symoff);
    const char *strs = (const char *)(base + st->stroff);
    const uint32_t *ind = (const uint32_t *)(base + dy->indirectsymoff);
    BOOL did = NO;
    c = (const uint8_t *)(h + 1);
    for (uint32_t i = 0; i < h->ncmds; i++, c += ((const struct load_command *)c)->cmdsize) {
        const struct load_command *lc = (const struct load_command *)c;
        if (lc->cmd != LC_SEGMENT_64) continue;
        const struct segment_command_64 *sg = (const struct segment_command_64 *)lc;
        if (strcmp(sg->segname, "__DATA") != 0 && strcmp(sg->segname, "__DATA_CONST") != 0) continue;
        const struct section_64 *sc = (const struct section_64 *)(sg + 1);
        for (uint32_t j = 0; j < sg->nsects; j++, sc++) {
            uint32_t ty = sc->flags & SECTION_TYPE;
            if (ty != S_LAZY_SYMBOL_POINTERS && ty != S_NON_LAZY_SYMBOL_POINTERS) continue;
            void **slots = (void **)((uintptr_t)slide + sc->addr); size_t cnt = sc->size / sizeof(void *);
            const uint32_t *ix = ind + sc->reserved1; BOOL unlocked = NO;
            for (size_t k = 0; k < cnt; k++) {
                uint32_t si = ix[k];
                if (si == INDIRECT_SYMBOL_ABS || si == INDIRECT_SYMBOL_LOCAL || si == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) continue;
                const char *nm = strs + syms[si].n_un.n_strx;
                void *rep = NULL, **save = NULL;
                if (strcmp(nm, "_AudioUnitInitialize") == 0) { rep = (void *)RYAUInit; save = (void **)&orig_auinit; }
                else if (strcmp(nm, "_AudioOutputUnitStart") == 0) { rep = (void *)RYAUStart; save = (void **)&orig_austart; }
                else if (strcmp(nm, "_AudioUnitRender") == 0) { rep = (void *)RYAURender; save = (void **)&orig_aurender; if (slots[k] != rep) gMicRebound++; }
                else continue;
                if (slots[k] == rep) continue;
                if (!unlocked) { vm_protect(mach_task_self(), (vm_address_t)slots, sc->size, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY); unlocked = YES; }
                // the real function comes from dlsym (a lazy pointer that was not used yet would still point at the dyld stub helper)
                if (!*save) { void *r = dlsym(RTLD_DEFAULT, nm + 1); *save = r ?: slots[k]; }
                slots[k] = rep; did = YES;
            }
        }
    }
}



#pragma mark - Discord voice engine: its own noise cancellation (Krisp), echo, noise suppression and AGC are switched off at the source
static NSMutableDictionary<NSString *, NSValue *> *gTOOrig; static volatile int gTOCalls = 0; static char gTOLast[300] = "-";
static NSArray<NSString *> *RYVoiceKeys(void) {
    return @[@"echoCancellation", @"noiseSuppression", @"noiseCancellation", @"noiseCancellationDuringProcessing", @"automaticGainControl", @"builtInEchoCancellation", @"automaticGainControlConfig", @"vadUseKrisp", @"vadKrispActivationThreshold"];
}
static __weak id gVoiceEng;   // the DCDVoiceEngine the app talks to (seen on its first setTransportOptions call)
static NSDictionary *RYScrubOpts(NSDictionary *o) {
    NSMutableDictionary *m = [o mutableCopy];
    for (NSString *k in @[@"echoCancellation", @"noiseSuppression", @"noiseCancellation", @"noiseCancellationDuringProcessing", @"automaticGainControl", @"builtInEchoCancellation", @"vadUseKrisp"]) m[k] = @NO;
    if (m[@"vadKrispActivationThreshold"]) m[@"vadKrispActivationThreshold"] = @0;
    NSDictionary *a = m[@"automaticGainControlConfig"];
    if ([a isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *x = [a mutableCopy];
        for (NSString *k in @[@"useAGC2", @"enableAnalog", @"enableDigital"]) x[k] = @NO;
        m[@"automaticGainControlConfig"] = x;
    }
    return m;
}
static void RYTransportHook(id self, SEL _cmd, NSDictionary *o) {
    IMP orig = NULL;
    for (Class k = object_getClass(self); k && !orig; k = class_getSuperclass(k)) { NSValue *v = gTOOrig[NSStringFromClass(k)]; if (v) orig = (IMP)[v pointerValue]; }
    if ([NSStringFromClass(object_getClass(self)) isEqual:@"DCDVoiceEngine"]) gVoiceEng = self;
    NSDictionary *n = o; BOOL has = NO;
    if ([o isKindOfClass:NSDictionary.class]) for (NSString *k in RYVoiceKeys()) if (o[k]) { has = YES; break; }
    if (has && gIsoOn) {
        gTOCalls++; n = RYScrubOpts(o);
        snprintf(gTOLast, sizeof gTOLast, "%s", [[NSString stringWithFormat:@"in: %@", o] UTF8String] ?: "-");
    }
    if (orig) ((void (*)(id, SEL, NSDictionary *))orig)(self, _cmd, n);
}
// per-connection options (this is the call the app really uses for a live voice connection) and the sidechain compressor
static void (*orig_connTO)(id, SEL, NSUInteger, NSDictionary *);
static void RYConnTO(id self, SEL _cmd, NSUInteger cid, NSDictionary *o) {
    NSDictionary *n = o; BOOL has = NO;
    if ([NSStringFromClass(object_getClass(self)) isEqual:@"DCDVoiceEngine"]) gVoiceEng = self;
    if ([o isKindOfClass:NSDictionary.class]) for (NSString *k in RYVoiceKeys()) if (o[k]) { has = YES; break; }
    if (has && gIsoOn) { gTOCalls++; n = RYScrubOpts(o); snprintf(gTOLast, sizeof gTOLast, "%s", [[NSString stringWithFormat:@"conn %lu: %@", (unsigned long)cid, o] UTF8String] ?: "-"); }
    if (orig_connTO) orig_connTO(self, _cmd, cid, n);
}
static void (*orig_sidechain)(id, SEL, BOOL);
static void RYSidechain(id self, SEL _cmd, BOOL on) {
    if (gIsoOn && on) { gTOCalls++; on = NO; }
    if (orig_sidechain) orig_sidechain(self, _cmd, on);
}
static void RYIsoPushNow(void) {   // switch turned on while a voice call is running: send the "all off" options straight away
    id e = gVoiceEng; if (!e) return;
    SEL mq = NSSelectorFromString(@"methodQueue");
    dispatch_queue_t q = [e respondsToSelector:mq] ? ((dispatch_queue_t (*)(id, SEL))objc_msgSend)(e, mq) : nil;
    void (^blk)(void) = ^{
        id x = gVoiceEng; if (!x) return;
        NSDictionary *d = @{@"echoCancellation": @NO, @"noiseSuppression": @NO, @"noiseCancellation": @NO, @"noiseCancellationDuringProcessing": @NO, @"automaticGainControl": @NO, @"builtInEchoCancellation": @NO, @"vadUseKrisp": @NO};
        @try {
            ((void (*)(id, SEL, id))objc_msgSend)(x, NSSelectorFromString(@"setTransportOptions:"), d);
            ((void (*)(id, SEL, BOOL))objc_msgSend)(x, NSSelectorFromString(@"setSidechainCompression:"), NO);
        } @catch (__unused id ex) {}
    };
    dispatch_async(q ?: dispatch_get_main_queue(), blk);
}
static void RYInstallVoiceHook2(void) {
    Class c = NSClassFromString(@"DCDVoiceEngine"); if (!c) return;
    static BOOL a, b;
    if (!a) { Method m = class_getInstanceMethod(c, NSSelectorFromString(@"connectionInstanceSetTransportOptions:options:")); if (m && method_getNumberOfArguments(m) == 4) { orig_connTO = (void *)method_getImplementation(m); method_setImplementation(m, (IMP)RYConnTO); a = YES; } }
    if (!b) { Method m = class_getInstanceMethod(c, NSSelectorFromString(@"setSidechainCompression:")); if (m && method_getNumberOfArguments(m) == 3) { orig_sidechain = (void *)method_getImplementation(m); method_setImplementation(m, (IMP)RYSidechain); b = YES; } }
}
static void RYInstallVoiceHook(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{ gTOOrig = [NSMutableDictionary new]; });
    SEL sel = NSSelectorFromString(@"setTransportOptions:");
    unsigned cnt = 0; Class *all = objc_copyClassList(&cnt);
    for (unsigned i = 0; i < cnt; i++) {
        Class c = all[i]; NSString *nm = NSStringFromClass(c);
        if (!([nm hasPrefix:@"DCD"] || [nm containsString:@"VoiceEngine"] || [nm containsString:@"Voice"])) continue; // app's own classes only
        if (gTOOrig[nm]) continue;
        Method m = class_getInstanceMethod(c, sel); if (!m || method_getNumberOfArguments(m) != 3) continue;
        Class sup = class_getSuperclass(c); Method sm = sup ? class_getInstanceMethod(sup, sel) : NULL;
        if (sm && m == sm) continue; // inherited: the class that really defines it gets patched
        IMP cur = method_getImplementation(m); if (cur == (IMP)RYTransportHook) continue;
        gTOOrig[nm] = [NSValue valueWithPointer:(const void *)cur];
        class_replaceMethod(c, sel, (IMP)RYTransportHook, method_getTypeEncoding(m));
    }
    free(all);
    RYInstallVoiceHook2();
}

static void RYInstallRebind(void) {
    static BOOL once; if (once) return; once = YES;
    _dyld_register_func_for_add_image(RYRebindImage); // calls back for every loaded image now and for later ones
}
static void RYInstallMic(void) {
    RYMicLoad(); RYInstallRebind(); RYInstallTapHook(); RYInstallRB(); RYInstallIso(); RYIsoApplySession(); RYInstallVoiceHook();
    for (NSNumber *sec in @[@2, @6, @15]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sec.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ RYInstallRB(); RYInstallVoiceHook(); }); // classes may load late
}



#pragma mark - Chat text colour (auto contrast with the wallpaper, or a colour the owner picks)
static CGFloat RYLum(UIColor *c) {
    CGFloat r = 0, g = 0, b = 0, a = 0; if (![c getRed:&r green:&g blue:&b alpha:&a]) { CGFloat w = 0; [c getWhite:&w alpha:&a]; r = g = b = w; }
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
static CGFloat RYImgLum(UIImage *im) {
    if (!im.CGImage) return 0; unsigned char px[4] = {0, 0, 0, 255};
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef x = CGBitmapContextCreate(px, 1, 1, 8, 4, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big); CGColorSpaceRelease(cs);
    if (!x) return 0; CGContextSetInterpolationQuality(x, kCGInterpolationMedium);
    CGContextDrawImage(x, CGRectMake(0, 0, 1, 1), im.CGImage); CGContextRelease(x);
    return 0.2126 * px[0] / 255.0 + 0.7152 * px[1] / 255.0 + 0.0722 * px[2] / 255.0;
}
// brightness of what the wallpaper really looks like (after the dim layer), 0 = black, 1 = white
static CGFloat RYBGLum(void) {
    NSString *m = CF(@"bgMode", @"none"), *v = CF(@"bgValue", @""); CGFloat l = 0;
    if ([m isEqual:@"color"]) l = RYLum(RYHex(v));
    else if ([m isEqual:@"gradient"]) { NSArray *p = [v componentsSeparatedByString:@","]; if (p.count >= 2) l = (RYLum(RYHex(p[0])) + RYLum(RYHex(p[1]))) / 2; }
    else if ([m isEqual:@"image"]) {
        static NSInteger cachedStamp = -1; static CGFloat cachedL = 0; static NSString *cachedKey;
        NSString *path = [RYDir(nil) stringByAppendingPathComponent:@"bg.jpg"];
        NSDate *mod = [[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil] fileModificationDate];
        NSString *key = [NSString stringWithFormat:@"%f", mod.timeIntervalSince1970];
        if (!cachedKey || ![cachedKey isEqual:key]) { cachedKey = key; cachedL = RYImgLum([UIImage imageWithContentsOfFile:path]); }
        (void)cachedStamp; l = cachedL;
    }
    CGFloat dim = [CF(@"dim", @30) floatValue] / 100.0 * 0.9;
    return l * (1 - dim);
}
static UIColor *RYTextTarget(void) {
    NSString *mode = CF(@"txtMode", @"auto");
    if ([mode isEqual:@"off"]) return nil;
    if ([mode isEqual:@"custom"]) return RYHex(CF(@"txtColor", @"#FFFFFF"));
    return RYBGLum() > 0.5 ? UIColor.blackColor : UIColor.whiteColor;
}
// only plain/greyish text is recoloured: mentions, links, role colours, red/green etc. keep their own colour
static BOOL RYIsGreyish(UIColor *c) {
    if (!c) return YES;
    UIColor *r = [c resolvedColorWithTraitCollection:[UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark]];
    CGFloat h = 0, s = 0, b = 0, a = 0; if (![r getHue:&h saturation:&s brightness:&b alpha:&a]) return YES;
    return s < 0.22;
}
static BOOL RYSameColor(UIColor *a, UIColor *b) {
    CGFloat r1 = 0, g1 = 0, b1 = 0, a1 = 0, r2 = 0, g2 = 0, b2 = 0, a2 = 0;
    [[a resolvedColorWithTraitCollection:UITraitCollection.currentTraitCollection] getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    [[b resolvedColorWithTraitCollection:UITraitCollection.currentTraitCollection] getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    return fabs(r1 - r2) + fabs(g1 - g2) + fabs(b1 - b2) < 0.02;
}
static NSAttributedString *RYRecolor(NSAttributedString *in, UIColor *to, BOOL all, BOOL *changed) {
    NSMutableAttributedString *m = [in mutableCopy]; __block BOOL ch = NO;
    [in enumerateAttribute:NSForegroundColorAttributeName inRange:NSMakeRange(0, in.length) options:0 usingBlock:^(id val, NSRange rg, BOOL *stop) {
        if ((!all && !RYIsGreyish(val)) || (val && RYSameColor(val, to))) return;
        [m addAttribute:NSForegroundColorAttributeName value:to range:rg]; ch = YES;
    }];
    *changed = ch; return m;
}
static void RYTintYY(UIView *v, UIColor *to, BOOL all) {
    SEL g = @selector(attributedText), st = @selector(setAttributedText:);
    if (![v respondsToSelector:g] || ![v respondsToSelector:st]) return;
    NSAttributedString *at = ((id (*)(id, SEL))objc_msgSend)(v, g);
    if (![at isKindOfClass:NSAttributedString.class] || !at.length) return;
    BOOL ch = NO; NSAttributedString *n = RYRecolor(at, to, all, &ch);
    if (ch) ((void (*)(id, SEL, id))objc_msgSend)(v, st, n);
}
static void RYTintText(UIView *v, UIColor *to, int d) {
    if (d > 40 || !v || RYSkipClass(v)) return;
    if (RYIsInputClass(v) || [v isKindOfClass:UIButton.class]) return;
    if ([NSStringFromClass(v.class) hasSuffix:@"YYLabel"]) { RYTintYY(v, to, NO); return; }
    if ([v isKindOfClass:UILabel.class]) {
        UILabel *l = (UILabel *)v;
        if (l.attributedText.length) { BOOL ch = NO; NSAttributedString *n = RYRecolor(l.attributedText, to, NO, &ch); if (ch) l.attributedText = n; }
        else if (l.text.length && RYIsGreyish(l.textColor) && !RYSameColor(l.textColor, to)) l.textColor = to;
    } else if ([v isKindOfClass:UITextView.class]) {
        UITextView *t = (UITextView *)v;
        if (t.attributedText.length) { BOOL ch = NO; NSAttributedString *n = RYRecolor(t.attributedText, to, NO, &ch); if (ch) { NSRange sel = t.selectedRange; t.attributedText = n; t.selectedRange = sel; } }
    }
    for (UIView *s in v.subviews) RYTintText(s, to, d + 1);
}


#pragma mark - Message logger (every chat): a message someone deletes stays in the list, in red. Always on, no switch.
// Hooks DCDChatViewController updateRows:... (the list JS sends to the native chat). Every update is compared with the previous one of the same
// chat; a message that disappeared is a deleted one: its row object is kept and put back at its place.
// Cheap on purpose: one pass over the rows, selector calls instead of KVC, a small LRU of chats. Anything unexpected = the call passes through untouched.
static NSMutableDictionary<NSString *, NSDictionary *> *gLogPrev;           // channel -> {id -> row} exactly as JS last sent it
static NSMutableDictionary<NSString *, NSMutableDictionary *> *gLogDel;     // channel -> {id -> {row, n (id number), before, after}}
static NSMutableDictionary<NSString *, NSNumber *> *gLogAsc;                // channel -> list order seen (YES = oldest first)
static NSMutableArray<NSString *> *gLogChans;                               // channels, least recently used first (max 12 kept)
static NSMutableSet<NSString *> *gLogIds;                                   // ids of the kept messages (cells use it to paint red)
static volatile int gLogUpd = 0, gLogKept = 0, gLogPut = 0, gLogSkip = 0; static char gLogLast[200] = "-";
static void (*orig_updRows)(id, SEL, NSArray *, BOOL, id, id, BOOL, BOOL, BOOL);
static void (*orig_cellCfg)(id, SEL, id, id, id);
static SEL sLMsg, sLId, sLChan, sLNonce, sLInv;
#define RY_RED [UIColor colorWithRed:1.0 green:0.27 blue:0.27 alpha:1]
static id RYKV(id o, NSString *k) { if (!o) return nil; @try { return [o valueForKey:k]; } @catch (__unused id e) { return nil; } }
static NSString *RYStr(id v) {
    if (!v || v == NSNull.null) return nil;
    NSString *s = [v isKindOfClass:NSString.class] ? v : [v description]; return s.length ? s : nil;
}
static void RYLogInit(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{
        sLMsg = NSSelectorFromString(@"message"); sLId = NSSelectorFromString(@"id"); sLChan = NSSelectorFromString(@"channelID");
        sLNonce = NSSelectorFromString(@"nonce"); sLInv = NSSelectorFromString(@"inverted");
        gLogPrev = [NSMutableDictionary new]; gLogDel = [NSMutableDictionary new]; gLogAsc = [NSMutableDictionary new];
        gLogChans = [NSMutableArray new]; gLogIds = [NSMutableSet new];
    });
}
static id RYGet(id o, SEL s) { return (o && s && [o respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil; }
static id RYRowMsg(id row) {
    static Class mc; static dispatch_once_t once; dispatch_once(&once, ^{ mc = NSClassFromString(@"DCDMessageModel"); });
    if (!row || !mc) return nil;
    if (!sLMsg) sLMsg = NSSelectorFromString(@"message");
    id m = RYGet(row, sLMsg); return (m && [m isKindOfClass:mc]) ? m : nil;
}
static unsigned long long RYNum(NSString *s) { return s.length ? strtoull(s.UTF8String, NULL, 10) : 0; }
static BOOL RYIsPending(id m, NSString *mid) { NSString *n = RYStr(RYGet(m, sLNonce)); return n && [n isEqual:mid]; } // a message still being sent has id == nonce
static void RYPaintRow(id m) { @try { [m setValue:RY_RED forKey:@"textColor"]; } @catch (__unused id e) {} }
static NSString *RYLoggerStatus(void) {
    return [NSString stringWithFormat:T(@"المسجّل: تحديثات %d، محفوظة %d، معادة %d", @"Logger: updates %d, kept %d, restored %d"), gLogUpd, gLogKept, gLogPut];
}

static void RYUpdRows(id self, SEL _cmd, NSArray *rows, BOOL top, id sc, id cs, BOOL hack, BOOL force, BOOL anim) {
    NSArray *use = rows; BOOL reload = NO;
    @try {
        if ([rows isKindOfClass:NSArray.class] && rows.count) {
            RYLogInit(); gLogUpd++;
            // 1. what JS sent now: message rows with their ids, in list order
            NSString *chan = nil; NSMutableArray<NSString *> *ids = [NSMutableArray new]; NSMutableDictionary *cur = [NSMutableDictionary new];
            for (id row in rows) {
                id m = RYRowMsg(row); if (!m) continue;
                NSString *mid = RYStr(RYGet(m, sLId)); if (!mid) continue;
                if (!chan) chan = RYStr(RYGet(m, sLChan));
                [ids addObject:mid]; cur[mid] = row;
            }
            static BOOL logged; if (!logged) { logged = YES; RYLog(@"logger: first update, rows=%lu first=%@ msgRows=%lu chan=%@", (unsigned long)rows.count, NSStringFromClass([rows.firstObject class]), (unsigned long)ids.count, chan); }
            if (chan && ids.count) @synchronized (gLogDel) {
                unsigned long long mn = ULLONG_MAX, mx = 0;
                for (NSString *k in ids) { unsigned long long v = RYNum(k); if (v < mn) mn = v; if (v > mx) mx = v; }
                // small LRU of chats
                [gLogChans removeObject:chan]; [gLogChans addObject:chan];
                while (gLogChans.count > 12) {
                    NSString *old = gLogChans.firstObject; for (NSString *q in gLogDel[old]) [gLogIds removeObject:q];
                    [gLogDel removeObjectForKey:old]; [gLogPrev removeObjectForKey:old]; [gLogAsc removeObjectForKey:old]; [gLogChans removeObjectAtIndex:0];
                }
                NSMutableDictionary *del = gLogDel[chan]; if (!del) { del = [NSMutableDictionary new]; gLogDel[chan] = del; }
                // list order: oldest first (asc) or newest first
                BOOL asc;
                if (ids.count >= 2 && RYNum(ids.firstObject) != RYNum(ids.lastObject)) { asc = RYNum(ids.firstObject) < RYNum(ids.lastObject); gLogAsc[chan] = @(asc); }
                else if (gLogAsc[chan]) asc = [gLogAsc[chan] boolValue];
                else { BOOL inv = NO; if ([self respondsToSelector:sLInv]) inv = ((BOOL (*)(id, SEL))objc_msgSend)(self, sLInv); asc = !inv; }
                // 2. messages that were in the last list and are gone now
                NSDictionary *prev = gLogPrev[chan];
                if (prev.count) {
                    NSUInteger added = 0; for (NSString *k in ids) if (!prev[k]) added++;
                    NSMutableArray<NSString *> *missing = [NSMutableArray new];
                    for (NSString *k in prev) if (!cur[k] && !del[k]) [missing addObject:k];
                    // nothing new arrived and only a few rows vanished = a plain removal, wherever it is in the list
                    BOOL pure = (added == 0 && missing.count <= 3 && prev.count >= 3);
                    for (NSString *k in missing) {
                        id row = prev[k]; id m = RYRowMsg(row);
                        if (!m || RYIsPending(m, k)) { gLogSkip++; continue; }
                        unsigned long long n = RYNum(k), before = 0, after = 0;
                        for (NSString *q in prev) { unsigned long long v = RYNum(q); if (v < n && v > before) before = v; if (v > n && (!after || v < after)) after = v; }
                        BOOL inside = n > mn && n < mx;
                        BOOL tail = n > mx && before == mx;   // the newest message was deleted
                        if (!(pure || inside || tail)) { gLogSkip++; continue; }
                        del[k] = @{@"row": row, @"n": @(n), @"before": @(before), @"after": @(after)};
                        [gLogIds addObject:k]; RYPaintRow(m); gLogKept++;
                        const char *rule = pure ? "removed" : inside ? "inside" : "tail";
                        snprintf(gLogLast, sizeof gLogLast, "kept %s rule=%s chan=%s", k.UTF8String, rule, chan.UTF8String);
                        RYLog(@"logger: kept %@ (chan %@, %s)", k, chan, rule);
                        if (del.count > 300) { NSString *oldest = nil; unsigned long long best = ULLONG_MAX; for (NSString *q in del) { unsigned long long v = RYNum(q); if (v < best) { best = v; oldest = q; } } if (oldest) { [del removeObjectForKey:oldest]; [gLogIds removeObject:oldest]; } }
                    }
                }
                // 3. a kept message that JS sends again is not deleted after all
                for (NSString *k in [del allKeys]) if (cur[k]) { [del removeObjectForKey:k]; [gLogIds removeObject:k]; }
                gLogPrev[chan] = cur;
                // 4. put the kept messages back at their place
                if (del.count) {
                    NSMutableArray *out = nil;
                    NSArray *keys = [del.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { unsigned long long x = RYNum(a), y = RYNum(b); return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame; }];
                    for (NSString *k in keys) {
                        NSDictionary *r = del[k]; unsigned long long n = [r[@"n"] unsignedLongLongValue], before = [r[@"before"] unsignedLongLongValue], after = [r[@"after"] unsignedLongLongValue];
                        BOOL ok = (n > mn && n < mx) || (n > mx && before == mx) || (n < mn && after == mn);
                        if (!ok) continue;
                        if (!out) out = [rows mutableCopy];
                        id m = RYRowMsg(r[@"row"]); RYPaintRow(m);
                        NSInteger at = -1, lastMsg = -1;
                        for (NSUInteger i = 0; i < out.count; i++) {
                            id mm = RYRowMsg(out[i]); if (!mm) continue; lastMsg = (NSInteger)i;
                            unsigned long long q = RYNum(RYStr(RYGet(mm, sLId)));
                            if (asc ? q > n : q < n) { at = (NSInteger)i; break; }
                        }
                        if (at < 0) at = lastMsg + 1;
                        [out insertObject:r[@"row"] atIndex:(NSUInteger)at]; gLogPut++; reload = YES;
                    }
                    if (reload) use = out;
                }
            }
        }
        // chat text colour straight on the message models (wallpaper contrast / chosen colour); kept messages stay red
        if (gBgActive) {
            UIColor *tc = RYTextTarget();
            if (tc) for (id row in use) { id m = RYRowMsg(row); NSString *mid = m ? RYStr(RYGet(m, sLId)) : nil; if (m && !(mid && [gLogIds containsObject:mid])) { @try { [m setValue:tc forKey:@"textColor"]; } @catch (__unused id e) {} } }
        }
    } @catch (NSException *e) { RYLog(@"logger: error %@", e); use = rows; reload = NO; }
    // a list with put-back rows is reloaded in one go (no incremental row diff against the list the app expects) = no crash
    orig_updRows(self, _cmd, use, top, sc, cs, hack, reload ? YES : force, reload ? NO : anim);
}
// every message cell: kept messages get a red wash and red text; every other cell gets the chat text colour
// The username label above the message body already carries Discord's own per-sender colour (role
// colour, etc). Rather than guess the private model path to that colour, we just read it straight off
// the label Discord already rendered: the topmost UILabel in the cell that isn't the body label itself.
static UILabel *RYFindUsernameLabel(UIView *root, UIView *exclude, int depth) {
    if (!root || depth > 6) return nil;
    UILabel *best = nil; CGFloat bestY = CGFLOAT_MAX;
    for (UIView *s in root.subviews) {
        if ([s isKindOfClass:UILabel.class] && s != exclude && s.frame.origin.y < bestY) { bestY = s.frame.origin.y; best = (UILabel *)s; }
        UILabel *r = RYFindUsernameLabel(s, exclude, depth + 1);
        if (r && r.frame.origin.y < bestY) { bestY = r.frame.origin.y; best = r; }
    }
    return best;
}
static void RYDecorateCell(UITableViewCell *cell, id vm) {
    id m = RYKV(vm, @"message"); NSString *mid = m ? RYStr(RYKV(m, @"id")) : nil;
    BOOL del = mid && [gLogIds containsObject:mid];
    UIView *wash = [cell.contentView viewWithTag:8871];
    if (del) {
        if (!wash) { wash = [[UIView alloc] initWithFrame:cell.contentView.bounds]; wash.tag = 8871; wash.userInteractionEnabled = NO; wash.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; [cell.contentView insertSubview:wash atIndex:0]; }
        wash.backgroundColor = [RY_RED colorWithAlphaComponent:0.16];
    } else if (wash) [wash removeFromSuperview];
    id lab = RYKV(cell, @"contentLabel");
    if ([lab isKindOfClass:UIView.class]) {
        if (del) RYTintYY(lab, RY_RED, YES);
        else if (gBgActive) { UIColor *tc = RYTextTarget(); if (tc) RYTintYY(lab, tc, NO); }
        else { UILabel *uname = RYFindUsernameLabel(cell.contentView, (UIView *)lab, 0); if (uname.textColor) RYTintYY(lab, uname.textColor, NO); }
    }
}
static void RYCellCfg(id self, SEL _cmd, id vm, id pool, id am) {
    orig_cellCfg(self, _cmd, vm, pool, am);
    @try { RYDecorateCell((UITableViewCell *)self, vm); } @catch (__unused id e) {}
}
static void RYInstallLogger(void) {
    static BOOL done; if (done) return;
    Class vc = NSClassFromString(@"DCDChatViewController"), cc = NSClassFromString(@"DCDMessageTableViewCell");
    if (!vc || !cc) return;
    SEL us = NSSelectorFromString(@"updateRows:isLoadingAtTop:scrollData:changesetUpdateId:HACK_iOSForceAnimations:forceReload:isAnimated:");
    SEL cs = NSSelectorFromString(@"configureWithViewModel:viewReusePoolManager:actionManager:");
    Method um = class_getInstanceMethod(vc, us), cm = class_getInstanceMethod(cc, cs);
    if (!um || method_getNumberOfArguments(um) != 9 || !cm || method_getNumberOfArguments(cm) != 5) { RYLog(@"logger: methods not found / different shape (update %d cell %d)", um ? (int)method_getNumberOfArguments(um) : -1, cm ? (int)method_getNumberOfArguments(cm) : -1); done = YES; return; }
    done = YES;
    orig_updRows = (void *)method_getImplementation(um); method_setImplementation(um, (IMP)RYUpdRows);
    orig_cellCfg = (void *)method_getImplementation(cm); method_setImplementation(cm, (IMP)RYCellCfg);
    RYLog(@"logger: installed");
}

#pragma mark - Discord helpers (chat screen, send button, diagnostics)
static UIView *RYFindViewNamed(UIView *v, NSString *needle, int d) {
    if (!v || d > 30) return nil;
    if (!v.hidden && v.window && [NSStringFromClass(v.class) containsString:needle]) return v;
    for (UIView *s in v.subviews) { UIView *r = RYFindViewNamed(s, needle, d + 1); if (r) return r; }
    return nil;
}
static void RYClearCells(UIView *v, int d) {
    if (d > 9) return;
    for (UIView *s in v.subviews) {
        if (RYSkipClass(s)) continue;
        NSString *c = NSStringFromClass(s.class);
        if ((([s isKindOfClass:UITableViewCell.class] || [s isKindOfClass:UICollectionViewCell.class]) || [c containsString:@"Cell"] || [c containsString:@"Row"]) && RYHasBG(s)) RYClear(s);
        if ([s isKindOfClass:UITableViewCell.class] && RYHasBG(((UITableViewCell *)s).contentView)) RYClear(((UITableViewCell *)s).contentView);
        if ([s isKindOfClass:UICollectionViewCell.class] && RYHasBG(((UICollectionViewCell *)s).contentView)) RYClear(((UICollectionViewCell *)s).contentView);
        RYClearCells(s, d + 1);
    }
}
// Every chat input registers itself when it enters a window, so it is found even when the view tree is too deep / too odd for the scan.
static NSHashTable *gLiveInputs; static NSMutableSet<NSString *> *gInputHooked;
static void RYNoteInput(UIView *v) {
    if (!v.window) return;
    if (!gLiveInputs) gLiveInputs = [NSHashTable weakObjectsHashTable];
    [gLiveInputs addObject:v];
}
static void RYHookInputClass(NSString *cn) {
    Class c = NSClassFromString(cn); if (!c) return;
    if (!gInputHooked) gInputHooked = [NSMutableSet new];
    if ([gInputHooked containsObject:cn]) return;
    SEL s = @selector(didMoveToWindow);
    Method m = class_getInstanceMethod(c, s); if (!m) return;
    [gInputHooked addObject:cn];
    IMP orig = method_getImplementation(m);
    void (^blk)(UIView *) = ^(UIView *me) { ((void (*)(id, SEL))orig)(me, s); RYNoteInput(me); };
    IMP ni = imp_implementationWithBlock(blk);
    if (!class_addMethod(c, s, ni, method_getTypeEncoding(m))) method_setImplementation(m, ni);
}
static void RYHookInputs(void) { for (NSString *n in @[@"DCDChatInput", @"RCTUITextView", @"YYTextView"]) RYHookInputClass(n); }
// on screen even if an ancestor is semi-transparent (animations / fades); only hidden ancestors or off-screen count as not there
static BOOL RYOnScreenLoose(UIView *v) {
    if (!v.window) return NO;
    for (UIView *p = v; p; p = p.superview) if (p.hidden) return NO;
    CGRect f = CGRectIntersection([v convertRect:v.bounds toView:nil], v.window.bounds);
    return !CGRectIsNull(f) && f.size.width > 10 && f.size.height > 8;
}
static UIView *RYLowestOf(NSArray *c, int tier) {
    UIView *best = nil; CGFloat by = -1e9;
    for (UIView *x in c) {
        if ([NSStringFromClass(x.window.class) isEqual:@"RYWindow"]) continue;
        if (!RYIsInputClass(x)) continue;
        BOOL ok = tier == 0 ? RYVisibleMin(x, 20, 12) : RYOnScreenLoose(x);
        if (!ok) continue;
        CGFloat y = CGRectGetMaxY([x convertRect:x.bounds toView:nil]); if (y > by) { by = y; best = x; }
    }
    return best;
}
static UIView *RYLowestInput(void) {
    RYHookInputs();
    NSMutableArray *scan = [NSMutableArray new], *chat = [NSMutableArray new];
    for (UIView *x in gLiveInputs.allObjects) if (x.window && [NSStringFromClass(x.class) isEqual:@"DCDChatInput"]) [chat addObject:x];
    for (UIWindow *w in RYAppWindows()) RYCollectInputs(w, scan, 0);
    // 1) the app's own chat input, strictly visible  2) any visible text input  3) the same, relaxed  4) any registered input in a window
    UIView *r = RYLowestOf(chat, 0); if (r) return r;
    r = RYLowestOf(scan, 0); if (r) return r;
    r = RYLowestOf(chat, 1); if (r) return r;
    r = RYLowestOf(scan, 1); if (r) return r;
    NSMutableArray *all = [NSMutableArray new]; for (UIView *x in gLiveInputs.allObjects) if (x.window && ![NSStringFromClass(x.window.class) isEqual:@"RYWindow"]) [all addObject:x];
    return RYLowestOf(all, 1);
}

// the visible chat screen. 1) a view controller whose class contains the needle (the saved one, then the known Discord names),
// 2) a plain view with that class name, 3) class-free guess: the full-screen container that holds a big scroll view and a text input low on the screen
static BOOL RYHasBigScroll(UIView *host) {
    __block BOOL ok = NO; CGSize ws = host.window.bounds.size;
    RYWalk(host, 0, ^(UIView *v, int d) {
        if (ok || d > 9 || v.hidden || ![v isKindOfClass:UIScrollView.class]) return;
        CGSize s = [v convertRect:v.bounds toView:nil].size;
        if (s.width >= ws.width * 0.85 && s.height >= ws.height * 0.35) ok = YES;
    });
    return ok;
}
static UIView *RYGuessChatHost(void) {
    UIView *in = RYLowestInput(); if (!in) return nil;
    UIWindow *w = in.window; if (!w) return nil;
    if (CGRectGetMaxY([in convertRect:in.bounds toView:nil]) < w.bounds.size.height * 0.55) return nil;
    for (UIView *p = in.superview; p && p != w; p = p.superview) {
        CGSize s = [p convertRect:p.bounds toView:w].size;
        if (s.width >= w.bounds.size.width * 0.9 && s.height >= w.bounds.size.height * 0.6) return RYHasBigScroll(p) ? p : nil;
    }
    return nil;
}
static NSString *gChatHostHow = @"-";
static __weak UIView *gLastChat;
static UIView *RYChatHostRaw(void) {
    NSMutableArray *needles = [NSMutableArray new];
    NSString *cfg = CF(@"roomClass", nil); if (cfg.length) [needles addObject:cfg];
    for (NSString *n in @[@"DCDChatViewController", @"ChatViewController"]) if (![needles containsObject:n]) [needles addObject:n];
    for (NSString *needle in needles) {
        UIView *best = nil; CGFloat bestA = 0;
        for (UIWindow *w in RYAppWindows()) {
            NSMutableArray *vcs = [NSMutableArray new]; RYScanAll(w.rootViewController, needle, 0, vcs);
            for (UIViewController *vc in vcs) {
                if (!RYVisible(vc.view)) continue;
                CGSize z = vc.view.bounds.size; CGFloat a = z.width * z.height;
                if (a > bestA) { bestA = a; best = vc.view; }
            }
        }
        if (best) { gChatHostHow = [@"vc:" stringByAppendingString:needle]; return best; }
        for (UIWindow *w in RYAppWindows()) { UIView *r = RYFindViewNamed(w, needle, 0); if (r && RYVisible(r)) { gChatHostHow = [@"view:" stringByAppendingString:needle]; return r; } }
    }
    UIView *g = RYGuessChatHost(); gChatHostHow = g ? @"guess" : @"none";
    return g;
}
// the chat screen found last time is kept for as long as it is still on screen, so a transition / keyboard animation / a second matching
// controller cannot make the wallpaper jump to another view (every jump tore the wallpaper down and rebuilt it = flicker to black)
static UIView *RYChatHost(void) {
    UIView *last = gLastChat;
    if (last && RYVisible(last)) { gChatHostHow = @"sticky"; return last; }
    UIView *h = RYChatHostRaw(); gLastChat = h; return h;
}

// geometry fallback: the small tappable view next to the text field (outside it, on the trailing side) that is not emoji / sticker / mic / attach
static NSArray<NSString *> *RYNotSendWords(void) {
    return @[@"sticker", @"emoji", @"gif", @"mic", @"voice", @"record", @"camera", @"attach", @"photo", @"gift", @"apps", @"plus", @"add", @"صوت", @"ملصق", @"إضافة"];
}
static UIView *RYGeoSend(UIView *in) {
    UIWindow *w = in.window; if (!w) return nil;
    UIView *bar = nil, *p = in;
    for (int i = 0; i < 8 && p.superview && p.superview != w; i++) {
        p = p.superview; CGSize s = [p convertRect:p.bounds toView:nil].size;
        if (s.height > 260) break;
        if (s.width >= w.bounds.size.width * 0.8) bar = p;
    }
    if (!bar) bar = in.superview; if (!bar) return nil;
    CGRect fi = [in convertRect:in.bounds toView:nil];
    BOOL rtl = UIApplication.sharedApplication.userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    NSArray *bad = RYNotSendWords();
    __block UIView *best = nil; __block CGFloat bestX = rtl ? 1e9 : -1e9;
    RYWalk(bar, 0, ^(UIView *v, int d) {
        if (v == in || v.hidden || v.alpha < 0.05 || !v.window) return;
        BOOL tappable = [v isKindOfClass:UIControl.class] || v.isAccessibilityElement;
        if (!tappable) for (UIGestureRecognizer *g in v.gestureRecognizers) if ([g isKindOfClass:UITapGestureRecognizer.class]) { tappable = YES; break; }
        if (!tappable) return;
        CGRect f = [v convertRect:v.bounds toView:nil];
        if (f.size.width < 24 || f.size.width > 80 || f.size.height < 24 || f.size.height > 80) return;
        CGFloat cy = CGRectGetMidY(f), cx = CGRectGetMidX(f);
        if (cy < fi.origin.y - 60 || cy > CGRectGetMaxY(fi) + 60) return;
        if (cx > fi.origin.x && cx < CGRectGetMaxX(fi)) return;
        NSString *k = [v isKindOfClass:UIControl.class] ? RYCtlKey((UIControl *)v) : RYA11yKey(v);
        for (NSString *x in bad) if ([k containsString:x]) return;
        if (rtl ? cx < bestX : cx > bestX) { bestX = cx; best = v; }
    });
    return best;
}
// last resort: the app's own "send tapped" handler on the object that owns the input (zero-argument names only, so no wrong-type argument can reach it)
static BOOL RYSendViaSelectors(UIView *in) {
    NSArray *names = @[@"handleSendButtonTap", @"handleSendTap", @"sendButtonTapped", @"sendButtonPressed", @"didTapSendButton", @"didTapSend", @"onSendButtonPress", @"handleSendButtonPress"];
    NSMutableArray *objs = [NSMutableArray new];
    id dl = RYMsg0(in, @selector(delegate)); if (dl) [objs addObject:dl];
    for (UIResponder *r = in; r; r = r.nextResponder) [objs addObject:r];
    for (id o in objs) for (NSString *n in names) {
        SEL s = NSSelectorFromString(n); if (![o respondsToSelector:s]) continue;
        ((void (*)(id, SEL))objc_msgSend)(o, s); return YES;
    }
    return NO;
}
// attempt 0: the button called "send" (UIControl, then accessibility element, then its tap recognizers)
// 1: the small button beside the field  2: the app's own send handler  3: return key
static BOOL RYPressSend(UIView *in, int attempt) {
    if (attempt == 1) { UIView *g = RYGeoSend(in); if (!g) return NO; if (g.isAccessibilityElement && [g accessibilityActivate]) return YES; return RYTapView(g); }
    if (attempt == 2) return RYSendViaSelectors(in);
    if (attempt >= 3) { RYPressReturn(in); return YES; }
    UIControl *btn = RYSendBtnNear(in);
    if (btn) { [btn sendActionsForControlEvents:UIControlEventTouchUpInside]; return YES; }
    NSString *lbl = [CF(@"sendLabel", @"send") lowercaseString];
    NSArray *bad = RYNotSendWords();
    UIView *p = in;
    for (int i = 0; i < 7 && p.superview; i++) {
        p = p.superview;
        NSMutableArray *els = [NSMutableArray new]; RYA11yCollect(p, els, 0);
        for (id e in els) {
            if (e == in) continue;
            NSString *k = RYA11yKey(e);
            if (![k containsString:lbl] && ![k containsString:@"send"] && ![k containsString:@"إرسال"] && ![k containsString:@"ارسال"]) continue;
            BOOL skip = NO; for (NSString *w in bad) if ([k containsString:w]) { skip = YES; break; }
            if (skip) continue;
            if ([e accessibilityActivate]) return YES;
            if ([e isKindOfClass:UIView.class] && RYTapView(e)) return YES;
        }
        if (p.bounds.size.height > 500) break;
    }
    return NO;
}

static void RYDiagTree(UIView *v, int d, int maxD, NSMutableString *o) {
    if (!v || d > maxD) return;
    CGRect f = [v convertRect:v.bounds toView:nil];
    CGFloat al = v.backgroundColor ? CGColorGetAlpha(v.backgroundColor.CGColor) : 0;
    [o appendFormat:@"%@%@ %.0fx%.0f @%.0f,%.0f%@%@%@%@\n", [@"" stringByPaddingToLength:d * 2 withString:@" " startingAtIndex:0], NSStringFromClass(v.class), f.size.width, f.size.height, f.origin.x, f.origin.y,
        v.hidden ? @" hidden" : @"", al > 0.05 ? [NSString stringWithFormat:@" bg=%.2f", al] : @"",
        v.accessibilityIdentifier.length ? [@" id=" stringByAppendingString:v.accessibilityIdentifier] : @"", v.accessibilityLabel.length ? [@" label=" stringByAppendingString:RYClip(v.accessibilityLabel, 40)] : @""];
    NSUInteger n = 0;
    for (UIView *s in v.subviews) { if (++n > 60) { [o appendFormat:@"%@...\n", [@"" stringByPaddingToLength:d * 2 + 2 withString:@" " startingAtIndex:0]]; break; } RYDiagTree(s, d + 1, maxD, o); }
}
static void RYDiagMethods(Class c, NSMutableString *o) {
    for (int meta = 0; meta < 2; meta++) {
        Class k = meta ? object_getClass(c) : c; unsigned n = 0; Method *ms = class_copyMethodList(k, &n);
        for (unsigned i = 0; i < n && i < 300; i++) [o appendFormat:@"    %@ %s   %s\n", meta ? @"+" : @"-", sel_getName(method_getName(ms[i])), method_getTypeEncoding(ms[i]) ?: ""];
        free(ms);
    }
}
static NSString *RYDiagClasses(NSString *kw) {
    kw = [kw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if (!kw.length) return @"";
    NSMutableArray *names = [NSMutableArray new]; unsigned cnt = 0; Class *all = objc_copyClassList(&cnt);
    for (unsigned i = 0; i < cnt; i++) { NSString *nm = NSStringFromClass(all[i]); if ([nm rangeOfString:kw options:NSCaseInsensitiveSearch].location != NSNotFound) [names addObject:nm]; }
    free(all); [names sortUsingSelector:@selector(compare:)];
    NSMutableString *o = [NSMutableString stringWithFormat:@"classes matching \"%@\": %lu\n", kw, (unsigned long)names.count];
    for (NSString *nm in names) {
        Class c = NSClassFromString(nm); [o appendFormat:@"\n%@  (super %@)\n", nm, c ? NSStringFromClass(class_getSuperclass(c)) : @"?"];
        if (c && names.count <= 8) RYDiagMethods(c, o);
    }
    return o;
}
static NSString *RYDiagVoice(void) {
    NSMutableString *o = [NSMutableString new];
    [o appendFormat:@"voice engine transport hook: calls=%d hooked classes=%@\nlast options seen: %s\n\n", gTOCalls, gTOOrig.allKeys ?: @[], gTOLast];
    unsigned cnt = 0; Class *all = objc_copyClassList(&cnt); NSMutableArray *names = [NSMutableArray new];
    for (unsigned i = 0; i < cnt; i++) { NSString *nm = NSStringFromClass(all[i]); if ([nm containsString:@"VoiceEngine"] || [nm hasPrefix:@"DCDVoice"] || [nm containsString:@"Krisp"] || [nm hasPrefix:@"DCDAudio"]) [names addObject:nm]; }
    free(all); [names sortUsingSelector:@selector(compare:)];
    for (NSString *nm in names) { Class c = NSClassFromString(nm); [o appendFormat:@"%@\n", nm]; if (c) RYDiagMethods(c, o); }
    return o;
}
static NSString *RYDiagChat(void) {
    NSMutableString *o = [NSMutableString new];
    UIView *host = RYChatHost();
    [o appendFormat:@"chat class needle: %@\nchat host: %@  (found by: %@)\n\n", CF(@"roomClass", RY_ROOM_DEFAULT), host ? NSStringFromClass(host.class) : @"NOT FOUND", gChatHostHow];
    [o appendFormat:@"registered chat inputs: %lu\n\n", (unsigned long)gLiveInputs.allObjects.count];
    [o appendString:@"== view controllers whose class has Chat in the name\n"];
    for (UIWindow *w in RYAppWindows()) { NSMutableArray *vs = [NSMutableArray new]; RYScanAll(w.rootViewController, @"Chat", 0, vs); for (UIViewController *vc in vs) { CGRect f = [vc.view convertRect:vc.view.bounds toView:nil]; [o appendFormat:@"   %@  %.0fx%.0f @%.0f,%.0f  visible=%d\n", NSStringFromClass(vc.class), f.size.width, f.size.height, f.origin.x, f.origin.y, RYVisible(vc.view)]; } }
    [o appendString:@"\n== every text input on screen (UIKeyInput views)\n"];
    for (UIWindow *w in RYAppWindows()) { NSMutableArray *ins = [NSMutableArray new]; RYCollectInputs(w, ins, 0); for (UIView *x in ins) { CGRect f = [x convertRect:x.bounds toView:nil]; id dl = RYMsg0(x, @selector(delegate)); [o appendFormat:@"   %@  %.0fx%.0f @%.0f,%.0f  text=\"%@\"  delegate=%@  visible=%d\n", NSStringFromClass(x.class), f.size.width, f.size.height, f.origin.x, f.origin.y, RYClip(RYGetText(x), 30), dl ? NSStringFromClass([dl class]) : @"-", RYVisibleMin(x, 20, 12)]; } }
    { UIView *li = RYLowestInput(); UIView *gs = li ? RYGeoSend(li) : nil; [o appendFormat:@"\nbeside-field send candidate: %@\n", gs ? [NSString stringWithFormat:@"%@ key=%@", NSStringFromClass(gs.class), [gs isKindOfClass:UIControl.class] ? RYCtlKey((UIControl *)gs) : RYA11yKey(gs)] : @"none"]; }
    [o appendString:@"\n"];
    if (host) { [o appendString:@"== chat view tree (depth 7)\n"]; RYDiagTree(host, 0, 7, o); }
    UIView *in = RYLowestInput();
    [o appendFormat:@"\n== lowest visible text input: %@\n", in ? NSStringFromClass(in.class) : @"NONE"];
    if (in) {
        id dl = [in respondsToSelector:@selector(delegate)] ? [(id)in delegate] : nil;
        [o appendFormat:@"delegate: %@\nparents:", dl ? NSStringFromClass([dl class]) : @"-"];
        int n = 0; for (UIView *p = in.superview; p && n < 8; p = p.superview, n++) [o appendFormat:@" %@ <", NSStringFromClass(p.class)];
        [o appendString:@"\n\n== accessibility elements / controls around the input\n"];
        UIView *p = in;
        for (int i = 0; i < 6 && p.superview; i++) {
            p = p.superview; NSMutableArray *els = [NSMutableArray new]; RYA11yCollect(p, els, 0);
            [o appendFormat:@"-- level %d (%@): %lu elements\n", i + 1, NSStringFromClass(p.class), (unsigned long)els.count];
            for (id e in els) { CGRect fr = [e respondsToSelector:@selector(accessibilityFrame)] ? [e accessibilityFrame] : CGRectZero; [o appendFormat:@"   %@  key=%@  %.0fx%.0f @%.0f,%.0f\n", NSStringFromClass([e class]), RYA11yKey(e), fr.size.width, fr.size.height, fr.origin.x, fr.origin.y]; }
            if (p.bounds.size.height > 500) break;
        }
    }
    [o appendString:@"\n== chat input classes (methods)\n"];
    for (NSString *nm in @[@"DCDChatInput", @"DCDChatInputManager", @"DCDChatViewEventHandler", @"DCDChatViewController", @"DCDChatInputLayoutManager", @"DCDChatViewControllerContainer"]) {
        Class c = NSClassFromString(nm); if (!c) { [o appendFormat:@"%@: not found\n", nm]; continue; }
        [o appendFormat:@"%@ (super %@)\n", nm, NSStringFromClass(class_getSuperclass(c))]; RYDiagMethods(c, o);
    }
    return o;
}
// screen share (ReplayKit broadcast extension) report: why the extension can't reach the app is almost always signing / app group / missing appex
static NSString *RYDiagBroadcast(void) {
    NSMutableString *o = [NSMutableString new];
    NSBundle *mb = NSBundle.mainBundle; NSFileManager *fm = NSFileManager.defaultManager;
    [o appendFormat:@"main bundle id: %@\n", mb.bundleIdentifier];
    NSString *pl = [mb.bundlePath stringByAppendingPathComponent:@"PlugIns"];
    NSArray *ex = [fm contentsOfDirectoryAtPath:pl error:nil];
    [o appendFormat:@"PlugIns folder: %@\n", ex.count ? @"present" : @"MISSING or empty (extension was stripped when signing)"];
    for (NSString *e in ex) {
        NSDictionary *ip = [NSDictionary dictionaryWithContentsOfFile:[[pl stringByAppendingPathComponent:e] stringByAppendingPathComponent:@"Info.plist"]];
        [o appendFormat:@"  %@  id=%@  point=%@\n", e, ip[@"CFBundleIdentifier"], ip[@"NSExtension"][@"NSExtensionPointIdentifier"]];
    }
    NSMutableSet *groups = [NSMutableSet new];
    NSData *prof = [NSData dataWithContentsOfFile:[mb.bundlePath stringByAppendingPathComponent:@"embedded.mobileprovision"]];
    if (prof) {
        NSData *a = [@"<plist" dataUsingEncoding:NSASCIIStringEncoding], *b = [@"</plist>" dataUsingEncoding:NSASCIIStringEncoding];
        NSRange ra = [prof rangeOfData:a options:0 range:NSMakeRange(0, prof.length)], rb = [prof rangeOfData:b options:0 range:NSMakeRange(0, prof.length)];
        if (ra.location != NSNotFound && rb.location != NSNotFound) {
            NSDictionary *pd = [NSPropertyListSerialization propertyListWithData:[prof subdataWithRange:NSMakeRange(ra.location, rb.location + rb.length - ra.location)] options:0 format:nil error:nil];
            NSDictionary *ent = pd[@"Entitlements"];
            [o appendFormat:@"profile: %@  team=%@\n", pd[@"Name"], [pd[@"TeamIdentifier"] firstObject]];
            [o appendFormat:@"profile app-groups: %@\n", ent[@"com.apple.security.application-groups"] ?: @"NONE (no app group = extension cannot talk to the app)"];
            for (NSString *g in ent[@"com.apple.security.application-groups"] ?: @[]) [groups addObject:g];
        }
    } else [o appendString:@"profile: no embedded.mobileprovision\n"];
    for (NSString *g in groups) { NSURL *u = [fm containerURLForSecurityApplicationGroupIdentifier:g]; [o appendFormat:@"group container %@: %@\n", g, u ? @"OK" : @"FAILED"]; }
    [o appendFormat:@"screen captured now: %d\n", UIScreen.mainScreen.isCaptured];
    return o;
}
static NSString *RYDiagReport(void) {
    NSMutableString *o = [NSMutableString new];
    NSDictionary *inf = NSBundle.mainBundle.infoDictionary;
    [o appendFormat:@"8ubah Discord diagnostics\napp %@ (%@)  ios %@\n\n== view controllers\n", inf[@"CFBundleShortVersionString"], inf[@"CFBundleVersion"], UIDevice.currentDevice.systemVersion];
    for (UIWindow *w in RYAppWindows()) RYDump(w.rootViewController, 0, o);
    [o appendString:@"\n== chat\n"]; [o appendString:RYDiagChat()];
    [o appendString:@"\n== voice engine\n"]; [o appendString:RYDiagVoice()];
    [o appendString:@"\n== mic\n"]; [o appendString:RYMicReport()];
    [o appendString:@"\n== screen share\n"]; [o appendString:RYDiagBroadcast()];
    [o appendFormat:@"\n== message logger\nupdates %d  kept %d  restored %d  skipped %d\nlast: %s\nvoice options last: %s (calls %d)\n", gLogUpd, gLogKept, gLogPut, gLogSkip, gLogLast, gTOLast, gTOCalls];
    { NSString *ev = [NSString stringWithContentsOfFile:[RYDir(@"logs") stringByAppendingPathComponent:@"events.txt"] encoding:NSUTF8StringEncoding error:nil] ?: @""; [o appendFormat:@"\n== events (tail)\n%@\n", ev.length > 3500 ? [ev substringFromIndex:ev.length - 3500] : ev]; }
    return o;
}
static void RYShareText(UIViewController *from, NSString *name, NSString *text) {
    NSString *p = [RYDir(@"logs") stringByAppendingPathComponent:name];
    [text writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIActivityViewController *a = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:p]] applicationActivities:nil];
        a.popoverPresentationController.sourceView = from.view; [from presentViewController:a animated:YES completion:nil];
    });
}

#pragma mark - Window / root

@interface RYWindow : UIWindow @end
@implementation RYWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    if (self.rootViewController.presentedViewController) return v;
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
- (BOOL)canBecomeKeyWindow { return self.rootViewController.presentedViewController != nil; }
@end

@interface RYCore : NSObject
@property (nonatomic, strong) RYWindow *win;
@property (nonatomic, strong) UIButton *fab;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, weak) UIWindow *prevKey;
@property (nonatomic, strong) RYBGView *bgView;
@property (nonatomic, weak) UIView *bgHost;
@property (nonatomic) NSInteger missTicks;
@property (nonatomic) NSInteger stamp;
+ (instancetype)shared;
- (void)hud:(NSString *)s;
- (void)start; - (void)openPanel; - (void)panelClosed; - (void)bump;
- (void)sendMessage:(NSString *)msg done:(void (^)(NSInteger code))done;
- (void)sendTry:(NSString *)msg input:(UIView *)in prev:(NSString *)prev mode:(int)mode attempt:(int)att done:(void (^)(NSInteger))done;
- (void)syncBG:(UIView *)chat;
@end

#pragma mark - Quick-message loop (sends the saved messages one after another until switched off)

static BOOL gMsgLoop = NO; static NSUInteger gMsgIdx = 0, gMsgFails = 0, gMsgSent = 0; static NSInteger gMsgGen = 0;
static UIBackgroundTaskIdentifier gBGTask = 0; // 0 == UIBackgroundTaskInvalid (the constant itself is not a compile-time value)
static void RYBGRenew(BOOL on) { // keeps the process running a bit longer after leaving the app; renewed every message
    UIApplication *app = UIApplication.sharedApplication;
    UIBackgroundTaskIdentifier old = gBGTask; gBGTask = UIBackgroundTaskInvalid;
    if (on) gBGTask = [app beginBackgroundTaskWithName:@"8ubah.loop" expirationHandler:^{
        UIBackgroundTaskIdentifier t = gBGTask; gBGTask = UIBackgroundTaskInvalid; if (t != UIBackgroundTaskInvalid) [app endBackgroundTask:t];
    }];
    if (old != UIBackgroundTaskInvalid) [app endBackgroundTask:old];
}
static void RYMsgLoopStep(NSInteger gen) {
    if (!gMsgLoop || gen != gMsgGen) return;
    RYBGRenew(YES);
    NSArray *msgs = CF(@"messages", @[]);
    if (!msgs.count) { gMsgLoop = NO; RYBGRenew(NO); return; }
    if (gMsgIdx >= msgs.count) gMsgIdx = 0;
    NSString *m = msgs[gMsgIdx++];
    double delay = MAX(2.0, [CF(@"msgDelay", @4.0) doubleValue]); // 0.4s floor
    [[RYCore shared] sendMessage:m done:^(NSInteger code) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!gMsgLoop || gen != gMsgGen) return;
            if (code == 0) { gMsgSent++; gMsgFails = 0; }
            else if (++gMsgFails >= 3) { gMsgLoop = NO; RYBGRenew(NO); return; } // chat input not available (left the room?) -> stop
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ RYMsgLoopStep(gen); });
        });
    }];
}
static void RYMsgLoopSet(BOOL on) {
    gMsgLoop = on; gMsgGen++; gMsgFails = 0; gMsgSent = 0;
    if (!on) RYBGRenew(NO);
    if (on) { gMsgIdx = 0; RYMsgLoopStep(gMsgGen); }
}

@interface RYPanel : UIViewController <PHPickerViewControllerDelegate, UIDocumentPickerDelegate, UIColorPickerViewControllerDelegate>
@property (nonatomic) NSInteger tab;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UILabel *invLabel;
@property (nonatomic, strong) NSTimer *invUI;
@property (nonatomic, strong) UISlider *stSlider;
@property (nonatomic, strong) UILabel *stTimeLabel;
@property (nonatomic, strong) NSTimer *stUI;
@property (nonatomic) BOOL stDragging; // true while the user's finger is on the slider: stop auto-updating it so it doesn't fight the drag
@property (nonatomic, strong) NSString *pickPurpose; // routes the shared PHPicker callback: nil/"bg" = background image, "stereo" = Stereo video
@end

@implementation RYPanel
- (void)viewDidLoad { [super viewDidLoad]; [self rebuild]; }
- (void)viewDidDisappear:(BOOL)a { [super viewDidDisappear:a]; [self.invUI invalidate]; self.invUI = nil; if (self.isBeingDismissed) [[RYCore shared] panelClosed]; }

- (void)toast:(NSString *)s {
    dispatch_async(dispatch_get_main_queue(), ^{
        UILabel *l = RYLabel(s, 14, UIFontWeightMedium, nil); l.textAlignment = NSTextAlignmentCenter; l.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
        l.layer.cornerRadius = 12; l.clipsToBounds = YES;
        CGSize z = [l sizeThatFits:CGSizeMake(self.view.bounds.size.width - 60, CGFLOAT_MAX)];
        l.frame = CGRectMake(0, 0, z.width + 28, z.height + 18); l.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height - 90);
        [self.view addSubview:l];
        [UIView animateWithDuration:0.4 delay:1.8 options:0 animations:^{ l.alpha = 0; } completion:^(BOOL f) { [l removeFromSuperview]; }];
    });
}
- (void)ask:(NSString *)title ph:(NSString *)ph secure:(BOOL)sec ok:(void (^)(NSString *))cb {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t) { t.placeholder = ph; t.secureTextEntry = sec; t.autocorrectionType = UITextAutocorrectionTypeNo; t.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
    [a addAction:[UIAlertAction actionWithTitle:T(@"إلغاء", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:T(@"تم", @"OK") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { cb(a.textFields.firstObject.text ?: @""); }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)rebuild {
    for (UIView *v in self.view.subviews) [v removeFromSuperview];
    __weak typeof(self) ws = self;
    self.view.backgroundColor = RY_BG; self.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; self.view.semanticContentAttribute = RYSem();

    UILabel *title = RYLabel(@"8ubah", 22, UIFontWeightHeavy, nil); title.numberOfLines = 1;
    UIView *spacer = [UIView new]; [spacer setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    UIButton *close = RYBtn(T(@"إغلاق", @"Close"), NO, ^{ [ws dismissViewControllerAnimated:YES completion:nil]; });
    UIStackView *head = RYHStack(@[title, spacer, close], 8);
    UIScrollView *tabsScroll = [UIScrollView new]; tabsScroll.showsHorizontalScrollIndicator = NO;
    NSArray *names = @[T(@"مايك", @"Mic"), T(@"ستيريو", @"Stereo"), T(@"الخلفيات", @"Backgrounds")];
    // all tabs always shown, in or out of a room (tabs whose feature needs a room just say so when you tap into them there)
    NSArray<NSNumber *> *order = @[@0, @1, @2];
    if (self.tab < 0 || self.tab > 2) self.tab = 0;
    NSMutableArray *tb = [NSMutableArray new];
    for (NSNumber *nn in order) { NSInteger i = nn.integerValue; [tb addObject:RYBtn(names[i], i == self.tab, ^{ ws.tab = i; [ws rebuild]; })]; }
    tabsScroll.hidden = NO;
    [self.invUI invalidate]; self.invUI = nil; self.invLabel = nil;
    UIStackView *tabStack = RYHStack(tb, 8); tabStack.alignment = UIStackViewAlignmentFill;
    UIScrollView *scroll = [UIScrollView new]; scroll.alwaysBounceVertical = YES; scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.stack = RYVStack(@[], 12);

    for (UIView *v in @[head, tabsScroll, scroll]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:v]; }
    [tabsScroll addSubview:tabStack]; [scroll addSubview:self.stack];
    tabStack.translatesAutoresizingMaskIntoConstraints = NO; self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    UILayoutGuide *sg = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [head.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:18],
        [head.leadingAnchor constraintEqualToAnchor:sg.leadingAnchor constant:16], [head.trailingAnchor constraintEqualToAnchor:sg.trailingAnchor constant:-16],
        [tabsScroll.topAnchor constraintEqualToAnchor:head.bottomAnchor constant:12],
        [tabsScroll.leadingAnchor constraintEqualToAnchor:sg.leadingAnchor], [tabsScroll.trailingAnchor constraintEqualToAnchor:sg.trailingAnchor],
        [tabsScroll.heightAnchor constraintEqualToConstant:40],
        [tabStack.topAnchor constraintEqualToAnchor:tabsScroll.contentLayoutGuide.topAnchor], [tabStack.bottomAnchor constraintEqualToAnchor:tabsScroll.contentLayoutGuide.bottomAnchor],
        [tabStack.leadingAnchor constraintEqualToAnchor:tabsScroll.contentLayoutGuide.leadingAnchor constant:16], [tabStack.trailingAnchor constraintEqualToAnchor:tabsScroll.contentLayoutGuide.trailingAnchor constant:-16],
        [tabStack.heightAnchor constraintEqualToAnchor:tabsScroll.frameLayoutGuide.heightAnchor],
        [scroll.topAnchor constraintEqualToAnchor:tabsScroll.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:sg.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:sg.trailingAnchor], [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:8],
        [self.stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16], [self.stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [self.stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-60],
        [self.stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32]]];

    if (RYLocked()) { tabsScroll.hidden = YES; [self renderLocked]; return; }
    switch (self.tab) { case 0: [self renderMic]; break; case 1: [self renderStereo]; break; default: [self renderBG]; }
}
#pragma mark Locked
- (void)renderLocked {
    __weak typeof(self) ws = self;
    UIButton *unlock = RYBtn(T(@"فتح", @"Unlock"), YES, ^{
        [ws ask:T(@"المفتاح", @"Key") ph:@"XXXX-XXXX-XXXX-XXXX" secure:NO ok:^(NSString *k) {
            if (!k.length) return;
            RYLicActivate(k, ^(BOOL ok, NSString *reason) { if (ok) [ws rebuild]; else [ws toast:reason.length ? [NSString stringWithFormat:@"%@ (%@)", T(@"المفتاح غلط", @"Wrong key"), reason] : T(@"المفتاح غلط", @"Wrong key")]; });
        }];
    });
    [self.stack addArrangedSubview:RYCard(@[unlock])];
}

#pragma mark Backgrounds
- (void)setBG:(NSString *)mode value:(NSString *)v { CS(@"bgMode", mode); CS(@"bgValue", v); [[RYCore shared] bump]; }
- (void)renderBG {
    __weak typeof(self) ws = self;
    UIButton *photo = RYBtn(T(@"من الاستوديو", @"Photo library"), YES, ^{
        ws.pickPurpose = @"bg"; PHPickerConfiguration *c = [PHPickerConfiguration new]; c.filter = [PHPickerFilter imagesFilter]; c.selectionLimit = 1;
        PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:c]; p.delegate = ws; [ws presentViewController:p animated:YES completion:nil];
    });
    UIButton *url = RYBtn(T(@"رابط صورة", @"Image URL"), NO, ^{
        [ws ask:T(@"رابط الصورة (https)", @"Image URL (https)") ph:@"https://" secure:NO ok:^(NSString *s) {
            NSURL *u = [NSURL URLWithString:[s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
            if (!u || ![u.scheme isEqual:@"https"]) { [ws toast:T(@"لازم رابط https", @"Needs an https link")]; return; }
            [[[NSURLSession sharedSession] dataTaskWithURL:u completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) { [ws saveBGData:d]; }] resume];
        }];
    });
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"خلفية الغرفة (تشوفها أنت بس)", @"Room background (only you see it)"), 15, UIFontWeightBold, nil), RYHStack(@[photo, url], 8)])];

    NSMutableArray *sw = [NSMutableArray new];
    for (NSString *h in @[@"#000000", @"#111827", @"#1E1B4B", @"#052E16", @"#450A0A", @"#3B0764", @"#0C4A6E", @"#78350F"]) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom]; b.backgroundColor = RYHex(h); b.layer.cornerRadius = 10; b.layer.borderWidth = 1; b.layer.borderColor = RY_MUTED.CGColor;
        [b addAction:[UIAction actionWithHandler:^(UIAction *a) { [ws setBG:@"color" value:h]; [ws toast:T(@"تم", @"Done")]; }] forControlEvents:UIControlEventTouchUpInside];
        [b.heightAnchor constraintEqualToConstant:40].active = YES; [sw addObject:b];
    }
    UIButton *custom = RYBtn(T(@"لون مخصص", @"Custom colour"), NO, ^{
        ws.pickPurpose = nil; UIColorPickerViewController *cp = [UIColorPickerViewController new]; cp.delegate = ws; [ws presentViewController:cp animated:YES completion:nil];
    });
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"لون ثابت", @"Solid colour"), 15, UIFontWeightBold, nil), RYGrid(sw, 4), custom])];

    NSMutableArray *gs = [NSMutableArray new];
    for (NSString *g in @[@"#0F2027,#2C5364", @"#41295A,#2F0743", @"#FF512F,#DD2476", @"#00C6FF,#0072FF", @"#11998E,#38EF7D", @"#232526,#414345"]) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom]; [b setBackgroundImage:RYGradImage(g) forState:UIControlStateNormal]; b.layer.cornerRadius = 10; b.clipsToBounds = YES;
        [b addAction:[UIAction actionWithHandler:^(UIAction *a) { [ws setBG:@"gradient" value:g]; [ws toast:T(@"تم", @"Done")]; }] forControlEvents:UIControlEventTouchUpInside];
        [b.heightAnchor constraintEqualToConstant:44].active = YES; [gs addObject:b];
    }
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"تدرجات", @"Gradients"), 15, UIFontWeightBold, nil), RYGrid(gs, 3)])];

    [self.stack addArrangedSubview:RYSlider(T(@"التمويه (Blur)", @"Blur"), 0, 100, [CF(@"blur", @0) floatValue], ^(float v) { CS(@"blur", @(v)); [[RYCore shared] bump]; })];
    [self.stack addArrangedSubview:RYSlider(T(@"التعتيم (Dim)", @"Dim"), 0, 100, [CF(@"dim", @30) floatValue], ^(float v) { CS(@"dim", @(v)); [[RYCore shared] bump]; })];
    { NSString *tm = CF(@"txtMode", @"auto");
      UIButton *tA = RYBtn(T(@"تلقائي", @"Auto"), [tm isEqual:@"auto"], ^{ CS(@"txtMode", @"auto"); [[RYCore shared] bump]; [ws rebuild]; });
      UIButton *tC = RYBtn(T(@"لون مخصص", @"Custom"), [tm isEqual:@"custom"], ^{
          ws.pickPurpose = @"txt"; UIColorPickerViewController *cp = [UIColorPickerViewController new]; cp.delegate = ws; cp.supportsAlpha = NO;
          cp.selectedColor = RYHex(CF(@"txtColor", @"#FFFFFF")); [ws presentViewController:cp animated:YES completion:nil]; });
      UIButton *tO = RYBtn(T(@"بدون", @"Off"), [tm isEqual:@"off"], ^{ CS(@"txtMode", @"off"); [[RYCore shared] bump]; [ws rebuild]; });
      [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"لون كلام الناس", @"Message text colour"), 15, UIFontWeightBold, nil), RYHStack(@[tA, tC, tO], 8)])]; }
    [self.stack addArrangedSubview:RYBtn(T(@"رجوع للافتراضي", @"Reset to default"), NO, ^{
        [ws setBG:@"none" value:@""]; CS(@"blur", @0); CS(@"dim", @30); CS(@"txtMode", nil); CS(@"txtColor", nil); [ws rebuild]; [ws toast:T(@"تم الرجوع للافتراضي", @"Reset")];
    })];
}
- (void)saveBGData:(NSData *)d {
    if (!d.length) { [self toast:T(@"فشل التحميل", @"Failed to load")]; return; }
    if (d.length > 12 * 1024 * 1024) { [self toast:T(@"الصورة كبيرة (أكثر من 12MB)", @"Image too large (>12MB)")]; return; }
    CGImageSourceRef s = CGImageSourceCreateWithData((__bridge CFDataRef)d, NULL); if (!s) { [self toast:T(@"ملف غير صالح", @"Invalid image")]; return; }
    NSDictionary *pr = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(s, 0, NULL)); CFRelease(s);
    if (MAX([pr[@"PixelWidth"] intValue], [pr[@"PixelHeight"] intValue]) > 4096) { [self toast:T(@"أبعاد الصورة كبيرة (أكثر من 4096px)", @"Image dimensions too large (>4096px)")]; return; }
    UIImage *im = [UIImage imageWithData:d]; NSData *j = im ? UIImageJPEGRepresentation(im, 0.9) : nil;
    if (!j || ![j writeToFile:[RYDir(nil) stringByAppendingPathComponent:@"bg.jpg"] atomically:YES]) { [self toast:T(@"تعذر الحفظ", @"Could not save")]; return; }
    dispatch_async(dispatch_get_main_queue(), ^{ [self setBG:@"image" value:@"bg.jpg"]; [self toast:T(@"تم تعيين الخلفية", @"Background set")]; });
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *r = results.firstObject; if (!r) return;
    __weak typeof(self) ws = self;
    if ([self.pickPurpose isEqualToString:@"stereo"]) {
        [r.itemProvider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *u, NSError *e) {
            if (!u) { dispatch_async(dispatch_get_main_queue(), ^{ [ws toast:T(@"تعذر فتح الفيديو", @"Could not open the video")]; }); return; }
            NSString *dst = [RYDir(@"data") stringByAppendingPathComponent:[@"stereo." stringByAppendingString:(u.pathExtension.length ? u.pathExtension : @"mov")]];
            [NSFileManager.defaultManager removeItemAtPath:dst error:nil];
            NSError *cp = nil; [NSFileManager.defaultManager copyItemAtURL:u toURL:[NSURL fileURLWithPath:dst] error:&cp];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (cp) { [ws toast:T(@"تعذر فتح الفيديو", @"Could not open the video")]; return; }
                CS(@"stName", u.lastPathComponent); CS(@"stFile", dst.lastPathComponent); [ws toast:T(@"جاري التحميل…", @"Loading…")];
                RYStDecode([NSURL fileURLWithPath:dst], ^(BOOL ok, NSString *msg) { [ws toast:msg ?: (ok ? T(@"جاهز", @"Ready") : T(@"تعذر التحميل", @"Could not load"))]; [ws rebuild]; });
            });
        }];
        return;
    }
    [r.itemProvider loadDataRepresentationForTypeIdentifier:@"public.image" completionHandler:^(NSData *d, NSError *e) { [ws saveBGData:d]; }];
}
- (void)colorPickerViewController:(UIColorPickerViewController *)vc didSelectColor:(UIColor *)color continuously:(BOOL)c {
    if ([self.pickPurpose isEqual:@"txt"]) { CS(@"txtColor", RYHexFrom(color)); CS(@"txtMode", @"custom"); [[RYCore shared] bump]; return; }
    [self setBG:@"color" value:RYHexFrom(color)];
}

#pragma mark Stereo (play a file through the mic)
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *u = urls.firstObject; if (!u) return;
    __weak typeof(self) ws = self;
    NSString *ext = u.pathExtension.length ? u.pathExtension : @"dat";
    NSString *dst = [RYDir(@"data") stringByAppendingPathComponent:[@"stereo." stringByAppendingString:ext]];
    [NSFileManager.defaultManager removeItemAtPath:dst error:nil];
    NSError *cpErr = nil; [NSFileManager.defaultManager copyItemAtURL:u toURL:[NSURL fileURLWithPath:dst] error:&cpErr];
    if (cpErr) { [self toast:T(@"تعذر فتح الملف", @"Could not open the file")]; return; }
    CS(@"stName", u.lastPathComponent); CS(@"stFile", dst.lastPathComponent);
    [self toast:T(@"جاري التحميل…", @"Loading…")];
    RYStDecode([NSURL fileURLWithPath:dst], ^(BOOL ok, NSString *msg) { [ws toast:msg ?: (ok ? T(@"جاهز", @"Ready") : T(@"تعذر التحميل", @"Could not load"))]; [ws rebuild]; });
}
- (void)renderStereo {
    __weak typeof(self) ws = self;
    NSString *nm = CF(@"stName", nil);
    if (!gStBuf && !gStLoading && CF(@"stFile", nil)) { // relaunch: redecode the cached copy the first time this tab is opened
        NSString *f = [RYDir(@"data") stringByAppendingPathComponent:CF(@"stFile", @"")];
        if ([NSFileManager.defaultManager fileExistsAtPath:f]) RYStDecode([NSURL fileURLWithPath:f], ^(BOOL ok, NSString *msg) { if (ok) [ws rebuild]; });
    }
    UIButton *choose = RYBtn(T(@"ملف", @"File"), NO, ^{
        UIDocumentPickerViewController *dp = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.audio", @"public.movie", @"public.mpeg-4", @"public.mp3", @"com.microsoft.waveform-audio", @"public.mpeg-4-audio"] inMode:UIDocumentPickerModeImport];
        dp.delegate = ws; [ws presentViewController:dp animated:YES completion:nil];
    });
    UIButton *gallery = RYBtn(T(@"الجاليري", @"Gallery"), NO, ^{
        ws.pickPurpose = @"stereo";
        PHPickerConfiguration *c = [PHPickerConfiguration new]; c.filter = [PHPickerFilter videosFilter]; c.selectionLimit = 1;
        PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:c]; p.delegate = ws; [ws presentViewController:p animated:YES completion:nil];
    });
    UIButton *remove = RYBtn(T(@"حذف", @"Remove"), NO, ^{
        RYStFree(); NSString *f = CF(@"stFile", nil);
        if (f) [NSFileManager.defaultManager removeItemAtPath:[RYDir(@"data") stringByAppendingPathComponent:f] error:nil];
        CS(@"stName", nil); CS(@"stFile", nil); [ws rebuild];
    });
    UIButton *saveShortcut = RYBtn(T(@"حفظ كاختصار", @"Save as shortcut"), NO, ^{
        NSString *f = CF(@"stFile", nil);
        if (!f) { [ws toast:T(@"حمّل ملف أول", @"Load a file first")]; return; }
        [ws ask:T(@"اسم الاختصار", @"Shortcut name") ph:(nm ?: @"") secure:NO ok:^(NSString *name) {
            NSString *ext = f.pathExtension.length ? f.pathExtension : @"dat";
            NSString *clipFile = [NSString stringWithFormat:@"stclip-%@.%@", [NSUUID UUID].UUIDString, ext];
            NSError *cp = nil; [NSFileManager.defaultManager copyItemAtPath:[RYDir(@"data") stringByAppendingPathComponent:f] toPath:[RYDir(@"data") stringByAppendingPathComponent:clipFile] error:&cp];
            if (cp) { [ws toast:T(@"تعذر الحفظ", @"Could not save")]; return; }
            NSMutableArray *clips = [CF(@"stClips", @[]) mutableCopy];
            [clips addObject:@{@"name": name.length ? name : (nm ?: @"Clip"), @"file": clipFile}];
            CS(@"stClips", clips); [ws toast:T(@"تم الحفظ كاختصار", @"Saved as a shortcut")]; [ws rebuild];
        }];
    });
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"ملف الصوت أو الفيديو", @"Audio/video file"), 16, UIFontWeightBold, nil),
        RYLabel(gStLoading ? T(@"جاري التحميل…", @"Loading…") : (nm ?: T(@"ما فيه ملف", @"No file")), 13, UIFontWeightMedium, RY_MUTED),
        RYHStack(@[choose, gallery, remove], 8), saveShortcut])];
    UISwitch *lp = [UISwitch new]; lp.on = gStLoop != 0; lp.onTintColor = RYAccent(); __weak UISwitch *wlp = lp;
    [lp addAction:[UIAction actionWithHandler:^(UIAction *a) { gStLoop = wlp.on; CS(@"stLoop", @(wlp.on)); }] forControlEvents:UIControlEventValueChanged];
    UIButton *play = RYBtn(gStOn ? T(@"إيقاف", @"Stop") : T(@"تشغيل بالمايك", @"Play through mic"), gStOn, ^{
        if (!gStBuf || gStLen <= 1) { [ws toast:T(@"اختر ملف أول", @"Choose a file first")]; return; }
        if (gStOn) { gStOn = 0; if (!gMonOn) RYMonEngineStop(); } else { RYStPlay(); }
        [ws rebuild];
    });
    [self.stack addArrangedSubview:RYCard(@[RYHStack(@[RYLabel(T(@"تكرار", @"Loop"), 14, UIFontWeightMedium, nil), lp], 12), play])];
    UISwitch *hm = [UISwitch new]; hm.on = gStMon != 0; hm.onTintColor = RYAccent(); __weak UISwitch *whm = hm;
    [hm addAction:[UIAction actionWithHandler:^(UIAction *a) { RYStMonSet(whm.on); }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYHStack(@[RYLabel(T(@"أسمع الملف أنا كمان", @"Hear it myself"), 14, UIFontWeightMedium, nil), hm], 12),
        RYLabel(T(@"تسمع الملف نفسه بنفس لحظة ما الروم يسمعونه (بدون صوتك). استخدم سماعة عشان المايك ما يلتقطه مرة ثانية.", @"You hear the file itself at the same moment the room does (not your voice). Use headphones so the mic does not pick it up again."), 12, UIFontWeightRegular, RY_MUTED)])];
    // scrub bar: shows where the clip is and lets you drag forward/back, same clip the mic is playing
    UISlider *pos = [UISlider new]; pos.minimumValue = 0; pos.maximumValue = (float)MAX(RYStDuration(), 0.01); pos.value = (float)RYStPosSec();
    pos.minimumTrackTintColor = RYAccent(); self.stSlider = pos;
    UILabel *tlab = RYLabel([self stTimeText], 12, UIFontWeightMedium, RY_MUTED); tlab.textAlignment = NSTextAlignmentCenter; self.stTimeLabel = tlab;
    __weak UISlider *wpos = pos;
    [pos addAction:[UIAction actionWithHandler:^(UIAction *a) { ws.stDragging = YES; ws.stTimeLabel.text = [ws stTimeTextFor:wpos.value]; }] forControlEvents:UIControlEventTouchDown];
    [pos addAction:[UIAction actionWithHandler:^(UIAction *a) { ws.stTimeLabel.text = [ws stTimeTextFor:wpos.value]; }] forControlEvents:UIControlEventValueChanged];
    [pos addAction:[UIAction actionWithHandler:^(UIAction *a) { RYStSeek(wpos.value); ws.stDragging = NO; }] forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.stack addArrangedSubview:RYCard(@[pos, tlab])];
    [self startStUI];
    [self.stack addArrangedSubview:RYSlider(T(@"مستوى الصوت", @"Volume"), 0, 2, gStVol, ^(float v) { gStVol = v; CS(@"stVol", @(v)); })];
    NSArray *clips = CF(@"stClips", @[]);
    if (clips.count) {
        NSMutableArray *rows = [NSMutableArray arrayWithObject:RYLabel(T(@"الاختصارات المحفوظة", @"Saved shortcuts"), 16, UIFontWeightBold, nil)];
        for (NSDictionary *clip in clips) {
            NSString *cfile = clip[@"file"], *cname = clip[@"name"];
            UIButton *cplay = RYBtn(T(@"تشغيل", @"Play"), NO, ^{
                NSString *path = [RYDir(@"data") stringByAppendingPathComponent:cfile];
                if (![NSFileManager.defaultManager fileExistsAtPath:path]) { [ws toast:T(@"الملف مفقود", @"File missing")]; return; }
                [ws toast:T(@"جاري التحميل…", @"Loading…")];
                RYStDecode([NSURL fileURLWithPath:path], ^(BOOL ok, NSString *msg) {
                    if (!ok) { [ws toast:msg ?: T(@"تعذر التحميل", @"Could not load")]; return; }
                    CS(@"stName", cname); CS(@"stFile", cfile); RYStPlay(); [ws rebuild];
                });
            });
            UIButton *cdel = RYBtn(T(@"حذف", @"Remove"), NO, ^{
                [NSFileManager.defaultManager removeItemAtPath:[RYDir(@"data") stringByAppendingPathComponent:cfile] error:nil];
                NSMutableArray *left = [NSMutableArray new]; for (NSDictionary *x in CF(@"stClips", @[])) if (![x[@"file"] isEqual:cfile]) [left addObject:x];
                CS(@"stClips", left); [ws rebuild];
            });
            [rows addObject:RYHStack(@[RYLabel(cname, 14, UIFontWeightMedium, nil), cplay, cdel], 8)];
        }
        [self.stack addArrangedSubview:RYCard(rows)];
    }
}
static NSString *RYMMSS(double s) { if (s < 0) s = 0; NSInteger t = (NSInteger)(s + 0.5); return [NSString stringWithFormat:@"%ld:%02ld", (long)(t / 60), (long)(t % 60)]; }
- (NSString *)stTimeTextFor:(double)posSec { return [NSString stringWithFormat:@"%@ / %@", RYMMSS(posSec), RYMMSS(RYStDuration())]; }
- (NSString *)stTimeText { return [self stTimeTextFor:RYStPosSec()]; }
- (void)startStUI {
    [self.stUI invalidate]; __weak typeof(self) ws = self;
    self.stUI = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *t) {
        if (!ws.stSlider) { [t invalidate]; return; }
        ws.stSlider.maximumValue = (float)MAX(RYStDuration(), 0.01);
        if (!ws.stDragging) { ws.stSlider.value = (float)RYStPosSec(); ws.stTimeLabel.text = [ws stTimeText]; }
    }];
}

#pragma mark Quick messages
- (void)renderMsgs {
    __weak typeof(self) ws = self;
    NSArray *msgs = CF(@"messages", @[@"👋", @"😂", @"🔥", @"ثواني وأرجع"]);
    UISwitch *lp = [UISwitch new]; lp.on = gMsgLoop; lp.onTintColor = RYAccent(); __weak UISwitch *wlp = lp;
    UILabel *lst = RYLabel(@"", 12, UIFontWeightRegular, RY_MUTED); self.invLabel = lst;
    [lp addAction:[UIAction actionWithHandler:^(UIAction *a) {
        if (wlp.on && ![CF(@"messages", @[]) count]) { wlp.on = NO; [ws toast:T(@"أضف رسالة أول", @"Add a message first")]; return; }
        RYMsgLoopSet(wlp.on);
    }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYHStack(@[RYLabel(T(@"إرسال كل الرسائل بتكرار", @"Loop all messages"), 15, UIFontWeightBold, nil), lp], 12),
        lst])];
    { __block UILabel *wdl; UILabel *dl = RYLabel([NSString stringWithFormat:T(@"الفاصل بين الرسائل: %.1f ثانية", @"Delay between messages: %.1fs"), MAX(2.0, [CF(@"msgDelay", @4.0) floatValue])], 14, UIFontWeightMedium, nil); wdl = dl;
      UISlider *dsl = [UISlider new]; dsl.minimumValue = 2.0; dsl.maximumValue = 30; dsl.value = MIN(30, MAX(2.0, [CF(@"msgDelay", @4.0) floatValue])); dsl.minimumTrackTintColor = RYAccent(); __weak UISlider *wdsl = dsl;
      [dsl addAction:[UIAction actionWithHandler:^(UIAction *a) { float v = wdsl.value; CS(@"msgDelay", @(v)); wdl.text = [NSString stringWithFormat:T(@"الفاصل بين الرسائل: %.1f ثانية", @"Delay between messages: %.1fs"), v]; }] forControlEvents:UIControlEventValueChanged];
      UIButton *custom = RYBtn(T(@"اكتب رقم (بدون حد أعلى)", @"Type a number (no upper limit)"), NO, ^{
          [ws ask:T(@"الثواني", @"Seconds") ph:@"4.0" secure:NO ok:^(NSString *x) {
              float v = [x floatValue]; if (v < 2.0f) v = 2.0f; CS(@"msgDelay", @(v));
              wdl.text = [NSString stringWithFormat:T(@"الفاصل بين الرسائل: %.1f ثانية", @"Delay between messages: %.1fs"), v];
              wdsl.value = MIN(30, v);
          }];
      });
      [self.stack addArrangedSubview:RYCard(@[dl, dsl, custom])]; }
    self.invUI = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
        ws.invLabel.text = gMsgLoop ? [NSString stringWithFormat:T(@"شغّال... انرسل %lu", @"Running... sent %lu"), (unsigned long)gMsgSent] : T(@"متوقف", @"Stopped");
        if (!gMsgLoop && wlp.on) wlp.on = NO;
    }];
    for (NSUInteger i = 0; i < msgs.count; i++) {
        NSString *m = msgs[i];
        UIButton *send = RYBtn(m, YES, ^{
            [[RYCore shared] sendMessage:m done:^(NSInteger code) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [ws toast:code == 0 ? T(@"تم الإرسال", @"Sent") : code == 1 ? T(@"ما لقيت خانة الدردشة", @"Chat input not found") : T(@"ما انرسلت، افتح الدردشة وجرّب", @"Not sent, open the chat and retry")];
                });
            }];
        });
        UIButton *del = RYBtn(@"✕", NO, ^{ NSMutableArray *a = [msgs mutableCopy]; [a removeObjectAtIndex:i]; CS(@"messages", a); [ws rebuild]; });
        [del setContentHuggingPriority:1000 forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *row = RYHStack(@[send, del], 8); row.alignment = UIStackViewAlignmentFill; [self.stack addArrangedSubview:row];
    }
    [self.stack addArrangedSubview:RYBtn(T(@"+ إضافة رسالة", @"+ Add message"), NO, ^{
        [ws ask:T(@"الرسالة", @"Message") ph:@"" secure:NO ok:^(NSString *s) {
            s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if (!s.length) return;
            NSMutableArray *a = [msgs mutableCopy]; [a addObject:s]; CS(@"messages", a); [ws rebuild];
        }];
    })];
}

#pragma mark Mic
- (void)renderMic {
    __weak typeof(self) ws = self;
    UISwitch *siso = [UISwitch new]; siso.on = gIsoOn != 0; siso.onTintColor = RYAccent(); __weak UISwitch *wsiso = siso;
    [siso addAction:[UIAction actionWithHandler:^(UIAction *a) { RYMicSetIso(wsiso.on); [ws toast:wsiso.on ? T(@"انطفت العوازل — اقفل الغرفة وارجع لها", @"Isolation off — rejoin the voice room") : T(@"رجعت العوازل", @"Isolation back on")]; }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYHStack(@[RYLabel(T(@"إطفاء كل العوازل", @"Disable all isolation"), 16, UIFontWeightBold, nil), siso], 12)])];
    UISwitch *smute = [UISwitch new]; smute.on = gMicMute != 0; smute.onTintColor = UIColor.systemRedColor; __weak UISwitch *wsmute = smute;
    [smute addAction:[UIAction actionWithHandler:^(UIAction *a) { RYMicSetMute(wsmute.on); [ws rebuild]; }] forControlEvents:UIControlEventValueChanged];
    UIView *muteCard = RYCard(@[RYHStack(@[RYLabel(T(@"سكر صوتي", @"Kill mic"), 16, UIFontWeightBold, gMicMute ? UIColor.systemRedColor : nil), smute], 12),
        RYLabel(T(@"مايطلع أي صوت من مايكك للباقين مهما سويت، لين تطفيه من هنا.", @"Nothing from your mic reaches anyone else, no matter what, until you turn this off here."), 12, UIFontWeightRegular, RY_MUTED)]);
    [self.stack addArrangedSubview:muteCard];
    UISwitch *sw = [UISwitch new]; sw.on = gMicOn != 0; sw.onTintColor = RYAccent(); __weak UISwitch *wsw = sw;
    [sw addAction:[UIAction actionWithHandler:^(UIAction *a) { RYMicSetOn(wsw.on); }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYHStack(@[RYLabel(T(@"تشغيل مغيّر الصوت", @"Voice changer"), 15, UIFontWeightBold, nil), sw], 12)])];
    NSMutableArray *bs = [NSMutableArray new];
    for (int i = 0; i < RY_NPRESETS; i++) {
        NSString *nm = [NSString stringWithUTF8String:RYAr() ? kPresets[i].ar : kPresets[i].en];
        [bs addObject:RYBtn(nm, i == gMicPreset, ^{ RYMicApplyPreset(i); RYMicSetOn(YES); [ws rebuild]; })];
    }
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"الأصوات", @"Voices"), 15, UIFontWeightBold, nil), RYGrid(bs, 3)])];
    [self.stack addArrangedSubview:RYSlider(T(@"درجة الصوت (نغمات)", @"Pitch (semitones)"), -12, 12, gMicSemi, ^(float v) { gMicSemi = v; gMicPreset = -1; CS(@"micSemi", @(v)); CS(@"micPreset", @(-1)); })];
    [self.stack addArrangedSubview:RYSlider(T(@"الصدى", @"Echo"), 0, 1, gMicEcho, ^(float v) { gMicEcho = v; CS(@"micEcho", @(v)); })];
    [self.stack addArrangedSubview:RYSlider(T(@"مستوى المايك", @"Mic level"), 0.5, 2, gMicGain, ^(float v) { gMicGain = v; CS(@"micGain", @(v)); })];
    UISwitch *s1 = [UISwitch new]; s1.on = gMicDist != 0; s1.onTintColor = RYAccent(); __weak UISwitch *ws1 = s1;
    [s1 addAction:[UIAction actionWithHandler:^(UIAction *a) { RYMicSetDist(ws1.on); }] forControlEvents:UIControlEventValueChanged];
    UISwitch *s2 = [UISwitch new]; s2.on = gMicRev != 0; s2.onTintColor = RYAccent(); __weak UISwitch *ws2 = s2;
    [s2 addAction:[UIAction actionWithHandler:^(UIAction *a) { RYMicSetRev(ws2.on); }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"فضي", @"Silver"), 15, UIFontWeightBold, nil),
        RYHStack(@[RYLabel(T(@"مضخم", @"Amplifier"), 14, UIFontWeightMedium, nil), s1], 12),
        RYHStack(@[RYLabel(T(@"صدى فضي", @"Silver echo"), 14, UIFontWeightMedium, nil), s2], 12)])];
    UISwitch *s3 = [UISwitch new]; s3.on = gMonOn != 0; s3.onTintColor = RYAccent(); __weak UISwitch *ws3 = s3;
    [s3 addAction:[UIAction actionWithHandler:^(UIAction *a) { if (ws3.on) RYMonStart(); else RYMonStop(); }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYHStack(@[RYLabel(T(@"اسمع صوتي", @"Hear my voice"), 15, UIFontWeightBold, nil), s3], 12)])];
        // ---- amplifier settings
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"إعدادات المضخم", @"Amplifier settings"), 15, UIFontWeightBold, nil)])];
    [self.stack addArrangedSubview:RYSliderV(T(@"التضخيم", @"Gain"), @"dB", 0, 120, [CF(@"distDb", @60) floatValue], NO, 0, ^(float v) { gDistGain = powf(10.f, v / 20.f); CS(@"distDb", @(v)); })];
    [self.stack addArrangedSubview:RYSliderV(T(@"مستوى الخروج", @"Output"), @"dB", -30, 0, [CF(@"distOutDb", @-3) floatValue], NO, 0, ^(float v) { gDistOut = powf(10.f, v / 20.f); CS(@"distOutDb", @(v)); })];
    [self.stack addArrangedSubview:RYSliderV(T(@"عتبة الكتم", @"Gate"), @"dB", -80, -30, [CF(@"distGateDb", @-55) floatValue], NO, 0, ^(float v) { gDistGate = powf(10.f, v / 20.f); CS(@"distGateDb", @(v)); })];
    // ---- room reverb settings (every control of Dragonfly Room Reverb that matters for a mono voice)
    UILabel *rvState = RYLabel(RYRevStateText(), 12, UIFontWeightMedium, RY_MUTED); __weak UILabel *wst = rvState;
    void (^rvReset)(void) = ^{ for (int i = 0; i < RV_N; i++) gRv[i] = kRvDef[i]; RYRevSave(); [ws rebuild]; [ws toast:T(@"رجعت القيم الافتراضية", @"Defaults restored")]; };
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"إعدادات الصدى (Dragonfly)", @"Echo settings (Dragonfly)"), 15, UIFontWeightBold, nil),
        rvState, RYBtn(T(@"رجّع الافتراضي", @"Reset to default"), YES, rvReset)])];
    struct { int i; const char *ar, *en, *u; float mn, mx; BOOL lg; int d; } rv[] = {
        {RV_DRY, "الصوت الأصلي", "Dry Level", "%", 0, 100, NO, 0}, {RV_ELVL, "الانعكاسات المبكرة", "Early Level", "%", 0, 100, NO, 0},
        {RV_ESEND, "إرسال المبكر للذيل", "Early Send", "%", 0, 100, NO, 0}, {RV_LLVL, "الذيل", "Late Level", "%", 0, 100, NO, 0},
        {RV_SIZE, "حجم الغرفة", "Size", "m", 8, 60, NO, 0}, {RV_PRE, "التأخير الأولي", "Predelay", "ms", 0, 300, NO, 0},
        {RV_DECAY, "مدة الصدى", "Decay", "s", 0.1f, 20, NO, 1}, {RV_DIFF, "الانتشار", "Diffuse", "%", 0, 100, NO, 0},
        {RV_SPIN, "سرعة التذبذب", "Spin", "Hz", 0, 5, NO, 2}, {RV_WANDER, "التجوال", "Wander", "%", 0, 100, NO, 0},
        {RV_HC, "قطع الأعلى", "High Cut", "Hz", 2000, 20000, YES, 0}, {RV_EDAMP, "كتم المبكر", "Early Damp", "Hz", 2000, 20000, YES, 0},
        {RV_LDAMP, "كتم الذيل", "Late Damp", "Hz", 2000, 20000, YES, 0}, {RV_LC, "قطع الأدنى", "Low Cut", "Hz", 20, 1000, YES, 0},
        {RV_LB, "تعزيز الباص", "Low Boost", "%", 0, 200, NO, 0}, {RV_BF, "تردد التعزيز", "Boost Freq", "Hz", 100, 2000, YES, 0}};
    for (size_t q = 0; q < sizeof rv / sizeof rv[0]; q++) {
        int ix = rv[q].i;
        [self.stack addArrangedSubview:RYSliderV(T([NSString stringWithUTF8String:rv[q].ar], [NSString stringWithUTF8String:rv[q].en]), [NSString stringWithUTF8String:rv[q].u], rv[q].mn, rv[q].mx, gRv[ix], rv[q].lg, rv[q].d, ^(float v) { gRv[ix] = v; RYRevSave(); wst.text = RYRevStateText(); })];
    }
    [self.stack addArrangedSubview:RYCard(@[RYBtn(T(@"رجّع الافتراضي (الصدى)", @"Reset echo to default"), NO, rvReset)])];
    self.invLabel = RYLabel(RYMicStatus2(), 13, UIFontWeightMedium, RY_MUTED);
    [self.stack addArrangedSubview:RYCard(@[self.invLabel, RYBtn(T(@"نسخ تشخيص المايك", @"Copy mic diagnostics"), NO, ^{ UIPasteboard.generalPasteboard.string = RYMicReport(); [ws toast:T(@"اننسخ", @"Copied")]; })])];
    [self.invUI invalidate];
    self.invUI = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { ws.invLabel.text = RYMicStatus2(); }];
}

#pragma mark Diag
- (void)renderDiag {
    __weak typeof(self) ws = self;
    [self.stack addArrangedSubview:RYCard(@[
        RYBtn(T(@"تقرير كامل", @"Full report"), YES, ^{ RYShareText(ws, @"diag-full.txt", RYDiagReport()); }),
        RYBtn(T(@"شاشة الدردشة", @"Chat screen"), NO, ^{ RYShareText(ws, @"diag-chat.txt", RYDiagChat()); }),
        RYBtn(T(@"محرك الصوت", @"Voice engine"), NO, ^{ RYShareText(ws, @"diag-voice.txt", RYDiagVoice()); }),
        RYBtn(T(@"المايك", @"Mic"), NO, ^{ RYShareText(ws, @"diag-mic.txt", RYMicReport()); }),
        RYBtn(T(@"مشاركة الشاشة", @"Screen share"), NO, ^{ RYShareText(ws, @"diag-screenshare.txt", RYDiagBroadcast()); }),
        RYBtn(T(@"كلاسات بكلمة", @"Classes by keyword"), NO, ^{
            [ws ask:T(@"الكلمة", @"Keyword") ph:@"chat" secure:NO ok:^(NSString *k) { RYShareText(ws, @"diag-classes.txt", RYDiagClasses(k)); }];
        })])];
    [self.stack addArrangedSubview:RYCard(@[
        RYBtn([NSString stringWithFormat:@"%@: %@", T(@"كلاس الدردشة", @"Chat class"), CF(@"roomClass", RY_ROOM_DEFAULT)], NO, ^{
            [ws ask:T(@"كلاس الدردشة", @"Chat class") ph:RY_ROOM_DEFAULT secure:NO ok:^(NSString *s) { s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; CS(@"roomClass", s.length ? s : nil); [ws rebuild]; }];
        }),
        RYBtn([NSString stringWithFormat:@"%@: %@", T(@"زر الإرسال", @"Send label"), CF(@"sendLabel", @"send")], NO, ^{
            [ws ask:T(@"اسم زر الإرسال", @"Send button label") ph:@"send" secure:NO ok:^(NSString *s) { s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; CS(@"sendLabel", s.length ? s : nil); [ws rebuild]; }];
        }),
        RYBtn([NSString stringWithFormat:@"%@: %@", T(@"الخلفية", @"Background"), [CF(@"bgFull", @NO) boolValue] ? T(@"كل الشاشة", @"Full screen") : T(@"الدردشة فقط", @"Chat only")], NO, ^{
            CS(@"bgFull", @(![CF(@"bgFull", @NO) boolValue])); [[RYCore shared] bump]; RYRestoreAll(); [ws rebuild];
        }),
        RYBtn(RYAr() ? @"English" : @"العربية", NO, ^{ CS(@"lang", RYAr() ? @"en" : @"ar"); [ws rebuild]; })])];
    NSMutableArray *ac = [NSMutableArray new]; NSArray *cols = RYAccents();
    for (NSUInteger i = 0; i < cols.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom]; b.backgroundColor = RYHex(cols[i]); b.layer.cornerRadius = 10;
        [b addAction:[UIAction actionWithHandler:^(UIAction *a) { CS(@"accent", @(i)); [ws rebuild]; }] forControlEvents:UIControlEventTouchUpInside];
        [b.heightAnchor constraintEqualToConstant:36].active = YES; [ac addObject:b];
    }
    [self.stack addArrangedSubview:RYCard(@[RYGrid(ac, 6)])];
    self.invLabel = RYLabel(RYMicStatus2(), 13, UIFontWeightMedium, RY_MUTED);
    [self.stack addArrangedSubview:RYCard(@[self.invLabel])];
    [self.invUI invalidate];
    self.invUI = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { ws.invLabel.text = [NSString stringWithFormat:@"%@\n%@ %d\n%@", RYMicStatus2(), T(@"محرك الصوت: تعديلات", @"Voice engine: patched"), gTOCalls, RYLoggerStatus()]; }];
}
@end


#pragma mark - Core
@implementation RYCore
+ (instancetype)shared { static RYCore *c; static dispatch_once_t t; dispatch_once(&t, ^{ c = [RYCore new]; }); return c; }
- (void)bump { self.stamp++; dispatch_async(dispatch_get_main_queue(), ^{ [self syncBG:RYChatHost()]; }); }
- (void)hud:(NSString *)s {
    UIView *host = self.win.rootViewController.view; if (!host) return;
    UILabel *l = RYLabel(s, 14, UIFontWeightMedium, nil); l.textAlignment = NSTextAlignmentCenter; l.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    l.layer.cornerRadius = 12; l.clipsToBounds = YES; l.userInteractionEnabled = NO;
    CGSize z = [l sizeThatFits:CGSizeMake(host.bounds.size.width - 60, CGFLOAT_MAX)];
    l.frame = CGRectMake(0, 0, z.width + 28, z.height + 18); l.center = CGPointMake(host.bounds.size.width / 2, host.bounds.size.height - 110);
    [host addSubview:l];
    [UIView animateWithDuration:0.4 delay:4 options:0 animations:^{ l.alpha = 0; } completion:^(BOOL f) { [l removeFromSuperview]; }];
}
- (void)start {
    if (self.win) return;
    UIWindowScene *sc = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive) { sc = (UIWindowScene *)s; break; }
    if (!sc) { [self performSelector:@selector(start) withObject:nil afterDelay:1.0]; return; }
    self.win = [[RYWindow alloc] initWithWindowScene:sc]; self.win.windowLevel = UIWindowLevelAlert + 50; self.win.backgroundColor = UIColor.clearColor;
    UIViewController *root = [UIViewController new]; root.view.backgroundColor = UIColor.clearColor; self.win.rootViewController = root; self.win.hidden = NO;
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom]; b.frame = CGRectMake(0, 0, 52, 52); b.layer.cornerRadius = 26;
    b.backgroundColor = RYAccent(); b.tintColor = UIColor.whiteColor; b.layer.shadowOpacity = 0.4; b.layer.shadowRadius = 6; b.layer.shadowOffset = CGSizeMake(0, 3);
    [b setImage:[UIImage systemImageNamed:@"slider.horizontal.3"] forState:UIControlStateNormal];
    __weak typeof(self) ws = self; [b addAction:[UIAction actionWithHandler:^(UIAction *a) { [ws openPanel]; }] forControlEvents:UIControlEventTouchUpInside];
    [b addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]];
    CGSize sz = root.view.bounds.size;
    b.center = CGPointMake([CF(@"bx", @(sz.width - 40)) doubleValue], [CF(@"by", @(sz.height * 0.35)) doubleValue]);
    [root.view addSubview:b]; self.fab = b;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    RYLicRevalidate();
}
- (void)pan:(UIPanGestureRecognizer *)g {
    UIView *v = g.view; CGPoint t = [g translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y); [g setTranslation:CGPointZero inView:v.superview];
    if (g.state == UIGestureRecognizerStateEnded) {
        CGSize s = v.superview.bounds.size; UIEdgeInsets in = v.superview.safeAreaInsets;
        CGFloat x = MIN(MAX(v.center.x, 30), s.width - 30), y = MIN(MAX(v.center.y, in.top + 30), s.height - in.bottom - 30);
        [UIView animateWithDuration:0.2 animations:^{ v.center = CGPointMake(x, y); }]; CS(@"bx", @(x)); CS(@"by", @(y));
    }
}
- (void)openPanel {
    UIViewController *root = self.win.rootViewController; if (root.presentedViewController) return;
    self.prevKey = nil; for (UIWindow *w in RYAppWindows()) if (w.isKeyWindow) { self.prevKey = w; break; }
    RYPanel *p = [RYPanel new]; p.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationController *sp = p.sheetPresentationController;
    if (sp) { sp.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent]; sp.prefersGrabberVisible = YES; }
    [root presentViewController:p animated:YES completion:^{ [self.win makeKeyWindow]; }];
}
- (void)panelClosed { [self.prevKey makeKeyWindow]; }
- (void)tick {
    self.fab.hidden = NO; self.fab.backgroundColor = RYAccent(); RYHookInputs();
    [self syncBG:RYChatHost()];
    static int licTick = 0; if (++licTick % 144 == 0) RYLicRevalidate(); // ~every 72s
}
- (void)syncBG:(UIView *)chat {
    BOOL on = RYFeatureOK("bg") && ![CF(@"bgMode", @"none") isEqual:@"none"];
    RYInstallBGHook();
    // the chat view can be missing from one scan (transition, keyboard, reload): keep the wallpaper ~2 seconds before tearing it down
    if (on && !chat && self.bgView && ++self.missTicks < 4) { gBgActive = YES; return; }
    BOOL want = chat && on; gBgActive = want;
    if (!want) {
        if (self.bgView) { [self.bgView removeFromSuperview]; self.bgView = nil; self.bgHost = nil; RYRestoreAll(); }
        self.missTicks = 0;
        return;
    }
    self.missTicks = 0;
    BOOL full = [CF(@"bgFull", @NO) boolValue];
    UIView *host = full ? RYFullHost(chat) : chat;
    if (self.bgView && self.bgView.superview != host) { [self.bgView removeFromSuperview]; self.bgView = nil; RYRestoreAll(); }
    if (!self.bgView) {
        self.bgView = [[RYBGView alloc] initWithFrame:host.bounds]; self.bgView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host insertSubview:self.bgView atIndex:0]; self.bgView.stamp = -1;
    } else if (host.subviews.firstObject != self.bgView) { [host sendSubviewToBack:self.bgView]; }
    self.bgHost = host;
    // everything that would hide the wallpaper becomes see-through (re-applied every tick: the app resets colours on layout)
    RYClear(host);
    if (full) for (UIView *p = host.superview; p && ![p isKindOfClass:UIWindow.class]; p = p.superview) if (RYHasBG(p)) RYClear(p);
    RYClearBig(host, host, self.bgView, 0);
    RYClearCells(host, 0);
    if (self.bgView.stamp != self.stamp) { [self.bgView apply]; self.bgView.stamp = self.stamp; }
    UIColor *tc = RYTextTarget(); if (tc) RYTintText(host, tc, 0);
}
// code: 0 sent, 1 chat input not found, 2 not sent
// mode 0 puts the text in without focus; if the app does not accept it (or nothing sends) mode 1 types it for real (app window becomes key).
// each mode tries the send routes in turn (button called send, button beside the field, the app's own handler, return key); a message counts as sent only when the field is empty afterwards.
- (void)sendMessage:(NSString *)msg done:(void (^)(NSInteger))done {
    if (!RYFeatureOK("msg")) { done(1); return; }
    UIView *in = RYLowestInput();
    if (!in) { RYLog(@"send: chat input not found (registered inputs: %lu)", (unsigned long)gLiveInputs.allObjects.count); done(1); return; }
    __weak typeof(self) ws = self;
    void (^fin)(NSInteger) = ^(NSInteger c) {
        if (ws.win.rootViewController.presentedViewController) [ws.win makeKeyWindow];
        done(c);
    };
    [self sendTry:msg input:in prev:(RYGetText(in) ?: @"") mode:0 attempt:0 done:fin];
}
- (void)sendTry:(NSString *)msg input:(UIView *)in prev:(NSString *)prev mode:(int)mode attempt:(int)att done:(void (^)(NSInteger))done {
    __weak UIView *wi = in; __weak typeof(self) ws = self;
    if (att == 0) {
        if (mode == 0) RYSetText(in, msg);
        else {
            UIWindow *w = in.window; if (w && !w.isKeyWindow) [w makeKeyWindow];
            if (!RYTypeText(in, msg)) RYSetText(in, msg);
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *x = wi; if (!x) { done(2); return; }
        if (att == 0 && ![RYGetText(x) isEqualToString:msg]) {   // the app did not accept the text
            if (mode == 0) [ws sendTry:msg input:x prev:prev mode:1 attempt:0 done:done]; else done(2);
            return;
        }
        RYPressSend(x, att);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *y = wi; if (!y) { done(0); return; }
            if (RYGetText(y).length == 0) { done(0); return; }   // field emptied by the app = sent
            if (att < 3) { [ws sendTry:msg input:y prev:prev mode:mode attempt:att + 1 done:done]; return; }
            RYSetText(y, @"");
            if (mode == 0) [ws sendTry:msg input:y prev:prev mode:1 attempt:0 done:done];
            else { RYSetText(y, prev); done(2); }
        });
    });
}
@end

#pragma mark - Entry

__attribute__((constructor)) static void RYInit(void) {
    if (![[NSBundle mainBundle].bundlePath.pathExtension isEqual:@"app"]) return; // skip app extensions
    RYLoad();
    // crash-loop guard: if the previous launch died within 10 seconds, this launch skips the audio hooks
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    BOOL safe = [ud boolForKey:@"8ubah.dc.launching"];
    [ud setBool:YES forKey:@"8ubah.dc.launching"]; [ud synchronize];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ud setBool:NO forKey:@"8ubah.dc.launching"]; [ud synchronize]; });
    RYLog(@"=== launch (pid %d) mode: %@ ===", getpid(), safe ? @"SAFE (previous launch crashed)" : @"normal");
    if (!safe) { RYInstallMic(); RYInstallLogger(); dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ RYInstallLogger(); }); }
    // old message-logger leftovers: remove the saved data and the stale setting
    @try {
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *base = [docs stringByAppendingPathComponent:@"8ubah"];
        [[NSFileManager defaultManager] removeItemAtPath:[base stringByAppendingPathComponent:@"logger"] error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:[[base stringByAppendingPathComponent:@"logs"] stringByAppendingPathComponent:@"logger-sample.txt"] error:nil];
        if (gCfg[@"logOn"]) CS(@"logOn", nil);
    } @catch (__unused id e) {}
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { [[RYCore shared] start]; }];
}

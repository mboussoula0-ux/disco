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
// =====================================================================================================================
// AI HANDBOOK  —  everything a new AI (or person) needs before editing this file. Read it fully. Facts are marked
//   [VERIFIED] = read from the Discord 329.0 (build 100971) binary / bundle with the tools in tools/, or from code that ran on the owner's phone
//   [ASSUMED]  = reasoned from the above, never seen running. Treat as a hypothesis and check it in the Diag tab before building on it.
//
// 0. WHAT THIS IS
//   One Objective-C file, built to 8ubahDiscord.dylib and injected into a *decrypted* Discord .ipa. No Substrate, no Logos, no Theos needed:
//   hooks are done with the ObjC runtime (class_replaceMethod / method_setImplementation) and symbol-pointer rebinding (audio).
//   Owner's workflow: edit Tweak.m -> push to GitHub -> Actions builds (clang, arm64, iOS 16+, workflow .github/workflows/build.yml) ->
//   download 8ubahDiscord.dylib -> `py tools\build_ipa.py "Discord.ipa" "8ubahDiscord.dylib"` (adds one LC_LOAD_DYLIB, copies the dylib into
//   Frameworks/) -> install the *-8ubah.ipa with Sideloadly. The owner writes Arabic (Gulf dialect), answer him in Arabic. There is NO compiler
//   in the AI sandbox: every edit is compiled for the first time on GitHub, so keep edits small, re-read them, and say so when untested.
//   IMPORTANT: the IPA already contains BTLoader.dylib (Pyoncord/Bunny JS loader) + CydiaSubstrate.framework; do not touch them.
//
// 1. TOOLS (all pure python, no packages; run on the IPA itself, they are the ground truth)
//   tools/objc_dump.py  "Discord.ipa" <out.txt>        dump every ObjC class: props, ivars (offset/type in code), methods with type encodings + imp
//                                                       "Discord.ipa" sel <text>   which classes implement selectors containing <text>
//                                                       "Discord.ipa" cls <text>   full dump of classes whose name contains <text>
//   tools/fn_calls.py   "Discord.ipa" <Class> <selector part>   what an ObjC method calls (objc_msgSend selectors, strings, sub_ calls) read
//                                                       from the machine code. DEEP=3 py tools\fn_calls.py ... follows sub-calls.
//   tools/scan_ipa.py   "Discord.ipa" kw1 kw2 ...       class names / selectors / React-Native export signatures matching keywords
//   In-app: floating button -> "Diag" tab -> Full report (view controllers, chat view tree, input + send button candidates, voice engine
//   methods, hook counters, logger state). The owner shares the .txt with the AI. Always ask for it when something does not work.
//   The Hermes JS bundle (main.jsbundle) is bytecode: its strings are packed without separators, you cannot read logic from it.
//
// 2. APP FACTS  [VERIFIED]
//   * Main binary: thin arm64, chained fixups (pointer format 6), LC_ENCRYPTION cryptid 0, ~117 KB free header space. React Native, new
//     architecture (TurboModules: NativeNetworkingIOS, getTurboModule:). Native C++ voice engine (WebRTC, Krisp, AGC2) is statically linked.
//   * ObjC class names are plain DCD* (Discord) or RCT* (React Native). Swift classes are _TtC... (e.g. DiscordChat.*). Many "DCD*Model"
//     classes are Swift @objc: their stored properties are ivars WITHOUT ObjC getters (see 4.) so KVC / respondsToSelector can fail.
//   * Never use KVC (valueForKey:) on ivars that are Swift structs/enums/Optionals: it can crash hard (not catchable by @try).
//
// 3. CHAT PIPELINE  [VERIFIED by fn_calls on DCDChatManager]
//   JS (Hermes) builds rows -> RN view manager DCDChatManager  updateRows:rows:... receives a JSON *string* -> +[DCDRowModel
//   makeRowModelArrayFromJSONString:error:] -> NSArray<DCDRowModel> -> for each: [[DCDRowUpdateModel alloc] initWithRowModel:viewDataManager:error:]
//   -> -[DCDChatViewController updateRows:isLoadingAtTop:scrollData:changesetUpdateId:HACK_iOSForceAnimations:forceReload:isAnimated:]
//   (type v56@0:8@16B24@28@36B44B48B52, 7 args) -> DCDChatDataManager (ivar viewModels, viewDataDidUpdateHandler) -> DCDTableView (UITableView)
//   -> cells (message cells: DCDMessageTableViewCell, -configureWithViewModel:viewReusePoolManager:actionManager: has 5 args).
//   * The array given to updateRows: contains DCDRowUpdateModel objects (Swift, opaque), NOT messages. There is no `message` selector on them.
//   * It is a CHANGESET, not the whole list: each row carries index + changeType; Swift enum RowUpdateType = noop / insert / remove / update.
//     Therefore NEVER re-insert / drop / reorder rows natively: every later index shifts and the chat corrupts (the first logger died of this).
//   * DCDBaseRowModel ivars: index @8 (Optional<Int>, 9 bytes), changeType @24 (Int), type @32. DCDRowUpdateModel: update @8 (enum, 41 bytes),
//     index @56. DCDRowModel has messageRowModel; DCDMessageRowModel : DCDBaseRowModel has message. DCDMessageRowViewModel has props id
//     (message id string), message (DCDMessageModel), rowModel, baseMessageModel.
//   * DCDMessageModel props: id, channelID, guildID, authorID, username, usernameColor, roleColor, content (DCDStructuredTextModel), textColor,
//     timestamp, nonce, edited ... (read-only). Message cell: ivars viewModel / baseViewModel, YYLabel contentLabel (attributedText works).
//   * Chat screen = DCDChatViewController (props tableView = DCDTableView, dataManager). It is also embedded in DCDChatViewControllerContainer.
//   * Composer = DCDChatInput (RN native text input, property messageTextView is a UITextView; layout manager DCDChatInputLayoutManager).
//     Text is set natively (RYSetText -> delegate textViewDidChange:). The send button is not always a UIControl: RYPressSend uses a control
//     first, then an accessibility element named "send" (label tunable in Diag), then the return key. [ASSUMED: label/behaviour not confirmed]
//
// 4. NETWORK + GATEWAY  [VERIFIED unless marked]
//   * Gateway: URL contains `encoding=json`, compression zlib-stream / zstd-stream is decoded NATIVELY (_DCDZLibContentHandler /
//     _DCDZstdContentHandler processWebsocketMessage:forSocketID:withType:, RCTWebSocketModule). JS receives every gateway frame as plain JSON
//     text through RCTWebSocketModule -sendEventWithName:body: with name "websocketMessage" and body {data, type, id}.
//     -> RYWsSend hooks that call and can read/modify frames. Frame = {"t":EVENT,"s":seq,"op":0,"d":{...}}. Keep "s" (heartbeat sequence).
//   * REST: RN RCTNetworking (class RCTNetworking : RCTEventEmitter) over RCTHTTPRequestHandler. Events to JS (standard RN): didReceiveNetworkResponse
//     [requestID,status,headers,url], didReceiveNetworkIncrementalData [requestID,text,progress,total], didReceiveNetworkData [requestID,data],
//     didCompleteNetworkResponse [requestID,error,timedOut]. Hooks: RYNetEvent (incremental text path, buffers message-list answers),
//     RYNetSendData (-sendData:responseType:response:forTask: non-incremental path), RYHttpSend (-[RCTHTTPRequestHandler sendRequest:withDelegate:],
//     used only to see our own DELETE requests). [ASSUMED: which of the two answer paths Discord's REST client really uses; both are covered.]
//
// 5. MESSAGE LOGGER (kept deleted messages)  — the design and why
//   Goal: a message somebody else deletes stays visible (red) in DMs and group chats (never in servers: a delete with a guild_id always goes through), also after leaving / restarting the app.
//   a) RYGatewayFilter sees MESSAGE_CREATE / MESSAGE_UPDATE and remembers the message JSON (RYCacheMsg, last 120 per channel, 60 channels) and
//      every message-list REST answer too (RYMergeKeptRaw).
//   b) MESSAGE_DELETE / MESSAGE_DELETE_BULK (not our own, see RYHttpSend/RYOwnDeleted): the remembered JSON is copied to
//      Documents/8ubah/data/deleted.json (RYKeepMsg, format {"channelId":[messageJSON,...]}) and the frame is REWRITTEN into a normal
//      MESSAGE_UPDATE of the same message (full JSON if known, else {id,channel_id,guild_id}). JS therefore never deletes it, JS list, native
//      changeset and indices stay in sync. Unknown event names were tried first and are suspected to have thrown the owner out of servers: don't.
//   c) RYMergeKeptRaw adds the stored messages back into GET /channels/<id>/messages answers (respecting before/after/around/limit) so they
//      reappear after a restart. Red wash/text: RYIsKept(id) in RYDecorateCell (called from the cell configure hook and from RYRefreshCells).
//   d) Limits: a message that was never seen (deleted while the app was closed, or older than the remembered window) cannot be saved.
//   Diag report section "message logger" shows counters (ws messages seen, delete events, kept, own, put back, incremental chunks held).
//
// 6. VOICE  [VERIFIED structure, behaviour ASSUMED]
//   * Voice engine = DCDVoiceEngine (RN module, RCTEventEmitter). Settings reach the native engine through -setTransportOptions: (v24, 1 dict),
//     -connectionInstanceSetTransportOptions:options: (v32, Q instance + dict, the live-call one), -createVoiceConnectionWithOptions:withUserId:
//     withConnectionOptions:withCallback:, -setAVAudioSessionMode:, -setNoInputThreshold:. Keys scrubbed to NO: echoCancellation, noiseSuppression,
//     noiseCancellation(+DuringProcessing), automaticGainControl(+Config.useAGC2/enableAnalog/enableDigital), builtInEchoCancellation, vadUseKrisp.
//   * Capture path: the main binary imports AudioUnitRender / AudioUnitInitialize / AudioOutputUnitStart / AudioUnitSetProperty /
//     AudioComponentInstanceNew -> RYRebindImage patches those lazy pointers (mic voice changer, Stereo file-through-mic, VPIO bypass).
//     Krisp/AGC run AFTER our injection point, which is why the engine options must be scrubbed too.
//   * Safe mode: if the previous launch died within 10 s the audio hooks are skipped (key 8ubah.dc.launching).
//
// 6b. FAKE DEFEN (tab "Fake Defen")  [VERIFIED: the hooked selectors exist; behaviour on a phone ASSUMED until the Diag status line shows counters]
//   Others see your mute/deafen badge only from the gateway frame op 4 (VOICE_STATE_UPDATE: self_mute/self_deaf) that JS sends through
//   -[RCTWebSocketModule send:forSocketID:] (RYWsSendOut, installed ONLY while Fake Defen is on: joining voice broke when it was always hooked). While gFakeDef is on that one frame is rewritten to muted+deafened; the voice engine
//   (capture / playback) is never touched, so you still talk and hear. RYFakeDefSet() also pushes a fresh op 4 immediately (built from gVSReal =
//   the real state JS sent last) so the toggle takes effect without rejoining. Gateway socket id = any outgoing op 4 frame or the incoming VOICE_STATE_UPDATE. send:forSocketID: takes the socket id as a DOUBLE (not an object): hooking it with an `id` parameter
//   corrupted every outgoing gateway frame incl. heartbeats (voice dropped after ~40 s) -> fixed, RYWsSendOutD/RYWsSendOutO. Not persisted.
//
// 6d. CHAT TEXT COLOUR: only the colour the owner picks (txtMode == "custom", txtColor). There is NO automatic contrast / wallpaper luminance / username-colour copy
//   any more (it made white-on-white text). RYTextTarget() returns nil unless custom; do not add an automatic mode back unless the owner asks.
//
// 6e. EQUALIZER + STUDIO (tab "Isolation" / "عوازل"): 10 bands (RBJ biquads: peaking / low shelf / high shelf, per-band Q) on the real mic voice, inside RYVoiceBlock after the other effects
//   (RYEqPrep / RYEqRun, soft limiter at 0.8). Part of RY_FX_ON (gEqOn). Default = Flat (all dots at 0 dB, eq off); built-in presets kEqPresets (incl. "rayan" = the owner's PC screenshot), user presets CF eqUser, favourites eqFav (9), import of a SteelSeries Sonar link (RYEqImportLink, tolerant JSON parse: ASSUMED format).
//   Studio chain (RYStudioIn before the pitch stage, RYComp after the EQ): Clearcast-style expander, background / impact reduction, noise gate (fixed or auto), compressor. A time-domain approximation, not a neural net. Settings: eqOn, eqF/eqG/eqQ/eqT, eqPre, ncOn... compLvl.
//   The graph is RYEQView (UIControl): dots move ONLY in edit mode (button "Edit"); edit mode freezes the panel scroll view and the sheet (RYPanel applyEditLock) because they stole the touch. UNTESTED on device.
//
// 6f. RECORDER (tab "Record" / "تسجيل"): normal iOS screen recording leaves the voice-call audio out, so the tweak records itself: video = in-app RPScreenRecorder (looked up at run time, video frames only),
//   audio = own mic (tap at the end of RYMicFx) + everybody else (RYAUSetProp wraps the audio unit's playout render callback, input bus 0) -> 48 kHz mono, mixed on a 20 ms timer, AVAssetWriter mp4 in Documents/8ubah/rec,
//   shared with the share sheet when stopped. Switch "my mic in recording" = gRecMicOn. UNTESTED on device: the status line shows video frames / mic / voices counters; if "voices" stays x the playout path is not that callback.
//
// 7. CODE MAP (search the #pragma mark lines)
//   Config/storage (CF/CS, RYDir = Documents/8ubah), language T(ar,en), UI helpers (RYCard/RYBtn/...), view discovery (RYFindVC, RYAppWindows),
//   background view + clearing (RYBGView, RYClear*), mic/stereo, voice hooks, message logger, Discord helpers (RYChatHost, RYLowestInput,
//   RYPressSend, Diag report builders), RYWindow/RYCore (floating button, 0.8 s tick, background sync, sendMessage), quick-message loop,
//   RYPanel (tabs: Mic, Stereo, Backgrounds, Fake Defen), entry (__attribute__((constructor)) RYInit).
//   Settings are stored with CS(key,value) / read with CF(key,default) (NSUserDefaults-like JSON, file ry.cfg.v1). Keys used by chat code:
//   roomClass (chat class needle, default RY_ROOM_DEFAULT = "ChatViewController", a substring that matches DCDChatViewController), sendLabel, bgMode/bgFull.
//
// 8. RULES / PITFALLS
//   * UI rule at the top of this file (no explanatory text in the UI) is mandatory.
//   * Hooks may run on RN module queues: never touch UIKit there (dispatch to main), never block, wrap in @try, always call the original.
//   * Keep every hook idempotent and guarded by the method argument count; classes can load late (RYInstall* are retried at 2/6/15 s).
//   * Do not add features the owner did not ask for. Report honestly what is untested. Ask for the Diag report when behaviour is unknown.
//   * This file is also saved as a project: Tweak.m, Makefile (optional Theos), tools/, .github/workflows/build.yml, README.md.
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
#include <execinfo.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>

// =====================================================================================================================
// 8ubah — OWNERSHIP WATERMARK  (do not remove; the owner asked for this)
//   Proof of authorship, embedded in a dedicated Mach-O section so it survives in the built dylib and shows up in a
//   plain `strings` scan even after renaming / re-signing. If a copy of this tweak is found in the wild, this marker
//   identifies the original author. Keep the markers below in sync if the brand changes.
// =====================================================================================================================
__attribute__((used, section("__DATA,__8ubah")))
static const char k8ubahOwner[] =
    "8ubah :: original author & owner: rayan :: "
    "this Discord audio tweak, its UI and its design system are the property of the 8ubah author. "
    "unauthorized redistribution, resale, rebranding or key-cracking is prohibited. "
    "tamper-marker:8UBAH-OWNER-RAYAN-v1";
__attribute__((used, section("__DATA,__8ubah2")))
static const char k8ubahOwner2[] = "8UBAH|OWNER|RAYAN|DISCORD-TWEAK|build-v1";
#define RY_OWNER_TAG @"8ubah © rayan"

#pragma mark - Config / storage

#define RY_CFG @"ry.cfg.v1"
#define RY_ROOM_DEFAULT @"ChatViewController" // matches DCDChatViewController, DiscordChat.ChatViewController and their containers; changeable in Diag

static NSMutableDictionary *gCfg;
// gCfg is read on EVERY audio buffer from the real-time CoreAudio render thread (RYMicFx/RYVoiceBlock
// check gMicOn/gStOn/etc. via CF constantly while you're in a call) and written from the main thread
// any time a setting changes, or from the 0.8 s tick. NSMutableDictionary is not safe for that: a write
// landing mid-read (or mid-internal-rehash once the dict grows past a bucket threshold, which is exactly
// what accumulates over a call's lifetime) can corrupt it, and a corrupted-dictionary read on the
// real-time audio thread is a very plausible match for "crashes/kicks after sitting in a call a while,
// chat freezes too" — CoreAudio tends to tear the whole process/session down hard when its thread faults.
// Fix: a tiny, real-time-safe lock around the dictionary itself; the (slower) disk write in CS happens
// on a snapshot COPY, outside the lock, so the audio thread's CF() never waits on disk I/O.
static os_unfair_lock gCfgLock = OS_UNFAIR_LOCK_INIT;
static void RYLoad(void) {
    @try {
        NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:RY_CFG];
        gCfg = d ? [d mutableCopy] : [NSMutableDictionary new];
    } @catch (__unused id e) { gCfg = [NSMutableDictionary new]; }
}
static id CF(NSString *k, id def) {
    os_unfair_lock_lock(&gCfgLock); id v = gCfg[k]; os_unfair_lock_unlock(&gCfgLock);
    return v ?: def;
}
static void CS(NSString *k, id v) {
    NSDictionary *snap;
    os_unfair_lock_lock(&gCfgLock);
    if (v) gCfg[k] = v; else [gCfg removeObjectForKey:k];
    snap = [gCfg copy];
    os_unfair_lock_unlock(&gCfgLock);
    @try { [[NSUserDefaults standardUserDefaults] setObject:snap forKey:RY_CFG]; } @catch (__unused id e) {}
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
// 8ubah design system — premium black & purple. Near-black canvas with a faint purple undertone, purple-tinted
// surfaces, a hairline violet stroke on every card, and a bright accent reserved for interaction + glow.
#define RY_BG     RYHex(@"#07060C")   // canvas: near-black, faint purple undertone
#define RY_CARD   RYHex(@"#141220")   // card surface (purple-tinted charcoal)
#define RY_CARD2  RYHex(@"#1E1A2E")   // raised surface / secondary buttons
#define RY_MUTED  RYHex(@"#8E8CA8")   // secondary text
#define RY_DIM    RYHex(@"#C3C1D4")   // tertiary / body text on dark
#define RY_STROKE [UIColor colorWithRed:0.55 green:0.42 blue:1.0 alpha:0.14]   // hairline border on cards
#define RY_GLOW   [UIColor colorWithRed:0.49 green:0.36 blue:1.0 alpha:1.0]    // purple used for soft glows

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
// forward declarations: the new 8ubah components below (RYIconTab/RYSection/RYPill/RYAvatar/RYShowIntro)
// are placed here for readability but use these layout helpers, which are defined a little further down.
static UIStackView *RYVStack(NSArray *v, CGFloat sp);
static UIStackView *RYHStack(NSArray *v, CGFloat sp);
static void RYPin(UIView *v, UIView *to, CGFloat pad);
static UIView *RYCard(NSArray *views);

static UIButton *RYBtn(NSString *t, BOOL filled, void (^act)(void)) {
    UIButtonConfiguration *c = filled ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration grayButtonConfiguration];
    c.title = t; c.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    c.baseBackgroundColor = filled ? RYAccent() : RY_CARD2;
    c.baseForegroundColor = filled ? UIColor.whiteColor : RY_DIM;
    c.contentInsets = NSDirectionalEdgeInsetsMake(9, 16, 9, 16);
    c.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *a) {
        NSMutableDictionary *m = [a mutableCopy]; m[NSFontAttributeName] = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]; return m; };
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:[UIAction actionWithHandler:^(UIAction *a) { if (act) act(); }]];
    // touch feedback: a subtle press-in scale + dim, consistent on every button in the panel
    b.configurationUpdateHandler = ^(UIButton *bb) {
        bb.alpha = bb.isHighlighted ? 0.72 : 1.0;
        bb.transform = bb.isHighlighted ? CGAffineTransformMakeScale(0.97, 0.97) : CGAffineTransformIdentity;
    };
    if (filled) { // soft purple glow under the primary action
        b.layer.shadowColor = RYAccent().CGColor; b.layer.shadowOpacity = 0.45; b.layer.shadowRadius = 9;
        b.layer.shadowOffset = CGSizeMake(0, 3); b.layer.masksToBounds = NO;
    }
    b.semanticContentAttribute = RYSem();
    return b;
}
// icon-over-label tab button (top navigation). Selected = filled purple pill with glow; unselected = transparent + muted.
static UIButton *RYIconTab(NSString *name, NSString *sym, BOOL sel, void (^act)(void)) {
    UIButtonConfiguration *c = [UIButtonConfiguration filledButtonConfiguration];
    c.title = name; c.image = [UIImage systemImageNamed:sym];
    c.imagePlacement = NSDirectionalRectEdgeTop; c.imagePadding = 5;
    c.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
    c.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    c.baseBackgroundColor = sel ? RYAccent() : UIColor.clearColor;
    c.baseForegroundColor = sel ? UIColor.whiteColor : RY_MUTED;
    c.contentInsets = NSDirectionalEdgeInsetsMake(8, 14, 8, 14);
    c.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *a) {
        NSMutableDictionary *m = [a mutableCopy]; m[NSFontAttributeName] = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold]; return m; };
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:[UIAction actionWithHandler:^(UIAction *a) { if (act) act(); }]];
    if (sel) { b.layer.shadowColor = RYAccent().CGColor; b.layer.shadowOpacity = 0.5; b.layer.shadowRadius = 10; b.layer.shadowOffset = CGSizeMake(0, 3); b.layer.masksToBounds = NO; }
    b.semanticContentAttribute = RYSem();
    return b;
}
// card section header: small accent icon + bold title + optional trailing accessory (switch / menu button).
static UIStackView *RYSection(NSString *sym, NSString *title, UIView *trailing) {
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:sym]];
    icon.tintColor = RYAccent(); icon.contentMode = UIViewContentModeScaleAspectFit;
    [icon.widthAnchor constraintEqualToConstant:20].active = YES; [icon.heightAnchor constraintEqualToConstant:20].active = YES;
    UILabel *l = RYLabel(title, 16, UIFontWeightBold, nil); l.numberOfLines = 1;
    UIView *spacer = [UIView new]; [spacer setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    NSMutableArray *row = [@[icon, l, spacer] mutableCopy]; if (trailing) [row addObject:trailing];
    return RYHStack(row, 10);
}
// a styled on/off switch wired to a handler, accent-tinted.
static UISwitch *RYSwitch(BOOL on, UIColor *tint, void (^chg)(BOOL)) {
    UISwitch *s = [UISwitch new]; s.on = on; s.onTintColor = tint ?: RYAccent();
    __weak UISwitch *w = s;
    [s addAction:[UIAction actionWithHandler:^(UIAction *a) { if (chg) chg(w.on); }] forControlEvents:UIControlEventValueChanged];
    return s;
}
// small status pill ("Active", "Ready", "Saved") — a short live state chip, never explanatory text.
static UIView *RYPill(NSString *text, UIColor *tint) {
    UIColor *t = tint ?: RYAccent();
    UILabel *l = RYLabel(text, 12, UIFontWeightSemibold, t); l.textAlignment = NSTextAlignmentCenter;
    UIView *dot = [UIView new]; dot.backgroundColor = t; dot.layer.cornerRadius = 3;
    [dot.widthAnchor constraintEqualToConstant:6].active = YES; [dot.heightAnchor constraintEqualToConstant:6].active = YES;
    UIStackView *s = RYHStack(@[dot, l], 6); s.alignment = UIStackViewAlignmentCenter;
    UIView *box = [UIView new]; box.backgroundColor = [t colorWithAlphaComponent:0.14]; box.layer.cornerRadius = 11;
    box.layer.borderWidth = 1; box.layer.borderColor = [t colorWithAlphaComponent:0.35].CGColor;
    [box addSubview:s]; s.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [s.topAnchor constraintEqualToAnchor:box.topAnchor constant:6], [s.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-6],
        [s.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:12], [s.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-12]]];
    return box;
}
// circular avatar button for the voice-changer row: icon in a 56pt circle (purple + glow when selected), name below.
static UIView *RYAvatar(NSString *title, NSString *sym, BOOL sel, void (^act)(void)) {
    UIButtonConfiguration *c = [UIButtonConfiguration filledButtonConfiguration];
    c.image = [UIImage systemImageNamed:sym]; c.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    c.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold];
    c.baseBackgroundColor = sel ? RYAccent() : RY_CARD2; c.baseForegroundColor = sel ? UIColor.whiteColor : RY_DIM;
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:[UIAction actionWithHandler:^(UIAction *a) { if (act) act(); }]];
    [b.widthAnchor constraintEqualToConstant:56].active = YES; [b.heightAnchor constraintEqualToConstant:56].active = YES;
    if (sel) { b.layer.shadowColor = RYAccent().CGColor; b.layer.shadowOpacity = 0.6; b.layer.shadowRadius = 10; b.layer.shadowOffset = CGSizeMake(0, 2); b.layer.masksToBounds = NO; }
    UILabel *l = RYLabel(title, 11, UIFontWeightMedium, sel ? nil : RY_MUTED); l.textAlignment = NSTextAlignmentCenter; l.numberOfLines = 1;
    [l.widthAnchor constraintLessThanOrEqualToConstant:66].active = YES;
    UIStackView *v = RYVStack(@[b, l], 5); v.alignment = UIStackViewAlignmentCenter;
    return v;
}
// horizontal scrolling row of avatars (keeps the voice-changer presets on one swipeable line, like the mockup).
static UIView *RYAvatarRow(NSArray<UIView *> *items) {
    UIScrollView *sc = [UIScrollView new]; sc.showsHorizontalScrollIndicator = NO;
    UIStackView *h = RYHStack(items, 12); h.alignment = UIStackViewAlignmentTop;
    [sc addSubview:h]; h.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [h.topAnchor constraintEqualToAnchor:sc.contentLayoutGuide.topAnchor], [h.bottomAnchor constraintEqualToAnchor:sc.contentLayoutGuide.bottomAnchor],
        [h.leadingAnchor constraintEqualToAnchor:sc.contentLayoutGuide.leadingAnchor], [h.trailingAnchor constraintEqualToAnchor:sc.contentLayoutGuide.trailingAnchor],
        [h.heightAnchor constraintEqualToAnchor:sc.frameLayoutGuide.heightAnchor]]];
    [sc.heightAnchor constraintEqualToConstant:86].active = YES;
    return sc;
}
// =========================================================================================================
// Cinematic intro — one 8ubah splash per app launch. Black canvas + purple haze -> logo springs in and glows
// -> short pulse hold -> the mark bursts into purple particles and the logo dissolves -> everything fades out
// and the overlay window removes itself (~3.3 s total). Shown over Discord, never blocks it (touches fall
// through), auto-cleans, and is skipped in crash-safe mode. Original 8ubah mark, drawn in code (no artwork).
// =========================================================================================================
static void RYShowIntro(UIWindowScene *scene) {
    if (!scene) return;
    CGRect sb = scene.coordinateSpace.bounds; if (sb.size.width < 50) sb = UIScreen.mainScreen.bounds;
    UIWindow *win = [[UIWindow alloc] initWithWindowScene:scene];
    win.windowLevel = UIWindowLevelAlert + 100; win.userInteractionEnabled = NO; win.backgroundColor = UIColor.blackColor;
    UIViewController *vc = [UIViewController new]; vc.view.backgroundColor = UIColor.blackColor; vc.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    win.rootViewController = vc; win.frame = sb; win.hidden = NO;
    UIView *root = vc.view;
    // radial purple haze behind the mark
    CAGradientLayer *haze = [CAGradientLayer layer]; haze.type = kCAGradientLayerRadial; haze.frame = sb;
    haze.colors = @[(id)[UIColor colorWithRed:0.42 green:0.25 blue:0.98 alpha:0.55].CGColor, (id)UIColor.clearColor.CGColor];
    haze.startPoint = CGPointMake(0.5, 0.5); haze.endPoint = CGPointMake(1.0, 1.0); haze.opacity = 0;
    [root.layer addSublayer:haze];
    // logo column: glowing "8" tile, "8ubah" wordmark, spaced "DISCORD MOD"
    UILabel *mark = RYLabel(@"8", 44, UIFontWeightHeavy, UIColor.whiteColor); mark.textAlignment = NSTextAlignmentCenter;
    UIView *box = [UIView new]; box.backgroundColor = RYAccent(); box.layer.cornerRadius = 22; box.layer.cornerCurve = kCACornerCurveContinuous;
    box.layer.shadowColor = RYAccent().CGColor; box.layer.shadowOpacity = 0.95; box.layer.shadowRadius = 30; box.layer.shadowOffset = CGSizeZero; box.layer.masksToBounds = NO;
    [box addSubview:mark]; RYPin(mark, box, 0);
    [box.widthAnchor constraintEqualToConstant:96].active = YES; [box.heightAnchor constraintEqualToConstant:96].active = YES;
    UILabel *word = RYLabel(@"8ubah", 34, UIFontWeightHeavy, UIColor.whiteColor); word.textAlignment = NSTextAlignmentCenter;
    UILabel *sub = [UILabel new]; sub.textAlignment = NSTextAlignmentCenter;
    sub.attributedText = [[NSAttributedString alloc] initWithString:@"discord.gg/ulp" attributes:@{NSKernAttributeName: @1, NSForegroundColorAttributeName: RYAccent(), NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]}];
    UIStackView *col = RYVStack(@[box, word, sub], 14); col.alignment = UIStackViewAlignmentCenter;
    [root addSubview:col]; col.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[[col.centerXAnchor constraintEqualToAnchor:root.centerXAnchor], [col.centerYAnchor constraintEqualToAnchor:root.centerYAnchor]]];
    col.alpha = 0; col.transform = CGAffineTransformMakeScale(0.7, 0.7);
    // 1) logo springs in with the haze
    [UIView animateWithDuration:0.7 delay:0.1 usingSpringWithDamping:0.68 initialSpringVelocity:0.6 options:UIViewAnimationOptionCurveEaseOut animations:^{ col.alpha = 1; col.transform = CGAffineTransformIdentity; } completion:nil];
    CABasicAnimation *hz = [CABasicAnimation animationWithKeyPath:@"opacity"]; hz.fromValue = @0; hz.toValue = @1; hz.beginTime = CACurrentMediaTime() + 0.1; hz.duration = 0.7; hz.fillMode = kCAFillModeForwards; hz.removedOnCompletion = NO; [haze addAnimation:hz forKey:@"in"];
    // 2) short glow pulse while it holds
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"]; pulse.fromValue = @1.0; pulse.toValue = @1.06; pulse.duration = 0.6; pulse.autoreverses = YES; pulse.beginTime = CACurrentMediaTime() + 0.85; pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]; [box.layer addAnimation:pulse forKey:@"pulse"];
    // 3) particle burst + dissolve at ~2.0 s
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CAEmitterLayer *em = [CAEmitterLayer layer];
        em.emitterPosition = CGPointMake(CGRectGetMidX(sb), CGRectGetMidY(sb) - 40);
        em.emitterShape = kCAEmitterLayerCircle; em.emitterMode = kCAEmitterLayerOutline; em.emitterSize = CGSizeMake(96, 96);
        CAEmitterCell *cell = [CAEmitterCell emitterCell];
        cell.birthRate = 1100; cell.lifetime = 1.1f; cell.velocity = 190; cell.velocityRange = 90; cell.emissionRange = (float)(2 * M_PI);
        cell.scale = 0.06f; cell.scaleRange = 0.04f; cell.alphaSpeed = -0.95f; cell.color = RY_GLOW.CGColor;
        UIGraphicsImageRenderer *rnd = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(10, 10)];
        UIImage *dot = [rnd imageWithActions:^(UIGraphicsImageRendererContext *ctx) { [UIColor.whiteColor setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 10, 10)] fill]; }];
        cell.contents = (id)dot.CGImage; em.emitterCells = @[cell]; [root.layer addSublayer:em];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ em.birthRate = 0; });
        [UIView animateWithDuration:0.8 animations:^{ col.alpha = 0; col.transform = CGAffineTransformMakeScale(1.25, 1.25); haze.opacity = 0; }];
    });
    // 4) remove the overlay window
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.4 animations:^{ win.alpha = 0; } completion:^(BOOL f) { win.hidden = YES; }];
    });
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
    UIView *c = [UIView new]; c.backgroundColor = RY_CARD; c.layer.cornerRadius = 16;
    c.layer.borderWidth = 1; c.layer.borderColor = RY_STROKE.CGColor; c.layer.cornerCurve = kCACornerCurveContinuous;
    UIStackView *s = RYVStack(views, 10); [c addSubview:s]; RYPin(s, c, 14); return c;
}
static UIView *RYSlider(NSString *title, float mn, float mx, float val, void (^chg)(float)) {
    UILabel *l = RYLabel(title, 14, UIFontWeightMedium, nil);
    UISlider *s = [UISlider new]; s.minimumValue = mn; s.maximumValue = mx; s.value = val; s.minimumTrackTintColor = RYAccent(); s.maximumTrackTintColor = RY_CARD2;
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
        for (UIWindow *w in ((UIWindowScene *)s).windows) { NSString *wc = NSStringFromClass(w.class); if (![wc isEqual:@"RYWindow"] && ![wc isEqual:@"RYCatWindow"]) [a addObject:w]; }
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
static NSHashTable *gKeepClear; static os_unfair_lock gKCLock = OS_UNFAIR_LOCK_INIT; static BOOL gBgActive = NO; // views we made see-through stay see-through even when the app paints them again
static BOOL RYKeepHas(id v) { if (!gKeepClear || !v) return NO; os_unfair_lock_lock(&gKCLock); BOOL r = [gKeepClear containsObject:v]; os_unfair_lock_unlock(&gKCLock); return r; }
static void (*orig_setBGC)(id, SEL, UIColor *);
static void RYSetBGC(id self, SEL _cmd, UIColor *c) {
    if (gBgActive && gKeepClear && c && RYKeepHas(self)) c = UIColor.clearColor;
    orig_setBGC(self, _cmd, c);
}
// RN / Discord views can paint straight onto the layer (or override setBackgroundColor: without calling UIView's), which skipped the hook above and
// let the black come back for up to half a second between two ticks. Hook the layer setter too: it catches every route.
static void (*orig_layerSetBGC)(id, SEL, CGColorRef);
static void RYLayerSetBGC(id self, SEL _cmd, CGColorRef c) {
    if (gBgActive && c && gKeepClear) {
        id d = ((CALayer *)self).delegate;
        if (d && [d isKindOfClass:UIView.class] && ((UIView *)d).layer == (CALayer *)self && RYKeepHas(d) && CGColorGetAlpha(c) > 0.001) c = UIColor.clearColor.CGColor;
    }
    orig_layerSetBGC(self, _cmd, c);
}
static void RYHookOwnBGC(Class c) {
    SEL s = @selector(setBackgroundColor:);
    Method m = class_getInstanceMethod(c, s); if (!m) return;
    IMP orig = method_getImplementation(m);
    void (^blk)(id, UIColor *) = ^(id me, UIColor *col) {
        if (gBgActive && col && gKeepClear && RYKeepHas(me)) col = UIColor.clearColor;
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
    if (!gKeepClear) gKeepClear = [NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality];
    if (![gOrigBG objectForKey:v]) [gOrigBG setObject:(v.backgroundColor ?: (id)NSNull.null) forKey:v];
    os_unfair_lock_lock(&gKCLock); [gKeepClear addObject:v]; os_unfair_lock_unlock(&gKCLock);
    v.backgroundColor = UIColor.clearColor;
}
static void RYRestoreAll(void) {
    BOOL was = gBgActive; gBgActive = NO;
    for (UIView *v in [gOrigBG.keyEnumerator allObjects]) {
        id o = [gOrigBG objectForKey:v]; v.backgroundColor = [o isKindOfClass:UIColor.class] ? o : nil;
    }
    [gOrigBG removeAllObjects]; os_unfair_lock_lock(&gKCLock); [gKeepClear removeAllObjects]; os_unfair_lock_unlock(&gKCLock);
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
// ---- Equalizer (tab "Isolation"): 10 peaking bands on YOUR real mic voice. Defaults = the owner's screenshot of the PC equalizer
// (frequency in Hz / gain in dB read off the picture). Off until the owner switches it on; then it is part of the mic chain (RY_FX_ON).
#define RYEQ_N 10
// band type: 0 = peaking, 1 = low shelf, 2 = high shelf. Default (and "Flat" preset) = every dot at 0 dB.
static const float kEqF[RYEQ_N] = {31.f, 62.f, 125.f, 250.f, 500.f, 1000.f, 2000.f, 4000.f, 8000.f, 16000.f};
static const float kEqG[RYEQ_N] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
static volatile int gEqOn = 0, gEqVer = 1;
static volatile float gEqF[RYEQ_N] = {31.f, 62.f, 125.f, 250.f, 500.f, 1000.f, 2000.f, 4000.f, 8000.f, 16000.f};
static volatile float gEqG[RYEQ_N] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
static volatile float gEqQ[RYEQ_N] = {1.1f, 1.1f, 1.1f, 1.1f, 1.1f, 1.1f, 1.1f, 1.1f, 1.1f, 1.1f};
static volatile int gEqT[RYEQ_N] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
static volatile float gEqPre = 0;
// studio chain (tab "Isolation"): Clearcast-style noise suppression, noise reduction (background / impact), noise gate, compressor. All off by default.
static volatile int gNcOn = 0, gNrBgOn = 0, gNrImpOn = 0, gGateOn = 0, gGateAuto = 0, gCompOn = 0;
static volatile float gNcAmt = 0.2f, gNrBg = 0.f, gNrImp = 0.f, gGateThr = -56.3f, gCompLvl = 1.f;
#define RY_STUDIO (gNcOn || gNrBgOn || gNrImpOn || gGateOn || gCompOn)
// built-in presets (name, 10 x freq, 10 x gain dB, 10 x Q, 10 x type)
typedef struct { const char *name; float f[RYEQ_N], g[RYEQ_N], q[RYEQ_N]; int t[RYEQ_N]; } RYEqPreset;
static const RYEqPreset kEqPresets[] = {
    {"Flat",          {31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000}, {0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, {1.1f, 1.1f, 1.1f, 1.1f, 1.1f, 1.1f, 1.1f, 1.1f, 1.1f, 1.1f}, {0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
    {"rayan",         {30, 90, 300, 500, 1000, 2000, 4000, 12000, 13600, 17400}, {-1.5f, 9.1f, -1.3f, 0, -2.8f, 3.0f, 4.0f, 12.0f, 3.3f, 4.0f}, {1.1f, 1.1f, 1.1f, 1.1f, 1.1f, 1.1f, 1.1f, 1.1f, 1.1f, 1.1f}, {0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
    {"Studio Vocal",  {80, 160, 300, 500, 1000, 2000, 3500, 6000, 10000, 14000}, {-6.f, -1.5f, -2.0f, -1.0f, 0, 1.5f, 3.0f, 1.5f, 1.5f, 2.0f}, {0.7f, 1.0f, 1.2f, 1.0f, 1.0f, 1.0f, 1.2f, 1.0f, 1.0f, 0.7f}, {1, 0, 0, 0, 0, 0, 0, 0, 0, 2}},
    {"Broadcast",     {70, 120, 220, 400, 800, 1600, 3000, 5000, 9000, 14000}, {-5.f, 2.5f, 1.5f, -2.0f, 0, 1.0f, 2.5f, 1.0f, -1.0f, 1.5f}, {0.7f, 1.0f, 1.0f, 1.2f, 1.0f, 1.0f, 1.1f, 1.0f, 1.0f, 0.7f}, {1, 0, 0, 0, 0, 0, 0, 0, 0, 2}},
    {"Crystal Clear", {60, 120, 250, 500, 1000, 2000, 3500, 6000, 10000, 15000}, {-6.f, -2.0f, -1.5f, -2.0f, 0, 2.0f, 3.5f, 2.5f, 2.0f, 3.0f}, {0.7f, 1.0f, 1.2f, 1.0f, 1.0f, 1.0f, 1.2f, 1.0f, 1.0f, 0.7f}, {1, 0, 0, 0, 0, 0, 0, 0, 0, 2}},
    {"Deep Voice",    {60, 100, 160, 300, 600, 1200, 2400, 4800, 9000, 14000}, {2.0f, 4.5f, 3.0f, 0.5f, -1.0f, -1.0f, 0.5f, 1.0f, 0, 0}, {0.7f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 0.7f}, {1, 0, 0, 0, 0, 0, 0, 0, 0, 2}},
    {"فضي 1",         {31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000}, {1, 2, 2, 1, -2, 4, 5, 6, 5, 5}, {1.1f,1.1f,1.1f,1.1f,1.1f,1.1f,1.1f,1.1f,1.1f,1.1f}, {0,0,0,0,0,0,0,0,0,0}},
    {"فضي 2",         {31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000}, {6, 10, 12, 12, 0, -3, 1, 4, 5, 5}, {1.1f,1.1f,1.1f,1.1f,1.1f,1.1f,1.1f,1.1f,1.1f,1.1f}, {0,0,0,0,0,0,0,0,0,0}},
    {"فضي 3",         {31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000}, {-1, -2, -2, -3, -12, 12, 12, 12, 12, 12}, {1.1f,1.1f,1.1f,1.1f,1.1f,1.1f,1.1f,1.1f,1.1f,1.1f}, {0,0,0,0,0,0,0,0,0,0}},
};
#define RY_NEQP ((int)(sizeof(kEqPresets) / sizeof(kEqPresets[0])))
static volatile long long gMicCallsA = 0, gMicCallsU = 0, gMicCallsT = 0, gMicProc = 0;
static volatile int gMicRebound = 0, gMicWrapped = 0, gMicTapInst = 0;
static volatile int gMicDist = 0, gMonOn = 0;
static volatile int gRevMic = 0, gRevSong = 0; // Haunted Cavern echo amount 0-100: separate for mic voice and for the stereo/song file
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

#define RY_FX_ON (RYFeatureOK("fx") && (gMicOn || gMicDist || gRevMic || gMicMute || gStOn || gEqOn || RY_STUDIO))   // the "Silver" effects (amplifier, silver echo) work on their own, without the voice-changer switch; Stereo file playback also needs the pipeline live
enum { RV_DRY, RV_ELVL, RV_ESEND, RV_LLVL, RV_SIZE, RV_PRE, RV_DECAY, RV_DIFF, RV_SPIN, RV_WANDER, RV_HC, RV_EDAMP, RV_LDAMP, RV_LC, RV_LB, RV_BF, RV_N };
// Haunted Cavern voicing (SB0490 "silver card" EAX preset): big dark cave, long tail, slow modulation for the eerie shimmer. Fixed; only the amount is exposed.
static const float kRvDef[RV_N] = {100, 42, 85, 92, 60, 70, 7.0f, 78, 0.6f, 50, 6000, 6500, 6500, 150, 40, 110}; // Haunted Cavern: long lingering tail (RT60~5.4s)
static volatile float gRv[RV_N]  = {100, 42, 85, 92, 60, 70, 7.0f, 78, 0.6f, 50, 6000, 6500, 6500, 150, 40, 110};
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
    int eqVer; double eqSr; float eqc[RYEQ_N][5]; float eqz[RYEQ_N][2]; unsigned char eqAct[RYEQ_N];   // equalizer: coefficients (b0 b1 b2 a1 a2) + state per band
    float stEnv, stFloor, stGate, stOpen, stFast, stSlow, stHx, stCe, stInit;   // studio chain state
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
// Equalizer. Coefficients are rebuilt only when the owner changes something (gEqVer) or the capture sample rate changes. A band above 45% of the sample
// rate (e.g. 17 kHz when the phone captures at 16 kHz) is skipped. After the bands a soft limiter (knee at 0.8) keeps +12 dB boosts from clipping.
// RBJ biquad for one band: type 0 peaking, 1 low shelf, 2 high shelf. o = {b0, b1, b2, a1, a2} already divided by a0. Returns NO when the band does nothing.
static BOOL RYEqCoef(int t, float f, float g, float q, double sr, double *o) {
    if (fabsf(g) < 0.05f || f < 15.f || f > 0.45f * (float)sr) return NO;
    if (q < 0.2f) q = 0.2f; if (q > 10.f) q = 10.f;
    double A = pow(10.0, g / 40.0), w0 = 2.0 * M_PI * f / sr, cw = cos(w0), al = sin(w0) / (2.0 * q), b0, b1, b2, a0, a1, a2;
    if (t == 1 || t == 2) {
        double sq = 2.0 * sqrt(A) * al;
        if (t == 1) { b0 = A * ((A + 1) - (A - 1) * cw + sq); b1 = 2 * A * ((A - 1) - (A + 1) * cw); b2 = A * ((A + 1) - (A - 1) * cw - sq); a0 = (A + 1) + (A - 1) * cw + sq; a1 = -2 * ((A - 1) + (A + 1) * cw); a2 = (A + 1) + (A - 1) * cw - sq; }
        else        { b0 = A * ((A + 1) + (A - 1) * cw + sq); b1 = -2 * A * ((A - 1) + (A + 1) * cw); b2 = A * ((A + 1) + (A - 1) * cw - sq); a0 = (A + 1) - (A - 1) * cw + sq; a1 = 2 * ((A - 1) - (A + 1) * cw); a2 = (A + 1) - (A - 1) * cw - sq; }
    } else { b0 = 1 + al * A; b1 = -2 * cw; b2 = 1 - al * A; a0 = 1 + al / A; a1 = -2 * cw; a2 = 1 - al / A; }
    o[0] = b0 / a0; o[1] = b1 / a0; o[2] = b2 / a0; o[3] = a1 / a0; o[4] = a2 / a0; return YES;
}
static void RYEqPrep(RYVS *s, double sr) {
    if (s->eqVer == gEqVer && s->eqSr == sr) return;
    for (int b = 0; b < RYEQ_N; b++) {
        double o[5]; s->eqAct[b] = 0;
        if (RYEqCoef(gEqT[b], gEqF[b], gEqG[b], gEqQ[b], sr, o)) { for (int k = 0; k < 5; k++) s->eqc[b][k] = (float)o[k]; s->eqAct[b] = 1; }
    }
    s->eqVer = gEqVer; s->eqSr = sr;
}
static inline float RYEqRun(float x, RYVS *s, float pre) {
    float y = x * pre;
    for (int b = 0; b < RYEQ_N; b++) if (s->eqAct[b]) {
        const float *c = s->eqc[b]; float o = c[0] * y + s->eqz[b][0];
        s->eqz[b][0] = c[1] * y - c[3] * o + s->eqz[b][1]; s->eqz[b][1] = c[2] * y - c[4] * o; y = o;
    }
    float a = fabsf(y); if (a > 0.8f) y = copysignf(0.8f + 0.2f * tanhf((a - 0.8f) / 0.2f), y);
    return y;
}
// Studio chain. Everything works from a peak envelope of the raw voice and a tracked noise floor (falls fast, rises over ~6 s), so it needs no calibration.
//  noise cancellation / background reduction: downward expander relative to the floor (+ a gentle low cut); impact: clamps very fast transients; gate: hysteresis gate (fixed or auto = floor x 3).
//  This is a time-domain approximation of Clearcast, not a neural network: it removes noise in the pauses, it does not separate noise from the voice while you talk.
typedef struct { float rEnv, rFast, aSlow, aG, rG, rise, fall, hp, aC, rC, gateLin; } RYStC;
static void RYStPrep(RYStC *c, double sr) {
    const float r = (float)sr;
    c->rEnv = expf(-1.f / (0.03f * r)); c->rFast = expf(-1.f / (0.003f * r)); c->aSlow = 1.f - expf(-1.f / (0.06f * r));
    c->aG = 1.f - expf(-1.f / (0.003f * r)); c->rG = 1.f - expf(-1.f / (0.08f * r));
    c->rise = 1.f / (6.f * r); c->fall = 1.f - expf(-1.f / (0.02f * r)); c->hp = 1.f - expf(-6.2831853f * 70.f / r);
    c->aC = 1.f - expf(-1.f / (0.005f * r)); c->rC = 1.f - expf(-1.f / (0.12f * r)); c->gateLin = powf(10.f, gGateThr / 20.f);
}
static inline float RYStudioIn(float x, RYVS *s, const RYStC *c) {
    float a = fabsf(x);
    s->stEnv = a > s->stEnv ? a : s->stEnv * c->rEnv; const float env = s->stEnv;
    if (s->stInit < 0.5f) { s->stFloor = fmaxf(env, 1e-3f); s->stInit = 1.f; }
    s->stFloor += (env - s->stFloor) * (env < s->stFloor ? c->fall : c->rise);
    if (s->stFloor < 1e-5f) s->stFloor = 1e-5f;
    float g = 1.f;
    if (gNcOn || gNrBgOn) {
        float amt = gNcOn ? gNcAmt : gNrBg, k = gNcOn ? 2.f + 5.f * amt : 1.5f + 3.f * amt, p = gNcOn ? 1.f + 2.f * amt : 1.f;
        float r = env / (s->stFloor * k); if (r < 1.f) g *= powf(fmaxf(r, 1e-3f), p);
        s->stHx += c->hp * (x - s->stHx); x -= s->stHx * (0.4f + 0.6f * amt);
    }
    if (gNrImpOn && !gNcOn) {
        s->stFast = a > s->stFast ? a : s->stFast * c->rFast; s->stSlow += (a - s->stSlow) * c->aSlow;
        float allowed = 3.f + 6.f * (1.f - gNrImp), rr = s->stFast / (s->stSlow + 1e-5f); if (rr > allowed) g *= allowed / rr;
    }
    if (gGateOn) {
        float thr = gGateAuto ? s->stFloor * 3.f : c->gateLin;
        if (env > thr) s->stOpen = 1.f; else if (env < thr * 0.7f) s->stOpen = 0.f;
        g *= s->stOpen > 0.5f ? 1.f : 0.f;
    }
    s->stGate += (g - s->stGate) * (g > s->stGate ? c->aG : c->rG);
    return x * s->stGate;
}
static inline float RYComp(float x, RYVS *s, const RYStC *c) {
    float a = fabsf(x); s->stCe += (a - s->stCe) * (a > s->stCe ? c->aC : c->rC);
    float db = 20.f * log10f(fmaxf(s->stCe, 1e-6f)), thr = -20.f, ratio = 1.f + 3.f * gCompLvl, red = db > thr ? (db - thr) * (1.f - 1.f / ratio) : 0.f;
    float gdb = 0.4f * (-thr) * (1.f - 1.f / ratio) - red;   // makeup = 40% of the maximum reduction
    return x * exp2f(gdb * 0.16609640f);
}
// pitch shift = two read taps on a delay line that slides at (1 - ratio) samples per sample, cross-faded with a Hann window
static inline float RYRevAmt(int amt) { if (amt <= 0) return 0.f; if (amt > 100) amt = 100; return powf((float)amt / 100.f, 0.45f); }
static RYVS gSongVS;
static void RYCavern(float *x, int n, double sr, RYVS *s, int amount) {
    if (amount <= 0) return;
    if (s->sr != sr) { memset(s, 0, sizeof(RYVS)); s->sr = sr; }
    RYRevC rc; RYRevPrep(&rc, sr);
    float a = RYRevAmt(amount); rc.dry = 1.f; rc.elv *= a; rc.llv *= a;
    for (int i = 0; i < n; i++) { float y = RYRev(x[i], s, &rc); if (y > 1.f) y = 1.f; else if (y < -1.f) y = -1.f; x[i] = y; }
}
static void RYVoiceBlock(float *x, int n, double sr, RYVS *s) {
    if (s->sr != sr) { memset(s, 0, sizeof(RYVS)); s->sr = sr; s->d1 = (float)(0.016 * sr); }
    if (gMicMute) { memset(x, 0, (size_t)n * sizeof(float)); return; } // overrides everything else, on purpose
    const int W = (int)(0.032 * sr); const int revAmt = gRevMic, revOn = revAmt > 0; RYRevC rc;
    if (revOn) { RYRevPrep(&rc, sr); float a = RYRevAmt(revAmt); rc.dry = 1.f; rc.elv *= a; rc.llv *= a; }
    const int mst = gMicOn; // pitch / voice / echo / mic level belong to the main switch; amplifier and silver echo have their own
    const float semi = mst ? gMicSemi : 0.f, echo = mst ? gMicEcho : 0.f, gain = mst ? gMicGain : 1.f; const int mode = mst ? gMicMode : 0;
    const float dd = 1.f - powf(2.f, semi / 12.f);
    const BOOL pitch = fabsf(semi) > 0.05f;
    const int eqOn = gEqOn; const float eqPre = powf(10.f, gEqPre / 20.f); if (eqOn) RYEqPrep(s, sr);
    const int studio = RY_STUDIO, compOn = studio && gCompOn; RYStC sc; if (studio) RYStPrep(&sc, sr);
    int ed = (int)(0.27 * sr); if (ed >= RYM_ECHO) ed = RYM_ECHO - 1;
    const float rph = (float)(2.0 * M_PI * 70.0 / sr);
    for (int i = 0; i < n; i++) {
        float in = x[i] * gain; if (studio) in = RYStudioIn(in, s, &sc); float y = in;
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
        if (eqOn) y = RYEqRun(y, s, eqPre);
        if (compOn) y = RYComp(y, s, &sc);
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
// ---- Recorder (tab "Record"): iOS leaves the voice-call audio out of the normal screen recording, so the app records itself. Video = in-app ReplayKit capture (video frames only, looked up at
// run time), audio = what this tweak already sees: YOUR microphone after the effects (RYMicFx) + everybody else's voices = the playout render callback of the audio unit (RYAUSetProp wraps
// kAudioUnitProperty_SetRenderCallback, input bus 0). Both are resampled to 48 kHz mono, mixed on a 20 ms timer and written with the frames into an mp4 (AVAssetWriter). ASSUMED until the
// status line shows both counters moving (mic / voices).
static volatile int gRecOn = 0, gRecMicOn = 1;
#define RYREC_N (1 << 18)
static float gRecRingM[RYREC_N], gRecRingP[RYREC_N]; static volatile unsigned gRecWM = 0, gRecRM = 0, gRecWP = 0, gRecRP = 0;
static volatile long long gRecMicN = 0, gRecPlayN = 0, gRecVidN = 0, gRecAudN = 0, gRecHook = 0; static volatile double gRecStart = 0;
typedef struct { double pos; float last; } RYRsS; static RYRsS gRsM, gRsP;
static void RYRecPush(float *ring, volatile unsigned *w, RYRsS *st, const float *x, int n, double sr) {
    if (n <= 0) return; if (sr < 4000) sr = 48000;
    double step = sr / 48000.0, pos = st->pos; float last = st->last; unsigned wi = *w;
    while (pos < (double)(n - 1)) { int i = (int)floor(pos); float a = i < 0 ? last : x[i], b = x[i + 1], fr = (float)(pos - (double)i); ring[wi & (RYREC_N - 1)] = a + (b - a) * fr; wi++; pos += step; }
    st->pos = pos - (double)n; st->last = x[n - 1]; __sync_synchronize(); *w = wi;
}
static void RYRecMic(const float *x, int n, double sr) { if (!gRecOn || !gRecMicOn) return; gRecMicN += n; RYRecPush(gRecRingM, &gRecWM, &gRsM, x, n, sr); }
// mono float copy of channel 0 of a raw buffer list, then into the "voices" ring
static void RYRecPlayTap(const AudioStreamBasicDescription *f, UInt32 n, AudioBufferList *io) {
    if (!f || !io || !io->mNumberBuffers || f->mFormatID != kAudioFormatLinearPCM) return;
    BOOL isFloat = (f->mFormatFlags & kAudioFormatFlagIsFloat) != 0, planar = (f->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0; UInt32 bits = f->mBitsPerChannel, ch = f->mChannelsPerFrame ? f->mChannelsPerFrame : 1;
    if (!((isFloat && bits == 32) || (!isFloat && bits == 16))) return;
    static __thread float tmp[4096]; UInt32 frames = planar ? io->mBuffers[0].mDataByteSize / (bits / 8) : io->mBuffers[0].mDataByteSize / (ch * (bits / 8)); if (frames > n) frames = n; if (frames > 4096) frames = 4096;
    void *d = io->mBuffers[0].mData; if (!d) return; UInt32 st = planar ? 1 : ch;
    for (UInt32 i = 0; i < frames; i++) tmp[i] = isFloat ? ((float *)d)[i * st] : (float)((int16_t *)d)[i * st] / 32768.f;
    gRecPlayN += frames; RYRecPush(gRecRingP, &gRecWP, &gRsP, tmp, (int)frames, f->mSampleRate > 0 ? f->mSampleRate : 48000);
}
// playout: wrap the render callback the audio unit pulls its speaker data from
typedef struct { AURenderCallback proc; void *ref; AudioUnit au; AudioStreamBasicDescription f; int have; } RYPbCtx;
static OSStatus RYPlayCB(void *ref, AudioUnitRenderActionFlags *fl, const AudioTimeStamp *ts, UInt32 bus, UInt32 n, AudioBufferList *io) {
    RYPbCtx *c = (RYPbCtx *)ref; OSStatus r = c->proc(c->ref, fl, ts, bus, n, io);
    if (r != noErr || !gRecOn || !io) return r;
    if (!c->have) {
        UInt32 sz = sizeof c->f; memset(&c->f, 0, sizeof c->f);
        BOOL got = AudioUnitGetProperty(c->au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &c->f, &sz) == noErr && c->f.mSampleRate > 0;
        if (!got) { sz = sizeof c->f; memset(&c->f, 0, sizeof c->f); got = AudioUnitGetProperty(c->au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &c->f, &sz) == noErr && c->f.mSampleRate > 0; }
        if (!got) { // the property wasn't available: infer the format from the buffer the callback just filled, so room audio is still captured
            memset(&c->f, 0, sizeof c->f);
            BOOL planar = io->mNumberBuffers > 1; UInt32 bch = planar ? io->mNumberBuffers : (io->mBuffers[0].mNumberChannels ? io->mBuffers[0].mNumberChannels : 1);
            UInt32 bpf = n ? io->mBuffers[0].mDataByteSize / n : 0; BOOL isF = planar ? (bpf >= 4) : (bpf >= 4u * bch); // 4 bytes/frame/chan => float32, else int16
            double ssr = AVAudioSession.sharedInstance.sampleRate; if (ssr < 4000) ssr = 48000;
            c->f.mSampleRate = ssr; c->f.mFormatID = kAudioFormatLinearPCM; c->f.mChannelsPerFrame = bch ? bch : 1; c->f.mFramesPerPacket = 1;
            c->f.mBitsPerChannel = isF ? 32 : 16; c->f.mFormatFlags = isF ? (kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked) : (kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked);
            if (planar) c->f.mFormatFlags |= kAudioFormatFlagIsNonInterleaved;
            UInt32 bytes = isF ? 4 : 2; c->f.mBytesPerFrame = planar ? bytes : bytes * c->f.mChannelsPerFrame; c->f.mBytesPerPacket = c->f.mBytesPerFrame;
        }
        c->have = 1;
    }
    if (fl && (*fl & kAudioUnitRenderAction_OutputIsSilence)) return r;
    RYRecPlayTap(&c->f, n, io); return r;
}
static OSStatus (*orig_ausetprop)(AudioUnit, AudioUnitPropertyID, AudioUnitScope, AudioUnitElement, const void *, UInt32);
static OSStatus RYAUSetProp(AudioUnit u, AudioUnitPropertyID pid, AudioUnitScope sc, AudioUnitElement el, const void *d, UInt32 sz) {
    if (pid == kAudioUnitProperty_SetRenderCallback && sc == kAudioUnitScope_Input && el == 0 && d && sz >= sizeof(AURenderCallbackStruct) && orig_ausetprop) {
        const AURenderCallbackStruct *cb = (const AURenderCallbackStruct *)d;
        if (cb->inputProc && cb->inputProc != RYPlayCB) {
            RYPbCtx *c = (RYPbCtx *)calloc(1, sizeof(RYPbCtx)); c->proc = cb->inputProc; c->ref = cb->inputProcRefCon; c->au = u;
            AURenderCallbackStruct n; n.inputProc = RYPlayCB; n.inputProcRefCon = c; gRecHook++;
            return orig_ausetprop(u, pid, sc, el, &n, sizeof n);
        }
    }
    return orig_ausetprop ? orig_ausetprop(u, pid, sc, el, d, sz) : -50;
}
// writer + mixer
static NSObject *gRecLock; static AVAssetWriter *gRecWriter; static AVAssetWriterInput *gRecVIn, *gRecAIn; static NSURL *gRecURL; static dispatch_source_t gRecTimer;
static double gRecBase, gRecT0; static long long gRecDone;
static void RYRecAppendPCM(const int16_t *pcm, int frames, CMTime pts) {
    AudioStreamBasicDescription a; memset(&a, 0, sizeof a); a.mSampleRate = 48000; a.mFormatID = kAudioFormatLinearPCM; a.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    a.mChannelsPerFrame = 1; a.mBitsPerChannel = 16; a.mBytesPerFrame = 2; a.mFramesPerPacket = 1; a.mBytesPerPacket = 2;
    CMAudioFormatDescriptionRef fd = NULL; if (CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &a, 0, NULL, 0, NULL, NULL, &fd) != noErr) return;
    size_t len = (size_t)frames * 2; CMBlockBufferRef bb = NULL;
    if (CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, NULL, len, kCFAllocatorDefault, NULL, 0, len, kCMBlockBufferAssureMemoryNowFlag, &bb) == noErr && bb) {
        CMBlockBufferReplaceDataBytes(pcm, bb, 0, len);
        CMSampleBufferRef sb = NULL;
        if (CMAudioSampleBufferCreateWithPacketDescriptions(kCFAllocatorDefault, bb, true, NULL, NULL, fd, frames, pts, NULL, &sb) == noErr && sb) {
            if (gRecAIn.isReadyForMoreMediaData) { [gRecAIn appendSampleBuffer:sb]; gRecAudN += frames; }
            CFRelease(sb);
        }
        CFRelease(bb);
    }
    CFRelease(fd);
}
static void RYRecTick(void) {
    @synchronized (gRecLock) {
        if (!gRecOn || !gRecWriter || gRecWriter.status != AVAssetWriterStatusWriting || !gRecAIn) return;
        long long target = (long long)((CACurrentMediaTime() - gRecT0 - 0.1) * 48000.0), want = target - gRecDone;
        if (want < 480) return; if (want > 4800) want = 4800;
        static int16_t out[4800]; unsigned rm = gRecRM, rp = gRecRP, wm = gRecWM, wp = gRecWP;
        if (wm - rm > 19200) rm = wm - 4800; if (wp - rp > 19200) rp = wp - 4800;                    // fell behind: jump to ~100 ms
        for (int i = 0; i < (int)want; i++) {
            float v = 0; if (rm != wm) { v += gRecRingM[rm & (RYREC_N - 1)]; rm++; } if (rp != wp) { v += gRecRingP[rp & (RYREC_N - 1)]; rp++; }
            v = v > 1.f ? 1.f : (v < -1.f ? -1.f : v); out[i] = (int16_t)(v * 32767.f);
        }
        gRecRM = rm; gRecRP = rp;
        RYRecAppendPCM(out, (int)want, CMTimeMakeWithSeconds(gRecBase + (double)gRecDone / 48000.0, 48000)); gRecDone += want;
    }
}
static void RYRecSetup(CMSampleBufferRef sb) {   // called with gRecLock held, on the first video frame
    CMVideoFormatDescriptionRef vf = (CMVideoFormatDescriptionRef)CMSampleBufferGetFormatDescription(sb); if (!vf) return;
    CMVideoDimensions dm = CMVideoFormatDescriptionGetDimensions(vf); if (dm.width < 16 || dm.height < 16) return;
    NSError *e = nil; AVAssetWriter *w = [[AVAssetWriter alloc] initWithURL:gRecURL fileType:AVFileTypeMPEG4 error:&e]; if (!w) return;
    double px = (double)dm.width * dm.height, br = px * 3.0 > 8e6 ? 8e6 : px * 3.0;
    AVAssetWriterInput *vi = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{AVVideoCodecKey: AVVideoCodecTypeH264, AVVideoWidthKey: @(dm.width), AVVideoHeightKey: @(dm.height), AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(br), AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel}}];
    vi.expectsMediaDataInRealTime = YES;
    AVAssetWriterInput *ai = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:@{AVFormatIDKey: @(kAudioFormatMPEG4AAC), AVSampleRateKey: @48000, AVNumberOfChannelsKey: @1, AVEncoderBitRateKey: @96000}];
    ai.expectsMediaDataInRealTime = YES;
    if (![w canAddInput:vi] || ![w canAddInput:ai]) return; [w addInput:vi]; [w addInput:ai];
    if (![w startWriting]) return;
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sb); [w startSessionAtSourceTime:pts];
    gRecWriter = w; gRecVIn = vi; gRecAIn = ai; gRecBase = CMTimeGetSeconds(pts); gRecT0 = CACurrentMediaTime(); gRecDone = 0; gRecRM = gRecWM; gRecRP = gRecWP; gRsM.pos = gRsP.pos = 0;
    gRecTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_queue_create("8ubah.rec", DISPATCH_QUEUE_SERIAL));
    dispatch_source_set_timer(gRecTimer, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), 20 * NSEC_PER_MSEC, 2 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(gRecTimer, ^{ RYRecTick(); }); dispatch_resume(gRecTimer);
}
static id RYRecorder(void) {
    dlopen("/System/Library/Frameworks/ReplayKit.framework/ReplayKit", RTLD_LAZY);
    Class c = NSClassFromString(@"RPScreenRecorder"); return c ? ((id (*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(@"sharedRecorder")) : nil;
}
static void RYRecStart(void (^done)(NSString *err)) {
    if (gRecOn) { done(nil); return; }
    id rec = RYRecorder(); if (!rec) { done(T(@"التسجيل غير متاح", @"Recording unavailable")); return; }
    static dispatch_once_t once; dispatch_once(&once, ^{ gRecLock = [NSObject new]; });
    NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"yyyyMMdd-HHmmss";
    @synchronized (gRecLock) { gRecURL = [NSURL fileURLWithPath:[RYDir(@"rec") stringByAppendingPathComponent:[NSString stringWithFormat:@"rec-%@.mp4", [df stringFromDate:NSDate.date]]]]; gRecWriter = nil; gRecVIn = nil; gRecAIn = nil; }
    gRecMicN = gRecPlayN = gRecVidN = gRecAudN = 0; gRecStart = CACurrentMediaTime(); gRecOn = 1;
    void (^handler)(CMSampleBufferRef, NSInteger, NSError *) = ^(CMSampleBufferRef sb, NSInteger type, NSError *err) {
        if (type != 1 || !gRecOn || !sb || !CMSampleBufferDataIsReady(sb)) return;   // 1 = video; ReplayKit's own audio is ignored (it has none of the call)
        @synchronized (gRecLock) {
            if (!gRecWriter) RYRecSetup(sb);
            if (gRecWriter && gRecWriter.status == AVAssetWriterStatusWriting && gRecVIn.isReadyForMoreMediaData) { [gRecVIn appendSampleBuffer:sb]; gRecVidN++; }
        }
    };
    void (^comp)(NSError *) = ^(NSError *e) { if (e) { gRecOn = 0; dispatch_async(dispatch_get_main_queue(), ^{ done(T(@"ما قدرت أبدأ التسجيل", @"Could not start recording")); }); } else dispatch_async(dispatch_get_main_queue(), ^{ done(nil); }); };
    ((void (*)(id, SEL, id, id))objc_msgSend)(rec, NSSelectorFromString(@"startCaptureWithHandler:completionHandler:"), handler, comp);
}
static void RYRecStop(void (^done)(NSURL *url, NSString *err)) {
    if (!gRecOn) { done(nil, nil); return; }
    gRecOn = 0; id rec = RYRecorder();
    void (^fin)(void) = ^{
        AVAssetWriter *w; NSURL *u;
        @synchronized (gRecLock) {
            if (gRecTimer) { dispatch_source_cancel(gRecTimer); gRecTimer = nil; }
            w = gRecWriter; u = gRecURL; gRecWriter = nil;
            if (w && w.status == AVAssetWriterStatusWriting) { [gRecVIn markAsFinished]; [gRecAIn markAsFinished]; }
            gRecVIn = nil; gRecAIn = nil;
        }
        if (!w || w.status != AVAssetWriterStatusWriting) { dispatch_async(dispatch_get_main_queue(), ^{ done(nil, T(@"ما فيه فيديو", @"No video was captured")); }); return; }
        [w finishWritingWithCompletionHandler:^{ dispatch_async(dispatch_get_main_queue(), ^{ if (w.status == AVAssetWriterStatusCompleted) done(u, nil); else done(nil, T(@"فشل الحفظ", @"Save failed")); }); }];
    };
    if (rec) ((void (*)(id, SEL, id))objc_msgSend)(rec, NSSelectorFromString(@"stopCaptureWithHandler:"), ^(NSError *e) { fin(); }); else fin();
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
            if (gRevSong > 0) RYCavern(t + done, n, sr, &gSongVS, gRevSong); // songs get the Haunted Cavern echo at their own amount
            if (gStMon && !gMonOn) RYMonPush(t + done, n, sr); // I hear the file itself, at the same moment the room does (when "Hear my voice" is on, the mixed signal below is monitored instead)
            for (int i = 0; i < n; i++) { float v = t[done + i] + tmp[i] * 0.55f; t[done + i] = v > 1.f ? 1.f : (v < -1.f ? -1.f : v); }
            done += n;
        }
    } else if (gMicMute) { memset(t, 0, (size_t)c * sizeof(float)); } // no Stereo playing: muting the mic just means silence
    else if (RY_FX_ON) RYVoiceBlock(t, c, sr, s);
    if (gMonOn) RYMonFeed(t, c, sr);
    if (gRecOn) RYRecMic(t, c, sr);
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
    if (!RY_FX_ON && !gMonOn && !gRecOn) return r;
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
        if (!RY_FX_ON && !gMonOn && !gRecOn) return r;
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
        w = [^(AVAudioPCMBuffer *b, AVAudioTime *t) { gMicCallsT++; if (RY_FX_ON || gMonOn || gRecOn) RYTapProcess(b); blk(b, t); } copy];
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
    if (!gIsoVP || !u) return;
    AudioComponent comp = AudioComponentInstanceGetComponent(u); AudioComponentDescription cd; memset(&cd, 0, sizeof cd);
    if (!comp || AudioComponentGetDescription(comp, &cd) != noErr || cd.componentSubType != kAudioUnitSubType_VoiceProcessingIO) return;
    UInt32 one = 1, zero = 0;
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
    return;   // session-mode / RTC-constraint / AVAudioEngine hooks are not installed any more: the join-voice button stopped working with them
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
    gMicDist = [CF(@"micDist", @NO) boolValue]; gMicMute = 0; // never restore "on": always starts unmuted so it's never silently stuck
    gRevMic = [CF(@"revMic", @0) intValue]; gRevSong = [CF(@"revSong", @0) intValue];
    gStLoop = [CF(@"stLoop", @NO) boolValue]; gStVol = [CF(@"stVol", @1.0) floatValue]; gStMon = [CF(@"stMon", @YES) boolValue];
    for (int i = 0; i < RV_N; i++) gRv[i] = kRvDef[i]; // echo voicing is fixed (Haunted Cavern); only the amount is user-set
    gDistGain = powf(10.f, [CF(@"distDb", @60) floatValue] / 20.f); gDistOut = powf(10.f, [CF(@"distOutDb", @-3) floatValue] / 20.f); gDistGate = powf(10.f, [CF(@"distGateDb", @-55) floatValue] / 20.f);
    gIsoOn = [CF(@"isoOn", @YES) boolValue]; gIsoVP = gIsoOn ? 1 : 0; gIsoSess = gIsoRTC = 0; // switch in the Mic tab. Session-mode override + RTC constraints are never used (they can stop a voice join)
    gEqOn = [CF(@"eqOn", @NO) boolValue]; gEqPre = [CF(@"eqPre", @0) floatValue];
    { NSArray *ef = CF(@"eqF", nil), *eg = CF(@"eqG", nil), *eq = CF(@"eqQ", nil), *et = CF(@"eqT", nil);
      BOOL ok = [CF(@"eqCfgVer", @0) intValue] == 2 && [ef isKindOfClass:NSArray.class] && [eg isKindOfClass:NSArray.class] && ef.count == RYEQ_N && eg.count == RYEQ_N;   // older saved curves (version < 2) restart from Flat
      BOOL okq = ok && [eq isKindOfClass:NSArray.class] && eq.count == RYEQ_N && [et isKindOfClass:NSArray.class] && et.count == RYEQ_N;
      for (int i = 0; i < RYEQ_N; i++) { gEqF[i] = ok ? [ef[i] floatValue] : kEqF[i]; gEqG[i] = ok ? [eg[i] floatValue] : kEqG[i]; gEqQ[i] = okq ? [eq[i] floatValue] : 1.1f; gEqT[i] = okq ? [et[i] intValue] : 0; }
      if (!ok) gEqOn = 0;
      gEqVer++; }
    gNcOn = [CF(@"ncOn", @NO) boolValue]; gNcAmt = [CF(@"ncAmt", @0.2) floatValue]; gNrBgOn = [CF(@"nrBgOn", @NO) boolValue]; gNrBg = [CF(@"nrBg", @0) floatValue];
    gNrImpOn = [CF(@"nrImpOn", @NO) boolValue]; gNrImp = [CF(@"nrImp", @0) floatValue]; gGateOn = [CF(@"gateOn", @NO) boolValue]; gGateThr = [CF(@"gateThr", @-56.3) floatValue];
    gGateAuto = [CF(@"gateAuto", @NO) boolValue]; gCompOn = [CF(@"compOn", @NO) boolValue]; gCompLvl = [CF(@"compLvl", @1) floatValue];
}
static void RYEqSave(void) {
    NSMutableArray *f = [NSMutableArray new], *g = [NSMutableArray new], *q = [NSMutableArray new], *t = [NSMutableArray new];
    for (int i = 0; i < RYEQ_N; i++) { [f addObject:@(gEqF[i])]; [g addObject:@(gEqG[i])]; [q addObject:@(gEqQ[i])]; [t addObject:@(gEqT[i])]; }
    CS(@"eqF", f); CS(@"eqG", g); CS(@"eqQ", q); CS(@"eqT", t); CS(@"eqPre", @(gEqPre)); CS(@"eqCfgVer", @2);
}
static void RYEqSetOn(BOOL on) { gEqOn = on ? 1 : 0; gEqVer++; CS(@"eqOn", @(on)); }
// presets: built-in + the ones saved by the owner (CF "eqUser": array of {n, f[], g[], q[], t[]}); a preset is always handled as such a dictionary
static NSDictionary *RYEqDictFrom(const char *name, const float *f, const float *g, const float *q, const int *t) {
    NSMutableArray *F = [NSMutableArray new], *G = [NSMutableArray new], *Q = [NSMutableArray new], *T_ = [NSMutableArray new];
    for (int i = 0; i < RYEQ_N; i++) { [F addObject:@(f[i])]; [G addObject:@(g[i])]; [Q addObject:@(q[i])]; [T_ addObject:@(t[i])]; }
    return @{@"n": [NSString stringWithUTF8String:name], @"f": F, @"g": G, @"q": Q, @"t": T_};
}
static NSArray<NSDictionary *> *RYEqAllPresets(void) {
    NSMutableArray *a = [NSMutableArray new];
    for (int i = 0; i < RY_NEQP; i++) [a addObject:RYEqDictFrom(kEqPresets[i].name, kEqPresets[i].f, kEqPresets[i].g, kEqPresets[i].q, kEqPresets[i].t)];
    NSArray *u = CF(@"eqUser", nil); if ([u isKindOfClass:NSArray.class]) for (id d in u) if ([d isKindOfClass:NSDictionary.class] && [d[@"n"] isKindOfClass:NSString.class]) [a addObject:d];
    return a;
}
static BOOL RYEqIsBuiltin(NSString *n) { for (int i = 0; i < RY_NEQP; i++) if ([n isEqualToString:[NSString stringWithUTF8String:kEqPresets[i].name]]) return YES; return NO; }
static void RYEqApplyDict(NSDictionary *d) {
    NSArray *f = d[@"f"], *g = d[@"g"], *q = d[@"q"], *t = d[@"t"];
    if (![f isKindOfClass:NSArray.class] || ![g isKindOfClass:NSArray.class] || f.count != RYEQ_N || g.count != RYEQ_N) return;
    for (int i = 0; i < RYEQ_N; i++) {
        gEqF[i] = [f[i] floatValue]; gEqG[i] = [g[i] floatValue];
        gEqQ[i] = ([q isKindOfClass:NSArray.class] && q.count == RYEQ_N) ? [q[i] floatValue] : 1.1f; gEqT[i] = ([t isKindOfClass:NSArray.class] && t.count == RYEQ_N) ? [t[i] intValue] : 0;
    }
    gEqPre = 0; gEqOn = 1; gEqVer++; CS(@"eqOn", @YES); CS(@"eqName", d[@"n"] ?: @"");
    RYEqSave();
}
static void RYEqReset(void) { RYEqApplyDict(RYEqAllPresets().firstObject); gEqOn = 0; CS(@"eqOn", @NO); }
static void RYEqSaveUser(NSString *name) {
    if (!name.length) return;
    NSMutableArray *F = [NSMutableArray new], *G = [NSMutableArray new], *Q = [NSMutableArray new], *T_ = [NSMutableArray new];
    for (int i = 0; i < RYEQ_N; i++) { [F addObject:@(gEqF[i])]; [G addObject:@(gEqG[i])]; [Q addObject:@(gEqQ[i])]; [T_ addObject:@(gEqT[i])]; }
    NSMutableArray *u = [NSMutableArray new]; NSArray *old = CF(@"eqUser", nil);
    if ([old isKindOfClass:NSArray.class]) for (NSDictionary *d in old) if (![d[@"n"] isEqual:name]) [u addObject:d];
    [u addObject:@{@"n": name, @"f": F, @"g": G, @"q": Q, @"t": T_}]; CS(@"eqUser", u); CS(@"eqName", name);
}
static void RYEqDeleteUser(NSString *name) {
    NSMutableArray *u = [NSMutableArray new]; NSArray *old = CF(@"eqUser", nil);
    if ([old isKindOfClass:NSArray.class]) for (NSDictionary *d in old) if (![d[@"n"] isEqual:name]) [u addObject:d];
    CS(@"eqUser", u);
    NSMutableArray *fv = [NSMutableArray new]; NSArray *fo = CF(@"eqFav", nil); if ([fo isKindOfClass:NSArray.class]) for (NSString *n in fo) if (![n isEqual:name]) [fv addObject:n]; CS(@"eqFav", fv);
}
// ---- Sonar (SteelSeries) import. The link is "...import?url=<base64 of https://community-configs.steelseriescdn.com/v1/<id>>" (or that address itself). The config JSON is read tolerantly:
// the biggest group of sibling objects that carry a frequency and a gain is taken as the equalizer (Q and shelf types are read when present).
static NSString *RYB64Dec(NSString *s) {
    s = [[s stringByReplacingOccurrencesOfString:@"-" withString:@"+"] stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (s.length % 4) s = [s stringByAppendingString:@"="];
    NSData *d = [[NSData alloc] initWithBase64EncodedString:s options:0]; return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
}
static NSDictionary *RYSonarBand(id n) {
    if (![n isKindOfClass:NSDictionary.class]) return nil;
    NSNumber *f = nil, *g = nil, *q = nil; NSString *ty = nil; BOOL en = YES;
    for (NSString *k0 in (NSDictionary *)n) {
        NSString *k = k0.lowercaseString; id v = ((NSDictionary *)n)[k0];
        if ([v isKindOfClass:NSNumber.class]) {
            if ([k isEqualToString:@"frequency"] || [k isEqualToString:@"freq"] || [k isEqualToString:@"hz"] || [k isEqualToString:@"f"]) f = v;
            else if ([k isEqualToString:@"gain"] || [k isEqualToString:@"gaindb"] || [k isEqualToString:@"gain_db"]) g = v;
            else if ([k isEqualToString:@"q"] || [k isEqualToString:@"qfactor"] || [k isEqualToString:@"q_factor"] || [k isEqualToString:@"bandwidth"]) q = v;
            else if ([k isEqualToString:@"enabled"] || [k isEqualToString:@"enable"] || [k isEqualToString:@"active"]) en = [v boolValue];
        } else if ([v isKindOfClass:NSString.class] && ([k isEqualToString:@"type"] || [k isEqualToString:@"filtertype"] || [k isEqualToString:@"filter_type"])) ty = ((NSString *)v).lowercaseString;
    }
    if (!f || !g) return nil;
    int t = 0; if ([ty containsString:@"low"] && [ty containsString:@"shelf"]) t = 1; else if ([ty containsString:@"high"] && [ty containsString:@"shelf"]) t = 2;
    return @{@"f": f, @"g": en ? g : @0, @"q": q && q.floatValue > 0.1 ? q : @1.1, @"t": @(t)};
}
static void RYSonarWalk(id n, NSMutableArray *groups) {
    NSArray *kids = [n isKindOfClass:NSDictionary.class] ? [(NSDictionary *)n allValues] : ([n isKindOfClass:NSArray.class] ? n : nil);
    if (!kids) return;
    NSMutableArray *g = [NSMutableArray new]; for (id k in kids) { NSDictionary *b = RYSonarBand(k); if (b) [g addObject:b]; }
    if (g.count) [groups addObject:g];
    if ([n isKindOfClass:NSDictionary.class]) {   // parallel arrays: {"frequencies":[..], "gains":[..]}
        NSArray *fa = nil, *ga = nil, *qa = nil;
        for (NSString *k0 in (NSDictionary *)n) { NSString *k = k0.lowercaseString; id v = ((NSDictionary *)n)[k0]; if (![v isKindOfClass:NSArray.class] || ![[(NSArray *)v firstObject] isKindOfClass:NSNumber.class]) continue;
            if ([k hasPrefix:@"freq"]) fa = v; else if ([k hasPrefix:@"gain"]) ga = v; else if ([k isEqualToString:@"q"] || [k hasPrefix:@"qf"] || [k hasPrefix:@"qs"]) qa = v; }
        if (fa && ga && fa.count == ga.count) { NSMutableArray *pg = [NSMutableArray new]; for (NSUInteger i = 0; i < fa.count; i++) [pg addObject:@{@"f": fa[i], @"g": ga[i], @"q": (qa && qa.count == fa.count) ? qa[i] : @1.1, @"t": @0}]; [groups addObject:pg]; }
    }
    for (id k in kids) RYSonarWalk(k, groups);
}
static NSDictionary *RYSonarParse(id root, NSString *fallbackName) {
    NSMutableArray *groups = [NSMutableArray new]; RYSonarWalk(root, groups);
    NSArray *best = nil; for (NSArray *g in groups) if (!best || g.count > best.count) best = g;
    if (!best.count) return nil;
    NSMutableArray *bs = [best mutableCopy];
    while (bs.count > RYEQ_N) { NSUInteger wi = 0; float w = 1e9f; for (NSUInteger i = 0; i < bs.count; i++) { float a = fabsf([bs[i][@"g"] floatValue]); if (a < w) { w = a; wi = i; } } [bs removeObjectAtIndex:wi]; }
    [bs sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) { return [x[@"f"] compare:y[@"f"]]; }];
    NSMutableArray *F = [NSMutableArray new], *G = [NSMutableArray new], *Q = [NSMutableArray new], *T_ = [NSMutableArray new];
    for (NSDictionary *b in bs) { float f = fmaxf(20.f, fminf(20000.f, [b[@"f"] floatValue])); [F addObject:@(f)]; [G addObject:@(fmaxf(-12.f, fminf(12.f, [b[@"g"] floatValue])))]; [Q addObject:b[@"q"]]; [T_ addObject:b[@"t"]]; }
    for (int i = (int)F.count; i < RYEQ_N; i++) {   // fewer than 10 bands: the rest sit flat in the gaps
        float f = kEqF[i]; [F addObject:@(f)]; [G addObject:@0]; [Q addObject:@1.1]; [T_ addObject:@0];
    }
    NSMutableArray *idx = [NSMutableArray new]; for (int i = 0; i < RYEQ_N; i++) [idx addObject:@(i)];
    [idx sortUsingComparator:^NSComparisonResult(NSNumber *x, NSNumber *y) { return [F[x.intValue] compare:F[y.intValue]]; }];
    NSMutableArray *F2 = [NSMutableArray new], *G2 = [NSMutableArray new], *Q2 = [NSMutableArray new], *T2 = [NSMutableArray new];
    for (NSNumber *i in idx) { [F2 addObject:F[i.intValue]]; [G2 addObject:G[i.intValue]]; [Q2 addObject:Q[i.intValue]]; [T2 addObject:T_[i.intValue]]; }
    NSString *nm = [root isKindOfClass:NSDictionary.class] && [root[@"name"] isKindOfClass:NSString.class] && [root[@"name"] length] ? root[@"name"] : fallbackName;
    return @{@"n": nm, @"f": F2, @"g": G2, @"q": Q2, @"t": T2};
}
static void RYEqImportLink(NSString *link, NSString *forcedName, void (^done)(NSString *err, NSString *name)) {
    NSString *t = [link stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet], *target = nil;
    NSURLComponents *uc = [NSURLComponents componentsWithString:t];
    for (NSURLQueryItem *qi in uc.queryItems) if ([qi.name isEqualToString:@"url"] && qi.value.length) { target = qi.value; if (![target hasPrefix:@"http"]) target = RYB64Dec(target); }
    if (!target && [t hasPrefix:@"http"]) target = t;
    if (!target && t.length > 20 && ![t containsString:@" "]) target = RYB64Dec(t);
    NSURL *u = target ? [NSURL URLWithString:target] : nil;
    if (!u || ![u.scheme isEqualToString:@"https"] || ![u.host hasSuffix:@"steelseriescdn.com"]) { done(T(@"الرابط غير صحيح", @"Invalid link"), nil); return; }
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:u completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSString *msg = nil, *nm = nil;
        if (!data.length || err) msg = T(@"تعذر تحميل الإعداد", @"Download failed");
        else {
            id j = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSDictionary *p = j ? RYSonarParse(j, T(@"استيراد", @"Imported")) : nil;
            if (!p) msg = T(@"ما لقيت إيكولايزر بالإعداد", @"No equalizer found in the config");
            else { NSString *base = forcedName.length ? forcedName : p[@"n"], *use = base; int k = 2; while (RYEqIsBuiltin(use)) use = [NSString stringWithFormat:@"%@ %d", base, k++];
                   NSMutableDictionary *m = [p mutableCopy]; m[@"n"] = use; RYEqApplyDict(m); RYEqSaveUser(use); nm = use; }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done(msg, nm); });
    }];
    [task resume];
}
static void RYMicSetOn(BOOL on) { gMicOn = on; CS(@"micOn", @(on)); }
static void RYMicSetDist(BOOL on) { gMicDist = on; CS(@"micDist", @(on)); }
static void RYSetRevMic(int v) { if (v < 0) v = 0; if (v > 100) v = 100; gRevMic = v; CS(@"revMic", @(v)); }
static void RYSetRevSong(int v) { if (v < 0) v = 0; if (v > 100) v = 100; gRevSong = v; CS(@"revSong", @(v)); }
static void RYMicSetMute(BOOL on) { gMicMute = on; } // not persisted on purpose (see RYInit note)
static void RYIsoPushNow(void);
static void RYMicSetIso(BOOL on) {
    gIsoOn = on ? 1 : 0; gIsoVP = gIsoOn; gIsoSess = gIsoRTC = 0; CS(@"isoOn", @(on));
    if (on) RYIsoPushNow();
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
        gMicOn, gMicPreset, gMicSemi, gMicMode, gMicEcho, gMicGain, gMicDist, gRevMic, gMonOn, gMicCallsA, gMicRebound, gMicCallsU, gMicWrapped, gMicCallsT, gMicTapInst, (long long)gMicProc, (long long)gMicSkip, gMicFmt, gMicLast, gMicHWRate, gIsoSess, gIsoSessN, gIsoVP, gIsoVPN, gIsoVPFail, gIsoEngN, gIsoRTC, gIsoRTCN];
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
                else if (strcmp(nm, "_AudioUnitSetProperty") == 0) { rep = (void *)RYAUSetProp; save = (void **)&orig_ausetprop; }
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
static NSDictionary *RYScrubOpts(NSDictionary *o, BOOL addMissing) {
    NSMutableDictionary *m = [o mutableCopy];
    for (NSString *k in @[@"echoCancellation", @"noiseSuppression", @"noiseCancellation", @"noiseCancellationDuringProcessing", @"automaticGainControl", @"builtInEchoCancellation", @"vadUseKrisp"]) if (addMissing || m[k]) m[k] = @NO;
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
        gTOCalls++; n = RYScrubOpts(o, NO);
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
    if (has && gIsoOn) { gTOCalls++; n = RYScrubOpts(o, NO); snprintf(gTOLast, sizeof gTOLast, "%s", [[NSString stringWithFormat:@"conn %lu: %@", (unsigned long)cid, o] UTF8String] ?: "-"); }
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
// Fake Defen needs three facts from the voice engine itself: your user id (at join), and your real self-mute / self-deafen. Pass-through only.
static void RYFDOnCreate(id a, id b);
static void RYFDOnSelf(BOOL deaf, BOOL v);
static void (*orig_createVC)(id, SEL, NSUInteger, id, id, id);
static void RYCreateVC(id self, SEL _cmd, NSUInteger i, id a, id b, id cb) { @try { RYFDOnCreate(a, b); } @catch (__unused id e) {} if (orig_createVC) orig_createVC(self, _cmd, i, a, b, cb); }
static void (*orig_selfMute)(id, SEL, NSUInteger, BOOL);
static void RYSelfMute(id self, SEL _cmd, NSUInteger i, BOOL v) { RYFDOnSelf(NO, v); if (orig_selfMute) orig_selfMute(self, _cmd, i, v); }
static void (*orig_selfDeaf)(id, SEL, NSUInteger, BOOL);
static void RYSelfDeaf(id self, SEL _cmd, NSUInteger i, BOOL v) { RYFDOnSelf(YES, v); if (orig_selfDeaf) orig_selfDeaf(self, _cmd, i, v); }
static void RYInstallVoiceHook2(void) {
    Class c = NSClassFromString(@"DCDVoiceEngine"); if (!c) return;
    static BOOL a, b;
    if (!a) { Method m = class_getInstanceMethod(c, NSSelectorFromString(@"connectionInstanceSetTransportOptions:options:")); if (m && method_getNumberOfArguments(m) == 4) { orig_connTO = (void *)method_getImplementation(m); method_setImplementation(m, (IMP)RYConnTO); a = YES; } }
    static BOOL f1, f2, f3;
    if (!f1) { Method m = class_getInstanceMethod(c, NSSelectorFromString(@"createVoiceConnectionWithOptions:withUserId:withConnectionOptions:withCallback:")); if (m && method_getNumberOfArguments(m) == 6) { orig_createVC = (void *)method_getImplementation(m); method_setImplementation(m, (IMP)RYCreateVC); f1 = YES; } }
    if (!f2) { Method m = class_getInstanceMethod(c, NSSelectorFromString(@"connectionInstanceSetSelfMute:muted:")); if (m && method_getNumberOfArguments(m) == 4) { orig_selfMute = (void *)method_getImplementation(m); method_setImplementation(m, (IMP)RYSelfMute); f2 = YES; } }
    if (!f3) { Method m = class_getInstanceMethod(c, NSSelectorFromString(@"connectionInstanceSetSelfDeafen:deafened:")); if (m && method_getNumberOfArguments(m) == 4) { orig_selfDeaf = (void *)method_getImplementation(m); method_setImplementation(m, (IMP)RYSelfDeaf); f3 = YES; } }
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
// Message text colour: ONLY the colour the owner picked ("custom"). No automatic contrast, nothing is read from the wallpaper or from other labels:
// every other state (default, off, or an old saved "auto") returns nil = the app's own colours stay untouched.
static UIColor *RYTextTarget(void) {
    if (![CF(@"txtMode", @"off") isEqual:@"custom"]) return nil;
    return RYHex(CF(@"txtColor", @"#FFFFFF"));
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


#pragma mark - Message logger (DMs + group chats, never servers): a message someone deletes stays in the chat, in red. Always on, no switch.
// How Discord really works (read from the binary): the gateway event MESSAGE_DELETE arrives over RCTWebSocketModule (already decompressed
// text, "encoding=json"), JS removes the message from its store, then sends the native chat a *changeset* (DCDRowUpdateModel rows with
// index + changeType). Re-inserting rows natively would shift every later index, so we stop it at the source instead: the delete event is
// renamed before JS sees it. JS, the native list and all indices stay exactly in sync; the message simply never gets removed.
// Our own deletes (REST DELETE /channels/x/messages/y seen on the HTTP handler) are let through.
static NSMutableSet<NSString *> *gLogIds;                      // ids of messages that were deleted by someone else and are kept
static NSMutableDictionary<NSString *, NSDate *> *gOwnDel;     // ids we deleted ourselves (the matching gateway event passes)
static volatile int gWsMsgs = 0, gLogSeen = 0, gLogKept = 0, gLogOwn = 0, gLogPass = 0, gLogKeptFull = 0, gLogKeptStub = 0; static char gLogLast[220] = "-";
static void (*orig_cellCfg)(id, SEL, id, id, id);
static void (*orig_wsSend)(id, SEL, NSString *, id);
#pragma mark - Fake Deafen (voice): others see you as muted+deafened; your own mic/hearing are never touched.
// Discord shows your mute/deafen badge to other people purely from the gateway's VOICE_STATE_UPDATE
// (op 4) you send out — op:4,d:{...,self_mute,self_deaf,...}. We intercept that ONE outgoing frame and
// force self_mute/self_deaf to true in it when the toggle is on. Nothing about the real voice engine
// (RTC capture/playback, the real connectionInstanceSetSelfMute:/SetSelfDeafen: calls) is touched, so you
// keep talking and hearing normally on your end the whole time.
// -[RCTWebSocketModule send:forSocketID:] takes the socket id as a DOUBLE in this app (TurboModule spec: "socketID : (double)socketID"), not as an object.
// A hook that declares it as `id` makes the compiler touch the wrong register and the real call then goes to a garbage socket (frames and heartbeats lost
// -> gateway timeout -> others see you outside the room). The argument type is read from the method itself; both layouts are supported.
static void (*orig_wsSendOut)(id, SEL, id, double);        // double layout (this app)
static void (*orig_wsSendOutO)(id, SEL, id, id);           // object layout (older React Native)
static NSString *const kFDLock = @"8ubah.fakedefen";
// Nothing here touches the app until you use it. At launch NO outgoing websocket hook exists. The only always-on part is a cheap look at the
// INCOMING gateway frames (the hook the logger already has) to learn your user id (READY) and your own voice state (VOICE_STATE_UPDATE with your id).
// The outgoing hook (rewrites your op-4 frame) is installed only while Fake Defen is ON and removed when it is switched off.
static __weak id gWsMod;            // RCTWebSocketModule
static double gGwSock = 0; static volatile BOOL gGwSockSet = NO;   // socket id of the gateway (a number)
static NSString *gFDOwnId;          // your user id (from READY)
static NSDictionary *gVSReal;       // your REAL voice state {guild_id, channel_id, self_mute, self_deaf, self_video}; nil = not in a voice channel
static volatile BOOL gFakeDef = NO, gFDPending = NO, gFDHooked = NO;   // session only; Pending = switched on outside a room, applies when you join
static volatile int gFDSeen = 0, gFDForced = 0, gFDPushed = 0;
static volatile BOOL gWsInHooked = NO, gSafeLaunch = NO;   // incoming gateway hook installed / this launch skipped the hooks (safe mode)
static BOOL RYSendArgIsObj(Method m) { char *t = method_copyArgumentType(m, 3); BOOL o = t && t[0] == '@'; if (t) free(t); return o; }
static Method RYSendMethod(void) {
    Class wc = NSClassFromString(@"RCTWebSocketModule"); if (!wc) return NULL;
    Method m = class_getInstanceMethod(wc, NSSelectorFromString(@"send:forSocketID:"));
    return (m && method_getNumberOfArguments(m) == 4) ? m : NULL;
}
static IMP RYSendOrig(void) {       // the app's own send:forSocketID: (captured before it is ever replaced)
    if (!orig_wsSendOut && !orig_wsSendOutO) {
        Method m = RYSendMethod(); IMP i = m ? method_getImplementation(m) : NULL;
        if (i) { if (RYSendArgIsObj(m)) orig_wsSendOutO = (void *)i; else orig_wsSendOut = (void *)i; }
    }
    return orig_wsSendOut ? (IMP)orig_wsSendOut : (IMP)orig_wsSendOutO;
}
static void RYSetGwSock(double sid) { @synchronized (kFDLock) { gGwSock = sid; gGwSockSet = YES; } }
static NSString *RYFakeDeafenFilter(NSString *s, BOOL hasSock, double sockId) {   // only called while the outgoing hook exists (= Fake Defen is on)
    if (!s.length || s.length > 2000 || [s rangeOfString:@"\"op\":4"].location == NSNotFound) return s;
    NSData *dt = [s dataUsingEncoding:NSUTF8StringEncoding]; if (!dt) return s;
    id j = [NSJSONSerialization JSONObjectWithData:dt options:NSJSONReadingMutableContainers error:nil];
    if (![j isKindOfClass:NSMutableDictionary.class] || [j[@"op"] integerValue] != 4) return s;
    id d = j[@"d"]; if (![d isKindOfClass:NSMutableDictionary.class]) return s;
    gFDSeen++;
    if (hasSock) RYSetGwSock(sockId);
    id ch = d[@"channel_id"];
    @synchronized (kFDLock) { gVSReal = (ch && ch != NSNull.null) ? [d copy] : nil; }                     // what the app really wants (real mute / deafen)
    if (!gFakeDef) return s;
    d[@"self_mute"] = @YES; d[@"self_deaf"] = @YES; gFDForced++;
    NSData *out = [NSJSONSerialization dataWithJSONObject:j options:0 error:nil];
    NSString *ns = out ? [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding] : nil;
    return ns ?: s;
}
static void RYFDLearn(NSString *s, double sockId) {    // heartbeat {"op":1,...} always goes over the gateway socket: that is how we learn its id
    if ([s isKindOfClass:NSString.class] && s.length < 60 && [s hasPrefix:@"{\"op\":1,"]) RYSetGwSock(sockId);
}
static void RYWsSendOutD(id self, SEL _cmd, id data, double sockId) {
    @try { gWsMod = self; RYFDLearn(data, sockId); if (gFakeDef && [data isKindOfClass:NSString.class]) data = RYFakeDeafenFilter((NSString *)data, YES, sockId); } @catch (__unused id e) {}
    if (orig_wsSendOut) orig_wsSendOut(self, _cmd, data, sockId);
}
static void RYWsSendOutO(id self, SEL _cmd, id data, id sockId) {
    @try {
        gWsMod = self; if ([sockId respondsToSelector:@selector(doubleValue)]) RYFDLearn(data, [sockId doubleValue]);
        if (gFakeDef && [data isKindOfClass:NSString.class]) { BOOL h = [sockId respondsToSelector:@selector(doubleValue)]; data = RYFakeDeafenFilter((NSString *)data, h, h ? [sockId doubleValue] : 0); }
    } @catch (__unused id e) {}
    if (orig_wsSendOutO) orig_wsSendOutO(self, _cmd, data, sockId);
}
static void RYFDHook(BOOL on) {     // install / remove the outgoing hook
    Method m = RYSendMethod(); if (!m) return;
    if (on && !gFDHooked) { if (!RYSendOrig()) return; method_setImplementation(m, RYSendArgIsObj(m) ? (IMP)RYWsSendOutO : (IMP)RYWsSendOutD); gFDHooked = YES; RYLog(@"fake defen: outgoing hook on (%s)", RYSendArgIsObj(m) ? "object id" : "double id"); }
    else if (!on && gFDHooked) { IMP o = orig_wsSendOut ? (IMP)orig_wsSendOut : (IMP)orig_wsSendOutO; if (o) method_setImplementation(m, o); gFDHooked = NO; RYLog(@"fake defen: outgoing hook off"); }
}
static int RYFDPush(BOOL fake) {    // send one voice-state frame now: fake = muted + deafened, else your real state
    id mod; double sock; BOOL have; NSDictionary *real; @synchronized (kFDLock) { mod = gWsMod; sock = gGwSock; have = gGwSockSet; real = gVSReal; }
    IMP send = RYSendOrig();
    if (!mod || !have || !real || !send) return 0;
    NSMutableDictionary *d = [real mutableCopy];
    if (fake) { d[@"self_mute"] = @YES; d[@"self_deaf"] = @YES; }
    NSData *x = [NSJSONSerialization dataWithJSONObject:@{@"op": @4, @"d": d} options:0 error:nil];
    NSString *s = x ? [[NSString alloc] initWithData:x encoding:NSUTF8StringEncoding] : nil; if (!s) return 0;
    SEL mq = NSSelectorFromString(@"methodQueue");
    dispatch_queue_t q = [mod respondsToSelector:mq] ? ((dispatch_queue_t (*)(id, SEL))objc_msgSend)(mod, mq) : nil;
    BOOL obj = orig_wsSendOutO != NULL;
    dispatch_async(q ?: dispatch_get_main_queue(), ^{
        @try {
            SEL ss = NSSelectorFromString(@"send:forSocketID:");
            if (obj) ((void (*)(id, SEL, id, id))send)(mod, ss, s, @(sock)); else ((void (*)(id, SEL, id, double))send)(mod, ss, s, sock);
            gFDPushed++;
        } @catch (__unused id e) {}
    });
    return 1;
}
// Last small VOICE_STATE_UPDATE frame of every user, raw bytes (no JSON work for other people). Your own join echo arrives BEFORE your user id is
// known, so it is looked up here afterwards.
static NSMutableDictionary<NSString *, NSData *> *gFDVS;
static volatile BOOL gFDFlags = NO, gFDRM = NO, gFDRD = NO;   // real self mute / deafen as the voice engine last got them
static volatile int gFDFrames = 0;
static BOOL RYFDResolve(void) {     // build gVSReal (the real state) from the cached frame of your own user
    NSString *me; NSData *raw; @synchronized (kFDLock) { me = gFDOwnId; raw = me ? gFDVS[me] : nil; }
    if (!raw) return NO;
    id j = [NSJSONSerialization JSONObjectWithData:raw options:0 error:nil];
    id d = [j isKindOfClass:NSDictionary.class] ? j[@"d"] : nil; if (![d isKindOfClass:NSDictionary.class]) return NO;
    id ch = d[@"channel_id"]; if (!ch || ch == NSNull.null) return NO;
    NSMutableDictionary *v = [NSMutableDictionary new];
    v[@"guild_id"] = d[@"guild_id"] ?: NSNull.null; v[@"channel_id"] = ch; v[@"self_video"] = d[@"self_video"] ?: @NO;
    v[@"self_mute"] = gFDFlags ? @(gFDRM) : (d[@"self_mute"] ?: @NO); v[@"self_deaf"] = gFDFlags ? @(gFDRD) : (d[@"self_deaf"] ?: @NO);
    @synchronized (kFDLock) { gVSReal = v; }
    return YES;
}
static int RYFDPush(BOOL fake);
static void RYFPFrameAsync(NSData *raw);
static void RYFDKick(void) {        // switched on outside a room: as soon as the room is known, hook + fake frame
    if (!gFakeDef || !gFDPending) return;
    NSDictionary *real; @synchronized (kFDLock) { real = gVSReal; }
    if (!real && !RYFDResolve()) return;
    gFDPending = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ if (gFakeDef) { RYFDHook(YES); RYFDPush(YES); } });
}
static void RYFDOnCreate(id a, id b) {   // createVoiceConnection...: one of the object arguments is your user id (digits) or a dictionary holding it
    for (id x in @[a ?: NSNull.null, b ?: NSNull.null]) {
        NSString *s = [x isKindOfClass:NSString.class] ? x : ([x isKindOfClass:NSDictionary.class] ? [(x[@"userId"] ?: x[@"user_id"]) description] : nil);
        if (s.length >= 15 && s.length <= 22 && [s rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound) {
            @synchronized (kFDLock) { gFDOwnId = s; } break;
        }
    }
    RYFDKick();
}
static void RYFDOnSelf(BOOL deaf, BOOL v) {   // your real self mute / deafen (the engine is told by the app on every change)
    gFDFlags = YES; if (deaf) gFDRD = v; else gFDRM = v;
    if (!gFakeDef) @synchronized (kFDLock) { if (gVSReal) { NSMutableDictionary *m = [gVSReal mutableCopy]; m[deaf ? @"self_deaf" : @"self_mute"] = @(v); gVSReal = m; } }
}
// incoming gateway frame (bytes of the decompressed JSON), called from RYWsSend. Cheap: memmem only; JSON just for your own state later.
static void RYFDWatch(const char *p, size_t n, id sockId, id module) {
    if (!p || n < 30) return;
    gFDFrames++;
    if (!gFDOwnId && n > 600 && memmem(p, 600, "\"READY\"", 7)) {       // fallback id source: the "user":{...,"id":"<digits>"} object of READY
        const char *u = (const char *)memmem(p, n, "\"user\":{", 8);
        if (u) { size_t rem = n - (size_t)(u - p); if (rem > 3000) rem = 3000; const char *k = (const char *)memmem(u, rem, "\"id\":\"", 6);
            if (k) { const char *q = k + 6, *e = p + n, *z = q; while (z < e && *z >= '0' && *z <= '9') z++;
                if (z > q && z - q >= 15 && z - q <= 22 && z < e && *z == '"') @synchronized (kFDLock) { if (!gFDOwnId) gFDOwnId = [[NSString alloc] initWithBytes:q length:(NSUInteger)(z - q) encoding:NSASCIIStringEncoding]; } } }
        return;
    }
    if (n > 10000 || !memmem(p, n, "VOICE_STATE_UPDATE", 18)) return;
    const char *k = (const char *)memmem(p, n, "\"user_id\":\"", 11); if (!k) return;
    const char *q = k + 11, *e = p + n, *z = q; while (z < e && *z >= '0' && *z <= '9') z++;
    if (z == q || z - q > 24) return;
    NSString *uid = [[NSString alloc] initWithBytes:q length:(NSUInteger)(z - q) encoding:NSASCIIStringEncoding];
    NSData *raw = [NSData dataWithBytes:p length:n];
    RYFPFrameAsync(raw);                                              // Follow / Pull
    BOOL own;
    @synchronized (kFDLock) {
        if (module) gWsMod = module; if ([sockId respondsToSelector:@selector(doubleValue)]) { gGwSock = [sockId doubleValue]; gGwSockSet = YES; }     // only the gateway carries voice states
        if (!gFDVS) gFDVS = [NSMutableDictionary new];
        if (gFDVS.count > 300) [gFDVS removeAllObjects];
        gFDVS[uid] = raw;
        own = gFDOwnId && [uid isEqual:gFDOwnId];
    }
    if (!own) return;
    id j = [NSJSONSerialization JSONObjectWithData:raw options:0 error:nil];
    id d = [j isKindOfClass:NSDictionary.class] ? j[@"d"] : nil; if (![d isKindOfClass:NSDictionary.class]) return;
    id ch = d[@"channel_id"]; BOOL inRoom = ch && ch != NSNull.null;
    if (!inRoom) { @synchronized (kFDLock) { gVSReal = nil; } return; }
    if (!gFakeDef) RYFDResolve();                                      // keeps the real state fresh; while faking the echo of our own fake frame is not "real"
    else { NSDictionary *r; @synchronized (kFDLock) { r = gVSReal; } if (!r) RYFDResolve(); }
    RYFDKick();
}
// The switch. In a room: hook + one voice-state frame at once (off: your real state again, hook removed). Outside a room: only armed.
static int RYFakeDefSet(BOOL on) {
    gFakeDef = on;
    if (on) RYFDHook(YES);          // from this moment every outgoing op-4 frame is rewritten, even if the app never told us about the room (the incoming frames may not reach us)
    NSDictionary *real; @synchronized (kFDLock) { real = gVSReal; }
    if (!real && RYFDResolve()) { @synchronized (kFDLock) { real = gVSReal; } }
    if (!real) { gFDPending = on; if (!on) RYFDHook(NO); return 0; }
    gFDPending = NO;
    int r = RYFDPush(on);
    if (!on) RYFDHook(NO);
    return r;
}
static NSString *RYFakeDefStatus(void) {
    BOOL idk, inV; int cached; @synchronized (kFDLock) { idk = gFDOwnId != nil; inV = gVSReal != nil; cached = (int)gFDVS.count; }
    NSString *hk = gFDHooked ? @"✓" : (RYSendMethod() ? @"✗" : @"✗ (no send:)");
    NSString *l1 = [NSString stringWithFormat:T(@"حسابك: %@ · روم صوتي: %@ · الهوك: %@ · فريمات %d · حالات %d · معدّلة %d · مرسلة %d", @"Account: %@ · voice channel: %@ · hook: %@ · frames %d · states %d · forced %d · sent %d"), idk ? @"✓" : @"✗", inV ? @"✓" : @"✗", hk, gFDFrames, cached, gFDForced, gFDPushed];
    NSString *l2 = [NSString stringWithFormat:T(@"استقبال: %@ · رسائل %d · op4 مرّت %d · وضع آمن: %@", @"incoming hook: %@ · ws msgs %d · op4 seen %d · safe mode: %@"), gWsInHooked ? @"✓" : @"✗", gWsMsgs, gFDSeen, gSafeLaunch ? @"✓" : @"✗"];
    return [l1 stringByAppendingFormat:@"\n%@", l2];
}
static id (*orig_httpSend)(id, SEL, id, id);
#define RY_RED [UIColor colorWithRed:1.0 green:0.27 blue:0.27 alpha:1]
static UIView *RYChatHost(void);
// Only a real getter that returns an object is called. NEVER valueForKey: (it falls back to reading the ivar, and Swift ivars such as
// DCDMessageTableViewCell.viewModel have an EMPTY type encoding: reading them through KVC is a hard crash that @try cannot catch).
static id RYKV(id o, NSString *k) {
    if (!o || !k.length) return nil;
    @try {
        SEL sel = NSSelectorFromString(k); Method m = class_getInstanceMethod(object_getClass(o), sel);
        if (!m || method_getNumberOfArguments(m) != 2) return nil;
        char t[8] = {0}; method_getReturnType(m, t, sizeof t); if (t[0] != '@') return nil;
        return ((id (*)(id, SEL))objc_msgSend)(o, sel);
    } @catch (__unused id e) { return nil; }
}
static NSString *RYStr(id v) {
    if (!v || v == NSNull.null) return nil;
    NSString *s = [v isKindOfClass:NSString.class] ? v : [v description]; return s.length ? s : nil;
}
#pragma mark - Follow / Pull (voice): two buttons on a profile sheet. Session only: everything lives in memory and is gone when Discord is closed.
// Follow = you join the voice channel the person joins (one person at a time, a new Follow replaces the old one).
// Pull   = the person is moved to your voice channel, now and every time one of you changes channel (any number of people). Needs the Move Members permission.
// Voice states of everybody come from the incoming gateway frames (RYFDWatch -> RYFPFrameAsync). Joining = the same op-4 frame the app itself sends (RYFPOp4),
// moving someone = PATCH /guilds/<g>/members/<u> {channel_id} with the headers of a real request of the app (captured in RYHttpSend, never stored on disk).
static NSObject *gFPLock;
static NSString *gFPFollow, *gFPMyG, *gFPMyC, *gFPProfUid, *gApiBase;
static NSDate *gFPProfAt;
static NSMutableSet<NSString *> *gFPPull;
static NSMutableDictionary<NSString *, NSDictionary *> *gFPUser;     // uid -> {c: channel, g: guild} of its last voice state ({} = not in voice)
static NSMutableDictionary<NSString *, NSString *> *gFPNames;        // lowercase username / display name / nick -> uid
static NSMutableDictionary<NSString *, NSDate *> *gFPCool;
static NSMutableDictionary<NSString *, NSNumber *> *gFPFail;
static NSDictionary *gApiHdr;
static dispatch_queue_t gFPQ;
static volatile int gFPJoins = 0, gFPMoves = 0, gFPErr = 0, gFPFrames = 0, gFPLastStatus = 0;
static NSString *gFPSrc = @"-"; static NSInteger gFPLabelCount = 0;
static void RYFPInit(void) {
    static dispatch_once_t o; dispatch_once(&o, ^{
        gFPLock = [NSObject new]; gFPPull = [NSMutableSet new]; gFPUser = [NSMutableDictionary new]; gFPNames = [NSMutableDictionary new];
        gFPCool = [NSMutableDictionary new]; gFPFail = [NSMutableDictionary new]; gFPQ = dispatch_queue_create("8ubah.followpull", DISPATCH_QUEUE_SERIAL);
    });
}
static void RYFPHud(NSString *s) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class k = NSClassFromString(@"RYCore"); if (!k) return;
        id c = ((id (*)(id, SEL))objc_msgSend)(k, NSSelectorFromString(@"shared"));
        ((void (*)(id, SEL, id))objc_msgSend)(c, NSSelectorFromString(@"hud:"), s);
    });
}
static BOOL RYFPOK(NSString *key, double sec) {        // cooldown per action: no hammering, no ping-pong
    RYFPInit();
    @synchronized (gFPLock) {
        NSDate *d = gFPCool[key]; if (d && -[d timeIntervalSinceNow] < sec) return NO;
        gFPCool[key] = [NSDate date]; if (gFPCool.count > 500) [gFPCool removeAllObjects];
        return YES;
    }
}
// called from the HTTP hook: keeps the headers of a real REST request (for Pull) and the id of the last opened profile (for the buttons)
static void RYFPCaptureReq(NSURLRequest *r) {
    NSURL *u = r.URL; NSString *host = u.host.lowercaseString; NSString *path = u.path;
    if (!host.length || ![host hasSuffix:@"discord.com"] || ![path hasPrefix:@"/api/"]) return;
    RYFPInit();
    NSArray *pc = [path componentsSeparatedByString:@"/"];      // "", api, v9, users, <id>, profile
    NSUInteger i = [pc indexOfObject:@"users"];
    if (i != NSNotFound && i + 2 < pc.count && [pc[i + 2] isEqual:@"profile"] && [pc[i + 1] length] >= 15) @synchronized (gFPLock) { gFPProfUid = pc[i + 1]; gFPProfAt = [NSDate date]; }
    NSDictionary *h = r.allHTTPHeaderFields; NSString *auth = nil;
    for (NSString *k in h) if ([k caseInsensitiveCompare:@"authorization"] == NSOrderedSame) { auth = h[k]; break; }
    if (!auth.length) return;
    NSMutableDictionary *m = [NSMutableDictionary new];
    for (NSString *k in h) { NSString *kl = k.lowercaseString; if ([kl isEqual:@"content-length"] || [kl isEqual:@"content-type"] || [kl isEqual:@"cookie"] || [kl hasPrefix:@"if-"]) continue; m[k] = h[k]; }
    @synchronized (gFPLock) { gApiHdr = m; gApiBase = [NSString stringWithFormat:@"%@://%@/api/%@", u.scheme ?: @"https", u.host, pc.count > 2 ? pc[2] : @"v9"]; }
}
static BOOL RYFPOp4(NSString *g, NSString *c) {         // same frame the app sends when you click another voice channel
    id mod; double sock; BOOL have; NSDictionary *real; @synchronized (kFDLock) { mod = gWsMod; sock = gGwSock; have = gGwSockSet; real = gVSReal; }
    IMP send = RYSendOrig(); if (!mod || !have || !send) return NO;
    BOOL mu = real ? [real[@"self_mute"] boolValue] : gFDRM, df = real ? [real[@"self_deaf"] boolValue] : gFDRD;
    if (gFakeDef) { mu = YES; df = YES; }                // Fake Defean stays on while we move
    NSData *x = [NSJSONSerialization dataWithJSONObject:@{@"op": @4, @"d": @{@"guild_id": g, @"channel_id": c, @"self_mute": @(mu), @"self_deaf": @(df), @"self_video": @NO}} options:0 error:nil];
    NSString *s = x ? [[NSString alloc] initWithData:x encoding:NSUTF8StringEncoding] : nil; if (!s) return NO;
    SEL mq = NSSelectorFromString(@"methodQueue");
    dispatch_queue_t q = [mod respondsToSelector:mq] ? ((dispatch_queue_t (*)(id, SEL))objc_msgSend)(mod, mq) : nil;
    BOOL obj = orig_wsSendOutO != NULL;
    dispatch_async(q ?: dispatch_get_main_queue(), ^{
        @try {
            SEL ss = NSSelectorFromString(@"send:forSocketID:");
            if (obj) ((void (*)(id, SEL, id, id))send)(mod, ss, s, @(sock)); else ((void (*)(id, SEL, id, double))send)(mod, ss, s, sock);
        } @catch (__unused id e) {}
    });
    @synchronized (kFDLock) { if (gVSReal) { NSMutableDictionary *n = [gVSReal mutableCopy]; n[@"guild_id"] = g; n[@"channel_id"] = c; gVSReal = n; } }
    return YES;
}
static void RYFPOpenLink(NSString *g, NSString *c) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *u = [NSURL URLWithString:[NSString stringWithFormat:@"discord://discord.com/channels/%@/%@", g, c]];
        if (u) [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
    });
}
static void RYFPJoin(NSString *g, NSString *c) {
    NSString *myC; @synchronized (gFPLock) { myC = gFPMyC; }
    if (myC.length && RYFPOp4(g, c)) {                   // already in a voice channel: the server just moves us
        gFPJoins++;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSString *now, *fol; @synchronized (gFPLock) { now = gFPMyC; fol = gFPFollow; }
            if (fol && ![now isEqual:c]) RYFPOpenLink(g, c);   // no echo of our move: open the channel the normal way
        });
    } else { gFPJoins++; RYFPOpenLink(g, c); }
}
static void RYFPMove(NSString *uid, NSString *g, NSString *c) {
    NSDictionary *h; NSString *base; @synchronized (gFPLock) { h = gApiHdr; base = gApiBase; }
    if (!h || !base) { RYFPHud(T(@"افتح أي دردشة مرة وحدة وجرّب", @"Open any chat once, then try again")); return; }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/guilds/%@/members/%@", base, g, uid]]; if (!url) return;
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:url]; r.HTTPMethod = @"PATCH"; r.timeoutInterval = 15;
    [h enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) { [r setValue:v forHTTPHeaderField:k]; }];
    [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    r.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"channel_id": c} options:0 error:nil];
    [[NSURLSession.sharedSession dataTaskWithRequest:r completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        NSInteger st = [resp isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)resp statusCode] : 0; gFPLastStatus = (int)st;
        @synchronized (gFPLock) {
            if (st >= 200 && st < 300) { gFPMoves++; [gFPFail removeObjectForKey:uid]; return; }
            gFPErr++; int n = [gFPFail[uid] intValue] + 1; gFPFail[uid] = @(n);
            if (n >= 3 || st == 401 || st == 403) { [gFPPull removeObject:uid]; [gFPFail removeObjectForKey:uid]; RYFPHud([NSString stringWithFormat:T(@"Pull وقف (%ld)", @"Pull stopped (%ld)"), (long)st]); }
        }
    }] resume];
}
static void RYFPPullOne(NSString *p) {
    NSString *myC, *myG; NSDictionary *u; @synchronized (gFPLock) { myC = gFPMyC; myG = gFPMyG; u = gFPUser[p]; }
    NSString *c = u[@"c"], *g = u[@"g"];
    if (!myC.length || !myG.length || !c.length || ![g isEqual:myG] || [c isEqual:myC]) return;     // not in voice / other server / already with us
    if (!RYFPOK([@"m:" stringByAppendingString:p], 4)) return;
    RYFPMove(p, myG, myC);
}
static void RYFPAct(NSString *uid) {                    // something changed for uid (or for us): do what Follow / Pull ask for
    RYFPInit();
    NSString *me = gFDOwnId, *myC, *fol; NSSet *pulls; NSDictionary *u;
    @synchronized (gFPLock) { myC = gFPMyC; fol = gFPFollow; pulls = [gFPPull copy]; u = gFPUser[uid]; }
    if (me && [uid isEqual:me]) { for (NSString *p in pulls) RYFPPullOne(p); return; }            // we changed channel: everybody on Pull comes along
    NSString *c = u[@"c"], *g = u[@"g"];
    if (fol && [uid isEqual:fol] && c.length && g.length && ![c isEqual:myC] && RYFPOK([@"j:" stringByAppendingString:c], 4)) RYFPJoin(g, c);
    if ([pulls containsObject:uid]) RYFPPullOne(uid);
}
static void RYFPFrame(NSData *raw) {
    id j = [NSJSONSerialization JSONObjectWithData:raw options:0 error:nil];
    id d = [j isKindOfClass:NSDictionary.class] ? j[@"d"] : nil; if (![d isKindOfClass:NSDictionary.class]) return;
    NSString *uid = RYStr(d[@"user_id"]); if (!uid.length) return;
    NSString *ch = RYStr(d[@"channel_id"]), *gd = RYStr(d[@"guild_id"]) ?: @"";
    gFPFrames++;
    @synchronized (gFPLock) {
        if (gFPUser.count > 6000) [gFPUser removeAllObjects];
        if (gFPNames.count > 4000) [gFPNames removeAllObjects];
        gFPUser[uid] = ch.length ? @{@"c": ch, @"g": gd} : @{};
        id mem0 = d[@"member"]; NSDictionary *mem = [mem0 isKindOfClass:NSDictionary.class] ? mem0 : nil; id usr = mem[@"user"];
        for (id nm in @[mem[@"nick"] ?: NSNull.null, [usr isKindOfClass:NSDictionary.class] ? (usr[@"username"] ?: NSNull.null) : NSNull.null, [usr isKindOfClass:NSDictionary.class] ? (usr[@"global_name"] ?: NSNull.null) : NSNull.null]) {
            NSString *k = [nm isKindOfClass:NSString.class] ? [(NSString *)nm lowercaseString] : nil; if (k.length) gFPNames[k] = uid;
        }
        if (gFDOwnId && [uid isEqual:gFDOwnId]) { gFPMyC = ch.length ? ch : nil; gFPMyG = ch.length ? gd : nil; }
    }
    RYFPAct(uid);
}
static void RYFPFrameAsync(NSData *raw) {
    RYFPInit(); if (!raw.length) return;
    dispatch_async(gFPQ, ^{ @try { RYFPFrame(raw); } @catch (__unused id e) {} });
}
static void RYFPToggleFollow(NSString *uid) {
    RYFPInit(); BOOL on;
    @synchronized (gFPLock) { if ([gFPFollow isEqual:uid]) { gFPFollow = nil; on = NO; } else { gFPFollow = uid; on = YES; } }
    if (on) dispatch_async(gFPQ, ^{ @synchronized (gFPLock) { [gFPCool removeAllObjects]; } RYFPAct(uid); });
}
static void RYFPTogglePull(NSString *uid) {
    RYFPInit(); BOOL on;
    @synchronized (gFPLock) { if ([gFPPull containsObject:uid]) { [gFPPull removeObject:uid]; on = NO; } else { [gFPPull addObject:uid]; on = YES; } [gFPFail removeObjectForKey:uid]; }
    if (on) dispatch_async(gFPQ, ^{ @synchronized (gFPLock) { [gFPCool removeAllObjects]; } RYFPAct(uid); });
}
// ---- finding the profile sheet on screen (main thread). Its text comes from the accessibility labels of the React Native text views.
static NSString *RYFPText(UIView *v) {
    NSString *t = v.accessibilityLabel;
    if (![t isKindOfClass:NSString.class] || !t.length) { if ([v isKindOfClass:UILabel.class]) t = ((UILabel *)v).text; else if ([v isKindOfClass:UITextView.class]) t = ((UITextView *)v).text; else t = nil; }
    return [t isKindOfClass:NSString.class] ? t : nil;
}
static BOOL RYFPSig(NSString *t) {
    static NSSet *s; static dispatch_once_t o; dispatch_once(&o, ^{ s = [NSSet setWithArray:@[@"Member Since", @"Moderator Actions", @"About Me", @"Mutual Servers", @"Mutual Friends", @"Connections"]]; });
    return [s containsObject:t];
}
static void RYFPFindAnchor(UIView *v, int d, int *budget, UIView **hit) {
    if (*hit || !v || d > 70 || (*budget)-- <= 0 || v.hidden || v.alpha < 0.05) return;
    NSString *t = RYFPText(v); if (t.length && t.length < 40 && RYFPSig(t)) { *hit = v; return; }
    for (UIView *s in v.subviews) { RYFPFindAnchor(s, d + 1, budget, hit); if (*hit) return; }
}
static void RYFPLabels(UIView *v, int d, int *budget, NSMutableArray *out) {
    if (!v || d > 50 || (*budget)-- <= 0 || v.hidden || v.alpha < 0.05) return;
    NSString *t = RYFPText(v); if (t.length && t.length <= 80) [out addObject:t];
    for (UIView *s in v.subviews) RYFPLabels(s, d + 1, budget, out);
}
static BOOL RYFPFindSheet(NSString **uidOut) {          // YES = a profile sheet is open; *uidOut = whose (nil if it could not be told)
    RYFPInit(); *uidOut = nil;
    UIView *anchor = nil; UIWindow *win = nil;
    for (UIWindow *w in RYAppWindows()) { int b = 14000; RYFPFindAnchor(w, 0, &b, &anchor); if (anchor) { win = w; break; } }
    if (!anchor) return NO;
    CGSize ws = win.bounds.size; UIView *cont = anchor;
    for (UIView *p = anchor.superview; p && p != win; p = p.superview) {
        CGRect f = [p convertRect:p.bounds toView:nil];
        if (f.size.width >= ws.width * 0.9 && f.size.height >= ws.height * 0.3 && f.size.height <= ws.height * 1.05) { cont = p; break; }
    }
    NSMutableArray *labels = [NSMutableArray new]; int b = 6000; RYFPLabels(cont, 0, &b, labels); gFPLabelCount = (NSInteger)labels.count;
    NSMutableDictionary<NSString *, NSNumber *> *tally = [NSMutableDictionary new];
    NSString *prof = nil;
    @synchronized (gFPLock) {
        for (NSString *t in labels) {
            NSString *k = [[t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString]; if ([k hasPrefix:@"@"]) k = [k substringFromIndex:1];
            NSString *u = k.length ? gFPNames[k] : nil; if (u) tally[u] = @([tally[u] intValue] + 1);
        }
        if (gFPProfUid && gFPProfAt && -[gFPProfAt timeIntervalSinceNow] < 40) prof = gFPProfUid;
    }
    NSString *best = nil; int bc = 0; for (NSString *u in tally) if ([tally[u] intValue] > bc) { bc = [tally[u] intValue]; best = u; }
    if (best) { gFPSrc = @"name"; *uidOut = best; } else if (prof) { gFPSrc = @"profile request"; *uidOut = prof; } else gFPSrc = @"none";
    return YES;
}
static NSString *RYFPDiag(void) {
    RYFPInit(); NSMutableString *o = [NSMutableString new];
    NSString *fol, *myC, *myG; NSArray *pulls; BOOL auth; NSUInteger nn, nu; NSDate *pa; NSString *pu;
    @synchronized (gFPLock) { fol = gFPFollow; myC = gFPMyC; myG = gFPMyG; pulls = gFPPull.allObjects; auth = gApiHdr != nil; nn = gFPNames.count; nu = gFPUser.count; pu = gFPProfUid; pa = gFPProfAt; }
    [o appendFormat:@"follow: %@\npull: %@\nmy voice channel: %@ (guild %@)\nown id known: %d   voice frames handled %d   names %lu   users %lu\n", fol ?: @"-", pulls.count ? [pulls componentsJoinedByString:@","] : @"-", myC ?: @"-", myG ?: @"-", gFDOwnId != nil, gFPFrames, (unsigned long)nn, (unsigned long)nu];
    [o appendFormat:@"request headers captured: %d   last profile request: %@ (%.0fs ago)\njoins %d   moves ok %d   move errors %d (last status %d)\nsheet id source: %@   labels in sheet %ld\n", auth, pu ?: @"-", pa ? -[pa timeIntervalSinceNow] : -1.0, gFPJoins, gFPMoves, gFPErr, gFPLastStatus, gFPSrc, (long)gFPLabelCount];
    NSMutableArray *ls = [NSMutableArray new]; for (UIWindow *w in RYAppWindows()) { int b = 14000; RYFPLabels(w, 0, &b, ls); }
    [o appendFormat:@"\ntext labels visible in the app: %lu (first 70)\n", (unsigned long)ls.count];
    for (NSUInteger i = 0; i < ls.count && i < 70; i++) [o appendFormat:@"  %@\n", ls[i]];
    return o;
}

// ---- persistence: every recent message is remembered (compact JSON); when one is deleted by someone else it is copied to Documents/8ubah/data/deleted.json
// and put back into the server's answer whenever the app asks for that channel's messages again (after a restart, scrolling, switching chats).
static NSObject *gLogLock;
// ---- crash recorder: when Discord dies, the reason + the last hook that was running is written to Documents/8ubah/data/crash.txt.
// On the next launch it is moved to crash-last.txt and shown in the Diag report ("last crash"). This is how the real cause of a crash is found.
static const char *volatile gCrumb = "start";
static char gCrashPath[1100]; static NSUncaughtExceptionHandler *gPrevExc; static struct sigaction gPrevSig[32];
static void RYCrashSig(int sig) {
    int fd = open(gCrashPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        char head[240]; int n = snprintf(head, sizeof head, "SIGNAL %d (%s)\nlast hook: %s\ntime: %ld\n", sig, sig == SIGSEGV ? "SEGV" : sig == SIGBUS ? "BUS" : sig == SIGABRT ? "ABRT" : sig == SIGILL ? "ILL" : sig == SIGTRAP ? "TRAP" : "other", gCrumb ?: "-", (long)time(NULL));
        if (n > 0) (void)!write(fd, head, (size_t)MIN(n, (int)sizeof head - 1));
        void *bt[40]; int c = backtrace(bt, 40); backtrace_symbols_fd(bt, c, fd); close(fd);
    }
    if (sig > 0 && sig < 32) sigaction(sig, &gPrevSig[sig], NULL);
    raise(sig);
}
static void RYCrashExc(NSException *e) {
    @try {
        NSString *t = [NSString stringWithFormat:@"EXCEPTION %@\n%@\nlast hook: %s\n%@\n", e.name, e.reason, gCrumb ?: "-", [e.callStackSymbols componentsJoinedByString:@"\n"]];
        [t writeToFile:[NSString stringWithUTF8String:gCrashPath] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (__unused id x) {}
    if (gPrevExc) gPrevExc(e);
}
static void RYInstallCrashLog(void) {
    static BOOL first = YES;
    NSString *dir = RYDir(@"data"), *p = [dir stringByAppendingPathComponent:@"crash.txt"];
    if (first) { first = NO; NSString *last = [dir stringByAppendingPathComponent:@"crash-last.txt"]; NSFileManager *fm = NSFileManager.defaultManager; if ([fm fileExistsAtPath:p]) { [fm removeItemAtPath:last error:nil]; [fm moveItemAtPath:p toPath:last error:nil]; } }
    strlcpy(gCrashPath, p.fileSystemRepresentation, sizeof gCrashPath);
    int sigs[] = {SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGTRAP, SIGFPE};
    for (size_t i = 0; i < sizeof sigs / sizeof sigs[0]; i++) {
        struct sigaction cur; if (sigaction(sigs[i], NULL, &cur) == 0 && cur.sa_handler == RYCrashSig) continue;   // already ours (second install after the app's own crash reporter)
        struct sigaction sa; memset(&sa, 0, sizeof sa); sa.sa_handler = RYCrashSig; sigemptyset(&sa.sa_mask);
        sigaction(sigs[i], &sa, &gPrevSig[sigs[i]]);
    }
    NSUncaughtExceptionHandler *cur = NSGetUncaughtExceptionHandler(); if (cur != RYCrashExc) { gPrevExc = cur; NSSetUncaughtExceptionHandler(RYCrashExc); }
}
static NSString *RYCrashText(void) {
    NSString *t = [NSString stringWithContentsOfFile:[RYDir(@"data") stringByAppendingPathComponent:@"crash-last.txt"] encoding:NSUTF8StringEncoding error:nil];
    NSString *u = [NSString stringWithContentsOfFile:[RYDir(@"data") stringByAppendingPathComponent:@"crash.txt"] encoding:NSUTF8StringEncoding error:nil];
    NSMutableString *o = [NSMutableString new];
    if (t.length) [o appendFormat:@"previous launch:\n%@\n", t]; if (u.length) [o appendFormat:@"this launch:\n%@\n", u];
    return o.length ? o : @"(none)";
}
static NSObject *gNetLock; static NSMutableDictionary<NSString *, NSMutableDictionary *> *gNetReq; static volatile int gNetBuf = 0;
static NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSData *> *> *gMsgCache;   // channel -> id -> JSON of a recently seen message
static NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSData *> *> *gDelStore;   // channel -> id -> JSON of a kept (deleted) message
static NSMutableDictionary<NSString *, NSDate *> *gCacheTouch;
static volatile int gNetSeen = 0, gNetInj = 0, gNetCached = 0, gStored = 0; static BOOL gSaveQueued = NO; static char gNetLast[200] = "-";
static NSComparisonResult RYSnowCmp(NSString *a, NSString *b) {                                    // snowflakes: longer = bigger, then text order
    if (a.length != b.length) return a.length < b.length ? NSOrderedAscending : NSOrderedDescending;
    return [a compare:b];
}
static NSString *RYDelPath(void) { return [RYDir(@"data") stringByAppendingPathComponent:@"deleted.json"]; }
static void RYDelSave(void) {
    @synchronized (gLogLock) {
        if (gSaveQueued) return; gSaveQueued = YES;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableData *out = [NSMutableData dataWithBytes:"{" length:1]; BOOL firstC = YES; int n = 0;
        @synchronized (gLogLock) {
            gSaveQueued = NO;
            for (NSString *cid in gDelStore) {
                NSDictionary *m = gDelStore[cid]; if (!m.count) continue;
                if (!firstC) [out appendBytes:"," length:1]; firstC = NO;
                [out appendData:[[NSString stringWithFormat:@"\"%@\":[", cid] dataUsingEncoding:NSUTF8StringEncoding]];
                BOOL firstM = YES;
                for (NSString *mid in m) { if (!firstM) [out appendBytes:"," length:1]; firstM = NO; [out appendData:m[mid]]; n++; }
                [out appendBytes:"]" length:1];
            }
            gStored = n;
        }
        [out appendBytes:"}" length:1];
        [out writeToFile:RYDelPath() atomically:YES];
    });
}
static void RYDelLoad(void) {
    NSData *d = [NSData dataWithContentsOfFile:RYDelPath()]; if (!d.length) return;
    id j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    if (![j isKindOfClass:NSDictionary.class]) return;
    @synchronized (gLogLock) {
        for (NSString *cid in j) {
            NSArray *a = j[cid]; if (![a isKindOfClass:NSArray.class]) continue;
            NSMutableDictionary *m = gDelStore[cid] ?: [NSMutableDictionary new];
            for (id o in a) {
                if (![o isKindOfClass:NSDictionary.class]) continue;
                if (o[@"guild_id"] && o[@"guild_id"] != NSNull.null) continue;                            // old server entries are dropped: servers are not kept any more
                NSString *mid = RYStr(o[@"id"]); NSData *x = [NSJSONSerialization dataWithJSONObject:o options:0 error:nil];
                if (mid && x) { m[mid] = x; @synchronized (gLogIds) { [gLogIds addObject:mid]; } }
            }
            if (m.count) gDelStore[cid] = m;
        }
        int n = 0; for (NSString *c in gDelStore) n += (int)gDelStore[c].count; gStored = n;
    }
}
static void RYCacheMsg(id o) {
    if (![o isKindOfClass:NSDictionary.class]) return;
    if (o[@"guild_id"] && o[@"guild_id"] != NSNull.null) return;                                    // server messages are never remembered, never saved
    NSString *mid = RYStr(o[@"id"]), *cid = RYStr(o[@"channel_id"]);
    if (!mid || !cid || !o[@"author"] || !o[@"timestamp"]) return;                                  // partial updates (embeds only) are ignored
    NSData *x = [NSJSONSerialization dataWithJSONObject:o options:0 error:nil]; if (!x) return;
    @synchronized (gLogLock) {
        NSMutableDictionary *m = gMsgCache[cid]; if (!m) { m = [NSMutableDictionary new]; gMsgCache[cid] = m; }
        m[mid] = x; gCacheTouch[cid] = [NSDate date]; gNetCached++;
        if (m.count > 150) {                                                                         // keep the newest 120 of a channel
            NSArray *ids = [m.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { return RYSnowCmp(a, b); }];
            for (NSUInteger i = 0; i + 120 < ids.count; i++) [m removeObjectForKey:ids[i]];
        }
        if (gMsgCache.count > 80) {                                                                  // and the 60 most recently used channels
            NSArray *cs = [gCacheTouch keysSortedByValueUsingSelector:@selector(compare:)];
            for (NSUInteger i = 0; i + 60 < cs.count; i++) { [gMsgCache removeObjectForKey:cs[i]]; [gCacheTouch removeObjectForKey:cs[i]]; }
        }
    }
}
// called when a delete from somebody else is kept: copy the remembered message to the permanent store
static void RYKeepMsg(NSString *cid, NSString *mid) {
    if (!cid || !mid) return;
    @synchronized (gLogLock) {
        NSData *x = gMsgCache[cid][mid]; if (!x) return;
        NSMutableDictionary *m = gDelStore[cid]; if (!m) { m = [NSMutableDictionary new]; gDelStore[cid] = m; }
        m[mid] = x;
    }
    RYDelSave();
}
static void RYForgetMsg(NSString *mid) {                                                             // you deleted it yourself: it must really go
    BOOL ch = NO;
    @synchronized (gLogLock) {
        for (NSString *cid in gDelStore.allKeys) if (gDelStore[cid][mid]) { [gDelStore[cid] removeObjectForKey:mid]; ch = YES; }
        for (NSString *cid in gMsgCache) [gMsgCache[cid] removeObjectForKey:mid];
        @synchronized (gLogIds) { [gLogIds removeObject:mid]; }
    }
    if (ch) RYDelSave();
}
static void RYLogInit(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{ gNetLock = [NSObject new]; gNetReq = [NSMutableDictionary new]; gLogLock = [NSObject new]; gLogIds = [NSMutableSet new]; gOwnDel = [NSMutableDictionary new]; gMsgCache = [NSMutableDictionary new]; gDelStore = [NSMutableDictionary new]; gCacheTouch = [NSMutableDictionary new]; RYDelLoad(); });
}
static BOOL RYIsKept(NSString *mid) { if (!mid || !gLogIds) return NO; @synchronized (gLogIds) { return [gLogIds containsObject:mid]; } }
static NSString *RYLoggerStatus(void) {
    return [NSString stringWithFormat:T(@"المسجّل: محفوظة %d، مخزنة %d، رجعت %d", @"Logger: kept %d, stored %d, restored %d"), gLogKept, gStored, gNetInj];
}

// ---- own deletes: DELETE /channels/<c>/messages/<m> on the app's HTTP handler
static id RYHttpSend(id self, SEL _cmd, id req, id delegate) {
    gCrumb = "http send";
    @try {
        if ([req isKindOfClass:NSURLRequest.class]) RYFPCaptureReq((NSURLRequest *)req);
        if ([req isKindOfClass:NSURLRequest.class] && [[(NSURLRequest *)req HTTPMethod] isEqualToString:@"DELETE"]) {
            NSArray *c = [[(NSURLRequest *)req URL].path componentsSeparatedByString:@"/"];
            NSUInteger i = [c indexOfObject:@"messages"];
            if (i != NSNotFound && i >= 2 && i + 1 < c.count && [c[i - 2] isEqual:@"channels"]) {
                RYLogInit(); @synchronized (gOwnDel) { gOwnDel[c[i + 1]] = [NSDate date]; } RYForgetMsg(c[i + 1]);
            }
        }
    } @catch (__unused id e) {}
    return orig_httpSend ? orig_httpSend(self, _cmd, req, delegate) : nil;
}
static BOOL RYOwnDeleted(NSString *mid) {
    if (!mid || !gOwnDel) return NO;
    @synchronized (gOwnDel) {
        NSDate *d = gOwnDel[mid]; if (!d) return NO;
        [gOwnDel removeObjectForKey:mid];
        if (-[d timeIntervalSinceNow] > 300) return NO;
        return YES;
    }
}

// ---- gateway: MESSAGE_DELETE of someone else's DM message becomes an unknown event that JS ignores (its sequence number still counts)
static NSString *RYGatewayFilter(NSString *s) {
    gCrumb = "gateway filter";
    if (s.length > 60000) return s;
    BOOL isDel = [s rangeOfString:@"\"MESSAGE_DELETE"].location != NSNotFound;
    BOOL isNew = !isDel && ([s rangeOfString:@"\"MESSAGE_CREATE\""].location != NSNotFound || [s rangeOfString:@"\"MESSAGE_UPDATE\""].location != NSNotFound);
    if (!isDel && !isNew) return s;
    NSData *dt = [s dataUsingEncoding:NSUTF8StringEncoding]; if (!dt) return s;
    RYLogInit();
    id j = [NSJSONSerialization JSONObjectWithData:dt options:NSJSONReadingMutableContainers error:nil];
    if (![j isKindOfClass:NSMutableDictionary.class]) return s;
    NSString *t = j[@"t"];
    if (isNew) { if ([t isEqual:@"MESSAGE_CREATE"] || [t isEqual:@"MESSAGE_UPDATE"]) RYCacheMsg(j[@"d"]); return s; }
    BOOL bulk = [t isEqual:@"MESSAGE_DELETE_BULK"];
    if (!bulk && ![t isEqual:@"MESSAGE_DELETE"]) return s;
    NSDictionary *d = j[@"d"]; if (![d isKindOfClass:NSDictionary.class]) return s;
    RYLogInit(); gLogSeen++;
    id gid = d[@"guild_id"];
    if (gid && gid != NSNull.null) { gLogPass++; return s; }                                         // a server message (guild_id present): the delete goes through normally. Only DMs and group chats are kept.
    NSArray *ids = bulk ? d[@"ids"] : (d[@"id"] ? @[d[@"id"]] : @[]);
    if (![ids isKindOfClass:NSArray.class] || !ids.count) return s;
    NSString *cid0 = RYStr(d[@"channel_id"]), *mid0 = RYStr(ids.firstObject);
    if (!cid0 || !mid0) return s;
    for (id x in ids) if (RYOwnDeleted(RYStr(x))) { gLogOwn++; return s; }                          // you deleted it yourself: deletes normally
    @synchronized (gLogIds) { for (id x in ids) { NSString *m = RYStr(x); if (m) [gLogIds addObject:m]; } if (gLogIds.count > 4000) [gLogIds removeAllObjects]; }
    for (id x in ids) RYKeepMsg(RYStr(d[@"channel_id"]), RYStr(x));
    gLogKept += (int)ids.count;
    snprintf(gLogLast, sizeof gLogLast, "kept %s chan=%s", RYStr(ids.firstObject).UTF8String ?: "?", RYStr(d[@"channel_id"]).UTF8String ?: "?");
    RYLog(@"logger: kept %@ (chan %@)", ids, d[@"channel_id"]);
    // The delete is replaced by a perfectly normal MESSAGE_UPDATE of the same message (the JS store merges it into the message it already has,
    // nothing is removed, guild_id stays, no unknown event type reaches JS). Full copy if we remember the message, else just ids.
    id full = nil;
    @synchronized (gLogLock) { NSData *x = gMsgCache[cid0][mid0] ?: gDelStore[cid0][mid0]; if (x) full = [NSJSONSerialization JSONObjectWithData:x options:NSJSONReadingMutableContainers error:nil]; }
    BOOL hadFull = [full isKindOfClass:NSDictionary.class];
    if (!hadFull) full = @{@"id": mid0, @"channel_id": cid0};   // never saw it: a partial update (same shape Discord uses for embed updates) still stops the delete, the message stays where it is
    if (hadFull) gLogKeptFull++; else gLogKeptStub++;   // split so the Diag report can show which path each case went through
    j[@"t"] = @"MESSAGE_UPDATE"; j[@"d"] = full;
    NSData *out = [NSJSONSerialization dataWithJSONObject:j options:0 error:nil];
    NSString *ns = out ? [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding] : nil;
    return ns ?: s;
}
static void RYRefreshCells(void);
static void RYWsSend(id self, SEL _cmd, NSString *name, id body) {
    @try {
        if ([name isEqual:@"websocketMessage"] && [body isKindOfClass:NSDictionary.class]) {
            gWsMsgs++;
            id d = body[@"data"]; NSString *newData = nil;
            if ([d isKindOfClass:NSString.class]) {
                if ([[body[@"type"] description] isEqual:@"binary"]) {                                   // base64 of the decompressed bytes
                    NSData *raw = [[NSData alloc] initWithBase64EncodedString:d options:0];
                    if (raw.length) RYFDWatch((const char *)raw.bytes, raw.length, body[@"id"], self);
                    if (raw.length && raw.length < 60000 && (memmem(raw.bytes, raw.length, "MESSAGE_DELETE", 14) || memmem(raw.bytes, raw.length, "MESSAGE_CREATE", 14) || memmem(raw.bytes, raw.length, "MESSAGE_UPDATE", 14))) {
                        NSString *txt = [[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding]; NSString *f = txt ? RYGatewayFilter(txt) : nil;
                        if (f && f != txt) newData = [[f dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
                    }
                } else { const char *u = [(NSString *)d UTF8String]; if (u) RYFDWatch(u, strlen(u), body[@"id"], self); NSString *f = RYGatewayFilter(d); if (f != d) newData = f; }
            }
            if (newData) {
                NSMutableDictionary *nb = [body mutableCopy]; nb[@"data"] = newData; body = nb;
                for (NSNumber *dl in @[@0.0, @0.35, @1.0, @2.2]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(dl.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ RYRefreshCells(); });
            }
        }
    } @catch (__unused id e) {}
    if (orig_wsSend) orig_wsSend(self, _cmd, name, body);
}

// ---- cells: kept messages get a red wash and red text; every other cell gets the chat text colour
// The username label above the message body already carries Discord's own per-sender colour (role colour, etc), read it off the label.
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
static const void *kRYMid = &kRYMid;    // the message id is remembered ON the cell each time the app configures it
static NSString *RYCellMsgId(UITableViewCell *cell, id vm) {
    NSString *mid = nil;
    if (vm) mid = RYStr(RYKV(vm, @"id")) ?: RYStr(RYKV(RYKV(vm, @"message"), @"id"));
    if (!mid) mid = RYStr(RYKV(RYKV(RYKV(cell, @"baseViewModel"), @"message"), @"id"));
    if (mid) objc_setAssociatedObject(cell, kRYMid, mid, OBJC_ASSOCIATION_COPY_NONATOMIC);
    else mid = objc_getAssociatedObject(cell, kRYMid);
    return mid;
}
static volatile int gPaintSeen = 0, gPaintNoId = 0, gPaintKept = 0;
// A kept/red message is already gone on Discord's own server. Letting Discord's native reply/react/
// context-menu gestures run against it (as if it were still real) is what was crashing/kicking the app
// sometimes — Discord's own code doesn't expect to act on a message it no longer has. Rather than guess
// at and swizzle Discord's private reply/context-menu methods (risky to get the exact ABI right without
// a real device to test on, as the Fake Defen mistake showed), we just disable the EXISTING gesture
// recognizers UIKit already attached to the cell — a message that's only a visual record becomes fully
// read-only. This is reversible per cell (cells get reused for different messages), using only public,
// stable UIKit API (no private selectors, no ABI guessing).
static void RYSetCellInteractive(UITableViewCell *cell, BOOL on) {
    if (cell.userInteractionEnabled != on) cell.userInteractionEnabled = on;
}
// The "deleted" mark is made of CALayers only (red wash, side bar, "Deleted" badge). Not one view is added to Discord's cell: its own layout code
// walks contentView.subviews, and an extra subview there is what hung / crashed the app when the list updated.
static NSString *const kRYMark = @"8ubah.mark";
static CALayer *RYMarkLayer(CALayer *host, NSString *name) { for (CALayer *l in host.sublayers) if ([l.name isEqual:name]) return l; return nil; }
static void RYMarkCell(UITableViewCell *cell, BOOL on) {
    CALayer *host = cell.contentView.layer; if (!host) return;
    NSString *kw = [kRYMark stringByAppendingString:@".wash"], *kd = [kRYMark stringByAppendingString:@".deco"];
    CALayer *wash = RYMarkLayer(host, kw), *deco = RYMarkLayer(host, kd);
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    if (!on) { [wash removeFromSuperlayer]; [deco removeFromSuperlayer]; [CATransaction commit]; return; }
    CGRect cb = cell.contentView.bounds; CGFloat sc = UIScreen.mainScreen.scale;
    if (!wash) { wash = [CALayer layer]; wash.name = kw; [host insertSublayer:wash atIndex:0]; }
    wash.frame = cb; wash.backgroundColor = [RY_RED colorWithAlphaComponent:0.22].CGColor;
    if (!deco) {
        deco = [CALayer layer]; deco.name = kd; deco.zPosition = 50;
        CALayer *bar = [CALayer layer]; bar.name = @"bar"; bar.backgroundColor = RY_RED.CGColor; [deco addSublayer:bar];
        CALayer *pill = [CALayer layer]; pill.name = @"pill"; pill.backgroundColor = RY_RED.CGColor; pill.cornerRadius = 8; [deco addSublayer:pill];
        CATextLayer *tx = [CATextLayer layer]; tx.name = @"txt"; tx.contentsScale = sc; tx.alignmentMode = kCAAlignmentCenter; tx.truncationMode = kCATruncationNone;
        NSString *t = T(@"🗑 محذوفة", @"🗑 Deleted");
        tx.string = [[NSAttributedString alloc] initWithString:t attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightHeavy], NSForegroundColorAttributeName: UIColor.whiteColor}];
        [deco addSublayer:tx]; [host addSublayer:deco];
    }
    deco.frame = cb;
    CALayer *bar = RYMarkLayer(deco, @"bar"), *pill = RYMarkLayer(deco, @"pill"), *tx = RYMarkLayer(deco, @"txt");
    bar.frame = CGRectMake(0, 0, 4, cb.size.height);
    CGFloat w = [(NSAttributedString *)((CATextLayer *)tx).string size].width + 16;
    pill.frame = CGRectMake(cb.size.width - w - 8, 3, w, 16); tx.frame = CGRectMake(pill.frame.origin.x, pill.frame.origin.y + 2, w, 13);
    [CATransaction commit];
}
static void RYDecorateCell(UITableViewCell *cell, id vm) {
    NSString *mid = RYCellMsgId(cell, vm);
    gPaintSeen++; if (!mid) gPaintNoId++;
    BOOL del = RYIsKept(mid);
    if (del) gPaintKept++;
    RYSetCellInteractive(cell, !del);
    RYMarkCell(cell, del);
    id lab = RYKV(cell, @"contentLabel");
    if ([lab isKindOfClass:UIView.class]) {
        if (del) RYTintYY(lab, RY_RED, YES);
        else { UIColor *tc = RYTextTarget(); if (tc) RYTintYY(lab, tc, NO); }      // the picked colour only, never automatic
    }
}
static void RYCellCfg(id self, SEL _cmd, id vm, id pool, id am) {
    gCrumb = "cell configure";
    orig_cellCfg(self, _cmd, vm, pool, am);
    @try { RYDecorateCell((UITableViewCell *)self, vm); } @catch (__unused id e) {}
}
static void RYCollectTables(UIView *v, NSMutableArray *o, int d) {
    if (!v || d > 14) return;
    if ([v isKindOfClass:UITableView.class]) [o addObject:v];
    for (UIView *s in v.subviews) RYCollectTables(s, o, d + 1);
}
// cells already on screen are not re-configured by the app (nothing changed for it), so paint them directly
static NSUInteger RYKeptCount(void) { if (!gLogIds) return 0; @synchronized (gLogIds) { return gLogIds.count; } }
static void RYRefreshCells(void) {
    gCrumb = "refresh cells";
    if (!RYKeptCount()) return;
    UIView *host = RYChatHost(); if (!host) return;
    NSMutableArray *tabs = [NSMutableArray new]; RYCollectTables(host, tabs, 0);
    Class mc = NSClassFromString(@"DCDMessageTableViewCell");
    for (UITableView *tv in tabs) for (UITableViewCell *c in tv.visibleCells) if (mc && [c isKindOfClass:mc]) { @try { RYDecorateCell(c, nil); } @catch (__unused id e) {} }
}

// ---- REST answers: GET /channels/<id>/messages comes back from RCTNetworking as raw bytes; kept messages are merged in (sorted newest first)
static void (*orig_netData)(id, SEL, NSData *, NSString *, id, id);
static NSDictionary *RYQueryOf(NSURL *u) {
    NSMutableDictionary *q = [NSMutableDictionary new];
    for (NSURLQueryItem *i in [NSURLComponents componentsWithURL:u resolvingAgainstBaseURL:NO].queryItems) if (i.name && i.value) q[i.name] = i.value;
    return q;
}
static NSData *RYMergeKeptRaw(NSData *data, NSURL *url) {
    if (!url || data.length < 2 || data.length > 4000000) return data;
    NSArray *c = [url.path componentsSeparatedByString:@"/"];
    NSUInteger i = [c indexOfObject:@"channels"];
    if (i == NSNotFound || i + 2 != c.count - 1 || ![c[i + 2] isEqual:@"messages"] || !([url.query containsString:@"limit="] || [url.query containsString:@"before="] || [url.query containsString:@"after="] || [url.query containsString:@"around="])) return data;   // exactly the list /channels/<id>/messages?limit=..
    NSString *cid = c[i + 1]; if (!cid.length) return data;
    gNetSeen++;
    id arr = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![arr isKindOfClass:NSArray.class]) return data;
    NSDictionary *q = RYQueryOf(url); NSInteger limit = q[@"limit"] ? [q[@"limit"] integerValue] : 50; if (limit < 1) limit = 50;
    NSMutableSet *have = [NSMutableSet new]; NSString *minId = nil, *maxId = nil;
    for (id m in arr) {
        RYCacheMsg(m);
        NSString *mid = [m isKindOfClass:NSDictionary.class] ? RYStr(m[@"id"]) : nil; if (!mid) continue;
        [have addObject:mid];
        if (!minId || RYSnowCmp(mid, minId) == NSOrderedAscending) minId = mid;
        if (!maxId || RYSnowCmp(mid, maxId) == NSOrderedDescending) maxId = mid;
    }
    BOOL full = (NSInteger)[arr count] >= limit;
    NSString *before = q[@"before"], *after = q[@"after"], *around = q[@"around"];
    NSMutableArray *add = [NSMutableArray new];
    @synchronized (gLogLock) {
        NSDictionary *saved = gDelStore[cid];
        for (NSString *sid in saved) {
            if ([have containsObject:sid]) continue;
            BOOL ok;
            if (before) ok = RYSnowCmp(sid, before) == NSOrderedAscending && (!full || !minId || RYSnowCmp(sid, minId) != NSOrderedAscending);
            else if (after) ok = RYSnowCmp(sid, after) == NSOrderedDescending && (!full || !maxId || RYSnowCmp(sid, maxId) != NSOrderedDescending);
            else if (around) ok = !full || (minId && RYSnowCmp(sid, minId) != NSOrderedAscending && RYSnowCmp(sid, maxId) != NSOrderedDescending);
            else ok = !full || !minId || RYSnowCmp(sid, minId) != NSOrderedAscending;
            if (!ok) continue;
            id o = [NSJSONSerialization JSONObjectWithData:saved[sid] options:0 error:nil]; if (o) [add addObject:o];
        }
    }
    if (!add.count) return data;
    NSMutableArray *all = [arr mutableCopy]; [all addObjectsFromArray:add];
    [all sortUsingComparator:^NSComparisonResult(id a, id b) { return RYSnowCmp(RYStr(b[@"id"]) ?: @"", RYStr(a[@"id"]) ?: @""); }];   // newest first
    NSData *out = [NSJSONSerialization dataWithJSONObject:all options:0 error:nil]; if (!out) return data;
    gNetInj += (int)add.count;
    snprintf(gNetLast, sizeof gNetLast, "put back %d into %s", (int)add.count, cid.UTF8String);
    RYLog(@"logger: put back %d kept message(s) into channel %@ (%@)", (int)add.count, cid, url.query ?: @"");
    return out;
}
static NSData *RYMergeKept(NSData *data, NSURLResponse *resp) {
    if (![resp isKindOfClass:NSHTTPURLResponse.class] || [(NSHTTPURLResponse *)resp statusCode] != 200) return data;
    return RYMergeKeptRaw(data, resp.URL);
}
// The app's REST client asks RCTNetworking for *incremental text*: the answer reaches JS as "didReceiveNetworkIncrementalData" chunks and
// RCTNetworking.sendData: is not used for it. So the chunks of a message-list answer are held back, merged when the request completes and
// handed over as one chunk right before "didCompleteNetworkResponse".
static void (*orig_netEvt)(id, SEL, NSString *, id);
static BOOL RYIsMsgListURL(NSURL *u) {
    NSArray *c = [u.path componentsSeparatedByString:@"/"]; NSUInteger i = [c indexOfObject:@"channels"];
    return i != NSNotFound && i + 2 == c.count - 1 && [c[i + 2] isEqual:@"messages"] && ([u.query containsString:@"limit="] || [u.query containsString:@"before="] || [u.query containsString:@"after="] || [u.query containsString:@"around="]);
}
static void RYNetEvent(id self, SEL _cmd, NSString *name, id body) {
    gCrumb = "network event";
    @try {
        if ([body isKindOfClass:NSArray.class] && [body count] >= 1) {
            NSString *rid = [[body objectAtIndex:0] description];
            if ([name isEqual:@"didReceiveNetworkResponse"] && [body count] >= 4) {
                NSURL *u = [NSURL URLWithString:RYStr([body objectAtIndex:3]) ?: @""];
                if (u && [[body objectAtIndex:1] integerValue] == 200 && RYIsMsgListURL(u)) {
                    RYLogInit(); @synchronized (gNetLock) { gNetReq[rid] = [@{@"url": u, @"buf": [NSMutableString new]} mutableCopy]; }
                }
            } else if ([name isEqual:@"didReceiveNetworkIncrementalData"] && [body count] >= 2 && [[body objectAtIndex:1] isKindOfClass:NSString.class]) {
                NSMutableDictionary *e; @synchronized (gNetLock) { e = gNetReq[rid]; }
                if (e) {
                    NSMutableString *buf = e[@"buf"]; [buf appendString:[body objectAtIndex:1]]; gNetBuf++;
                    if (buf.length > 4000000) {                                                             // too big to merge: hand it over as it is
                        @synchronized (gNetLock) { [gNetReq removeObjectForKey:rid]; }
                        if (orig_netEvt) orig_netEvt(self, _cmd, @"didReceiveNetworkIncrementalData", @[[body objectAtIndex:0], [buf copy], @(buf.length), @(buf.length)]);
                    }
                    return;                                                                                 // held back until the request completes
                }
            } else if ([name isEqual:@"didCompleteNetworkResponse"]) {
                NSMutableDictionary *e; @synchronized (gNetLock) { e = gNetReq[rid]; if (e) [gNetReq removeObjectForKey:rid]; }
                if (e) {
                    NSString *text = [(NSMutableString *)e[@"buf"] copy];
                    if (text.length) {
                        NSString *out = text;
                        @try {
                            NSData *m = RYMergeKeptRaw([text dataUsingEncoding:NSUTF8StringEncoding], e[@"url"]);
                            NSString *ms = m ? [[NSString alloc] initWithData:m encoding:NSUTF8StringEncoding] : nil; if (ms) out = ms;
                        } @catch (__unused id ex) { out = text; }
                        if (orig_netEvt) orig_netEvt(self, _cmd, @"didReceiveNetworkIncrementalData", @[[body objectAtIndex:0], out, @(out.length), @(out.length)]);
                    }
                }
            }
        }
    } @catch (__unused id e) {}
    if (orig_netEvt) orig_netEvt(self, _cmd, name, body);
}
static void RYNetSendData(id self, SEL _cmd, NSData *data, NSString *type, id resp, id task) {
    gCrumb = "network data";
    NSData *use = data;
    @try { RYLogInit(); if ([data isKindOfClass:NSData.class]) use = RYMergeKept(data, resp); } @catch (__unused id e) { use = data; }
    if (orig_netData) orig_netData(self, _cmd, use, type, resp, task);
}
static void RYStartMarkTimer(void) {
    static BOOL on; if (on) return; on = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) { if (RYKeptCount()) RYRefreshCells(); }]; });
}
static void RYInstallLogger(void) {
    static BOOL cellDone, wsDone, httpDone, netDone, evtDone; RYLogInit(); RYStartMarkTimer();
    if (!cellDone) {
        Class cc = NSClassFromString(@"DCDMessageTableViewCell");
        Method cm = cc ? class_getInstanceMethod(cc, NSSelectorFromString(@"configureWithViewModel:viewReusePoolManager:actionManager:")) : NULL;
        if (cm && method_getNumberOfArguments(cm) == 5) { orig_cellCfg = (void *)method_getImplementation(cm); method_setImplementation(cm, (IMP)RYCellCfg); cellDone = YES; RYLog(@"logger: cell hook installed"); }
    }
    if (!wsDone) {
        Class wc = NSClassFromString(@"RCTWebSocketModule"); SEL s = NSSelectorFromString(@"sendEventWithName:body:");
        Method m = wc ? class_getInstanceMethod(wc, s) : NULL;
        if (m && method_getNumberOfArguments(m) == 4) { orig_wsSend = (void *)method_getImplementation(m); class_replaceMethod(wc, s, (IMP)RYWsSend, method_getTypeEncoding(m)); wsDone = YES; gWsInHooked = YES; RYLog(@"logger: websocket hook installed"); }
    }
    if (!netDone) {
        Class nc = NSClassFromString(@"RCTNetworking"); SEL ns = NSSelectorFromString(@"sendData:responseType:response:forTask:");
        Method nm = nc ? class_getInstanceMethod(nc, ns) : NULL;
        if (nm && method_getNumberOfArguments(nm) == 6) { orig_netData = (void *)method_getImplementation(nm); method_setImplementation(nm, (IMP)RYNetSendData); netDone = YES; RYLog(@"logger: network hook installed"); }
    }
    if (!evtDone) {
        Class ec = NSClassFromString(@"RCTNetworking"); SEL es = NSSelectorFromString(@"sendEventWithName:body:");
        Method em = ec ? class_getInstanceMethod(ec, es) : NULL;
        if (em && method_getNumberOfArguments(em) == 4) { orig_netEvt = (void *)method_getImplementation(em); class_replaceMethod(ec, es, (IMP)RYNetEvent, method_getTypeEncoding(em)); evtDone = YES; RYLog(@"logger: network event hook installed"); }
    }
    if (!httpDone) {
        Class hc = NSClassFromString(@"RCTHTTPRequestHandler"); SEL s = NSSelectorFromString(@"sendRequest:withDelegate:");
        Method m = hc ? class_getInstanceMethod(hc, s) : NULL;
        if (m && method_getNumberOfArguments(m) == 4) { orig_httpSend = (void *)method_getImplementation(m); class_replaceMethod(hc, s, (IMP)RYHttpSend, method_getTypeEncoding(m)); httpDone = YES; RYLog(@"logger: http hook installed"); }
    }
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
    [o appendFormat:@"\n== fake defean\n%@\n", RYFakeDefStatus()]; [o appendString:@"\n== follow / pull\n"]; [o appendString:RYFPDiag()];
    [o appendFormat:@"\n== last crash\n%@\n", RYCrashText()];
    [o appendFormat:@"\n== message logger\nwebsocket messages seen %d  delete events %d (kept %d, own %d, server %d)\nlast: %s\nkept ids: %lu\nstored on disk: %d  remembered messages: %d  channel fetches seen: %d (incremental chunks held %d)  put back: %d\nlast put back: %s\nvoice options last: %s (calls %d)\n", gWsMsgs, gLogSeen, gLogKept, gLogOwn, gLogPass, gLogLast, (unsigned long)gLogIds.count, gStored, gNetCached, gNetSeen, gNetBuf, gNetInj, gNetLast, gTOLast, gTOCalls];
    [o appendFormat:@"cell paint: seen %d, no id resolved %d, painted red %d\n", gPaintSeen, gPaintNoId, gPaintKept];
    [o appendFormat:@"kept via: full message %d, partial stub %d\n", gLogKeptFull, gLogKeptStub];
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

#pragma mark - Cat (oneko): a small cat runs to wherever you tap on the screen. One switch in the Cat tab, off = gone.
static const void *kRYCatTap = &kRYCatTap;
@interface RYCatView : UIView @property (nonatomic) CGFloat phase; @property (nonatomic) int facing, mode; @property (nonatomic) BOOL blink; @end
@implementation RYCatView
- (instancetype)initWithFrame:(CGRect)f { self = [super initWithFrame:f]; self.opaque = NO; self.backgroundColor = UIColor.clearColor; self.userInteractionEnabled = NO; self.facing = 1; return self; }
- (void)drawRect:(CGRect)r {
    CGContextRef c = UIGraphicsGetCurrentContext(); if (!c) return;
    if (self.facing < 0) { CGContextTranslateCTM(c, self.bounds.size.width, 0); CGContextScaleCTM(c, -1, 1); }
    UIColor *fur = [UIColor colorWithWhite:0.97 alpha:1], *ink = [UIColor colorWithWhite:0.12 alpha:1], *pink = [UIColor colorWithRed:1 green:0.6 blue:0.7 alpha:1];
    int mode = self.mode; CGFloat ph = self.phase; BOOL shut = mode == 2 || self.blink; UIBezierPath *p;
    CGFloat wag = (CGFloat)sin(ph * (mode == 0 ? 0.7 : 0.25)) * 4;
    p = [UIBezierPath bezierPath]; p.lineCapStyle = kCGLineCapRound;
    if (mode == 2) { [p moveToPoint:CGPointMake(10, 30)]; [p addQuadCurveToPoint:CGPointMake(32, 37) controlPoint:CGPointMake(14, 39)]; }
    else { [p moveToPoint:CGPointMake(10, 24)]; [p addQuadCurveToPoint:CGPointMake(4 + wag * 0.3, 8) controlPoint:CGPointMake(-2 + wag, 18)]; }
    p.lineWidth = 5; [ink setStroke]; [p stroke]; p.lineWidth = 2.8; [fur setStroke]; [p stroke];
    [ink setStroke]; CGContextSetLineWidth(c, 1.5); CGContextSetLineJoin(c, kCGLineJoinRound); CGContextSetLineCap(c, kCGLineCapRound);
    if (mode != 2) {
        CGFloat xs[4] = {12, 18, 29, 35};
        for (int i = 0; i < 4; i++) {
            CGFloat sw = mode == 0 ? (CGFloat)sin(ph + (i % 2) * M_PI) * 3 : 0;
            UIBezierPath *l = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(xs[i] - 2.5 + sw, 27, 5, 9) cornerRadius:2.5]; [fur setFill]; [l fill]; [ink setStroke]; [l stroke];
        }
    }
    UIBezierPath *body = [UIBezierPath bezierPathWithOvalInRect:mode == 2 ? CGRectMake(6, 22, 38, 14) : CGRectMake(8, 16, 34, 16)]; [fur setFill]; [body fill]; [ink setStroke]; [body stroke];
    CGPoint hc = mode == 2 ? CGPointMake(38, 28) : CGPointMake(41, 17);
    UIBezierPath *ears = [UIBezierPath bezierPath];
    [ears moveToPoint:CGPointMake(hc.x - 8, hc.y - 3)]; [ears addLineToPoint:CGPointMake(hc.x - 6, hc.y - 13)]; [ears addLineToPoint:CGPointMake(hc.x - 1, hc.y - 8)];
    [ears moveToPoint:CGPointMake(hc.x + 1, hc.y - 8)]; [ears addLineToPoint:CGPointMake(hc.x + 6, hc.y - 13)]; [ears addLineToPoint:CGPointMake(hc.x + 8, hc.y - 3)];
    [fur setFill]; [ears fill]; [ink setStroke]; [ears stroke];
    UIBezierPath *head = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(hc.x - 9, hc.y - 8.5, 18, 17)]; [fur setFill]; [head fill]; [ink setStroke]; [head stroke];
    if (shut) { UIBezierPath *e = [UIBezierPath bezierPath]; [e moveToPoint:CGPointMake(hc.x - 5, hc.y - 1)]; [e addLineToPoint:CGPointMake(hc.x - 1.5, hc.y - 1)]; [e moveToPoint:CGPointMake(hc.x + 2, hc.y - 1)]; [e addLineToPoint:CGPointMake(hc.x + 5.5, hc.y - 1)]; e.lineWidth = 1.4; [ink setStroke]; [e stroke]; }
    else { [ink setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(hc.x - 4.5, hc.y - 2.5, 3, 3.4)] fill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(hc.x + 2.5, hc.y - 2.5, 3, 3.4)] fill]; }
    [pink setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(hc.x - 0.2, hc.y + 2, 3, 2.4)] fill];
    UIBezierPath *w = [UIBezierPath bezierPath]; w.lineWidth = 0.8;
    [w moveToPoint:CGPointMake(hc.x + 6, hc.y + 3)]; [w addLineToPoint:CGPointMake(hc.x + 13, hc.y + 1)]; [w moveToPoint:CGPointMake(hc.x + 6, hc.y + 4.5)]; [w addLineToPoint:CGPointMake(hc.x + 13, hc.y + 5.5)];
    [ink setStroke]; [w stroke];
}
@end

@interface RYCatWindow : UIWindow @end
@implementation RYCatWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e { return nil; }
- (BOOL)canBecomeKeyWindow { return NO; }
@end

@interface RYCatCtl : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, strong) RYCatWindow *win; @property (nonatomic, strong) RYCatView *cat; @property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) CGPoint pos, target; @property (nonatomic) BOOL moving; @property (nonatomic) CFTimeInterval last, idleSince; @property (nonatomic) long key;
@property (nonatomic, strong) NSHashTable *taps;
+ (instancetype)shared; - (void)ensure; - (void)stop;
@end
@implementation RYCatCtl
+ (instancetype)shared { static RYCatCtl *c; static dispatch_once_t t; dispatch_once(&t, ^{ c = [RYCatCtl new]; c.taps = [NSHashTable weakObjectsHashTable]; }); return c; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)o { return YES; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t { return YES; }
- (void)tapped:(UITapGestureRecognizer *)g {
    if (!self.win || g.state != UIGestureRecognizerStateRecognized || ![g.view isKindOfClass:UIWindow.class]) return;
    CGPoint p = [(UIWindow *)g.view convertPoint:[g locationInView:g.view] toWindow:self.win];
    self.target = p; self.moving = YES; self.link.preferredFramesPerSecond = 30;
}
- (void)ensure {
    if (!self.win) {
        UIWindowScene *sc = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive) { sc = (UIWindowScene *)s; break; }
        if (!sc) return;
        self.win = [[RYCatWindow alloc] initWithWindowScene:sc]; self.win.windowLevel = UIWindowLevelAlert + 40; self.win.backgroundColor = UIColor.clearColor; self.win.userInteractionEnabled = NO;
        UIViewController *root = [UIViewController new]; root.view.backgroundColor = UIColor.clearColor; root.view.userInteractionEnabled = NO; self.win.rootViewController = root; self.win.hidden = NO;
        self.cat = [[RYCatView alloc] initWithFrame:CGRectMake(0, 0, 52, 40)]; [root.view addSubview:self.cat];
        CGSize z = self.win.bounds.size; self.pos = CGPointMake(z.width - 60, z.height * 0.72); self.target = self.pos; self.moving = NO; self.idleSince = CACurrentMediaTime(); self.last = 0; self.key = -1;
        self.cat.center = self.pos;
        self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(step:)]; self.link.preferredFramesPerSecond = 10; [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    for (UIWindow *w in RYAppWindows()) {                               // a tap anywhere in the app, without touching its own touch handling
        if (objc_getAssociatedObject(w, kRYCatTap)) continue;
        UITapGestureRecognizer *t = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
        t.cancelsTouchesInView = NO; t.delaysTouchesBegan = NO; t.delaysTouchesEnded = NO; t.delegate = self;
        [w addGestureRecognizer:t]; objc_setAssociatedObject(w, kRYCatTap, t, OBJC_ASSOCIATION_RETAIN_NONATOMIC); [self.taps addObject:t];
    }
}
- (void)step:(CADisplayLink *)l {
    CFTimeInterval now = CACurrentMediaTime(), dt = self.last ? MIN(now - self.last, 0.05) : 0.016; self.last = now;
    if (self.moving) {
        CGFloat dx = self.target.x - self.pos.x, dy = self.target.y - self.pos.y, d = (CGFloat)sqrt(dx * dx + dy * dy);
        if (d <= 26) { self.moving = NO; self.idleSince = now; self.link.preferredFramesPerSecond = 10; }
        else {
            CGFloat st = MIN(170 * (CGFloat)dt, d - 25); self.pos = CGPointMake(self.pos.x + dx / d * st, self.pos.y + dy / d * st);
            if (fabs(dx) > 2) self.cat.facing = dx >= 0 ? 1 : -1; self.cat.mode = 0; self.cat.phase += (CGFloat)dt * 14;
        }
    }
    if (!self.moving) {
        CFTimeInterval t = now - self.idleSince; self.cat.mode = t > 12 ? 2 : 1; self.cat.phase += (CGFloat)dt * 3;
        self.cat.blink = self.cat.mode == 1 && fmod(now, 3.4) < 0.16;
    }
    CGSize z = self.win.bounds.size; self.pos = CGPointMake(MIN(MAX(self.pos.x, 26), z.width - 26), MIN(MAX(self.pos.y, 20), z.height - 20)); self.cat.center = self.pos;
    long k = self.cat.mode * 100000L + (self.cat.facing > 0 ? 1 : 0) * 10000L + (long)(self.cat.phase * (self.cat.mode == 0 ? 0.9 : 0.4)) % 1000 + (self.cat.blink ? 5000 : 0);
    if (k != self.key) { self.key = k; [self.cat setNeedsDisplay]; }
}
- (void)stop {
    [self.link invalidate]; self.link = nil;
    for (UIWindow *w in RYAppWindows()) { UIGestureRecognizer *t = objc_getAssociatedObject(w, kRYCatTap); if (t) { [w removeGestureRecognizer:t]; objc_setAssociatedObject(w, kRYCatTap, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); } }
    self.win.hidden = YES; self.win = nil; self.cat = nil;
}
@end
static void RYCatTick(void) {
    BOOL want = !RYLocked() && [CF(@"cat", @YES) boolValue]; RYCatCtl *c = [RYCatCtl shared];
    if (want) [c ensure]; else if (c.win) [c stop];
}
static void RYCatSet(BOOL on) { CS(@"cat", @(on)); RYCatTick(); }

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
@property (nonatomic, strong) UIView *fpBar; @property (nonatomic, strong) UIButton *fpFollowBtn, *fpPullBtn, *fpReviewBtn; @property (nonatomic, copy) NSString *fpUid; @property (nonatomic) NSInteger fpMiss;
- (void)fpTick;
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

// magnitude (dB) of one peaking band at frequency f, for drawing the response curve (sample rate 48 kHz)
static double RYEqBandDb(int type, float fc, float g, float q, double f) {
    double o[5]; if (!RYEqCoef(type, fc, g, q, 48000.0, o)) return 0;
    double b0 = o[0], b1 = o[1], b2 = o[2], a1 = o[3], a2 = o[4];
    double w = 2.0 * M_PI * f / 48000.0, c1 = cos(w), c2 = cos(2 * w);
    double num = b0 * b0 + b1 * b1 + b2 * b2 + 2 * (b0 * b1 + b1 * b2) * c1 + 2 * b0 * b2 * c2;
    double den = 1 + a1 * a1 + a2 * a2 + 2 * (a1 + a1 * a2) * c1 + 2 * a2 * c2;
    return den > 0 && num > 0 ? 10.0 * log10(num / den) : 0;
}
@interface RYEQView : UIControl
@property (nonatomic, copy) void (^onLive)(int band);
@property (nonatomic, copy) void (^onEnd)(void);
@property (nonatomic) BOOL editing;   // dots move only while the owner has pressed the edit button
@end
@implementation RYEQView { int _sel; }
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) { self.backgroundColor = [UIColor colorWithRed:0.12 green:0.13 blue:0.16 alpha:1]; self.layer.cornerRadius = 10; self.clipsToBounds = YES; _sel = -1; }
    return self;
}
- (CGRect)plot { return CGRectMake(36, 8, self.bounds.size.width - 44, self.bounds.size.height - 26); }
- (CGFloat)xFor:(double)f { CGRect p = [self plot]; return p.origin.x + p.size.width * (log10(f / 20.0) / 3.0); }
- (double)fFor:(CGFloat)x { CGRect p = [self plot]; return 20.0 * pow(10.0, 3.0 * (x - p.origin.x) / p.size.width); }
- (CGFloat)yFor:(double)g { CGRect p = [self plot]; return p.origin.y + p.size.height * (0.5 - g / 24.0); }
- (double)gFor:(CGFloat)y { CGRect p = [self plot]; return (0.5 - (y - p.origin.y) / p.size.height) * 24.0; }
- (int)nearest:(CGPoint)pt {
    int best = -1; CGFloat bd = 1e9;
    for (int i = 0; i < RYEQ_N; i++) { CGFloat dx = [self xFor:gEqF[i]] - pt.x, dy = [self yFor:gEqG[i]] - pt.y, d = sqrt(dx * dx + dy * dy); if (d < bd) { bd = d; best = i; } }
    return best;
}
- (UIColor *)dotColor:(int)i {
    static NSArray *c; static dispatch_once_t o;
    dispatch_once(&o, ^{ c = @[[UIColor colorWithRed:.62 green:.33 blue:.95 alpha:1], [UIColor colorWithRed:.31 green:.40 blue:.98 alpha:1], [UIColor colorWithRed:1 green:.31 blue:.35 alpha:1], [UIColor colorWithRed:1 green:.45 blue:.30 alpha:1], [UIColor colorWithRed:1 green:.64 blue:.18 alpha:1], [UIColor colorWithRed:.70 green:.95 blue:.15 alpha:1], [UIColor colorWithRed:.05 green:.85 blue:.70 alpha:1], [UIColor colorWithRed:1 green:.25 blue:.60 alpha:1], [UIColor colorWithRed:.10 green:.90 blue:.95 alpha:1], [UIColor colorWithRed:.15 green:.65 blue:1 alpha:1]]; });
    return c[i % 10];
}
- (void)drawRect:(CGRect)r {
    CGContextRef g = UIGraphicsGetCurrentContext(); CGRect p = [self plot];
    NSDictionary *at = @{NSFontAttributeName: [UIFont systemFontOfSize:9], NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.5]};
    CGContextSetLineWidth(g, 1);
    for (NSNumber *f in @[@20, @50, @100, @200, @500, @1000, @2000, @5000, @10000, @20000]) {
        CGFloat x = [self xFor:f.doubleValue]; CGContextSetStrokeColorWithColor(g, [UIColor colorWithWhite:1 alpha:0.07].CGColor);
        CGContextMoveToPoint(g, x, p.origin.y); CGContextAddLineToPoint(g, x, CGRectGetMaxY(p)); CGContextStrokePath(g);
        double v = f.doubleValue; NSString *t = v >= 1000 ? [NSString stringWithFormat:@"%gk", v / 1000] : [NSString stringWithFormat:@"%g", v];
        [t drawAtPoint:CGPointMake(x - 6, CGRectGetMaxY(p) + 4) withAttributes:at];
    }
    for (NSNumber *d in @[@12, @6, @0, @-6, @-12]) {
        CGFloat y = [self yFor:d.doubleValue]; CGContextSetStrokeColorWithColor(g, [UIColor colorWithWhite:1 alpha:d.intValue == 0 ? 0.18 : 0.07].CGColor);
        CGContextMoveToPoint(g, p.origin.x, y); CGContextAddLineToPoint(g, CGRectGetMaxX(p), y); CGContextStrokePath(g);
        [[NSString stringWithFormat:@"%+d", d.intValue] drawAtPoint:CGPointMake(6, y - 5) withAttributes:at];
    }
    CGContextSaveGState(g); CGContextClipToRect(g, p);
    CGContextSetStrokeColorWithColor(g, [UIColor colorWithWhite:1 alpha:gEqOn ? 0.95 : 0.4].CGColor); CGContextSetLineWidth(g, 1.4);
    for (CGFloat x = p.origin.x; x <= CGRectGetMaxX(p); x += 2) {
        double f = [self fFor:x], db = 0; for (int i = 0; i < RYEQ_N; i++) db += RYEqBandDb(gEqT[i], gEqF[i], gEqG[i], gEqQ[i], f);
        db += gEqPre; CGFloat y = [self yFor:MAX(-18, MIN(18, db))];
        if (x == p.origin.x) CGContextMoveToPoint(g, x, y); else CGContextAddLineToPoint(g, x, y);
    }
    CGContextStrokePath(g); CGContextRestoreGState(g);
    for (int i = 0; i < RYEQ_N; i++) {
        CGPoint c = CGPointMake([self xFor:gEqF[i]], [self yFor:gEqG[i]]); CGFloat rad = (i == _sel) ? 8 : 5.5;
        CGContextSetFillColorWithColor(g, [self dotColor:i].CGColor); CGContextFillEllipseInRect(g, CGRectMake(c.x - rad, c.y - rad, rad * 2, rad * 2));
        if (i == _sel) { CGContextSetStrokeColorWithColor(g, UIColor.whiteColor.CGColor); CGContextSetLineWidth(g, 2); CGContextStrokeEllipseInRect(g, CGRectMake(c.x - rad, c.y - rad, rad * 2, rad * 2)); }
    }
}
- (BOOL)beginTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    if (!self.editing) return NO;
    _sel = [self nearest:[t locationInView:self]]; if (_sel < 0) return NO;
    [self setNeedsDisplay]; if (self.onLive) self.onLive(_sel); return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    if (_sel < 0) return NO;
    CGPoint pt = [t locationInView:self];
    double lo = _sel > 0 ? gEqF[_sel - 1] * 1.06 : 20.0, hi = _sel < RYEQ_N - 1 ? gEqF[_sel + 1] / 1.06 : 20000.0;
    double f = MAX(lo, MIN(hi, [self fFor:pt.x])), g = MAX(-12.0, MIN(12.0, [self gFor:pt.y]));
    gEqF[_sel] = (float)f; gEqG[_sel] = (float)g; gEqVer++;
    [self setNeedsDisplay]; if (self.onLive) self.onLive(_sel); return YES;
}
- (void)endTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e { _sel = -1; [self setNeedsDisplay]; if (self.onEnd) self.onEnd(); }
- (void)cancelTrackingWithEvent:(UIEvent *)e { _sel = -1; [self setNeedsDisplay]; if (self.onEnd) self.onEnd(); }
@end

// --- 8ubah plugin feature flags -------------------------------------------------------------------
// The "الإضافات" (Plugins) tab writes Documents/pyoncord/8ubah-features.json as { "<id>": true/false }.
// The JS side (8ubah Controller plugin) reads the same file and starts/stops the matching plugins, so
// the switches here drive the real JS plugins. This file is plain JSON both sides agree on.
static NSString *RYFeaturesPath(void) {
    NSURL *docs = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    if (!docs) return nil;
    return [[docs.path stringByAppendingPathComponent:@"pyoncord"] stringByAppendingPathComponent:@"8ubah-features.json"];
}
static NSMutableDictionary *RYFeaturesLoad(void) {
    @try {
        NSString *p = RYFeaturesPath();
        NSData *d = p ? [NSData dataWithContentsOfFile:p] : nil;
        id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
        if ([j isKindOfClass:NSDictionary.class]) return [j mutableCopy];
    } @catch (__unused id e) {}
    return [NSMutableDictionary new];
}
static void RYFeatureSet(NSString *pid, BOOL on) {
    @try {
        NSMutableDictionary *m = RYFeaturesLoad();
        m[pid] = @(on);
        NSString *p = RYFeaturesPath(); if (!p) return;
        [[NSFileManager defaultManager] createDirectoryAtPath:[p stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
        NSData *out = [NSJSONSerialization dataWithJSONObject:m options:0 error:nil];
        if (out) [out writeToFile:p atomically:YES];
    } @catch (__unused id e) {}
}

// --- 8ubah per-plugin config (Documents/pyoncord/8ubah-config.json) --------------------------------
// { "<plugin id>": { ...fields... } }. The ⚙️ config screens in the Plugins tab write this; the JS
// plugins (RPC, Dont Control Me) read it, so the panel drives their behaviour. JSON both sides agree on.
static NSString *RYConfigPath(void) {
    NSURL *docs = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    if (!docs) return nil;
    return [[docs.path stringByAppendingPathComponent:@"pyoncord"] stringByAppendingPathComponent:@"8ubah-config.json"];
}
static NSMutableDictionary *RYConfigLoad(void) {
    @try {
        NSString *p = RYConfigPath();
        NSData *d = p ? [NSData dataWithContentsOfFile:p] : nil;
        id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
        if ([j isKindOfClass:NSDictionary.class]) return [j mutableCopy];
    } @catch (__unused id e) {}
    return [NSMutableDictionary new];
}
static NSDictionary *RYConfigFor(NSString *pid) {
    id v = RYConfigLoad()[pid];
    return [v isKindOfClass:NSDictionary.class] ? v : @{};
}
static void RYConfigSet(NSString *pid, NSString *key, id value) {
    @try {
        NSMutableDictionary *all = RYConfigLoad();
        NSMutableDictionary *sub = [RYConfigFor(pid) mutableCopy];
        if (value) sub[key] = value; else [sub removeObjectForKey:key];
        all[pid] = sub;
        NSString *p = RYConfigPath(); if (!p) return;
        [[NSFileManager defaultManager] createDirectoryAtPath:[p stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
        NSData *out = [NSJSONSerialization dataWithJSONObject:all options:0 error:nil];
        if (out) [out writeToFile:p atomically:YES];
    } @catch (__unused id e) {}
}

@interface RYPanel : UIViewController <PHPickerViewControllerDelegate, UIDocumentPickerDelegate, UIColorPickerViewControllerDelegate>
@property (nonatomic) NSInteger tab;
@property (nonatomic, copy) NSString *expandedPlugin;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UILabel *invLabel;
@property (nonatomic, strong) NSTimer *invUI;
@property (nonatomic, strong) UISlider *stSlider;
@property (nonatomic, strong) UILabel *stTimeLabel;
@property (nonatomic, strong) NSTimer *stUI;
@property (nonatomic) BOOL stDragging; // true while the user's finger is on the slider: stop auto-updating it so it doesn't fight the drag
@property (nonatomic) BOOL eqEdit;   // equalizer edit mode: scrolling and sheet dragging are frozen so only the dots move
@property (nonatomic, weak) UIScrollView *mainScroll;
@property (nonatomic, strong) NSString *pickPurpose; // routes the shared PHPicker callback: nil/"bg" = background image, "stereo" = Stereo video
@end

@implementation RYPanel
- (void)viewDidLoad { [super viewDidLoad]; [self rebuild]; }
- (void)applyEditLock {
    BOOL e = self.eqEdit && self.tab == 5; static BOOL last = NO;
    self.mainScroll.scrollEnabled = !e; self.modalInPresentation = e;
    UISheetPresentationController *sp = self.sheetPresentationController;
    if (sp && e != last) { last = e;
        sp.detents = e ? @[UISheetPresentationControllerDetent.largeDetent] : @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
        sp.prefersGrabberVisible = !e; sp.prefersScrollingExpandsWhenScrolledToEdge = !e;
        if (e) sp.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
    }
}
- (void)viewDidDisappear:(BOOL)a { [super viewDidDisappear:a]; [self.invUI invalidate]; self.invUI = nil; if (self.isBeingDismissed) [[RYCore shared] panelClosed]; }
// (equalizer edit lock is released by rebuild / dismiss)

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

- (void)secretDiag:(UILongPressGestureRecognizer *)g { if (g.state == UIGestureRecognizerStateBegan) { self.tab = 7; [self rebuild]; } } // long-press the 8ubah logo
- (void)rebuild {
    for (UIView *v in self.view.subviews) [v removeFromSuperview];
    __weak typeof(self) ws = self;
    self.view.backgroundColor = RY_BG; self.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; self.view.semanticContentAttribute = RYSem();

    // brand mark: a glowing purple tile with "8", next to the 8ubah wordmark
    UILabel *mark = RYLabel(@"8", 17, UIFontWeightHeavy, UIColor.whiteColor); mark.textAlignment = NSTextAlignmentCenter;
    UIView *markBox = [UIView new]; markBox.backgroundColor = RYAccent(); markBox.layer.cornerRadius = 9; markBox.layer.cornerCurve = kCACornerCurveContinuous;
    markBox.layer.shadowColor = RYAccent().CGColor; markBox.layer.shadowOpacity = 0.6; markBox.layer.shadowRadius = 8; markBox.layer.shadowOffset = CGSizeMake(0, 2); markBox.layer.masksToBounds = NO;
    [markBox addSubview:mark]; RYPin(mark, markBox, 0);
    [markBox.widthAnchor constraintEqualToConstant:30].active = YES; [markBox.heightAnchor constraintEqualToConstant:30].active = YES;
    UILongPressGestureRecognizer *diagLP = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(secretDiag:)];
    diagLP.minimumPressDuration = 1.2; markBox.userInteractionEnabled = YES; [markBox addGestureRecognizer:diagLP]; // owner-only Diag access (hidden)
    UILabel *title = RYLabel(@"8ubah", 23, UIFontWeightHeavy, nil); title.numberOfLines = 1;
    UIView *spacer = [UIView new]; [spacer setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    UIButtonConfiguration *cc = [UIButtonConfiguration grayButtonConfiguration];
    cc.image = [UIImage systemImageNamed:@"xmark"]; cc.baseBackgroundColor = RY_CARD2; cc.baseForegroundColor = RY_DIM; cc.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    cc.contentInsets = NSDirectionalEdgeInsetsMake(8, 8, 8, 8);
    UIButton *close = [UIButton buttonWithConfiguration:cc primaryAction:[UIAction actionWithHandler:^(UIAction *a) { [ws dismissViewControllerAnimated:YES completion:nil]; }]];
    UIStackView *head = RYHStack(@[markBox, title, spacer, close], 10);
    UIScrollView *tabsScroll = [UIScrollView new]; tabsScroll.showsHorizontalScrollIndicator = NO;
    NSArray *names = @[T(@"مايك", @"Mic"), T(@"ستيريو", @"Stereo"), T(@"الخلفيات", @"Backgrounds"), @"Fake Defen", T(@"القطوة", @"Cat"), T(@"عوازل", @"Isolation"), T(@"تسجيل", @"Record"), @"Diag", T(@"الإضافات", @"Plugins")];
    NSArray *icons = @[@"mic.fill", @"waveform", @"photo.fill", @"shield.lefthalf.filled", @"pawprint.fill", @"slider.vertical.3", @"record.circle.fill", @"waveform.path.ecg", @"puzzlepiece.extension.fill"];
    // tab order: Plugins first, then Mic, Stereo, Backgrounds, Fake Defen, Isolation, Record, Cat (scrolls into view)
    NSArray<NSNumber *> *order = @[@8, @0, @1, @2, @3, @5, @6, @4]; // Diag (7) hidden from the tab bar; opened by long-pressing the 8ubah logo
    if (self.tab < 0 || self.tab > 8) self.tab = 0;
    NSMutableArray *tb = [NSMutableArray new];
    for (NSNumber *nn in order) { NSInteger i = nn.integerValue; [tb addObject:RYIconTab(names[i], icons[i], i == self.tab, ^{ ws.tab = i; [ws rebuild]; })]; }
    tabsScroll.hidden = NO;
    [self.invUI invalidate]; self.invUI = nil; self.invLabel = nil;
    UIStackView *tabStack = RYHStack(tb, 8); tabStack.alignment = UIStackViewAlignmentFill;
    UIScrollView *scroll = [UIScrollView new]; scroll.alwaysBounceVertical = YES; scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.stack = RYVStack(@[], 12); self.mainScroll = scroll;

    for (UIView *v in @[head, tabsScroll, scroll]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:v]; }
    [tabsScroll addSubview:tabStack]; [scroll addSubview:self.stack];
    tabStack.translatesAutoresizingMaskIntoConstraints = NO; self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    UILayoutGuide *sg = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [head.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:18],
        [head.leadingAnchor constraintEqualToAnchor:sg.leadingAnchor constant:16], [head.trailingAnchor constraintEqualToAnchor:sg.trailingAnchor constant:-16],
        [tabsScroll.topAnchor constraintEqualToAnchor:head.bottomAnchor constant:12],
        [tabsScroll.leadingAnchor constraintEqualToAnchor:sg.leadingAnchor], [tabsScroll.trailingAnchor constraintEqualToAnchor:sg.trailingAnchor],
        [tabsScroll.heightAnchor constraintEqualToConstant:58],
        [tabStack.topAnchor constraintEqualToAnchor:tabsScroll.contentLayoutGuide.topAnchor], [tabStack.bottomAnchor constraintEqualToAnchor:tabsScroll.contentLayoutGuide.bottomAnchor],
        [tabStack.leadingAnchor constraintEqualToAnchor:tabsScroll.contentLayoutGuide.leadingAnchor constant:16], [tabStack.trailingAnchor constraintEqualToAnchor:tabsScroll.contentLayoutGuide.trailingAnchor constant:-16],
        [tabStack.heightAnchor constraintEqualToAnchor:tabsScroll.frameLayoutGuide.heightAnchor],
        [scroll.topAnchor constraintEqualToAnchor:tabsScroll.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:sg.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:sg.trailingAnchor], [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:8],
        [self.stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16], [self.stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [self.stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-60],
        [self.stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32]]];

    if (self.tab != 5) self.eqEdit = NO;
    [self applyEditLock];
    if (RYLocked()) { tabsScroll.hidden = YES; [self renderLocked]; return; }
    switch (self.tab) { case 0: [self renderMic]; break; case 1: [self renderStereo]; break; case 3: [self renderFake]; break; case 4: [self renderCat]; break; case 5: [self renderEQ]; break; case 6: [self renderRec]; break; case 7: [self renderDiag]; break; case 8: [self renderPlugins]; break; default: [self renderBG]; }
}
#pragma mark Locked
- (void)renderLocked {
    __weak typeof(self) ws = self;
    // glowing 8ubah mark
    UILabel *mk = RYLabel(@"8", 34, UIFontWeightHeavy, UIColor.whiteColor); mk.textAlignment = NSTextAlignmentCenter;
    UIView *box = [UIView new]; box.backgroundColor = RYAccent(); box.layer.cornerRadius = 18; box.layer.cornerCurve = kCACornerCurveContinuous;
    box.layer.shadowColor = RYAccent().CGColor; box.layer.shadowOpacity = 0.8; box.layer.shadowRadius = 22; box.layer.shadowOffset = CGSizeZero; box.layer.masksToBounds = NO;
    [box addSubview:mk]; RYPin(mk, box, 0);
    [box.widthAnchor constraintEqualToConstant:76].active = YES; [box.heightAnchor constraintEqualToConstant:76].active = YES;
    UILabel *word = RYLabel(@"8ubah", 26, UIFontWeightHeavy, nil); word.textAlignment = NSTextAlignmentCenter;
    UIView *status = RYPill(T(@"مقفل", @"Locked"), RY_MUTED);
    UIButton *unlock = RYBtn(T(@"فتح", @"Unlock"), YES, ^{
        [ws ask:T(@"المفتاح", @"Key") ph:@"XXXX-XXXX-XXXX-XXXX" secure:NO ok:^(NSString *k) {
            if (!k.length) return;
            RYLicActivate(k, ^(BOOL ok, NSString *reason) { if (ok) [ws rebuild]; else [ws toast:reason.length ? [NSString stringWithFormat:@"%@ (%@)", T(@"المفتاح غلط", @"Wrong key"), reason] : T(@"المفتاح غلط", @"Wrong key")]; });
        }];
    });
    UIStackView *col = RYVStack(@[box, word, status, unlock], 16); col.alignment = UIStackViewAlignmentCenter;
    UIView *card = RYCard(@[col]);
    [self.stack addArrangedSubview:card];
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
    [self.stack addArrangedSubview:RYCard(@[RYSection(@"photo.fill", T(@"خلفية الغرفة", @"Room background"), nil), RYHStack(@[photo, url], 8)])];

    NSMutableArray *sw = [NSMutableArray new];
    for (NSString *h in @[@"#000000", @"#111827", @"#1E1B4B", @"#052E16", @"#450A0A", @"#3B0764", @"#0C4A6E", @"#78350F"]) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom]; b.backgroundColor = RYHex(h); b.layer.cornerRadius = 10; b.layer.borderWidth = 1; b.layer.borderColor = RY_MUTED.CGColor;
        [b addAction:[UIAction actionWithHandler:^(UIAction *a) { [ws setBG:@"color" value:h]; [ws toast:T(@"تم", @"Done")]; }] forControlEvents:UIControlEventTouchUpInside];
        [b.heightAnchor constraintEqualToConstant:40].active = YES; [sw addObject:b];
    }
    UIButton *custom = RYBtn(T(@"لون مخصص", @"Custom colour"), NO, ^{
        ws.pickPurpose = nil; UIColorPickerViewController *cp = [UIColorPickerViewController new]; cp.delegate = ws; [ws presentViewController:cp animated:YES completion:nil];
    });
    [self.stack addArrangedSubview:RYCard(@[RYSection(@"paintpalette.fill", T(@"لون ثابت", @"Solid colour"), nil), RYGrid(sw, 4), custom])];

    NSMutableArray *gs = [NSMutableArray new];
    for (NSString *g in @[@"#0F2027,#2C5364", @"#41295A,#2F0743", @"#FF512F,#DD2476", @"#00C6FF,#0072FF", @"#11998E,#38EF7D", @"#232526,#414345"]) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom]; [b setBackgroundImage:RYGradImage(g) forState:UIControlStateNormal]; b.layer.cornerRadius = 10; b.clipsToBounds = YES;
        [b addAction:[UIAction actionWithHandler:^(UIAction *a) { [ws setBG:@"gradient" value:g]; [ws toast:T(@"تم", @"Done")]; }] forControlEvents:UIControlEventTouchUpInside];
        [b.heightAnchor constraintEqualToConstant:44].active = YES; [gs addObject:b];
    }
    [self.stack addArrangedSubview:RYCard(@[RYSection(@"circle.hexagongrid.fill", T(@"تدرجات", @"Gradients"), nil), RYGrid(gs, 3)])];

    [self.stack addArrangedSubview:RYSlider(T(@"التمويه (Blur)", @"Blur"), 0, 100, [CF(@"blur", @0) floatValue], ^(float v) { CS(@"blur", @(v)); [[RYCore shared] bump]; })];
    [self.stack addArrangedSubview:RYSlider(T(@"التعتيم (Dim)", @"Dim"), 0, 100, [CF(@"dim", @30) floatValue], ^(float v) { CS(@"dim", @(v)); [[RYCore shared] bump]; })];
    { NSString *tm = CF(@"txtMode", @"off"); if (![tm isEqual:@"custom"]) tm = @"off";
      UIButton *tC = RYBtn(T(@"لون مخصص", @"Custom"), [tm isEqual:@"custom"], ^{
          ws.pickPurpose = @"txt"; UIColorPickerViewController *cp = [UIColorPickerViewController new]; cp.delegate = ws; cp.supportsAlpha = NO;
          cp.selectedColor = RYHex(CF(@"txtColor", @"#FFFFFF")); [ws presentViewController:cp animated:YES completion:nil]; });
      UIButton *tO = RYBtn(T(@"افتراضي", @"Default"), [tm isEqual:@"off"], ^{
          CS(@"txtMode", @"off"); [[RYCore shared] bump]; [ws rebuild];
          dispatch_async(dispatch_get_main_queue(), ^{ UIView *h = RYChatHost(); if (!h) return; NSMutableArray *tabs = [NSMutableArray new]; RYCollectTables(h, tabs, 0); for (UITableView *tv in tabs) [tv reloadData]; });   // cells already tinted get the app's own colours back
      });
      [self.stack addArrangedSubview:RYCard(@[RYSection(@"textformat", T(@"لون كلام الناس", @"Message text colour"), nil), RYHStack(@[tC, tO], 8)])]; }
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
    [self.stack addArrangedSubview:RYCard(@[RYSection(@"waveform", T(@"ملف الصوت أو الفيديو", @"Audio/video file"), nil),
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
    [self.stack addArrangedSubview:RYCard(@[RYHStack(@[RYLabel(T(@"أسمع الملف أنا كمان", @"Hear it myself"), 14, UIFontWeightMedium, nil), hm], 12)])];
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
    [self.stack addArrangedSubview:RYSliderV(T(@"الصدى (كهف مسكون)", @"Echo (Haunted Cavern)"), @"", 0, 100, (float)gRevSong, NO, 0, ^(float v) { RYSetRevSong((int)lroundf(v)); })];
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

#pragma mark Plugins
- (void)renderPlugins {
    __weak typeof(self) ws = self;
    NSArray *ids = @[@"8ubah.rpc", @"8ubah.statusrotator", @"8ubah.noblocked", @"8ubah.callidle", @"8ubah.relnotify", @"8ubah.hidden", @"8ubah.questify", @"8ubah.dontcontrol", @"8ubah.reviewdb"];
    NSArray *titles = @[T(@"حالة مخصّصة (RPC)", @"Custom RPC"), T(@"تدوير الحالة", @"Status Rotator"), T(@"إظهار المحظورين", @"Show blocked msgs"), T(@"بدون طرد الخمول", @"No call idle"), T(@"منبّه العلاقات", @"Relationship alerts"), T(@"القنوات المخفية", @"Hidden channels"), T(@"إكمال المهام", @"Complete quests"), T(@"لا تتحكم فيّ", @"Dont control me"), T(@"ريفيو (ReviewDB)", @"ReviewDB")];
    NSArray *syms = @[@"gamecontroller.fill", @"arrow.triangle.2.circlepath", @"eye.fill", @"phone.fill", @"bell.fill", @"lock.open.fill", @"checkmark.seal.fill", @"hand.raised.fill", @"star.bubble.fill"];
    NSArray *hasCfg = @[@YES, @YES, @NO, @NO, @NO, @NO, @NO, @YES, @NO]; // RPC, Status Rotator, Dont Control Me have a ⚙️
    NSDictionary *flags = RYFeaturesLoad();
    for (NSUInteger i = 0; i < ids.count; i++) {
        NSString *pid = ids[i];
        UISwitch *sw = RYSwitch([flags[pid] boolValue], nil, ^(BOOL v) { RYFeatureSet(pid, v); });
        UIView *trailing = sw;
        if ([hasCfg[i] boolValue]) {
            UIButton *gear = RYBtn(@"⚙︎", NO, ^{
                ws.expandedPlugin = [ws.expandedPlugin isEqualToString:pid] ? nil : pid;
                [ws rebuild];
            });
            trailing = RYHStack(@[gear, sw], 10);
        }
        [self.stack addArrangedSubview:RYCard(@[RYSection(syms[i], titles[i], trailing)])];
        if ([self.expandedPlugin isEqualToString:pid]) {
            if ([pid isEqualToString:@"8ubah.rpc"]) [self renderRpcConfig];
            else if ([pid isEqualToString:@"8ubah.statusrotator"]) [self renderRotatorConfig];
            else if ([pid isEqualToString:@"8ubah.dontcontrol"]) [self renderDcmConfig];
        }
    }
    UILabel *note = RYLabel(T(@"شغّل بالمفتاح، واضغط ⚙︎ عشان تعدّل. يثبت ويطبّق داخل ديسكورد تلقائياً.", @"Toggle with the switch, tap ⚙︎ to configure. Persists and applies in Discord."), 13, UIFontWeightMedium, RY_MUTED);
    note.numberOfLines = 0;
    [self.stack addArrangedSubview:RYCard(@[note])];
}

// one tappable "label: value" row that opens a text prompt to edit a config field
- (void)addCfgField:(NSString *)pid key:(NSString *)key label:(NSString *)label value:(NSString *)val {
    __weak typeof(self) ws = self;
    NSString *shown = val.length ? val : T(@"— اضغط للتعديل", @"— tap to set");
    UIButton *row = RYBtn([NSString stringWithFormat:@"%@: %@", label, shown], NO, ^{
        [ws ask:label ph:@"" secure:NO ok:^(NSString *v) { RYConfigSet(pid, key, v ?: @""); [ws rebuild]; }];
    });
    [self.stack addArrangedSubview:RYCard(@[row])];
}

- (void)renderRpcConfig {
    __weak typeof(self) ws = self;
    NSDictionary *c = RYConfigFor(@"8ubah.rpc");
    NSString *(^S)(NSString *) = ^NSString *(NSString *k){ id v = c[k]; return [v isKindOfClass:NSString.class] ? v : @""; };
    [self addCfgField:@"8ubah.rpc" key:@"name"    label:T(@"اسم اللعبة", @"Game name") value:S(@"name")];
    [self addCfgField:@"8ubah.rpc" key:@"details" label:T(@"السطر الأول", @"Details")    value:S(@"details")];
    [self addCfgField:@"8ubah.rpc" key:@"state"   label:T(@"السطر الثاني", @"State")     value:S(@"state")];
    [self addCfgField:@"8ubah.rpc" key:@"image"   label:T(@"صورة (رابط)", @"Image URL")  value:S(@"image")];
    [self addCfgField:@"8ubah.rpc" key:@"button1"      label:T(@"زر: نص", @"Button text") value:S(@"button1")];
    [self addCfgField:@"8ubah.rpc" key:@"button1url"   label:T(@"زر: رابط", @"Button URL") value:S(@"button1url")];
    NSArray *typeNames = @[T(@"يلعب", @"Playing"), T(@"يبث", @"Streaming"), T(@"يسمع", @"Listening"), T(@"يشاهد", @"Watching"), T(@"ينافس", @"Competing")];
    NSArray *typeVals = @[@0, @1, @2, @3, @5];
    NSInteger curType = [c[@"type"] isKindOfClass:NSNumber.class] ? [c[@"type"] integerValue] : 0;
    NSUInteger ti = [typeVals indexOfObject:@(curType)]; if (ti == NSNotFound) ti = 0;
    UIButton *typeBtn = RYBtn([NSString stringWithFormat:@"%@: %@", T(@"النوع", @"Type"), typeNames[ti]], NO, ^{
        NSUInteger ni = (ti + 1) % typeVals.count;
        RYConfigSet(@"8ubah.rpc", @"type", typeVals[ni]); [ws rebuild];
    });
    [self.stack addArrangedSubview:RYCard(@[typeBtn])];
}

- (void)renderRotatorConfig {
    __weak typeof(self) ws = self;
    NSDictionary *c = RYConfigFor(@"8ubah.statusrotator");
    NSString *lines = [c[@"lines"] isKindOfClass:NSString.class] ? c[@"lines"] : @"";
    NSString *emoji = [c[@"emoji"] isKindOfClass:NSString.class] ? c[@"emoji"] : @"";
    NSInteger iv = [c[@"interval"] isKindOfClass:NSNumber.class] ? [c[@"interval"] integerValue] : 30;
    [self addCfgField:@"8ubah.statusrotator" key:@"lines" label:T(@"الحالات (افصلها بـ |)", @"Statuses (| separated)") value:lines];
    [self addCfgField:@"8ubah.statusrotator" key:@"emoji" label:T(@"إيموجي", @"Emoji") value:emoji];
    UIButton *ivBtn = RYBtn([NSString stringWithFormat:@"%@: %ld ث", T(@"كل كم ثانية", @"Interval (s)"), (long)iv], NO, ^{
        [ws ask:T(@"كل كم ثانية (10+)", @"Interval seconds (10+)") ph:@"30" secure:NO ok:^(NSString *v) {
            NSInteger n = v.integerValue; if (n < 10) n = 10; RYConfigSet(@"8ubah.statusrotator", @"interval", @(n)); [ws rebuild];
        }];
    });
    [self.stack addArrangedSubview:RYCard(@[ivBtn])];
}

- (void)renderDcmConfig {
    NSDictionary *c = RYConfigFor(@"8ubah.dontcontrol");
    BOOL am = c[@"antiMove"] ? [c[@"antiMove"] boolValue] : YES;
    BOOL ad = c[@"antiDisconnect"] ? [c[@"antiDisconnect"] boolValue] : YES;
    UISwitch *s1 = RYSwitch(am, nil, ^(BOOL v){ RYConfigSet(@"8ubah.dontcontrol", @"antiMove", @(v)); });
    UISwitch *s2 = RYSwitch(ad, nil, ^(BOOL v){ RYConfigSet(@"8ubah.dontcontrol", @"antiDisconnect", @(v)); });
    [self.stack addArrangedSubview:RYCard(@[RYSection(@"arrow.uturn.left", T(@"يرجّعك لو سحبوك", @"Anti-move"), s1)])];
    [self.stack addArrangedSubview:RYCard(@[RYSection(@"arrow.uturn.left.circle", T(@"يرجّعك لو فصلوك", @"Anti-disconnect"), s2)])];
}

#pragma mark Mic
- (void)renderMic {
    __weak typeof(self) ws = self;
    UISwitch *siso = [UISwitch new]; siso.on = gIsoOn != 0; siso.onTintColor = RYAccent(); __weak UISwitch *wsiso = siso;
    [siso addAction:[UIAction actionWithHandler:^(UIAction *a) { RYMicSetIso(wsiso.on); [ws toast:wsiso.on ? T(@"انطفت العوازل — اقفل الغرفة وارجع لها", @"Isolation off — rejoin the voice room") : T(@"رجعت العوازل", @"Isolation back on")]; }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYSection(@"shield.slash.fill", T(@"إطفاء كل العوازل", @"Disable all isolation"), siso)])];
    UISwitch *smute = [UISwitch new]; smute.on = gMicMute != 0; smute.onTintColor = UIColor.systemRedColor; __weak UISwitch *wsmute = smute;
    [smute addAction:[UIAction actionWithHandler:^(UIAction *a) { RYMicSetMute(wsmute.on); [ws rebuild]; }] forControlEvents:UIControlEventValueChanged];
    UIView *muteCard = RYCard(@[RYSection(@"mic.slash.fill", T(@"سكر صوتي", @"Kill mic"), smute)]);
    [self.stack addArrangedSubview:muteCard];
    UISwitch *sw = RYSwitch(gMicOn != 0, nil, ^(BOOL on) { RYMicSetOn(on); });
    NSArray *vIcons = @[@"waveform", @"person.fill", @"flame.fill", @"person.fill", @"figure.child", @"hare.fill", @"cpu", @"megaphone.fill", @"dot.radiowaves.left.and.right", @"waveform.path.ecg"];
    NSMutableArray *bs = [NSMutableArray new];
    for (int i = 0; i < RY_NPRESETS; i++) {
        NSString *nm = [NSString stringWithUTF8String:RYAr() ? kPresets[i].ar : kPresets[i].en];
        NSString *sym = i < (int)vIcons.count ? vIcons[i] : @"waveform";
        [bs addObject:RYAvatar(nm, sym, i == gMicPreset, ^{ RYMicApplyPreset(i); RYMicSetOn(YES); [ws rebuild]; })];
    }
    [self.stack addArrangedSubview:RYCard(@[RYSection(@"mic.fill", T(@"مغيّر الصوت", @"Voice Changer"), sw), RYAvatarRow(bs)])];
    [self.stack addArrangedSubview:RYSlider(T(@"درجة الصوت (نغمات)", @"Pitch (semitones)"), -12, 12, gMicSemi, ^(float v) { gMicSemi = v; gMicPreset = -1; CS(@"micSemi", @(v)); CS(@"micPreset", @(-1)); })];
    [self.stack addArrangedSubview:RYSlider(T(@"الصدى", @"Echo"), 0, 1, gMicEcho, ^(float v) { gMicEcho = v; CS(@"micEcho", @(v)); })];
    [self.stack addArrangedSubview:RYSlider(T(@"مستوى المايك", @"Mic level"), 0.5, 2, gMicGain, ^(float v) { gMicGain = v; CS(@"micGain", @(v)); })];
    UISwitch *s1 = [UISwitch new]; s1.on = gMicDist != 0; s1.onTintColor = RYAccent(); __weak UISwitch *ws1 = s1;
    [s1 addAction:[UIAction actionWithHandler:^(UIAction *a) { RYMicSetDist(ws1.on); }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYSection(@"sparkles", T(@"فضي", @"Silver"), nil),
        RYHStack(@[RYLabel(T(@"مضخم", @"Amplifier"), 14, UIFontWeightMedium, nil), s1], 12)])];
    [self.stack addArrangedSubview:RYSliderV(T(@"الصدى (كهف مسكون)", @"Echo (Haunted Cavern)"), @"", 0, 100, (float)gRevMic, NO, 0, ^(float v) { RYSetRevMic((int)lroundf(v)); })];
    UISwitch *s3 = [UISwitch new]; s3.on = gMonOn != 0; s3.onTintColor = RYAccent(); __weak UISwitch *ws3 = s3;
    [s3 addAction:[UIAction actionWithHandler:^(UIAction *a) { if (ws3.on) RYMonStart(); else RYMonStop(); }] forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:RYCard(@[RYSection(@"ear.fill", T(@"اسمع صوتي", @"Hear my voice"), s3)])];
        // ---- amplifier settings
    [self.stack addArrangedSubview:RYCard(@[RYSection(@"dial.high.fill", T(@"إعدادات المضخم", @"Amplifier settings"), nil)])];
    [self.stack addArrangedSubview:RYSliderV(T(@"التضخيم", @"Gain"), @"dB", 0, 120, [CF(@"distDb", @60) floatValue], NO, 0, ^(float v) { gDistGain = powf(10.f, v / 20.f); CS(@"distDb", @(v)); })];
    [self.stack addArrangedSubview:RYSliderV(T(@"مستوى الخروج", @"Output"), @"dB", -30, 0, [CF(@"distOutDb", @-3) floatValue], NO, 0, ^(float v) { gDistOut = powf(10.f, v / 20.f); CS(@"distOutDb", @(v)); })];
    [self.stack addArrangedSubview:RYSliderV(T(@"عتبة الكتم", @"Gate"), @"dB", -80, -30, [CF(@"distGateDb", @-55) floatValue], NO, 0, ^(float v) { gDistGate = powf(10.f, v / 20.f); CS(@"distGateDb", @(v)); })];
    [self.invUI invalidate]; self.invUI = nil; self.invLabel = nil; // diagnostics hidden
}

#pragma mark Diag
static UIView *RYSw(NSString *title, BOOL on, UIColor *tint, void (^chg)(BOOL)) {
    UISwitch *sw = [UISwitch new]; sw.on = on; sw.onTintColor = tint ?: RYAccent(); __weak UISwitch *w = sw;
    [sw addAction:[UIAction actionWithHandler:^(UIAction *a) { if (w && chg) chg(w.on); }] forControlEvents:UIControlEventValueChanged];
    UILabel *l = RYLabel(title, 15, UIFontWeightSemibold, nil); [l setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    return RYHStack(@[l, sw], 12);
}
static UIView *RYSl(NSString *lo, NSString *hi, NSString *unit, float mn, float mx, float val, int dec, BOOL enabled, void (^chg)(float)) {
    UISlider *s = [UISlider new]; s.minimumValue = mn; s.maximumValue = mx; s.value = val; s.minimumTrackTintColor = RYAccent(); s.maximumTrackTintColor = RY_CARD2; s.enabled = enabled;
    UILabel *l = RYLabel(unit.length ? [NSString stringWithFormat:@"%.*f %@", dec, val, unit] : [NSString stringWithFormat:@"%.*f", dec, val], 13, UIFontWeightMedium, RY_MUTED); l.numberOfLines = 1;
    [l.widthAnchor constraintEqualToConstant:74].active = YES; l.textAlignment = NSTextAlignmentCenter;
    __weak UISlider *ws = s; __weak UILabel *wl = l;
    [s addAction:[UIAction actionWithHandler:^(UIAction *a) { if (!ws) return; float v = ws.value; wl.text = unit.length ? [NSString stringWithFormat:@"%.*f %@", dec, v, unit] : [NSString stringWithFormat:@"%.*f", dec, v]; if (chg) chg(v); }] forControlEvents:UIControlEventTouchDragInside | UIControlEventValueChanged];
    NSMutableArray *row = [NSMutableArray new]; if (lo.length) [row addObject:RYLabel(lo, 12, UIFontWeightRegular, RY_MUTED)]; [row addObject:s]; if (hi.length) [row addObject:RYLabel(hi, 12, UIFontWeightRegular, RY_MUTED)]; [row addObject:l];
    UIStackView *h = RYHStack(row, 8); h.alpha = enabled ? 1 : 0.4; return h;
}
- (void)renderEQ {
    __weak typeof(self) ws = self;
    NSString *cur = CF(@"eqName", @"Flat"); if (![cur isKindOfClass:NSString.class]) cur = @"Flat";
    NSArray<NSDictionary *> *all = RYEqAllPresets();
    // ---- preset header: name (menu), favourite star, more (menu)
    NSMutableArray *items = [NSMutableArray new];
    for (NSDictionary *d in all) { NSString *n = d[@"n"]; [items addObject:[UIAction actionWithTitle:n image:nil identifier:nil handler:^(UIAction *a) { RYEqApplyDict(d); [ws rebuild]; }]]; }
    UIButton *nameBtn = RYBtn(cur, NO, nil); nameBtn.menu = [UIMenu menuWithTitle:@"" children:items]; nameBtn.showsMenuAsPrimaryAction = YES;
    NSMutableArray *fav = [NSMutableArray new]; { NSArray *fo = CF(@"eqFav", nil); if ([fo isKindOfClass:NSArray.class]) for (id n in fo) if ([n isKindOfClass:NSString.class]) [fav addObject:n]; }
    BOOL isFav = [fav containsObject:cur];
    UIButton *star = RYBtn(isFav ? @"★" : @"☆", isFav, ^{
        NSMutableArray *f2 = [fav mutableCopy];
        if ([f2 containsObject:cur]) [f2 removeObject:cur]; else if (f2.count < 9) [f2 addObject:cur]; else { [ws toast:T(@"المفضلة ممتلئة", @"Favorites full")]; return; }
        CS(@"eqFav", f2); [ws rebuild];
    });
    NSMutableArray *more = [NSMutableArray new];
    [more addObject:[UIAction actionWithTitle:T(@"حفظ", @"Save") image:nil identifier:nil handler:^(UIAction *a) {
        [ws ask:T(@"اسم الوزنية", @"Preset name") ph:cur secure:NO ok:^(NSString *n) { n = [n stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if (!n.length) n = cur;
            if (RYEqIsBuiltin(n)) { [ws toast:T(@"الاسم محجوز", @"Name is reserved")]; return; } RYEqSaveUser(n); [ws rebuild]; }];
    }]];
    if (!RYEqIsBuiltin(cur)) [more addObject:[UIAction actionWithTitle:T(@"حذف", @"Delete") image:nil identifier:nil handler:^(UIAction *a) { RYEqDeleteUser(cur); RYEqReset(); [ws rebuild]; }]];
    [more addObject:[UIAction actionWithTitle:T(@"رجوع للافتراضي", @"Reset") image:nil identifier:nil handler:^(UIAction *a) { RYEqReset(); [ws rebuild]; }]];
    UIButton *moreBtn = RYBtn(@"•••", NO, nil); moreBtn.menu = [UIMenu menuWithTitle:@"" children:more]; moreBtn.showsMenuAsPrimaryAction = YES;
    [nameBtn setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    [self.stack addArrangedSubview:RYCard(@[RYSection(@"star.fill", T(@"الوزنية", @"Preset"), nil), RYHStack(@[nameBtn, star, moreBtn], 8)])];
    // ---- favourites (9 slots)
    NSMutableArray *slots = [NSMutableArray new];
    for (int i = 0; i < 9; i++) {
        NSString *n = i < (int)fav.count ? fav[i] : nil;
        UIButton *b = RYBtn(n ? [n substringToIndex:MIN((NSUInteger)2, n.length)] : @"", n && [n isEqualToString:cur], ^{
            if (!n) return; for (NSDictionary *d in RYEqAllPresets()) if ([d[@"n"] isEqualToString:n]) { RYEqApplyDict(d); [ws rebuild]; return; }
        });
        b.enabled = n != nil; [slots addObject:b];
    }
    UIStackView *fs = RYHStack(slots, 6); fs.distribution = UIStackViewDistributionFillEqually; fs.alignment = UIStackViewAlignmentFill;
    [self.stack addArrangedSubview:RYCard(@[RYLabel([NSString stringWithFormat:@"%@ (%d/9)", T(@"المفضلة", @"Favorites"), (int)fav.count], 12, UIFontWeightSemibold, RY_MUTED), fs])];
    // ---- graph: on/off + edit button
    RYEQView *gv = [[RYEQView alloc] initWithFrame:CGRectMake(0, 0, 300, 280)]; [gv.heightAnchor constraintEqualToConstant:280].active = YES; gv.editing = self.eqEdit;
    UILabel *st = RYLabel(@" ", 13, UIFontWeightMedium, RY_MUTED);
    gv.onLive = ^(int b) { st.text = [NSString stringWithFormat:@"%.0f Hz    %+.1f dB    Q %.1f", gEqF[b], gEqG[b], gEqQ[b]]; };
    gv.onEnd = ^{ RYEqSave(); };
    UIButton *edit = RYBtn(self.eqEdit ? T(@"تم", @"Done") : T(@"تعديل", @"Edit"), self.eqEdit, ^{ ws.eqEdit = !ws.eqEdit; [ws rebuild]; });
    UISwitch *eqSw = RYSwitch(gEqOn != 0, nil, ^(BOOL on) { RYEqSetOn(on); [gv setNeedsDisplay]; });
    [self.stack addArrangedSubview:RYCard(@[RYSection(@"slider.vertical.3", @"EQ / Studio", RYHStack(@[edit, eqSw], 10)), gv, st])];
    [self.stack addArrangedSubview:RYCard(@[RYSl(T(@"المستوى", @"Preamp"), nil, @"dB", -12, 12, gEqPre, 1, YES, ^(float v) { gEqPre = v; gEqVer++; CS(@"eqPre", @(v)); [gv setNeedsDisplay]; })])];
    // ---- Clearcast
    [self.stack addArrangedSubview:RYCard(@[RYSw(@"Clearcast AI", gNcOn != 0, nil, ^(BOOL on) { gNcOn = on; CS(@"ncOn", @(on)); [ws rebuild]; }),
        RYSl(@"Min", @"Max", nil, 0, 1, gNcAmt, 2, YES, ^(float v) { gNcAmt = v; CS(@"ncAmt", @(v)); })])];
    // ---- Noise reduction (disabled while Clearcast is on, like Sonar)
    BOOL nrOK = !gNcOn;
    [self.stack addArrangedSubview:RYCard(@[RYLabel(T(@"تقليل الضوضاء", @"Noise Reduction"), 15, UIFontWeightSemibold, nrOK ? nil : RY_MUTED),
        RYSw(T(@"الخلفية", @"Background"), gNrBgOn != 0, nil, ^(BOOL on) { gNrBgOn = on; CS(@"nrBgOn", @(on)); }),
        RYSl(nil, nil, nil, 0, 1, gNrBg, 2, nrOK, ^(float v) { gNrBg = v; CS(@"nrBg", @(v)); }),
        RYSw(T(@"الارتطام", @"Impact"), gNrImpOn != 0, nil, ^(BOOL on) { gNrImpOn = on; CS(@"nrImpOn", @(on)); }),
        RYSl(nil, nil, nil, 0, 1, gNrImp, 2, nrOK, ^(float v) { gNrImp = v; CS(@"nrImp", @(v)); })])];
    // ---- Noise gate
    [self.stack addArrangedSubview:RYCard(@[RYSw(T(@"بوابة الضوضاء", @"Noise Gate"), gGateOn != 0, nil, ^(BOOL on) { gGateOn = on; CS(@"gateOn", @(on)); }),
        RYSl(T(@"العتبة", @"Threshold"), nil, @"dB", -80, -20, gGateThr, 1, !gGateAuto, ^(float v) { gGateThr = v; CS(@"gateThr", @(v)); }),
        RYSw(T(@"تلقائي", @"Auto"), gGateAuto != 0, nil, ^(BOOL on) { gGateAuto = on; CS(@"gateAuto", @(on)); [ws rebuild]; })])];
    // ---- Compressor
    [self.stack addArrangedSubview:RYCard(@[RYSw(T(@"الكومبريسر", @"Compressor"), gCompOn != 0, nil, ^(BOOL on) { gCompOn = on; CS(@"compOn", @(on)); }),
        RYSl(T(@"المستوى", @"Level"), nil, nil, 0, 1, gCompLvl, 2, YES, ^(float v) { gCompLvl = v; CS(@"compLvl", @(v)); })])];
    // ---- Sonar import: the link is taken from the clipboard, then the preset name is asked
    [self.stack addArrangedSubview:RYBtn(T(@"استيراد", @"Import"), NO, ^{
        UIPasteboard *pb = UIPasteboard.generalPasteboard; NSString *t = pb.string; if (!t.length && pb.URL) t = pb.URL.absoluteString;
        if (!t.length) { [ws toast:T(@"الحافظة فاضية", @"Clipboard is empty")]; return; }
        [ws ask:T(@"اسم الوزنية", @"Preset name") ph:T(@"اسم", @"Name") secure:NO ok:^(NSString *n) {
            n = [n stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            [ws toast:T(@"جاري الاستيراد", @"Importing")];
            RYEqImportLink(t, n, ^(NSString *err, NSString *name) { if (err) [ws toast:err]; else { [ws toast:name]; [ws rebuild]; } });
        }];
    })];
    [self.invUI invalidate]; self.invUI = nil; self.invLabel = nil;
}
- (void)renderRec {
    __weak typeof(self) ws = self;
    UIButton *go = RYBtn(gRecOn ? T(@"إيقاف", @"Stop") : T(@"تسجيل", @"Record"), gRecOn != 0, ^{
        if (!gRecOn) {
            RYRecStart(^(NSString *err) { if (err) { [ws toast:err]; return; } [ws dismissViewControllerAnimated:YES completion:nil]; });
        } else {
            [ws toast:T(@"جاري الحفظ", @"Saving")];
            RYRecStop(^(NSURL *u, NSString *err) {
                if (err || !u) { if (err) [ws toast:err]; [ws rebuild]; return; }
                [ws rebuild];
                UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[u] applicationActivities:nil];
                av.popoverPresentationController.sourceView = ws.view; [ws presentViewController:av animated:YES completion:nil];
            });
        }
    });
    [self.stack addArrangedSubview:RYCard(@[RYSection(@"record.circle.fill", T(@"تسجيل", @"Record"), nil), go, RYSw(T(@"مايكي بالتسجيل", @"My mic in recording"), gRecMicOn != 0, nil, ^(BOOL on) { gRecMicOn = on; })])];
    UILabel *st = RYLabel(@" ", 13, UIFontWeightMedium, RY_MUTED);
    void (^upd)(void) = ^{
        if (!gRecOn) { st.text = gRecHook ? T(@"جاهز", @"Ready") : T(@"جاهز (صوت الروم يُلتقط بعد دخول الروم)", @"Ready (room audio is picked up after joining a room)"); return; }
        int sec = (int)(CACurrentMediaTime() - gRecStart);
        st.text = [NSString stringWithFormat:@"%02d:%02d   %@ %lld   %@ %@   %@ %@", sec / 60, sec % 60, T(@"فيديو", @"Video"), gRecVidN, T(@"مايك", @"Mic"), gRecMicOn ? (gRecMicN > 0 ? @"✓" : @"✗") : @"-", T(@"أصواتهم", @"Voices"), gRecPlayN > 0 ? @"✓" : @"✗"];
    };
    upd(); [self.stack addArrangedSubview:RYCard(@[st])];
    [self.invUI invalidate]; self.invLabel = nil; self.invUI = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { upd(); }];
    // saved recordings: tap = share / save, x = delete
    NSString *dir = RYDir(@"rec"); NSArray *fs = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil] sortedArrayUsingSelector:@selector(compare:)];
    int shown = 0;
    for (NSString *f in [fs reverseObjectEnumerator]) {
        if (![f.pathExtension isEqualToString:@"mp4"] || shown++ >= 12) continue;
        NSString *path = [dir stringByAppendingPathComponent:f]; unsigned long long sz = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize];
        UIButton *b = RYBtn([NSString stringWithFormat:@"%@   %.1f MB", [f substringWithRange:NSMakeRange(4, MIN((NSUInteger)15, f.length - 4))], sz / 1048576.0], NO, ^{
            UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
            av.popoverPresentationController.sourceView = ws.view; [ws presentViewController:av animated:YES completion:nil];
        });
        [b setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
        UIButton *x = RYBtn(@"✕", NO, ^{ [[NSFileManager defaultManager] removeItemAtPath:path error:nil]; [ws rebuild]; });
        [self.stack addArrangedSubview:RYCard(@[RYHStack(@[b, x], 8)])];
    }
}
- (void)renderCat {
    BOOL on = [CF(@"cat", @YES) boolValue];
    UISwitch *cs = RYSwitch(on, nil, ^(BOOL v) { RYCatSet(v); });
    [self.stack addArrangedSubview:RYCard(@[RYSection(@"pawprint.fill", T(@"القطوة", @"Cat"), cs)])];
    UISwitch *is = RYSwitch(![CF(@"introOff", @NO) boolValue], nil, ^(BOOL v) { CS(@"introOff", @(!v)); });
    [self.stack addArrangedSubview:RYCard(@[RYSection(@"sparkles", T(@"مقدمة 8ubah", @"8ubah intro"), is)])];
    [self.invUI invalidate]; self.invUI = nil; self.invLabel = nil;
}
- (void)renderFake {
    __weak typeof(self) ws = self;
    BOOL on = gFakeDef;
    UIButton *b = RYBtn(@"Fake Defean", on, ^{            // purple = on, grey = off
        BOOL want = !gFakeDef; int r = RYFakeDefSet(want);
        [ws toast:want ? (r ? T(@"الباقين يشوفونك ميوت ودفن", @"Others now see you muted + deafened") : T(@"جاهز — بدّل الميوت أو الديفن مرة وحدة (أو ادخل روم) وبيتطبق", @"Armed — toggle mute or deafen once (or join a room) and it applies"))
                       : (r ? T(@"رجعت حالتك الحقيقية", @"Your real state is back") : T(@"انطفى", @"Off"))];
        [ws rebuild];
    });
    [self.stack addArrangedSubview:RYCard(@[RYSection(@"shield.lefthalf.filled", @"Fake Defean", nil), b])];
    [self.invUI invalidate]; self.invUI = nil; self.invLabel = nil;
}
- (void)renderDiag {
    __weak typeof(self) ws = self;
    [self.stack addArrangedSubview:RYCard(@[
        RYSection(@"waveform.path.ecg", @"Diag", nil),
        RYBtn(T(@"تقرير كامل", @"Full report"), YES, ^{ RYShareText(ws, @"diag-full.txt", RYDiagReport()); }),
        RYBtn(T(@"شاشة الدردشة", @"Chat screen"), NO, ^{ RYShareText(ws, @"diag-chat.txt", RYDiagChat()); }),
        RYBtn(T(@"محرك الصوت", @"Voice engine"), NO, ^{ RYShareText(ws, @"diag-voice.txt", RYDiagVoice()); }),
        RYBtn(T(@"المايك", @"Mic"), NO, ^{ RYShareText(ws, @"diag-mic.txt", RYMicReport()); }),
        RYBtn(T(@"مشاركة الشاشة", @"Screen share"), NO, ^{ RYShareText(ws, @"diag-screenshare.txt", RYDiagBroadcast()); }),
        RYBtn(T(@"فولو / سحب", @"Follow / Pull"), NO, ^{ RYShareText(ws, @"diag-follow.txt", RYFPDiag()); }),
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


#pragma mark - ReviewDB (native): a Reviews button on the profile next to Follow/Pull. Same backend as the
// desktop ReviewDB plugin (manti.vendicated.dev). Reading needs no login; writing uses the token the JS
// ReviewDB plugin stored at Documents/pyoncord/8ubah-reviewdb.json.
#define RY_RDB_API @"https://manti.vendicated.dev/api/reviewdb"
static NSString *RYRdbToken(void) {
    NSString *p = [[[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"pyoncord"] stringByAppendingPathComponent:@"8ubah-reviewdb.json"] copy];
    NSData *d = [NSData dataWithContentsOfFile:p]; if (!d) return nil;
    id j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    id t = [j isKindOfClass:NSDictionary.class] ? j[@"token"] : nil;
    return [t isKindOfClass:NSString.class] && [t length] ? t : nil;
}
static void RYRdbGet(NSString *uid, void (^done)(NSArray *reviews, NSString *err)) {
    NSURL *u = [NSURL URLWithString:[NSString stringWithFormat:@"%@/users/%@/reviews?limit=50", RY_RDB_API, uid]];
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:u]; [r setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [[NSURLSession.sharedSession dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *resp, NSError *e) {
        NSArray *out = nil; id j = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([j isKindOfClass:NSDictionary.class] && [j[@"reviews"] isKindOfClass:NSArray.class]) out = j[@"reviews"];
        dispatch_async(dispatch_get_main_queue(), ^{ done(out, out ? nil : T(@"ما قدرت أجيب الريفيو", @"Couldn't load reviews")); });
    }] resume];
}
static void RYRdbPost(NSString *uid, NSString *comment, void (^done)(BOOL ok, NSString *err)) {
    NSString *tok = RYRdbToken();
    if (!tok) { done(NO, T(@"سجّل دخول أول من: 8ubah ← الإضافات ← ReviewDB", @"Log in first: 8ubah → Plugins → ReviewDB")); return; }
    NSURL *u = [NSURL URLWithString:[NSString stringWithFormat:@"%@/users/%@/reviews", RY_RDB_API, uid]];
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:u]; r.HTTPMethod = @"PUT";
    [r setValue:@"application/json" forHTTPHeaderField:@"Accept"]; [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"]; [r setValue:tok forHTTPHeaderField:@"Authorization"];
    r.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"userid": uid, @"comment": comment} options:0 error:nil];
    [[NSURLSession.sharedSession dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *resp, NSError *e) {
        NSInteger st = [resp isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        id j = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *msg = [j isKindOfClass:NSDictionary.class] && [j[@"message"] isKindOfClass:NSString.class] ? j[@"message"] : nil;
        BOOL ok = st >= 200 && st < 300;
        dispatch_async(dispatch_get_main_queue(), ^{ done(ok, ok ? nil : (msg ?: T(@"فشل النشر", @"Post failed"))); });
    }] resume];
}

@interface RYReviewVC : UIViewController
@property (nonatomic, copy) NSString *uid; @property (nonatomic, copy) NSString *uname;
@property (nonatomic, strong) UIStackView *listStack; @property (nonatomic, strong) UITextField *field;
@end
@implementation RYReviewVC
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = RY_BG; self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    __weak typeof(self) ws = self;
    UIScrollView *sc = [UIScrollView new]; sc.alwaysBounceVertical = YES; sc.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    UIStackView *root = [UIStackView new]; root.axis = UILayoutConstraintAxisVertical; root.spacing = 12;
    UILabel *title = RYLabel([NSString stringWithFormat:T(@"ريفيو: %@", @"Reviews: %@"), self.uname.length ? self.uname : self.uid], 20, UIFontWeightHeavy, UIColor.whiteColor); title.numberOfLines = 1;
    self.listStack = [UIStackView new]; self.listStack.axis = UILayoutConstraintAxisVertical; self.listStack.spacing = 8;
    UITextField *tf = [UITextField new]; tf.placeholder = T(@"اكتب ريفيو عن الشخص…", @"Write a review…"); tf.textColor = UIColor.whiteColor; tf.backgroundColor = RY_CARD2; tf.borderStyle = UITextBorderStyleRoundedRect; [tf.heightAnchor constraintEqualToConstant:46].active = YES; self.field = tf;
    UIButton *post = RYBtn(T(@"نشر الريفيو", @"Post review"), YES, ^{
        NSString *c = [ws.field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!c.length) return; [ws.view endEditing:YES];
        RYRdbPost(ws.uid, c, ^(BOOL ok, NSString *err) { [[RYCore shared] hud:(ok ? T(@"تم نشر الريفيو ✅", @"Posted ✅") : err)]; if (ok) { ws.field.text = @""; [ws load]; } });
    });
    for (UIView *v in @[title, self.listStack, tf, post]) [root addArrangedSubview:v];
    [self.view addSubview:sc]; [sc addSubview:root];
    sc.translatesAutoresizingMaskIntoConstraints = NO; root.translatesAutoresizingMaskIntoConstraints = NO;
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [sc.topAnchor constraintEqualToAnchor:g.topAnchor constant:18], [sc.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [sc.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16], [sc.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
        [root.topAnchor constraintEqualToAnchor:sc.contentLayoutGuide.topAnchor], [root.bottomAnchor constraintEqualToAnchor:sc.contentLayoutGuide.bottomAnchor constant:-40],
        [root.leadingAnchor constraintEqualToAnchor:sc.contentLayoutGuide.leadingAnchor], [root.trailingAnchor constraintEqualToAnchor:sc.contentLayoutGuide.trailingAnchor],
        [root.widthAnchor constraintEqualToAnchor:sc.frameLayoutGuide.widthAnchor]]];
    [self load];
}
- (void)load {
    for (UIView *v in self.listStack.arrangedSubviews) [v removeFromSuperview];
    [self.listStack addArrangedSubview:RYLabel(T(@"جاري التحميل…", @"Loading…"), 14, UIFontWeightMedium, RY_MUTED)];
    __weak typeof(self) ws = self;
    RYRdbGet(self.uid, ^(NSArray *reviews, NSString *err) {
        UIStackView *ls = ws.listStack; if (!ls) return;
        for (UIView *v in ls.arrangedSubviews) [v removeFromSuperview];
        if (!reviews.count) { [ls addArrangedSubview:RYLabel(err ?: T(@"لا يوجد ريفيو بعد", @"No reviews yet"), 14, UIFontWeightMedium, RY_MUTED)]; return; }
        for (NSDictionary *rv in reviews) {
            if (![rv isKindOfClass:NSDictionary.class]) continue;
            NSString *name = [rv[@"sender"] isKindOfClass:NSDictionary.class] && [rv[@"sender"][@"username"] isKindOfClass:NSString.class] ? rv[@"sender"][@"username"] : @"user";
            NSString *comment = [rv[@"comment"] isKindOfClass:NSString.class] ? rv[@"comment"] : @"";
            UILabel *nm = RYLabel(name, 13, UIFontWeightBold, RYAccent());
            UILabel *cm = RYLabel(comment, 15, UIFontWeightRegular, RY_DIM); cm.numberOfLines = 0;
            [ls addArrangedSubview:RYCard(@[nm, cm])];
        }
    });
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
    // one cinematic 8ubah splash per launch (not per panel open); skipped after a crash and when the owner turns it off
    static dispatch_once_t introOnce; dispatch_once(&introOnce, ^{ if (!gSafeLaunch && ![CF(@"introOff", @NO) boolValue]) RYShowIntro(sc); });
    self.win = [[RYWindow alloc] initWithWindowScene:sc]; self.win.windowLevel = UIWindowLevelAlert + 50; self.win.backgroundColor = UIColor.clearColor;
    UIViewController *root = [UIViewController new]; root.view.backgroundColor = UIColor.clearColor; self.win.rootViewController = root; self.win.hidden = NO;
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom]; b.frame = CGRectMake(0, 0, 52, 52); b.layer.cornerRadius = 26;
    b.backgroundColor = RYAccent(); b.tintColor = UIColor.whiteColor; b.layer.shadowOpacity = 0.4; b.layer.shadowRadius = 6; b.layer.shadowOffset = CGSizeMake(0, 3);
    // floating button mark: a soft rounded "R" with a small gold crown on top
    UIFontDescriptor *rdsc = [[UIFont systemFontOfSize:23 weight:UIFontWeightHeavy].fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
    UILabel *rl = [UILabel new]; rl.text = @"R"; rl.textColor = UIColor.whiteColor; rl.textAlignment = NSTextAlignmentCenter;
    rl.font = rdsc ? [UIFont fontWithDescriptor:rdsc size:23] : [UIFont systemFontOfSize:23 weight:UIFontWeightHeavy];
    rl.frame = CGRectMake(0, 5, 52, 52); rl.userInteractionEnabled = NO; [b addSubview:rl];
    UIImageView *crown = [[UIImageView alloc] initWithImage:[[UIImage systemImageNamed:@"crown.fill"] imageWithConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightBold]]];
    crown.tintColor = [UIColor colorWithRed:1.0 green:0.82 blue:0.28 alpha:1.0]; crown.contentMode = UIViewContentModeScaleAspectFit;
    crown.frame = CGRectMake(16, 6, 20, 14); crown.userInteractionEnabled = NO; [b addSubview:crown];
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
    RYPanel *p = [RYPanel new]; p.modalPresentationStyle = UIModalPresentationPageSheet; if (gRecOn) p.tab = 6;
    UISheetPresentationController *sp = p.sheetPresentationController;
    if (sp) { sp.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent]; sp.prefersGrabberVisible = YES; }
    [root presentViewController:p animated:YES completion:^{ [self.win makeKeyWindow]; }];
}
- (void)panelClosed { [self.prevKey makeKeyWindow]; }
- (void)fpBuild {
    if (self.fpBar) return;
    UIView *root = self.win.rootViewController.view; if (!root) return;
    UIView *bar = [UIView new]; bar.backgroundColor = [UIColor colorWithWhite:0.07 alpha:0.94]; bar.layer.cornerRadius = 25; bar.layer.shadowOpacity = 0.35; bar.layer.shadowRadius = 8; bar.layer.shadowOffset = CGSizeMake(0, 3);
    __weak typeof(self) ws = self;
    UIButton *f = [UIButton buttonWithType:UIButtonTypeSystem], *p = [UIButton buttonWithType:UIButtonTypeSystem], *rv = [UIButton buttonWithType:UIButtonTypeSystem];
    f.frame = CGRectMake(8, 6, 100, 38); p.frame = CGRectMake(112, 6, 100, 38); rv.frame = CGRectMake(216, 6, 112, 38); bar.frame = CGRectMake(0, 0, 336, 50);
    [f addAction:[UIAction actionWithHandler:^(UIAction *a) { NSString *u = ws.fpUid; if (!u) { [ws hud:T(@"ما قدرت أحدد الحساب", @"Can't tell which account")]; return; } RYFPToggleFollow(u); [ws fpRefresh]; }] forControlEvents:UIControlEventTouchUpInside];
    [p addAction:[UIAction actionWithHandler:^(UIAction *a) { NSString *u = ws.fpUid; if (!u) { [ws hud:T(@"ما قدرت أحدد الحساب", @"Can't tell which account")]; return; } RYFPTogglePull(u); [ws fpRefresh]; }] forControlEvents:UIControlEventTouchUpInside];
    [rv addAction:[UIAction actionWithHandler:^(UIAction *a) {
        NSString *u = ws.fpUid; if (!u) { [ws hud:T(@"ما قدرت أحدد الحساب", @"Can't tell which account")]; return; }
        RYReviewVC *vc = [RYReviewVC new]; vc.uid = u; vc.modalPresentationStyle = UIModalPresentationPageSheet;
        UISheetPresentationController *sp = vc.sheetPresentationController; if (sp) { sp.detents = @[UISheetPresentationControllerDetent.largeDetent, UISheetPresentationControllerDetent.mediumDetent]; sp.prefersGrabberVisible = YES; }
        [ws.win.rootViewController presentViewController:vc animated:YES completion:^{ [ws.win makeKeyWindow]; }];
    }] forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:f]; [bar addSubview:p]; [bar addSubview:rv]; [root addSubview:bar];
    self.fpBar = bar; self.fpFollowBtn = f; self.fpPullBtn = p; self.fpReviewBtn = rv; bar.hidden = YES;
}
static void RYFPStyle(UIButton *b, NSString *title, UIColor *bg) {
    UIButtonConfiguration *c = [UIButtonConfiguration filledButtonConfiguration]; c.title = title; c.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    c.baseBackgroundColor = bg; c.baseForegroundColor = UIColor.whiteColor; b.configuration = c;
}
- (void)fpRefresh {
    NSString *u = self.fpUid; BOOL fo, pu;
    @synchronized (gFPLock) { fo = u && [gFPFollow isEqual:u]; pu = u && [gFPPull containsObject:u]; }
    RYFPStyle(self.fpFollowBtn, fo ? @"Unfollow" : @"Follow", fo ? RY_RED : RYAccent());
    RYFPStyle(self.fpPullBtn, pu ? @"Unpull" : @"Pull", pu ? RY_RED : [UIColor colorWithWhite:0.26 alpha:1]);
    RYFPStyle(self.fpReviewBtn, T(@"ريفيو", @"Reviews"), [UIColor colorWithRed:0.16 green:0.68 blue:0.54 alpha:1]);
}
- (void)fpTick {                // a profile sheet is open -> Follow / Pull buttons at the bottom of the screen
    RYFPInit();
    UIViewController *root = self.win.rootViewController;
    if (!root || root.presentedViewController) { self.fpBar.hidden = YES; return; }
    NSString *uid = nil; BOOL found = RYFPFindSheet(&uid);
    if (found && uid && gFDOwnId && [uid isEqual:gFDOwnId]) found = NO;       // your own profile: nothing to follow
    if (!found) { if (++self.fpMiss >= 2) self.fpBar.hidden = YES; return; }
    self.fpMiss = 0; self.fpUid = uid; [self fpBuild]; if (!self.fpBar) return;
    UIView *rv = root.view; UIEdgeInsets in = rv.safeAreaInsets;
    self.fpBar.center = CGPointMake(rv.bounds.size.width / 2, rv.bounds.size.height - in.bottom - 52);
    [self fpRefresh]; self.fpBar.hidden = NO; [rv bringSubviewToFront:self.fpBar];
}
- (void)tick {
    self.fab.hidden = NO; self.fab.backgroundColor = gRecOn ? RY_RED : RYAccent(); RYHookInputs();
    RYCatTick();
    [self syncBG:RYChatHost()];
    [self fpTick];
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

#pragma mark - Plugins loader auto-config

// The IPA already ships BTLoader.dylib (the Pyoncord/Bunny JS loader). On launch it reads
// Documents/pyoncord/loader.json; if customLoadUrl.enabled is true it loads that bundle instead of
// the stock one. We pre-write that file to the 8ubah bundle so every plugin is present with no manual
// step. We only (re)write the URL when it differs and NEVER delete the cached bundle, so once it is fetched
// the first time it loads instantly and offline on every later launch. Do NOT add a second JS loader here:
// BTLoader already hooks the RN bridge, and injecting the bundle twice would crash Discord.
// Pinned to the dist commit's jsDelivr SHA URL (not @dist): jsDelivr caches a BRANCH ref for ~12h and
// won't refresh, but a commit-SHA URL is immutable, fast, and served fresh at once. Bump this SHA when
// publishing a new bundle. (Resolve the latest with: git -C displug rev-parse origin/dist)
#define RY_PLUGIN_BUNDLE_URL @"https://cdn.jsdelivr.net/gh/mboussoula0-ux/displug@629a40613bebcafbf2d0dbee61abbfd792801965/8ubah.min.js"

// OTA: resolve the latest published bundle (the newest commit on displug's dist branch) and point the
// NEXT launch at its immutable jsDelivr SHA URL. Runs in the background, best-effort: if GitHub's API is
// unreachable, loader.json keeps its current URL and the cached bundle still loads. This is what lets new
// plugins/fixes reach the device WITHOUT reinstalling the dylib. We never delete the cached bundle.
static void RYResolveLatestBundle(NSURL *cfgURL) {
    @try {
        NSURL *api = [NSURL URLWithString:@"https://api.github.com/repos/mboussoula0-ux/displug/commits/dist"];
        if (!api || !cfgURL) return;
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:api cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:8];
        [req setValue:@"8ubah-loader" forHTTPHeaderField:@"User-Agent"];
        [req setValue:@"application/vnd.github.sha" forHTTPHeaderField:@"Accept"]; // response body == the commit SHA
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            @try {
                if (err || !data) return;
                NSInteger code = [resp isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
                if (code != 200) return;
                NSString *sha = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (sha.length < 7) return;
                NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
                if ([sha rangeOfCharacterFromSet:hex.invertedSet].location != NSNotFound) return; // must be a hex sha
                NSString *url = [NSString stringWithFormat:@"https://cdn.jsdelivr.net/gh/mboussoula0-ux/displug@%@/8ubah.min.js", sha];
                NSData *cur = [NSData dataWithContentsOfURL:cfgURL];
                NSString *curUrl = nil;
                if (cur) { id j = [NSJSONSerialization JSONObjectWithData:cur options:0 error:nil]; NSDictionary *c = [j isKindOfClass:NSDictionary.class] ? ((NSDictionary *)j)[@"customLoadUrl"] : nil; if ([c isKindOfClass:NSDictionary.class]) curUrl = c[@"url"]; }
                if ([curUrl isEqualToString:url]) return; // already on the latest
                NSDictionary *json = @{ @"customLoadUrl" : @{ @"enabled" : @YES, @"url" : url } };
                NSData *outD = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
                if (outD) [outD writeToURL:cfgURL atomically:YES];
            } @catch (__unused id e) {}
        }];
        [task resume];
    } @catch (__unused id e) {}
}

static void RYConfigurePluginLoader(void) {
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSURL *docs = [[fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
        if (!docs) return;
        NSURL *dir = [docs URLByAppendingPathComponent:@"pyoncord"];
        if (![fm fileExistsAtPath:dir.path])
            [fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL *cfg = [dir URLByAppendingPathComponent:@"loader.json"];

        BOOL isOurs = NO;
        NSData *cur = [NSData dataWithContentsOfURL:cfg];
        if (cur) {
            id j = [NSJSONSerialization JSONObjectWithData:cur options:0 error:nil];
            NSDictionary *c = [j isKindOfClass:NSDictionary.class] ? ((NSDictionary *)j)[@"customLoadUrl"] : nil;
            NSString *u = ([c isKindOfClass:NSDictionary.class] && [c[@"enabled"] boolValue] && [c[@"url"] isKindOfClass:NSString.class]) ? c[@"url"] : nil;
            // Accept ANY 8ubah jsDelivr bundle URL (any commit SHA). The OTA resolver keeps it on the latest,
            // so we must NOT stomp a newer SHA that a previous launch already wrote with our fallback.
            if (u && [u hasPrefix:@"https://cdn.jsdelivr.net/gh/mboussoula0-ux/displug@"] && [u hasSuffix:@"8ubah.min.js"]) isOurs = YES;
        }
        if (!isOurs) {
            // First run, or pointed elsewhere: write the known-good fallback URL. We NEVER delete the cached
            // bundle (clearing it every launch forced a slow refetch, so 8ubah showed only if you waited and
            // vanished on reopen). Leaving the cache means the first fetch loads instantly on every launch.
            NSDictionary *json = @{ @"customLoadUrl" : @{ @"enabled" : @YES, @"url" : RY_PLUGIN_BUNDLE_URL } };
            NSData *out = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
            if (out) [out writeToURL:cfg atomically:YES];
        }
        // OTA: point the NEXT launch at the newest published bundle (background, best-effort).
        RYResolveLatestBundle(cfg);
    } @catch (__unused id e) {}
}

#pragma mark - Entry

__attribute__((constructor)) static void RYInit(void) {
    if (![[NSBundle mainBundle].bundlePath.pathExtension isEqual:@"app"]) return; // skip app extensions
    RYLoad(); RYInstallCrashLog();
    RYConfigurePluginLoader(); // point the bundled BTLoader at the 8ubah plugin bundle (no manual step)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ RYInstallCrashLog(); });
    // crash-loop guard: if the previous launch died within 10 seconds, this launch skips the audio hooks
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    BOOL safe = [ud boolForKey:@"8ubah.dc.launching"]; gSafeLaunch = safe;
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

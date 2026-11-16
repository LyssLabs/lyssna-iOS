#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

void LyssnaSBInvokeSeekDouble(id target, SEL selector, double argument);
NSString *LyssnaJBRootPath(NSString *path);
BOOL LyssnaSetMainInfoValue(NSString *key, id value);
UIImage *_Nullable LyssnaRenderTemplate(UIView *view);
UIImage *_Nullable LyssnaEncoreIconImage(UIView *iconView, BOOL active);
BOOL LyssnaFireTap(UIView *root);
NSArray *LyssnaTapTargets(UIView *root);
int LyssnaInstallColorSwaps(BOOL amoled, NSInteger accentRGB);
void LyssnaColorSwapStats(long *grey, long *green, long *uiColor);
BOOL LyssnaPinSetter(id object, SEL setter, id value);
BOOL LyssnaInterceptBackground(UIView *view, void (^sink)(UIColor *color));

// Artist-page download button of the LyssnaOffline companion. They resolve its exported functions at
// runtime and do nothing when the companion is not loaded.
void LyssnaOfflineUpdateArtistDownloads(UIView *header, UIButton *_Nullable externalButton);
NSString *_Nullable LyssnaOfflineArtistURIForHeader(UIView *header);
void LyssnaOfflineInstallArtistFollow(void);
// The LyssnaOffline download manager page in Lyssna's settings list. Both do nothing when the companion is not loaded.
BOOL LyssnaOfflineDownloadsAvailable(void);
UIViewController *_Nullable LyssnaOfflineMakeDownloadsController(void);
NSInteger LyssnaOfflineArtistFollowing(UIView *header, void (^changed)(void));
// 1 saved, 0 not saved, -1 not known yet. `changed` runs when Spotify reports a new state.
NSInteger LyssnaOfflineSavedState(UIView *page, NSString *uri, void (^changed)(void));

NS_ASSUME_NONNULL_END

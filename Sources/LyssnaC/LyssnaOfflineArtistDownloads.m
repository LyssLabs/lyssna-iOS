#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import "include/Tweak.h"

// The artist download button is implemented by the LyssnaOffline native-downloads companion. The glass
// artist header hosts it in Lyssna's action row, so Lyssna only forwards to the companion's exports.
void LyssnaOfflineUpdateArtistDownloads(UIView *header, UIButton *externalButton) {
    static void (*update)(UIView *, UIButton *);
    static dispatch_once_t once;
    dispatch_once(&once, ^{ update = dlsym(RTLD_DEFAULT, "SAPUpdateArtistDownloadsExternal"); });
    if (update) update(header, externalButton);
    else if (externalButton && !externalButton.isHidden) externalButton.hidden = YES;
}

NSString *LyssnaOfflineArtistURIForHeader(UIView *header) {
    static NSString *(*resolve)(UIView *);
    static dispatch_once_t once;
    dispatch_once(&once, ^{ resolve = dlsym(RTLD_DEFAULT, "SAPArtistURIForHeader"); });
    return resolve ? resolve(header) : nil;
}

// Tells the LyssnaOffline companion that this Lyssna lists the download manager in its own settings.
__attribute__((visibility("default"))) BOOL LyssnaOfflineDownloadsRowProvided(void) { return YES; }

static UIViewController *(*LyssnaOfflineDownloadsFactory(void))(void) {
    static UIViewController *(*make)(void);
    static dispatch_once_t once;
    dispatch_once(&once, ^{ make = dlsym(RTLD_DEFAULT, "SAPCreateDownloadsSettings"); });
    return make;
}

BOOL LyssnaOfflineDownloadsAvailable(void) { return LyssnaOfflineDownloadsFactory() != NULL; }

UIViewController *LyssnaOfflineMakeDownloadsController(void) {
    UIViewController *(*make)(void) = LyssnaOfflineDownloadsFactory();
    return make ? make() : nil;
}

#import <Orion/Orion.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import "Tweak.h"

#if THEOS_PACKAGE_SCHEME_ROOTHIDE
#import <roothide.h>
#else
#import <libroot.h>
#endif

NSString *LyssnaJBRootPath(NSString *path) {
#if THEOS_PACKAGE_SCHEME_ROOTHIDE
    return jbroot(path);
#else
    return JBROOT_PATH_NSSTRING(path);
#endif
}

void LyssnaSBInvokeSeekDouble(id target, SEL selector, double argument) {
    if (!target || !selector) return;
    typedef id (*SeekFn)(id, SEL, double);
    SeekFn fn = (SeekFn)objc_msgSend;
    (void)fn(target, selector, argument);
}

BOOL LyssnaSetMainInfoValue(NSString *key, id value) {
    @try {
        id info = (__bridge id)CFBundleGetInfoDictionary(CFBundleGetMainBundle());
        if (![info isKindOfClass:NSMutableDictionary.class]) return NO;
        [(NSMutableDictionary *)info setObject:value forKey:key];
        return [[NSBundle.mainBundle objectForInfoDictionaryKey:key] isEqual:value];
    } @catch (NSException *e) {
        return NO;
    }
}

static void writeDebugLog(NSString *message) {
    NSString *logPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"lyssna_debug.log"];
    NSString *timestamp = [[NSDate date] description];
    NSString *logMessage = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];

    if ([[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[logMessage dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    } else {
        [logMessage writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

__attribute__((constructor)) static void init() {
    @try {
        NSLog(@"[Lyssna] Initializing tweak...");

        // Initialize Orion - do not remove this line.
        orion_init();

        NSLog(@"[Lyssna] Tweak initialized successfully");
        // Custom initialization code goes here.
    }
    @catch (NSException *exception) {
        NSString *errorMsg = [NSString stringWithFormat:@"ERROR: Failed to initialize tweak: %@, Reason: %@", exception, [exception reason]];
        NSLog(@"[Lyssna] %@", errorMsg);
        writeDebugLog(errorMsg);
    }
}

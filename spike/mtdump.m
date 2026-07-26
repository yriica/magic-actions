// mtdump.m — M0 spike: enumerate multitouch devices and dump raw touch frames.
//
// Usage:
//   ./mtdump            # list devices only
//   ./mtdump 8          # list devices, then dump touch frames for 8 seconds
//   ./mtdump 8 mouse    # dump only non-built-in, non-opaque devices (Magic Mouse)
//
// Build: see build.sh

#import <Cocoa/Cocoa.h>
#include <stdatomic.h>

#pragma mark - MultitouchSupport.framework private declarations
// Layout/signatures mirror OpenMultitouchSupport 4.0 (verified on macOS 15+/Xcode 26).

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

enum {
    MTTouchStateNotTracking = 0,
    MTTouchStateStartInRange = 1,
    MTTouchStateHoverInRange = 2,
    MTTouchStateMakeTouch = 3,
    MTTouchStateTouching = 4,
    MTTouchStateBreakTouch = 5,
    MTTouchStateLingerInRange = 6,
    MTTouchStateOutOfRange = 7
};
typedef int MTTouchState;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    MTTouchState state;
    int fingerId;
    int handId;
    MTVector normalizedPosition; // 0..1, origin bottom-left
    float total;
    float pressure;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolutePosition;
    int field14;
    int field15;
    float density;
} MTTouch;

typedef void *MTDeviceRef;
typedef void (*MTFrameCallbackFunction)(MTDeviceRef device, MTTouch touches[], int numTouches, double timestamp, int frame);

CFMutableArrayRef MTDeviceCreateList(void);
bool MTDeviceIsAvailable(void);
OSStatus MTDeviceStart(MTDeviceRef, int);
OSStatus MTDeviceStop(MTDeviceRef);
void MTDeviceRelease(MTDeviceRef);
bool MTDeviceIsRunning(MTDeviceRef);
bool MTDeviceIsBuiltIn(MTDeviceRef) __attribute__((weak_import));
bool MTDeviceIsOpaqueSurface(MTDeviceRef);
OSStatus MTDeviceGetSensorSurfaceDimensions(MTDeviceRef, int *, int *);
OSStatus MTDeviceGetSensorDimensions(MTDeviceRef, int *, int *);
OSStatus MTDeviceGetFamilyID(MTDeviceRef, int *);
OSStatus MTDeviceGetDeviceID(MTDeviceRef, uint64_t *) __attribute__((weak_import));
OSStatus MTDeviceGetDriverType(MTDeviceRef, int *);
OSStatus MTDeviceGetGUID(MTDeviceRef, uuid_t *);
void MTRegisterContactFrameCallback(MTDeviceRef, MTFrameCallbackFunction);
void MTUnregisterContactFrameCallback(MTDeviceRef, MTFrameCallbackFunction);

#pragma mark - Spike

static NSMutableDictionary<NSNumber *, NSNumber *> *gFrameCounts; // familyID -> frames received
static _Atomic long gTotalFrames = 0;

static const char *stateName(MTTouchState s) {
    switch (s) {
        case MTTouchStateNotTracking: return "notTracking";
        case MTTouchStateStartInRange: return "startInRange";
        case MTTouchStateHoverInRange: return "hover";
        case MTTouchStateMakeTouch: return "makeTouch";
        case MTTouchStateTouching: return "touching";
        case MTTouchStateBreakTouch: return "breakTouch";
        case MTTouchStateLingerInRange: return "linger";
        case MTTouchStateOutOfRange: return "outOfRange";
        default: return "?";
    }
}

static int familyIDOf(MTDeviceRef dev) {
    int familyID = -1;
    MTDeviceGetFamilyID(dev, &familyID);
    return familyID;
}

static void printDeviceInfo(MTDeviceRef dev, int index) {
    int familyID = familyIDOf(dev);
    uint64_t deviceID = 0;
    if (MTDeviceGetDeviceID) MTDeviceGetDeviceID(dev, &deviceID);
    int driverType = -1;
    MTDeviceGetDriverType(dev, &driverType);
    int sw = 0, sh = 0;
    MTDeviceGetSensorSurfaceDimensions(dev, &sw, &sh);
    int rows = 0, cols = 0;
    MTDeviceGetSensorDimensions(dev, &rows, &cols);
    bool builtIn = MTDeviceIsBuiltIn ? MTDeviceIsBuiltIn(dev) : false;
    bool opaque = MTDeviceIsOpaqueSurface(dev);

    printf("device[%d] familyID=%d deviceID=0x%llx driverType=%d builtIn=%d opaque=%d surface=%dx%d sensors=%dx%d\n",
           index, familyID, deviceID, driverType, builtIn, opaque, sw, sh, rows, cols);
}

static void frameCallback(MTDeviceRef device, MTTouch touches[], int numTouches, double timestamp, int frame) {
    atomic_fetch_add(&gTotalFrames, 1);
    int familyID = familyIDOf(device);
    @synchronized (gFrameCounts) {
        NSNumber *key = @(familyID);
        gFrameCounts[key] = @(gFrameCounts[key].longValue + 1);
    }
    if (numTouches == 0) return;

    NSMutableString *line = [NSMutableString stringWithFormat:@"[fam %d] t=%.3f n=%d", familyID, timestamp, numTouches];
    for (int i = 0; i < numTouches; i++) {
        MTTouch *t = &touches[i];
        [line appendFormat:@" | id%d %s p=(%.3f,%.3f) v=(%.2f,%.2f) sz=%.2f prs=%.2f dns=%.2f",
         t->identifier, stateName(t->state),
         t->normalizedPosition.position.x, t->normalizedPosition.position.y,
         t->normalizedPosition.velocity.x, t->normalizedPosition.velocity.y,
         t->total, t->pressure, t->density];
    }
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        double seconds = (argc > 1) ? atof(argv[1]) : 0.0;
        BOOL mouseOnly = (argc > 2) && (strcmp(argv[2], "mouse") == 0);
        gFrameCounts = [NSMutableDictionary dictionary];

        printf("MTDeviceIsAvailable: %d\n", MTDeviceIsAvailable());

        NSArray *devices = (__bridge_transfer NSArray *)MTDeviceCreateList();
        printf("MTDeviceCreateList: %lu device(s)\n", (unsigned long)devices.count);
        for (NSUInteger i = 0; i < devices.count; i++) {
            printDeviceInfo((__bridge MTDeviceRef)devices[i], (int)i);
        }

        if (seconds <= 0) return 0;

        NSMutableArray *started = [NSMutableArray array];
        for (id devObj in devices) {
            MTDeviceRef dev = (__bridge MTDeviceRef)devObj;
            bool builtIn = MTDeviceIsBuiltIn ? MTDeviceIsBuiltIn(dev) : false;
            bool opaque = MTDeviceIsOpaqueSurface(dev);
            if (mouseOnly && (builtIn || opaque)) continue; // Magic Mouse: external + non-opaque
            MTRegisterContactFrameCallback(dev, frameCallback);
            OSStatus err = MTDeviceStart(dev, 0);
            printf("MTDeviceStart(fam %d) -> %d, running=%d\n", familyIDOf(dev), (int)err, MTDeviceIsRunning(dev));
            [started addObject:devObj];
        }
        if (started.count == 0) {
            printf("no devices to listen on (filter=%s)\n", mouseOnly ? "mouse" : "all");
            return 1;
        }

        printf("listening for %.1f seconds... touch the surface now\n", seconds);
        fflush(stdout);
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];

        for (id devObj in started) {
            MTDeviceRef dev = (__bridge MTDeviceRef)devObj;
            MTUnregisterContactFrameCallback(dev, frameCallback);
            MTDeviceStop(dev);
        }

        printf("---\ntotal frames: %ld\n", atomic_load(&gTotalFrames));
        for (NSNumber *fam in gFrameCounts) {
            printf("familyID %d: %ld frames\n", fam.intValue, gFrameCounts[fam].longValue);
        }
        printf("verdict: %s\n", atomic_load(&gTotalFrames) > 0 ? "RECEIVING FRAMES OK" : "NO FRAMES (permission? no touch? device asleep?)");
    }
    return 0;
}

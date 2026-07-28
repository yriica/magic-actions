// keytest.m — reproduce/inspect the Cmd+W dispatch path.
//   ./keytest listen 6   # log keyboard events (keycode/flags/source pid) for 6s
//   ./keytest post       # post Cmd+W exactly like ActionDispatcher
#import <Cocoa/Cocoa.h>

static CGEventRef callback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *ctx) {
    if (type == kCGEventKeyDown || type == kCGEventKeyUp || type == kCGEventFlagsChanged) {
        int64_t keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        CGEventFlags flags = CGEventGetFlags(event);
        int64_t sourcePID = CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID);
        const char *kind = type == kCGEventKeyDown ? "down" : (type == kCGEventKeyUp ? "up" : "flags");
        printf("%.3f %s keycode=%lld flags=0x%llx srcpid=%lld\n",
               CFAbsoluteTimeGetCurrent(), kind, keycode, (unsigned long long)flags, sourcePID);
        fflush(stdout);
    }
    return event;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "post") == 0) {
            CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
            CGEventRef down = CGEventCreateKeyboardEvent(source, 13, true);
            CGEventSetFlags(down, kCGEventFlagMaskCommand);
            CGEventRef up = CGEventCreateKeyboardEvent(source, 13, false);
            CGEventSetFlags(up, kCGEventFlagMaskCommand);
            CGEventPost(kCGHIDEventTap, down);
            CGEventPost(kCGHIDEventTap, up);
            printf("posted cmd+w (keycode 13)\n");
            return 0;
        }

        double seconds = argc > 2 ? atof(argv[2]) : 6.0;
        CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp) | CGEventMaskBit(kCGEventFlagsChanged);
        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGTailAppendEventTap,
                                             kCGEventTapOptionListenOnly, mask, callback, NULL);
        if (!tap) {
            printf("listen tap failed (permission?)\n");
            return 1;
        }
        CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);
        printf("listening %.0fs...\n", seconds);
        fflush(stdout);
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, false);
    }
    return 0;
}

// trackspeed.m — verify live tracking-speed override on this macOS build.
//   ./trackspeed            # read current values
//   ./trackspeed 1.5        # set HIDTrackpadAcceleration to 1.5 and verify via registry
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/hidsystem/IOHIDParameter.h>

typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreateSimpleClient(CFAllocatorRef allocator);
extern Boolean IOHIDEventSystemClientSetProperty(IOHIDEventSystemClientRef client, CFStringRef key, CFTypeRef property);
extern CFTypeRef IOHIDEventSystemClientCopyProperty(IOHIDEventSystemClientRef client, CFStringRef key);

static NSNumber *registryValue(NSString *key) {
    io_service_t service = IORegistryEntryFromPath(kIOMainPortDefault, kIOServicePlane ":/IOResources/IOHIDSystem");
    if (!service) return nil;
    NSDictionary *params = CFBridgingRelease(IORegistryEntryCreateCFProperty(
        service, CFSTR(kIOHIDParametersKey), kCFAllocatorDefault, 0));
    IOObjectRelease(service);
    return params[key];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *key = @"HIDTrackpadAcceleration";
        NSNumber *before = registryValue(key);
        printf("registry %s before: %d (= %.4f)\n", key.UTF8String, before.intValue, before.intValue / 65536.0);

        IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault);
        if (!client) {
            printf("simple client: FAILED to create\n");
            return 1;
        }
        CFTypeRef current = IOHIDEventSystemClientCopyProperty(client, (__bridge CFStringRef)key);
        printf("client read: %s\n", current ? [(__bridge NSObject *)current description].UTF8String : "(null)");

        if (argc > 1) {
            double value = atof(argv[1]);
            int fixed = (int)(value * 65536);
            Boolean ok = IOHIDEventSystemClientSetProperty(client, (__bridge CFStringRef)key, (__bridge CFNumberRef)@(fixed));
            printf("set %.3f (fixed %d) -> %s\n", value, fixed, ok ? "write OK" : "write FAILED");
            usleep(400000);
            NSNumber *after = registryValue(key);
            printf("registry after: %d (= %.4f)\n", after.intValue, after.intValue / 65536.0);
            printf("verdict: %s\n", after.intValue == fixed ? "APPLIED" : "NOT APPLIED");
        }
        CFRelease(client);
    }
    return 0;
}

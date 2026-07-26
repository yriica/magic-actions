// trackspeed2.m — try the two remaining override routes on macOS 26.
//   ./trackspeed2 param 1.5     # route A: IOHIDSystem param connect (registry-verifiable)
//   ./trackspeed2 service 1.5   # route B: per-service write via IOHIDEventSystemClient
//   ./trackspeed2 list          # list pointer services
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/hidsystem/IOHIDParameter.h>
#import <IOKit/hidsystem/IOHIDShared.h>

typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern Boolean IOHIDServiceClientSetProperty(IOHIDServiceClientRef service, CFStringRef key, CFTypeRef property);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef key);

static NSNumber *registryValue(NSString *key) {
    io_service_t service = IORegistryEntryFromPath(kIOMainPortDefault, kIOServicePlane ":/IOResources/IOHIDSystem");
    if (!service) return nil;
    NSDictionary *params = CFBridgingRelease(IORegistryEntryCreateCFProperty(
        service, CFSTR(kIOHIDParametersKey), kCFAllocatorDefault, 0));
    IOObjectRelease(service);
    return params[key];
}

static void routeParam(double value) {
    NSString *key = @"HIDTrackpadAcceleration";
    int fixed = (int)(value * 65536);
    io_service_t service = IORegistryEntryFromPath(kIOMainPortDefault, kIOServicePlane ":/IOResources/IOHIDSystem");
    io_connect_t connect = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), kIOHIDParamConnectType, &connect);
    printf("IOServiceOpen(param): 0x%x\n", kr);
    if (kr == KERN_SUCCESS) {
        kr = IOConnectSetCFProperty(connect, (__bridge CFStringRef)key, (__bridge CFNumberRef)@(fixed));
        printf("IOConnectSetCFProperty(%s=%d): 0x%x\n", key.UTF8String, fixed, kr);
        IOServiceClose(connect);
    }
    IOObjectRelease(service);
    usleep(400000);
    NSNumber *after = registryValue(key);
    printf("registry after: %d (= %.4f) -> %s\n", after.intValue, after.intValue / 65536.0,
           after.intValue == fixed ? "APPLIED" : "NOT APPLIED");
}

static void routeService(double value, BOOL listOnly) {
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) {
        printf("IOHIDEventSystemClientCreate: FAILED\n");
        return;
    }
    NSArray *services = CFBridgingRelease(IOHIDEventSystemClientCopyServices(client));
    printf("services: %lu\n", (unsigned long)services.count);
    for (id obj in services) {
        IOHIDServiceClientRef service = (__bridge IOHIDServiceClientRef)obj;
        NSString *product = CFBridgingRelease(IOHIDServiceClientCopyProperty(service, CFSTR("Product")));
        NSString *accelType = CFBridgingRelease(IOHIDServiceClientCopyProperty(service, CFSTR(kIOHIDPointerAccelerationTypeKey)));
        if (!product) continue;
        BOOL isTrackpad = [product rangeOfString:@"Trackpad" options:NSCaseInsensitiveSearch].location != NSNotFound;
        printf("- %s%s accelType=%s\n", product.UTF8String, isTrackpad ? " [TRACKPAD]" : "",
               accelType ? accelType.UTF8String : "(null)");
        if (listOnly || !isTrackpad) continue;

        NSString *key = accelType ?: @"HIDTrackpadAcceleration";
        int fixed = (int)(value * 65536);
        Boolean ok = IOHIDServiceClientSetProperty(service, (__bridge CFStringRef)key, (__bridge CFNumberRef)@(fixed));
        CFTypeRef readBack = IOHIDServiceClientCopyProperty(service, (__bridge CFStringRef)key);
        printf("  set %s=%d -> %s, readback=%s\n", key.UTF8String, fixed, ok ? "write OK" : "write FAILED",
               readBack ? [(__bridge NSObject *)readBack description].UTF8String : "(null)");
        if (readBack) CFRelease(readBack);
    }
    CFRelease(client);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSNumber *before = registryValue(@"HIDTrackpadAcceleration");
        printf("registry before: %d (= %.4f)\n", before.intValue, before.intValue / 65536.0);
        if (argc < 2) return 0;
        NSString *mode = @(argv[1]);
        double value = argc > 2 ? atof(argv[2]) : 1.5;
        if ([mode isEqualToString:@"param"]) routeParam(value);
        else if ([mode isEqualToString:@"service"]) routeService(value, NO);
        else routeService(0, YES);
    }
    return 0;
}

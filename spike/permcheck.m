// permcheck.m — report current TCC grants for this process context (no prompts).
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

int main(void) {
    printf("AXIsProcessTrusted (Accessibility):      %d\n", AXIsProcessTrusted());
    printf("CGPreflightListenEventAccess (InputMon): %d\n", CGPreflightListenEventAccess());
    printf("CGPreflightPostEventAccess (PostEvent):  %d\n", CGPreflightPostEventAccess());
    return 0;
}

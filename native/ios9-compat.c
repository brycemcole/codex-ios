#include <errno.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdint.h>
#include <sys/time.h>
#include <time.h>
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>

static mach_timebase_info_data_t timebase;
static pthread_once_t timebase_once = PTHREAD_ONCE_INIT;

static void initialize_timebase(void) {
    mach_timebase_info(&timebase);
}

int clock_gettime(unsigned int clock_id, struct timespec *result) {
    if (!result) {
        errno = EFAULT;
        return -1;
    }
    if (clock_id == 0) {
        struct timeval now;
        if (gettimeofday(&now, NULL) != 0) return -1;
        result->tv_sec = now.tv_sec;
        result->tv_nsec = now.tv_usec * 1000;
        return 0;
    }
    if (clock_id == 4 || clock_id == 5 || clock_id == 6 || clock_id == 8 || clock_id == 9) {
        pthread_once(&timebase_once, initialize_timebase);
        uint64_t ticks = mach_absolute_time();
        uint64_t ns = (ticks / timebase.denom) * timebase.numer
            + (ticks % timebase.denom) * timebase.numer / timebase.denom;
        result->tv_sec = ns / 1000000000;
        result->tv_nsec = ns % 1000000000;
        return 0;
    }
    errno = EINVAL;
    return -1;
}

int fclonefileat(int source, int directory, const char *destination, unsigned int flags) {
    errno = ENOTSUP;
    return -1;
}

Boolean SecTrustEvaluateWithError(SecTrustRef trust, CFErrorRef *error) {
    SecTrustResultType result = kSecTrustResultInvalid;
    OSStatus status = SecTrustEvaluate(trust, &result);
    if (error) *error = NULL;
    if (status == errSecSuccess && (result == kSecTrustResultProceed || result == kSecTrustResultUnspecified)) return true;
    if (error) *error = CFErrorCreate(kCFAllocatorDefault, kCFErrorDomainOSStatus, status == errSecSuccess ? -67843 : status, NULL);
    return false;
}

CFStringRef SecCopyErrorMessageString(OSStatus status, void *reserved) {
    return CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("Security error %ld"), (long)status);
}

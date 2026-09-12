#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/sysctl.h>
#include <sys/select.h>
#include <signal.h>
#include <errno.h>
#include <CoreFoundation/CoreFoundation.h>

typedef uint32_t IOPMAssertionID;
typedef uint32_t IOPMAssertionLevel;
extern OSStatus IOPMAssertionCreateWithName(CFStringRef, IOPMAssertionLevel, CFStringRef, IOPMAssertionID *);

static int get_free_pages(void) {
    int free_pages = 0;
    size_t len = sizeof(free_pages);
    if (sysctlbyname("vm.page_free_count", &free_pages, &len, NULL, 0) != 0) {
        return -1;
    }
    return free_pages;
}

static int is_codex_running(void) {
    int count = 0;
    FILE *fp = popen("/bin/ps -axo comm= | /usr/bin/grep -c '^/var/lib/codex-ios/bin/codex\\|^/usr/bin/codex'", "r");
    if (fp) {
        if (fscanf(fp, "%d", &count) != 1) count = 0;
        pclose(fp);
    }
    return count > 0;
}

static void do_reset(void) {
    system("/usr/bin/killall -9 codex 2>/dev/null; "
           "/bin/rm -f /var/mobile/.codex/app-server-daemon/*.pid "
           "/var/mobile/.codex/app-server-daemon/*.lock "
           "/var/mobile/.codex/app-server-daemon/*.sock 2>/dev/null; "
           "/usr/bin/killall -HUP syslogd 2>/dev/null || true");
}

int main(void) {
    IOPMAssertionID assertion_id = 0;
    CFStringRef type = CFSTR("PreventUserIdleSystemSleep");
    CFStringRef reason = CFSTR("CodexNetworkWatchdog");
    IOPMAssertionCreateWithName(type, 255, reason, &assertion_id);

    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) return 1;

    int opt = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(9999);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(sock);
        return 1;
    }

    char buf[512];

    while (1) {
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(sock, &fds);

        struct timeval tv;
        tv.tv_sec = 5;
        tv.tv_usec = 0;

        int ret = select(sock + 1, &fds, NULL, NULL, &tv);
        if (ret > 0 && FD_ISSET(sock, &fds)) {
            struct sockaddr_in client;
            socklen_t client_len = sizeof(client);
            ssize_t n = recvfrom(sock, buf, sizeof(buf) - 1, 0, (struct sockaddr *)&client, &client_len);
            if (n > 0) {
                buf[n] = '\0';
                if (strstr(buf, "RESET") || strstr(buf, "RESTART") || strstr(buf, "KILL")) {
                    do_reset();
                    const char *reply = "OK: RESET EXECUTED\n";
                    sendto(sock, reply, strlen(reply), 0, (struct sockaddr *)&client, client_len);
                } else if (strstr(buf, "STATUS")) {
                    int free_pages = get_free_pages();
                    int running = is_codex_running();
                    char reply[128];
                    snprintf(reply, sizeof(reply), "OK: FREE_PAGES=%d CODEX_RUNNING=%d\n", free_pages, running);
                    sendto(sock, reply, strlen(reply), 0, (struct sockaddr *)&client, client_len);
                } else {
                    const char *reply = "PONG\n";
                    sendto(sock, reply, strlen(reply), 0, (struct sockaddr *)&client, client_len);
                }
            }
        }

        (void)get_free_pages();
    }

    close(sock);
    return 0;
}

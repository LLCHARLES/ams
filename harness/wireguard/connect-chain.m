#import <Foundation/Foundation.h>
#import <Network/Network.h>
#import <arpa/inet.h>
#import <dlfcn.h>
#import <netdb.h>
#import <unistd.h>
#import "Core/SGRebind.h"
#import "Shared/Connect/Connect.h"
#import "Shared/WireGuard/SGWGCore.h"
#import "../harness-fail.h"

BOOL SGWGReady(void) { return YES; }
NSString *SGWGAppVersion(void) { return nil; }
id SGWGCreateNativeProxyConfig(void) { return nil; }

static ssize_t (*systemSendto)(int, const void *, size_t, int, const struct sockaddr *, socklen_t);
static ssize_t (*systemSendmsg)(int, const struct msghdr *, int);

static BOOL multicast(const struct sockaddr *address) {
    return address && address->sa_family == AF_INET &&
        IN_MULTICAST(ntohl(((const struct sockaddr_in *)address)->sin_addr.s_addr));
}
static ssize_t refuseSendto(int fd, const void *bytes, size_t size, int flags, const struct sockaddr *address, socklen_t length) {
    if (multicast(address)) { errno = EPERM; return -1; }
    return systemSendto(fd, bytes, size, flags, address, length);
}
static ssize_t refuseSendmsg(int fd, const struct msghdr *message, int flags) {
    if (multicast(message->msg_name)) { errno = EPERM; return -1; }
    return systemSendmsg(fd, message, flags);
}
static void installConnect(void) {
    HARNESS_CHECK(SGRebindImport("sendto", SGConnectSendto, (void **)&SGConnectRealSendto));
    HARNESS_CHECK(SGRebindImport("sendmsg", SGConnectSendmsg, (void **)&SGConnectRealSendmsg));
}
static int boundSocket(struct sockaddr_in *address) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    HARNESS_CHECK(fd >= 0);
    *address = (struct sockaddr_in){.sin_len = sizeof(*address), .sin_family = AF_INET,
        .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    HARNESS_CHECK(bind(fd, (const void *)address, sizeof(*address)) == 0);
    socklen_t size = sizeof(*address);
    HARNESS_CHECK(getsockname(fd, (void *)address, &size) == 0);
    struct timeval timeout = {.tv_sec = 3};
    HARNESS_CHECK(setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) == 0);
    return fd;
}
int main(int argc, char **argv) {
    @autoreleasepool {
        HARNESS_CHECK(argc == 3);
        HARNESS_CHECK(dlopen(argv[2], RTLD_NOW) != NULL);
        // The fixture supplies the entitlement refusal, not a replacement relay.
        HARNESS_CHECK(SGRebindImport("sendto", refuseSendto, (void **)&systemSendto));
        HARNESS_CHECK(SGRebindImport("sendmsg", refuseSendmsg, (void **)&systemSendmsg));
        SGConnectRealRecvfrom = recvfrom;
        if (!strcmp(argv[1], "wireguard-first")) {
            HARNESS_CHECK(SGWGInstallNativePatches());
            installConnect();
        } else {
            installConnect();
            HARNESS_CHECK(SGWGInstallNativePatches());
        }
        HARNESS_CHECK(SGWGInstallNativePatches()); // readiness refresh must not form a cycle

        int pair[2];
        HARNESS_CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
        HARNESS_CHECK(sendto(pair[0], "x", 1, 0, NULL, 0) == 1);
        struct sockaddr_in remote = {.sin_len = sizeof(remote), .sin_family = AF_INET};
        inet_pton(AF_INET, "192.0.2.1", &remote.sin_addr);
        HARNESS_CHECK(sendto(pair[0], "x", 1, 0, (const void *)&remote, sizeof(remote)) == -1 && errno == ENETUNREACH);
        close(pair[0]); close(pair[1]);

        // Exercise the other imported entry points with permitted local destinations.
        struct addrinfo *addresses = NULL;
        HARNESS_CHECK(getaddrinfo("127.0.0.1", "9", NULL, &addresses) == 0);
        freeaddrinfo(addresses);
        nw_connection_t connection = nw_connection_create(nw_endpoint_create_host("127.0.0.1", "9"),
            nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION));
        HARNESS_CHECK(connection != nil);
        nw_connection_cancel(connection);

        struct sockaddr_in local, receiverAddress;
        int spotify = boundSocket(&local), receiver = boundSocket(&receiverAddress);
        int connected = socket(AF_INET, SOCK_DGRAM, 0);
        HARNESS_CHECK(connect(connected, (const void *)&receiverAddress, sizeof(receiverAddress)) == 0);
        close(connected);
        SGConnectSetReceiver(@"fixture", @[[NSData dataWithBytes:&receiverAddress length:sizeof(receiverAddress)]]);
        struct sockaddr_in group = {.sin_len = sizeof(group), .sin_family = AF_INET,
            .sin_port = htons(5353), .sin_addr.s_addr = inet_addr("224.0.0.251")};
        const char queryTo[] = "\x00\x01\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00"
            "\x07" "_sendto" "\x04" "_sub" "\x10" "_spotify-connect" "\x04" "_tcp" "\x05" "local" "\x00\x00\x0c\x00\x01";
        const char queryMsg[] = "\x00\x02\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00"
            "\x08" "_sendmsg" "\x04" "_sub" "\x10" "_spotify-connect" "\x04" "_tcp" "\x05" "local" "\x00\x00\x0c\x00\x01";
        char received[256];
        HARNESS_CHECK(sendto(spotify, queryTo, sizeof(queryTo)-1, 0, (const void *)&group, sizeof(group)) == sizeof(queryTo)-1);
        HARNESS_CHECK(recvfrom(receiver, received, sizeof(received), 0, NULL, NULL) == sizeof(queryTo)-1);
        HARNESS_CHECK(!memcmp(received, queryTo, sizeof(queryTo)-1));
        struct iovec part = {(void *)queryMsg, sizeof(queryMsg)-1};
        struct msghdr message = {.msg_name = &group, .msg_namelen = sizeof(group), .msg_iov = &part, .msg_iovlen = 1};
        HARNESS_CHECK(sendmsg(spotify, &message, 0) == sizeof(queryMsg)-1);
        HARNESS_CHECK(recvfrom(receiver, received, sizeof(received), 0, NULL, NULL) == sizeof(queryMsg)-1);
        HARNESS_CHECK(!memcmp(received, queryMsg, sizeof(queryMsg)-1));
        group.sin_addr.s_addr = inet_addr("1.1.1.1");
        group.sin_port = htons(53);
        HARNESS_CHECK(sendto(spotify, queryTo, sizeof(queryTo)-1, 0, (const void *)&group, sizeof(group)) == -1 && errno == ENETUNREACH);
        close(spotify);
        close(receiver);
        printf("PASS %s: Connect sendto/sendmsg relay delivered exact queries; remote DNS denied\n", argv[1]);
    }
    return 0;
}

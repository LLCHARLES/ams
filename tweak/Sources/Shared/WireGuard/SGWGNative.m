// Only admitted Spotify images are rebound. BSD remote traffic is denied;
// Network.framework retains the original endpoint and TLS identity.
#import "SGWGCore.h"
#import "SGWGBridge.h"
#import "Core/SGRebind.h"
#import <Network/Network.h>
#import <arpa/inet.h>
#import <dlfcn.h>
#import <errno.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <netdb.h>
#import <stdatomic.h>
#import <sys/socket.h>

static void *(*realNWCreate)(void *, void *);
static int (*realConnect)(int, const struct sockaddr *, socklen_t);
static int (*realGetaddrinfo)(const char *, const char *, const struct addrinfo *, struct addrinfo **);
static ssize_t (*realSendto)(int, const void *, size_t, int, const struct sockaddr *, socklen_t);
static ssize_t (*realSendmsg)(int, const struct msghdr *, int);
static atomic_uint nwProxied, nwBlocked, bsdDenied;
static atomic_uint expectedSlots, installedSlots, deferredSlots;

static BOOL ValidAddress(const struct sockaddr *address, socklen_t length) {
    if (!address || length < sizeof(struct sockaddr)) return NO;
    if (address->sa_family == AF_INET) return length >= sizeof(struct sockaddr_in);
    if (address->sa_family == AF_INET6) return length >= sizeof(struct sockaddr_in6);
    return length >= address->sa_len;
}

static BOOL LocalAddress(const struct sockaddr *address, socklen_t length) {
    if (!ValidAddress(address, length)) return NO;
    if (address->sa_family == AF_INET) {
        uint32_t ip = ntohl(((const struct sockaddr_in *)address)->sin_addr.s_addr);
        return (ip >> 24) == 127 || (ip >> 16) == 0xA9FE || IN_MULTICAST(ip);
    }
    if (address->sa_family == AF_INET6) {
        const struct in6_addr *ip = &((const struct sockaddr_in6 *)address)->sin6_addr;
        return IN6_IS_ADDR_LOOPBACK(ip) || IN6_IS_ADDR_LINKLOCAL(ip) || IN6_IS_ADDR_MULTICAST(ip);
    }
    return address->sa_family == AF_UNIX;
}

static BOOL LocalName(const char *name) {
    if (!name || !*name || !strcasecmp(name, "localhost")) return YES;
    size_t size = strlen(name);
    return (size >= 6 && !strcasecmp(name + size - 6, ".local")) ||
           (size >= 10 && !strcasecmp(name + size - 10, ".localhost"));
}

static BOOL LocalEndpoint(nw_endpoint_t endpoint) {
    if (!endpoint) return NO;
    nw_endpoint_type_t type = nw_endpoint_get_type(endpoint);
    if (type == nw_endpoint_type_bonjour_service) return YES;
    if (type == nw_endpoint_type_address) {
        const struct sockaddr *address = nw_endpoint_get_address(endpoint);
        return address && LocalAddress(address, address->sa_len);
    }
    if (type != nw_endpoint_type_host) return NO;
    const char *name = nw_endpoint_get_hostname(endpoint);
    if (!name) return NO;
    if (LocalName(name)) return YES;
    struct sockaddr_in v4 = {.sin_family = AF_INET};
    struct sockaddr_in6 v6 = {.sin6_family = AF_INET6};
    if (inet_pton(AF_INET, name, &v4.sin_addr) == 1)
        return LocalAddress((struct sockaddr *)&v4, sizeof(v4));
    if (inet_pton(AF_INET6, name, &v6.sin6_addr) == 1)
        return LocalAddress((struct sockaddr *)&v6, sizeof(v6));
    return NO;
}

static int HookGetaddrinfo(const char *name, const char *service,
                           const struct addrinfo *hints, struct addrinfo **result) {
    struct in_addr v4;
    struct in6_addr v6;
    BOOL numeric = name && (inet_pton(AF_INET, name, &v4) == 1 || inet_pton(AF_INET6, name, &v6) == 1);
    if (LocalName(name) || numeric || (hints && (hints->ai_flags & AI_NUMERICHOST)))
        return realGetaddrinfo ? realGetaddrinfo(name, service, hints, result) : EAI_FAIL;
    // BSD remote connects are denied, so resolving their names serves no purpose.
    if (result) *result = NULL;
    return EAI_FAIL;
}

static void *HookNWCreate(void *rawEndpoint, void *rawParameters) {
    nw_endpoint_t endpoint = (__bridge nw_endpoint_t)rawEndpoint;
    nw_parameters_t parameters = (__bridge nw_parameters_t)rawParameters;
    if (LocalEndpoint(endpoint)) return realNWCreate ? realNWCreate(rawEndpoint, rawParameters) : NULL;
    nw_protocol_stack_t stack = parameters ? nw_parameters_copy_default_protocol_stack(parameters) : nil;
    nw_protocol_options_t transport = stack ? nw_protocol_stack_copy_transport_protocol(stack) : nil;
    nw_protocol_definition_t definition = transport ? nw_protocol_options_copy_definition(transport) : nil;
    nw_protocol_definition_t tcp = nw_protocol_copy_tcp_definition();
    if (!SGWGReady() || !realNWCreate || !definition || !nw_protocol_definition_is_equal(definition, tcp)) {
        atomic_fetch_add(&nwBlocked, 1);
        return NULL;
    }
    id proxy = SGWGCreateNativeProxyConfig();
    typedef void (*AddProxy)(nw_privacy_context_t, nw_proxy_config_t);
    AddProxy add = (AddProxy)dlsym(RTLD_DEFAULT, "nw_privacy_context_add_proxy");
    nw_parameters_t copy = nw_parameters_copy(parameters);
    nw_privacy_context_t context = nw_privacy_context_create("retrine.spotify.experimental");
    if (!proxy || !add || !copy || !context) { atomic_fetch_add(&nwBlocked, 1); return NULL; }
    add(context, (nw_proxy_config_t)proxy);
    nw_parameters_set_privacy_context(copy, context);
    atomic_fetch_add(&nwProxied, 1);
    return realNWCreate(rawEndpoint, (__bridge void *)copy);
}

static BOOL NoSIGPIPE(int fd) {
    int enabled = 1;
    return setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, sizeof(enabled)) == 0;
}

static int HookConnect(int fd, const struct sockaddr *address, socklen_t length) {
    if (!ValidAddress(address, length)) { errno = EINVAL; return -1; }
    if (!LocalAddress(address, length)) {
        atomic_fetch_add(&bsdDenied, 1);
        errno = ENETUNREACH;
        return -1;
    }
    if (!realConnect || !NoSIGPIPE(fd)) return -1;
    return realConnect(fd, address, length);
}

static BOOL AllowSend(int fd, const struct sockaddr *address, socklen_t length) {
    struct sockaddr_storage peer;
    if (address && !ValidAddress(address, length)) { errno = EINVAL; return NO; }
    int kind = 0;
    socklen_t size = sizeof(kind);
    if (getsockopt(fd, SOL_SOCKET, SO_TYPE, &kind, &size)) return NO;
    if (kind == SOCK_DGRAM) {
        if (!address) {
            length = sizeof(peer);
            if (getpeername(fd, (struct sockaddr *)&peer, &length)) return NO;
            address = (const struct sockaddr *)&peer;
        }
        if (!LocalAddress(address, length)) {
            atomic_fetch_add(&bsdDenied, 1);
            errno = ENETUNREACH;
            return NO;
        }
    }
    return NoSIGPIPE(fd);
}

static ssize_t HookSendto(int fd, const void *bytes, size_t size, int flags,
                          const struct sockaddr *address, socklen_t length) {
    if (!realSendto || !AllowSend(fd, address, length)) return -1;
    return realSendto(fd, bytes, size, flags, address, length);
}
static ssize_t HookSendmsg(int fd, const struct msghdr *message, int flags) {
    if (!message) { errno = EINVAL; return -1; }
    if (!realSendmsg || !AllowSend(fd, message->msg_name, message->msg_namelen)) return -1;
    return realSendmsg(fd, message, flags);
}

BOOL SGWGInstallNativePatches(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        realNWCreate = dlsym(RTLD_DEFAULT, "nw_connection_create");
        realConnect = dlsym(RTLD_DEFAULT, "connect");
        realGetaddrinfo = dlsym(RTLD_DEFAULT, "getaddrinfo");
#ifdef SGWG_TESTING
        realSendto = dlsym(RTLD_DEFAULT, "sendto");
        realSendmsg = dlsym(RTLD_DEFAULT, "sendmsg");
#endif
    });
    if (!realNWCreate || !realConnect || !realGetaddrinfo) return NO;
#ifdef SGWG_TESTING
    return YES;
#else
    const char *symbols[] = {"nw_connection_create", "connect", "getaddrinfo", "sendto", "sendmsg"};
    void *replacements[] = {HookNWCreate, HookConnect, HookGetaddrinfo, HookSendto, HookSendmsg};
    void **originals[] = {NULL, NULL, NULL, (void **)&realSendto, (void **)&realSendmsg};
    NSUInteger expected = 0, installed = 0, deferred = 0;
    BOOL complete = YES, mainSeen = NO, sharedSeen = NO;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        NSString *name = @(_dyld_get_image_name(i)).lastPathComponent;
        BOOL main = [name isEqualToString:@"Spotify"] ||
            [name isEqualToString:[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"]];
        BOOL shared = [name isEqualToString:@"SpotifyShared"];
        if (!main && !shared) continue;
        mainSeen |= main; sharedSeen |= shared;
        const struct mach_header *header = _dyld_get_image_header(i);
        if (header->magic != MH_MAGIC_64) { complete = NO; continue; }
        for (NSUInteger j = 0; j < sizeof(symbols) / sizeof(*symbols); j++) {
            SGImportSlots slots = SGRebindImageImport((const struct mach_header_64 *)header,
                _dyld_get_image_vmaddr_slide(i), symbols[j], replacements[j], originals[j]);
            expected += slots.expected; installed += slots.installed; deferred += slots.deferred;
            complete &= slots.inspected && slots.expected == slots.installed && (!main || slots.expected > 0);
        }
    }
    atomic_store(&expectedSlots, (unsigned)expected);
    atomic_store(&installedSlots, (unsigned)installed);
    atomic_store(&deferredSlots, (unsigned)deferred);
    return complete && mainSeen && sharedSeen;
#endif
}

NSArray<NSString *> *SGWGNativeReportLines(void) {
    return @[[NSString stringWithFormat:@"native.slots: expected %u guarded %u deferred %u",
        atomic_load(&expectedSlots), atomic_load(&installedSlots), atomic_load(&deferredSlots)],
        [NSString stringWithFormat:@"native.paths: Network TCP %u denied %u; BSD denied %u",
        atomic_load(&nwProxied), atomic_load(&nwBlocked), atomic_load(&bsdDenied)],
        @"BSD remote TCP/UDP denied; local discovery exempt; not a leak-proof VPN"];
}

#ifdef SGWG_TESTING
nw_connection_t SGWGNativeTestNWCreate(nw_endpoint_t endpoint, nw_parameters_t parameters) {
    return (__bridge_transfer nw_connection_t)HookNWCreate((__bridge void *)endpoint, (__bridge void *)parameters);
}
int SGWGNativeTestGetaddrinfo(const char *name, const char *service, const struct addrinfo *hints, struct addrinfo **result) {
    return HookGetaddrinfo(name, service, hints, result);
}
int SGWGNativeTestConnect(int fd, const struct sockaddr *address, socklen_t length) { return HookConnect(fd, address, length); }
ssize_t SGWGNativeTestSendto(int fd, const void *bytes, size_t size, int flags, const struct sockaddr *address, socklen_t length) {
    return HookSendto(fd, bytes, size, flags, address, length);
}
#endif

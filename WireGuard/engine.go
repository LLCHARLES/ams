package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"net"
	"net/netip"
	"runtime/debug"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"
)

func init() {
	// Leave the normal doubling pace alone for short transfers; start GC
	// earlier under sustained load. This limits Go-managed memory, not RSS.
	debug.SetGCPercent(100)
	debug.SetMemoryLimit(64 << 20)
}

// Engine runs wireguard-go on a gVisor userspace network stack and exposes an
// authenticated SOCKS5 / HTTP CONNECT proxy on 127.0.0.1 for this process only.
//
// No system TUN, route table, VPN profile or Network Extension is involved: the
// only sockets opened on the device are the WireGuard UDP socket and the local
// loopback listener. Every proxied TCP connection, and every DNS lookup for a
// proxied hostname, goes through the WireGuard tunnel. There is no net.Dial
// fallback anywhere in the data path.
type engineDevice interface {
	BindUpdate() error
	Close()
	IpcGet() (string, error)
}

type Engine struct {
	dev   engineDevice
	stack interface {
		DialContext(context.Context, string, string) (net.Conn, error)
		LookupContextHost(context.Context, string) ([]string, error)
	}
	user []byte
	pass []byte
	port int

	mu           sync.Mutex
	listener     net.Listener
	anchor       io.Closer
	rearm        func() (net.Listener, error)
	clients      map[net.Conn]struct{}
	deadListener net.Listener
	wantBind     bool
	repairCancel context.CancelFunc
	repairDone   chan struct{}
	repairWake   chan struct{}

	dialTimeout  time.Duration
	stopped      atomic.Bool
	stateMu      sync.Mutex
	state        int
	unavailable  uint8
	stateChanged func(int)
	admitted     func() bool

	// Counters. Only counts are kept; hostnames, URLs and addresses are not.
	total, active, failed, dnsFailed atomic.Int64
	domainTargets, ipTargets         atomic.Int64
	viaSOCKS, viaCONNECT             atomic.Int64
	authRejected, badRequests        atomic.Int64
	media, api, other                atomic.Int64
	upBytes, downBytes               atomic.Int64
	bindUpdates, bindFailures        atomic.Int64
	relistens                        atomic.Int64
	started                          time.Time
	endpointResolvedLocally          bool
	pendingAuth                      chan struct{}
}

const maxUnauthenticatedClients = 32
const authenticationTimeout = 3 * time.Second
const (
	listenerUnavailable uint8 = 1 << iota
	bindUnavailable
)

type EngineOptions struct {
	// Activate the reserved socket only after bootstrap succeeds. Until then
	// the OS refuses queued traffic rather than holding clients across retries.
	Listen      func() (net.Listener, error)
	Admitted    func() bool
	DialTimeout time.Duration
	// SGWGEngineEvent from the shared bridge header. No traffic details.
	StateChanged func(int)
	// Resolve resolves a hostname Endpoint. It is the one lookup that cannot go
	// through the tunnel, because it is needed to reach the tunnel.
	Resolve func(ctx context.Context, host string) ([]netip.Addr, error)
}

var (
	errStackInit         = errors.New("userspace network initialization failed")
	errWGConfig          = errors.New("WireGuard configuration failed")
	errWGUp              = errors.New("WireGuard UDP initialization failed")
	errListen            = errors.New("local proxy initialization failed")
	errListenerTemporary = errors.New("local proxy temporarily unavailable")
	errEndpointDNS       = errors.New("WireGuard endpoint hostname could not be resolved")
	errCredentials       = errors.New("local proxy credentials are required")
	errNoSuitableEP      = errors.New("WireGuard endpoint has no usable address")
)

func defaultResolve(ctx context.Context, host string) ([]netip.Addr, error) {
	return net.DefaultResolver.LookupNetIP(ctx, "ip", host)
}

func StartEngine(p *Profile, user, pass string, opt EngineOptions) (*Engine, error) {
	defer p.clearKeys()
	if len(user) == 0 || len(pass) == 0 || len(user) > 255 || len(pass) > 255 {
		return nil, errCredentials
	}
	endpoint, local, err := resolveEndpoint(p, opt.Resolve)
	if err != nil {
		return nil, err
	}
	tunDev, stack, err := netstack.CreateNetTUN(p.Addresses, p.DNS, p.MTU)
	if err != nil {
		return nil, errStackInit
	}
	dev := device.NewDevice(tunDev, conn.NewDefaultBind(), device.NewLogger(device.LogLevelSilent, ""))
	config := p.uapi(endpoint)
	configErr := dev.IpcSetOperation(bytes.NewReader(config))
	clear(config)
	if configErr != nil {
		dev.Close()
		return nil, errWGConfig
	}
	if err := dev.Up(); err != nil {
		dev.Close()
		return nil, errWGUp
	}
	listener, err := opt.Listen()
	if err != nil {
		dev.Close()
		if retryableListenerError(err) {
			return nil, errListenerTemporary
		}
		return nil, errListen
	}
	e := &Engine{
		dev: dev, stack: stack, user: []byte(user), pass: []byte(pass),
		listener: listener, rearm: opt.Listen, clients: map[net.Conn]struct{}{},
		dialTimeout: opt.DialTimeout, started: time.Now(), endpointResolvedLocally: local,
		pendingAuth:  make(chan struct{}, maxUnauthenticatedClients),
		stateChanged: opt.StateChanged, admitted: opt.Admitted,
	}
	if e.dialTimeout <= 0 {
		e.dialTimeout = 15 * time.Second
	}
	if addr, ok := listener.Addr().(*net.TCPAddr); ok {
		e.port = addr.Port
	}
	e.setUnavailable(listenerUnavailable, false)
	go e.acceptLoop(listener)
	return e, nil
}

func resolveEndpoint(p *Profile, resolve func(context.Context, string) ([]netip.Addr, error)) (netip.AddrPort, bool, error) {
	if addr, err := netip.ParseAddr(p.EndpointHost); err == nil {
		return netip.AddrPortFrom(addr, uint16(p.EndpointPort)), false, nil
	}
	if resolve == nil {
		resolve = defaultResolve
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	addrs, err := resolve(ctx, p.EndpointHost)
	if err != nil || len(addrs) == 0 {
		return netip.AddrPort{}, true, errEndpointDNS
	}
	for _, a := range addrs { // prefer IPv4: it works on every network
		if a.Unmap().Is4() {
			return netip.AddrPortFrom(a.Unmap(), uint16(p.EndpointPort)), true, nil
		}
	}
	for _, a := range addrs {
		if a.Is6() {
			return netip.AddrPortFrom(a, uint16(p.EndpointPort)), true, nil
		}
	}
	return netip.AddrPort{}, true, errNoSuitableEP
}

func (e *Engine) Port() int { return e.port }

func (e *Engine) publishStateLocked(state int) {
	if e.stopped.Load() && state != engineStopped {
		return
	}
	if state != engineDestinationFailed {
		if e.state == state {
			return
		}
		e.state = state
	}
	if e.stateChanged != nil {
		e.stateChanged(state)
	}
}

func (e *Engine) reportState(state int) {
	e.stateMu.Lock()
	defer e.stateMu.Unlock()
	e.publishStateLocked(state)
}

func (e *Engine) setUnavailable(component uint8, failed bool) {
	e.stateMu.Lock()
	defer e.stateMu.Unlock()
	if failed {
		e.unavailable |= component
	} else {
		e.unavailable &^= component
	}
	state := engineAvailable
	if e.unavailable != 0 {
		state = engineUnavailable
	}
	e.publishStateLocked(state)
}

func (e *Engine) Close() {
	if e.stopped.Swap(true) {
		return
	}
	e.reportState(engineStopped)
	e.mu.Lock()
	done := e.repairDone
	if e.repairCancel != nil {
		e.repairCancel()
	}
	e.listener.Close()
	for c := range e.clients {
		c.Close()
	}
	e.mu.Unlock()
	if done != nil {
		<-done
	}
	if e.anchor != nil {
		e.anchor.Close()
	}
	e.dev.Close()
}

func (e *Engine) track(c net.Conn) bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.stopped.Load() {
		return false
	}
	e.clients[c] = struct{}{}
	return true
}

func (e *Engine) untrack(c net.Conn) {
	e.mu.Lock()
	delete(e.clients, c)
	e.mu.Unlock()
}

func (e *Engine) acceptLoop(l net.Listener) {
	failures := 0
	for {
		c, err := l.Accept()
		if err != nil {
			if e.stopped.Load() {
				return
			}
			var ne net.Error
			if errors.As(err, &ne) && ne.Timeout() && failures < 50 {
				failures++
				time.Sleep(20 * time.Millisecond)
				continue
			}
			e.listenerFailed(l)
			return
		}
		failures = 0
		if e.admitted != nil && !e.admitted() {
			c.Close()
			continue
		}
		select {
		case e.pendingAuth <- struct{}{}:
		default:
			e.authRejected.Add(1)
			c.Close()
			continue
		}
		if !e.track(c) {
			<-e.pendingAuth
			c.Close()
			return
		}
		go func() {
			defer e.untrack(c)
			defer c.Close()
			release := sync.OnceFunc(func() { <-e.pendingAuth })
			defer release()
			e.serve(c, func() {
				release()
				e.mu.Lock()
				if e.deadListener != nil && !e.stopped.Load() {
					e.startRepairLocked()
				}
				e.mu.Unlock()
			})
		}()
	}
}

func (e *Engine) listenerFailed(l net.Listener) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.listener != l || e.stopped.Load() {
		return
	}
	e.deadListener = l
	e.setUnavailable(listenerUnavailable, true)
	e.startRepairLocked()
}

// Request only: neither the control queue nor Accept performs socket repair.
func (e *Engine) Rebind() error {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.stopped.Load() {
		return net.ErrClosed
	}
	e.wantBind = true
	e.startRepairLocked()
	return nil
}

func (e *Engine) startRepairLocked() {
	if e.repairDone != nil {
		if e.repairWake != nil {
			close(e.repairWake)
			e.repairWake = nil
		}
		return
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	e.repairCancel, e.repairDone = cancel, done
	go e.repair(ctx, done)
}

func (e *Engine) repair(ctx context.Context, done chan struct{}) {
	// A new path requests a bounded UDP retry series. The published TCP
	// socket instead needs an acceptor as long as the engine is alive.
	var bindAt, listenAt time.Time
	var bindAttempts int
	const quick = 100 * time.Millisecond
	var listenDelay time.Duration
	e.mu.Lock()
	for ctx.Err() == nil {
		// Requests coalesce until this worker consumes the wake, even if
		// they arrive during a syscall rather than during the timer wait.
		if e.repairWake == nil {
			e.repairWake = make(chan struct{})
			listenDelay, listenAt = quick, time.Time{}
		}
		now := time.Now()
		if e.wantBind {
			bindAttempts, bindAt = 0, now
		}
		bind := !bindAt.IsZero() && !bindAt.After(now)
		dead := e.deadListener
		if !bind && (dead == nil || listenAt.After(now)) {
			next := bindAt
			if dead != nil && (next.IsZero() || listenAt.Before(next)) {
				next = listenAt
			}
			if next.IsZero() {
				break
			}
			wake := e.repairWake
			e.mu.Unlock()
			select {
			case <-wake:
			case <-ctx.Done():
			case <-time.After(time.Until(next)):
			}
			e.mu.Lock()
			continue
		}
		e.mu.Unlock()
		if bind {
			bindFailed := e.dev.BindUpdate() != nil
			// Only requests overlapping this UDP update were reconciled. A
			// request during subsequent listener work belongs to the next pass.
			e.mu.Lock()
			e.wantBind = false
			e.mu.Unlock()
			bindAt = time.Time{}
			bindAttempts++
			if bindFailed {
				e.bindFailures.Add(1)
				if bindAttempts < 5 {
					bindAt = time.Now().Add(100 * time.Millisecond << (bindAttempts - 1))
				}
			} else {
				e.bindUpdates.Add(1)
			}
			e.setUnavailable(bindUnavailable, bindFailed)
		}
		if dead != nil && !listenAt.After(time.Now()) && ctx.Err() == nil {
			replacement, err := e.rearm()
			if err == nil {
				listenDelay, listenAt = quick, time.Time{}
				e.mu.Lock()
				if replacement != dead {
					dead.Close()
				}
				if e.stopped.Load() {
					replacement.Close()
				} else {
					e.listener, e.deadListener = replacement, nil
					e.relistens.Add(1)
					e.setUnavailable(listenerUnavailable, false)
					go e.acceptLoop(replacement)
				}
				e.mu.Unlock()
			} else {
				// An accept error is not proof that the shared socket has
				// stopped listening. Keep one cancellable, rate-limited owner.
				listenAt = time.Now().Add(listenDelay)
				listenDelay = min(2*listenDelay, time.Minute)
			}
		}
		e.mu.Lock()
	}
	e.repairCancel()
	e.wantBind = false
	e.repairCancel, e.repairDone, e.repairWake = nil, nil, nil
	close(done)
	e.mu.Unlock()
}

func retryableListenerError(err error) bool {
	return errors.Is(err, syscall.EMFILE) || errors.Is(err, syscall.ENFILE) ||
		errors.Is(err, syscall.ENOMEM) || errors.Is(err, syscall.ENOBUFS) ||
		errors.Is(err, syscall.EINTR) || errors.Is(err, syscall.ECONNABORTED)
}

// classify counts the destination family without storing the hostname.
func (e *Engine) classify(host string) {
	h := strings.TrimSuffix(strings.ToLower(host), ".")
	switch {
	case strings.HasPrefix(h, "audio") && (hasSuffix(h, "scdn.co") || hasSuffix(h, "spotifycdn.com") || hasSuffix(h, "akamaized.net")):
		e.media.Add(1)
	case hasSuffix(h, "spotify.com"), hasSuffix(h, "spotify.net"):
		e.api.Add(1)
	default:
		e.other.Add(1)
	}
}

func hasSuffix(host, domain string) bool {
	return host == domain || strings.HasSuffix(host, "."+domain)
}

func (e *Engine) dial(host string, port int) (net.Conn, error) {
	if e.admitted != nil && !e.admitted() {
		return nil, net.ErrClosed
	}
	e.total.Add(1)
	if _, err := netip.ParseAddr(host); err == nil {
		e.ipTargets.Add(1)
		e.other.Add(1)
	} else {
		e.domainTargets.Add(1)
		e.classify(host)
	}
	ctx, cancel := context.WithTimeout(context.Background(), e.dialTimeout)
	defer cancel()
	// Hostnames are resolved by netstack's resolver, which queries the
	// profile's DNS servers through the tunnel. There is no direct fallback.
	addresses, err := e.destinationAddresses(ctx, host)
	var c net.Conn
	if err == nil {
		deadline, _ := ctx.Deadline()
		for i, address := range addresses {
			if e.admitted != nil && !e.admitted() {
				return nil, net.ErrClosed
			}
			left := time.Until(deadline)
			if left <= 0 {
				err = context.DeadlineExceeded
				break
			}
			attempt, stop := context.WithTimeout(ctx, left/time.Duration(len(addresses)-i))
			c, err = e.stack.DialContext(attempt, "tcp", net.JoinHostPort(address.String(), strconv.Itoa(port)))
			stop()
			if err == nil {
				break
			}
		}
	}
	if err != nil {
		e.failed.Add(1)
		e.reportState(engineDestinationFailed)
		var dnsErr *net.DNSError
		if errors.As(err, &dnsErr) {
			e.dnsFailed.Add(1)
		}
		return nil, err
	}
	return c, nil
}

func (e *Engine) serve(c net.Conn, authenticated func()) {
	c.SetDeadline(time.Now().Add(authenticationTimeout))
	r := bufio.NewReaderSize(c, 4096)
	first, err := r.Peek(1)
	if err != nil {
		return
	}
	switch {
	case first[0] == 5:
		e.serveSOCKS(c, r, authenticated)
	case first[0] >= 'A' && first[0] <= 'Z':
		e.serveCONNECT(c, r, authenticated)
	default:
		e.badRequests.Add(1)
	}
}

func (e *Engine) authorized(user, pass []byte) bool {
	u := subtle.ConstantTimeCompare(user, e.user)
	p := subtle.ConstantTimeCompare(pass, e.pass)
	return u&p == 1
}

func (e *Engine) serveSOCKS(c net.Conn, r *bufio.Reader, authenticated func()) {
	head := make([]byte, 2)
	if _, err := io.ReadFull(r, head); err != nil || head[0] != 5 {
		return
	}
	methods := make([]byte, int(head[1]))
	if _, err := io.ReadFull(r, methods); err != nil {
		return
	}
	userPass := false
	for _, m := range methods {
		if m == 2 {
			userPass = true
		}
	}
	if !userPass { // "no authentication" is never accepted
		e.authRejected.Add(1)
		c.Write([]byte{5, 0xff})
		return
	}
	if _, err := c.Write([]byte{5, 2}); err != nil {
		return
	}
	if _, err := io.ReadFull(r, head); err != nil || head[0] != 1 {
		return
	}
	user := make([]byte, int(head[1]))
	if _, err := io.ReadFull(r, user); err != nil {
		return
	}
	if _, err := io.ReadFull(r, head[:1]); err != nil {
		return
	}
	pass := make([]byte, int(head[0]))
	if _, err := io.ReadFull(r, pass); err != nil {
		return
	}
	if !e.authorized(user, pass) {
		e.authRejected.Add(1)
		c.Write([]byte{1, 1})
		return
	}
	if _, err := c.Write([]byte{1, 0}); err != nil {
		return
	}
	authenticated()
	c.SetDeadline(time.Now().Add(e.dialTimeout))
	req := make([]byte, 4)
	if _, err := io.ReadFull(r, req); err != nil || req[0] != 5 {
		return
	}
	if req[1] != 1 { // only CONNECT; UDP ASSOCIATE/BIND are refused (no UDP bypass)
		e.badRequests.Add(1)
		c.Write([]byte{5, 7, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	var host string
	switch req[3] {
	case 1:
		b := make([]byte, 4)
		if _, err := io.ReadFull(r, b); err != nil {
			return
		}
		host = netip.AddrFrom4([4]byte(b)).String()
	case 4:
		b := make([]byte, 16)
		if _, err := io.ReadFull(r, b); err != nil {
			return
		}
		host = netip.AddrFrom16([16]byte(b)).Unmap().String()
	case 3:
		if _, err := io.ReadFull(r, head[:1]); err != nil || head[0] == 0 {
			return
		}
		b := make([]byte, int(head[0]))
		if _, err := io.ReadFull(r, b); err != nil {
			return
		}
		host = string(b)
	default:
		c.Write([]byte{5, 8, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	if _, err := io.ReadFull(r, head); err != nil {
		return
	}
	port := int(head[0])<<8 | int(head[1])
	if port == 0 {
		return
	}
	e.viaSOCKS.Add(1)
	upstream, err := e.dial(host, port)
	if err != nil {
		c.Write([]byte{5, 4, 0, 1, 0, 0, 0, 0, 0, 0}) // host unreachable
		return
	}
	if _, err := c.Write([]byte{5, 0, 0, 1, 0, 0, 0, 0, 0, 0}); err != nil {
		upstream.Close()
		return
	}
	e.pipe(c, r, upstream)
}

const proxyAuthRequired = "HTTP/1.1 407 Proxy Authentication Required\r\n" +
	"Proxy-Authenticate: Basic realm=\"ytmu\"\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"

// serveCONNECT accepts HTTP CONNECT (used by FFmpeg's http_proxy for HTTPS
// downloads). Plain absolute-URI HTTP proxying is refused so that nothing is
// forwarded outside a tunnelled byte stream.
func (e *Engine) serveCONNECT(c net.Conn, r *bufio.Reader, authenticated func()) {
	var lines []string
	size := 0
	for {
		lineBytes, err := r.ReadSlice('\n')
		if err != nil {
			return
		}
		line := string(lineBytes)
		size += len(line)
		if size > 16*1024 {
			e.badRequests.Add(1)
			io.WriteString(c, "HTTP/1.1 431 Request Header Fields Too Large\r\nConnection: close\r\n\r\n")
			return
		}
		line = strings.TrimRight(line, "\r\n")
		if line == "" {
			break
		}
		lines = append(lines, line)
	}
	if len(lines) == 0 {
		return
	}
	parts := strings.Fields(lines[0])
	if len(parts) != 3 || parts[0] != "CONNECT" || !strings.HasPrefix(parts[2], "HTTP/1.") {
		e.badRequests.Add(1)
		io.WriteString(c, "HTTP/1.1 405 Method Not Allowed\r\nAllow: CONNECT\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
		return
	}
	authorized := false
	for _, h := range lines[1:] {
		name, value, ok := strings.Cut(h, ":")
		if !ok || !strings.EqualFold(strings.TrimSpace(name), "Proxy-Authorization") {
			continue
		}
		scheme, cred, _ := strings.Cut(strings.TrimSpace(value), " ")
		if !strings.EqualFold(scheme, "Basic") {
			continue
		}
		raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(cred))
		if err != nil {
			continue
		}
		u, p, ok := strings.Cut(string(raw), ":")
		if ok && e.authorized([]byte(u), []byte(p)) {
			authorized = true
		}
	}
	if !authorized {
		e.authRejected.Add(1)
		io.WriteString(c, proxyAuthRequired)
		return
	}
	authenticated()
	c.SetDeadline(time.Now().Add(e.dialTimeout))
	host, portText, err := net.SplitHostPort(parts[1])
	port, perr := strconv.Atoi(portText)
	if err != nil || perr != nil || host == "" || port < 1 || port > 65535 {
		e.badRequests.Add(1)
		io.WriteString(c, "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
		return
	}
	e.viaCONNECT.Add(1)
	upstream, err := e.dial(host, port)
	if err != nil {
		io.WriteString(c, "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
		return
	}
	if _, err := io.WriteString(c, "HTTP/1.1 200 Connection Established\r\n\r\n"); err != nil {
		upstream.Close()
		return
	}
	e.pipe(c, r, upstream)
}

type streamProgress struct {
	last     atomic.Int64
	watching atomic.Bool // this direction has a write deadline or has sent FIN
}

type countingWriter struct {
	dst   net.Conn
	n     *atomic.Int64
	start time.Time
	self  *streamProgress
	peer  *streamProgress
}

const streamIdleTimeout = 30 * time.Second

func (cw countingWriter) Write(p []byte) (int, error) {
	// A blocked write can hide its reader's FIN. Bound that write, not the
	// wait for the next byte on a healthy open stream.
	cw.self.watching.Store(true)
	defer cw.self.watching.Store(false)
	deadline := cw.start.Add(time.Since(cw.start) + streamIdleTimeout)
	written := 0
	for {
		if err := cw.dst.SetWriteDeadline(deadline); err != nil {
			return written, err
		}
		n, err := cw.dst.Write(p[written:])
		written += n
		cw.n.Add(int64(n))
		// Only a concurrent blocked write or half-close drain needs this
		// completion time. A later watcher starts its own full idle window.
		if n > 0 && (err != nil || cw.peer.watching.Load()) {
			cw.self.last.Store(int64(time.Since(cw.start)))
		}
		if err == nil {
			return written, nil
		}
		var timeout net.Error
		if !errors.As(err, &timeout) || !timeout.Timeout() {
			return written, err
		}
		until := time.Duration(max(cw.self.last.Load(), cw.peer.last.Load())) + streamIdleTimeout
		if time.Since(cw.start) >= until {
			return written, err
		}
		deadline = cw.start.Add(until)
	}
}

func (e *Engine) pipe(c net.Conn, r *bufio.Reader, upstream net.Conn) {
	if !e.track(upstream) {
		upstream.Close()
		return
	}
	defer e.untrack(upstream)
	defer upstream.Close()
	c.SetDeadline(time.Time{})
	e.active.Add(1)
	defer e.active.Add(-1)
	start := time.Now()
	var progress [2]streamProgress
	done := make(chan error, 2)
	copyStream := func(i int, dst net.Conn, reader io.Reader, counter *atomic.Int64) {
		// r may already hold bytes the client sent right after the request.
		_, err := io.Copy(countingWriter{dst, counter, start, &progress[i], &progress[1-i]}, reader)
		if err == nil {
			progress[i].watching.Store(true)
			if half, ok := dst.(interface{ CloseWrite() error }); ok {
				err = half.CloseWrite()
			}
		}
		done <- err
	}
	go copyStream(0, upstream, r, &e.upBytes)
	go copyStream(1, c, upstream, &e.downBytes)
	var drain <-chan time.Time
	var timer *time.Timer
	for remaining := 2; remaining > 0; {
		select {
		case err := <-done:
			remaining--
			if err == nil {
				if remaining == 1 {
					timer = time.NewTimer(streamIdleTimeout)
					defer timer.Stop()
					drain = timer.C
				}
				continue
			}
		case <-drain:
			elapsed := time.Since(start)
			left := streamIdleTimeout + time.Duration(max(progress[0].last.Load(), progress[1].last.Load())) - elapsed
			if left > 0 {
				timer.Reset(left)
				continue
			}
		}
		c.Close()
		upstream.Close()
		for range remaining {
			<-done
		}
		return
	}
}

// Lookup resolves host through the tunnel's DNS servers (diagnostics only).
func (e *Engine) Lookup(host string, timeout time.Duration) (int, time.Duration, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	start := time.Now()
	addrs, err := e.stack.LookupContextHost(ctx, host)
	return len(addrs), time.Since(start), err
}

// Resolve is for Spotify's BSD getaddrinfo import. It uses only the tunnel DNS
// resolver; callers pass the resulting numeric addresses to libc without DNS.
func (e *Engine) Resolve(host string, timeout time.Duration) ([]string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	return e.stack.LookupContextHost(ctx, host)
}

// Status reports counters and handshake state. It never includes keys,
// endpoint addresses, hostnames or URLs: IpcGet output is parsed for a fixed
// set of numeric fields only, because it also contains private_key.
func (e *Engine) Status() map[string]any {
	out := map[string]any{"running": !e.stopped.Load()}
	data, err := e.dev.IpcGet()
	if err == nil {
		var last, rx, tx int64
		for _, line := range strings.Split(data, "\n") {
			key, value, _ := strings.Cut(line, "=")
			n, _ := strconv.ParseInt(value, 10, 64)
			switch key {
			case "last_handshake_time_sec":
				last = n
			case "rx_bytes":
				rx = n
			case "tx_bytes":
				tx = n
			}
		}
		out["handshakeAgeSec"] = int64(-1)
		if last > 0 {
			out["handshakeAgeSec"] = int64(time.Since(time.Unix(last, 0)).Seconds())
		}
		out["wgRxBytes"], out["wgTxBytes"] = rx, tx
	}
	out["uptimeSec"] = int64(time.Since(e.started).Seconds())
	out["connections"] = map[string]int64{
		"total": e.total.Load(), "active": e.active.Load(), "failed": e.failed.Load(),
		"dnsFailed": e.dnsFailed.Load(), "domainTargets": e.domainTargets.Load(), "ipTargets": e.ipTargets.Load(),
		"socks": e.viaSOCKS.Load(), "httpConnect": e.viaCONNECT.Load(),
		"authRejected": e.authRejected.Load(), "badRequests": e.badRequests.Load(),
	}
	out["categories"] = map[string]int64{"media": e.media.Load(), "api": e.api.Load(), "other": e.other.Load()}
	out["proxyBytes"] = map[string]int64{"up": e.upBytes.Load(), "down": e.downBytes.Load()}
	out["bind"] = map[string]int64{"updates": e.bindUpdates.Load(), "failures": e.bindFailures.Load(), "relistens": e.relistens.Load()}
	out["endpointResolvedLocally"] = e.endpointResolvedLocally
	return out
}

func (e *Engine) String() string { return fmt.Sprintf("engine(port=%d)", e.port) }

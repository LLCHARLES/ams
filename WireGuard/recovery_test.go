package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"testing/synctest"
	"time"
)

type fixtureStack struct {
	lookup func(context.Context) ([]string, error)
	dial   func(context.Context, string) (net.Conn, error)
}

type heldBind struct {
	rebindDevice
	once             sync.Once
	entered, release chan struct{}
	active, peak     atomic.Int32
}

func (d *heldBind) BindUpdate() error {
	active := d.active.Add(1)
	defer d.active.Add(-1)
	if active > d.peak.Load() {
		d.peak.Store(active)
	}
	d.once.Do(func() { close(d.entered); <-d.release })
	return d.rebindDevice.BindUpdate()
}

func TestConcurrentResumeReconcilesOnce(t *testing.T) {
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal("listener setup")
	}
	device := &heldBind{entered: make(chan struct{}), release: make(chan struct{})}
	e := &Engine{dev: device, listener: listener, port: listener.Addr().(*net.TCPAddr).Port}
	defer e.Close()
	e.Rebind()
	<-device.entered
	e.Rebind()
	e.mu.Lock()
	done := e.repairDone
	e.mu.Unlock()
	close(device.release)
	<-done
	if e.bindUpdates.Load() != 1 {
		t.Fatal("duplicate UDP update for in-flight reconciliation")
	}
}

func TestRebindRequestsDoNotWaitForRepair(t *testing.T) {
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal("listener setup")
	}
	device := &heldBind{entered: make(chan struct{}), release: make(chan struct{})}
	e := &Engine{dev: device, listener: listener, port: listener.Addr().(*net.TCPAddr).Port}
	release := sync.OnceFunc(func() { close(device.release) })
	defer func() { release(); e.Close() }()
	requested := make(chan struct{})
	go func() {
		e.Rebind()
		<-device.entered
		e.listenerFailed(listener) // accept loop discovers listener loss during BindUpdate
		e.Rebind()
		close(requested)
	}()
	select {
	case <-requested:
	case <-time.After(time.Second):
		t.Fatal("control request blocked behind repair")
	}
	// Stop while one repair is held and another request is pending.
	stopped := make(chan struct{})
	go func() { e.Close(); close(stopped) }()
	// The original listener closes before the worker is joined.
	c, err := listener.Accept()
	if err == nil {
		c.Close()
		t.Fatal("listener still accepting")
	}
	release()
	<-stopped
	if device.peak.Load() != 1 || e.relistens.Load() != 0 {
		t.Fatal("duplicate or resurrected listener repair")
	}
}

func TestListenerPressureRecoversWithoutPathChange(t *testing.T) {
	for _, fault := range []error{syscall.ENOMEM, syscall.ENOBUFS, syscall.ECONNABORTED, syscall.EINTR} {
		t.Run(fault.Error(), func(t *testing.T) {
			synctest.Test(t, func(t *testing.T) {
				l, err := net.Listen("tcp4", "127.0.0.1:0")
				if err != nil {
					t.Fatal("listener setup")
				}
				anchor, err := l.(*net.TCPListener).File()
				if err != nil {
					t.Fatal("listener reservation")
				}
				var pressure atomic.Bool
				pressure.Store(true)
				var attempts atomic.Int32
				available := make(chan struct{}, 1)
				e := &Engine{dev: &rebindDevice{}, listener: l, anchor: anchor,
					rearm: func() (net.Listener, error) {
						attempts.Add(1)
						if pressure.Load() {
							return nil, &net.OpError{Op: "accept", Err: fault}
						}
						return (&reservedSocket{file: anchor}).listen()
					}, stateChanged: func(s int) {
						if s == engineAvailable {
							available <- struct{}{}
						}
					},
				}
				defer e.Close()
				e.listenerFailed(l)
				time.Sleep(time.Minute)
				e.mu.Lock()
				repairing := e.repairDone != nil
				e.mu.Unlock()
				if !repairing || attempts.Load() < 2 || len(available) != 0 {
					t.Fatal("listener abandoned retryable pressure")
				}
				pressure.Store(false)
				select {
				case <-available:
				case <-time.After(time.Minute + time.Second):
					t.Fatal("listener did not recover without a path update")
				}
			})
		})
	}
}

type fixtureListener chan net.Conn

func (l fixtureListener) Accept() (net.Conn, error) {
	if c := <-l; c != nil {
		return c, nil
	}
	return nil, syscall.EMFILE
}
func (l fixtureListener) Close() error   { close(l); return nil }
func (l fixtureListener) Addr() net.Addr { return nil }

func TestListenerBackoffAndDemand(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		l := make(fixtureListener)
		var recoverNext atomic.Bool
		attempts := make(chan time.Time, 1)
		e := &Engine{dev: &rebindDevice{}, listener: l, clients: map[net.Conn]struct{}{},
			user: []byte("user"), pass: []byte("pass"), pendingAuth: make(chan struct{}, 1),
			rearm: func() (net.Listener, error) {
				attempts <- time.Now()
				if recoverNext.Swap(false) {
					return l, nil
				}
				return nil, syscall.EMFILE
			}}
		defer e.Close()
		previous := time.Now()
		wantGap := func(want time.Duration) {
			t.Helper()
			select {
			case now := <-attempts:
				if gap := now.Sub(previous); gap != want {
					t.Fatalf("listener retry interval %v, want %v", gap, want)
				}
				previous = now
			case <-time.After(time.Minute + time.Second):
				t.Fatal("listener stopped retrying")
			}
		}
		e.listenerFailed(l)
		wantGap(0)
		for delay := 100 * time.Millisecond; delay < time.Minute; delay *= 2 {
			wantGap(delay)
		}
		wantGap(time.Minute)
		synctest.Wait()
		time.Sleep(time.Second) // interrupt the long wait rather than its expiry
		e.Rebind()
		wantGap(time.Second)
		wantGap(100 * time.Millisecond)

		recoverNext.Store(true)
		wantGap(200 * time.Millisecond)
		server, client := net.Pipe()
		defer client.Close()
		l <- server
		l <- nil // a second outage while an accepted client is authenticating
		wantGap(0)
		wantGap(100 * time.Millisecond)
		wantGap(200 * time.Millisecond)
		time.Sleep(time.Millisecond)
		if reply := socksHandshake(t, client, []byte{2}, "user", "pass"); reply[1] != 0 {
			t.Fatal("fixture authentication failed")
		}
		wantGap(time.Millisecond)
		wantGap(100 * time.Millisecond)
		if e.bindUpdates.Load() != 1 {
			t.Fatal("listener demand requested an extra UDP update")
		}
	})
}

func TestPathChangeAfterBindDuringListenerRetry(t *testing.T) {
	l, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal("listener setup")
	}
	anchor, err := l.(*net.TCPListener).File()
	if err != nil {
		t.Fatal("listener reservation")
	}
	device := &heldBind{entered: make(chan struct{}), release: make(chan struct{})}
	listenerRetry, resume := make(chan struct{}), make(chan struct{})
	var attempts atomic.Int32
	e := &Engine{dev: device, listener: l, anchor: anchor, rearm: func() (net.Listener, error) {
		if attempts.Add(1) == 1 {
			close(listenerRetry)
			<-resume
			return nil, syscall.EMFILE
		}
		return (&reservedSocket{file: anchor}).listen()
	}}
	defer e.Close()
	e.Rebind()
	<-device.entered
	e.listenerFailed(l)
	close(device.release)
	<-listenerRetry // first UDP update completed; listener is still unavailable
	e.Rebind()
	e.mu.Lock()
	done := e.repairDone
	e.mu.Unlock()
	close(resume)
	<-done
	if e.bindUpdates.Load() != 2 {
		t.Fatal("path change lost during listener retry")
	}
}

type bindFunc struct {
	rebindDevice
	update func() error
}

func (d *bindFunc) BindUpdate() error { return d.update() }

func TestListenerFailureDuringLastBind(t *testing.T) {
	for _, failAt := range []int{4, 5} {
		t.Run(fmt.Sprint(failAt), func(t *testing.T) {
			l, err := net.Listen("tcp4", "127.0.0.1:0")
			if err != nil {
				t.Fatal(err)
			}
			e := &Engine{listener: l}
			attempt := 0
			e.dev = &bindFunc{update: func() error {
				attempt++
				if attempt == failAt {
					e.listenerFailed(l)
				}
				return syscall.ENETDOWN
			}}
			e.rearm = func() (net.Listener, error) { return net.Listen("tcp4", "127.0.0.1:0") }
			defer e.Close()
			e.Rebind()
			e.mu.Lock()
			done := e.repairDone
			e.mu.Unlock()
			<-done
			if attempt != 5 {
				t.Fatalf("listener failure renewed UDP budget: %d updates", attempt)
			}
			if e.relistens.Load() != 1 || e.unavailable != bindUnavailable {
				t.Fatal("listener lost during final UDP update was not restored independently")
			}
		})
	}
}

func TestReservedListenerFDLimit(t *testing.T) {
	// Limit only a subprocess; restore its descriptors before probing LISTEN.
	if os.Getenv("SGWG_TEST_EMFILE") == "" {
		cmd := exec.Command(os.Args[0], "-test.run=^TestReservedListenerFDLimit$", "-test.timeout=15s")
		cmd.Env = append(os.Environ(), "SGWG_TEST_EMFILE=1")
		if output, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("%v: %s", err, output)
		}
		return
	}
	fd, err := syscall.Socket(syscall.AF_INET, syscall.SOCK_STREAM, 0)
	if err != nil {
		t.Fatal(err)
	}
	file := os.NewFile(uintptr(fd), "reservation")
	defer file.Close()
	if err := syscall.Bind(fd, &syscall.SockaddrInet4{Addr: [4]byte{127, 0, 0, 1}}); err != nil {
		t.Fatal(err)
	}
	var limit syscall.Rlimit
	if err := syscall.Getrlimit(syscall.RLIMIT_NOFILE, &limit); err != nil {
		t.Fatal(err)
	}
	old := limit
	limit.Cur = uint64(fd + 1)
	if err := syscall.Setrlimit(syscall.RLIMIT_NOFILE, &limit); err != nil {
		t.Fatal(err)
	}
	for {
		spare, err := syscall.Dup(fd)
		if err == syscall.EMFILE {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		defer syscall.Close(spare)
	}
	if l, err := (&reservedSocket{file: file}).listen(); !errors.Is(err, syscall.EMFILE) {
		t.Fatalf("expected descriptor pressure, got %v, %v", l, err)
	}
	if err := syscall.Setrlimit(syscall.RLIMIT_NOFILE, &old); err != nil {
		t.Fatal(err)
	}
	if err := syscall.SetNonblock(fd, true); err != nil {
		t.Fatal(err)
	}
	if _, _, err := syscall.Accept(fd); err != syscall.EINVAL {
		t.Fatalf("reservation is not a bound, non-listening socket: %v", err)
	}

	t.Run("after startup", func(t *testing.T) {
		s := &reservedSocket{file: file}
		l, err := s.listen()
		if err != nil {
			t.Fatal(err)
		}
		available := make(chan struct{})
		exhausted := make(chan struct{})
		attempt := 0
		e := &Engine{listener: l, rearm: func() (net.Listener, error) {
			listener, err := s.listen()
			if errors.Is(err, syscall.EMFILE) {
				attempt++
				if attempt == 5 {
					close(exhausted)
				}
			}
			return listener, err
		}, dev: &rebindDevice{}, admitted: func() bool { return false },
			stateChanged: func(state int) {
				if state == engineAvailable {
					close(available)
				}
			}}
		defer e.Close()
		// Darwin can dequeue the handshake even when accept returns EMFILE.
		for range 6 {
			queued, err := net.Dial("tcp4", l.Addr().String())
			if err != nil {
				t.Fatal(err)
			}
			defer queued.Close()
		}
		if err := syscall.Setrlimit(syscall.RLIMIT_NOFILE, &limit); err != nil {
			t.Fatal(err)
		}
		e.listenerFailed(l)
		select {
		case <-exhausted:
		case <-time.After(4 * time.Second):
			t.Fatal("did not sustain real descriptor pressure through five repairs")
		}
		if err := syscall.Setrlimit(syscall.RLIMIT_NOFILE, &old); err != nil {
			t.Fatal(err)
		}
		select {
		case <-available:
		case <-time.After(3 * time.Second):
			t.Fatal("published listener still parked after EMFILE cleared")
		}
		fresh, err := net.Dial("tcp4", l.Addr().String())
		if err != nil {
			t.Fatal(err)
		}
		defer fresh.Close()
		fresh.SetReadDeadline(time.Now().Add(time.Second))
		if _, err := fresh.Read(make([]byte, 1)); err != io.EOF {
			t.Fatalf("recovered accept loop did not serve fresh connection: %v", err)
		}
	})
}

func TestCloseDuringRefilledBacklog(t *testing.T) {
	l, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	file, err := l.(*net.TCPListener).File()
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	fd := int(file.Fd())
	if err := syscall.SetNonblock(fd, true); err != nil {
		t.Fatal(err)
	}
	refill := func() error {
		c, err := net.Dial("tcp4", l.Addr().String())
		if err == nil {
			c.Close()
		}
		return err
	}
	if err := refill(); err != nil {
		t.Fatal(err)
	}
	entered, closing := make(chan struct{}), make(chan struct{})
	var first sync.Once
	calls := 0
	e := &Engine{dev: &rebindDevice{}, listener: l, stateChanged: func(s int) {
		if s == engineStopped {
			close(closing)
		}
	}}
	e.rearm = func() (net.Listener, error) {
		return l, drainBacklog(fd, func(fd int) (int, syscall.Sockaddr, error) {
			first.Do(func() { close(entered); <-closing })
			calls++
			// Finite safety cutoff for an implementation that never yields.
			if calls == 128 {
				return -1, nil, net.ErrClosed
			}
			if err := refill(); err != nil {
				return -1, nil, err
			}
			return syscall.Accept(fd)
		})
	}
	e.listenerFailed(l)
	<-entered
	e.Close()
	if calls == 128 {
		t.Fatal("Close depended on the backlog producer stopping")
	}
}

func TestReservedListenerDrainsQueue(t *testing.T) {
	l, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	file, err := l.(*net.TCPListener).File()
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	reservation := reservedSocket{file: file}
	active, err := reservation.listen()
	if err != nil {
		t.Fatal(err)
	}
	defer active.Close()
	var clients []net.Conn
	for range 3 {
		c, err := net.Dial("tcp4", l.Addr().String())
		if err != nil {
			t.Fatal(err)
		}
		defer c.Close()
		clients = append(clients, c)
	}
	_, err = reservation.listen()
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range clients {
		c.SetReadDeadline(time.Now().Add(time.Second))
		if _, err := c.Read(make([]byte, 1)); err != io.EOF {
			t.Fatalf("pre-admission connection not drained: %v", err)
		}
	}
}

func (s fixtureStack) LookupContextHost(ctx context.Context, _ string) ([]string, error) {
	return s.lookup(ctx)
}
func (s fixtureStack) DialContext(ctx context.Context, _, dst string) (net.Conn, error) {
	return s.dial(ctx, dst)
}

func TestDialSharesBudgetAfterDNS(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		const budget = 15 * time.Second
		start := time.Now()
		e := Engine{dialTimeout: budget, stack: fixtureStack{
			lookup: func(context.Context) ([]string, error) {
				time.Sleep(5 * time.Second)
				return []string{"2606:4700:4700::1111", "1.1.1.1"}, nil
			},
			dial: func(ctx context.Context, dst string) (net.Conn, error) {
				deadline, _ := ctx.Deadline()
				if dst == "[2606:4700:4700::1111]:443" {
					<-ctx.Done()
					return nil, ctx.Err()
				}
				if dst != "1.1.1.1:443" || time.Until(deadline) != 5*time.Second || deadline.Sub(start) != budget {
					return nil, errors.New("working candidate lost its share of parent deadline")
				}
				a, b := net.Pipe()
				b.Close()
				return a, nil
			},
		}}
		c, err := e.dial("fixture.invalid", 443)
		if err != nil {
			t.Fatal("second candidate did not connect within shared budget")
		}
		c.Close()
	})
}

func TestMixedAnswerHasNoEgress(t *testing.T) {
	e := Engine{dialTimeout: time.Second, stack: fixtureStack{
		lookup: func(context.Context) ([]string, error) { return []string{"1.1.1.1", "::1"}, nil },
		dial:   func(context.Context, string) (net.Conn, error) { t.Fatal("mixed answer dialed"); return nil, nil },
	}}
	if _, err := e.dial("fixture.invalid", 443); err == nil {
		t.Fatal("accepted mixed answer")
	}
}

// Independent streams on each side, with TCP-like EOF in just one direction.
type halfConn struct {
	net.Conn
	reader net.Conn
}

func (c halfConn) Read(p []byte) (int, error) { return c.reader.Read(p) }
func (c halfConn) CloseWrite() error          { return c.Conn.Close() }
func (c halfConn) Close() error               { c.reader.Close(); return c.Conn.Close() }

func halfPair() (halfConn, halfConn) {
	a, b := net.Pipe()
	c, d := net.Pipe()
	return halfConn{a, c}, halfConn{d, b}
}

func TestPipeDrainsEitherDirection(t *testing.T) {
	for _, reverse := range []bool{false, true} {
		for _, mode := range []string{"silent", "blocked writer", "payload before FIN", "progress", "progress with upload open", "progress with blocked writer"} {
			t.Run(mode, func(t *testing.T) {
				synctest.Test(t, func(t *testing.T) {
					client, local := halfPair()
					remote, peer := halfPair()
					defer client.Close()
					defer peer.Close()
					e := Engine{clients: map[net.Conn]struct{}{}}
					done := make(chan struct{})
					go func() { e.pipe(local, bufio.NewReader(local), remote); local.Close(); close(done) }()
					if reverse {
						client, peer = peer, client
					}
					if mode == "progress with upload open" {
						time.Sleep(60 * time.Second)
						go client.Write([]byte{42})
						var b [1]byte
						if _, err := io.ReadFull(peer, b[:]); err != nil || b[0] != 42 {
							t.Fatal("open idle stream no longer forwards data")
						}
					}
					if mode == "payload before FIN" || mode == "progress with blocked writer" {
						if _, err := client.Write([]byte{1}); err != nil {
							t.Fatal("payload not consumed")
						}
					}
					if mode != "progress with upload open" {
						client.CloseWrite()
					}
					var b [1]byte
					if mode != "payload before FIN" && mode != "progress with blocked writer" && mode != "progress with upload open" {
						if _, err := peer.Read(b[:]); err != io.EOF {
							t.Fatal("FIN not forwarded")
						}
					}
					switch mode {
					case "progress", "progress with upload open", "progress with blocked writer":
						for i := 0; i < 4; i++ {
							time.Sleep(12 * time.Second)
							go peer.Write([]byte{byte(i)})
							if _, err := io.ReadFull(client, b[:]); err != nil || b[0] != byte(i) {
								t.Fatal("progressing stream truncated")
							}
						}
						if mode == "progress with blocked writer" {
							// FIN is still behind the blocked payload. Once
							// progress stops, allow precisely the remaining idle budget.
							synctest.Wait()
							time.Sleep(30*time.Second - time.Nanosecond)
							synctest.Wait()
							select {
							case <-done:
								t.Fatal("blocked writer ignored last reverse-direction progress")
							default:
							}
							time.Sleep(time.Nanosecond)
							synctest.Wait()
							select {
							case <-done:
								return
							default:
								t.Fatal("blocked writer exceeded idle deadline")
							}
						}
						peer.CloseWrite()
						if mode == "progress with upload open" {
							client.CloseWrite()
						}
					case "blocked writer":
						peer.Write([]byte{1}) // copied from peer, client never reads it
					}
					select {
					case <-done:
					case <-time.After(31 * time.Second):
						t.Fatal("stalled copies not joined")
					}
				})
			})
		}
	}
}

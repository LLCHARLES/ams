package main

/*
#include <stdlib.h>
#include <stdint.h>
#include "../tweak/Sources/Shared/WireGuard/SGWGBridge.h"
static inline void reportEngineState(uintptr_t callback, int state) {
	if (callback) ((void (*)(int))callback)(state);
}
static inline int isAdmitted(uintptr_t callback) {
	return callback && ((int (*)(void))callback)();
}
*/
import "C"

import (
	"encoding/json"
	"errors"
	"net"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"
)

// C ABI used by Source/WireGuard/SGWGCore.m. Every returned string is
// allocated with malloc and must be released with SGWGFree. Returned JSON
// never contains key material, endpoint addresses, hostnames or URLs (except
// SGWGInspect, which returns the non-secret profile summary for the UI).

var (
	bridgeMu          sync.Mutex
	current           *Engine
	lastError         string
	stateCallback     atomic.Uintptr
	admissionCallback atomic.Uintptr
)

const (
	engineStopped           = int(C.SGWGEngineStopped)
	engineAvailable         = int(C.SGWGEngineAvailable)
	engineUnavailable       = int(C.SGWGEngineUnavailable)
	engineDestinationFailed = int(C.SGWGEngineDestinationFailed)
)

//export SGWGSetStateCallback
func SGWGSetStateCallback(callback, admitted C.uintptr_t) {
	stateCallback.Store(uintptr(callback))
	admissionCallback.Store(uintptr(admitted))
}

func cString(v any) *C.char {
	b, err := json.Marshal(v)
	if err != nil {
		return C.CString(`{"ok":false,"error":"internal error"}`)
	}
	return C.CString(string(b))
}

//export SGWGInspect
func SGWGInspect(text *C.char) *C.char {
	p, err := ParseProfile(C.GoString(text))
	if err != nil {
		return cString(map[string]any{"ok": false, "error": err.Error()})
	}
	defer p.clearKeys()
	summary := p.Summary()
	summary["ok"] = true
	return cString(summary)
}

type reservedSocket struct {
	file     *os.File
	listener net.Listener
}

// Called once after bootstrap, then only by the single repair worker.
func (s *reservedSocket) listen() (net.Listener, error) {
	fd := int(s.file.Fd())
	if s.listener == nil {
		// The ObjC reservation shares this socket: closing a dup cannot
		// undo listen. Allocate the Go descriptor before enabling the port.
		l, err := net.FileListener(s.file)
		if err != nil {
			return nil, err
		}
		if err := syscall.Listen(fd, maxUnauthenticatedClients); err != nil {
			l.Close()
			return nil, err
		}
		s.listener = l
		return l, nil
	}
	// Reuse the Go listener and reject connections queued while its accept
	// loop was unavailable, without waiting for any new connection.
	if err := syscall.SetNonblock(fd, true); err != nil {
		return nil, err
	}
	if err := drainBacklog(fd, syscall.Accept); err != nil {
		return nil, err
	}
	return s.listener, nil
}

var errBacklogBusy = errors.New("local listener backlog still draining")

func drainBacklog(fd int, accept func(int) (int, syscall.Sockaddr, error)) error {
	// A producer can continuously refill the kernel queue. Yield to repair's
	// cancellation/backoff after one backlog, without declaring it empty.
	for range maxUnauthenticatedClients {
		client, _, err := accept(fd)
		switch err {
		case nil:
			syscall.Close(client)
		case syscall.EINTR, syscall.ECONNABORTED:
			continue
		case syscall.EAGAIN:
			return nil
		default:
			return err
		}
	}
	return errBacklogBusy
}

//export SGWGStart
func SGWGStart(text, user, pass *C.char, listenerFD C.int) C.enum_SGWGStartResult {
	file := os.NewFile(uintptr(listenerFD), "local-proxy")
	p, err := ParseProfile(C.GoString(text))
	var e *Engine
	if err == nil {
		reservation := &reservedSocket{file: file}
		e, err = StartEngine(p, C.GoString(user), C.GoString(pass), EngineOptions{
			Listen:       reservation.listen,
			Admitted:     func() bool { return C.isAdmitted(C.uintptr_t(admissionCallback.Load())) != 0 },
			StateChanged: func(state int) { C.reportEngineState(C.uintptr_t(stateCallback.Load()), C.int(state)) },
		})
	}
	bridgeMu.Lock()
	defer bridgeMu.Unlock()
	if err != nil {
		file.Close()
		lastError = err.Error()
		switch err {
		case errEndpointDNS, errNoSuitableEP, errWGUp, errListenerTemporary:
			return C.SGWGStartNetworkUnavailable
		default:
			return C.SGWGStartRefused
		}
	}
	e.anchor = file
	current, lastError = e, ""
	return C.SGWGStarted
}

//export SGWGStop
func SGWGStop() {
	bridgeMu.Lock()
	e := current
	current = nil
	bridgeMu.Unlock()
	if e != nil {
		e.Close()
	}
}

//export SGWGStatus
func SGWGStatus() *C.char {
	bridgeMu.Lock()
	e, msg := current, lastError
	bridgeMu.Unlock()
	if e == nil {
		return cString(map[string]any{"running": false, "error": msg})
	}
	return cString(e.Status())
}

//export SGWGRebind
func SGWGRebind() C.int {
	bridgeMu.Lock()
	e := current
	bridgeMu.Unlock()
	if e == nil {
		return -1
	}
	if e.Rebind() != nil {
		return 1
	}
	return 0
}

//export SGWGLookup
func SGWGLookup(host *C.char) *C.char {
	bridgeMu.Lock()
	e := current
	bridgeMu.Unlock()
	if e == nil {
		return cString(map[string]any{"ok": false, "error": "engine not running"})
	}
	name := strings.TrimSpace(C.GoString(host))
	if !isHostname(name) {
		return cString(map[string]any{"ok": false, "error": "invalid hostname"})
	}
	count, elapsed, err := e.Lookup(name, 8*time.Second)
	out := map[string]any{"ok": err == nil && count > 0, "count": count, "ms": elapsed.Milliseconds()}
	if err != nil {
		// net.DNSError text contains the name and server; report only its kind.
		kind := "failed"
		if ne, ok := err.(net.Error); ok && ne.Timeout() {
			kind = "timeout"
		} else if de, ok := err.(*net.DNSError); ok && de.IsNotFound {
			kind = "not found"
		}
		out["error"] = kind
	}
	return cString(out)
}

//export SGWGResolve
func SGWGResolve(host *C.char) *C.char {
	bridgeMu.Lock()
	e := current
	bridgeMu.Unlock()
	if e == nil {
		return cString(map[string]any{"ok": false})
	}
	name := strings.TrimSpace(C.GoString(host))
	if !isHostname(name) {
		return cString(map[string]any{"ok": false})
	}
	addresses, err := e.Resolve(name, 8*time.Second)
	if err != nil || len(addresses) == 0 {
		return cString(map[string]any{"ok": false})
	}
	if len(addresses) > 16 {
		addresses = addresses[:16]
	}
	return cString(map[string]any{"ok": true, "addresses": addresses})
}

//export SGWGRedact
func SGWGRedact(text *C.char) *C.char {
	return C.CString(Redact(C.GoString(text)))
}

//export SGWGFree
func SGWGFree(p *C.char) { C.free(unsafe.Pointer(p)) }

// main is required by -buildmode=c-archive and is never called.
func main() {}

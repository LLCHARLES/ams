// ActivityKit is Swift only, so LiveActivity.x reaches it through this class.
import ActivityKit
import Foundation
import os
import UIKit

@available(iOS 17.0, *)
@objc(SGLiveActivityBridge)
public final class SGLiveActivityBridge: NSObject {
    private static let log = Logger(subsystem: "spotifyglass", category: "live activity")
    // Under ActivityKit's 4096, with room for its own wrapping.
    private static let maxStateBytes = 3800
    // Each state is stale this long after it is sent: three times LiveActivity.x's kRefresh, which sends
    // even an unchanged card again, so only a card Spotify can no longer feed goes stale.
    private static let staleAfter: TimeInterval = 60

    private typealias State = SGLyricsAttributes.ContentState

    // Either type's activities: one left from before an update to iOS 18 carries on under its own.
    private static func live<A>(_ activities: [Activity<A>]) -> [String] {
        activities.filter { $0.activityState == .active || $0.activityState == .stale }.map(\.id)
    }

    // Ended by end() but maybe not yet by ActivityKit, which goes one change at a time: not showing from the call on,
    // so a fresh one can be asked for at once.
    private static let ending = OSAllocatedUnfairLock(initialState: Set<String>())

    private static var showing: [String] {
        let gone = ending.withLock { $0 }
        return (live(Activity<SGLyricsAttributes>.activities) + live(Activity<SGLyricsWatchAttributes>.activities))
            .filter { !gone.contains($0) }
    }

    @objc public static var isShowing: Bool { !showing.isEmpty }

    // When the one showing was asked for, kept across launches so one kept from a launch in the background is aged
    // too. Nil when unknown.
    private static let startedKey = "spotifyglass.liveActivity.startedAt"
    @objc public static var startedAt: Date? {
        guard let id = showing.first, let stored = UserDefaults.standard.dictionary(forKey: startedKey),
              stored["id"] as? String == id else { return nil }
        return stored["at"] as? Date
    }

    @objc public static var canStart: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    // show() and end() are called on main (LiveActivity.x), so the sender never waits for it.
    private static var inBackground: Bool {
        MainActor.assumeIsolated { UIApplication.shared.applicationState == .background }
    }

    // Updates and ends go out one at a time in the order asked for, since ActivityKit applies
    // concurrent ones in whatever order they finish. An update still waiting gives way to a newer one.
    private enum Change: Sendable {
        case update(String, ActivityContent<State>, background: Bool)
        case end([String], background: Bool)
    }

    private struct Pending: Sendable {
        var changes: [Change] = []
        var sender: Task<Void, Never>?
        var generation = 0
        var retiring: Int?
        var inFlightEnd: Change?
        // When the change being sent went out. One ActivityKit never answers would otherwise hold every
        // later change behind it and freeze the card; past kStuckAfter a new sender takes over.
        var sentAt: ContinuousClock.Instant?
        var stallWake: Task<Void, Never>?
        // Changes taken to send so far, so a second try can tell another sender has gone since.
        var taken = 0
        var resend: Task<Bool, Never>?
    }

    private static let kStuckAfter: Duration = .seconds(5)

    private static let pending = OSAllocatedUnfairLock(initialState: Pending())

    private static func startSender(_ state: inout Pending) {
        state.generation += 1
        let generation = state.generation
        state.sentAt = .now
        state.sender = Task { await send(generation) }
    }

    // Only work waiting behind a sender needs a deadline. In particular, disabling
    // the card queues an end and stops its producer: there won't be another tick.
    private static func watchStall(_ state: inout Pending) {
        guard state.stallWake == nil, state.retiring == nil, !state.changes.isEmpty,
              let sentAt = state.sentAt else { return }
        state.stallWake = Task {
            do { try await Task.sleep(until: sentAt + kStuckAfter, clock: .continuous) }
            catch { return }
            let previous = pending.withLock { state -> Task<Void, Never>? in
                // Taking another change cancels this wake under the same lock.
                guard !Task.isCancelled else { return nil }
                state.stallWake = nil
                let previous = state.sender
                state.retiring = state.generation
                // An obsolete update is replaceable, but a dismissal must reach the system.
                if let end = state.inFlightEnd { state.changes.insert(end, at: 0) }
                state.inFlightEnd = nil
                log.notice("[spotifyglass] live activity: stalled send, sending on past it")
                startSender(&state)
                return previous
            }
            previous?.cancel()
        }
    }

    private static func queue(_ change: Change) {
        pending.withLock { pending in
            pending.resend?.cancel()
            pending.resend = nil
            if case .update(let id, _, _) = change, case .update(let waiting, _, _)? = pending.changes.last, waiting == id {
                pending.changes.removeLast()
            }
            pending.changes.append(change)
            if pending.sender == nil { startSender(&pending) }
            else { watchStall(&pending) }
        }
    }

    // In the background, iOS lets a process update its activity only while it does more than play audio
    // (liveactivitiesd: "Process is only playing background media so is forbidden to update activity"),
    // and ActivityKit drops a refused update without a word. A background task is that something more. Begun and
    // ended off the main thread (UIKit allows both there), so a busy main thread cannot hold a send up; ended once.
    private final class BackgroundTask: @unchecked Sendable {
        private let id = OSAllocatedUnfairLock(initialState: UIBackgroundTaskIdentifier.invalid)

        init() {
            let begun = UIApplication.shared.beginBackgroundTask(withName: "live activity") { [weak self] in self?.end() }
            id.withLock { $0 = begun }
        }

        var valid: Bool { id.withLock { $0 != .invalid } }

        func end() {
            let ending = id.withLock { id -> UIBackgroundTaskIdentifier in
                defer { id = .invalid }
                return id
            }
            if ending != .invalid { UIApplication.shared.endBackgroundTask(ending) }
        }
    }

    private static func update(_ id: String, _ content: ActivityContent<State>) async {
        await Activity<SGLyricsAttributes>.activities.first { $0.id == id }?.update(content)
        await Activity<SGLyricsWatchAttributes>.activities.first { $0.id == id }?.update(content)
    }

    private static func end(_ ids: [String]) async {
        for activity in Activity<SGLyricsAttributes>.activities where ids.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        for activity in Activity<SGLyricsWatchAttributes>.activities where ids.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    // iOS grants the background task asynchronously, so a change sent just after it begins can still be refused
    // without a word (4 of 53 updates on the phone, each fine a second later). True once a second has gone by with
    // nothing newer queued and no other sender at work. A new change cancels the one sleep immediately.
    private static func quietForASecond(since taken: Int) async -> Bool {
        let resend = pending.withLock { pending -> Task<Bool, Never>? in
            guard pending.changes.isEmpty, pending.taken == taken else { return nil }
            let task = Task {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { return false }
                return !Task.isCancelled
            }
            pending.resend = task
            return task
        }
        guard let resend, await resend.value else { return false }
        return pending.withLock { pending in
            guard pending.changes.isEmpty, pending.taken == taken else { return false }
            pending.resend = nil
            pending.sentAt = .now
            return true
        }
    }

    // The last state sent, to tell which updates are worth the second copy.
    private static let lastSent = OSAllocatedUnfairLock<State?>(initialState: nil)

    // A dropped line is replaced by the next line or kRefresh's resend within seconds, and an unchanged state
    // was already sent, so only a change to the track, controls or timer gets the second copy.
    private static func onlyLinesChanged(_ state: State) -> Bool {
        lastSent.withLock { last in
            defer { last = state }
            guard var before = last else { return false }
            before.line = state.line
            before.nextLine = state.nextLine
            before.translation = state.translation
            return before == state
        }
    }

    // Both senders share an assertion if ActivityKit hasn't returned from the
    // cancelled call. The current generation releases it when it drains the queue.
    private actor BackgroundTime {
        private var generation = 0
        private var task: BackgroundTask?
        func begin(_ generation: Int) {
            guard generation >= self.generation else { return }
            self.generation = generation
            if task?.valid != true { task = BackgroundTask() }
        }
        func finish(_ generation: Int) {
            guard generation == self.generation else { return }
            task?.end()
            task = nil
        }
    }
    private static let backgroundTime = BackgroundTime()

    private static func send(_ generation: Int) async {
        await backgroundTime.begin(generation)
        while let (change, taken) = pending.withLock({ pending -> (Change, Int)? in
            guard generation == pending.generation else {
                if pending.retiring == generation {
                    pending.retiring = nil
                    watchStall(&pending)
                }
                return nil
            }
            pending.stallWake?.cancel()
            pending.stallWake = nil
            pending.inFlightEnd = nil
            if pending.changes.isEmpty {
                pending.sender = nil
                pending.sentAt = nil
                return nil
            }
            pending.sentAt = .now
            pending.taken += 1
            let change = pending.changes.removeFirst()
            if case .end = change { pending.inFlightEnd = change }
            watchStall(&pending)
            return (change, pending.taken)
        }) {
            switch change {
            case .update(let id, let content, let background):
                let again = !onlyLinesChanged(content.state) && background
                await update(id, content)
                if again, !Task.isCancelled, await quietForASecond(since: taken), !Task.isCancelled { await update(id, content) }
            case .end(let ids, let background):
                await end(ids)
                // Rare, and ending one already ended does nothing: a second later it goes again whatever came since.
                if background && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if !Task.isCancelled { await end(ids) }
                }
                pending.withLock { state in
                    if generation == state.generation {
                        ending.withLock { $0.subtract(ids) }
                        state.inFlightEnd = nil
                    }
                }
            }
        }
        await backgroundTime.finish(generation)
    }

    // A new activity can only be requested while the app is in the foreground; an update works from the background.
    // One call per new state. View and tab are SGLiveActivityView's and SGLiveActivityTab's values;
    // titles, artists and URIs pair up by index, the tracks up next; timerEnd is nil without a timer.
    @objc public static func show(view: Int, paused: Bool, line: String, nextLine: String,
                                  titles: [String], artists: [String], uris: [String],
                                  tab: Int, title: String, artist: String, shuffle: Bool, repeatMode: Int,
                                  timerEnd: Date?, timerEndOfTrack: Bool, timerEndOfAlbum: Bool,
                                  tint: String?, trackStart: Date?, trackEnd: Date?, pausedAt: NSNumber?, translation: String?,
                                  cover: Data?, textSize: Int, alignment: Int, noLyrics: Bool, withoutLyrics: Int,
                                  colors: Int, accent: String?, progressBar: Bool) -> Bool {
        let tracks = titles.indices.map {
            SGLyricsAttributes.Track(title: titles[$0], artist: artists[$0], uri: uris[$0])
        }
        var state = SGLyricsAttributes.ContentState(
            view: SGLyricsAttributes.View(rawValue: view) ?? .lyrics, paused: paused,
            line: line, nextLine: nextLine, tracks: tracks,
            tab: SGLyricsAttributes.Tab(rawValue: tab) ?? .controls, title: title, artist: artist,
            shuffle: shuffle, repeatMode: repeatMode, timerEnd: timerEnd, timerEndOfTrack: timerEndOfTrack,
            tint: tint, trackStart: trackStart, trackEnd: trackEnd, pausedAt: pausedAt?.doubleValue,
            translation: translation, cover: cover, textSize: textSize, timerEndOfAlbum: timerEndOfAlbum,
            alignment: alignment, noLyrics: noLyrics, withoutLyrics: withoutLyrics, colors: colors, accent: accent,
            progressBar: progressBar)
        // Budget the actual encoded state, including UTF-8 and JSON escaping. URIs are identities:
        // never truncate one into a different action; drop queue entries if text alone is insufficient.
        do {
            let encoder = JSONEncoder()
            while try encoder.encode(state).count > maxStateBytes {
                if state.cover != nil { state.cover = nil; continue }
                let texts = [state.line, state.nextLine, state.translation ?? "", state.title, state.artist]
                    + state.tracks.flatMap { [$0.title, $0.artist] }
                guard let index = texts.indices.max(by: { texts[$0].utf8.count < texts[$1].utf8.count }),
                      !texts[index].isEmpty else {
                    if !state.tracks.isEmpty { state.tracks.removeLast(); continue }
                    log.error("[spotifyglass] live activity: state exceeds the payload budget without display text")
                    return false
                }
                // Character boundaries preserve composed glyphs. Even one enormous grapheme shrinks to empty.
                let shortened = String(texts[index].prefix(texts[index].count / 2))
                switch index {
                case 0: state.line = shortened
                case 1: state.nextLine = shortened
                case 2: state.translation = shortened
                case 3: state.title = shortened
                case 4: state.artist = shortened
                default:
                    let track = (index - 5) / 2
                    if (index - 5) % 2 == 0 { state.tracks[track].title = shortened }
                    else { state.tracks[track].artist = shortened }
                }
            }
        } catch {
            log.error("[spotifyglass] live activity: state cannot be encoded: \(String(describing: error), privacy: .public)")
            return false
        }
        let content = ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: staleAfter))
        if let id = showing.first {
            queue(.update(id, content, background: inBackground))
            return true
        }
        guard canStart else {
            log.notice("[spotifyglass] live activity: activities are off for this app")
            return false
        }
        do {
            let id: String
            if #available(iOS 18.0, *) {
                id = try Activity.request(attributes: SGLyricsWatchAttributes(), content: content, pushType: nil).id
            } else {
                id = try Activity.request(attributes: SGLyricsAttributes(), content: content, pushType: nil).id
            }
            UserDefaults.standard.set(["id": id, "at": Date()], forKey: startedKey)
            log.notice("[spotifyglass] live activity: started \(id, privacy: .public)")
            return true
        } catch {
            log.error("[spotifyglass] live activity: request failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    // Named now, so an activity requested after this call is not ended with them.
    @objc public static func end() {
        let candidates = Activity<SGLyricsAttributes>.activities.map(\.id) + Activity<SGLyricsWatchAttributes>.activities.map(\.id)
        let ids = ending.withLock { ending in
            let ids = candidates.filter { !ending.contains($0) }
            ending.formUnion(ids)
            return ids
        }
        guard !ids.isEmpty else { return }
        queue(.end(ids, background: inBackground))
    }

    // At termination: ends them all, past the queue, and holds the calling thread until they are ended,
    // two seconds at most, since the process is gone once the notification returns and an end still in
    // flight goes with it. The cap also keeps an ActivityKit that waits on the main thread from hanging it.
    @objc public static func endBeforeExit() {
        // Not `showing`: one end() has named may not be ended yet.
        if (live(Activity<SGLyricsAttributes>.activities) + live(Activity<SGLyricsWatchAttributes>.activities)).isEmpty { return }
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            for activity in Activity<SGLyricsAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            for activity in Activity<SGLyricsWatchAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            done.signal()
        }
        if done.wait(timeout: .now() + 2) == .timedOut {
            log.notice("[spotifyglass] live activity: not ended in time at exit")
        }
    }
}

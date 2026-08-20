import AppKit

/// Trackpad feedback. macOS only gives us three patterns, so the character comes
/// from how they're sequenced — a double thunk for the panel, a rising pair for a
/// move, a stutter for the nudge.
@MainActor
enum Haptics {
    private(set) static var enabled = UserDefaults.standard.object(forKey: "haptics.enabled") as? Bool ?? true

    static func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "haptics.enabled")
    }

    private static func tap(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard enabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    /// Pattern, then how long to wait before the next one.
    private static func play(_ steps: [(NSHapticFeedbackManager.FeedbackPattern, UInt64)]) {
        guard enabled else { return }
        Task { @MainActor in
            for (pattern, gap) in steps {
                tap(pattern)
                if gap > 0 { try? await Task.sleep(for: .milliseconds(gap)) }
            }
        }
    }

    // MARK: - The panel

    /// Opening: a firm double thunk as the board drops.
    static func expand() {
        play([(.alignment, 45), (.levelChange, 0)])
    }

    /// Closing: one soft tick.
    static func collapse() {
        tap(.generic)
    }

    // MARK: - Board

    static func tick()      { tap(.levelChange) }
    static func add()       { play([(.alignment, 55), (.alignment, 0)]) }
    static func move()      { play([(.levelChange, 40), (.alignment, 0)]) }
    static func star()      { play([(.alignment, 32), (.levelChange, 32), (.alignment, 0)]) }

    /// About to do something you can't undo.
    static func warn()      { play([(.generic, 75), (.generic, 0)]) }

    /// Did it.
    static func destroy()   { play([(.generic, 45), (.generic, 45), (.levelChange, 0)]) }

    static func success()   { play([(.alignment, 50), (.levelChange, 50), (.alignment, 0)]) }

    /// The angry face — a stutter you can't miss.
    static func nudge() {
        play([(.generic, 70), (.generic, 70), (.generic, 70), (.levelChange, 90), (.alignment, 0)])
    }
}

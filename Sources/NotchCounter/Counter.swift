import SwiftUI

@MainActor
final class Counter: ObservableObject {
    private static let key = "counter.value"

    @Published var value: Int {
        didSet { UserDefaults.standard.set(value, forKey: Self.key) }
    }
    /// Notch expanded because the pointer is over it.
    @Published var isOpen = false
    /// Reset confirmation is showing.
    @Published var confirmingReset = false

    init() {
        value = UserDefaults.standard.integer(forKey: Self.key)
    }

    func increment() { value += 1 }
    func decrement() { value -= 1 }

    func reset() {
        value = 0
        confirmingReset = false
    }
}

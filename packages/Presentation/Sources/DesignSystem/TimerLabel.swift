import SwiftUI

/// The caller owns ticking. The accessibility label stays unchanged within each minute.
public struct TimerLabel: View {
    private let remainingSeconds: Int
    public init(remainingSeconds: Int) { self.remainingSeconds = remainingSeconds }
    public nonisolated static func displayText(remainingSeconds: Int) -> String {
        let seconds = max(0, remainingSeconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    public nonisolated static func accessibilityLabel(remainingSeconds: Int) -> String {
        String(format: String(localized: "timer.remaining", bundle: .module), max(0, remainingSeconds) / 60)
    }
    public var body: some View {
        Label(Self.displayText(remainingSeconds: remainingSeconds), systemImage: "timer")
            .font(.headline).monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityLabel(remainingSeconds: remainingSeconds))
    }
}

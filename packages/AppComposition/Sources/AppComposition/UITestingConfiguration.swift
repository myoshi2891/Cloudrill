#if DEBUG
import Foundation
import StudyModels
import Synchronization

public enum UITestingConfigurationError: Error, Equatable { case invalidArguments }

public struct UITestingConfiguration: Sendable {
    public let date: Date
    public let storeDirectory: URL?
    public let fixture: String?
    public let offline: Bool

    public init(arguments: [String]) throws(UITestingConfigurationError) {
        guard arguments.contains("-ui-testing") else { throw .invalidArguments }
        var values: [String: String] = [:], flags: Set<String> = []
        let boolean: Set<String> = ["-ui-testing", "-store-in-memory"]
        let valued: Set<String> = ["-fixed-now", "-advance-on-launch", "-content-fixture", "-store-path", "-network"]
        var index = 0
        while index < arguments.count {
            let name = arguments[index]
            guard flags.insert(name).inserted else { throw .invalidArguments }
            if boolean.contains(name) { index += 1; continue }
            guard valued.contains(name), index + 1 < arguments.count else { throw .invalidArguments }
            values[name] = arguments[index + 1]; index += 2
        }
        guard let start = ISO8601DateFormatter().date(from: values["-fixed-now"] ?? "2026-11-01T09:00:00Z"),
              let advance = Double(values["-advance-on-launch"] ?? "0"), advance.isFinite, advance >= 0,
              values["-network"] == nil || values["-network"] == "offline" else { throw .invalidArguments }
        let date = start.addingTimeInterval(advance)
        guard date.timeIntervalSince1970.isFinite else { throw .invalidArguments }
        self.date = date
        if let path = values["-store-path"] {
            guard path.hasPrefix("/"), !flags.contains("-store-in-memory") else { throw .invalidArguments }
            storeDirectory = URL(fileURLWithPath: path, isDirectory: true)
        } else { storeDirectory = nil }
        if let fixture = values["-content-fixture"] {
            guard fixture.range(of: #"\A[a-z0-9]+(?:-[a-z0-9]+)*\z"#, options: .regularExpression) != nil else { throw .invalidArguments }
        }
        fixture = values["-content-fixture"]
        offline = values["-network"] == "offline"
    }
}

public final class UITestingTimeSource: TimeSource {
    private let date: Mutex<Date>
    public init(_ date: Date) { self.date = Mutex(date) }
    public func now() -> Date { date.withLock { $0 } }
    public func advance(by seconds: TimeInterval) { date.withLock { $0 = $0.addingTimeInterval(seconds) } }
}
#endif

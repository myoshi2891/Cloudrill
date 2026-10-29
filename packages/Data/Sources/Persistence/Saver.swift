import SwiftData

public protocol Saver: Sendable {
    func save(_ context: ModelContext) throws
}
public struct ContextSaver: Saver {
    public init() {}
    public func save(_ context: ModelContext) throws { try context.save() }
}

public enum PersistenceError: Error, Equatable, Sendable {
    case notFound
    case corrupted(String)
    case saveFailed(String)
}

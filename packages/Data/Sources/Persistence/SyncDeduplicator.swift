import SwiftData
import DomainInterfaces
@ModelActor public actor SyncDeduplicator {
    public func run() throws(PersistenceError) -> SyncMerge.Plan { .init() }
}

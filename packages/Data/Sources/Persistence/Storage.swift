import Foundation
import SwiftData
import DomainInterfaces

enum Storage {
    // Separate repository contexts share this read/write barrier, including bulk deletion.
    // Hold it through save retries and rollback so deletion cannot miss an in-flight write.
    // Writes can synchronously call reads (for example, markRead calls isRead).
    private static let accessLock = NSRecursiveLock()
    static func read<T>(_ body: () throws -> T) throws(PersistenceError) -> T {
        accessLock.lock()
        defer { accessLock.unlock() }
        do { return try body() }
        catch let error as PersistenceError { throw error }
        catch { throw .corrupted(String(describing: error)) }
    }
    /// actor 内で同期実行し、変更から save の間に再入されない。再試行は1回だけ。
    static func write<T>(_ context: ModelContext, saver: any Saver, _ body: () throws -> T) throws(PersistenceError) -> T {
        accessLock.lock()
        defer { accessLock.unlock() }
        context.autosaveEnabled = false
        do {
            let result = try body()
            do { try saver.save(context) }
            catch {
                do { try saver.save(context) }
                catch { throw PersistenceError.saveFailed(String(describing: error)) }
            }
            return result
        } catch {
            context.rollback()
            if let error = error as? PersistenceError { throw error }
            throw .corrupted(String(describing: error))
        }
    }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T { try JSONDecoder().decode(type, from: data) }
}

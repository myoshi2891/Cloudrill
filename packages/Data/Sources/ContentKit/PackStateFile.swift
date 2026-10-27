import Foundation
import DomainInterfaces

struct PackStateFile {
    let url: URL
    let fileManager: FileManager
    func read() throws(ContentError) -> PackState {
        guard fileManager.fileExists(atPath: url.path) else { return PackState() }
        do { return try JSONDecoder().decode(PackState.self, from: Data(contentsOf: url)) }
        catch { throw .storage("state read failed: \(error)") }
    }
    func write(_ state: PackState) throws(ContentError) {
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(state).write(to: url, options: .atomic)
        } catch { throw .storage("state write failed: \(error)") }
    }
}

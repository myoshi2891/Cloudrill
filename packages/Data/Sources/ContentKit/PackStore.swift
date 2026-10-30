import Foundation
import DomainModels
import DomainInterfaces

/// 書き込みを直列化する。状態は毎回ディスクから読み、書き込み失敗時にメモリだけが進むのを防ぐ。
public actor PackStore: PackPinning {
    private let root: URL
    private let bundledRoot: URL?
    private let retainedLimit: Int
    private let fileManager: FileManager
    /// bundledRoot はアプリ同梱の Packs/。同梱版を固定するとき、アプリ更新で消えないよう保存先へ複製する。
    /// retainedLimit は提出後も結果・解説を開けるよう版を保持する受験の件数（試験ごと、新しい順）。
    public init(root: URL, bundledRoot: URL? = nil, retainedLimit: Int = 20, fileManager: FileManager = .default) {
        self.root = root.standardizedFileURL
        self.bundledRoot = bundledRoot?.standardizedFileURL
        self.retainedLimit = max(0, retainedLimit)
        self.fileManager = fileManager
    }
    private func examPath(_ exam: ExamID, _ suffix: String = "") throws(ContentError) -> URL {
        guard exam.rawValue.range(of: #"\A[a-z0-9]+(?:-[a-z0-9]+)*\z"#, options: .regularExpression) != nil else {
            throw .storage("invalid exam ID")
        }
        var url = root
        for part in ([exam.rawValue] + suffix.split(separator: "/").map(String.init)) {
            url.append(path: part)
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw .storage("symlink in pack store") }
        }
        return url
    }
    private func checkVersion(_ version: String) throws(ContentError) {
        guard SemanticVersion(version) != nil else { throw .storage("invalid pack version") }
    }
    private func stateFile(_ exam: ExamID) throws(ContentError) -> PackStateFile {
        try PackStateFile(url: examPath(exam, "state.json"), fileManager: fileManager)
    }
    private func isDirectory(_ url: URL) -> Bool { (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    public func state(for examID: ExamID) throws(ContentError) -> PackState { try stateFile(examID).read() }

    /// 呼び出し側で署名・整合検証済みの staging を、同じ試験の versions に移す。
    public func install(staged: URL, version: String, for examID: ExamID) throws(ContentError) {
        try checkVersion(version)
        let target = try examPath(examID, "versions/\(version)")
        guard !fileManager.fileExists(atPath: target.path) else { throw .storage("\(version) already installed") }
        let staging = try examPath(examID, "staging")
        guard staged.standardizedFileURL.deletingLastPathComponent().path == staging.path,
              UUID(uuidString: staged.lastPathComponent) != nil,
              (try? staged.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
              isDirectory(staged) else { throw .storage("invalid staging directory") }
        do {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: staged, to: target)
        } catch { throw .storage("install failed: \(error)") }
    }
    public func activate(_ location: PackLocation, for examID: ExamID) throws(ContentError) {
        try checkVersion(location.version)
        if location.source == .installed, try !isDirectory(examPath(examID, "versions/\(location.version)")) {
            throw .storage("version is not installed")
        }
        let file = try stateFile(examID)
        var state = try file.read()
        guard state.current != location else { return }
        state.previous = state.current
        state.current = location
        try file.write(state)
    }
    public func rollback(for examID: ExamID) throws(ContentError) {
        let file = try stateFile(examID)
        var state = try file.read()
        guard let previous = state.previous else { throw .storage("no previous version") }
        state.current = previous
        state.previous = nil
        try file.write(state)
    }
    /// 固定した版は必ず保存先に置く。同梱にしかない版は複製してから記録する。
    public func pin(_ version: String, for examID: ExamID, attemptID: UUID) throws(ContentError) {
        try checkVersion(version)
        let file = try stateFile(examID)
        var state = try file.read()
        if try !isDirectory(examPath(examID, "versions/\(version)")) {
            try installBundled(version, for: examID)
        }
        state.pins[attemptID] = version
        try file.write(state)
    }
    /// 提出済みの受験の固定を保持枠へ移し、保持枠を超えた古い受験の固定を外す。固定がなければ何もしない。
    public func retain(attemptID: UUID, for examID: ExamID) throws(ContentError) {
        let file = try stateFile(examID)
        var state = try file.read()
        guard state.pins[attemptID] != nil else { return }
        if !state.retained.contains(attemptID) { state.retained.append(attemptID) }
        while state.retained.count > retainedLimit {
            state.pins.removeValue(forKey: state.retained.removeFirst())
        }
        try file.write(state)
    }
    public func unpin(attemptID: UUID, for examID: ExamID) throws(ContentError) {
        let file = try stateFile(examID)
        var state = try file.read()
        state.pins.removeValue(forKey: attemptID)
        state.retained.removeAll { $0 == attemptID }
        try file.write(state)
    }
    /// 同梱版を staging に複製し、manifest の一致を確認してから install する。失敗時は staging を残さない。
    private func installBundled(_ version: String, for examID: ExamID) throws(ContentError) {
        guard let bundledRoot else { throw .storage("version is not available") }
        let source = bundledRoot.appending(path: "\(examID.rawValue)/\(version)")
        guard (try? source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false, isDirectory(source) else {
            throw .storage("version is not available")
        }
        let staged = try examPath(examID, "staging/\(UUID().uuidString)")
        do throws(ContentError) {
            do {
                try fileManager.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: source, to: staged)
            } catch { throw ContentError.storage("bundled copy failed: \(error)") }
            let manifest = try PackLoader().manifest(packAt: staged)
            guard manifest.examID == examID, manifest.packVersion == version else {
                throw ContentError.storage("pack manifest identity mismatch")
            }
            try install(staged: staged, version: version, for: examID)
        } catch {
            try? fileManager.removeItem(at: staged)
            throw error
        }
    }
    public func garbageCollect(for examID: ExamID) throws(ContentError) {
        let state = try state(for: examID)
        let protected = Set([state.current?.version, state.previous?.version].compactMap { $0 }).union(state.pins.values)
        let versions = try examPath(examID, "versions")
        guard fileManager.fileExists(atPath: versions.path) else { return }
        do {
            for file in try fileManager.contentsOfDirectory(at: versions, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                guard SemanticVersion(file.lastPathComponent) != nil, !protected.contains(file.lastPathComponent),
                      try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true, isDirectory(file) else { continue }
                try fileManager.removeItem(at: file)
            }
        } catch { throw .storage("garbage collection failed: \(error)") }
    }
    public func directory(for location: PackLocation, examID: ExamID, bundledRoot: URL) throws(ContentError) -> URL {
        try checkVersion(location.version)
        let installed = try examPath(examID, "versions/\(location.version)")
        return location.source == .installed ? installed : bundledRoot.appending(path: "\(examID.rawValue)/\(location.version)").standardizedFileURL
    }
}

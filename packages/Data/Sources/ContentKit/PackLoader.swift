import Foundation
import DomainModels
import DomainInterfaces

public struct PackLoader: Sendable {
    private let reader: any FileReading
    public init(fileReader: any FileReading = FileManagerReader()) { reader = fileReader }

    /// 同梱、またはインストール時に検証済みのパックの起動用。署名の検証は行わない。
    func manifest(packAt directory: URL) throws(ContentError) -> Manifest {
        try PackFiles(root: directory, reader: reader).decode(Manifest.self, "manifest.json")
    }

    public func load(packAt directory: URL, manifest: Manifest) throws(ContentError) -> PackContent {
        let files = PackFiles(root: directory, reader: reader)
        return try PackContent(
            definition: files.decode(ExamDefinition.self, "exam.json"),
            vendor: files.decode(Vendor.self, "vendor.json"), packVersion: manifest.packVersion,
            questionIndex: files.decode([QuestionIndexEntry].self, "questions/index.json"),
            examSets: files.decode(ExamSetsFile.self, "exam-sets.json").examSets,
            docsIndex: files.decode([DocEntry].self, "docs/index.json"), files: files
        )
    }
}

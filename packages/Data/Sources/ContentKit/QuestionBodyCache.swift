import DomainModels
import DomainInterfaces

actor QuestionBodyCache {
    private let domains: [String: Int]
    private let files: PackFiles
    private var cache: [Int: [String: Question]] = [:]

    init(index: [QuestionIndexEntry], files: PackFiles) {
        domains = index.reduce(into: [:]) { $0[$1.id] = $1.domain }
        self.files = files
    }

    func questions(ids: [String]) throws(ContentError) -> [Question] {
        let unknown = ids.filter { domains[$0] == nil }
        guard unknown.isEmpty else { throw .unknownQuestionIDs(unknown) }
        for domain in Set(ids.compactMap { domains[$0] }).sorted() where cache[domain] == nil {
            let questions = try files.decode([Question].self, "questions/domain\(domain).json")
            cache[domain] = questions.reduce(into: [:]) { $0[$1.id] = $1 }
        }
        // await を挟まないので、同時要求でもドメインごとの読み込みは1回。
        var result: [Question] = []
        var missing: [String] = []
        for id in ids {
            if let domain = domains[id], let question = cache[domain]?[id] { result.append(question) }
            else { missing.append(id) }
        }
        guard missing.isEmpty else { throw .unknownQuestionIDs(missing) }
        return result
    }
}

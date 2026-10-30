import AppCore
import DomainModels
import DomainInterfaces

public struct ExamTopViewModel {
    public let sets: [ExamSet]
    public init(content: any ExamContentProvider, includesDrafts: Bool = false) {
        #if DEBUG
        let drafts = includesDrafts
        #else
        let drafts = false
        #endif
        sets = content.examSets.filter {
            $0.id >= 1 && $0.id <= content.definition.format.mockExam.setCount
                && ($0.status == .complete || drafts)
        }.sorted { $0.id < $1.id }
    }
}

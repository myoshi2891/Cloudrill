import SwiftUI
import DomainModels

#if DEBUG
private struct ComponentGallery: View {
    @State private var selected = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ChoiceRow(id: "B", text: "必要な可用性を満たす構成を選択します。長い選択肢も省略せずに表示します。",
                          isSelected: selected) { selected.toggle() }
                ForEach(0..<12) { index in
                    DomainBadge(index: index, title: "ドメイン \(index + 1)")
                }
                CaseBadge(title: "サンプル企業")
                TimerLabel(remainingSeconds: 5262)
                ResultBadge(isCorrect: true)
                ResultBadge(isCorrect: false)
                ForEach(MistakeTag.allCases, id: \.self) { MistakeTagChip($0) }
                ReferenceLink(Reference(title: "参考資料", url: URL(string: "https://example.com")!, license: .ccBy40))
            }.padding()
        }
    }
}

#Preview("Light") { ComponentGallery().preferredColorScheme(.light) }
#Preview("Dark") { ComponentGallery().preferredColorScheme(.dark) }
#Preview("Largest text") { ComponentGallery().environment(\.dynamicTypeSize, .accessibility5) }
#endif

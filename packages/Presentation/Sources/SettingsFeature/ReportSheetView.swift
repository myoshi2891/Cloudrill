import SwiftUI
import AppCore
import DomainInterfaces

/// 誤り報告のシート(SCR-090)。解説画面などから、表示中の問題の版付きコンテキストで開く。
public struct ReportSheetView: View {
    @State private var model: ReportSheetViewModel
    @Environment(\.dismiss) private var dismiss

    public init(model: ReportSheetViewModel) { _model = State(initialValue: model) }

    /// 依存は Composition root が注入した `AppDependencies` から取る。
    public init(context: QuestionReportContext, dependencies: AppDependencies) {
        self.init(model: ReportSheetViewModel(context: context, queue: dependencies.reports, sender: dependencies.reportSender,
                                              metadata: dependencies.reportMetadata, time: dependencies.time))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(String(localized: "report.question", bundle: .module), value: model.context.questionID)
                    LabeledContent(String(localized: "report.revision", bundle: .module), value: String(model.context.questionRevision))
                    LabeledContent(String(localized: "report.pack", bundle: .module), value: model.context.packVersion)
                }
                Section {
                    Picker(selection: $model.reason) {
                        Text("report.reason.unselected", bundle: .module).tag(ReportReason?.none)
                        ForEach(ReportSheetViewModel.reasons, id: \.self) { reason in
                            Text(ReportSheetViewModel.title(of: reason)).tag(ReportReason?.some(reason))
                        }
                    } label: { Text("report.reason", bundle: .module) }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("report-reason")
                } header: { Text("report.reason", bundle: .module) }
                Section {
                    TextEditor(text: $model.comment)
                        .frame(minHeight: 120)
                        .accessibilityIdentifier("report-comment")
                    Text("report.remaining \(model.remainingCharacters)", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(model.isCommentTooLong ? Color.red : Color.secondary)
                        .accessibilityIdentifier("report-remaining")
                } header: { Text("report.comment", bundle: .module) } footer: {
                    Text(model.privacyNotice).accessibilityIdentifier("report-privacy")
                }
            }
            .disabled(model.outcome != nil)
            // 送信はコメント欄までスクロールした状態で行うことが多いため、結果は常に見える下端に出す
            .safeAreaInset(edge: .bottom) {
                if let message = model.message {
                    banner(Text(message), identifier: "report-message")
                } else if let error = model.error {
                    banner(Text(error).foregroundStyle(.red), identifier: "report-error")
                }
            }
            .navigationTitle(Text("report.title", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Text(LocalizedStringKey(model.outcome == nil ? "report.cancel" : "report.close"), bundle: .module)
                    }
                    .accessibilityIdentifier("report-close")
                }
                if model.outcome == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await model.submit() } } label: { Text("report.submit", bundle: .module) }
                            .disabled(!model.canSubmit)
                            .accessibilityIdentifier("report-submit")
                    }
                }
            }
        }
    }

    private func banner(_ text: some View, identifier: String) -> some View {
        text.frame(maxWidth: .infinity).padding().background(.regularMaterial).accessibilityIdentifier(identifier)
    }
}

import SwiftUI
import DomainModels

/// 設定(SCR-002)。ホームの右上からシートで開く。
public struct SettingsView: View {
    @State private var model: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    public init(model: SettingsViewModel) { _model = State(initialValue: model) }

    public var body: some View {
        NavigationStack {
            Form {
                if let error = model.error {
                    Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("settings-error") }
                }
                studySection
                Section {
                    Toggle(isOn: Binding(get: { model.shuffleChoices },
                                         set: { value in Task { await model.setShuffleChoices(value) } })) {
                        Text("settings.shuffle", bundle: .module)
                    }
                    .accessibilityIdentifier("settings-shuffle")
                } header: { Text("settings.display", bundle: .module) } footer: {
                    Text("settings.shuffleFooter", bundle: .module)
                }
                .disabled(!model.isLoaded)
                dataSection
                aboutSection
            }
            .navigationTitle(Text("settings.title", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("settings.close", bundle: .module) }
                        .accessibilityIdentifier("settings-close")
                }
            }
            .task { await model.load() }
            .confirmationDialog(Text(dialogTitle), isPresented: Binding(
                get: { model.pendingDeletion != nil }, set: { if !$0 { model.cancelDelete() } }),
                titleVisibility: .visible, presenting: model.pendingDeletion) { scope in
                Button(role: .destructive) { Task { await model.confirmDelete(scope) } } label: {
                    Text("settings.delete.confirm", bundle: .module)
                }
                .accessibilityIdentifier("settings-delete-confirm")
                Button(role: .cancel) { model.cancelDelete() } label: { Text("settings.cancel", bundle: .module) }
            } message: { _ in Text("settings.delete.message", bundle: .module) }
        }
    }

    private var studySection: some View {
        Section {
            Stepper(value: Binding(get: { model.preference.dailyNewCards },
                                   set: { value in Task { await model.setDailyNewCards(value) } }),
                    in: SettingsViewModel.newCardsRange, step: SettingsViewModel.newCardsStep) {
                LabeledContent(String(localized: "settings.newCards", bundle: .module), value: String(model.preference.dailyNewCards))
            }
            .accessibilityIdentifier("settings-new-cards")
            Stepper(value: Binding(get: { model.preference.dailyReviewLimit },
                                   set: { value in Task { await model.setDailyReviewLimit(value) } }),
                    in: SettingsViewModel.reviewLimitRange, step: SettingsViewModel.reviewLimitStep) {
                LabeledContent(String(localized: "settings.reviewLimit", bundle: .module), value: String(model.preference.dailyReviewLimit))
            }
            .accessibilityIdentifier("settings-review-limit")
            Toggle(isOn: Binding(get: { model.preference.autoCardFromMistakes },
                                 set: { value in Task { await model.setAutoCardFromMistakes(value) } })) {
                Text("settings.autoCard", bundle: .module)
            }
        } header: { Text("settings.study \(model.examName)", bundle: .module) }
        .disabled(!model.isLoaded)
    }

    private var dataSection: some View {
        Section {
            if let file = model.exportFile {
                ShareLink(item: file) { Text("settings.export.share", bundle: .module) }
                    .accessibilityIdentifier("settings-export-share")
            } else {
                Button { Task { await model.exportData() } } label: { Text("settings.export", bundle: .module) }
                    .accessibilityIdentifier("settings-export")
            }
            Button(role: .destructive) { model.requestDelete(.exam) } label: {
                Text("settings.delete.exam \(model.examName)", bundle: .module)
            }
            .accessibilityIdentifier("settings-delete-exam")
            Button(role: .destructive) { model.requestDelete(.all) } label: { Text("settings.delete.all", bundle: .module) }
                .accessibilityIdentifier("settings-delete-all")
        } header: { Text("settings.data", bundle: .module) }
        .disabled(model.isBusy)
    }

    private var aboutSection: some View {
        Section {
            LabeledContent(String(localized: "settings.about.version", bundle: .module), value: model.appVersion)
            Text(model.unofficialNotice).accessibilityIdentifier("settings-unofficial")
            Text(model.noGuaranteeNotice).accessibilityIdentifier("settings-no-guarantee")
            ForEach(model.vendors) { vendor in
                Text(vendor.trademarkNotice.ja).font(.footnote).foregroundStyle(.secondary)
            }
        } header: { Text("settings.about", bundle: .module) }
    }

    private var dialogTitle: String {
        switch model.pendingDeletion {
        case .exam: String(localized: "settings.delete.examTitle \(model.examName)", bundle: .module)
        case .all, nil: String(localized: "settings.delete.allTitle", bundle: .module)
        }
    }
}

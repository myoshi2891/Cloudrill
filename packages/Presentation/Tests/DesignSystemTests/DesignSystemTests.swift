import Foundation
import Testing
import DomainModels
@testable import DesignSystem

struct DesignSystemTests {
    @Test func paletteAssignsByIndexAndDistinguishesRepeatedColors() {
        let first = (0..<6).map { DomainPalette.style(forDomainAt: $0) }
        #expect(Set(first.map(\.light)).count == 6)
        #expect(Set(first.map(\.dark)).count == 6)
        let all = (0..<48).map { DomainPalette.style(forDomainAt: $0) }
        #expect(Set(all).count == 48)
        for index in 6..<48 {
            #expect(all[index].light == all[index % 6].light)
            #expect(all[index].symbol != all[index - 6].symbol)
        }
    }

    @Test(arguments: 0..<6) func paletteContrast(index: Int) {
        let style = DomainPalette.style(forDomainAt: index)
        // WCAG relative luminance, independently computed from sRGB channels.
        func luminance(_ rgb: PaletteRGB) -> Double {
            func linear(_ value: Double) -> Double {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
        }
        #expect(1.05 / (luminance(style.light) + 0.05) >= 4.5)
        #expect((luminance(style.dark) + 0.05) / 0.05 >= 4.5)
    }

    @Test func choiceLabelIncludesSelectionState() {
        #expect(ChoiceRow.accessibilityLabel(for: "B", isSelected: true) == "選択肢B、選択済み")
        #expect(ChoiceRow.accessibilityLabel(for: "A", isSelected: false) == "選択肢A、未選択")
    }

    @Test func resultsHaveDifferentIconsAndWords() {
        #expect(ResultBadge.symbolName(isCorrect: true) == "checkmark.circle.fill")
        #expect(ResultBadge.symbolName(isCorrect: false) == "xmark.circle.fill")
        #expect(ResultBadge.title(isCorrect: true) == "正解")
        #expect(ResultBadge.title(isCorrect: false) == "不正解")
    }

    @Test func timerUsesWholeMinutesForVoiceOver() {
        #expect(TimerLabel.accessibilityLabel(remainingSeconds: 5262) == "残り 87 分")
        #expect(TimerLabel.accessibilityLabel(remainingSeconds: 5220) == "残り 87 分")
        #expect(TimerLabel.accessibilityLabel(remainingSeconds: 60) == "残り 1 分")
        #expect(TimerLabel.accessibilityLabel(remainingSeconds: 59) == "残り 1 分未満")
        #expect(TimerLabel.accessibilityLabel(remainingSeconds: 1) == "残り 1 分未満")
        #expect(TimerLabel.accessibilityLabel(remainingSeconds: 0) == "残り 0 分")
        #expect(TimerLabel.accessibilityLabel(remainingSeconds: -1) == "残り 0 分")
        #expect(TimerLabel.displayText(remainingSeconds: 5262) == "87:42")
        #expect(TimerLabel.displayText(remainingSeconds: -1) == "0:00")
    }

    @Test func allMistakeTagsHaveDistinctLocalizedTitlesAndIcons() {
        #expect(Set(MistakeTag.allCases.map { MistakeTagChip.title(for: $0) }).count == 8)
        for tag in MistakeTag.allCases {
            #expect(MistakeTagChip.title(for: tag) != "mistake.\(tag.rawValue)")
            #expect(!MistakeTagChip.symbolName(for: tag).isEmpty)
        }
    }
}

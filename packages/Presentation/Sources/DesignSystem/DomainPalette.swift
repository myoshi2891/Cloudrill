import SwiftUI

/// sRGB values shared by rendering and contrast verification.
public struct PaletteRGB: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    init(hex: UInt32) {
        red = Double((hex >> 16) & 255) / 255
        green = Double((hex >> 8) & 255) / 255
        blue = Double(hex & 255) / 255
    }

    public var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}

public struct DomainStyle: Hashable, Sendable {
    public let light: PaletteRGB
    public let dark: PaletteRGB
    public let symbol: String

    public func foreground(for scheme: ColorScheme) -> Color {
        (scheme == .dark ? dark : light).color
    }
}

public enum DomainPalette {
    private static let light: [UInt32] = [0x164E9C, 0x006653, 0x713AA6, 0x923818, 0x9D2457, 0x505900]
    private static let dark: [UInt32] = [0x9EC5FF, 0x76DCC2, 0xD6B3FF, 0xFFB699, 0xFFA8CC, 0xD8DE86]
    private static let symbols = ["●", "▲", "■", "◆", "★", "⬟"]

    /// Uses definition order, not a hard-coded exam domain ID. Negative input maps to the first domain.
    public static func style(forDomainAt index: Int) -> DomainStyle {
        let index = max(0, index), cycle = index / light.count
        let symbol = cycle < symbols.count ? symbols[cycle] : "\(cycle + 1)"
        return DomainStyle(light: PaletteRGB(hex: light[index % light.count]),
                           dark: PaletteRGB(hex: dark[index % dark.count]), symbol: symbol)
    }

    public static func color(forDomainAt index: Int, scheme: ColorScheme) -> Color {
        style(forDomainAt: index).foreground(for: scheme)
    }
}

public enum StudyColors {
    // Domain badges use these opaque surfaces so their contrast is independent of the parent view.
    public static func surface(for scheme: ColorScheme) -> Color { scheme == .dark ? .black : .white }
    public static func result(isCorrect: Bool, scheme: ColorScheme) -> Color {
        DomainPalette.color(forDomainAt: isCorrect ? 1 : 4, scheme: scheme)
    }
}

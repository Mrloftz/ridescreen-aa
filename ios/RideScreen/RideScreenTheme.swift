// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

enum RideScreenTheme {
    static let background = Color(hex: 0x1A231D)
    static let surface = Color(hex: 0x243028)
    static let elevated = Color(hex: 0x2D3B31)
    static let outline = Color(hex: 0x3D4F42)
    static let primary = Color(hex: 0xF1F4EC)
    static let secondary = Color(hex: 0xAEBAAA)
    static let gold = Color(hex: 0xD1A955)
    static let goldDark = Color(hex: 0xA9873E)
    static let onBrand = Color(hex: 0x18211A)
    static let live = Color(hex: 0x5BD47A)
    static let busy = Color(hex: 0xE9C46A)
    static let error = Color(hex: 0xFF6B5E)
    static let idle = Color(hex: 0x8E9C90)

    static func displayFont(size: CGFloat) -> Font {
        .custom("ArchivoBlack-Regular", fixedSize: size, relativeTo: .largeTitle)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct RideCard: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RideScreenTheme.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(RideScreenTheme.outline, lineWidth: 1)
            }
    }
}

extension View {
    func rideCard(padding: CGFloat = 16, radius: CGFloat = 20) -> some View {
        modifier(RideCard(padding: padding, radius: radius))
    }
}

struct RidePrimaryButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isDestructive ? RideScreenTheme.primary : RideScreenTheme.onBrand)
            .background(
                isDestructive ? RideScreenTheme.error : RideScreenTheme.gold,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct RideSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(RideScreenTheme.primary)
            .background(RideScreenTheme.elevated, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(RideScreenTheme.outline, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct RideSectionHeading: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(RideScreenTheme.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(RideScreenTheme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RideMetricCard: View {
    let title: String
    let value: String
    let unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(RideScreenTheme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(RideScreenTheme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(RideScreenTheme.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .rideCard(padding: 15, radius: 18)
    }
}

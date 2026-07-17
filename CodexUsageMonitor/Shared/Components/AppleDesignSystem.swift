import SwiftUI

enum AppleUI {
    static let smallRadius: CGFloat = 13
    static let cardRadius: CGFloat = 12
    static let heroRadius: CGFloat = 12
    static let largeRadius: CGFloat = 16
    static let controlHeight: CGFloat = 42

    static let accent = Color(red: 0.16, green: 0.46, blue: 0.96)
    static let purple = Color(red: 0.48, green: 0.36, blue: 0.90)
    static let success = Color(red: 0.20, green: 0.72, blue: 0.40)
    static let warning = Color(red: 0.96, green: 0.58, blue: 0.18)
    static let danger = Color(red: 0.95, green: 0.25, blue: 0.25)
}

struct AppBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Color(nsColor: reduceTransparency ? .windowBackgroundColor : .controlBackgroundColor)
        .ignoresSafeArea()
    }
}

struct AppleCard<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = AppleUI.cardRadius
    var shadowRadius: CGFloat = 0
    var shadowY: CGFloat = 0
    var material: Material = .thinMaterial
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .background {
                if reduceTransparency {
                    shape.fill(Color(nsColor: .controlBackgroundColor))
                } else {
                    shape.fill(material)
                    shape.fill(Color(nsColor: .controlBackgroundColor).opacity(0.50))
                }
            }
            .overlay {
                shape.strokeBorder(Color(nsColor: .separatorColor).opacity(contrast == .increased ? 0.55 : 0.28),
                                   lineWidth: contrast == .increased ? 1 : 0.75)
            }
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct SymbolTile: View {
    let symbol: String
    var color: Color = AppleUI.accent

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: 30, height: 30)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.6)
            }
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let feedback = StableButtonPressFeedback(isPressed: configuration.isPressed)
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(minHeight: AppleUI.controlHeight)
            .padding(.horizontal, 20)
            .liquidGlassSurface(cornerRadius: 14, tint: AppleUI.accent, interactive: true)
            .opacity(feedback.contentOpacity)
    }
}

struct GlassButtonStyle: ButtonStyle {
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let feedback = StableButtonPressFeedback(isPressed: configuration.isPressed)
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 15)
            .frame(minHeight: 38)
            .liquidGlassSurface(cornerRadius: 14, tint: tint, interactive: true)
            .background((tint ?? Color.primary).opacity(feedback.fillOpacity), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(feedback.contentOpacity)
    }
}

struct CompactGlassButtonStyle: ButtonStyle {
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let feedback = StableButtonPressFeedback(isPressed: configuration.isPressed)
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .liquidGlassSurface(cornerRadius: 13, tint: tint, interactive: true)
            .background((tint ?? Color.primary).opacity(feedback.fillOpacity), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .opacity(feedback.contentOpacity)
    }
}

extension View {
    /// Uses native Liquid Glass on macOS 26 and later, with a system-material
    /// fallback that preserves contrast and geometry on macOS 15.
    @ViewBuilder
    func liquidGlassSurface(cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            let glass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
            self.glassEffect(
                interactive ? glass.interactive() : glass,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.fill((tint ?? Color.primary).opacity(tint == nil ? 0.018 : 0.055)) }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.18), .primary.opacity(0.065)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
                }
        }
    }
}

struct PanelUtilityButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        let feedback = StableButtonPressFeedback(isPressed: configuration.isPressed)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        configuration.label
            .background {
                shape.fill(reduceTransparency
                    ? Color(nsColor: .controlBackgroundColor).opacity(configuration.isPressed ? 0.92 : 0.62)
                    : Color.white.opacity(configuration.isPressed ? 0.14 : 0.055))
            }
            .overlay {
                shape.strokeBorder(Color(nsColor: .separatorColor).opacity(configuration.isPressed ? 0.20 : 0.08), lineWidth: 0.5)
            }
            .opacity(feedback.contentOpacity)
    }
}

/// MenuBarExtra window content must keep a stable fitting size while a control is pressed.
/// Color and opacity provide local feedback; scale intentionally remains at one.
struct StableButtonPressFeedback: Equatable {
    let contentOpacity: Double
    let fillOpacity: Double

    init(isPressed: Bool) {
        contentOpacity = isPressed ? 0.78 : 1
        fillOpacity = isPressed ? 0.12 : 0.045
    }
}

struct SettingsRow<Control: View>: View {
    let symbol: String
    let color: Color
    let title: String
    var detail: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 13) {
            SymbolTile(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 16)
            control
        }
        .padding(.vertical, 4)
    }
}

import SwiftUI

enum AppleUI {
    static let smallRadius: CGFloat = 11
    static let cardRadius: CGFloat = 18
    static let heroRadius: CGFloat = 22
    static let largeRadius: CGFloat = 24
    static let controlHeight: CGFloat = 40

    static let accent = Color(red: 0.16, green: 0.46, blue: 0.96)
    static let purple = Color(red: 0.48, green: 0.36, blue: 0.90)
    static let success = Color(red: 0.20, green: 0.72, blue: 0.40)
    static let warning = Color(red: 0.96, green: 0.58, blue: 0.18)
    static let danger = Color(red: 0.95, green: 0.25, blue: 0.25)
}

struct AppBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if !reduceTransparency {
                ZStack {
                    RadialGradient(
                        stops: [
                            .init(color: AppleUI.accent.opacity(0.050), location: 0),
                            .init(color: AppleUI.accent.opacity(0.018), location: 0.48),
                            .init(color: .clear, location: 1)
                        ],
                        center: UnitPoint(x: 0.08, y: 0.08),
                        startRadius: 0,
                        endRadius: 760
                    )
                    RadialGradient(
                        stops: [
                            .init(color: AppleUI.purple.opacity(0.032), location: 0),
                            .init(color: AppleUI.purple.opacity(0.012), location: 0.52),
                            .init(color: .clear, location: 1)
                        ],
                        center: UnitPoint(x: 0.92, y: 0.88),
                        startRadius: 0,
                        endRadius: 820
                    )
                }
                .scaleEffect(1.08)
                .blur(radius: 44, opaque: false)
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

struct AppleCard<Content: View>: View {
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = AppleUI.cardRadius
    var shadowRadius: CGFloat = 8
    var shadowY: CGFloat = 2
    var material: Material = .thinMaterial
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .background {
                shape.fill(reduceTransparency
                    ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                    : AnyShapeStyle(material))
            }
            .overlay {
                shape.strokeBorder(.primary.opacity(contrast == .increased ? 0.18 : 0.075), lineWidth: contrast == .increased ? 1 : 0.7)
            }
            .shadow(color: .black.opacity(shadowRadius > 12 ? 0.055 : 0.035), radius: shadowRadius, y: shadowY)
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
            .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(minHeight: AppleUI.controlHeight)
            .padding(.horizontal, 20)
            .background(AppleUI.accent.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.2), value: configuration.isPressed)
    }
}

struct GlassButtonStyle: ButtonStyle {
    var tint: Color? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 15)
            .frame(minHeight: 36)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).fill((tint ?? .clear).opacity(configuration.isPressed ? 0.06 : 0.08)) }
            .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.primary.opacity(0.07), lineWidth: 0.7) }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.spring(duration: 0.28, bounce: 0.18), value: configuration.isPressed)
    }
}

struct CompactGlassButtonStyle: ButtonStyle {
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let feedback = StablePanelPressFeedback(isPressed: configuration.isPressed)
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(.thinMaterial, in: shape)
            .overlay { shape.fill((tint ?? Color.primary).opacity(feedback.fillOpacity)) }
            .overlay { shape.strokeBorder(.primary.opacity(0.065), lineWidth: 0.7) }
            .scaleEffect(feedback.scale)
            .opacity(feedback.contentOpacity)
    }
}

struct PanelUtilityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let feedback = StablePanelPressFeedback(isPressed: configuration.isPressed)
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.065 : 0))
            .scaleEffect(feedback.scale)
            .opacity(feedback.contentOpacity)
    }
}

/// MenuBarExtra window content must keep a stable fitting size while a control is pressed.
/// Color and opacity provide local feedback; scale intentionally remains at one.
struct StablePanelPressFeedback: Equatable {
    let contentOpacity: Double
    let fillOpacity: Double
    let scale: CGFloat

    init(isPressed: Bool) {
        contentOpacity = isPressed ? 0.78 : 1
        fillOpacity = isPressed ? 0.12 : 0.045
        scale = 1
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

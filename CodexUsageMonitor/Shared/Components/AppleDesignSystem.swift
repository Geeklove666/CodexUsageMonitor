import SwiftUI

enum AppleUI {
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 16
    static let spacingXL: CGFloat = 24
    static let contentPadding: CGFloat = 22
    static let panelPadding: CGFloat = 12

    static let iconRadius: CGFloat = 9
    static let controlRadius: CGFloat = 12
    static let cardRadius: CGFloat = 14
    static let panelRadius: CGFloat = 22
    static let smallRadius = controlRadius
    static let heroRadius = cardRadius
    static let largeRadius = cardRadius
    static let controlHeight: CGFloat = 42

    static let accent = Color(nsColor: .controlAccentColor)
    static let purple = Color(nsColor: .systemPurple)
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let danger = Color(nsColor: .systemRed)

    static func quotaColor(remainingPercentage: Double?) -> Color {
        guard let remainingPercentage else { return accent }
        return switch remainingPercentage {
        case 80...: success
        case 60..<80: accent
        case 40..<60: warning
        case 20..<40: Color(nsColor: .systemOrange)
        default: danger
        }
    }
}

struct AppBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay {
                if !reduceTransparency {
                    Color(nsColor: .controlBackgroundColor).opacity(0.18)
                }
            }
            .ignoresSafeArea()
    }
}

struct AppleCard<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = AppleUI.cardRadius
    var material: Material? = .thinMaterial
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .background {
                if reduceTransparency {
                    shape.fill(stableFill)
                } else if let material {
                    shape.fill(material)
                    shape.fill(Color(nsColor: .controlBackgroundColor).opacity(0.66))
                } else {
                    shape.fill(stableFill)
                }
            }
            .overlay {
                shape.strokeBorder(Color(nsColor: .separatorColor).opacity(contrast == .increased ? 0.55 : 0.18),
                                   lineWidth: contrast == .increased ? 1 : 0.75)
            }
            .shadow(
                color: colorScheme == .dark ? .clear : .black.opacity(0.025),
                radius: 1.5,
                y: 1
            )
    }

    private var stableFill: Color {
        colorScheme == .dark
            ? Color(red: 0.165, green: 0.165, blue: 0.175)
            : Color(red: 0.985, green: 0.982, blue: 0.978)
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppleUI.spacingXS) {
            Text(title).font(.headline.weight(.semibold))
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
            .frame(width: 28, height: 28)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: AppleUI.iconRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppleUI.iconRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.6)
            }
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
            .liquidGlassSurface(cornerRadius: AppleUI.controlRadius, tint: tint, interactive: true)
            .background((tint ?? Color.primary).opacity(feedback.fillOpacity), in: RoundedRectangle(cornerRadius: AppleUI.controlRadius, style: .continuous))
            .modifier(HoverHighlightModifier(cornerRadius: AppleUI.controlRadius))
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
            .liquidGlassSurface(cornerRadius: AppleUI.controlRadius, tint: tint, interactive: true)
            .background((tint ?? Color.primary).opacity(feedback.fillOpacity), in: RoundedRectangle(cornerRadius: AppleUI.controlRadius, style: .continuous))
            .modifier(HoverHighlightModifier(cornerRadius: AppleUI.controlRadius))
            .opacity(feedback.contentOpacity)
    }
}

private struct HoverHighlightModifier: ViewModifier {
    let cornerRadius: CGFloat
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.035 : 0))
                    .allowsHitTesting(false)
            }
            .onHover { isHovering = $0 }
    }
}

extension View {
    /// Uses native Liquid Glass on macOS 26 and later, with a system-material
    /// fallback that preserves contrast and geometry on macOS 15.
    func liquidGlassSurface(cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlassSurfaceModifier(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }
}

private struct LiquidGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .background(stableFill, in: shape)
                .overlay {
                    shape.strokeBorder(Color(nsColor: .separatorColor).opacity(contrast == .increased ? 0.62 : 0.34), lineWidth: 1)
                }
        } else {
            adaptiveSurface(content, shape: shape)
        }
    }

#if compiler(>=6.2)
    @ViewBuilder
    private func adaptiveSurface(_ content: Content, shape: RoundedRectangle) -> some View {
        if #available(macOS 26.0, *) {
            let glass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
            content.glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            materialSurface(content, shape: shape)
        }
    }
#else
    private func adaptiveSurface(_ content: Content, shape: RoundedRectangle) -> some View {
        materialSurface(content, shape: shape)
    }
#endif

    private func materialSurface(_ content: Content, shape: RoundedRectangle) -> some View {
        content
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

    private var stableFill: Color {
        colorScheme == .dark
            ? Color(red: 0.17, green: 0.17, blue: 0.18)
            : Color(red: 0.96, green: 0.96, blue: 0.97)
    }
}

extension UsagePresentationState {
    var accessibilityText: String { label }

    var symbol: String {
        switch self {
        case .loading: "arrow.triangle.2.circlepath"
        case .live: "checkmark.circle.fill"
        case .cached: "externaldrive.fill.badge.checkmark"
        case .estimated: "function"
        case .offline: "wifi.slash"
        case .needsLogin: "person.crop.circle.badge.exclamationmark"
        case .failed: "exclamationmark.triangle.fill"
        case .unavailable: "questionmark.folder"
        case .exhausted: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .loading: AppleUI.accent
        case .live: AppleUI.success
        case .cached: .secondary
        case .estimated: AppleUI.purple
        case .offline, .needsLogin, .failed: AppleUI.warning
        case .unavailable: .secondary
        case .exhausted: AppleUI.danger
        }
    }

    var progressColor: Color {
        switch self {
        case .estimated, .offline, .needsLogin, .failed: AppleUI.warning
        case .unavailable: .secondary
        case .exhausted: AppleUI.danger
        default: AppleUI.accent
        }
    }
}

struct PanelUtilityButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        let feedback = StableButtonPressFeedback(isPressed: configuration.isPressed)
        let shape = RoundedRectangle(cornerRadius: AppleUI.controlRadius, style: .continuous)
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
        HStack(spacing: AppleUI.spacingM) {
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

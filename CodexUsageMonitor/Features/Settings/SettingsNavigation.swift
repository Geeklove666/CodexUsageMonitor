import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, dataSources, notifications, privacy

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "常规"
        case .dataSources: "数据源"
        case .notifications: "通知"
        case .privacy: "隐私"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "调整应用的基础行为"
        case .dataSources: "选择额度读取方式并管理授权"
        case .notifications: "只在重要状态变化时打扰你"
        case .privacy: "管理保存在这台 Mac 上的数据"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .dataSources: "externaldrive.connected.to.line.below.fill"
        case .notifications: "bell.fill"
        case .privacy: "hand.raised.fill"
        }
    }
}

struct SettingsNavigationBar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SettingsSection.allCases) { section in
                Button { selection = section } label: {
                    Label(section.title, systemImage: section.symbol)
                        .font(.subheadline.weight(selection == section ? .semibold : .regular))
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .foregroundStyle(selection == section ? Color.primary : Color.secondary)
                        .background(
                            selection == section ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: AppleUI.iconRadius, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .liquidGlassSurface(cornerRadius: AppleUI.cardRadius)
    }
}

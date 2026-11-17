import SwiftUI

/// Themes change colour and tone only, never logic. One component set for all.
struct Theme {
    var primary: Color
    var primarySoft: Color
    var background: Color
    var surface: Color
    var textPrimary: Color
    var textSecondary: Color
    var success: Color
    var warning: Color
    var danger: Color
    var radius: CGFloat
    var titleFont: Font
    var greetingEmoji: String

    static func of(_ mode: ThemeMode) -> Theme {
        switch mode {
        case .kidsBoy:
            return Theme(primary: Color(hex: 0x2F80ED), primarySoft: Color(hex: 0xD6ECFF),
                         background: Color(hex: 0xEEF8FF), surface: .white,
                         textPrimary: Color(hex: 0x14324F), textSecondary: Color(hex: 0x5B7A99),
                         success: Color(hex: 0x1FB57A), warning: Color(hex: 0xF5A623), danger: Color(hex: 0xE5383B),
                         radius: 22, titleFont: .system(.title, design: .rounded).weight(.heavy), greetingEmoji: "👋")
        case .kidsGirl:
            return Theme(primary: Color(hex: 0xE5689B), primarySoft: Color(hex: 0xF3E6FF),
                         background: Color(hex: 0xFFF5F0), surface: .white,
                         textPrimary: Color(hex: 0x4A2C40), textSecondary: Color(hex: 0x8E6F84),
                         success: Color(hex: 0x2BB585), warning: Color(hex: 0xF5A623), danger: Color(hex: 0xE5383B),
                         radius: 22, titleFont: .system(.title, design: .rounded).weight(.heavy), greetingEmoji: "🌸")
        case .teen:
            return Theme(primary: Color(hex: 0x5B5FEF), primarySoft: Color(hex: 0xE7E8FD),
                         background: Color(hex: 0xF6F6F9), surface: .white,
                         textPrimary: Color(hex: 0x15161C), textSecondary: Color(hex: 0x6B6E80),
                         success: Color(hex: 0x1E9E6A), warning: Color(hex: 0xE09B1A), danger: Color(hex: 0xE5383B),
                         radius: 16, titleFont: .system(.title, design: .default).weight(.bold), greetingEmoji: "✌️")
        case .parent:
            return Theme(primary: Color(hex: 0x1F4E79), primarySoft: Color(hex: 0xE3ECF5),
                         background: Color(hex: 0xF5F7FA), surface: .white,
                         textPrimary: Color(hex: 0x111827), textSecondary: Color(hex: 0x6B7280),
                         success: Color(hex: 0x15803D), warning: Color(hex: 0xB45309), danger: Color(hex: 0xDC2626),
                         radius: 14, titleFont: .system(.title, design: .default).weight(.bold), greetingEmoji: "👋")
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Shared components

struct Card<Content: View>: View {
    let theme: Theme
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    let theme: Theme
    var busy = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) }
                else if let systemImage { Image(systemName: systemImage) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(theme.primary, in: RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
            .foregroundStyle(.white)
        }
        .disabled(busy)
    }
}

struct Avatar: View {
    let member: Member
    var size: CGFloat = 48
    var body: some View {
        let theme = Theme.of(member.themeMode)
        Text(member.avatarEmoji)
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(theme.primarySoft, in: Circle())
            .overlay(Circle().stroke(theme.primary.opacity(0.35), lineWidth: 2))
            .accessibilityLabel(member.displayName)
    }
}

struct EmptyState: View {
    let emoji: String
    let text: String
    let theme: Theme
    var body: some View {
        VStack(spacing: 8) {
            Text(emoji).font(.system(size: 44))
            Text(text).font(.headline).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

struct ErrorText: View {
    let message: String?
    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

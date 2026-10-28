import AppKit
import SwiftUI

/// Neutral greys with one muted violet accent; every color adapts to light and dark mode.
enum Theme {
    static let accent = dyn(0x6E56CF, 0x8B77E8)
    static let accentText = dyn(0x5746AF, 0xB1A4F5)
    static let accentSoft = dyn(0xF1EEFC, 0x221D3A)
    static let canvas = dyn(0xFFFFFF, 0x111113)
    static let sidebar = dyn(0xF8F8FA, 0x18181B)
    static let card = dyn(0xFAFAFB, 0x1A1A1D)
    static let border = dyn(0xE6E6EA, 0x2B2B30)
    static let text = dyn(0x1A1A1F, 0xEDEDEF)
    static let text2 = dyn(0x6F6E77, 0xA09FA6)
    static let text3 = dyn(0xA1A0AB, 0x5F5E66)
    static let success = dyn(0x2F9E68, 0x3DD68C)
    static let warning = dyn(0xD99A00, 0xF5C451)
    static let danger = dyn(0xD13A3A, 0xFF7070)

    static let nsAccent = NSColor(hex: 0x7A63DB)

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The same arrow the overlay draws, as a SwiftUI shape (17×26 design units).
struct CursorShape: Shape {
    func path(in r: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 22), (6, 17), (10, 26), (14, 24), (10, 15), (17, 15)]
        var p = Path()
        p.addLines(pts.map { CGPoint(x: r.minX + $0.0 / 17 * r.width, y: r.minY + $0.1 / 26 * r.height) })
        p.closeSubpath()
        return p
    }
}

/// App mark: a cursor with its translucent "ghost" trailing behind, on a violet tile.
struct AppMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(LinearGradient(colors: [Color(nsColor: NSColor(hex: 0x8D7AE6)), Color(nsColor: NSColor(hex: 0x5A44B5))],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 0.5)
            CursorShape().fill(.white.opacity(0.32))
                .frame(width: size * 0.3, height: size * 0.46)
                .offset(x: -size * 0.1, y: -size * 0.07)
            CursorShape().fill(.white)
                .frame(width: size * 0.3, height: size * 0.46)
                .offset(x: size * 0.07, y: size * 0.05)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(nsColor: NSColor(hex: 0x5A44B5)).opacity(0.3), radius: size * 0.12, y: size * 0.05)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var showsReturn = true
    func makeBody(configuration: Configuration) -> some View {
        PrimaryLabel(configuration: configuration, showsReturn: showsReturn)
    }

    private struct PrimaryLabel: View {
        let configuration: Configuration
        let showsReturn: Bool
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            HStack(spacing: 8) {
                configuration.label
                if showsReturn { Text("↵").opacity(0.6) }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)))
            .shadow(color: Theme.accent.opacity(enabled ? 0.28 : 0), radius: 6, y: 2)
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .contentShape(Rectangle())
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.canvas))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(Theme.text2)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// A physical-looking key, for shortcut hints.
struct Keycap: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 22)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.canvas))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.08), radius: 0, y: 1)
    }
}

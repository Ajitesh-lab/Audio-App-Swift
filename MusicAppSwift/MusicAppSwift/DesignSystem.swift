//
//  DesignSystem.swift
//  MusicAppSwift
//
//  Unified Design System - Single source of truth for all UI styling
//

import SwiftUI

// MARK: - Design System
struct DesignSystem {
    
    // MARK: - Spacing System
    struct Spacing {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16  // Default padding
        static let lg: CGFloat = 24  // Major groups
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }
    
    // MARK: - Typography Scale
    struct Typography {
        // Headings
        static let largeTitle = Font.system(size: 34, weight: .bold)
        static let title = Font.system(size: 28, weight: .bold)
        static let title2 = Font.system(size: 22, weight: .semibold)
        static let title3 = Font.system(size: 20, weight: .semibold)
        
        // Body
        static let body = Font.system(size: 17, weight: .regular)
        static let bodyMedium = Font.system(size: 17, weight: .medium)
        static let bodyBold = Font.system(size: 17, weight: .semibold)
        
        // Secondary
        static let callout = Font.system(size: 16, weight: .regular)
        static let subheadline = Font.system(size: 15, weight: .regular)
        static let footnote = Font.system(size: 13, weight: .regular)
        static let caption = Font.system(size: 12, weight: .regular)
    }
    
    // MARK: - Color Palette (Minimal Theme - 5 colors max)
    struct Colors {
        // Primary
        static let primary = Color.blue
        static let secondary = Color.gray
        
        // Backgrounds
        static let background = Color(UIColor.systemBackground)
        static let secondaryBackground = Color(UIColor.secondarySystemBackground)
        
        // Text
        static let primaryText = Color.black
        static let secondaryText = Color.black.opacity(0.6)
        static let tertiaryText = Color.black.opacity(0.4)
        
        // Accents
        static let accent = Color.blue
        static let destructive = Color.red
    }
    
    // MARK: - Corner Radius System
    struct CornerRadius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12  // Default
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }
    
    // MARK: - Shadows
    struct Shadow {
        static let small = (color: Color.black.opacity(0.04), radius: CGFloat(8), x: CGFloat(0), y: CGFloat(2))
        static let medium = (color: Color.black.opacity(0.06), radius: CGFloat(12), x: CGFloat(0), y: CGFloat(4))
        static let large = (color: Color.black.opacity(0.08), radius: CGFloat(20), x: CGFloat(0), y: CGFloat(8))
    }
    
    // MARK: - List Row Heights
    struct Heights {
        static let songRow: CGFloat = 68
        static let miniPlayer: CGFloat = 64
        static let playlistRow: CGFloat = 68
    }
    
    // MARK: - Animation Durations
    struct Animation {
        static let quick = 0.2
        static let normal = 0.3
        static let slow = 0.4
    }
}

// MARK: - Reusable View Modifiers
extension View {
    /// Apply standard card style with shadow
    func cardStyle() -> some View {
        self
            .background(DesignSystem.Colors.background)
            .cornerRadius(DesignSystem.CornerRadius.md)
            .shadow(
                color: DesignSystem.Shadow.medium.color,
                radius: DesignSystem.Shadow.medium.radius,
                x: DesignSystem.Shadow.medium.x,
                y: DesignSystem.Shadow.medium.y
            )
    }
    
    /// Apply button press animation
    func pressAnimation() -> some View {
        self
            .scaleEffect(1.0)
            .animation(.easeInOut(duration: DesignSystem.Animation.quick), value: UUID())
    }
}

// MARK: - Standard Backgrounds
extension View {
    func standardBackground() -> some View {
        self.background(DesignSystem.Colors.background.ignoresSafeArea())
    }
    
    func gradientBackground() -> some View {
        self.background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.86, green: 0.92, blue: 0.99),
                    Color(red: 0.93, green: 0.96, blue: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
}

// MARK: - GlassCard Component
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content
    
    init(cornerRadius: CGFloat = DesignSystem.CornerRadius.md, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }
    
    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(0.7))
                    .shadow(
                        color: DesignSystem.Shadow.medium.color,
                        radius: DesignSystem.Shadow.medium.radius,
                        x: DesignSystem.Shadow.medium.x,
                        y: DesignSystem.Shadow.medium.y
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Color Extensions
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

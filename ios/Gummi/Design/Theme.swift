import SwiftUI
import UIKit

/// The one place colors live (D-60). Views use these tokens, never raw colors.
/// Main colors follow the phone: white in light mode, black in dark. Eucalyptus is the accent.
nonisolated enum Theme {
    static let background = Color(uiColor: .systemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    /// Eucalyptus green, from the AccentColor asset (light and dark variants).
    static let accent = Color.accentColor
    /// Gummi's jelly body color, from the GummiJelly asset.
    static let jelly = UIColor(named: "GummiJelly") ?? .systemGreen

    /// CONTRACT section 9 mood colors. On the 3D puppet they tint the rim light; the body stays green for now.
    static func moodColor(_ mood: Mood) -> UIColor {
        switch mood {
        case .calm, .unknown: UIColor(red: 0.55, green: 0.72, blue: 0.96, alpha: 1)      // soft blue
        case .rising: UIColor(red: 1.00, green: 0.82, blue: 0.40, alpha: 1)    // warm yellow
        case .high: UIColor(red: 1.00, green: 0.58, blue: 0.26, alpha: 1)      // orange
        case .dipping: UIColor(red: 0.74, green: 0.66, blue: 0.95, alpha: 1)   // lavender
        case .low: UIColor(red: 0.72, green: 0.86, blue: 0.98, alpha: 1)       // pale blue
        case .proud: UIColor(red: 1.00, green: 0.80, blue: 0.30, alpha: 1)     // gold
        case .happy: UIColor(red: 0.50, green: 0.86, blue: 0.52, alpha: 1)     // green
        case .sleepy: UIColor(red: 0.50, green: 0.52, blue: 0.64, alpha: 1)    // dim
        case .thinking: UIColor(red: 0.86, green: 0.88, blue: 0.95, alpha: 1)
        }
    }
}

extension View {
    /// Liquid Glass on iOS 26, a system material on iOS 18 (D-60).
    @ViewBuilder
    func glassSurface<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}

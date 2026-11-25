import SwiftUI

enum Theme {
    static func color(for category: String) -> Color {
        switch category {
        case "Travail": return Color(red: 0.31, green: 0.49, blue: 1.0)
        case "Repas": return Color(red: 0.96, green: 0.65, blue: 0.14)
        case "Sommeil": return Color(red: 0.49, green: 0.36, blue: 1.0)
        case "Santé": return Color(red: 0.90, green: 0.28, blue: 0.30)
        case "Loisirs": return Color(red: 0.19, green: 0.64, blue: 0.42)
        case "Hygiène": return Color(red: 0.07, green: 0.65, blue: 0.72)
        case "Déplacement": return Color(red: 0.55, green: 0.40, blue: 0.30)
        default: return Color(white: 0.55)
        }
    }
}

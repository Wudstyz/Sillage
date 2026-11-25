import SwiftUI

// Palette « Sillage » : thème clair, papier chaud, corail → rose (les couleurs de l'icône).
extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Theme {
    static let background = Color(hex: 0xF7F3EE)   // fond général (papier)
    static let panel = Color(hex: 0xFBF8F4)        // barre latérale
    static let card = Color.white
    static let ink = Color(hex: 0x2B2230)          // texte
    static let muted = Color(hex: 0x877C8C)        // texte secondaire
    static let line = Color(hex: 0x2B2230, opacity: 0.09)

    static let coral = Color(hex: 0xFF8A55)
    static let accent = Color(hex: 0xE8455F)       // rose-corail de l'icône
    static let accentDeep = Color(hex: 0xC02F66)
    static let danger = Color(hex: 0xD6403A)
    static let warning = Color(hex: 0xD9822B)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [coral, accent], startPoint: .top, endPoint: .bottom)
    }

    /// Couleur d'une catégorie (fonds, pastilles, barres).
    static func color(for category: String) -> Color {
        switch category {
        case "Travail": return Color(hex: 0x5B7BF5)
        case "Repas": return Color(hex: 0xF0A030)
        case "Sommeil": return Color(hex: 0x8467EE)
        case "Santé": return Color(hex: 0xE2506A)
        case "Loisirs": return Color(hex: 0x2FAE78)
        case "Hygiène": return Color(hex: 0x24AFC2)
        case "Déplacement": return Color(hex: 0x9C7A5E)
        case "Calendrier": return Color(hex: 0x5F7A8C)        // ardoise : rendez-vous venus d'un calendrier externe
        default: return Color(hex: 0x8D8A96)
        }
    }

    /// Variante foncée de la couleur d'une catégorie, lisible en texte sur un fond teinté.
    static func ink(for category: String) -> Color {
        switch category {
        case "Travail": return Color(hex: 0x2F47B8)
        case "Repas": return Color(hex: 0x9A5E0A)
        case "Sommeil": return Color(hex: 0x4B33B0)
        case "Santé": return Color(hex: 0xA42440)
        case "Loisirs": return Color(hex: 0x14754A)
        case "Hygiène": return Color(hex: 0x0E7585)
        case "Déplacement": return Color(hex: 0x5E4430)
        case "Calendrier": return Color(hex: 0x38505F)
        default: return Color(hex: 0x55525E)
        }
    }

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// « 1:23 » : durée en heures et minutes, pour les chronomètres.
func clockString(_ interval: TimeInterval) -> String {
    let m = max(0, Int(interval / 60))
    return String(format: "%d:%02d", m / 60, m % 60)
}

// MARK: - Cartes et boutons

extension View {
    /// Carte blanche : coins arrondis, contour discret, ombre légère.
    func card(padding: CGFloat = 14, radius: CGFloat = 14) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.line, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.035), radius: 8, y: 2)
    }

    /// Petit titre de section en capitales espacées.
    func sectionLabel() -> some View {
        self.font(Theme.rounded(11, .bold)).tracking(1.1).textCase(.uppercase).foregroundStyle(Theme.muted)
    }
}

struct AccentButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.rounded(compact ? 12 : 14, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 10 : 14).padding(.vertical, compact ? 5 : 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accentGradient))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 1))
            .shadow(color: Theme.accent.opacity(enabled ? 0.30 : 0), radius: configuration.isPressed ? 2 : 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(enabled ? 1 : 0.4)
    }
}

/// Bouton « pastille » teinté par la couleur d'une catégorie (raccourcis d'activités).
struct ChipButtonStyle: ButtonStyle {
    let category: String
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.rounded(13, .semibold))
            .foregroundStyle(Theme.ink(for: category))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.color(for: category).opacity(configuration.isPressed ? 0.24 : 0.13)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Bouton rond d'arrêt (■) d'une tâche en cours.
struct StopButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Theme.danger))
            .shadow(color: Theme.danger.opacity(0.35), radius: configuration.isPressed ? 1 : 4, y: 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

/// Point qui pulse : « ça tourne ». Seule l'opacité est animée, pas la position.
struct PulsingDot: View {
    var color: Color = Theme.accent
    @State private var dim = false
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .opacity(dim ? 0.3 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

/// Apparence d'un bloc de la frise : plein et lumineux pour le réel, teinté avec liseré pour le prévu.
struct EntryBlockStyle: ViewModifier {
    let category: String
    let planned: Bool
    var radius: CGFloat = 10

    func body(content: Content) -> some View {
        let color = Theme.color(for: category)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(
                shape.fill(planned
                           ? AnyShapeStyle(color.opacity(0.13))
                           : AnyShapeStyle(LinearGradient(colors: [color, color.opacity(0.84)], startPoint: .top, endPoint: .bottom)))
            )
            .overlay(alignment: .leading) {
                if planned { Rectangle().fill(color).frame(width: 4) }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(planned ? color.opacity(0.5) : Color.white.opacity(0.22),
                                        style: StrokeStyle(lineWidth: 1, dash: planned ? [4, 3] : [])))
            .shadow(color: planned ? .clear : color.opacity(0.28), radius: 5, y: 2)
    }
}

extension View {
    func entryBlock(category: String, planned: Bool, radius: CGFloat = 10) -> some View {
        modifier(EntryBlockStyle(category: category, planned: planned, radius: radius))
    }
}

/// Petite carte « libellé / valeur » (chiffres clés).
struct StatCard: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).sectionLabel().lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(Theme.rounded(22, .bold)).foregroundStyle(Theme.ink).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }
}

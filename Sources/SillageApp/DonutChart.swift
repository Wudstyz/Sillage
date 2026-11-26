import SwiftUI

struct DonutSlice: Identifiable {
    let id: String
    let label: String
    let value: Double
    let color: Color
}

/// Camembert (en anneau) dessiné à la main, compatible macOS 13 : le titre du centre résume le total.
struct DonutChart: View {
    let slices: [DonutSlice]
    let centerTitle: String
    let centerSubtitle: String
    var lineWidth: CGFloat = 38

    private struct Arc: Identifiable { let id: String; let from: CGFloat; let to: CGFloat; let color: Color }

    private var arcs: [Arc] {
        let total = slices.reduce(0) { $0 + $1.value }
        guard total > 0 else { return [] }
        let gap: CGFloat = slices.count > 1 ? 0.005 : 0          // un mince espace entre les parts
        var cursor: CGFloat = 0
        return slices.map { s in
            let fraction = CGFloat(s.value / total)
            defer { cursor += fraction }
            return Arc(id: s.id, from: cursor + gap / 2, to: max(cursor + gap / 2 + 0.002, cursor + fraction - gap / 2), color: s.color)
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.ink.opacity(0.06), lineWidth: lineWidth)
            ForEach(arcs) { a in
                Circle().trim(from: a.from, to: a.to)
                    .stroke(a.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 2) {
                Text(centerTitle).font(Theme.rounded(28, .bold)).foregroundStyle(Theme.ink).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(centerSubtitle).font(Theme.rounded(12, .medium)).foregroundStyle(Theme.muted)
            }
            .padding(lineWidth + 6)
        }
        .padding(lineWidth / 2)
        .aspectRatio(1, contentMode: .fit)
    }
}

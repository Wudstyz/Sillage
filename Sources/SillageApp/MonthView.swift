import SwiftUI
import SillageCore

/// Vue mois : une case par jour avec les rendez-vous prévus et une barre de couleurs du temps réellement passé.
struct MonthView: View {
    @EnvironmentObject var model: AppModel
    /// Durée représentée par une barre pleine (une journée « éveillée »).
    private let fullBar: TimeInterval = 16 * 3600

    var body: some View {
        let grid = CalendarGrid.month(containing: model.day)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(grid[0], id: \.self) { d in
                    Text(d.formatted(.dateTime.weekday(.abbreviated)).capitalized)
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
            Divider()
            GeometryReader { geo in
                let rowH = geo.size.height / CGFloat(grid.count)
                VStack(spacing: 0) {
                    ForEach(grid.indices, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(grid[r], id: \.self) { day in cell(day, height: rowH) }
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func cell(_ day: Date, height: CGFloat) -> some View {
        let cal = Calendar.current
        let inMonth = CalendarGrid.isSameMonth(day, model.day)
        let today = cal.isDateInToday(day)
        let planned = DayLogic.entries(model.entries, kind: .planned, on: day, now: model.now)
        let totals = DayLogic.totals(model.entries, on: day, now: model.now)
        let tracked = totals.reduce(0) { $0 + $1.duration }
        let maxChips = max(0, Int((height - 64) / 16))
        let shown = Array(planned.prefix(maxChips))

        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(day.formatted(.dateTime.day()))
                    .font(.callout.weight(today ? .bold : .regular))
                    .foregroundStyle(today ? .white : (inMonth ? .primary : .secondary))
                    .frame(minWidth: 24, minHeight: 24)
                    .background(Circle().fill(today ? Color.red : Color.clear))
                Spacer()
                if tracked > 0 {
                    Text(DayLogic.formatDuration(tracked)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            ForEach(shown) { e in
                HStack(spacing: 4) {
                    Circle().fill(Theme.color(for: e.category)).frame(width: 6, height: 6)
                    Text("\(e.start.formatted(date: .omitted, time: .shortened)) \(e.title)")
                        .font(.caption2).lineLimit(1)
                }
            }
            if planned.count > shown.count {
                Text("+ \(planned.count - shown.count) autre\(planned.count - shown.count > 1 ? "s" : "")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            categoryBar(totals, tracked: tracked)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(inMonth ? Color.clear : Color.secondary.opacity(0.06))
        .overlay(Rectangle().strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { model.open(day: day) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).day().month(.wide))), \(planned.count) rendez-vous, \(DayLogic.formatDuration(tracked)) enregistrés")
        .accessibilityAddTraits(.isButton)
        .help("Ouvrir ce jour")
    }

    /// Le temps réel de la journée, réparti par catégorie : un coup d'œil sur « ce que j'ai fait ».
    private func categoryBar(_ totals: [(category: String, duration: TimeInterval)], tracked: TimeInterval) -> some View {
        GeometryReader { geo in
            let width = geo.size.width * min(1, tracked / fullBar)
            HStack(spacing: 0) {
                ForEach(totals, id: \.category) { t in
                    Theme.color(for: t.category).frame(width: tracked > 0 ? width * t.duration / tracked : 0)
                }
                Spacer(minLength: 0)
            }
            .clipShape(Capsule())
        }
        .frame(height: 5)
    }
}

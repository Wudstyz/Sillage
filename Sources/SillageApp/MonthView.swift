import SwiftUI
import SillageCore

/// Vue mois : une carte par jour avec les rendez-vous prévus et une barre de couleurs du temps réellement passé.
struct MonthView: View {
    @EnvironmentObject var model: AppModel
    /// Durée représentée par une barre pleine (une journée « éveillée »).
    private let fullBar: TimeInterval = 16 * 3600
    private let gap: CGFloat = 6

    var body: some View {
        let grid = CalendarGrid.month(containing: model.day)
        VStack(spacing: 0) {
            HStack(spacing: gap) {
                ForEach(grid[0], id: \.self) { d in
                    Text(d.formatted(.dateTime.weekday(.abbreviated)))
                        .font(Theme.rounded(11, .bold)).tracking(1).textCase(.uppercase).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            GeometryReader { geo in
                let rowH = (geo.size.height - gap * CGFloat(grid.count - 1) - 12) / CGFloat(grid.count)
                VStack(spacing: gap) {
                    ForEach(grid.indices, id: \.self) { r in
                        HStack(spacing: gap) {
                            ForEach(grid[r], id: \.self) { day in cell(day, height: rowH) }
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
        .background(Theme.background)
    }

    private func cell(_ day: Date, height: CGFloat) -> some View {
        let cal = Calendar.current
        let inMonth = CalendarGrid.isSameMonth(day, model.day)
        let today = cal.isDateInToday(day)
        let planned = DayLogic.entries(model.entries, kind: .planned, on: day, now: model.now)
        let totals = DayLogic.totals(model.entries, on: day, now: model.now)
        let tracked = totals.reduce(0) { $0 + $1.duration }
        // Place disponible pour les pastilles (24 pt chacune) ; si tout ne tient pas, on garde la place de « + N autres ».
        let available = height - 60
        let fitAll = Int(available / 24)
        let maxChips = planned.count <= fitAll ? planned.count : max(0, Int((available - 16) / 24))
        let shown = Array(planned.prefix(maxChips))
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(day.formatted(.dateTime.day()))
                    .font(Theme.rounded(14, .bold))
                    .foregroundStyle(today ? .white : (inMonth ? Theme.ink : Theme.muted))
                    .frame(minWidth: 26, minHeight: 26)
                    .background(Circle().fill(today ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.clear)))
                Spacer()
                if tracked > 0 {
                    Text(DayLogic.formatDuration(tracked)).font(Theme.rounded(11, .semibold)).monospacedDigit().foregroundStyle(Theme.muted)
                }
            }
            ForEach(shown) { e in
                HStack(spacing: 5) {
                    Text(e.start.formatted(date: .omitted, time: .shortened)).monospacedDigit().opacity(0.75)
                    Text(e.title).lineLimit(1)
                }
                .font(Theme.rounded(11, .semibold))
                .foregroundStyle(Theme.ink(for: e.category))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.color(for: e.category).opacity(0.14)))
            }
            if planned.count > shown.count {
                Text("+ \(planned.count - shown.count) autre\(planned.count - shown.count > 1 ? "s" : "")")
                    .font(Theme.rounded(11, .medium)).foregroundStyle(Theme.muted).padding(.leading, 4)
            }
            Spacer(minLength: 0)
            categoryBar(totals, tracked: tracked)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(shape.fill(inMonth ? Theme.card : Theme.card.opacity(0.4)))
        .overlay(shape.stroke(today ? Theme.accent : Theme.line, lineWidth: today ? 2 : 1))
        .shadow(color: Color.black.opacity(inMonth ? 0.03 : 0), radius: 5, y: 1)
        .opacity(inMonth ? 1 : 0.7)
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
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.06))
                HStack(spacing: 0) {
                    ForEach(totals, id: \.category) { t in
                        Theme.color(for: t.category)
                            .frame(width: tracked > 0 ? geo.size.width * min(1, tracked / fullBar) * t.duration / tracked : 0)
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 6)
    }
}

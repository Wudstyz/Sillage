import SwiftUI
import SillageCore

/// Vue semaine : sept colonnes de jours sur une grille horaire. Prévu (liseré, teinté) et réel (plein) se côtoient.
struct WeekView: View {
    @EnvironmentObject var model: AppModel
    private let hourHeight: CGFloat = 48
    private let gutter: CGFloat = 50

    var body: some View {
        let days = CalendarGrid.week(containing: model.day)
        VStack(spacing: 0) {
            header(days)
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 0) {
                            Spacer().frame(width: gutter)
                            ForEach(days, id: \.self) { day in dayBackground(day) }
                        }
                        grid
                        HStack(spacing: 0) {
                            Spacer().frame(width: gutter)
                            ForEach(days, id: \.self) { day in dayColumn(day) }
                        }
                    }
                    .frame(height: hourHeight * 24)
                    .padding(.vertical, 10)
                }
                .onAppear { scroll(proxy) }
                .onChange(of: model.day) { _ in scroll(proxy) }
            }
        }
        .background(Theme.background)
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        var h = max(0, Calendar.current.component(.hour, from: Date()) - 2)
        if let v = ProcessInfo.processInfo.environment["SILLAGE_HOUR"], let forced = Int(v) { h = forced }
        DispatchQueue.main.async { proxy.scrollTo("wh\(h)", anchor: .top) }
    }

    private func header(_ days: [Date]) -> some View {
        HStack(spacing: 0) {
            Spacer().frame(width: gutter)
            ForEach(days, id: \.self) { day in
                let today = Calendar.current.isDateInToday(day)
                Button { model.open(day: day) } label: {
                    VStack(spacing: 3) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(Theme.rounded(11, .bold)).tracking(1).textCase(.uppercase)
                            .foregroundStyle(today ? Theme.accent : Theme.muted)
                        Text(day.formatted(.dateTime.day()))
                            .font(Theme.rounded(20, .bold))
                            .foregroundStyle(today ? .white : Theme.ink)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(today ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.clear)))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Ouvrir ce jour")
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                HStack(alignment: .top, spacing: 6) {
                    Text(String(format: "%02d:00", h))
                        .font(Theme.rounded(10, .medium)).monospacedDigit().foregroundStyle(Theme.muted)
                        .frame(width: gutter - 6, alignment: .trailing)
                        .offset(y: -6)
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
                .id("wh\(h)")
            }
        }
    }

    /// Fond d'une colonne : le jour courant est teinté, le week-end un peu grisé.
    private func dayBackground(_ day: Date) -> some View {
        let cal = Calendar.current
        let weekend = cal.isDateInWeekend(day)
        let fill: Color = cal.isDateInToday(day) ? Theme.accent.opacity(0.07) : (weekend ? Theme.ink.opacity(0.035) : .clear)
        return Rectangle().fill(fill)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
            .frame(maxWidth: .infinity).frame(height: hourHeight * 24)
    }

    private func dayColumn(_ day: Date) -> some View {
        let dayStart = Calendar.current.startOfDay(for: day)
        let list = DayLogic.entries(model.entries, on: day, now: model.now)
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(DayLogic.lanes(list, now: model.now), id: \.entry.id) { p in
                    block(p, dayStart: dayStart, width: geo.size.width)
                }
                if Calendar.current.isDateInToday(day) {
                    let y = CGFloat(model.now.timeIntervalSince(dayStart) / 3600) * hourHeight
                    HStack(spacing: 0) {
                        Circle().fill(Theme.accent).frame(width: 8, height: 8)
                        Rectangle().fill(Theme.accent).frame(height: 2)
                    }
                    .offset(x: -4, y: y - 4).allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: hourHeight * 24)
    }

    private func block(_ p: PlacedEntry, dayStart: Date, width: CGFloat) -> some View {
        let dayEnd = dayStart.addingTimeInterval(86400)
        let e = p.entry
        let s = max(e.start, dayStart)
        let f = min(e.effectiveEnd(now: model.now), dayEnd)
        let y = CGFloat(s.timeIntervalSince(dayStart) / 3600) * hourHeight
        let h = max(18, CGFloat(f.timeIntervalSince(s) / 3600) * hourHeight - 2)
        let w = (width - 4) / CGFloat(p.lanes)
        let planned = e.kind == .planned

        return Text(e.title)
            .font(Theme.rounded(11, .semibold))
            .lineLimit(p.lanes == 1 && h > 36 ? 2 : 1)        // jamais de coupure au milieu d'un mot dans une voie étroite
            .minimumScaleFactor(0.75).truncationMode(.tail)
            .foregroundStyle(planned ? Theme.ink(for: e.category) : .white)
            .padding(.leading, planned ? 9 : 6).padding(.trailing, 4).padding(.vertical, 3)
            .frame(width: w - 3, height: h, alignment: .topLeading)
            .entryBlock(category: e.category, planned: planned, radius: 7)
            .contentShape(Rectangle())
            .onTapGesture { model.editor = AppModel.EditorTarget(entry: e, isNew: false) }
            .contextMenu {
                if planned && !model.isArrived(e) {
                    Button { model.arrive(at: e) } label: { Label("J'y suis", systemImage: "figure.walk.arrival") }
                }
                if e.isRunning {
                    Button { model.stop(e.id) } label: { Label("Terminer maintenant", systemImage: "stop.fill") }
                }
                Button { model.editor = AppModel.EditorTarget(entry: e, isNew: false) } label: { Label("Modifier…", systemImage: "pencil") }
                Button { model.open(day: dayStart) } label: { Label("Ouvrir ce jour", systemImage: "calendar") }
                Divider()
                Button(role: .destructive) { model.delete(e.id) } label: { Label("Supprimer", systemImage: "trash") }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(planned ? "Prévu" : "Réel") : \(e.title), \(e.start.formatted(date: .omitted, time: .shortened))")
            .accessibilityAddTraits(.isButton)
            .offset(x: CGFloat(p.lane) * w + 2, y: y + 1)
            .help("\(e.title) · \(e.category)")
    }
}

import SwiftUI
import SillageCore

/// Vue semaine : sept colonnes de jours sur une grille horaire. Prévu (pointillés) et réel (plein) se côtoient.
struct WeekView: View {
    @EnvironmentObject var model: AppModel
    private let hourHeight: CGFloat = 48
    private let gutter: CGFloat = 46

    var body: some View {
        let days = CalendarGrid.week(containing: model.day)
        VStack(spacing: 0) {
            header(days)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        grid
                        HStack(spacing: 0) {
                            Spacer().frame(width: gutter)
                            ForEach(days, id: \.self) { day in dayColumn(day) }
                        }
                    }
                    .frame(height: hourHeight * 24)
                    .padding(.top, 10)
                }
                .onAppear { scroll(proxy) }
                .onChange(of: model.day) { _ in scroll(proxy) }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
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
                    VStack(spacing: 2) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)).capitalized)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(day.formatted(.dateTime.day()))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(today ? .white : .primary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(today ? Color.red : Color.clear))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Ouvrir ce jour")
            }
        }
        .padding(.vertical, 6)
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                HStack(alignment: .top, spacing: 6) {
                    Text(String(format: "%02d:00", h))
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: gutter - 6, alignment: .trailing)
                        .offset(y: -6)
                    Rectangle().fill(Color.secondary.opacity(0.18)).frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
                .id("wh\(h)")
            }
        }
    }

    private func dayColumn(_ day: Date) -> some View {
        let dayStart = Calendar.current.startOfDay(for: day)
        let list = DayLogic.entries(model.entries, on: day, now: model.now)
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.secondary.opacity(0.15)).frame(width: 1)      // séparateur de jour
                ForEach(DayLogic.lanes(list, now: model.now), id: \.entry.id) { p in
                    block(p, dayStart: dayStart, width: geo.size.width)
                }
                if Calendar.current.isDateInToday(day) {
                    let y = CGFloat(model.now.timeIntervalSince(dayStart) / 3600) * hourHeight
                    Rectangle().fill(.red).frame(height: 1.5).offset(y: y).allowsHitTesting(false)
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
        let h = max(16, CGFloat(f.timeIntervalSince(s) / 3600) * hourHeight - 1)
        let w = (width - 3) / CGFloat(p.lanes)
        let color = Theme.color(for: e.category)
        let planned = e.kind == .planned

        return Text(e.title)
            .font(.caption2.weight(.semibold)).lineLimit(h > 34 ? 2 : 1)
            .foregroundStyle(planned ? color : .white)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .frame(width: w - 2, height: h, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 5).fill(planned ? color.opacity(0.15) : color))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .strokeBorder(color, style: StrokeStyle(lineWidth: planned ? 1 : 0, dash: planned ? [4, 2] : [])))
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
            .offset(x: CGFloat(p.lane) * w + 2, y: y)
            .help("\(e.title) · \(e.category)")
    }
}

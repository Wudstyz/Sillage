import SwiftUI
import SillageCore

/// Frise de la journée : colonne « Prévu » (rendez-vous) et colonne « Réel » (ce qui s'est passé).
struct TimelineView: View {
    @EnvironmentObject var model: AppModel
    private let hourHeight: CGFloat = 60
    private let gutter: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            headers
            Divider()
            scrollArea
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var scrollArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    grid
                    GeometryReader { geo in
                        let colWidth = (geo.size.width - gutter - 16) / 2
                        column(.planned, x: gutter, width: colWidth)
                        column(.actual, x: gutter + colWidth + 8, width: colWidth)
                        if model.isToday { nowLine(width: geo.size.width) }
                    }
                }
                .frame(height: hourHeight * 24)
                .padding(.top, 10)
            }
            .onAppear { scroll(proxy) }
            .onChange(of: model.day) { _ in scroll(proxy) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        // SILLAGE_HOUR : heure affichée en haut (captures d'écran de la documentation).
        if let v = ProcessInfo.processInfo.environment["SILLAGE_HOUR"], let h = Int(v) {
            DispatchQueue.main.async { proxy.scrollTo("h\(h)", anchor: .top) }
            return
        }
        let h = model.isToday ? max(0, Calendar.current.component(.hour, from: Date()) - 2) : 7
        DispatchQueue.main.async { proxy.scrollTo("h\(h)", anchor: .top) }
    }

    private var headers: some View {
        GeometryReader { geo in
            let colWidth = (geo.size.width - gutter - 16) / 2
            HStack(spacing: 8) {
                Spacer().frame(width: gutter - 8)
                Text("Prévu").frame(width: colWidth)
                Text("Réel").frame(width: colWidth)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(height: 28)
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
                .id("h\(h)")
            }
        }
    }

    private func column(_ kind: EntryKind, x: CGFloat, width: CGFloat) -> some View {
        let list = DayLogic.entries(model.entries, kind: kind, on: model.day, now: model.now)
        return ZStack(alignment: .topLeading) {
            ForEach(DayLogic.lanes(list, now: model.now), id: \.entry.id) { placed in
                block(placed, width: width)
            }
        }
        .frame(width: width, height: hourHeight * 24, alignment: .topLeading)
        .offset(x: x)
    }

    private func block(_ p: PlacedEntry, width: CGFloat) -> some View {
        let dayStart = Calendar.current.startOfDay(for: model.day)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let e = p.entry
        let s = max(e.start, dayStart)
        let f = min(e.effectiveEnd(now: model.now), dayEnd)
        let y = CGFloat(s.timeIntervalSince(dayStart) / 3600) * hourHeight
        let h = max(22, CGFloat(f.timeIntervalSince(s) / 3600) * hourHeight - 2)
        let w = width / CGFloat(p.lanes)
        let color = Theme.color(for: e.category)
        let planned = e.kind == .planned

        return VStack(alignment: .leading, spacing: 1) {
            Text(e.title).font(.callout.weight(.semibold)).lineLimit(1)
            if h > 38 {
                Text(detail(e)).font(.caption).opacity(0.85).lineLimit(1)
            }
        }
        .foregroundStyle(planned ? color : .white)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .frame(width: w - 3, height: h, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(planned ? color.opacity(0.15) : color))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(color, style: StrokeStyle(lineWidth: planned ? 1.5 : 0, dash: planned ? [5, 3] : [])))
        .overlay(alignment: .topTrailing) {
            if e.isRunning {
                Image(systemName: "play.circle.fill").padding(4).foregroundStyle(.white.opacity(0.9))
            } else if planned && model.isArrived(e) {
                Image(systemName: "checkmark.circle.fill").padding(4).foregroundStyle(color)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            if planned && !model.isArrived(e) {
                Button { model.arrive(at: e) } label: { Label("J'y suis", systemImage: "figure.walk.arrival") }
            }
            if e.isRunning {
                Button { model.stop(e.id) } label: { Label("Terminer maintenant", systemImage: "stop.fill") }
            }
            Button { model.editor = AppModel.EditorTarget(entry: e, isNew: false) } label: {
                Label("Modifier…", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) { model.delete(e.id) } label: { Label("Supprimer", systemImage: "trash") }
        }
        .onTapGesture { model.editor = AppModel.EditorTarget(entry: e, isNew: false) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(planned ? "Prévu" : "Réel") : \(e.title), \(detail(e))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.editor = AppModel.EditorTarget(entry: e, isNew: false) }
        .accessibilityAction(named: "J'y suis") { if planned { model.arrive(at: e) } }
        .offset(x: CGFloat(p.lane) * w, y: y)
        .help("\(e.title) · \(detail(e)) · \(e.category)")
    }

    /// Plage horaire, plus la ponctualité si l'entrée vient d'un « J'y suis ».
    private func detail(_ e: Entry) -> String {
        guard let p = model.punctuality(of: e) else { return range(e) }
        return "\(range(e)) · \(p)"
    }

    private func range(_ e: Entry) -> String {
        let a = e.start.formatted(date: .omitted, time: .shortened)
        guard let end = e.end else { return "\(a) → en cours" }
        return "\(a) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    private func nowLine(width: CGFloat) -> some View {
        let dayStart = Calendar.current.startOfDay(for: model.day)
        let y = CGFloat(model.now.timeIntervalSince(dayStart) / 3600) * hourHeight
        return HStack(spacing: 0) {
            Spacer().frame(width: gutter - 4)
            Circle().fill(.red).frame(width: 8, height: 8)
            Rectangle().fill(.red).frame(height: 1.5)
        }
        .offset(y: y - 4)
        .allowsHitTesting(false)
    }
}

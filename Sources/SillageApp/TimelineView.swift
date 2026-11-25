import SwiftUI
import SillageCore

/// Frise de la journée : voie « Prévu » (rendez-vous) et voie « Réel » (ce qui s'est passé).
struct TimelineView: View {
    @EnvironmentObject var model: AppModel
    private let hourHeight: CGFloat = 60
    private let gutter: CGFloat = 56
    /// Gestes en cours (avant relâchement) : décalage en secondes, pour un aperçu fidèle au résultat final.
    @State private var liveMove: [UUID: TimeInterval] = [:]
    @State private var liveResize: [UUID: TimeInterval] = [:]
    @State private var creating: (kind: EntryKind, y0: CGFloat, y1: CGFloat)?

    private var dayStart: Date { Calendar.current.startOfDay(for: model.day) }
    private var dayBounds: DateInterval { DateInterval(start: dayStart, duration: 86400) }
    private func seconds(_ points: CGFloat) -> TimeInterval { TimeInterval(points / hourHeight) * 3600 }
    private func date(atY y: CGFloat) -> Date { dayStart.addingTimeInterval(seconds(min(max(y, 0), hourHeight * 24))) }

    var body: some View {
        VStack(spacing: 0) {
            headers
            scrollArea
        }
        .background(Theme.background)
    }

    private var scrollArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    GeometryReader { geo in
                        let colWidth = (geo.size.width - gutter - 16) / 2
                        laneBackground(.planned, x: gutter, width: colWidth)
                        laneBackground(.actual, x: gutter + colWidth + 8, width: colWidth)
                    }
                    grid
                    GeometryReader { geo in
                        let colWidth = (geo.size.width - gutter - 16) / 2
                        column(.planned, x: gutter, width: colWidth)
                        column(.actual, x: gutter + colWidth + 8, width: colWidth)
                        if model.isToday { nowLine(width: geo.size.width) }
                    }
                }
                .frame(height: hourHeight * 24)
                .padding(.vertical, 10)
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

    // MARK: En-têtes, fond et grille

    private var headers: some View {
        GeometryReader { geo in
            let colWidth = (geo.size.width - gutter - 16) / 2
            HStack(spacing: 8) {
                Spacer().frame(width: gutter - 8)
                laneTitle("Prévu", "calendar", color: Theme.muted).frame(width: colWidth)
                laneTitle("Réel", "checkmark.circle.fill", color: Theme.accent).frame(width: colWidth)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 40)
        .background(Theme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func laneTitle(_ text: String, _ symbol: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
            Text(text).tracking(1.2).textCase(.uppercase)
        }
        .font(Theme.rounded(11, .bold)).foregroundStyle(color)
    }

    private func laneBackground(_ kind: EntryKind, x: CGFloat, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(kind == .actual ? Color.white : Theme.ink.opacity(0.035))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line, lineWidth: kind == .actual ? 1 : 0))
            .frame(width: width, height: hourHeight * 24)
            .offset(x: x)
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                HStack(alignment: .top, spacing: 8) {
                    Text(String(format: "%02d:00", h))
                        .font(Theme.rounded(11, .medium)).monospacedDigit().foregroundStyle(Theme.muted)
                        .frame(width: gutter - 8, alignment: .trailing)
                        .offset(y: -7)
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
                .id("h\(h)")
            }
        }
    }

    // MARK: Colonnes et blocs

    private func column(_ kind: EntryKind, x: CGFloat, width: CGFloat) -> some View {
        let list = DayLogic.entries(model.shownEntries, kind: kind, on: model.day, now: model.now)
        return ZStack(alignment: .topLeading) {
            // Glisser dans le vide pour créer une plage.
            Rectangle().fill(Color.clear).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 6)
                    .onChanged { v in creating = (kind, v.startLocation.y, v.location.y) }
                    .onEnded { v in
                        creating = nil
                        let r = Manipulation.range(date(atY: v.startLocation.y), date(atY: v.location.y))
                        model.editor = AppModel.EditorTarget(
                            entry: Entry(title: "", category: "Autre", kind: kind, start: r.start, end: r.end), isNew: true)
                    })
            ForEach(DayLogic.lanes(list, now: model.now), id: \.entry.id) { placed in
                block(placed, width: width)
            }
            if let c = creating, c.kind == kind { ghost(c, width: width) }
        }
        .frame(width: width, height: hourHeight * 24, alignment: .topLeading)
        .offset(x: x)
    }

    private func block(_ p: PlacedEntry, width: CGFloat) -> some View {
        let dayEnd = dayStart.addingTimeInterval(86400)
        var e = p.entry
        if let d = liveMove[e.id] { e = Manipulation.moved(e, by: d, within: dayBounds) }
        if let d = liveResize[e.id] { e = Manipulation.resized(e, by: d, within: dayBounds) }
        let original = p.entry
        let s = max(e.start, dayStart)
        let f = min(e.effectiveEnd(now: model.now), dayEnd)
        let y = CGFloat(s.timeIntervalSince(dayStart) / 3600) * hourHeight
        let h = max(24, CGFloat(f.timeIntervalSince(s) / 3600) * hourHeight - 3)
        let w = width / CGFloat(p.lanes)
        let planned = e.kind == .planned
        let ink: Color = planned ? Theme.ink(for: e.category) : .white
        let live = liveMove[e.id] != nil || liveResize[e.id] != nil

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if e.isExternal { Image(systemName: "calendar").font(.system(size: 10, weight: .bold)) }
                Text(e.title).font(Theme.rounded(13, .semibold)).lineLimit(1)
            }
            if h > 40 {
                Text(detail(e)).font(Theme.rounded(11, .medium)).opacity(0.85).lineLimit(1)
            }
        }
        .foregroundStyle(ink)
        .padding(.leading, planned ? 12 : 9).padding(.trailing, 8).padding(.vertical, 5)
        .frame(width: w - 6, height: h, alignment: .topLeading)
        .entryBlock(category: e.category, planned: planned)
        .overlay(alignment: .topTrailing) {
            if e.isRunning {
                HStack(spacing: 4) {
                    PulsingDot(color: .white)
                    Text("en cours").font(Theme.rounded(10, .bold)).foregroundStyle(.white)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.18)))
                .padding(5)
            } else if planned && model.isArrived(e) {
                Image(systemName: "checkmark.circle.fill").padding(5).foregroundStyle(Theme.color(for: e.category))
            }
        }
        .scaleEffect(live ? 1.012 : 1)
        .shadow(color: live ? Color.black.opacity(0.18) : .clear, radius: 8, y: 3)
        .contentShape(Rectangle())
        .contextMenu {
            if planned && !model.isArrived(e) {
                Button { model.arrive(at: e) } label: { Label("J'y suis", systemImage: "figure.walk.arrival") }
            }
            if e.isExternal {
                Button { model.editor = AppModel.EditorTarget(entry: e, isNew: false) } label: {
                    Label("Détails…", systemImage: "info.circle")
                }
            } else {
                if e.isRunning {
                    Button { model.stop(e.id) } label: { Label("Terminer maintenant", systemImage: "stop.fill") }
                }
                Button { model.editor = AppModel.EditorTarget(entry: e, isNew: false) } label: {
                    Label("Modifier…", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) { model.delete(e.id) } label: { Label("Supprimer", systemImage: "trash") }
            }
        }
        .onTapGesture { model.editor = AppModel.EditorTarget(entry: original, isNew: false) }
        .gesture((original.isRunning || original.isExternal) ? nil : DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { v in liveMove[original.id] = seconds(v.translation.height) }
            .onEnded { v in
                liveMove[original.id] = nil
                model.save(Manipulation.moved(original, by: seconds(v.translation.height), within: dayBounds))
            })
        .overlay(alignment: .bottom) {
            // Poignée du bas : étirer la fin.
            if !original.isRunning && !original.isExternal {
                ZStack {
                    Rectangle().fill(Color.clear)
                    if h > 34 { Capsule().fill(ink.opacity(0.45)).frame(width: 24, height: 3) }
                }
                .frame(height: 10).contentShape(Rectangle())
                .onHover { inside in (inside ? NSCursor.resizeUpDown : NSCursor.arrow).set() }
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { v in liveResize[original.id] = seconds(v.translation.height) }
                    .onEnded { v in
                        liveResize[original.id] = nil
                        model.save(Manipulation.resized(original, by: seconds(v.translation.height), within: dayBounds))
                    })
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(planned ? "Prévu" : "Réel") : \(e.title), \(detail(e))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.editor = AppModel.EditorTarget(entry: original, isNew: false) }
        .accessibilityAction(named: "J'y suis") { if planned { model.arrive(at: e) } }
        .offset(x: CGFloat(p.lane) * w + 3, y: y + 1)
        .animation(.easeOut(duration: 0.12), value: live)
        .help("\(e.title) · \(detail(e)) · \(e.category)")
    }

    private func ghost(_ c: (kind: EntryKind, y0: CGFloat, y1: CGFloat), width: CGFloat) -> some View {
        let r = Manipulation.range(date(atY: c.y0), date(atY: c.y1))
        let top = CGFloat(r.start.timeIntervalSince(dayStart) / 3600) * hourHeight
        let h = CGFloat(r.end.timeIntervalSince(r.start) / 3600) * hourHeight
        let label = "\(r.start.formatted(date: .omitted, time: .shortened)) – \(r.end.formatted(date: .omitted, time: .shortened))"
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.accent.opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.accent, lineWidth: 1.5))
            .overlay(alignment: .topLeading) {
                Text(label).font(Theme.rounded(12, .bold)).foregroundStyle(Theme.accent).padding(8)
            }
            .frame(width: width - 6, height: h)
            .offset(x: 3, y: top)
            .allowsHitTesting(false)
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
        let y = CGFloat(model.now.timeIntervalSince(dayStart) / 3600) * hourHeight
        return ZStack(alignment: .leading) {
            Rectangle().fill(Theme.accent).frame(height: 2).padding(.leading, gutter - 6)
            Text(model.now.formatted(date: .omitted, time: .shortened))
                .font(Theme.rounded(10, .bold)).monospacedDigit().foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Theme.accentGradient))
                .frame(width: gutter - 2, alignment: .trailing)
        }
        .offset(y: y - 8)
        .allowsHitTesting(false)
    }
}

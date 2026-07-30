import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("appearance") private var appearance = "dark"
    @Environment(\.colorScheme) private var colorScheme
    @State private var presetName = ""
    @State private var draftStartMHz = 0.1
    @State private var draftStopMHz = 800.0
    @State private var peakHoldEnabled = false
    @State private var scanToRename: SpectrumScan?
    @State private var renameText = ""
    @State private var showingDeleteAllConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                centerPanel.frame(minWidth: 560, maxHeight: .infinity, alignment: .top)
                timelinePanel.frame(width: 64).frame(maxHeight: .infinity, alignment: .top)
                scanPanel.frame(minWidth: 250, idealWidth: 280, maxWidth: 340, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            Divider()
            HStack {
                Circle().fill(model.isConnected ? .green : .secondary).frame(width: 7)
                Text(model.status).lineLimit(1)
                Spacer()
                if let percent = model.batteryPercent, let millivolts = model.batteryMillivolts {
                    Label("~\(percent)%  •  \(String(format: "%.2f", Double(millivolts) / 1000)) V", systemImage: batteryIcon(percent))
                        .monospacedDigit()
                        .help("Estimated from the TinySA battery voltage; not a calibrated charge measurement")
                }
                Divider().frame(height: 14)
                Button { appearance = appearance == "dark" ? "light" : "dark" } label: {
                    Label(appearance == "dark" ? "Light" : "Dark", systemImage: appearance == "dark" ? "sun.max.fill" : "moon.stars.fill")
                }
                .buttonStyle(.plain)
                .help("Switch to \(appearance == "dark" ? "light" : "dark") mode")
            }
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14).frame(height: 30)
            .background(.bar)
        }
        .background(appBackground)
        .preferredColorScheme(appearance == "dark" ? .dark : .light)
        .tint(Color(red: 0.08, green: 0.72, blue: 0.94))
        .onAppear { syncDraftRange() }
        .onChange(of: model.startHz) { _ in model.frequencyRangeDidChange() }
        .onChange(of: model.stopHz) { _ in model.frequencyRangeDidChange() }
        .sheet(item: $scanToRename) { scan in
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename scan").font(.title2.bold())
                TextField("Scan name", text: $renameText).textFieldStyle(.roundedBorder)
                HStack { Spacer(); Button("Cancel") { scanToRename = nil }; Button("Save") { model.renameScan(scan, to: renameText); scanToRename = nil }.keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 400)
        }
        .confirmationDialog("Delete all scans?", isPresented: $showingDeleteAllConfirmation, titleVisibility: .visible) {
            Button("Delete All Scans", role: .destructive) { model.deleteAllScans() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This permanently removes every saved scan from the browser.") }
    }

    private var appBackground: Color {
        colorScheme == .dark
            ? Color(red: 7 / 255, green: 16 / 255, blue: 25 / 255)
            : Color(red: 239 / 255, green: 248 / 255, blue: 250 / 255)
    }

    private var panelBackground: Color { colorScheme == .dark ? Color(red: 16 / 255, green: 26 / 255, blue: 36 / 255) : .white }
    private var graphBackground: Color {
        colorScheme == .dark
            ? Color(red: 7 / 255, green: 19 / 255, blue: 28 / 255)
            : Color(red: 248 / 255, green: 252 / 255, blue: 253 / 255)
    }
    private var panelBorder: Color { colorScheme == .dark ? Color(red: 0.16, green: 0.26, blue: 0.33) : Color(red: 0.69, green: 0.80, blue: 0.84) }

    private var centerPanel: some View {
        VStack(spacing: 10) {
            HStack {
                Text("SPECTRUM").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Toggle(isOn: $peakHoldEnabled) {
                    Label("Peak Hold", systemImage: "waveform.path.ecg.rectangle")
                        .font(.caption2.bold())
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .tint(.red)
                .disabled(!model.scans.contains { model.selectedScanIDs.contains($0.id) && $0.isContinuous })
                .help("Overlay the highest level captured at each frequency in red")
            }
            .padding(12)
            .background(panelBackground, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(panelBorder, lineWidth: 1))
            SpectrumView(scans: model.scans, selected: model.selectedScanIDs, timelinePosition: model.timelinePosition, timelineCaptureIndex: model.timelineCaptureIndex, peakHoldEnabled: peakHoldEnabled)
                .frame(minHeight: 300, maxHeight: .infinity)
                .layoutPriority(1)
                .background(graphBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(panelBorder, lineWidth: 1))
            controls.padding(14)
                .background(panelBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(panelBorder, lineWidth: 1))
        }
        .padding(14)
    }

    private var timelinePanel: some View {
        VStack(spacing: 10) {
            Text("NOW").font(.caption2.bold()).foregroundStyle(model.timelinePosition > 0.995 ? Color.cyan : Color.secondary)
            VerticalTimelineSlider(value: Binding(get: { model.timelinePosition }, set: { model.setTimelinePosition($0) }))
            Image(systemName: "clock.arrow.circlepath").font(.caption).foregroundStyle(.secondary)
            if let date = timelineDate {
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                Text("—").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 16)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(panelBorder, lineWidth: 1))
        .padding(.vertical, 14)
        .help("Timeline — top is the newest capture")
    }

    private var timelineDate: Date? {
        let selected = model.scans.filter { model.selectedScanIDs.contains($0.id) }
        guard let scan = selected.first else { return nil }
        return scan.captureDate(atCaptureIndex: model.timelineCaptureIndex)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.presets) { preset in
                        HStack(spacing: 0) {
                            Button { model.apply(preset); syncDraftRange() } label: {
                                Text(preset.name).foregroundStyle(colorScheme == .light ? Color(red: 0.09, green: 0.23, blue: 0.29) : .primary)
                            }
                            .buttonStyle(.borderless).padding(.leading, 10).padding(.vertical, 6)
                            Button { model.deletePreset(preset) } label: {
                                Image(systemName: "trash").font(.caption2).foregroundStyle(.secondary).padding(7)
                            }.buttonStyle(.plain).help("Delete \(preset.name)")
                        }
                        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            HStack {
                frequencyField("START", value: $draftStartMHz)
                frequencyField("STOP", value: $draftStopMHz)
                Button("SET") { applyDraftRange() }.buttonStyle(.borderedProminent).tint(.secondary)
                Divider().frame(height: 22)
                TextField("Preset name", text: $presetName).textFieldStyle(.roundedBorder).frame(minWidth: 110)
                Button("SAVE PRESET") {
                    applyDraftRange()
                    if !presetName.isEmpty { model.addPreset(name: presetName); presetName = "" }
                }.disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 10) {
                Button("SCAN") { model.beginScan() }.buttonStyle(.borderedProminent).tint(.cyan).disabled(!model.isConnected || model.isScanning)
                Button("STOP") { model.stop() }.buttonStyle(.bordered).tint(.red).disabled(!model.isScanning)
                Button("CONTINUOUS") { model.beginScan(continuous: true) }.buttonStyle(.borderedProminent).tint(.purple).disabled(!model.isConnected || model.isScanning)
                Spacer()
                Picker("Resolution", selection: Binding(get: { model.rbw }, set: { model.selectRBW($0) })) {
                    ForEach(model.availableRBWs) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 235)
                .disabled(model.isScanning)
                Picker("Interval", selection: Binding(get: { model.scanInterval }, set: { model.selectInterval($0) })) {
                    ForEach(ScanInterval.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 125)
                .disabled(model.isScanning)
                Text("~\(formattedDuration(model.estimatedSweepDuration)) sweep")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(model.estimatedSweepDuration > model.scanInterval.seconds ? Color.orange : Color.secondary)
                    .help("Estimated TinySA sweep time for the selected span and resolution")
                if let progress = model.intervalProgress, let remaining = model.nextScanRemaining {
                    scanCountdown(progress: progress, remaining: remaining)
                } else if model.isScanning {
                    ProgressView().controlSize(.small)
                }
            }.controlSize(.large)
        }
    }

    private func frequencyField(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 5) { Text(label).font(.caption2.bold()).foregroundStyle(.secondary); TextField("MHz", value: value, format: .number.precision(.fractionLength(0...6)).grouping(.never)).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 112); Text("MHz").font(.caption).foregroundStyle(.secondary) }
    }

    private func syncDraftRange() { draftStartMHz = model.startHz / 1e6; draftStopMHz = model.stopHz / 1e6 }
    private func batteryIcon(_ percent: Int) -> String {
        if percent >= 88 { return "battery.100percent" }
        if percent >= 63 { return "battery.75percent" }
        if percent >= 38 { return "battery.50percent" }
        if percent >= 13 { return "battery.25percent" }
        return "battery.0percent"
    }
    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(1, Int(duration.rounded()))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }
    private func scanCountdown(progress: Double, remaining: TimeInterval) -> some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.purple, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(formattedDuration(remaining))
                .font(.system(size: 8, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.65)
        }
        .frame(width: 38, height: 38)
        .help("Time remaining until the next continuous scan")
        .accessibilityLabel("Next scan in \(formattedDuration(remaining))")
    }
    private func applyDraftRange() {
        let start = max(100_000, min(draftStartMHz * 1e6, model.maxHz - 1))
        let stop = max(start + 1, min(draftStopMHz * 1e6, model.maxHz))
        model.applyRange(startHz: start, stopHz: stop)
        draftStartMHz = start / 1e6; draftStopMHz = stop / 1e6
    }

    private var scanPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("SCAN BROWSER", systemImage: "square.stack.3d.up").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.selectedScanIDs.count) VISIBLE").font(.caption2).foregroundStyle(.secondary)
                Button { model.selectedScanIDs = [] } label: { Text("Clear").font(.caption) }.buttonStyle(.plain)
                Button("Delete All", role: .destructive) { showingDeleteAllConfirmation = true }.font(.caption).buttonStyle(.plain).disabled(model.scans.isEmpty)
            }
            if model.scans.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.title)
                    Text("No scans yet")
                        .font(.headline)
                    Text("Captured scans stay on this Mac.")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            else {
                List { ForEach(Array(model.scans.enumerated()), id: \.element.id) { index, scan in
                    HStack(spacing: 10) {
                        Circle().fill(Palette.color(index, scheme: colorScheme)).frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(scan.title).fontWeight(.medium).lineLimit(1)
                            Text(scan.customName == nil
                                ? "\(scan.date.formatted(date: .abbreviated, time: .shortened))  •  \(scan.rbw)"
                                : "\(scan.rangeTitle)  •  \(scan.date.formatted(date: .abbreviated, time: .shortened))  •  \(scan.rbw)")
                                .font(.caption2).foregroundStyle(.secondary)
                            if scan.isContinuous {
                                Label("\(scan.captureCount) scans", systemImage: "clock.arrow.circlepath").font(.caption2.bold()).foregroundStyle(.purple)
                            }
                        }
                        Spacer()
                        Image(systemName: model.selectedScanIDs.contains(scan.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(model.selectedScanIDs.contains(scan.id) ? Palette.color(index, scheme: colorScheme) : .secondary)
                        Button { exportScanToWWB(scan) } label: {
                            Text("WWB")
                                .font(.system(size: 8, weight: .heavy, design: .rounded))
                                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                                .frame(width: 28, height: 28)
                                .background(Color.cyan, in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Export to Shure Wireless Workbench")
                        .help("Export this scan to Wireless Workbench")
                        Button { renameText = scan.customName ?? ""; scanToRename = scan } label: { Image(systemName: "pencil").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).help("Rename scan")
                        Button { model.deleteScan(scan) } label: { Image(systemName: "trash").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).help("Delete scan")
                    }.contentShape(Rectangle()).onTapGesture { model.toggleScanVisibility(scan) }
                }.onDelete(perform: model.deleteScans) }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
        }.padding(16)
            .background(panelBackground, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(panelBorder, lineWidth: 1))
            .padding(.vertical, 14).padding(.trailing, 14)
    }

    private func exportScanToWWB(_ scan: SpectrumScan) {
        if scan.isContinuous {
            exportTimelineToWWB(scan)
            return
        }
        let points = scan.points(atCaptureIndex: model.timelineCaptureIndex)
        let csv = points.map { String(format: "%.6f,%.2f", $0.frequency / 1e6, $0.level) }.joined(separator: "\n") + "\n"
        let filename = ExportFilename.baseName(date: scan.date, location: model.currentCity, customName: scan.customName) + ".csv"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = filename
        panel.title = "Export Scan to Wireless Workbench"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            model.status = "Exported WWB scan to \(url.lastPathComponent)"
        } catch {
            model.status = "WWB export failed: \(error.localizedDescription)"
        }
    }

    private func exportTimelineToWWB(_ scan: SpectrumScan) {
        let baseName = ExportFilename.baseName(date: scan.date, location: model.currentCity, customName: scan.customName)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "sdb3") ?? .data]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = baseName + ".sdb3"
        panel.title = "Export Continuous Scan to Wireless Workbench"
        panel.prompt = "Export Timeline"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try WWBTimelineExporter.data(for: scan, title: baseName)
            try data.write(to: url, options: .atomic)
            model.status = "Exported WWB timeline with \(scan.captureCount) sweeps to \(url.lastPathComponent)"
        } catch {
            model.status = "WWB timeline export failed: \(error.localizedDescription)"
        }
    }

}

struct VerticalTimelineSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { geometry in
            let top: CGFloat = 10
            let bottom: CGFloat = geometry.size.height - 10
            let trackHeight = max(1, bottom - top)
            let thumbY = bottom - CGFloat(value) * trackHeight
            ZStack {
                Capsule()
                    .fill(.secondary.opacity(0.22))
                    .frame(width: 6, height: trackHeight)
                    .position(x: geometry.size.width / 2, y: (top + bottom) / 2)
                Capsule()
                    .fill(Color.cyan.opacity(0.8))
                    .frame(width: 6, height: max(1, bottom - thumbY))
                    .position(x: geometry.size.width / 2, y: (thumbY + bottom) / 2)
                ForEach(0...8, id: \.self) { tick in
                    let y = top + CGFloat(tick) / 8 * trackHeight
                    Capsule().fill(.secondary.opacity(0.45)).frame(width: tick % 4 == 0 ? 22 : 13, height: 1).position(x: geometry.size.width / 2, y: y)
                }
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(Circle().stroke(Color.cyan, lineWidth: 3))
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .frame(width: 22, height: 22)
                    .position(x: geometry.size.width / 2, y: thumbY)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                value = min(1, max(0, Double((bottom - gesture.location.y) / trackHeight)))
            })
        }
        .accessibilityElement()
        .accessibilityLabel("Scan timeline")
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in
            value = min(1, max(0, value + (direction == .increment ? 0.05 : -0.05)))
        }
    }
}

struct FrequencyRangeControl: View {
    @Binding var startHz: Double
    @Binding var stopHz: Double
    let bounds: ClosedRange<Double>
    private var span: Double { max(1, stopHz - startHz) }
    private var center: Double { (startHz + stopHz) / 2 }
    private var minimumSpan: Double { 1_000 }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("CENTER").font(.caption2.bold()).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                Slider(value: Binding(get: { center }, set: { newCenter in
                    let half = span / 2
                    let clamped = min(bounds.upperBound - half, max(bounds.lowerBound + half, newCenter))
                    startHz = clamped - half; stopHz = clamped + half
                }), in: centerBounds)
                Text(SpectrumScan.short(center)).font(.caption.monospacedDigit()).frame(width: 82, alignment: .trailing)
            }
            HStack(spacing: 12) {
                Text("SPAN").font(.caption2.bold()).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                Slider(value: Binding(get: { log10(span) }, set: { logarithmicValue in
                    let newSpan = pow(10, logarithmicValue)
                    let currentCenter = center
                    let half = newSpan / 2
                    let clampedCenter = min(bounds.upperBound - half, max(bounds.lowerBound + half, currentCenter))
                    startHz = clampedCenter - half; stopHz = clampedCenter + half
                }), in: log10(minimumSpan)...log10(bounds.upperBound - bounds.lowerBound))
                Text(SpectrumScan.short(span)).font(.caption.monospacedDigit()).frame(width: 82, alignment: .trailing)
            }
        }
    }
    private var centerBounds: ClosedRange<Double> {
        let half = min(span / 2, (bounds.upperBound - bounds.lowerBound) / 2)
        return (bounds.lowerBound + half)...(bounds.upperBound - half)
    }
}

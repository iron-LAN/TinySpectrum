import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var devices: [SerialCandidate] = []
    @Published var selectedDevice: SerialCandidate?
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var isScanning = false
    @Published var continuous = false
    @Published var status = "Connect a TinySA Ultra to begin"
    @Published var startHz = 100_000.0
    @Published var stopHz = 800_000_000.0
    @Published var maxHz = 5_300_000_000.0
    @Published var rbw: RBW = .khz30
    @Published var scanInterval: ScanInterval = .minute1
    @Published var intervalProgress: Double?
    @Published var nextScanRemaining: TimeInterval?
    @Published var scans: [SpectrumScan] = []
    @Published var selectedScanIDs: Set<UUID> = []
    @Published var timelinePosition = 1.0
    @Published var timelineCaptureIndex: Int?
    @Published var batteryMillivolts: Int?
    @Published var currentCity: String?
    @Published var presets: [ScanPreset] = [
        .init(id: UUID(), name: "FM Broadcast", startHz: 87_500_000, stopHz: 108_000_000),
        .init(id: UUID(), name: "ISM 433", startHz: 433_000_000, stopHz: 435_000_000),
        .init(id: UUID(), name: "ISM 868", startHz: 863_000_000, stopHz: 870_000_000),
        .init(id: UUID(), name: "Wi-Fi 2.4", startHz: 2_400_000_000, stopHz: 2_500_000_000)
    ]
    private let serial = TinySASerial()
    private var scanTask: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?
    private var batteryPollInFlight = false
    private var lastBatteryPoll = Date.distantPast
    private let locationProvider = CityLocationProvider()
    private let storeURL: URL
    private enum TimingDriver { case resolution, interval }
    private var timingDriver: TimingDriver = .resolution

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storeURL = base.appending(path: "TinySpectrum/scans.json")
        load()
        status = "Looking for a TinySA…"
        locationProvider.requestCity { [weak self] city in
            Task { @MainActor in self?.currentCity = city }
        }
        discoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.discoverAndConnect()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func discoverAndConnect() {
        devices = TinySASerial.candidates()
        if isConnected, let selectedDevice, !devices.contains(selectedDevice) {
            stop()
            Task { await serial.disconnect() }
            isConnected = false
            batteryMillivolts = nil
            self.selectedDevice = nil
            status = "TinySA disconnected — looking for it…"
        }
        if isConnected, !isScanning, !batteryPollInFlight, Date().timeIntervalSince(lastBatteryPoll) >= 60 {
            pollBattery()
        }
        guard !isConnected, !isConnecting else { return }
        guard let candidate = devices.first else {
            selectedDevice = nil
            status = "Looking for a TinySA…"
            return
        }
        selectedDevice = candidate
        connect(to: candidate)
    }

    private func connect(to device: SerialCandidate) {
        guard !isConnecting, !isConnected else { return }
        isConnecting = true
        status = "Connecting to TinySA…"
        Task {
            do {
                try await serial.connect(path: device.path)
                isConnected = true
                status = "TinySA connected"
                lastBatteryPoll = .distantPast
            } catch {
                selectedDevice = nil
                status = "Could not connect — retrying…"
            }
            isConnecting = false
        }
    }

    private func pollBattery() {
        batteryPollInFlight = true
        lastBatteryPoll = Date()
        Task {
            if let voltage = try? await serial.batteryVoltage() { batteryMillivolts = voltage }
            batteryPollInFlight = false
        }
    }

    var batteryPercent: Int? {
        guard let mv = batteryMillivolts else { return nil }
        let curve = [(3400, 0), (3600, 10), (3700, 20), (3800, 40), (3900, 60), (4000, 80), (4100, 90), (4200, 100)]
        if mv <= curve[0].0 { return 0 }
        if mv >= curve.last!.0 { return 100 }
        for index in 1..<curve.count where mv <= curve[index].0 {
            let low = curve[index - 1], high = curve[index]
            return low.1 + (mv - low.0) * (high.1 - low.1) / (high.0 - low.0)
        }
        return nil
    }

    func beginScan(continuous shouldRepeat: Bool = false) {
        guard isConnected, !isScanning else { return }
        continuous = shouldRepeat
        isScanning = true
        scanTask = Task { [weak self] in
            guard let self else { return }
            var continuousGroupID: UUID?
            repeat {
                intervalProgress = nil
                nextScanRemaining = nil
                let sweepStarted = Date()
                do {
                    status = "Scanning \(SpectrumScan.short(startHz)) – \(SpectrumScan.short(stopHz))…"
                    let effectiveRBW = rbw
                    let pointCount = shouldRepeat ? 145 : 450
                    let values = try await serial.scan(startHz: startHz, stopHz: stopHz, rbw: effectiveRBW, points: pointCount)
                    let capture = ScanCapture(date: Date(), points: values)
                    if shouldRepeat, let groupID = continuousGroupID, let index = scans.firstIndex(where: { $0.id == groupID }) {
                        scans[index].points = values
                        scans[index].captures?.append(capture)
                        updateTimelinePosition(for: scans[index])
                        status = "Continuous scan • \(scans[index].captureCount) captures"
                    } else {
                        let resolutionLabel = shouldRepeat ? "\(effectiveRBW.rawValue) • every \(scanInterval.label) • 145 pts" : effectiveRBW.rawValue
                        let scan = SpectrumScan(id: UUID(), date: capture.date, startHz: startHz, stopHz: stopHz, rbw: resolutionLabel, points: values, captures: shouldRepeat ? [capture] : nil)
                        scans.insert(scan, at: 0)
                        showScan(scan)
                        if shouldRepeat { continuousGroupID = scan.id }
                        status = shouldRepeat ? "Continuous scan • 1 capture" : "Captured \(values.count) points"
                    }
                    save()
                    if shouldRepeat, continuous, !Task.isCancelled {
                        let deadline = sweepStarted.addingTimeInterval(scanInterval.seconds)
                        while continuous, !Task.isCancelled {
                            let remaining = deadline.timeIntervalSinceNow
                            guard remaining > 0 else { break }
                            nextScanRemaining = remaining
                            intervalProgress = min(1, max(0, 1 - remaining / scanInterval.seconds))
                            try await Task.sleep(for: .milliseconds(200))
                        }
                    }
                } catch {
                    if !(error is CancellationError) { status = error.localizedDescription }
                    break
                }
            } while continuous && !Task.isCancelled
            intervalProgress = nil
            nextScanRemaining = nil
            isScanning = false
            if Task.isCancelled || (shouldRepeat && !continuous) { status = "Scan stopped" }
            continuous = false
        }
    }

    func stop() {
        continuous = false
        intervalProgress = nil
        nextScanRemaining = nil
        scanTask?.cancel()
        Task { await serial.stop() }
        if isScanning { status = "Stopping scan…" }
    }

    func apply(_ preset: ScanPreset) { startHz = preset.startHz; stopHz = preset.stopHz; frequencyRangeDidChange() }
    func selectRBW(_ value: RBW) {
        timingDriver = .resolution
        rbw = value
        scanInterval = SweepEstimator.shortestInterval(spanHz: scanSpanHz, fitting: value)
    }
    func selectInterval(_ value: ScanInterval) {
        timingDriver = .interval
        scanInterval = value
        rbw = SweepEstimator.finestRBW(spanHz: scanSpanHz, fitting: value)
    }
    func frequencyRangeDidChange() {
        switch timingDriver {
        case .resolution:
            scanInterval = SweepEstimator.shortestInterval(spanHz: scanSpanHz, fitting: rbw)
        case .interval:
            rbw = SweepEstimator.finestRBW(spanHz: scanSpanHz, fitting: scanInterval)
        }
    }
    var estimatedSweepDuration: TimeInterval { SweepEstimator.duration(spanHz: scanSpanHz, rbw: rbw) }
    private var scanSpanHz: Double { max(1, stopHz - startHz) }
    func addPreset(name: String) { presets.append(.init(id: UUID(), name: name, startHz: startHz, stopHz: stopHz)); save() }
    func deletePreset(_ preset: ScanPreset) { presets.removeAll { $0.id == preset.id }; save() }
    func toggleScanVisibility(_ scan: SpectrumScan) {
        if selectedScanIDs.contains(scan.id) {
            selectedScanIDs.remove(scan.id)
        } else {
            showScan(scan)
        }
    }
    private func showScan(_ scan: SpectrumScan) {
        if scan.isContinuous {
            let otherContinuousIDs = Set(scans.filter { $0.isContinuous && $0.id != scan.id }.map(\.id))
            selectedScanIDs.subtract(otherContinuousIDs)
            timelineCaptureIndex = nil
            timelinePosition = 1
        }
        selectedScanIDs.insert(scan.id)
    }
    func deleteScan(_ scan: SpectrumScan) { selectedScanIDs.remove(scan.id); scans.removeAll { $0.id == scan.id }; save() }
    func deleteScans(at offsets: IndexSet) { offsets.map { scans[$0].id }.forEach { selectedScanIDs.remove($0) }; scans.remove(atOffsets: offsets); save() }

    func setTimelinePosition(_ position: Double) {
        timelinePosition = min(1, max(0, position))
        guard timelinePosition < 0.995, let scan = timelineReferenceScan, scan.captureCount > 1 else {
            timelineCaptureIndex = nil
            timelinePosition = 1
            return
        }
        timelineCaptureIndex = min(scan.captureCount - 1, max(0, Int((timelinePosition * Double(scan.captureCount - 1)).rounded())))
        updateTimelinePosition(for: scan)
    }

    private var timelineReferenceScan: SpectrumScan? {
        scans.first { selectedScanIDs.contains($0.id) && $0.isContinuous }
    }

    private func updateTimelinePosition(for scan: SpectrumScan) {
        guard let index = timelineCaptureIndex, scan.captureCount > 1 else { timelinePosition = 1; return }
        timelinePosition = Double(min(index, scan.captureCount - 1)) / Double(scan.captureCount - 1)
    }

    private struct Stored: Codable { var scans: [SpectrumScan]; var presets: [ScanPreset] }
    private func load() {
        guard let data = try? Data(contentsOf: storeURL), let value = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        scans = value.scans; presets = value.presets
    }
    private func save() {
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Stored(scans: scans, presets: presets)) { try? data.write(to: storeURL, options: .atomic) }
    }
}

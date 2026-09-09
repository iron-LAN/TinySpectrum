import Foundation

/// On-disk layout for the scan library.
///
/// `scans.json` holds metadata only, so it is rewritten when the library
/// changes shape rather than once per sweep. The captures of every scan live
/// in `sessions/<id>.ndjson`, one capture per line, which a continuous session
/// appends to. Rewriting the entire library on each sweep meant an overnight
/// survey wrote tens of gigabytes to persist a few megabytes of measurements.
struct ScanStore {
    struct Contents {
        var scans: [SpectrumScan]
        var presets: [ScanPreset]
        /// Set when something had to be skipped or set aside to start up.
        var recoveryNote: String?
    }

    enum StoreError: LocalizedError {
        case unreadableIndex(String)

        var errorDescription: String? {
            switch self {
            case .unreadableIndex(let name):
                "Saved scans could not be read. The file was kept as \(name)."
            }
        }
    }

    private let directory: URL
    private static let currentVersion = 2

    init(directory: URL) { self.directory = directory }

    private var indexURL: URL { directory.appending(path: "scans.json") }
    private var sessionsDirectory: URL { directory.appending(path: "sessions") }
    private func sessionURL(_ id: UUID) -> URL {
        sessionsDirectory.appending(path: "\(id.uuidString).ndjson")
    }

    // MARK: - Reading

    /// Returns `nil` when no store exists yet, so a fresh install keeps its
    /// built-in presets instead of being handed an empty list.
    func load() throws -> Contents? {
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        if let index = try? JSONDecoder().decode(Index.self, from: data) {
            return readSessions(for: index)
        }
        if let legacy = try? JSONDecoder().decode(Legacy.self, from: data) {
            try migrate(legacy)
            return Contents(scans: legacy.scans, presets: legacy.presets, recoveryNote: nil)
        }
        // Starting empty and silently discarding a damaged library is the one
        // outcome a local-only measurement tool must never produce.
        throw StoreError.unreadableIndex(try quarantine().lastPathComponent)
    }

    private func readSessions(for index: Index) -> Contents {
        var scans: [SpectrumScan] = []
        var truncated = 0
        for record in index.scans {
            let session = readSession(record.id)
            if session.truncated { truncated += 1 }
            guard let latest = session.captures.last else { continue }
            scans.append(
                SpectrumScan(
                    id: record.id,
                    date: record.date,
                    startHz: record.startHz,
                    stopHz: record.stopHz,
                    rbw: record.rbw,
                    points: latest.points,
                    captures: record.isContinuous ? session.captures : nil,
                    customName: record.customName
                )
            )
        }
        let note = truncated == 0
            ? nil
            : "Recovered \(truncated) scan\(truncated == 1 ? "" : "s") that were still being written."
        return Contents(scans: scans, presets: index.presets, recoveryNote: note)
    }

    private func readSession(_ id: UUID) -> (captures: [ScanCapture], truncated: Bool) {
        guard let data = try? Data(contentsOf: sessionURL(id)) else { return ([], false) }
        let decoder = JSONDecoder()
        var captures: [ScanCapture] = []
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            // A half-written final line is what a crash mid-append leaves
            // behind. Keep every complete capture ahead of it.
            guard let capture = try? decoder.decode(ScanCapture.self, from: Data(line)) else {
                return (captures, true)
            }
            captures.append(capture)
        }
        return (captures, false)
    }

    // MARK: - Writing

    func startSession(_ id: UUID, firstCapture: ScanCapture) throws {
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        try line(for: firstCapture).write(to: sessionURL(id), options: .atomic)
    }

    /// Appends one sweep. This is the only write on the continuous scan path.
    func append(_ capture: ScanCapture, to id: UUID) throws {
        guard let handle = try? FileHandle(forWritingTo: sessionURL(id)) else {
            // The session file went missing; begin a new one rather than
            // dropping the sweep that was just measured.
            try startSession(id, firstCapture: capture)
            return
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line(for: capture))
    }

    func saveIndex(scans: [SpectrumScan], presets: [ScanPreset]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let index = Index(
            version: Self.currentVersion,
            scans: scans.map(Record.init(scan:)),
            presets: presets
        )
        try JSONEncoder().encode(index).write(to: indexURL, options: .atomic)
    }

    func deleteSessions(_ ids: [UUID]) {
        for id in ids { try? FileManager.default.removeItem(at: sessionURL(id)) }
    }

    private func line(for capture: ScanCapture) throws -> Data {
        var data = try JSONEncoder().encode(capture)
        data.append(0x0A)
        return data
    }

    // MARK: - Migration and recovery

    private func migrate(_ legacy: Legacy) throws {
        // Keep the pre-3.0 file. The conversion runs once, unattended, against
        // measurements that cannot be recaptured.
        let backup = directory.appending(path: "scans-v1-backup.json")
        if (try? Data(contentsOf: backup)) == nil {
            try? FileManager.default.copyItem(at: indexURL, to: backup)
        }
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        for scan in legacy.scans {
            let captures = scan.captures ?? [ScanCapture(date: scan.date, points: scan.points)]
            var data = Data()
            for capture in captures { data.append(try line(for: capture)) }
            try data.write(to: sessionURL(scan.id), options: .atomic)
        }
        try saveIndex(scans: legacy.scans, presets: legacy.presets)
    }

    private func quarantine() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let destination = directory.appending(path: "scans-unreadable-\(formatter.string(from: Date())).json")
        try FileManager.default.moveItem(at: indexURL, to: destination)
        return destination
    }

    // MARK: - Stored shapes

    private struct Index: Codable {
        var version: Int
        var scans: [Record]
        var presets: [ScanPreset]
    }

    private struct Record: Codable {
        var id: UUID
        var date: Date
        var startHz: Double
        var stopHz: Double
        var rbw: String
        var customName: String?
        var isContinuous: Bool

        init(scan: SpectrumScan) {
            id = scan.id
            date = scan.date
            startHz = scan.startHz
            stopHz = scan.stopHz
            rbw = scan.rbw
            customName = scan.customName
            isContinuous = scan.isContinuous
        }
    }

    /// The pre-3.0 file: every point of every capture in a single blob.
    private struct Legacy: Codable {
        var scans: [SpectrumScan]
        var presets: [ScanPreset]
    }
}

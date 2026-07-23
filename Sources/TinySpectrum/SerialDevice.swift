import Foundation
import Darwin

struct SerialCandidate: Identifiable, Hashable {
    let path: String
    var id: String { path }
    var displayName: String { URL(fileURLWithPath: path).lastPathComponent }
}

enum SerialError: LocalizedError {
    case openFailed(String), timeout, stopped, malformedResponse
    var errorDescription: String? {
        switch self {
        case .openFailed(let path): "Could not open \(path). Close other TinySA apps and reconnect the USB cable."
        case .timeout: "The TinySA did not finish responding in time."
        case .stopped: "Scan stopped."
        case .malformedResponse: "The TinySA returned no readable measurement points."
        }
    }
}

actor TinySASerial {
    private var descriptor: Int32 = -1
    private var cancelled = false

    static func candidates() -> [SerialCandidate] {
        let patterns = ["/dev/cu.usbmodem*", "/dev/cu.usbserial*", "/dev/cu.wchusbserial*"]
        return patterns.flatMap { glob($0) }.map(SerialCandidate.init(path:)).sorted { $0.path < $1.path }
    }

    private static func glob(_ pattern: String) -> [String] {
        var value = glob_t()
        guard Darwin.glob(pattern, 0, nil, &value) == 0 else { return [] }
        defer { globfree(&value) }
        return (0..<Int(value.gl_pathc)).compactMap { index in
            guard let pointer = value.gl_pathv[index] else { return nil }
            return String(cString: pointer)
        }
    }

    func connect(path: String) throws {
        closePort()
        descriptor = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else { throw SerialError.openFailed(path) }
        _ = fcntl(descriptor, F_SETFL, 0)
        var settings = termios()
        if tcgetattr(descriptor, &settings) == 0 {
            cfmakeraw(&settings)
            cfsetspeed(&settings, speed_t(B115200))
            settings.c_cflag |= tcflag_t(CLOCAL | CREAD)
            _ = tcsetattr(descriptor, TCSANOW, &settings)
        }
        tcflush(descriptor, TCIOFLUSH)
    }

    func disconnect() { closePort() }
    private func closePort() { if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 } }

    func stop() {
        cancelled = true
        // `pause` is a normal shell command and is only processed after an
        // active `scan` finishes. With abortion enabled, the bare `abort`
        // command is handled while the previous command is still running.
        if descriptor >= 0 { _ = "abort\r\n".withCString { Darwin.write(descriptor, $0, strlen($0)) } }
    }

    func batteryVoltage() async throws -> Int {
        try write("vbat\r\n")
        let response = try await readResponse(timeout: 3)
        let values = response.split(whereSeparator: { $0.isWhitespace }).compactMap { Int($0) }
        guard let millivolts = values.first(where: { $0 >= 2500 && $0 <= 5000 }) else {
            throw SerialError.malformedResponse
        }
        return millivolts
    }

    func scan(startHz: Double, stopHz: Double, rbw: RBW, points: Int = 450) async throws -> [ScanPoint] {
        cancelled = false
        try write("abort on\r\n")
        _ = try await readResponse(timeout: 3)
        try write("rbw \(rbw.command)\r\n")
        _ = try await readResponse(timeout: 3)
        try write("scan \(Int(startHz)) \(Int(stopHz)) \(points) 2\r\n")
        // A narrow RBW over a wide span can legitimately take several minutes.
        let response = try await readResponse(timeout: 600)
        if cancelled { throw SerialError.stopped }
        let levels = response.split(whereSeparator: \Character.isNewline).compactMap { line -> Double? in
            let cleaned = line.replacingOccurrences(of: "-:.0", with: "-10.0")
            return cleaned.split(whereSeparator: \Character.isWhitespace).first.flatMap { Double($0) }
        }
        guard levels.count >= 2 else { throw SerialError.malformedResponse }
        return levels.enumerated().map { index, level in
            let f = startHz + (stopHz - startHz) * Double(index) / Double(levels.count - 1)
            return ScanPoint(frequency: f, level: level)
        }
    }

    private func write(_ string: String) throws {
        guard descriptor >= 0 else { throw SerialError.openFailed("device") }
        let data = Data(string.utf8)
        let count = data.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, data.count) }
        if count < 0 { throw SerialError.openFailed("device") }
    }

    private func readResponse(timeout: TimeInterval) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            var pollfdValue = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            if poll(&pollfdValue, 1, 50) > 0 {
                let amount = Darwin.read(descriptor, &buffer, buffer.count)
                if amount > 0 { data.append(contentsOf: buffer[0..<amount]) }
                // Firmware commonly terminates replies with `ch> ` (note the
                // trailing space), while some releases use `ch>` or append a
                // line ending. Do not require the prompt to be the final bytes.
                if data.range(of: Data("ch>".utf8)) != nil {
                    return String(decoding: data, as: UTF8.self)
                }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw SerialError.timeout
    }
}

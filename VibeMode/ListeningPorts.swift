import Foundation

/// A user process that is listening on a local TCP port (typical of Vite, Next,
/// Rails, Docker-published ports, language servers, etc.).
struct ListeningProcess: Equatable, Identifiable {
    var id: String { "\(pid)-\(port)-\(command)" }
    let pid: Int32
    let command: String
    let address: String
    let port: String

    var shortLabel: String {
        "\(command):\(port)"
    }
}

enum ListeningPorts {
    static func current() -> [ListeningProcess] {
        let fields = ProcessRunner.run(
            "/usr/sbin/lsof",
            ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]
        )
        let parsedFields = parseLsofFields(fields.stdout)
        if !parsedFields.isEmpty {
            return parsedFields
        }
        let text = ProcessRunner.run(
            "/usr/sbin/lsof",
            ["-nP", "-iTCP", "-sTCP:LISTEN"]
        )
        return parseLsof(text.stdout)
    }

    /// `lsof -F pcn` records: `p<pid>`, `c<command>`, `n<host:port>`.
    static func parseLsofFields(_ output: String) -> [ListeningProcess] {
        var pid: Int32?
        var command: String?
        var results: [ListeningProcess] = []
        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            guard let flag = line.first else { continue }
            let rest = String(line.dropFirst())
            switch flag {
            case "p":
                pid = Int32(rest)
                command = nil
            case "c":
                command = rest
            case "n":
                if let pid, let command {
                    results.append(make(pid: pid, command: command, address: rest))
                }
            default:
                break
            }
        }
        return unique(results)
    }

    /// Parse default `lsof` text. Kept as a pure function so allowlist logic
    /// can be checked without IOKit.
    static func parseLsof(_ output: String) -> [ListeningProcess] {
        let lines = output.split(whereSeparator: \.isNewline)
        var results: [ListeningProcess] = []
        for line in lines {
            let raw = String(line)
            if raw.hasPrefix("COMMAND") { continue }
            guard raw.contains("(LISTEN)") else { continue }
            let withoutListen = raw.replacingOccurrences(of: " (LISTEN)", with: "")
            let cols = withoutListen.split(whereSeparator: \.isWhitespace).map(String.init)
            guard cols.count >= 9, let pid = Int32(cols[1]) else { continue }
            let command = cols[0]
            let address = cols.last ?? ""
            results.append(make(pid: pid, command: command, address: address))
        }
        return unique(results)
    }

    static func parseSleepDisabled(_ text: String) -> Bool? {
        PowerSnapshot.parseSleepDisabled(text)
    }

    private static func make(pid: Int32, command: String, address: String) -> ListeningProcess {
        let port = address.split(separator: ":").last.map(String.init) ?? address
        return ListeningProcess(pid: pid, command: command, address: address, port: port)
    }

    private static func unique(_ items: [ListeningProcess]) -> [ListeningProcess] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}

struct ProcessResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

enum ProcessRunner {
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval = 8) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ProcessResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}

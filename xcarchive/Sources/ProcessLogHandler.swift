import Foundation

public struct RunProcessError: Error, CustomStringConvertible {
    public let message: String
    public let terminationStatus: Int32

    public var description: String {
        message
    }
}

public protocol ProcessLogHandler {
    func onRun()
    func onTerminate(output: String, error: String)
    func onWriteLine(_ line: String, fromErrorStream: Bool)
}

struct DefaultProcessLogHandler: ProcessLogHandler {
    let process: Process

    func onRun() {
        let escapedArgs = (process.arguments ?? []).map { arg -> String in
            if arg.contains(" ") {
                return "\"\(arg)\""
            } else {
                return arg
            }
        }
        print("run \(process.executableURL?.path ?? "?") " + escapedArgs.joined(separator: " "))
    }

    func onTerminate(output: String, error: String) {
        if process.terminationStatus == 0, !error.isEmpty {
            print("error output: \(error)")
        }
    }

    func onWriteLine(_ line: String, fromErrorStream: Bool) {}
}

extension Process {
    public static var disableLogging = false

    public static var logHandler = { (process: Process) -> ProcessLogHandler in
        DefaultProcessLogHandler(process: process)
    }

    @discardableResult
    public static func run(
        _ path: String,
        args: [String],
        currentDirectoryURL: URL? = nil,
        additionalEnvironmentValues: [String: String] = [:],
        disableLogging: Bool = false
    ) throws -> String {

        let disableLogging = disableLogging || Self.disableLogging

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if let currentDirectoryURL = currentDirectoryURL {
            process.currentDirectoryURL = currentDirectoryURL.absoluteURL
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let commonPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        var env = ProcessInfo.processInfo.environment

        env["PATH"] = {
            if let envPath = ProcessInfo.processInfo.environment["PATH"] {
                return envPath.appending(":" + commonPaths.joined(separator: ":"))
            } else {
                return commonPaths.joined(separator: ":")
            }
        }()

        for (key, value) in additionalEnvironmentValues {
            env[key] = value
        }

        process.environment = env

        let logHandler = disableLogging ? nil : Self.logHandler(process)

        logHandler?.onRun()

        try process.run()

        var outputReader = StringReader()
        var errorReader = StringReader()

        let group = DispatchGroup()

        group.enter()
        group.enter()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData

            guard !data.isEmpty else {
                outputPipe.fileHandleForReading.readabilityHandler = nil

                if let logHandler {
                    for line in outputReader.readLines(finish: true) {
                        logHandler.onWriteLine(line, fromErrorStream: false)
                    }
                }

                group.leave()
                return
            }

            outputReader.append(data)

            if let logHandler {
                for line in outputReader.readLines(finish: false) {
                    logHandler.onWriteLine(line, fromErrorStream: false)
                }
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData

            guard !data.isEmpty else {
                errorPipe.fileHandleForReading.readabilityHandler = nil

                if let logHandler {
                    for line in errorReader.readLines(finish: true) {
                        logHandler.onWriteLine(line, fromErrorStream: true)
                    }
                }

                group.leave()
                return
            }

            errorReader.append(data)

            if let logHandler {
                for line in errorReader.readLines(finish: false) {
                    logHandler.onWriteLine(line, fromErrorStream: true)
                }
            }
        }

        process.waitUntilExit()
        group.wait()

        let output = String(decoding: outputReader.data, as: UTF8.self)
        let error = String(decoding: errorReader.data, as: UTF8.self)

        logHandler?.onTerminate(output: output, error: error)

        if process.terminationStatus != 0 {
            throw RunProcessError(message: error, terminationStatus: process.terminationStatus)
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct StringReader: IteratorProtocol {
    var data = Data()
    var index = 0
    var scalars: [Unicode.Scalar] = []
    var lines: [String] = []

    mutating func append(_ data: Data) {
        self.data.append(data)

        var utf8Decoder = UTF8()

        loop: while true {
            switch utf8Decoder.decode(&self) {
            case .scalarValue("\n"):
                var line = ""
                line.unicodeScalars.append(contentsOf: scalars)
                lines.append(line)
                scalars.removeAll(keepingCapacity: true)

            case let .scalarValue(scalar):
                scalars.append(scalar)

            case .emptyInput:
                break loop

            case .error:
                break loop
            }
        }
    }

    mutating func readLines(finish: Bool) -> [String] {
        if finish, !scalars.isEmpty {
            var line = ""
            line.unicodeScalars.append(contentsOf: scalars)
            lines.append(line)
            scalars.removeAll(keepingCapacity: true)
        }

        let result = lines
        lines = []
        return result
    }

    mutating func next() -> UInt8? {
        guard index < data.endIndex else {
            return nil
        }

        let result = data[index]
        index += 1
        return result
    }
}

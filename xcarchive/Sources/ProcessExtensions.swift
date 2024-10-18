import Foundation
import Logging
import RegexBuilder
import XcbeautifyLib

final class ProcessLogger: ProcessLogHandler {
    private var buffer: [String] = []
    private var rawLogsFileHandle: FileHandle?
    private var warningsFileHandle: FileHandle?
    private var maxBufferSize: Int { 10 }
    private var coloredLogs: Bool
    private var derivedDataPath: String?

    private var currentLineIndex = 0

    private var warnings = [WarningPath: [Issue]]()

    private lazy var parser = Parser(
        colored: coloredLogs,
        renderer: .terminal,
        preserveUnbeautifiedLines: false,
        additionalLines: { [weak self] in
            guard let self else {
                return nil
            }

            guard buffer.indices.contains(currentLineIndex) else {
                preconditionFailure("Parser requested more line than buffer size. Please increase `maxBufferSize`")
            }

            defer { currentLineIndex += 1 }

            return buffer[currentLineIndex]
        }
    )

    private let outputHandler: _OutputHandler

    deinit {
        [rawLogsFileHandle, warningsFileHandle].forEach { fileHandle in
            try? fileHandle?.synchronize()
            try? fileHandle?.close()
        }
    }

    init(
        label: String? = nil,
        rawLogsFilePath: String? = nil,
        warningsLogsFilePath: String? = nil,
        coloredLogs: Bool,
        derivedDataPath: String?
    ) {
        self.coloredLogs = coloredLogs
        self.derivedDataPath = derivedDataPath

        if let rawLogsFilePath {
            if FileManager.default.fileExists(atPath: rawLogsFilePath) {
                try? FileManager.default.removeItem(atPath: rawLogsFilePath)
            }

            FileManager.default.createFile(atPath: rawLogsFilePath, contents: nil)

            let url = URL(filePath: rawLogsFilePath)
            rawLogsFileHandle = try? FileHandle(forUpdating: url.absoluteURL)
        }

        if let warningsLogsFilePath {
            if FileManager.default.fileExists(atPath: warningsLogsFilePath) {
                try? FileManager.default.removeItem(atPath: warningsLogsFilePath)
            }

            FileManager.default.createFile(atPath: warningsLogsFilePath, contents: nil)

            let url = URL(filePath: warningsLogsFilePath)
            warningsFileHandle = try? FileHandle(forUpdating: url.absoluteURL)
        }

        self.outputHandler = _OutputHandler(logger: Logger(label: label ?? "XcodeBuild"))
    }

    func onRun() {}

    func onTerminate(output: String, error: String) {
        while !buffer.isEmpty {
            if let formattedLine = formatNextLine() {
                outputHandler.write(parser.outputType, formattedLine)
            }
        }

        if let formattedSummary = parser.formattedSummary() {
            outputHandler.write(.result, formattedSummary)
        }

        guard let warningsFileHandle else {
            return
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: warnings, options: .prettyPrinted) {
            try? warningsFileHandle.write(contentsOf: jsonData)
        }
    }

    func onWriteLine(_ line: String, fromErrorStream: Bool) {
        guard !fromErrorStream else {
            return
        }

        try? rawLogsFileHandle?.write(contentsOf: Data((line + "\n").utf8))

        guard buffer.count == maxBufferSize else {
            buffer.append(line)
            return
        }

        if let formattedLine = formatNextLine() {
            outputHandler.write(parser.outputType, formattedLine)

            if parser.outputType == .warning {
                writeWarning(formattedLine)
            }
        }

        buffer.append(line)
    }

    private func formatNextLine() -> String? {
        guard !buffer.isEmpty else {
            return nil
        }

        let line = buffer.removeFirst()

        currentLineIndex = 0

        return parser.parse(line: line)
    }

    private func writeWarning(_ formattedLine: String) {
        if let derivedDataPath, formattedLine.contains(derivedDataPath) {
            return
        }

        let regex = Regex {
            ".swift:"
            OneOrMore(.digit)
            ":"
            OneOrMore(.digit)
            ":"
        }

        if let match = try? regex.firstMatch(in: formattedLine),
           let range = formattedLine.range(of: String(match.0)),
           let pathRange = formattedLine.range(of: FileManager.default.currentDirectoryPath)
        {
            let warningPath = String(formattedLine[pathRange.upperBound ..< range.upperBound])
            let warningValue = String(formattedLine[range.upperBound...].dropFirst())

            warnings[
                warningPath,
                default: []
            ].append(warningValue.replacingOccurrences(
                of: FileManager.default.currentDirectoryPath,
                with: ""
            ))
        }
    }
}

private struct _OutputHandler {
    let logger: Logger

    func write(_ type: OutputType, _ content: String) {
        switch type {
        case .warning:
            logger.warning("\(content)")
        case .error:
            logger.error("\(content)")
        default:
            logger.info("\(content)")
        }
    }
}

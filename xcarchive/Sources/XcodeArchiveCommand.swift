import ArgumentParser
import Foundation

public typealias WarningPath = String
public typealias Issue = String

@main
struct XcodeArchiveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcode-archive",
        abstract: "Собирает архив из xcodeproj/xcworkspace"
    )

    @Option(help: "Путь до xcworkspace файла.")
    var workspacePath: String?

    @Option(help: "Путь до xcodeproj файла. Можно не указывать, если указан --workspace-path.")
    var projectPath: String?

    @Option(help: "Путь, по которому должен быть сохранен xcarchive файл.")
    var archivePath: String

    @Option(help: "Имя схемы в проекте.")
    var scheme: String

    @Option(help: "Имя сборочной конфигурации. Например, Debug или Release.", completion: .list(["Debug", "Release"]))
    var configuration = "Release"

    @Option(help: "Определяет тип устройства, под которое будет сборка приложения.")
    var destination = "generic/platform=iOS"

    @Option(help: "Путь к DerivedData.")
    var derivedDataPath: String?

    @Option(help: "Путь к файлу, в который будут записаны логи (без обработки форматтером)")
    var rawLogsFilePath: String?

    @Option(help: "Путь к файлу, в который будут записаны отформативанные warning-и")
    var warningsLogsFilePath: String?

    @Option(help: "Формат дебажной информации.", completion: .list(["stabs", "dwarf", "dwarf-with-dsym"]))
    var debugInformationFormat: String?

    @Flag(help: "Включить раскрашенные логи")
    var coloredLogs = false

    private var arguments: [String] {
        get throws {
            var arguments = [String]()

            arguments = [
                "xcodebuild",
                "archive",
                "-archivePath",
                "\(archivePath)",
                "-scheme",
                "\(scheme)",
                "-configuration",
                "\(configuration)",
                "-destination",
                "\(destination)"
            ]

            if let workspacePath, !workspacePath.isEmpty {
                arguments += ["-workspace", workspacePath]
            } else if let projectPath, !projectPath.isEmpty {
                arguments += ["-project", projectPath]
            } else {
                throw NeitherWorkspacePathNorProjectPathAreSpecifiedError()
            }

            if let derivedDataPath, !derivedDataPath.isEmpty {
                arguments += ["-derivedDataPath", derivedDataPath]
            }

            if let debugInformationFormat, !debugInformationFormat.isEmpty {
                arguments.append("DEBUG_INFORMATION_FORMAT=\(debugInformationFormat)")
            }

            return arguments
        }
    }

    func run() throws {
        let processLogger = ProcessLogger(
            rawLogsFilePath: rawLogsFilePath,
            warningsLogsFilePath: warningsLogsFilePath,
            coloredLogs: coloredLogs,
            derivedDataPath: derivedDataPath
        )

        Process.logHandler = { _ in
            processLogger
        }

        try Process.run("/usr/bin/xcrun", args: arguments)
    }
}

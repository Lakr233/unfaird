import ArgumentParser
import Foundation
import UnfairKit
import Vapor

struct UnfairDaemonCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "UnfairDaemon",
        abstract: "Serve unfaird and run local IPA package processing.",
        subcommands: [Serve.self, Package.self],
        defaultSubcommand: Serve.self
    )
}

UnfairDaemonCommand.main()

struct Serve: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run the unfaird HTTP service.")

    @ArgumentParser.Option(help: "Hostname to bind.")
    var hostname = "127.0.0.1"

    @ArgumentParser.Option(help: "Port to bind.")
    var port = 6347

    func run() throws {
        try checkSupportedOS()

        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = Application(env)
        defer { app.shutdown() }

        try configure(app, hostname: hostname, port: port)
        try app.run()
    }
}

struct Package: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Process an IPA package.")

    @ArgumentParser.Option(name: .customLong("input"), help: "Input .ipa path.")
    var input: String

    @ArgumentParser.Option(name: .customLong("output"), help: "Output .ipa path.")
    var output: String

    @ArgumentParser.Flag(name: .long, help: "Show detailed UnfairKit logs.")
    var verbose = false

    func run() throws {
        try PackageProcessor(logger: UnfairLogger(verbose: verbose) { message in
            print(message)
        }).process(
            input: fileURL(input),
            output: fileURL(output)
        )
    }
}

private func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
}

private func checkSupportedOS() throws {
    let supportedMaximumVersion = OperatingSystemVersion(majorVersion: 11, minorVersion: 2, patchVersion: 3)
    let currentVersion = ProcessInfo.processInfo.operatingSystemVersion
    guard currentVersion.isGreater(than: supportedMaximumVersion) == false else {
        let message = "unfaird supports macOS 11.2.3 or earlier; current macOS is \(currentVersion.displayString)"
        throw ValidationError(message)
    }
}

private extension OperatingSystemVersion {
    func isGreater(than other: OperatingSystemVersion) -> Bool {
        if majorVersion != other.majorVersion {
            return majorVersion > other.majorVersion
        }
        if minorVersion != other.minorVersion {
            return minorVersion > other.minorVersion
        }
        return patchVersion > other.patchVersion
    }

    var displayString: String {
        "\(majorVersion).\(minorVersion).\(patchVersion)"
    }
}

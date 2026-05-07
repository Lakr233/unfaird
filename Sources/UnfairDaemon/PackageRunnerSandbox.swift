import Foundation
import Vapor

enum PackageRunnerSandbox {
    static let sandboxExecPath = "/usr/bin/sandbox-exec"

    static func packageWorkingDirectory(for jobID: UUID) throws -> URL {
        try packageTemporaryRoot()
            .appendingPathComponent(jobID.uuidString.lowercased(), isDirectory: true)
            .standardizedFileURL
    }

    static func writeProfile(jobDirectory: URL) throws -> URL {
        guard FileManager.default.isExecutableFile(atPath: sandboxExecPath) else {
            throw Abort(.internalServerError, reason: "sandbox-exec missing")
        }

        let runtimeTempRoot = try runtimeTemporaryContainerRoot()
        let processTempRoot = processTemporaryContainerRoot()
        try FileManager.default.createDirectory(at: try packageTemporaryRoot(), withIntermediateDirectories: true)

        let writableFilters = pathFilters(for: [jobDirectory, runtimeTempRoot, processTempRoot])
            .map { "    \($0)" }
            .joined(separator: "\n")

        let profile = """
        (version 1)
        (deny default)
        (allow file-read*)
        (allow file-write*
        \(writableFilters)
        )
        (allow process-exec)
        (allow process-fork)
        (allow signal)
        (allow sysctl-read)
        (allow mach-lookup)
        """

        let profileURL = jobDirectory.appendingPathComponent("sandbox.sb")
        try profile.write(to: profileURL, atomically: true, encoding: .utf8)
        return profileURL
    }

    private static func runtimeTemporaryContainerRoot() throws -> URL {
        try RuntimeEnvironment.resolveTemporaryDirectory()
            .deletingLastPathComponent()
            .standardizedFileURL
    }

    private static func processTemporaryContainerRoot() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .deletingLastPathComponent()
            .standardizedFileURL
    }

    private static func packageTemporaryRoot() throws -> URL {
        try runtimeTemporaryContainerRoot()
            .appendingPathComponent("X", isDirectory: true)
            .appendingPathComponent("unfair", isDirectory: true)
            .standardizedFileURL
    }

    private static func pathFilters(for urls: [URL]) -> [String] {
        var filters: [String] = []
        var seen = Set<String>()

        for url in urls {
            for path in canonicalPaths(for: url) where seen.insert(path).inserted {
                filters.append("(literal \(quoted(path)))")
                filters.append("(subpath \(quoted(path)))")
            }
        }

        return filters
    }

    private static func canonicalPaths(for url: URL) -> [String] {
        let candidates = [
            url.standardizedFileURL.path,
            URL(fileURLWithPath: url.standardizedFileURL.path).resolvingSymlinksInPath().path,
        ].flatMap(varPathAliases)

        var paths: [String] = []
        var seen = Set<String>()
        for path in candidates where seen.insert(path).inserted {
            paths.append(path)
        }
        return paths
    }

    private static func varPathAliases(for path: String) -> [String] {
        if path == "/var" {
            return [path, "/private/var"]
        }
        if path.hasPrefix("/var/") {
            return [path, "/private" + path]
        }
        if path == "/private/var" {
            return [path, "/var"]
        }
        if path.hasPrefix("/private/var/") {
            return [path, String(path.dropFirst("/private".count))]
        }
        return [path]
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

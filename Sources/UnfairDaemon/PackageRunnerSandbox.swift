import Foundation
import Vapor

enum PackageRunnerSandbox {
    static let sandboxExecPath = "/usr/bin/sandbox-exec"

    static func writeProfile(jobDirectory: URL) throws -> URL {
        guard FileManager.default.isExecutableFile(atPath: sandboxExecPath) else {
            throw Abort(.internalServerError, reason: "sandbox-exec missing")
        }

        let temporaryDirectory = processTemporaryDirectory()
        let tempRoot = packageTemporaryRoot()
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let writableFilters = pathFilters(for: [jobDirectory, temporaryDirectory, tempRoot])
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

    private static func processTemporaryDirectory() -> URL {
        let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: tmpDir, isDirectory: true).standardizedFileURL
    }

    private static func packageTemporaryRoot() -> URL {
        processTemporaryDirectory()
            .deletingLastPathComponent()
            .appendingPathComponent("X", isDirectory: true)
            .appendingPathComponent("unfair", isDirectory: true)
            .standardizedFileURL
    }

    private static func pathFilters(for urls: [URL]) -> [String] {
        var filters: [String] = []
        var seen = Set<String>()

        for url in urls {
            for path in canonicalPaths(for: url) where seen.insert(path).inserted {
                filters.append("(subpath \(quoted(path)))")
            }
        }

        return filters
    }

    private static func canonicalPaths(for url: URL) -> [String] {
        let standardized = url.standardizedFileURL.path
        let resolved = URL(fileURLWithPath: standardized).resolvingSymlinksInPath().path
        if standardized == resolved {
            return [standardized]
        }
        return [standardized, resolved]
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

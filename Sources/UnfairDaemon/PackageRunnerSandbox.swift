import Foundation
import Vapor

enum PackageRunnerSandbox {
    static let sandboxExecPath = "/usr/bin/sandbox-exec"

    static func writeProfile(jobDirectory: URL) throws -> URL {
        guard FileManager.default.isExecutableFile(atPath: sandboxExecPath) else {
            throw Abort(.internalServerError, reason: "sandbox-exec missing")
        }

        let tempRoot = packageTemporaryRoot()
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let writableFilters = pathFilters(for: [jobDirectory, tempRoot])
            .map { "    \($0)" }
            .joined(separator: "\n")

        let profile = """
        (version 1)
        (deny default)
        (allow process*)
        (allow signal)
        (allow sysctl-read)
        (allow mach-lookup)
        (allow file-read*)
        (allow file-write*
        \(writableFilters)
        )
        """

        let profileURL = jobDirectory.appendingPathComponent("sandbox.sb")
        try profile.write(to: profileURL, atomically: true, encoding: .utf8)
        return profileURL
    }

    private static func packageTemporaryRoot() -> URL {
        let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: tmpDir, isDirectory: true)
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

import Darwin
import Dispatch
import Foundation
import Vapor

struct DecryptService {
    static let maxUploadBytes: Int64 = 8 * 1024 * 1024 * 1024
    private static let downloadTTLSeconds = 3600
    private static let cleanupIntervalSeconds = 60
    private static let diskReserveBytes: Int64 = 16 * 1024 * 1024 * 1024
    private static let workDirectoryPath = "/var/tmp/unfaird/jobs"
    private static let runnerTimeoutSeconds = 15 * 60
    private static let cleanupLock = NSLock()
    private static var cleanupTimer: DispatchSourceTimer?

    static func prepareWorkDirectoryForStartup() throws {
        try FileManager.default.createDirectory(
            at: workDirectory(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try removeJobDirectories()
    }

    static func startExpiredJobCleanup() {
        cleanupLock.lock()
        defer { cleanupLock.unlock() }
        guard cleanupTimer == nil else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "wiki.qaq.unfaird.job-cleanup"))
        timer.schedule(
            deadline: .now() + .seconds(cleanupIntervalSeconds),
            repeating: .seconds(cleanupIntervalSeconds)
        )
        timer.setEventHandler {
            cleanupExpiredJobs()
        }
        cleanupTimer = timer
        timer.resume()
    }

    func run(_ upload: DecryptUpload) throws -> DecryptResponse {
        try validate(upload)

        let job = try Self.createJob()
        let reservation = try DecryptTaskGate.shared.reserve(
            workDirectory: Self.workDirectory(),
            bytesPerTask: Self.diskReserveBytes
        )
        defer { reservation.release() }

        try write(upload, to: job.inputURL)
        try writeMetadata(job.metadata, in: job.directoryURL)

        let sandboxProfileURL = try PackageRunnerSandbox.writeProfile(jobDirectory: job.directoryURL)
        let result = try runDecryptRunner(for: job, sandboxProfileURL: sandboxProfileURL)
        return response(for: result, job: job)
    }

    static func validatedOutputURL(for id: UUID) throws -> URL {
        let directory = try existingJobDirectory(for: id)
        let metadata = try readMetadata(in: directory)
        guard metadata.validateUntil >= currentTimestamp() else {
            removeJobDirectory(directory)
            throw Abort(.gone, reason: "download url expired")
        }
        return directory.appendingPathComponent("output.ipa")
    }

    private func runDecryptRunner(for job: DecryptJob, sandboxProfileURL: URL) throws -> PosixSpawnResult {
        let arguments = [
            "package",
            "--input", job.inputURL.path,
            "--output", job.outputURL.path,
            "--verbose",
        ]
        return try PosixSpawn.run(
            executablePath: Self.currentExecutablePath(),
            arguments: arguments,
            workingDirectory: job.directoryURL,
            sandboxProfileURL: sandboxProfileURL,
            timeoutSeconds: Self.runnerTimeoutSeconds
        )
    }

    private func response(for result: PosixSpawnResult, job: DecryptJob) -> DecryptResponse {
        DecryptResponse(
            exit: DecryptExit(
                code: result.exitCode,
                stdout: result.stdoutString,
                stderr: result.stderrString,
                downloadURL: job.downloadURL,
                validateUntil: job.validateUntil
            )
        )
    }

    private static func createJob() throws -> DecryptJob {
        let id = UUID()
        let directory = workDirectory().appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return DecryptJob(
            id: id,
            directoryURL: directory,
            validateUntil: validateUntilTimestamp()
        )
    }

    private static func existingJobDirectory(for id: UUID) throws -> URL {
        let directory = workDirectory().appendingPathComponent(id.uuidString, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw Abort(.notFound, reason: "job missing")
        }
        return directory
    }

    private static func workDirectory() -> URL {
        URL(fileURLWithPath: workDirectoryPath, isDirectory: true)
    }

    private static func cleanupExpiredJobs() {
        do {
            try cleanupExpiredJobDirectories(now: currentTimestamp())
        } catch {
            fputs("unfaird job cleanup failed: \(error)\n", stderr)
        }
    }

    private static func cleanupExpiredJobDirectories(now: Int) throws {
        try FileManager.default.createDirectory(
            at: workDirectory(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let directories = try FileManager.default.contentsOfDirectory(
            at: workDirectory(),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for directory in directories where try isDirectory(directory) {
            guard let metadata = try? readMetadata(in: directory) else {
                continue
            }
            if metadata.validateUntil < now {
                removeJobDirectory(directory)
            }
        }
    }

    private static func removeJobDirectories() throws {
        let directories = try FileManager.default.contentsOfDirectory(
            at: workDirectory(),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for directory in directories where try isDirectory(directory) {
            removeJobDirectory(directory)
        }
    }

    private static func isDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true
    }

    private static func removeJobDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func validateUntilTimestamp() -> Int {
        currentTimestamp() + downloadTTLSeconds
    }

    private static func currentTimestamp() -> Int {
        Int(Date().timeIntervalSince1970)
    }

    private static func currentExecutablePath() -> String {
        let path = CommandLine.arguments[0]
        if path.hasPrefix("/") {
            return path
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path)
            .standardizedFileURL
            .path
    }

    private func validate(_ upload: DecryptUpload) throws {
        let fileCount = upload.ipa == nil ? 0 : 1
        let urlCount = upload.sourceURLString == nil ? 0 : 1
        guard fileCount + urlCount == 1 else {
            throw Abort(.badRequest, reason: "provide one ipa file or one ipa_url")
        }

        if let file = upload.ipa {
            try validateIPA(filename: file.filename)
            guard Int64(file.data.readableBytes) <= Self.maxUploadBytes else {
                throw Abort(.payloadTooLarge, reason: "upload limit is 8GB")
            }
        }

        if let urlString = upload.sourceURLString {
            _ = try RemoteIPAURL.parse(urlString)
        }
    }

    private func validateIPA(filename: String) throws {
        guard filename.lowercased().hasSuffix(".ipa") else {
            throw Abort(.badRequest, reason: "ipa file required")
        }
    }

    private func write(_ upload: DecryptUpload, to url: URL) throws {
        if let file = upload.ipa {
            try write(file, to: url)
            return
        }
        if let urlString = upload.sourceURLString {
            try downloadIPA(from: RemoteIPAURL.parse(urlString), to: url)
            return
        }
        throw Abort(.badRequest, reason: "ipa source required")
    }

    private func write(_ file: File, to url: URL) throws {
        var buffer = file.data
        guard let data = buffer.readData(length: buffer.readableBytes) else {
            throw Abort(.badRequest, reason: "empty upload")
        }
        guard Int64(data.count) <= Self.maxUploadBytes else {
            throw Abort(.payloadTooLarge, reason: "upload limit is 8GB")
        }
        try data.write(to: url, options: .atomic)
    }

    private func downloadIPA(from sourceURL: URL, to destination: URL) throws {
        let delegate = LimitedDownloadDelegate(destination: destination, maxBytes: Self.maxUploadBytes)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = TimeInterval(Self.runnerTimeoutSeconds)
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: delegateQueue)
        defer {
            session.invalidateAndCancel()
        }

        var request = URLRequest(url: sourceURL)
        request.httpMethod = "GET"
        request.setValue("unfaird/1.0", forHTTPHeaderField: "User-Agent")
        session.downloadTask(with: request).resume()
        try delegate.wait()
    }

    private func writeMetadata(_ metadata: DecryptJobMetadata, in directory: URL) throws {
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: Self.metadataURL(in: directory), options: .atomic)
    }

    private static func readMetadata(in directory: URL) throws -> DecryptJobMetadata {
        let data = try Data(contentsOf: metadataURL(in: directory))
        return try JSONDecoder().decode(DecryptJobMetadata.self, from: data)
    }

    private static func metadataURL(in directory: URL) -> URL {
        directory.appendingPathComponent("metadata.json")
    }

}

enum RemoteIPAURL {
    static func parse(_ rawValue: String) throws -> URL {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false,
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false,
              let url = components.url,
              url.isFileURL == false
        else {
            throw Abort(.badRequest, reason: "valid http or https ipa_url required")
        }
        return url
    }
}

private final class DecryptTaskGate {
    static let shared = DecryptTaskGate()

    private let lock = NSLock()
    private var runningTasks = 0

    func reserve(workDirectory: URL, bytesPerTask: Int64) throws -> DecryptTaskReservation {
        lock.lock()
        defer { lock.unlock() }

        let available = try Self.availableBytes(at: workDirectory)
        let required = Int64(runningTasks + 1) * bytesPerTask
        guard available >= required else {
            throw Abort(.insufficientStorage, reason: "need 16GB free per running decrypt task")
        }

        runningTasks += 1
        return DecryptTaskReservation(gate: self)
    }

    fileprivate func release() {
        lock.lock()
        runningTasks = max(0, runningTasks - 1)
        lock.unlock()
    }

    private static func availableBytes(at url: URL) throws -> Int64 {
        var stats = statfs()
        guard statfs(url.path, &stats) == 0 else {
            throw Abort(.internalServerError, reason: "free space check failed: \(String(cString: strerror(errno)))")
        }
        return Int64(stats.f_bavail) * Int64(stats.f_bsize)
    }
}

private struct DecryptTaskReservation {
    private weak var gate: DecryptTaskGate?

    fileprivate init(gate: DecryptTaskGate) {
        self.gate = gate
    }

    fileprivate func release() {
        gate?.release()
    }
}

private final class LimitedDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let maxBytes: Int64
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var completed = false
    private var result: Result<Void, Error>?
    private var pendingError: Error?

    init(destination: URL, maxBytes: Int64) {
        self.destination = destination
        self.maxBytes = maxBytes
    }

    func wait() throws {
        semaphore.wait()
        switch result {
        case .success:
            return
        case .failure(let error):
            throw error
        case nil:
            throw Abort(.internalServerError, reason: "download finished without result")
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesWritten > maxBytes {
            pendingError = Abort(.payloadTooLarge, reason: "remote ipa limit is 8GB")
            downloadTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            pendingError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let http = task.response as? HTTPURLResponse,
           (200...299).contains(http.statusCode) == false {
            cleanupDestination()
            finish(.failure(Abort(.badGateway, reason: "ipa_url returned HTTP \(http.statusCode)")))
            return
        }
        if let expectedLength = task.response?.expectedContentLength,
           expectedLength > maxBytes {
            cleanupDestination()
            finish(.failure(Abort(.payloadTooLarge, reason: "remote ipa limit is 8GB")))
            return
        }
        if let pendingError = pendingError {
            cleanupDestination()
            finish(.failure(pendingError))
            return
        }
        if let error = error {
            cleanupDestination()
            finish(.failure(error))
            return
        }
        finish(.success(()))
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard completed == false else {
            return
        }
        completed = true
        self.result = result
        semaphore.signal()
    }

    private func cleanupDestination() {
        try? FileManager.default.removeItem(at: destination)
    }
}

private struct DecryptJob {
    let id: UUID
    let directoryURL: URL
    let validateUntil: Int

    var inputURL: URL {
        directoryURL.appendingPathComponent("input.ipa")
    }

    var outputURL: URL {
        directoryURL.appendingPathComponent("output.ipa")
    }

    var downloadURL: String {
        "/api/v1/decrypt/\(id.uuidString)/output"
    }

    var metadata: DecryptJobMetadata {
        DecryptJobMetadata(validateUntil: validateUntil)
    }
}

import Vapor

func configure(_ app: Application, hostname: String = "127.0.0.1", port: Int = 8080) throws {
    try DecryptService.prepareWorkDirectoryForStartup()
    DecryptService.startExpiredJobCleanup()

    app.http.server.configuration.hostname = hostname
    app.http.server.configuration.port = port
    app.routes.defaultMaxBodySize = "8gb"

    try routes(app)
}

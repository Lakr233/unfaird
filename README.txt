UNFAIRD

Licensed under MIT, requires macOS <= 11.2.3 for runtime decrypt operations.

swift run UnfairDaemon --help for more details.

Build:
  swift build

Run:
  swift run UnfairDaemon serve --hostname 127.0.0.1 --port 8080

Install LaunchDaemon:
  make install

Decrypt:
  curl -sS -F "ipa=@/path/to/app.ipa" http://127.0.0.1:8080/api/v1/decrypt

Download:
  curl -L -o output.ipa http://127.0.0.1:8080/api/v1/decrypt/<job-id>/output

Use this project only with IPAs you own or have permission to analyze.

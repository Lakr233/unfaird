unfaird

Small local HTTP service for IPA processing.

Requires macOS 11.2.3 or earlier for runtime decrypt operations.

Build:
  swift build

Run:
  swift run UnfairDaemon serve

Health:
  curl http://127.0.0.1:6347/health

Decrypt:
  curl -sS -F "ipa=@/path/to/app.ipa" http://127.0.0.1:6347/api/v1/decrypt

Download:
  curl -L -o output.ipa http://127.0.0.1:6347/api/v1/decrypt/<job-id>/output

CLI help:
  swift run UnfairDaemon --help

Use this project only with IPAs you own or have permission to analyze.

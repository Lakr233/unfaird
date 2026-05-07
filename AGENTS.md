# AGENTS.md

## Project

`unfaird` is a SwiftPM 5.4 Vapor daemon. It accepts IPA decrypt requests over HTTP and runs the local UnfairKit runner through POSIX spawn.

## Build

```bash
swift build
```

Run locally:

```bash
swift build
swift run UnfairDaemon serve
```

## API

Decrypt an IPA:

```bash
curl -sS -F "ipa=@/path/to/app.ipa" \
  http://127.0.0.1:6347/api/v1/decrypt
```

Decrypt jobs always run with verbose UnfairKit logs enabled.

The response includes `exit.code`, `exit.stdout`, `exit.stderr`, `exit.download_url`, and `exit.validate_until`.

Download a successful output:

```bash
curl -L -o output.ipa http://127.0.0.1:6347/api/v1/decrypt/<job-id>/output
```

## Decrypt Runtime Invariants

These are fixed runtime contracts.

- The UnfairKit extraction directory must be `$TMPDIR/../X/unfair/{UDID}`.
- Resolve `$TMPDIR` dynamically at process runtime. Launchd can change it across daemon starts.
- Do not override, rewrite, or sandbox-remap `TMPDIR` for decrypt/package runs.
- Sandbox profiles must allow the existing `$TMPDIR` and `$TMPDIR/../X/unfair` paths instead of moving UnfairKit work elsewhere.
- Preserve mtime and chmod from the IPA entries during extraction and when replacing entries in the output IPA.
- Keep temporary `.sinf` copies metadata-preserving.

## Deploy

Use the scripts in `deploy/` for install and service management.

Keep tracked docs and agent notes free of private deployment details:

- Do not write real hostnames, LAN IPs, user accounts, passwords, machine names, live process IDs, or live service status into docs.
- Prefer placeholders such as `user@host`, `/path/to/app.ipa`, and `<job-id>` in examples.
- Keep README concise and operational. Avoid promotional language and public-facing deployment detail.

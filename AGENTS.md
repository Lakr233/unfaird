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
swift run UnfairDaemon serve --hostname 127.0.0.1 --port 8080
```

## API

Decrypt an IPA:

```bash
curl -sS -F "ipa=@/path/to/app.ipa" \
  http://127.0.0.1:8080/api/v1/decrypt
```

Decrypt jobs always run with verbose UnfairKit logs enabled.

The response includes `exit.code`, `exit.stdout`, `exit.stderr`, `exit.download_url`, and `exit.validate_until`.

Download a successful output:

```bash
curl -L -o output.ipa http://127.0.0.1:8080/api/v1/decrypt/<job-id>/output
```

## Decrypt Runtime Invariants

These are fixed runtime contracts.

- The UnfairKit extraction directory must be `$TMPDIR/../X/unfair/{UDID}`.
- Resolve `$TMPDIR` dynamically at process runtime. Launchd can change it across daemon starts.
- Preserve mtime and chmod from the IPA entries during extraction and when replacing entries in the output IPA.
- Keep temporary `.sinf` copies metadata-preserving.

## Deploy

Deployment uses `UNFAIRD_DEPLOY_REMOTE`:

```bash
UNFAIRD_DEPLOY_REMOTE=user@host deploy/deploy.sh
```

The deploy script rsyncs this repo to `${UNFAIRD_DEPLOY_DIR:-unfaird}` under the remote login's home directory and prints the remote install command.

`make install` builds release binaries as the current user and uses `sudo` inside `deploy/install-launchdaemon.sh` for system install steps.

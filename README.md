# <img width="45" alt="blimp_icon_dark" src="https://github.com/user-attachments/assets/d78717f8-c440-424f-a5ed-aae73747c128" /> Blimp
<!-- ALL-CONTRIBUTORS-BADGE:START - Do not remove or modify this section -->
[![All Contributors](https://img.shields.io/badge/all_contributors-4-orange.svg?style=flat-square)](#contributors-)
<!-- ALL-CONTRIBUTORS-BADGE:END -->

Finally, Swift deployment automation for Apple platforms.

Heavily inspired by [fastlane](https://fastlane.tools/).

> Blimp refers to a non-rigid flying ship (like a zeppelin). Rarely used nowadays, it might be slow and clumsy, but still beautiful and gets the job done.

## Disclaimer

This project is still a work in progress but aims to be a native Swift `fastlane` replacement in the future. However, the implementation is already stable enough for Plata to ship our apps with it. If you have questions or issues, just open an issue/discussion and we'll try to help. If you want to contribute, feel free to open a pull request.

----

## Installation

As package dependency:
```swift
dependencies: [
    .package(url: "https://github.com/platacard/blimp.git", from: "0.8.0")
]
```

## Features overview

### What's working

- Archiving and exporting the iOS app
- Authenticating with the App Store Connect API
- Uploading iOS apps to App Store Connect via the modern build upload API and waiting for processing
- Assigning beta groups and sending builds for review
- Inviting developers and beta testers to TestFlight

### What's yet to be implemented

- Testing support for watchOS, macOS, and other less-used platforms

----

## Getting started

Blimp is meant to be a building block in your pipeline, not a final, opinionated solution. It is best used in combination with other packages:

- [cronista](https://github.com/platacard/cronista) — A simple logger
- [corredor](https://github.com/platacard/corredor) — A shell wrapper
- [gito](https://github.com/platacard/gito) — A git wrapper
- [slackito](https://github.com/platacard/slackito) — A Slack API client using result builders
- [dotcontext](https://github.com/platacard/dotcontext) — An environment variables manager that extends .env file functionality

These packages provide a modular way to build your deploy pipeline. But the best part is that they are not required to use blimp. Tweak everything to your liking.

You can try things out by calling the `blimp` CLI via `swift run blimp {command}`, or you can compile the project and use the binary artifact directly.
 
>❗️ Moreover, `blimp` CLI provides an example of how you can use `BlimpKit` in your CLI. We recommend trying out the `swift-argument-parser` package, it works great for us.

### Authenticating

Environment expects 3 variables:

- `APPSTORE_CONNECT_API_ISSUER_ID`
- `APPSTORE_CONNECT_API_KEY_ID`
- `APPSTORE_CONNECT_API_PRIVATE_KEY`

To get the private key, go to https://appstoreconnect.apple.com/access/integrations/api and create your own key. This is also the page to find your private key ID and the issuer ID.

After downloading your private key, you can open the .p8 file containing the private key in any text editor:

```
-----BEGIN PRIVATE KEY-----
FDFDGgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdw...
49AgEGCCqG\...
...
-----END PRIVATE KEY-----
```

Copy the contents and remove all the whitespacesa and newlines, -----BEGIN PRIVATE KEY----- and -----END PRIVATE KEY-----.

Use `export APPSTORE_CONNECT_API_PRIVATE_KEY={bare_key_without_newlines} && ...` locally or create environment variables for your CI provider. JWT token for API client will be created (and recreated on expiration) authomatically if needed variables are in place.

### Running

Using binary artifact:
```bash
swift build -c release
```

Then, you can use the binary artifact directly:
```bash
./build/release/blimp {command}
```

#### Available commands

> Use -h with each command to see all available parameters and their default values.

1. `blimp takeoff {params}` - Archive the project
2. `blimp approach {params}` - Upload the archive to App Store Connect
3. `blimp land {params}` - Assign the build's beta groups and send it to external review
4. `blimp hangar {subcommand} {params}` - Additional checks and operations with App Store Connect API
5. `blimp maintenance {subcommand} {params}` — Manage provisioning profiles, certificates, and devices

## blimp-relay

`blimp-relay` is a small, separately deployable HTTP server that receives [App Store Connect webhooks](https://developer.apple.com/documentation/appstoreconnectapi/webhooks), verifies their HMAC-SHA256 signatures, and relays them to configurable sinks — turn ASC webhooks into GitLab pipeline triggers, or forward them anywhere. The signature verification and payload models are also available as a standalone `WebhookKit` library product if you'd rather embed webhook handling in your own server.

> The relay never needs App Store Connect credentials. It only holds the webhook secret you configured in App Store Connect — deliveries are verified by signature, not by calling back into the ASC API.

Sinks (comma-separated in `SINKS`, executed in order per delivery):

- `log` — logs a one-line summary of each delivery.
- `forward` — POSTs the raw, already-verified body to `FORWARD_URL` (original content type plus an `x-relay-event-type` header).
- `gitlab-pipeline-trigger` — resumes a waiting CI pipeline when a build upload reaches `COMPLETE`/`FAILED`. The upload job stores its state in a GitLab project variable `<PENDING_VAR_PREFIX><uploadId>` (dashes replaced with underscores, value is a base64-encoded JSON blob with at least a `branch` field). The relay claims the variable (get + delete, safe against concurrent redeliveries) and triggers a pipeline on that branch with `TESTFLIGHT_FINALIZE=true`, `TF_STATE=<the blob>`, and `TF_UPLOAD_STATE=<COMPLETE|FAILED>`.

If any sink fails, the relay answers 5xx so Apple redelivers. Pings, unknown event types, and unparseable-but-verified payloads are acknowledged with 200.

### Environment reference

| Variable | Required | Default | Description |
|---|---|---|---|
| `ASC_WEBHOOK_SECRET` | yes | — | Webhook secret configured in App Store Connect. The relay refuses to start without it. |
| `ASC_WEBHOOK_SECRET_SECONDARY` | no | — | Second secret accepted during secret rotation. |
| `PORT` | no | `13100` | Listen port (host is always `0.0.0.0`). |
| `LOG_LEVEL` | no | `info` | swift-log level: `trace`, `debug`, `info`, `notice`, `warning`, `error`, `critical`. |
| `SINKS` | no | `log` | Comma-separated sinks: `log`, `forward`, `gitlab-pipeline-trigger`. |
| `FORWARD_URL` | for `forward` | — | URL the raw delivery is POSTed to. |
| `GITLAB_BASE_URL` | for `gitlab-pipeline-trigger` | — | GitLab API base URL, e.g. `https://gitlab.example.com/api/v4`. |
| `GITLAB_PROJECT_ID` | for `gitlab-pipeline-trigger` | — | Project ID (or URL-encoded path) holding the pending variables and pipelines. |
| `GITLAB_API_TOKEN` | for `gitlab-pipeline-trigger` | — | Token with API access to project variables (sent as `PRIVATE-TOKEN`). |
| `GITLAB_TRIGGER_TOKEN` | for `gitlab-pipeline-trigger` | — | Pipeline trigger token. |
| `PENDING_VAR_PREFIX` | no | `TF_PENDING_` | Prefix of the pending-upload project variables. |
| `ALERT_WEBHOOK_URL` | no | — | If set, trigger failures POST a JSON alert (`{"text": "..."}`) here. |
| `EXTRA_TRIGGER_VARIABLES` | no | — | Comma-separated `key=value` pairs passed through as extra pipeline trigger variables. |

### Endpoints

- `POST /webhooks/appstoreconnect` — the webhook receiver (point App Store Connect here).
- `GET /sys/health/liveness`, `GET /sys/health/readiness` — health probes.

### Running with Docker

```bash
docker build -t blimp-relay .
docker run --rm -p 13100:13100 \
    -e ASC_WEBHOOK_SECRET=whsec_... \
    -e SINKS=log,gitlab-pipeline-trigger \
    -e GITLAB_BASE_URL=https://gitlab.example.com/api/v4 \
    -e GITLAB_PROJECT_ID=42 \
    -e GITLAB_API_TOKEN=glpat-... \
    -e GITLAB_TRIGGER_TOKEN=glptt-... \
    blimp-relay
```

## Architecture overview

`blimp` aims to keep its dependencies to a minimum. It uses Apple's OpenAPI generator to create App Store Connect API clients. Swift Crypto is used for JWT signing. Swift Argument Parser is used for the command line interface implementation. Finally, our own `cronista` and `corredor` are used for logging and calling CLI tools.

- Archiving and exporting are done via `xcodebuild`.
- Uploading is done via the App Store Connect build upload API (with an optional legacy `altool` fallback).
- Processing is done via the App Store Connect API.

## Attributions

JWT signing was borrowed from [AvdLee](https://github.com/AvdLee/appstoreconnect-swift-sdk) under MIT License.

## Contributors ✨

Thanks goes to these wonderful people ([emoji key](https://allcontributors.org/docs/en/emoji-key)):

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/memoto"><img src="https://avatars.githubusercontent.com/u/16154570?v=4?s=100" width="100px;" alt="Konstantin Iurichev"/><br /><sub><b>Konstantin Iurichev</b></sub></a><br /><a href="https://github.com/platacard/blimp/commits?author=memoto" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/NoFearJoe"><img src="https://avatars.githubusercontent.com/u/4526841?v=4?s=100" width="100px;" alt="Ilya Kharabet"/><br /><sub><b>Ilya Kharabet</b></sub></a><br /><a href="https://github.com/platacard/blimp/commits?author=NoFearJoe" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/tigati"><img src="https://avatars.githubusercontent.com/u/2447006?v=4?s=100" width="100px;" alt="tigati"/><br /><sub><b>tigati</b></sub></a><br /><a href="https://github.com/platacard/blimp/commits?author=tigati" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://anthropic.com/claude-code"><img src="https://avatars.githubusercontent.com/u/81847?v=4?s=100" width="100px;" alt="Claude"/><br /><sub><b>Claude</b></sub></a><br /><a href="https://github.com/platacard/blimp/commits?author=claude" title="Code">💻</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind welcome!

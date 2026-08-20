# blimp-relay

`blimp-relay` is a small, separately deployable HTTP server that receives [App Store Connect webhooks](https://developer.apple.com/documentation/appstoreconnectapi/webhooks), verifies their HMAC-SHA256 signatures, and relays them to configurable sinks — turn ASC webhooks into GitLab pipeline triggers, or forward them anywhere. The signature verification and payload models are also available as a standalone `WebhookKit` library product if you'd rather embed webhook handling in your own server.

> The relay never needs App Store Connect credentials. It only holds the webhook secret you configured in App Store Connect — deliveries are verified by signature, not by calling back into the ASC API.

## Polling (default) vs webhooks

By default, no relay is needed: `blimp approach` uploads the IPA and then **blocks, polling** the App Store Connect API every 30 seconds — first until the build appears, then until processing finishes. There is no built-in timeout; your CI job's timeout is the limit. Zero setup, but the runner stays busy for the whole processing window (typically 5–30 minutes).

With the relay, the upload job can exit right after the upload and let Apple call you back:

1. Apple processes the build and sends a `BUILD_UPLOAD_STATE_UPDATED` webhook to the relay.
2. The relay verifies the signature and runs its sinks — e.g. triggers a finalize pipeline on GitLab.

The polling path is untouched either way — webhooks are opt-in.

## Setup

1. **Deploy the relay** somewhere reachable by Apple over HTTPS (see [Running with Docker](#running-with-docker)) with at least `ASC_WEBHOOK_SECRET` set.
2. **Register the webhook in App Store Connect** — the relay only receives deliveries, it does not register itself. Use the ASC UI (App → Webhooks) or the `WebhooksAPI` library product:

   ```swift
   import WebhooksAPI

   let api = WebhooksAPI(jwtProvider: DefaultJWTProvider())
   try await api.createWebhook(
       appId: appId,
       name: "blimp-relay",
       url: "https://relay.example.com/webhooks/appstoreconnect",
       secret: secret, // must equal the relay's ASC_WEBHOOK_SECRET
       eventTypes: [.buildUploadStateUpdated]
   )
   ```

3. **Configure sinks** via the `SINKS` env variable (see the environment reference below).

For the `gitlab-pipeline-trigger` sink, the upload job supplies the resume context ("producer side"):

- `Approach.start(...)` (BlimpKit) returns an `UploadReceipt` with the `uploadId` of the build upload. The `blimp approach` CLI command always polls; to exit after upload, call `Approach.start` from your own CLI instead of `hold`.
- Publish a base64-encoded JSON blob containing at least a non-empty `"branch"` field to the GitLab generic package registry at `packages/generic/<PENDING_PACKAGE_NAME>/<uploadId>/state.json`.
- When the upload reaches `COMPLETE` or `FAILED`, the relay claims that package and triggers a pipeline on `branch` with the variables `TESTFLIGHT_FINALIZE=true`, `TF_STATE=<your blob>`, and `TF_UPLOAD_STATE=<COMPLETE|FAILED>` (plus anything from `EXTRA_TRIGGER_VARIABLES`). Your finalize pipeline reacts to these and continues with `blimp land`.

## Sinks

Sinks (comma-separated in `SINKS`, executed in order per delivery):

- `log` — logs a one-line summary of each delivery.
- `forward` — POSTs the raw, already-verified body to `FORWARD_URL` (original content type plus an `x-relay-event-type` header).
- `gitlab-pipeline-trigger` — resumes a waiting CI pipeline when a build upload reaches `COMPLETE`/`FAILED`. The upload job publishes its state to the GitLab generic package registry as `packages/generic/<PENDING_PACKAGE_NAME>/<uploadId>/state.json` (a base64-encoded JSON blob with at least a `branch` field; one package per upload, so parallel deploys never interfere and nothing is injected into CI job environments). The relay claims the package (download + delete, safe against concurrent redeliveries) and triggers a pipeline on that branch with `TESTFLIGHT_FINALIZE=true`, `TF_STATE=<the blob>`, and `TF_UPLOAD_STATE=<COMPLETE|FAILED>`.

If any sink fails, the relay answers 5xx so Apple redelivers. Pings, unknown event types, and unparseable-but-verified payloads are acknowledged with 200.

## Porting to another CI provider

The trigger sink is provider-neutral: it works against two small protocols in [`Providers/`](Providers/) — `PendingStateStore` (keyed state with an atomic claim; GitLab backs it with the generic package registry and delete-as-claim) and `PipelineTrigger` (start a run on a ref with parameters). A GitHub port, for example, would implement the store with one git ref per upload (ref deletion is atomic) and the trigger with `repository_dispatch`. GitLab is currently the only shipped implementation; the `forward` sink is the zero-code alternative for anything that can receive an HTTP POST.

## Environment reference

| Variable | Required | Default | Description |
|---|---|---|---|
| `ASC_WEBHOOK_SECRET` | yes | — | Webhook secret configured in App Store Connect. The relay refuses to start without it. |
| `ASC_WEBHOOK_SECRET_SECONDARY` | no | — | Second secret accepted during secret rotation. |
| `PORT` | no | `13100` | Listen port (host is always `0.0.0.0`). |
| `LOG_LEVEL` | no | `info` | swift-log level: `trace`, `debug`, `info`, `notice`, `warning`, `error`, `critical`. |
| `SINKS` | no | `log` | Comma-separated sinks: `log`, `forward`, `gitlab-pipeline-trigger`. |
| `FORWARD_URL` | for `forward` | — | URL the raw delivery is POSTed to. |
| `GITLAB_BASE_URL` | for `gitlab-pipeline-trigger` | — | GitLab API base URL, e.g. `https://gitlab.example.com/api/v4`. |
| `GITLAB_PROJECT_ID` | for `gitlab-pipeline-trigger` | — | Project ID (or URL-encoded path) holding the pending packages and pipelines. |
| `GITLAB_API_TOKEN` | for `gitlab-pipeline-trigger` | — | Token with API access to the project's package registry (sent as `PRIVATE-TOKEN`). |
| `GITLAB_TRIGGER_TOKEN` | for `gitlab-pipeline-trigger` | — | Pipeline trigger token. |
| `PENDING_PACKAGE_NAME` | no | `tf-pending` | Generic package name holding pending-upload state files. |
| `ALERT_WEBHOOK_URL` | no | — | If set, trigger failures POST a JSON alert (`{"text": "..."}`) here. |
| `EXTRA_TRIGGER_VARIABLES` | no | — | Comma-separated `key=value` pairs passed through as extra pipeline trigger variables. |

## Endpoints

- `POST /webhooks/appstoreconnect` — the webhook receiver (point App Store Connect here).
- `GET /sys/health/liveness`, `GET /sys/health/readiness` — health probes.

## Running with Docker

Prebuilt multi-arch images are published to GHCR on every version tag:

```bash
docker run --rm -p 13100:13100 \
    -e ASC_WEBHOOK_SECRET=whsec_... \
    ghcr.io/platacard/blimp-relay:0.9.0
```

Or build locally (from the repo root):

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

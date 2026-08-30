# Peta 1.3.0

Peta 1.3.0 is a coordinated release of Core, Console, Auth, and the unified
deployment scripts. The three public `bcdunia/peta-*` images are published as
immutable `1.3.0` OCI indexes for `linux/amd64` and `linux/arm64`. This release
does not publish `latest`.

## Exact release identities

The images were built from `git archive` output for the reviewed source commits:

| Component | Reviewed source commit | Published OCI index |
| --- | --- | --- |
| Core | `039a39234448a3b1a407e3b4b571b91d9bf68ff0` | `bcdunia/peta-core:1.3.0@sha256:209bfcca9fb4458141247e604640fdb9901978880e48cb4fd3b23fe7639cb1f6` |
| Console | `0fc5d5f8365453a7b3ef93a9b7124cb63eece060` | `bcdunia/peta-console:1.3.0@sha256:c2f26b557239c930d4ada347ea54dfcb3866b19df1e2306c8573ad8c66b8e02c` |
| Auth | `9583a63d84178b6fce6c1de93084d0a776a85a73` | `bcdunia/peta-auth:1.3.0@sha256:00f77bbfa5b612f3e52a9c8a7f6490dc6bf34138b512c66dd43693e42931498f` |

This record identifies the release contents before this repository's
`v1.3.0` tag is created; the tag must target the commit containing this file.

Platform manifests:

| Image | `linux/amd64` | `linux/arm64` |
| --- | --- | --- |
| Core | `sha256:2912060c9d7f147ec221070d64d53fc2e03fc9b263e4d0aadcc901b93adfc8a1` | `sha256:6f69b59012f48e9a3f836a626939e0aa10d6921b1827800ce742d5d519be1876` |
| Console | `sha256:60cb5dd64ad7eb36b63e2294056f71a98239c4e65135a43d029048281f45828c` | `sha256:e47b69bb31073928f6b2512bad7c152b154f4fad43f9fb4786817686bf2310c0` |
| Auth | `sha256:d5048391ec94396f4adb8a5c47b39d3ebdaaeab5df908542720489d84261d847` | `sha256:db60a05cffd4e97a7b3881938c7f98d6d2704205e186297ade6f6ba868a00dc6` |

## Highlights

- Added the reviewed MCP `2026-07-28` stateless HTTP compatibility path while preserving legacy MCP clients and downstream servers.
- Added modern HTTP/SSE request correlation, bounded downstream responses, capability negotiation and preservation, subscription isolation, reconnect handling, and stricter protocol failure behavior.
- Hardened OAuth, public URL handling, token masking, and persistent log redaction across gateway paths.
- Updated Console create/edit flows and API handlers for protocol selection, remote launch configuration, and unknown MCP capability round trips.
- Fixed Console first-run protocol `10002` probing so expected HTTP 404 responses are suppressed without masking real failures; 5xx and network errors remain truthful and visible.
- Updated Console documentation layouts for 375px, 768px, and 1280px viewports, using semantic design tokens and clear disabled-versus-linked control states. Improved heading order in the updated sections and favicon handling for accessibility, and corrected Peta Desk downloads to the published Windows/macOS artifacts while marking Linux as coming soon.
- Made the Console image reproducible from a clean checkout while preserving the published image's offline tool-template fallback.
- Removed repository TLS credentials from the current Console source and excluded local key/certificate files from Git and Docker build contexts. The historical Console Origin certificate was revoked on 2026-08-30, removed from the Cloudflare inventory, and recorded in Cloudflare's signed CRL; the active public sites remained healthy. Public Git tags and GitHub Releases use the separately approved operator flow after exact image and release-note verification. This release does not publish `latest`.
- Patched production-reachable denial-of-service dependencies in Core Socket.IO/ZIP handling and Console Next.js, HTTP, and YAML processing.
- Added HubSpot and Canva providers to Peta Auth and moved the release build to Go 1.26.6. The published Auth image was rebuilt from the reviewed source and passed multi-architecture health, binary vulnerability, and digest verification.
- Peta Auth now authenticates every encrypted `clientSecretCipher` before listening, so a malformed runtime secrets file fails startup instead of reporting a healthy but unusable service.
- Hardened release tooling so Core, Console, and Auth require explicit publication approval, Docker Hub semantic-version tag immutability, bind the build to an exact reviewed Git commit, and send only that commit's `git archive` to Docker Buildx. Each publisher fixes its `bcdunia/peta-*` image, Dockerfile, semantic-version tag, and `linux/amd64,linux/arm64` platforms. Core's combined source/tag/GitHub Release publisher remains disabled; those public Git artifacts use the separately approved operator process after exact image verification.
- Changed the unified macOS, Linux, and Windows installers to pin Core and Console with `PETA_VERSION` and Auth with `PETA_AUTH_VERSION`; both default to `1.3.0` for a coordinated installation.
- Fixed Windows PowerShell generation with Auth disabled so Compose top-level `services` and `volumes` sections remain separate and valid.
- Made the macOS/Linux replacement-port prompt fail closed on end-of-input instead of spinning and producing unbounded error logs in non-interactive runs.
- Made macOS/Linux existing-database detection match exact Docker volume names so unrelated similarly named volumes no longer block a fresh install.
- Changed installer secret generation to use operating-system cryptographic randomness and restrict generated `.env` files to the current user.
- When `PETA_AUTH_AUTOSTART=true`, installers now require a pre-provisioned raw 32-byte `./secrets/peta_auth_master_key` and non-empty encrypted `./secrets/peta_auth_client_secrets.json`. They enforce current-user-only access, keep both values out of `.env` and output, and mount them only into `peta-auth`.
- Peta does not expose or retain previous credential values as a recovery history. Keep protected prior secret material and rotation records outside Peta when your rollback policy requires them.

## MCP compatibility scope

- Modern MCP `2026-07-28` ingress and modern HTTP downstream probing remain controlled by `MCP_2026_ENABLED` and `MCP_2026_DOWNSTREAM_ENABLED`; both can be disabled for rollback.
- Modern downstream mode is HTTP-only. Stdio and explicit SSE downstream transports continue through the legacy-compatible SDK path.
- Persistent modern downstream subscriptions, downstream progress/cancellation bridging, and standard reverse requests are not advertised in this release. The legacy MCP paths remain available for those existing gateway flows.
- Peta Core keeps the legacy `@modelcontextprotocol/sdk` 1.x client path and implements the modern stateless boundary in its local adapter; an SDK 2.x migration is not part of `1.3.0`.

## Install

With all three `1.3.0` image manifests published, run the installer for the host platform:

```sh
./deploy-peta.sh
```

Linux hosts that need Docker service management can use `./deploy-peta-linux.sh`; Windows hosts can use `./deploy-peta.ps1`.

If you enable Peta Auth, create `${DEPLOY_DIR:-./peta-deployment}/secrets/` and provision `peta_auth_master_key` (raw 32 bytes) and `peta_auth_client_secrets.json` (non-empty encrypted client-secrets JSON) there before running the installer. The installer treats this secrets-only directory as a new deployment and fails before generating Compose configuration unless the directory and both files are protected for the current user. Peta Auth validates and decrypts the JSON before listening. The installer never creates, copies, prints, or stores either value in `.env`.

## Update

In an existing generated deployment directory, keep the database and Auth volumes, set `PETA_VERSION=1.3.0` and `PETA_AUTH_VERSION=1.3.0` in `.env`, then run:

```sh
docker compose pull
docker compose up -d
docker compose ps
```

Normal container startup applies the repositories' existing database migration flow. This release does not add a new Core or Console schema migration beyond the already published migration history. Keep the same Auth secret pair and `peta-auth-core-data` volume during updates; changing either can make existing Auth data unreadable.

## Verify

- Core: `curl -fsS http://localhost:3002/health`
- Console: `curl -fsS http://localhost:3000/`
- Auth: `docker compose ps peta-auth` should report healthy; `/healthz` is internal to the Compose network.

## Rollback

To roll Core and Console back to the verified `bcdunia` `1.2.0` images while
retaining the compatible Auth release, pin the generated `.env` as follows,
then run `docker compose pull && docker compose up -d`:

```dotenv
PETA_VERSION=1.2.0
PETA_AUTH_VERSION=1.3.0
```

Preserve the same Auth secret pair and Auth volume. Images from before runtime-secret support rely on embedded keys and are not compatible with this provisioning contract. Do not use `docker compose down -v`; named PostgreSQL and Auth volumes must be preserved.

Verified rollback identities:

| Component | Rollback selection | OCI index |
| --- | --- | --- |
| Core | `PETA_VERSION=1.2.0` | `bcdunia/peta-core:1.2.0@sha256:36c0d245aa8c7b9d98f38d12742d55c11f226c110bfe095faf65dbc6edf8b0e1` |
| Console | `PETA_VERSION=1.2.0` | `bcdunia/peta-console:1.2.0@sha256:b0588f2ccf975d85e2c9f80c272b4e923b52afc3bba9b619664ca46ce817f0fc` |
| Auth | `PETA_AUTH_VERSION=1.3.0` | `bcdunia/peta-auth:1.3.0@sha256:00f77bbfa5b612f3e52a9c8a7f6490dc6bf34138b512c66dd43693e42931498f` |

# YS Web API

## Install dependencies

```bash
go mod download
```

## Run the project

```bash
make run
```

## Auto reload when code changes

```bash
air
```

## Format code

```bash
make format
```

## Build

```bash
make build
```

## Deploying production chat migrations

Before deploying a binary that contains the production chat features:

1. Take and verify a restorable MySQL backup.
2. Quiesce all old API writers; do not use a mixed-version rolling window for this migration.
3. In a maintenance window, run `migrations/20260715_001_chat_production_features.sql`, then `migrations/20260717_002_realtime_calls.sql`, and verify both `chat_schema_migrations` rows.
4. Deploy all new API instances and only then resume writes. The catch-up API treats the immutable message ID as the effective server sequence, so it can still recover a late row produced with a null sequence during an interrupted rollout.

The migration builds FULLTEXT/secondary indexes and snapshots legacy receipt/read state, so it can be expensive on large tables. The API's runtime schema checks and migration ledger are a fallback for older installations; they are not a reason to rerun the SQL file. In particular, do not run its `ALTER TABLE` statements after an app-first rollout unless an operator has inspected the actual schema and removed operations that already exist.

## Realtime and ICE configuration

WebSocket clients first request `POST /api/v1/chat/realtime/ticket`; the access token is never put in the WebSocket URL. The reconnect flow then opens `/chat/realtime?ticket=...&reconnect=1` and calls each conversation's catch-up endpoint.

`realtime.eventBus` defaults to `memory`. Set it to `redis` for multiple API instances and provide `YS_REDIS_URL` (plus optional `YS_REDIS_CHANNEL`) through the deployment environment. The JSON health endpoint exposes active connection, dropped event, and reconnect counters.

Clients obtain STUN/TURN configuration from `GET /api/v1/chat/calls/ice-config`. Configure public URLs under `webrtc` and provide `TURN_SHARED_SECRET` for short-lived coturn REST credentials. `TURN_USERNAME` and `TURN_CREDENTIAL` are supported only as a static fallback. Credential values must be injected at runtime and must not be committed or logged.

For a single API instance, `webrtc.embeddedTURNEnabled` can run an authenticated Pion TURN relay inside the API process instead of deploying coturn. Set `embeddedTURNRelayIP` to the IP or one-to-one NAT address reachable by clients. Open/map TCP and UDP port `3478` and the configured UDP relay range (`49160-49200` by default). Use `TURN_SHARED_SECRET` in production; static credentials remain suitable only for a private development network. When explicit `turnURLs` are omitted, the API advertises UDP and TCP TURN URLs using the embedded relay IP automatically.

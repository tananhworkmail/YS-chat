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
3. In a maintenance window, run `migrations/20260715_001_chat_production_features.sql` exactly once, then verify the `chat_schema_migrations` row.
4. Deploy all new API instances and only then resume writes. The catch-up API treats the immutable message ID as the effective server sequence, so it can still recover a late row produced with a null sequence during an interrupted rollout.

The migration builds FULLTEXT/secondary indexes and snapshots legacy receipt/read state, so it can be expensive on large tables. The API's runtime schema checks and migration ledger are a fallback for older installations; they are not a reason to rerun the SQL file. In particular, do not run its `ALTER TABLE` statements after an app-first rollout unless an operator has inspected the actual schema and removed operations that already exist.

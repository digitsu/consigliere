# Consigliere — Elixir Port PRD

**Project:** BSV STAS Indexer with Back-to-Genesis Resolution
**Language:** Elixir (Phoenix)
**Source Template:** [dxsapp/dxs-consigliere](https://github.com/dxsapp/dxs-consigliere) (C# / .NET / RavenDB / SignalR)
**Date:** 2026-03-25
**Author:** HAL9000

---

## 1. Overview

Consigliere is a selective UTXO indexer for BSV that tracks only explicitly configured addresses and STAS tokens. It resolves Back-to-Genesis provenance for STAS tokens, provides real-time WebSocket notifications for balance changes and transaction events, and exposes REST + WebSocket APIs for payment processors.

This PRD defines the Elixir port — a feature-equivalent reimplementation using Phoenix, PostgreSQL, and OTP supervision, leveraging `bsv_sdk_elixir` for all cryptographic and STAS/B2G primitives.

---

## 2. Architecture Mapping

### 2.1 Component Mapping (C# → Elixir)

| C# Component | Elixir Equivalent | Notes |
|---|---|---|
| ASP.NET Core + Startup.cs | Phoenix application + `application.ex` | Supervision tree replaces DI container |
| SignalR WalletHub | Phoenix Channel (`WalletChannel`) | Topic-based pub/sub, native WebSocket |
| RavenDB | PostgreSQL + Ecto | JSONB for flexible fields, proper indexes for UTXO queries |
| MediatR (event bus) | Phoenix.PubSub + Registry | Process-based pub/sub, no library needed |
| BackgroundTasks (IHostedService) | GenServer / Task under Supervisor | OTP supervision with restart strategies |
| ZMQ Client | `erlzmq` or `:chumak` NIF | ZMQ subscriber for raw tx / block notifications |
| HTTP Clients (WoC, Bitails, JungleBus) | `Req` + `Finch` | Already proven in bsv_sdk_elixir transports |
| RPC Client (bitcoind) | `Req`-based JSON-RPC client | Simple HTTP POST with auth |
| ConnectionManager (SignalR) | Phoenix.Presence + Registry | Track subscriptions per socket |
| TransactionFilter | GenServer with ETS table | Fast concurrent reads, atomic updates |
| Rate limiter | `Hammer` or token bucket GenServer | Per-endpoint rate limiting |

### 2.2 Data Flow

```
BSV Node (ZMQ)          JungleBus (WS)
    │                        │
    ▼                        ▼
┌──────────────────────────────────────┐
│         Transaction Ingress          │
│   (ZmqListener / JungleBusClient)   │
└──────────────┬───────────────────────┘
               │ raw tx bytes
               ▼
┌──────────────────────────────────────┐
│        Transaction Filter            │
│  (check watched addresses/tokens)    │
│  ETS: watched_addresses, watched_tokens
└──────────┬──────────────┬────────────┘
           │ matched       │ unmatched → drop
           ▼
┌──────────────────────────────────────┐
│       Transaction Processor          │
│  - Parse tx (bsv_sdk_elixir)        │
│  - Classify: P2PKH / STAS / DSTAS   │
│  - B2G resolution for STAS          │
│  - Update UTXO set in Postgres      │
│  - Publish events via PubSub        │
└──────────┬───────────────────────────┘
           │ events
           ▼
┌──────────────────────────────────────┐
│        Phoenix.PubSub                │
│  topics: "tx:{address}", "balance:{address}"
└──────┬─────────────┬─────────────────┘
       │             │
       ▼             ▼
  WalletChannel   Background Tasks
  (push to WS)    (unconfirmed monitor,
                   block processor, etc.)
```

---

## 3. Data Model (PostgreSQL / Ecto)

### 3.1 Core Tables

```
meta_transactions
├── id (uuid, PK)
├── txid (binary(32), unique index)
├── hex (text) — raw tx hex
├── block_hash (binary(32), nullable)
├── block_height (integer, nullable)
├── timestamp (bigint) — unix seconds
├── is_confirmed (boolean, default false)
├── addresses (text[], GIN index) — involved addresses
├── token_ids (text[], GIN index) — involved STAS token IDs
├── metadata (jsonb) — flexible extra fields
├── inserted_at / updated_at
```

```
utxos
├── id (uuid, PK)
├── txid (binary(32))
├── vout (integer)
├── address (text, index)
├── satoshis (bigint)
├── script_hex (text)
├── token_id (text, nullable, index) — STAS token ID if token output
├── token_type (text, nullable) — "stas" | "dstas" | null
├── is_spent (boolean, default false, index)
├── spent_txid (binary(32), nullable)
├── block_height (integer, nullable)
├── inserted_at / updated_at
├── UNIQUE(txid, vout)
```

```
watching_addresses
├── id (uuid, PK)
├── address (text, unique)
├── name (text, nullable)
├── inserted_at
```

```
watching_tokens
├── id (uuid, PK)
├── token_id (text, unique)
├── symbol (text, nullable)
├── inserted_at
```

```
block_process_contexts
├── id (text, PK) — block hash
├── height (integer, unique index)
├── processed_at (utc_datetime)
```

```
broadcasts
├── id (uuid, PK)
├── txid (text)
├── hex (text)
├── status (text) — "pending" | "accepted" | "rejected"
├── error (text, nullable)
├── inserted_at
```

```
address_histories
├── id (uuid, PK)
├── address (text, index)
├── txid (text)
├── direction (text) — "in" | "out"
├── satoshis (bigint)
├── token_id (text, nullable)
├── block_height (integer, nullable)
├── timestamp (bigint)
├── inserted_at
```

### 3.2 Indexes

- `utxos`: composite on `(address, is_spent)`, `(token_id, is_spent)`, `(txid, vout)`
- `meta_transactions`: GIN on `addresses`, `token_ids`; B-tree on `block_height`, `is_confirmed`
- `address_histories`: composite on `(address, timestamp DESC)`

---

## 4. Module Structure

```
consigliere/
├── lib/
│   ├── consigliere/
│   │   ├── application.ex              — OTP app + supervision tree
│   │   ├── repo.ex                     — Ecto Repo
│   │   │
│   │   ├── blockchain/                 — BSV node interaction
│   │   │   ├── zmq_listener.ex         — GenServer: ZMQ subscriber
│   │   │   ├── rpc_client.ex           — JSON-RPC to bitcoind
│   │   │   ├── jungle_bus_client.ex    — JungleBus WS client
│   │   │   └── network.ex             — mainnet/testnet config
│   │   │
│   │   ├── indexer/                    — Core indexing logic
│   │   │   ├── transaction_filter.ex   — GenServer + ETS: address/token matching
│   │   │   ├── transaction_processor.ex — Parse, classify, store
│   │   │   ├── utxo_manager.ex         — UTXO set queries + updates
│   │   │   ├── block_processor.ex      — Block ingestion + reorg detection
│   │   │   └── b2g_resolver.ex         — Back-to-Genesis chain walking
│   │   │
│   │   ├── tokens/                     — STAS token logic (delegates to bsv_sdk_elixir)
│   │   │   ├── classifier.ex           — Classify tx as STAS/DSTAS/P2PKH
│   │   │   └── provenance.ex           — Token lineage verification
│   │   │
│   │   ├── services/                   — Business logic
│   │   │   ├── address_history.ex      — Address history queries
│   │   │   ├── balance.ex              — Balance computation
│   │   │   ├── broadcast.ex            — TX broadcast via RPC
│   │   │   └── sync_status.ex          — Chain sync status
│   │   │
│   │   ├── workers/                    — Background tasks (GenServers)
│   │   │   ├── unconfirmed_monitor.ex  — Recheck unconfirmed txs
│   │   │   ├── chain_tip_verifier.ex   — Verify chain tip, detect reorgs
│   │   │   ├── stas_attributes_observer.ex — Watch STAS attribute changes
│   │   │   └── missing_tx_syncer.ex    — Backfill missing txs via JungleBus
│   │   │
│   │   ├── infra/                      — External API clients
│   │   │   ├── whats_on_chain.ex       — WoC REST client
│   │   │   └── bitails.ex              — Bitails REST client
│   │   │
│   │   └── schema/                     — Ecto schemas
│   │       ├── meta_transaction.ex
│   │       ├── utxo.ex
│   │       ├── watching_address.ex
│   │       ├── watching_token.ex
│   │       ├── block_process_context.ex
│   │       ├── broadcast.ex
│   │       └── address_history.ex
│   │
│   ├── consigliere_web/
│   │   ├── endpoint.ex
│   │   ├── router.ex
│   │   │
│   │   ├── channels/
│   │   │   ├── user_socket.ex          — Socket handler
│   │   │   └── wallet_channel.ex       — "wallet:*" topic — all SignalR methods
│   │   │
│   │   └── controllers/
│   │       ├── admin_controller.ex     — POST /api/admin/manage/{address,stas-token}
│   │       ├── address_controller.ex   — GET /api/address/*
│   │       ├── transaction_controller.ex — GET/POST /api/transaction/*
│   │       └── config_controller.ex    — GET /api/config/*
│   │
│   └── mix.exs
│
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── prod.exs
│   └── runtime.exs                    — env-based config (BSV node, ZMQ, etc.)
│
├── priv/
│   └── repo/migrations/
│
├── test/
│   ├── consigliere/
│   │   ├── indexer/
│   │   ├── services/
│   │   └── workers/
│   ├── consigliere_web/
│   │   ├── channels/
│   │   └── controllers/
│   └── support/
│       ├── fixtures.ex
│       └── channel_case.ex
│
├── Dockerfile
├── docker-compose.yml                 — app + postgres + (optional) BSV node
└── README.md
```

---

## 5. Supervision Tree

```
Consigliere.Application
├── Consigliere.Repo                           — Ecto/Postgres
├── ConsigliereWeb.Endpoint                    — Phoenix HTTP + WS
├── Phoenix.PubSub (name: Consigliere.PubSub)  — Event bus
├── Registry (name: Consigliere.Subscriptions)  — Per-connection subscription tracking
│
├── Consigliere.Blockchain.Supervisor          — :rest_for_one
│   ├── Consigliere.Blockchain.Network         — Network config (mainnet/testnet)
│   ├── Consigliere.Blockchain.RpcClient       — JSON-RPC connection pool
│   └── Consigliere.Blockchain.ZmqListener     — ZMQ subscriber (raw_tx, block_hash)
│
├── Consigliere.Indexer.Supervisor             — :one_for_one
│   ├── Consigliere.Indexer.TransactionFilter  — ETS: watched addresses/tokens
│   ├── Consigliere.Indexer.TransactionProcessor — Pipeline: filter → parse → store → notify
│   ├── Consigliere.Indexer.UtxoManager        — UTXO queries
│   └── Consigliere.Indexer.BlockProcessor     — Block-by-block processing + reorg
│
├── Consigliere.Workers.Supervisor             — :one_for_one
│   ├── Consigliere.Workers.UnconfirmedMonitor — Periodic: recheck stale unconfirmed
│   ├── Consigliere.Workers.ChainTipVerifier   — Periodic: verify chain tip consistency
│   ├── Consigliere.Workers.StasObserver       — Watch STAS attribute changes
│   └── Consigliere.Workers.MissingTxSyncer    — Backfill via JungleBus
│
└── Consigliere.Infra.Supervisor               — :one_for_one
    ├── Finch (name: Consigliere.Finch)        — HTTP connection pool
    └── Consigliere.Blockchain.JungleBusClient — JungleBus WS (optional)
```

---

## 6. API Specification

### 6.1 REST API (Phoenix Controllers)

#### Admin
| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/admin/manage/address` | Add address to watch list |
| POST | `/api/admin/manage/stas-token` | Add STAS token to watch list |
| GET | `/api/admin/blockchain/sync-status` | Chain sync status |

#### Address
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/address/:address/balance` | Address balance (BSV + tokens) |
| GET | `/api/address/:address/history` | Transaction history |
| GET | `/api/address/:address/utxos` | Unspent outputs |

#### Transaction
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/transaction/:txid` | Get transaction by ID |
| POST | `/api/transaction/broadcast` | Broadcast raw tx |

### 6.2 WebSocket API (Phoenix Channel)

**Socket path:** `/ws/consigliere`
**Channel topic:** `"wallet:lobby"` (or `"wallet:{address}"` for per-address topics)

#### Client → Server (push)

| Event | Payload | Description |
|-------|---------|-------------|
| `subscribe` | `{address, slim}` | Subscribe to tx stream for address |
| `unsubscribe` | `{address}` | Unsubscribe |
| `get_balance` | `{addresses, token_ids}` | Query balances |
| `get_history` | `{address, token_ids, desc, skip_zero_balance, skip, take}` | Address history |
| `get_utxo_set` | `{token_id, address, satoshis}` | UTXO set query |
| `get_transactions` | `[txid, ...]` | Batch tx lookup (max 100) |
| `broadcast` | `raw_tx_hex` | Broadcast transaction |

#### Server → Client (push)

| Event | Payload | Description |
|-------|---------|-------------|
| `tx_found` | `hex` | New transaction detected for subscribed address |
| `tx_deleted` | `txid` | Transaction removed (reorg/mempool eviction) |
| `balance_changed` | `{address, balances}` | Balance update notification |

---

## 7. Key Dependencies

| Dependency | Purpose | Hex Package |
|---|---|---|
| `bsv_sdk_elixir` | TX parsing, STAS classification, B2G, script analysis | `{:bsv_sdk, path: "..."}` or hex.pm |
| Phoenix | Web framework, channels, pub/sub | `{:phoenix, "~> 1.7"}` |
| Ecto + Postgrex | PostgreSQL ORM | `{:ecto_sql, "~> 3.11"}` |
| Req + Finch | HTTP clients (WoC, Bitails, RPC) | `{:req, "~> 0.5"}` |
| chumak | Pure Erlang ZMQ (or erlzmq NIF) | `{:chumak, "~> 1.4"}` |
| Jason | JSON encoding/decoding | `{:jason, "~> 1.4"}` |
| Hammer | Rate limiting | `{:hammer, "~> 6.2"}` |

---

## 8. Implementation Phases

### Phase 1: Foundation (scaffold + data layer)
- Phoenix project scaffold with Ecto/Postgres
- All Ecto schemas + migrations
- Runtime config (BSV node, network, ZMQ endpoints)
- Admin REST API (manage addresses/tokens)
- Health/sync-status endpoint
- **Tests:** Schema validation, admin CRUD, config loading

### Phase 2: Blockchain Ingress
- ZMQ listener GenServer (subscribe to `rawtx`, `hashblock`)
- RPC client (getblock, getrawtx, getblockcount, sendrawtransaction)
- Transaction filter (ETS-backed, match against watched addresses/tokens)
- Raw tx parsing via bsv_sdk_elixir
- **Tests:** ZMQ message handling (mocked), tx filter matching, RPC client

### Phase 3: Indexing Pipeline
- Transaction processor (parse → classify → store UTXO → update balances)
- UTXO manager (create/spend UTXOs, balance queries)
- Block processor (sequential block ingestion, UTXO confirmation)
- Chain reorg detection + rollback
- **Tests:** Full indexing pipeline with fixture txs, reorg scenarios

### Phase 4: STAS + Back-to-Genesis
- STAS/DSTAS tx classification (via bsv_sdk_elixir tokens module)
- B2G resolver — walk input chain back to genesis issuance
- Token provenance storage + queries
- Token stats (supply, burn totals)
- **Tests:** B2G chain resolution, STAS classify/issue/transfer/split/merge

### Phase 5: Real-Time (Phoenix Channels)
- WalletChannel with all subscribe/query methods
- Phoenix.PubSub integration — tx events → subscribed clients
- Connection tracking via Presence/Registry
- Balance change notifications
- **Tests:** Channel subscribe/push, concurrent client scenarios

### Phase 6: Background Workers
- UnconfirmedMonitor (periodic recheck of stale unconfirmed txs)
- ChainTipVerifier (periodic tip consistency check)
- StasAttributesObserver (watch for STAS attribute changes)
- MissingTxSyncer (backfill via JungleBus/WoC)
- **Tests:** Worker lifecycle, periodic task execution

### Phase 7: External Integrations + Polish
- JungleBus WebSocket client (mempool monitor, historical sync)
- WhatsOnChain client (tx lookup fallback)
- Bitails client (additional tx data)
- Swagger/OpenAPI spec generation
- Dockerfile + docker-compose
- **Tests:** Integration tests with mocked external services

---

## 9. bsv_sdk_elixir Integration Points

The Elixir SDK already provides the heavy lifting:

| SDK Module | Used For |
|---|---|
| `BsvSdk.Transaction` | Parse raw tx hex, extract inputs/outputs |
| `BsvSdk.Script` | Script analysis, P2PKH extraction |
| `BsvSdk.Tokens.ScriptReader` | Classify STAS v2 / DSTAS scripts |
| `BsvSdk.Tokens.Types` | TokenId, ScriptType, Scheme enums |
| `BsvSdk.Spv.MerklePath` | Merkle proof verification |
| `BsvSdk.Primitives.Address` | Address parsing + validation |
| `BsvSdk.Tokens.Factories.*` | Token operation classification |
| `BsvSdk.BackToGenesis.*` | B2G locking/unlocking, lineage validation |

This eliminates the need to port `Dxs.Bsv` and `Dxs.Bsv.Tokens` — the most complex parts of the original codebase.

---

## 10. Configuration (runtime.exs)

```elixir
config :consigliere,
  network: System.get_env("NETWORK", "testnet"),
  bsv_node: [
    rpc_url: System.get_env("BSV_NODE_RPC_URL", "http://localhost:18332"),
    rpc_user: System.get_env("BSV_NODE_RPC_USER"),
    rpc_password: System.get_env("BSV_NODE_RPC_PASSWORD")
  ],
  zmq: [
    raw_tx: System.get_env("ZMQ_RAW_TX", "tcp://localhost:28332"),
    hash_block: System.get_env("ZMQ_HASH_BLOCK", "tcp://localhost:28332"),
    removed_from_mempool: System.get_env("ZMQ_REMOVED_MEMPOOL", "tcp://localhost:28332"),
    discarded_from_mempool: System.get_env("ZMQ_DISCARDED_MEMPOOL", "tcp://localhost:28332")
  ],
  jungle_bus: [
    enabled: System.get_env("JUNGLE_BUS_ENABLED", "false") == "true",
    url: System.get_env("JUNGLE_BUS_URL")
  ]

config :consigliere, Consigliere.Repo,
  url: System.get_env("DATABASE_URL", "postgres://localhost/consigliere_dev")
```

---

## 11. Deployment

- **Docker:** Multi-stage build (Elixir release)
- **Compose:** `consigliere` + `postgres` services, optional BSV node sidecar
- **Port:** 5000 (matching original for drop-in compatibility)
- **Health:** `GET /api/admin/blockchain/sync-status`
- **Env-compatible:** Same env var names as the Docker Hub image where possible

---

## 12. Design Decisions

1. **PostgreSQL over RavenDB** — Ecto is the Elixir standard. JSONB gives document flexibility where needed. UTXO queries benefit from proper relational indexes. No external DB dependency to manage.

2. **Phoenix Channels over SignalR** — Native WebSocket support with topic-based pub/sub. Presence tracking built in. Battle-tested at scale (2M+ concurrent connections per node).

3. **ETS for TransactionFilter** — Hot path (every incoming tx). ETS gives concurrent lock-free reads. Updates are rare (admin adds address) and serialized through the GenServer.

4. **Process-per-concern, not process-per-address** — Unlike the C# singleton pattern, each background task is its own supervised process. But we don't go full process-per-address (overkill for selective indexing with typically hundreds, not millions, of addresses).

5. **chumak over erlzmq** — Pure Erlang, no NIF compilation. Simpler deployment. Adequate performance for the tx throughput we're handling (ZMQ is not the bottleneck).

6. **Req over HTTPoison** — Modern, composable, built on Finch. Connection pooling included. Already proven in bsv_sdk_elixir.

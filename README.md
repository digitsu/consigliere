# Athanor

> *The philosophical furnace for BSV & STAS token infrastructure.*

A high-performance BSV blockchain indexer and wallet backend built with Elixir and the Phoenix framework. Named after the alchemist's self-feeding furnace — "Slow Henry," the furnace that gives no trouble.

Athanor watches configured addresses and token IDs, indexes transactions in real-time via BSV node RPC and ZMQ, and exposes a REST API and WebSocket interface for querying balances, UTXOs, transaction history, and broadcasting transactions.

## Key Features

- **STAS Back-to-Genesis Resolution** — Fully resolves token provenance by tracing each STAS UTXO back to its original genesis transaction, ensuring accurate ownership and lineage verification
- **Selective UTXO Indexing** — Indexes only explicitly configured addresses and token IDs, avoiding full-chain tracking to reduce infrastructure load, storage, and costs
- **Dynamic Address Onboarding** — Add new addresses and token IDs at runtime via the Admin API without reindexing or downtime
- **Multiple Transaction Types** — Natively indexes STAS tokens (STAS, STAS-BTG, dSTAS) and standard P2PKH transactions
- **Real-Time Event Streaming** — Push-based WebSocket notifications via Phoenix Channels for transaction detection, balance changes, and UTXO state updates
- **Fault Tolerant** — Built on the BEAM VM with OTP supervision trees. If a ZMQ listener or RPC connection crashes, only that process restarts
- **Concurrent** — Lightweight Erlang processes handle thousands of concurrent WebSocket connections and parallel transaction processing

## Tech Stack

| Component   | Technology                              |
|-------------|----------------------------------------|
| Runtime     | Elixir 1.15+ / Erlang/OTP 26+         |
| Framework   | Phoenix 1.8                            |
| Database    | PostgreSQL 14+ (Ecto)                  |
| BSV SDK     | [bsv_sdk](https://hex.pm/packages/bsv_sdk) — tx parsing, STAS classification |
| ZMQ         | chumak (pure Erlang ZMQ)               |
| HTTP Client | Req (Finch-backed)                     |
| Real-time   | Phoenix Channels (WebSocket)           |

## Quick Start

Requires Elixir 1.15+, Erlang/OTP 26+, and PostgreSQL 14+.

```bash
# Clone the repository
git clone https://github.com/Bittoku/athanor.git
cd athanor

# Install dependencies and set up the database
mix setup

# Start the server (default port 5000)
mix phx.server
```

Or use Docker Compose:

```bash
# Generate a secret key
export SECRET_KEY_BASE=$(mix phx.gen.secret)

# Start with Docker Compose
docker compose up -d
```

## Configuration

Configure via environment variables:

| Variable              | Default                  | Description                                      |
|-----------------------|--------------------------|--------------------------------------------------|
| `NETWORK`             | testnet                  | BSV network (`mainnet` or `testnet`)             |
| `BSV_NODE_RPC_URL`    | http://localhost:18332   | BSV node JSON-RPC endpoint                       |
| `BSV_NODE_RPC_USER`   | —                        | RPC username                                     |
| `BSV_NODE_RPC_PASSWORD` | —                      | RPC password                                     |
| `ZMQ_RAW_TX`          | tcp://localhost:28332    | ZMQ endpoint for raw transaction notifications   |
| `JUNGLE_BUS_ENABLED`  | false                    | Enable JungleBus cloud streaming                 |
| `PORT`                | 5000                     | HTTP server port                                 |
| `DATABASE_URL`        | —                        | PostgreSQL connection URL (production)            |

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                     Athanor                          │
│                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │
│  │  Blockchain   │  │   Indexing    │  │    API    │ │
│  │    Layer      │  │   Pipeline   │  │   Layer   │ │
│  │              │  │              │  │           │ │
│  │  BSV Node    │  │  ETS Filter  │  │  REST API │ │
│  │  (RPC+ZMQ)  │──│  BSV SDK     │──│  Phoenix  │ │
│  │  JungleBus  │  │  PostgreSQL  │  │  Channels │ │
│  └──────────────┘  └──────────────┘  └───────────┘ │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │              Worker Processes                  │   │
│  │  Chain Tip Verifier · Unconfirmed Monitor    │   │
│  │  Missing Tx Syncer · STAS Attributes Observer│   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

- **Blockchain Layer** — Connects to a BSV node via JSON-RPC for block/transaction queries and ZMQ for real-time notifications. Optionally connects to JungleBus for cloud-based transaction streaming.
- **Indexing Pipeline** — Incoming transactions are filtered against watched addresses and token IDs using an ETS-backed filter for lock-free concurrent reads. Matching transactions are classified by the BSV SDK's STAS token parser, and UTXO state is maintained in PostgreSQL.
- **API Layer** — Phoenix-powered REST API for address balances, UTXO sets, transaction history, and admin operations. Phoenix Channels WebSocket for real-time push notifications.
- **Worker Processes** — Background GenServers for chain tip verification, unconfirmed transaction monitoring, missing transaction sync, and STAS attribute observation — all supervised independently for fault isolation.

## REST API

All endpoints are under `/api` and return JSON.

### Admin Endpoints

```bash
# Register an address to watch
POST /api/admin/manage/address
{ "address": "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", "name": "Treasury Wallet" }

# List all watched addresses
GET /api/admin/manage/addresses

# Register a STAS token ID to track
POST /api/admin/manage/stas-token
{ "token_id": "1TokenRedemptionAddr...", "symbol": "MYTKN" }

# List all watched STAS token IDs
GET /api/admin/manage/stas-tokens

# Check indexer sync status
GET /api/admin/blockchain/sync-status
```

### Address Endpoints

```bash
# Get balances (BSV + tokens)
GET /api/address/:address/balance

# List unspent outputs
GET /api/address/:address/utxos

# Paginated transaction history (?skip=0&take=50)
GET /api/address/:address/history
```

### Transaction Endpoints

```bash
# Look up an indexed transaction
GET /api/transaction/:txid

# Broadcast a raw transaction
POST /api/transaction/broadcast
{ "hex": "0100000001..." }
```

## WebSocket API (Phoenix Channels)

Connect to `ws://localhost:5000/socket/websocket` and join a wallet topic.

### Topics

- `wallet:lobby` — general wallet operations
- `wallet:{address}` — address-specific subscriptions and push notifications

### Events

| Event         | Direction  | Description                                        |
|---------------|------------|----------------------------------------------------|
| `subscribe`   | → server   | Subscribe to address notifications                 |
| `unsubscribe` | → server   | Unsubscribe from address notifications             |
| `get_balance`  | → server   | Query current balances                             |
| `get_utxo_set` | → server   | Query unspent outputs                              |
| `get_history`  | → server   | Query transaction history                          |
| `broadcast`   | → server   | Broadcast a raw transaction                        |
| `new_tx`      | ← server   | Push: new transaction affecting subscribed address |

### Client Example

```javascript
import { Socket } from "phoenix"

const socket = new Socket("ws://localhost:5000/socket/websocket")
socket.connect()

const channel = socket.channel("wallet:1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa")

channel.join()
  .receive("ok", () => console.log("Joined wallet channel"))

// Get current UTXOs
channel.push("get_utxo_set", {})
  .receive("ok", ({ utxos }) => console.log("UTXOs:", utxos))

// Broadcast a transaction built with the STAS SDK
channel.push("broadcast", { hex: rawTxHex })
  .receive("ok", ({ txid, status }) => console.log("Broadcast:", txid, status))

// Listen for real-time notifications
channel.on("new_tx", (payload) => {
  console.log("New transaction:", payload)
})
```

## Related Projects

- [Consigliere](https://github.com/dxsapp/dxs-consigliere) — The original C# / .NET BSV indexer by DXS (RavenDB, SignalR). Athanor provides a compatible API surface.
- [bsv_sdk](https://hex.pm/packages/bsv_sdk) — BSV SDK for Elixir with full STAS token support
- [bsv-sdk-rust](https://github.com/Bittoku/bsv-sdk-rust) — BSV SDK for Rust with full STAS token support
- [STAS Token](https://stastoken.com) — Protocol documentation and developer tools

## License

MIT — Copyright (c) 2026 Jerry David Chan

## Author

[David Chan](https://github.com/digitsu) — [Bittoku](https://bittoku.co.jp)

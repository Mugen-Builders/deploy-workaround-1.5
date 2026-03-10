# Deploying to fly.io

> [!WARNING]
> This guide and `Dockerfile.node` target **`@cartesi/cli` v1.5.x** (rollups-node v1.5.1) only.

This project uses `Dockerfile.node` instead of the default Cartesi node image to work around a **5-second ready-timeout bug** in the Cartesi go-supervisor that causes the `inspect-server` to be killed before it finishes initialising on fly.io.

The fix uses [nitro](https://github.com/leahneukirchen/nitro) as the process supervisor (no ready-timeout) and nginx as the HTTP reverse proxy.

---

## Prerequisites

- [fly CLI](https://fly.io/docs/hands-on/install-flyctl/) installed and logged in (`fly auth login`)
- [Docker](https://www.docker.com/) with BuildKit support (Docker Desktop ≥ 4.x)
- [Cartesi CLI](https://docs.cartesi.io/cartesi-rollups/1.5/development/installation/) installed

---

## First-time setup

### 1. Build the RISC-V machine image

```bash
cartesi build
```

This produces the machine snapshot under `.cartesi/image/`.

### 2. Create the fly.io app

```bash
fly apps create <your-app-name>
```

### 3. Create and attach a Postgres database

```bash
fly postgres create \
  --name <your-app-name>-db \
  --region <your-region>        # e.g. mad, iad, gru

fly postgres attach <your-app-name>-db --app <your-app-name>
```

`fly postgres attach` automatically sets `DATABASE_URL` as a secret. The Cartesi node expects `CARTESI_POSTGRES_ENDPOINT`, so copy the value and set it:

```bash
fly secrets set \
  --app <your-app-name> \
  CARTESI_POSTGRES_ENDPOINT="postgres://<your_app_name>:<password>@<your-app-name>-db.flycast:5432/<your_app_name>?sslmode=disable"
```

> Use the app-specific user URL (not the `postgres` superuser URL). `sslmode=disable` is safe here because `.flycast` is fly.io's encrypted private network.

### 4. Set required secrets

```bash
fly secrets set \
  --app <your-app-name> \
  CARTESI_BLOCKCHAIN_HTTP_ENDPOINT="https://sepolia.infura.io/v3/<YOUR_KEY>" \
  CARTESI_BLOCKCHAIN_WS_ENDPOINT="wss://sepolia.infura.io/ws/v3/<YOUR_KEY>" \
  CARTESI_AUTH_MNEMONIC="word1 word2 word3 ..."
```

> **RPC provider notes:**
> - [Infura](https://infura.io) works well on the free tier for testnets.
> - [Alchemy](https://alchemy.com) requires a paid plan to avoid rate-limit errors under node load.
> - For mainnet deployments, use a provider with WebSocket support and generous rate limits.

| Secret | Description |
|--------|-------------|
| `CARTESI_BLOCKCHAIN_HTTP_ENDPOINT` | RPC HTTP URL (Infura/Alchemy/etc.) |
| `CARTESI_BLOCKCHAIN_WS_ENDPOINT` | RPC WebSocket URL |
| `CARTESI_AUTH_MNEMONIC` | Wallet mnemonic for the authority claimer |
| `CARTESI_AUTH_MNEMONIC_ACCOUNT_INDEX` | (optional) Account index, default `0` |
| `CARTESI_AUTH_PRIVATE_KEY` | Alternative to mnemonic: raw private key `0x...` |
| `CARTESI_POSTGRES_ENDPOINT` | Postgres connection string (set above) |

The non-sensitive contract addresses and chain config are already in `fly.toml [env]`.

---

## Deploy

Run these steps every time you want to push a new version.

```bash
# Rebuild the machine snapshot if dapp code changed
cartesi build

# Build, push and deploy in one step
./deploy.sh
```

<details>
<summary>Manual steps (what deploy.sh does under the hood)</summary>

```bash
fly auth docker

docker build \
  --platform linux/amd64 \
  -f Dockerfile.node \
  -t registry.fly.io/<your-app-name> \
  .cartesi/image/

docker push registry.fly.io/<your-app-name>

fly deploy
```

</details>

---

## Architecture inside the container

`nitro` starts each service as an independent process from its run script in `/etc/nitro/<service>/run`. There is no ready-timeout — services start and restart independently.

| Service | Internal port (BASE=10000) | Purpose |
|---------|---------------------------|---------|
| nginx | 10000 (public) | Reverse proxy + `/healthz` |
| advance-runner | 10001 | Processes inputs from server-manager |
| authority-claimer | 10002 | Submits claims on-chain |
| dispatcher | 10003 | Reads state-server, routes inputs |
| graphql-server | 10004 | GraphQL API |
| indexer | 10008 | Indexes outputs to Postgres |
| inspect-server | 10009 | Handles inspect requests |
| redis | 10011 | Internal message queue |
| server-manager | 10012 | Runs the Cartesi machine |
| state-server | 10013 | Tracks on-chain state |

nginx routes external traffic:

| Path | Proxied to |
|------|-----------|
| `GET /healthz` | 200 OK (nginx itself) |
| `/graphql` | graphql-server (10004) |
| `/inspect[/*]` | inspect-server (10009) |
| `/metrics` | dispatcher (10003) |

Services with dependencies (`advance-runner`, `inspect-server`, `dispatcher`) poll their dependency's port in a loop before executing — no external tooling needed.

---

## Troubleshooting

```bash
# Live logs
fly logs --app <your-app-name>

# SSH into the running machine
fly ssh console --app <your-app-name>

# Check which secrets are set (values are redacted)
fly secrets list --app <your-app-name>

# Scale up memory if server-manager OOMs
fly scale memory 4096 --app <your-app-name>
```

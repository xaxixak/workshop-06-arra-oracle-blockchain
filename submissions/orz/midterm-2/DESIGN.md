# Orz midterm-2 design — op-reth based OP Stack chain

> **Status**: design only (this commit). Implementation in subsequent session.
> **Assignment**: workshop-06 midterm #2 — deploy real chain using op-reth / reth family
> **Issued**: 2026-06-20 05:46 UTC by ก้อง / nazt (Discord msg `1517767510685126756`)

## Why op-reth (vs op-geth from session #1)

| dimension | op-geth (workshop-06 session) | op-reth (this assignment) |
|---|---|---|
| language | Go | Rust |
| EVM impl | go-ethereum fork | revm (Rust EVM) |
| memory profile | larger (Go GC) | smaller (Rust ownership) |
| state DB | Pebble (Go) | MDBX (Rust) |
| maintainer | Optimism + ethereum foundation | Paradigm + Optimism |
| OP Stack support | reference implementation | growing (Holocene+ supported) |
| use case | proven default | bleeding edge, perf focus |

**Why workshop wants op-reth**: prove that OP Stack rollup is **client-agnostic at the EL** — the rollup spec (rollup.json, batches, derivation) should work across any conformant execution client. op-reth as alternative EL = stress test of CL/EL separation.

## Architecture

```
                  L1 Sepolia (anchor)
                       ▲
                       │ batches via BatchInbox
                       │
       ┌───────────────┴──────────────────┐
       │  op-batcher (unchanged, Go)      │
       └───────────────▲──────────────────┘
                       │ rollup.json
                       │
                       │ engine_newPayloadV3 ← engine API JWT
              ┌────────┴───────┐                  ┌────────────────────┐
              │   op-node      │ ◄────── L2 P2P ──► │  op-node (peer)    │
              │ (CL, unchanged)│                  └────────────────────┘
              └────────┬───────┘
                       │ engine_newPayloadV3 / engine_forkchoiceUpdatedV3
                       │
                       ▼
              ┌────────────────┐
              │   op-reth      │ ← NEW (Rust execution layer)
              │  --chain custom│
              │  --datadir ... │
              └────────────────┘
```

**key insight**: only the EL (op-reth ↔ op-geth swap) changes. CL (op-node) + batcher unchanged. JWT engine API is the contract.

## op-reth flag mapping (from op-geth → op-reth)

| op-geth flag | op-reth equivalent | notes |
|---|---|---|
| `--datadir=$DATA` | `--datadir $DATA` | same concept |
| `--networkid=$ID` | `--chain custom-genesis.json` | reth uses chain spec file |
| `--syncmode=full` | `--full` | flag is implicit in op-reth |
| `--http.port=$PORT` | `--http --http.port $PORT` | similar |
| `--authrpc.port=$PORT` | `--authrpc.port $PORT` | engine API |
| `--authrpc.jwtsecret=$JWT` | `--authrpc.jwtsecret $JWT` | engine API JWT |
| `--rollup.disabletxpoolgossip=true` | `--rollup.disable-tx-pool-gossip` | naming convention diff |
| `--rollup.sequencerhttp=$URL` | `--rollup.sequencer-http $URL` | naming convention diff |
| `--port=$DEVP2P` | `--port $DEVP2P` | devp2p (rarely needed in OP) |
| init: `op-geth init genesis.json` | reth init: `op-reth init --chain genesis.json` | sequence is similar |

**flag inventory** done from op-reth `--help` v1.0+ (check at impl time — flag names may have evolved per release).

## Makefile structure (step-by-step deploy)

```makefile
# orz-opreth-chain — step-by-step Makefile for OP Stack chain with op-reth EL
# Usage:
#   make preflight  → check tools + accounts
#   make wallet     → generate fresh wallets (deployer, batcher, sequencer)
#   make deploy-l1  → deploy OP Stack L1 contracts (op-deployer)
#   make genesis    → generate genesis.json + rollup.json from deploy output
#   make init       → op-reth init from genesis
#   make sequencer  → start op-reth + op-node (sequencer mode)
#   make batcher    → start op-batcher
#   make verify     → verify L1 batch + L2 head match
#   make follower   → start op-reth + op-node (follower mode, peer to sequencer)
#   make snapshot   → snapshot datadir to .old-chain-<height>

include .env
# REQUIRED env: L1_RPC, L1_BEACON, SEPOLIA_FUNDED_PK, CHAIN_ID,
#               OP_RETH_BIN, OP_NODE_BIN, OP_BATCHER_BIN, OP_DEPLOYER_BIN

preflight:
	@command -v $(OP_RETH_BIN) >/dev/null || (echo "op-reth not in PATH"; exit 1)
	@command -v $(OP_NODE_BIN) >/dev/null || (echo "op-node not in PATH"; exit 1)
	@command -v cast >/dev/null || (echo "cast not in PATH (foundry)"; exit 1)
	@echo "✅ preflight OK"

wallet:
	@mkdir -p $(WALLET_DIR)
	@cast wallet new --json > $(WALLET_DIR)/deployer.json && chmod 600 $(WALLET_DIR)/deployer.json
	@cast wallet new --json > $(WALLET_DIR)/batcher.json  && chmod 600 $(WALLET_DIR)/batcher.json
	@cast wallet new --json > $(WALLET_DIR)/sequencer.json && chmod 600 $(WALLET_DIR)/sequencer.json
	@openssl rand -hex 32 > $(WALLET_DIR)/jwt.txt && chmod 600 $(WALLET_DIR)/jwt.txt
	@openssl rand -hex 32 > $(WALLET_DIR)/p2p_priv.txt && chmod 600 $(WALLET_DIR)/p2p_priv.txt
	@echo "deployer:  $$(jq -r '.[0].address' $(WALLET_DIR)/deployer.json)"
	@echo "batcher:   $$(jq -r '.[0].address' $(WALLET_DIR)/batcher.json)"
	@echo "sequencer: $$(jq -r '.[0].address' $(WALLET_DIR)/sequencer.json)"
	@echo "→ fund deployer + batcher addresses on L1 Sepolia before deploy-l1"

deploy-l1:
	@DEPLOYER_PK=$$(jq -r '.[0].private_key' $(WALLET_DIR)/deployer.json) && \
		BATCHER_ADDR=$$(jq -r '.[0].address' $(WALLET_DIR)/batcher.json) && \
		$(OP_DEPLOYER_BIN) init --l1-rpc-url $(L1_RPC) --intent intent.toml && \
		$(OP_DEPLOYER_BIN) apply --intent intent.toml --workdir deployer-workdir \
			--deployer-private-key $$DEPLOYER_PK

genesis:
	@$(OP_DEPLOYER_BIN) inspect genesis --workdir deployer-workdir --chain-id $(CHAIN_ID) \
		> genesis.json
	@$(OP_DEPLOYER_BIN) inspect rollup --workdir deployer-workdir --chain-id $(CHAIN_ID) \
		> rollup.json
	@echo "L2 genesis hash: $$(jq -r '.genesis.l2.hash' rollup.json)"

init:
	@mkdir -p $(DATADIR)
	@$(OP_RETH_BIN) node --datadir $(DATADIR) --chain genesis.json init
	# verify: reth log "Wrote genesis state hash=<hash>"

sequencer:
	@$(OP_RETH_BIN) node \
		--datadir $(DATADIR) \
		--chain genesis.json \
		--http --http.addr 0.0.0.0 --http.port 8545 --http.api eth,net,web3,debug \
		--ws --ws.addr 0.0.0.0 --ws.port 8546 \
		--authrpc.addr 0.0.0.0 --authrpc.port 8551 \
		--authrpc.jwtsecret $(WALLET_DIR)/jwt.txt \
		--port 30303 \
		--rollup.sequencer-http http://127.0.0.1:8545 \
		--rollup.disable-tx-pool-gossip \
		>op-reth.log 2>&1 &
	@sleep 5
	@$(OP_NODE_BIN) \
		--l1 $(L1_RPC) --l1.beacon $(L1_BEACON) \
		--l2 http://127.0.0.1:8551 --l2.jwt-secret $(WALLET_DIR)/jwt.txt \
		--rollup.config rollup.json \
		--p2p.priv.path $(WALLET_DIR)/p2p_priv.txt \
		--p2p.sequencer.key $$(jq -r '.[0].private_key' $(WALLET_DIR)/sequencer.json) \
		--sequencer.enabled \
		>op-node.log 2>&1 &

batcher:
	@BATCHER_PK=$$(jq -r '.[0].private_key' $(WALLET_DIR)/batcher.json) && \
		$(OP_BATCHER_BIN) \
			--l1-eth-rpc $(L1_RPC) \
			--l2-eth-rpc http://127.0.0.1:8545 \
			--rollup-rpc http://127.0.0.1:9547 \
			--private-key $$BATCHER_PK \
			--num-confirmations 1 \
			>op-batcher.log 2>&1 &

verify:
	@echo "L2 head:"
	@cast block-number --rpc-url http://127.0.0.1:8545
	@echo "Sync status:"
	@curl -s -X POST -H "Content-Type: application/json" \
		--data '{"jsonrpc":"2.0","method":"optimism_syncStatus","id":1,"params":[]}' \
		http://127.0.0.1:9547 | jq '.result'

follower:
	@# similar to sequencer but without --sequencer.enabled and --p2p.sequencer.key
	@# Add --p2p.static for sequencer peer multiaddr

snapshot:
	@HEIGHT=$$(cast block-number --rpc-url http://127.0.0.1:8545) && \
		mv $(DATADIR) $(DATADIR).snap-$$HEIGHT && \
		echo "snapshot → $(DATADIR).snap-$$HEIGHT"

clean:
	@rm -rf $(DATADIR) deployer-workdir genesis.json rollup.json *.log

.PHONY: preflight wallet deploy-l1 genesis init sequencer batcher verify follower snapshot clean
```

## known unknowns / risks

1. **op-reth + op-node engine API compatibility**: need to verify `engine_newPayloadV3` + `engine_forkchoiceUpdatedV3` semantics match between op-reth and op-node version pair. Possibly need specific minor versions.

2. **op-reth chain spec format**: may differ from op-geth's `genesis.json`. Might need to use `--chain custom` with a reth-specific JSON schema (not OP Stack genesis spec verbatim). Verify at impl time.

3. **MDBX vs Pebble database differences**: snapshot/restore strategies may differ. Backup workflow needs adaptation.

4. **op-reth Holocene/Jovian/Isthmus/Jovian/Karst/Lagoon hardfork support**: ensure target chain config matches op-reth supported hardforks. Workshop chain v4 has all hardforks "@genesis" = needs op-reth that supports them all.

5. **Performance baseline**: should benchmark op-reth vs op-geth on same chain to justify the swap (lower memory? faster sync? more TPS?).

## Phase plan

| Phase | Goal | Status |
|---|---|---|
| 0 | This DESIGN.md commit | ✅ this commit |
| 1 | Discord/Discussion post: invite peer Oracle feedback on design | next session |
| 2 | Source op-reth binary (build or download release) for Linux x86-64 | next session |
| 3 | Implement Makefile end-to-end on natz-ai-03 server | next session |
| 4 | Spin up sequencer-mode chain + verify L1 batch posting | next session |
| 5 | Spin up follower-mode (peer to Nova's chain v4 with op-reth EL) | next session |
| 6 | PR to workshop-06 with full Makefile + DESIGN + proof | next session |

## References

- op-reth docs: https://github.com/paradigmxyz/reth
- OP Stack spec: https://specs.optimism.io/
- Workshop-06 PR #14 (Nova's op-geth-based deploy) for op-geth reference
- Workshop-06 PR #13 (Orz's follower kit + technical book "สร้าง Chain ของจริง")

— Orz Oracle 🎼 (Phase 0 commit only — implementation continues in fresh session)

# HEAD-MATCH PROOF — Orz follower on Nova canonical chain v4

> **Captured**: 2026-06-20 04:32 UTC
> **Chain**: workshop-06 ARRA Oracle Blockchain (chain-id `20260619`)
> **Genesis (v4)**: `0x1c9445c6cac6880fae00b45dedfc8bf43ce5fd39ec8eb9053b02e2e89a09ff23`
> **L1 anchor**: Sepolia testnet (`11155111`)

## Sync state

| Field | Orz follower | Nova canonical |
|---|---|---|
| `unsafe_l2` | 1715 | 1737 (gap 22 ≈ 44s — normal follower lag) |
| `safe_l2` | 1715 | — |
| `finalized_l2` | 1091 | — |
| `current_l1` | 11099053 | — |

## Byte-for-byte block hash proof

### Block 1091 (finalized)

```
Orz:  0xbcc9cbce57811e79ab8a0f0c0413075702acb5a8fc4b4bbe7cb50ae87e784d53
Nova: 0xbcc9cbce57811e79ab8a0f0c0413075702acb5a8fc4b4bbe7cb50ae87e784d53
                                       ✅ IDENTICAL
```

### Block 1715 (safe head)

```
Orz:  0xecb51655d510c3a9c39b83fb5bd8a52da8db066fa8105459ff8456aeb2bdbd9a
Nova: 0xecb51655d510c3a9c39b83fb5bd8a52da8db066fa8105459ff8456aeb2bdbd9a
                                       ✅ IDENTICAL
```

## Verification commands (anyone can re-run)

```bash
# Get Orz follower block hash (via ssh + curl to internal RPC)
ssh oracle-school@141.11.156.4 'curl -s -X POST -H "Content-Type: application/json" \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"id\":1,\"params\":[\"0x443\",false]}" \
  http://127.0.0.1:19545' | jq -r '.result.hash'

# Get Nova canonical block hash (via public RPC)
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","id":1,"params":["0x443",false]}' \
  http://141.11.156.4:9545 | jq -r '.result.hash'
```

`0x443` = block 1091. `0x6b3` = block 1715. Substitute hex for other block numbers.

## What this proves

1. **L1 derivation path works end-to-end**: Orz follower's `op-node` walked Sepolia L1 from genesis origin (L1 block `11098766`), found batch txs posted by batcher `0x644Da211BB604B58666b8a9a2419E4F3F2aceC0A` → `0x00B183C4dd52…` BatchInbox, decoded them into L2 payloads, fed them via engine API to `op-geth`, which built the canonical chain — and the resulting block hashes match Nova's locally-sequenced chain byte-for-byte.

2. **L1 finality verified**: `finalized_l2 = 1091` means Sepolia L1 has confirmed (with 2 finality epochs) that the L1 batch txs containing L2 blocks 0..1091 are now immutable. The L2 chain history through block 1091 is anchored to Sepolia security.

3. **No P2P shortcut**: Orz follower configured `--syncmode=consensus-layer`. The byte-for-byte match was achieved purely via L1 derivation (path 2 in the OP Stack spec). P2P gossip (path 1) was peered but not the source of historical sync.

## Configuration that worked

```
genesis source:  /home/oracle-school/op-stack/genesis-l2-20260619.json  (authoritative — Nova workspace)
rollup source:   /home/oracle-school/op-stack/rollup.json                (same)
peer ID (v4):    16Uiu2HAkzt25EFAurBMAYJzwExEGKV4aUYkce7aRbEZwUDFmXoao
op-node flags:   --syncmode=consensus-layer
                 --p2p.static=/ip4/141.11.156.4/tcp/9227/p2p/<peer_id>
                 --l1=https://ethereum-sepolia-rpc.publicnode.com
                 --p2p.discovery.path/peerstore.path (unique per Oracle)
```

## What did NOT work (recorded for future Oracles)

- **HTTP server `:8181`**: serves stale `genesis.json` (timestamp `0x6a35d560` = chain v3 deprecated). `rollup.json` was updated but `genesis.json` was not. Following the HTTP server caused `op-node` crash with "L2 genesis hash mismatch" (`0xf26a66…` vs `0xe365a0cf…`).
- **Trust nazt's announcement message**: announcement said `0xe365a0cf…` but the actual deployed chain (after silent redeploy minutes later) had genesis `0x1c9445c6…`. Always probe RPC for ground truth.

## Lesson recorded

Authority follows `mtime`, not the announcement. When source-of-truth is distributed across (a) HTTP cache, (b) announcement message, (c) RPC live state, (d) filesystem working dir — the filesystem with latest `mtime` is the safest probe target.

— Orz Oracle 🎼 *the Golden Conductor*

---

## DUAL PATH PROOF (2026-06-20 05:01 UTC)

After Nova added `--p2p.sequencer.key` flag (fix shipped by DustBoy/B3 diagnosis), Path 2 P2P gossip began working. Orz follower now demonstrates **both** OP Stack sync paths simultaneously:

### State

```
unsafe_l2 = 2612   (= Nova head exactly — real-time via P2P gossip)
safe_l2   = 2591   (L1-derived, 21 blocks behind unsafe = expected)
finalized = 2054   (L1 finality confirmed)
peers     = 7 connected
```

### Path 2 (P2P gossip) — block 2612 byte-for-byte

```
Orz:  0x4e4e46f8a3d12f2c10fc344b0a6bf8b98e70c44eda486918cb31bf22a62225e8
Nova: 0x4e4e46f8a3d12f2c10fc344b0a6bf8b98e70c44eda486918cb31bf22a62225e8
                                     ✅ IDENTICAL
```

### Path 1 (L1 derivation) — block 2591 byte-for-byte

```
Orz:  0x8805ac3b9faff05835aef8f84422bf12876bc47dc15bf2cab9a164158c4644c8
Nova: 0x8805ac3b9faff05835aef8f84422bf12876bc47dc15bf2cab9a164158c4644c8
                                     ✅ IDENTICAL
```

### Verification log line

```
t=2026-06-20T05:01:15+0000 lvl=info msg="Inserted new L2 unsafe block (synchronous)" 
  hash=0x4e4e46f8a3d12f2c10fc344b0a6bf8b98e70c44eda486918cb31bf22a62225e8 
  number=2612 newpayload_time=4.416ms fcu2_time=1.193ms total_time=5.612ms
```

The "(synchronous)" qualifier indicates this block arrived via P2P gossip and was inserted via the `engine_newPayloadV3` engine API path — exactly the OP Stack CL→EL flow for unsafe block propagation.

### Workshop conclusion

The OP Stack spec promises that L1 derivation (Path 1, canonical) and L2 P2P gossip (Path 2, real-time) can run simultaneously on a single follower instance with complementary outcomes. This proof captures that simultaneity on Orz follower with byte-for-byte parity on both paths against Nova canonical, after the fleet collectively diagnosed (DustBoy + B3) and resolved (Nova maintainer) the missing `--p2p.sequencer.key` flag on the sequencer.

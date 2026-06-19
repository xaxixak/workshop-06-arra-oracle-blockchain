# Orz L2 sync kit — Nova canonical follower

> One-command bring-up of an OP Stack L2 follower peered with Nova (workshop-06 chain-id `20260619`).

## TL;DR

```bash
# On natz-ai-03 (oracle-school@141.11.156.4):
curl -fsSL https://raw.githubusercontent.com/xaxixak/workshop-06-arra-oracle-blockchain/orz-submission/submissions/orz/l2-sync/sync.sh \
  | bash -s -- myname 30000
```

That's it. Replace `myname` (your Oracle name) and `30000` (your port-offset; pick anything 10k+ that isn't used). Output is sync proof: L2 head, Nova head, peer count, sync_status.

## What's in this dir

| File | Source | Notes |
|---|---|---|
| `genesis.json` | `/home/oracle-school/op-stack/genesis-l2-20260619.json` | Nova canonical L2 genesis (9.5 MB) |
| `rollup.json`  | `/home/oracle-school/op-stack/rollup.json` | L2 chain config — L2 hash `0x563326cd…086784` |
| `sync.sh`      | this file | One-command follower bring-up |
| `README.md`    | this file | what you're reading |

## Pre-reqs

- Run on `oracle-school@141.11.156.4` (the workshop server)
- Binaries available at `/home/oracle-school/op-stack/op-geth-binary` and `/op-node`
- Override binary location with `OPSTACK=/somewhere/else bash sync.sh ...`

## Port plan

The script picks 6 ports from your `OFFSET` arg:

| service | port |
|---|---|
| op-geth HTTP | `$OFFSET + 545` |
| op-geth WS | `$OFFSET + 546` |
| op-geth AuthRPC (engine API to op-node) | `$OFFSET + 551` |
| op-geth devp2p | `$OFFSET + 303` |
| op-node RPC | `$OFFSET + 547` |
| op-node libp2p (TCP+UDP) | `$OFFSET + 227` |

For `OFFSET=30000`: ports `30545/30546/30551/30303/30547/30227`. Pick an offset nobody else is using. Orz used `+10000` (ports 19xxx), Nova uses `9xxx`, ChaiKlang's running follower templates may be at other offsets — `ss -tlnH` shows what's taken.

## Proof you'll see

When sync is **healthy** (Nova batcher posting + libp2p gossip working):
```
L2 head (this node):   500+
L2 head (Nova @9545):  500+   (within ~5 of yours)
libp2p peers:          1-3 connected
unsafe_l2 = 500+
safe_l2   = 480+  (derived from L1)
current_l1 = 11094xxx  (advancing)
```

When sync is **blocked on Nova batcher mismatch** (current workshop state at 11:50 UTC):
```
L2 head (this node):   0
L2 head (Nova @9545):  600+   (Nova producing but not batching cleanly)
libp2p peers:          1-3   (peered, but no historical sync via gossip)
unsafe_l2 = 0
safe_l2   = 0
current_l1 = 11094xxx (L1 traversal works)
```

If you see the second pattern, check `op-node.log`:
```
grep -i "unauthorized submitter" ~/$YOUR_NAME-l2-sync/op-node.log
```
If that appears: Nova's L1 batch submitter ≠ `rollup.json` `batcherAddr`. Not your fault — Nova needs to reconcile.

## Kill

```bash
pgrep -af "$YOUR_NAME-l2-sync" | awk '{print $1}' | xargs -r kill
```

## How this differs from the other sync PRs

| PR | layer | sync mechanism | genesis |
|---|---|---|---|
| #2 Chaiklang | L1 Clique | geth devp2p | `0xb27b68…` cluster |
| #7 Bongbaeng | L1 Clique | geth devp2p | `0xedf353…` cluster |
| #11 Sombo | L1 Clique | geth devp2p | `0xedf353…` cluster |
| #14 Nova | L2 OP Stack | sequencer (this PR's target) | `0xd5fff5…` then re-init to `0x563326cd…` |
| **#13 Orz `l2-sync/`** | **L2 OP Stack follower** | **libp2p static-peer + L1 derivation** | **`0x563326cd…` (Nova canonical)** |

This kit is the **follower template for Nova** — same role as the revised Leica #8 but with a verified working `bash` recipe + the diagnosed "unauthorized submitter" pattern documented.

## Authorship

— Orz Oracle 🎼 (AI, ไม่ใช่คน — Rule 6) — workshop-06 contribution from `xaxixak/workshop-06-arra-oracle-blockchain/orz-submission`

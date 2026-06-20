## §5 follower template — dual path (L1 derive + P2P gossip)

**ทุก non-sequencer Oracle ในห้องเรียน = follower**. follower setup ต้องสามารถ verify chain จาก 2 paths พร้อมกัน — L1 derivation (canonical, slow) + P2P gossip (real-time, fast)

### path 1 — L1 derivation (canonical, slow)

```
op-node → L1 RPC (Sepolia) → walk forward → ที่ batch tx → decode → engine_newPayloadV3 → op-geth → save block
```

flow โดยละเอียด:
1. op-node start ที่ `genesis.l1.number` (e.g. 11098766)
2. fetch L1 block N → ตรวจทุก tx ที่ to=BatchInbox
3. filter tx by from=`rollup.json.system_config.batcherAddr` (= §4 alignment gate)
4. decompress channel → extract frames → reconstruct L2 blocks
5. for each L2 block: call `engine_newPayloadV3` on op-geth → op-geth append
6. increment current_l1 → repeat

**properties**:
- safe block (= L1 derive) ใช้ได้แม้ Nova sequencer ตาย
- ช้า (rate-limited L1 RPC, ~10-70 blocks/sec on Sepolia public)
- canonical — ถ้า follower derive ได้ block ที่ hash match → ถูกแน่นอน

**Orz's first proof (Path 1 only)** ที่ 04:32 UTC:
```
safe_l2:      1715  0xecb51655d510…
finalized_l2: 1091  0xbcc9cbce5781…
nova_head:    1737  (lag 22 blocks expected, normal)

byte-for-byte block 1091: ตรง 100%
byte-for-byte block 1715: ตรง 100%
```

### path 2 — L2 P2P gossip (real-time, fast)

```
sequencer's op-node → sign block payload → publish ผ่าน libp2p gossip → follower's op-node → engine_newPayloadV3 → op-geth → save block as "unsafe"
```

flow:
1. sequencer's op-node produce block N (timestamp ใหม่)
2. sign payload with `--p2p.sequencer.key` (= §3 critical flag)
3. broadcast over libp2p gossip topic
4. all peers subscribed รับ block → verify signature → forward to engine API
5. op-geth append → unsafe_l2 advance

**properties**:
- real-time (ทันที sequencer produce)
- "unsafe" — reorg possible ถ้า L1 batch ไม่ confirm
- ต้อง libp2p connectivity ทำงาน (= §3 requirement)
- ต้อง follower configure `--p2p.static=<sequencer_multiaddr>`

**Orz's dual proof** ที่ 05:01 UTC (หลัง Nova เพิ่ม sequencer.key):
```
unsafe_l2:    2612  ← = Nova head EXACTLY (lag 0)
safe_l2:      2591  ← lag 21 vs unsafe = expected
finalized_l2: 2054  ← L1 finality

byte-for-byte block 2612 (P2P path): ตรง 100%
byte-for-byte block 2591 (L1 derive): ตรง 100%
```

### follower template — full op-geth + op-node command set

```bash
ME=/home/oracle-school/orz-l2-sync
OPSTACK=/home/oracle-school/op-stack

# port offset = pick unique (Orz uses 19xxx, Nova 9xxx)
OFF=19000

# 1. init op-geth with genesis from rollup
$OPSTACK/op-geth-binary --datadir=$ME/datadir init $ME/genesis.json
# verify: log "Successfully wrote genesis state database=chaindata hash=<L2_HASH>"

# 2. start op-geth (execution layer)
nohup $OPSTACK/op-geth-binary \
  --datadir=$ME/datadir --networkid=$L2_CHAIN_ID \
  --syncmode=full --gcmode=archive \
  --http --http.addr=0.0.0.0 --http.port=$((OFF+545)) \
  --http.api=eth,net,web3,debug,engine --http.corsdomain=* \
  --ws --ws.addr=0.0.0.0 --ws.port=$((OFF+546)) \
  --authrpc.addr=0.0.0.0 --authrpc.port=$((OFF+551)) \
  --authrpc.jwtsecret=$ME/jwt.txt \
  --port=$((OFF+303)) \
  --nodiscover --maxpeers=10 \
  --rollup.disabletxpoolgossip=true \
  --rollup.sequencerhttp=$SEQUENCER_HTTP \
  --verbosity=3 \
  >$ME/op-geth.log 2>&1 &

# 3. start op-node (consensus layer)
nohup $OPSTACK/op-node \
  --l1=$L1_RPC \
  --l1.beacon.ignore=true --l1.trustrpc=true \
  --l2=http://127.0.0.1:$((OFF+551)) \
  --l2.jwt-secret=$ME/jwt.txt \
  --rollup.config=$ME/rollup.json \
  --rpc.addr=0.0.0.0 --rpc.port=$((OFF+547)) \
  --p2p.listen.ip=0.0.0.0 --p2p.listen.tcp=$((OFF+227)) --p2p.listen.udp=$((OFF+227)) \
  --p2p.priv.path=$ME/opnode_p2p_priv.txt \
  --p2p.discovery.path=$ME/p2p_discovery_db \   # ← Orz catch: avoid lock collision
  --p2p.peerstore.path=$ME/p2p_peerstore_db \
  --p2p.static=$SEQUENCER_MULTIADDR \           # ← path 2 requirement
  --syncmode=consensus-layer \                  # ← enable both paths
  --metrics.enabled=false \
  >$ME/op-node.log 2>&1 &
```

### diagnostic — both paths working?

```bash
# query optimism_syncStatus
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"optimism_syncStatus","id":1,"params":[]}' \
  http://127.0.0.1:$OPNODE_RPC | jq '.result | {unsafe:.unsafe_l2.number, safe:.safe_l2.number, finalized:.finalized_l2.number, l1:.current_l1.number}'

# interpret:
# unsafe > 0 + safe = unsafe   → BOTH paths working ✅
# unsafe > 0 + safe = 0        → path 2 (P2P) only, batcher not posting
# unsafe = 0 + safe > 0        → path 1 (L1) only, sequencer P2P broken (§3 trap)
# unsafe = 0 + safe = 0        → neither path; check peer + L1 RPC
```

### snapshot strategy — Nothing is Deleted

ทุก chain redeploy → Orz backup datadir เก่าก่อน re-init:
```bash
# Nothing is Deleted (Fleet SOP §6.5)
mv $ME/datadir $ME/datadir.chain-v<N>-safe<HEIGHT>
# → history accessible for post-mortem analysis
```

Orz vault ตอนนี้:
```
/home/oracle-school/orz-l2-sync.old-chain-safe8477          v1 canonical fork
/home/oracle-school/orz-l2-sync.old-chain-v2-safe2045        v2 batcher-mismatch
/home/oracle-school/orz-l2-sync/datadir.wrong-genesis-f26a66 v3 HTTP cache crash
/home/oracle-school/orz-l2-sync/datadir                       v4 active dual-path
```

→ §6: failure chronology (v1 → v4)

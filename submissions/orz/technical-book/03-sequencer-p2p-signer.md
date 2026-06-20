## §3 🔧 sequencer — `--p2p.sequencer.key` หนึ่งบรรทัดที่ปลด deadlock

**บทเรียนใหญ่ที่สุดของ workshop**: P2P sync ของ OP Stack ไม่ใช่ "เปิดแล้วใช้ได้" — sequencer ต้องมี **signing key** สำหรับ sign block ที่จะ gossip. ขาด flag เดียว → ทุก follower ติด unsafe_l2 = 0 ตลอดกาล

### the smoking-gun log line

DustBoy (PhD Oracle) เป็นคน catch ตอน 04:43 UTC:
```
"failed to publish newly created block" 
err="node has no p2p signer, payload cannot be published"
```

ทุก block ที่ sequencer produce → trigger warning นี้ → ไม่ publish ผ่าน libp2p gossip → followers ไม่ได้รับ unsafe blocks → ทุกคนติด 0

B3 Oracle confirm จาก vantage ของ B3 follower: `peers: None` + `error reconnecting to static peer ... all dials failed` ทั้งที่ peer-id ตรง + TCP :9227 เปิด

### root cause

OP Stack's libp2p gossip layer มี security requirement: ทุก unsafe block ที่ส่ง P2P ต้องถูก sign โดย sequencer's signing key. follower verifies ว่า block มาจาก authorized sequencer ก่อน accept

`op-node` ของ sequencer ต้องการ flag:
```bash
--p2p.sequencer.key=<private-key-hex>
```
flag นี้ระบุ private key ที่ op-node จะใช้ sign block payload before broadcasting. flag ไม่จำเป็นสำหรับ follower (followers verify, ไม่ sign)

### the fix

Nova owner เพิ่ม flag ใน `start-node.sh`:
```bash
op-node \
  ... # other flags
  --p2p.sequencer.key=<HEX_PRIVATE_KEY>
```

หลัง restart op-node:
- Nova's op-node ที่ produce block 2497+ เริ่ม sign payload
- Tonk's follower (ที่ตั้ง `--p2p.static=...Nova...` ไว้แต่แรก) connect P2P ได้ทันที, 2 peers connected
- Orz follower (config เดียวกัน) — 7 peers ภายใน 30 วินาที, unsafe_l2 = Nova head EXACTLY ที่ block 2612

byte-for-byte block 2612 hash:
```
Orz follower:  0x4e4e46f8a3d12f2c10fc344b0a6bf8b98e70c44eda486918cb31bf22a62225e8
Nova canonical: 0x4e4e46f8a3d12f2c10fc344b0a6bf8b98e70c44eda486918cb31bf22a62225e8
                                          ✅ IDENTICAL
```

### implications สำหรับ chain ใหม่

1. **sequencer's libp2p key คนละตัว** กับ batcher / deployer / sequencer-EOA. มันคือ "block-signer key" — เก็บใน file, ไม่ใช่ wallet
2. **followers ไม่ต้องรู้** key นี้ — แค่รู้ peer ID (derived from public key)
3. **ทุก redeploy** ที่ generate libp2p key ใหม่ → ทุก follower ต้องอัพเดท `--p2p.static=...<new_peer_id>`. ถ้าใช้ key เดิม → peer ID เดิม → followers reconnect อัตโนมัติ (Nova v2→v3 ทำแบบนี้)

### sequencer flags ที่ workshop ใช้ (verified)

```bash
op-node \
  --l1=<sepolia_rpc> \
  --l1.beacon.ignore=true --l1.trustrpc=true \
  --l2=http://127.0.0.1:8551 --l2.jwt-secret=$JWT \
  --rollup.config=rollup.json \
  --rpc.addr=0.0.0.0 --rpc.port=9547 \
  --p2p.listen.ip=0.0.0.0 --p2p.listen.tcp=9227 --p2p.listen.udp=9227 \
  --p2p.priv.path=$LIBP2P_PRIV_KEY \
  --p2p.sequencer.key=$SEQUENCER_SIGNING_KEY \   # ← CRITICAL
  --sequencer.enabled=true \
  --syncmode=consensus-layer \
  --metrics.enabled=false
```

### diagnostic commands

```bash
# verify sequencer ส่ง gossip ได้:
tail -f $LOG | grep -i "publish\|signer"
# normal:  "Successfully published L2 block" hash=0x... number=N
# trap:    "failed to publish newly created block" err="node has no p2p signer"

# verify peer connection จาก follower:
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"opp2p_peers","id":1,"params":[true]}' \
  http://127.0.0.1:9547 | jq '.result.peers | length'
# 0 = sequencer ไม่ publish (P2P signer missing) หรือ peer-id ผิด
# 1+ = peer connected, gossip flowing
```

### credit

- **DustBoy / PhD Oracle** — diagnose โดย grep "no p2p signer" ใน Nova's op-node log (msg `1517751959354998928`)
- **B3 Oracle** — confirm จาก follower vantage โดยเช็ค `peers: None` + dial fail (msg `1517752180218663002`)
- **Nova maintainer** — เพิ่ม flag + restart sequencer (msg `1517756130246525018`)
- **Tonk Oracle** — first to verify dual-path proof หลัง fix (msg `1517756130246525018`)
- **Orz Oracle** — DUAL HEAD-MATCH proof (Path 1 + Path 2 simultaneously, msg `1517756395989106822`)

→ §4: batcher + rollup.json batcherAddr alignment

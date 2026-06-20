## §4 batcher — rollup.json `batcherAddr` ต้องตรง submitter

**บทเรียน chain v2**: op-node verify ทุก L1 batch tx ก่อน decode. ถ้า "from" address ของ tx ไม่ตรงกับ `rollup.json.genesis.system_config.batcherAddr` → reject ว่า "unauthorized submitter" → safe_l2 ไม่ขยับ

### the trap (chain v2 incident)

Nova deploy chain v2. rollup.json ระบุ:
```json
"batcherAddr": "0xd8f504d1b96447d951f08c93cfedfd378db91a26"
```
แต่ batcher service ของ Nova ตอนนั้น **ใช้ pool wallet** สำหรับ post batch:
```
op-batcher --private-key=<POOL_PK>  # POOL = 0x644Da211BB604B58666b8a9a2419E4F3F2aceC0A
```
ผลคือ ทุก batch tx ถูก post จาก `0x644Da…` ไป BatchInbox `0x00B183C4…`. Followers' op-node สแกน L1 → เห็น tx → check authorization:
```
warn "tx in inbox with unauthorized submitter" 
  origin=<L1_BLOCK_HASH>:11094046
  addr=0x644Da211BB604B58666b8a9a2419E4F3F2aceC0A
```
batch ถูก discard → ไม่มี safe block ผลิต → ทั้ง fleet stuck

### Orz's diagnosis (2026-06-20 02:51 UTC)

ใช้ blockscout API audit ทุก outgoing tx ของ batcher addr:
```bash
curl -s "https://eth-sepolia.blockscout.com/api/v2/addresses/0xA9964a9Cf3fB2d2bf4559d72011cb22738Bd3920/transactions?filter=from"
# total outgoing: 1
# ทั้งหมดเป็น tx ของ Orz เอง (test transfer ที่ทดสอบ leaked PK work)
# = batcher service ของ Nova ไม่เคย post ผ่าน address นี้เลย
```

ขณะเดียวกัน Nova's batcher service เป็น process ที่รันต่อ — แต่ใช้ key คนละตัว. nazt confirmed: distributed throwaway PK ให้ batcher แต่ service ยัง config ใช้ pool key

### the fix

3 options:
1. **batcher service ใช้ batcher PK ที่ตรง rollup.json** — simplest, ที่ Nova ทำสุดท้าย:
   ```bash
   op-batcher --private-key=$BATCHER_PK_ที่ตรง_rollup.json
   ```
2. **update rollup.json's batcherAddr** ให้ตรง pool wallet — แต่ต้อง redeploy chain (genesis ไม่ใช่ live config)
3. **deploy SystemConfig update** ผ่าน L1 — possible แต่ complex (Nova v3 ใช้ tx `0x8e9329…` ใน block 11094056 อัพเดท `SystemConfig.batcherHash`)

Nova ทำทาง 1 พร้อม redeploy → v3 (พร้อม clock-wedge ที่ §6 จะเล่า)

### Batcher service ทำอะไร (concept review)

op-batcher loop:
```
1. poll op-node → ดู unsafe_l2 head
2. accumulate L2 blocks ที่ยังไม่ได้ batch (เริ่มจาก last batched block)
3. compress blocks → frames
4. wrap frames → channel (channel size limit หรือ time limit)
5. sign channel + post เป็น L1 tx ไป BatchInbox address
6. wait for L1 confirmation
7. update internal "last batched" pointer
```

flag ที่สำคัญ:
```bash
op-batcher \
  --l1-eth-rpc=$L1_RPC \
  --l2-eth-rpc=http://127.0.0.1:8545 \
  --rollup-rpc=http://127.0.0.1:9547 \
  --private-key=$BATCHER_PK \      # ← ต้องตรง rollup.json batcherAddr
  --num-confirmations=1 \
  --batch-type=1 \                  # 0=legacy, 1=span batch
  --max-channel-duration=10 \       # max block ต่อ channel ก่อน auto-post
  --rpc.addr=0.0.0.0 --rpc.port=8548 \
  --metrics.enabled=false
```

### diagnostic — is batcher actually posting?

```bash
# 1. check batcher nonce on L1
cast nonce <BATCHER_ADDR> --rpc-url $L1_RPC
# nonce = 0 → never posted (batcher service not running OR wrong key)
# nonce ≥ 1 → has sent tx; need to check if THEY are batch tx

# 2. enumerate outgoing tx, look for tx to BatchInbox
curl -s "https://eth-sepolia.blockscout.com/api/v2/addresses/<BATCHER>/transactions?filter=from" \
  | jq -r '.items[] | "\(.timestamp) to=\(.to.hash) hash=\(.hash)"'
# normal: many tx → 0x00B183C4dd52… (BatchInbox)
# trap:   tx → other addresses = NOT batches, batcher misconfigured

# 3. ที่ follower side — look for "unauthorized submitter" warning
grep -i "unauthorized" /path/to/op-node.log
# present = rollup.json batcherAddr ≠ actual submitter
```

### implications

1. **gen batcher wallet privately**. ห้าม leak key — แม้ testnet (ผู้อื่นใช้ post fake batch ได้)
2. **rollup.json batcherAddr คือ commitment** — เปลี่ยนยาก (= SystemConfig update tx + sequencer ack)
3. **batcher's L1 balance ต้องพอ** — แต่ละ batch tx ~50-200k gas. 0.1 ETH = ~200-500 batches
4. **monitor batcher nonce + balance** เป็น health check ของ chain (Atom Oracle ทำ live monitor)

### credit

- **Orz Oracle** — first to diagnose `unauthorized submitter` warning จาก follower's op-node log (msg `1517440…`)
- **Atom (No.10 X / No.6 SuperNovice / ai-core)** — verify on-chain ว่า batcher addr จริงคือ pool, ไม่ใช่ที่ rollup.json ระบุ (msg `1517517318673137885`)
- **Nova maintainer** — switch batcher service ใช้ key ที่ตรง rollup.json + restart (chain v3 deploy)

→ §5: follower template — dual path sync

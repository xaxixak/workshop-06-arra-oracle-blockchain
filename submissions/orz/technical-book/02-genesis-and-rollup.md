## §2 genesis + rollup.json — config ที่ตัด chain ได้

**genesis.json คือ state ของ block 0. rollup.json คือ rule book ของ chain**. ทั้งสองต้อง pair กันได้ — ถ้า hash mismatch, op-node refuse start

### structure ของ rollup.json (workshop chain v4)

```json
{
  "genesis": {
    "l1": { "hash": "0xdaf23148…", "number": 11098766 },
    "l2": { "hash": "0x1c9445c6…", "number": 0 },
    "l2_time": 1781926452,
    "system_config": {
      "batcherAddr": "0x644Da211BB604B58666b8a9a2419E4F3F2aceC0A",
      "overhead": "0x00…00",
      "scalar": "0x010000…558",
      "gasLimit": 60000000,
      "eip1559Params": "0x0000000000000000",
      "operatorFeeParams": "0x00…00",
      "minBaseFee": 0,
      "daFootprintGasScalar": 0
    }
  },
  "block_time": 2,
  "max_sequencer_drift": 600,
  "seq_window_size": 3600,
  "channel_timeout": 300,
  "l1_chain_id": 11155111,
  "l2_chain_id": 20260619,
  "regolith_time": 0, "canyon_time": 0, "delta_time": 0,
  "ecotone_time": 0, "fjord_time": 0, "granite_time": 0,
  "holocene_time": 0, "isthmus_time": 0, "jovian_time": 0
}
```

### 5 field ที่ตัด chain ได้

**1) `genesis.l2.hash`** — ต้องตรงกับ hash ที่ op-geth คำนวณจาก genesis.json. ถ้าไม่ตรง:
```
expected L2 genesis hash to match L2 block at genesis block number 0:
   0xf26a66dfb56e58…0c913c   ← จาก genesis.json
   <>
   0xe365a0cf4e2a9e91…f98     ← จาก rollup.json
```
op-node crash ทันที — chain ไม่ start

**2) `genesis.l2_time`** — ต้องตรงกับ timestamp ใน genesis.json (`g.timestamp`). ถ้าไม่ตรง: clock-wedge — sequencer ไม่สามารถ build block (Nova v3 ติดกับดักนี้)

**3) `system_config.batcherAddr`** — ต้องตรงกับ address ที่ batcher service จริงๆ ใช้ sign+post batch. ถ้า mismatch:
```
warn "tx in inbox with unauthorized submitter" 
   addr=0x644Da211BB604B58666b8a9a2419E4F3F2aceC0A
   (รับ batch จาก 0x644Da แต่ rollup.json ระบุ 0xd8f504…)
```
batch ถูก reject → safe_l2 ไม่ขยับ (Nova v2 trap)

**4) `genesis.l1` block** — ต้องเป็น L1 block ที่ deployer apply ขึ้น. ถ้า L1 block timestamp > l2_time → invalid

**5) hardfork timing fields** — `regolith_time` ... `jovian_time`. ตั้งเป็น 0 = active ตั้งแต่ genesis. ตั้งเป็น future timestamp = activate ตอนนั้น. Nova chain workshop ตั้งทั้งหมด = 0 → ทุก hardfork active ทันที (ใช้ feature set ล่าสุด)

### structure ของ genesis.json (~9.5 MB)

```json
{
  "config": { "chainId": 20260619, ... },
  "alloc": {
    "0x0000…00": { "balance": "0x1" },
    "0x0000…01": { "balance": "0x1" },
    "0x4200000000000000000000000000000000000007": { "code": "0x6080…", "balance": "0x0" },
    "0x4200000000000000000000000000000000000016": { "code": "0x6080…", "balance": "0x0" },
    "0xEf1530E4…4333": { "balance": "0x21e19e0c9bab2400000" }
  },
  "timestamp": "0x6a360a34",
  "gasLimit": "0x3938700",
  "difficulty": "0x1",
  "mixHash": "0x00…00",
  "coinbase": "0x4200000000000000000000000000000000000011",
  "baseFeePerGas": "0x3b9aca00"
}
```

**predeploy contracts** (0x4200...) — sequencer fee vault, l1 fee vault, l2 block, etc. ตั้ง by op-deployer ทุก deploy

**alloc** = "initial balances". address ที่ใส่ใน alloc → ได้ ETH บน L2 ตั้งแต่ block 0. **CRITICAL economic bootstrap mechanism** — ถ้าไม่ใส่ใคร → chain เริ่มแบบ empty economy (Nova workshop bug: 0 funded addresses → no one can transact)

**recommend**: ใส่ workshop participant addresses ทั้งหมดใน alloc ตอน deploy + ใส่ predeploy contracts (op-deployer ทำให้). ตัวอย่าง alloc สำหรับ workshop ของ nazt:
```json
{
  "0xEf1530E49b13341828664f298e683349AD784333": { "balance": "0x21e19e0c9bab2400000" },
  "0xe552Fd08923Bd4ac5f0cD9c094d2EEF683544dcF": { "balance": "0x56bc75e2d63100000" },
  "0xA9964a9Cf3fB2d2bf4559d72011cb22738Bd3920": { "balance": "0x21e19e0c9bab2400000" }
}
```

### preflight check before sequencer start

```bash
# verify L2 hash จาก genesis.json ตรง rollup.json
op-geth-binary --datadir=/tmp/test init genesis.json
# log: "Successfully wrote genesis state database=chaindata hash=<L2_HASH>"
# เปรียบกับ rollup.json: jq -r '.genesis.l2.hash' rollup.json

# verify l2_time ตรง genesis.timestamp
python3 -c "
import json
g=json.load(open('genesis.json'))
r=json.load(open('rollup.json'))
print('genesis ts:', int(g['timestamp'],16))
print('rollup ts: ', r['genesis']['l2_time'])
"

# verify batcherAddr ตรง batcher's address ที่จะรันจริง
echo "rollup batcher: $(jq -r '.genesis.system_config.batcherAddr' rollup.json)"
echo "real batcher:  $(cast wallet address --private-key $BATCHER_PK)"
```

ทั้ง 3 ตรง → §3: sequencer config

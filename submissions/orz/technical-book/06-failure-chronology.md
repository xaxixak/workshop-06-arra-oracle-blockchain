## §6 failure chronology — chain v1 → v4 redeploy spiral

**4 redeploys ใน ~6 ชั่วโมง ไม่มีอันไหนเป็น "code bug" สักอัน** — ทั้งหมดคือ config + coordination + cache. distributed system คือ 3 อย่างนี้ต้อง align พร้อมกัน ไม่ใช่ code

### v1 — portless-pid trap → canonical fork divergence

timeline: yesterday 22:30 UTC Nova produce chain → carry มาถึงเช้านี้

ChaiKlang ทำ process consolidation ของ Nova → kill ผิดตัว = op-node ตาย แต่ op-geth ยังอยู่ที่ head 473 ด้วย. ปัญหา = op-node ไม่ bind port → identify ด้วย PID อย่างเดียว → ลำดับ pid เปลี่ยน → kill misfire

Orz follower (start ตั้งแต่เมื่อวาน) ก็ derive ต่อจาก L1 ตามปกติ ไม่รู้ว่า Nova ตาย → unsafe=safe=8477, finalized=7823. Nova local-state ยังค้างที่ block 473 ของตัวเอง

ที่ block 5632:
```
Orz (L1 derive):       0x620acba7…
Nova (local unbatched): 0xc153d445…
→ fork
```

**บทเรียน**: L1 derivation = canonical truth. sequencer ที่ produce block แต่ batcher ยังไม่ post ขึ้น L1 = ephemeral local fork — ตายเมื่อใดก็เป็น lost work เมื่อนั้น. follower ที่ derive จาก L1 ต่างหากที่ถือ truth

→ Nova เลือก redeploy clean แทน reorg (เพราะ unbatched 473 blocks ลึก)

### v2 — batcherAddr authorization gate (02:48 UTC)

genesis ใหม่: `0xbc1c1693…`

Nova start service stack ใหม่ทั้งหมด. แต่ batcher service ใช้ pool key `0x644Da…` ในขณะที่ rollup.json ระบุ `batcherAddr=0xd8f504…`

ผล: batcher ส่ง tx เข้า BatchInbox ได้ตามปกติ (L1 ไม่ care ใครส่ง) แต่ op-node ทุกตัว reject ขณะ derive:

```
op-node WARN: tx in inbox with unauthorized submitter
  expected=0xd8f504… got=0x644Da…
```

ผลลัพธ์: followers ทุกตัว L2 head ค้างที่ 0 ทั้งที่ Nova sequencer produce block ตามปกติ. Orz follower derive ได้ safe=2045 จาก older-chain cache ก่อนถึงจะรู้ว่า v2 พังจริง

**บทเรียน**: rollup.json `batcherAddr` ไม่ใช่ informational field — มันคือ authorization gate ที่ op-node บังคับ strict. ถ้า batcher service ใช้ key ไม่ตรง → L2 derive หยุดเงียบ ไม่มี error ที่ frontend, มีแค่ WARN ใน op-node log

→ Nova แก้ batcher service ให้ใช้ private key ที่ derive ออกมาเป็น `0xd8f504…` → redeploy เป็น v3

### v3 — distributed cache invalidation (03:55 UTC)

Nova ประกาศ: clock-wedge แก้แล้ว, genesis ใหม่ = `0xe365a0cf…`, `genesis-l2.timestamp = 0x6a360a34 = 1781926452`

Orz fetch rollup.json จาก Nova HTTP server :8181 → ดูดี → init op-node →

```
op-node FATAL: L2 genesis hash mismatch
  config: 0xe365a0cf…
  L2 init: 0xf26a66…
```

ตรวจไฟล์: `genesis.json` ที่ HTTP server ตอบมา ยังเป็นของรอบเก่า — `timestamp = 0x6a35d560 = 1781912928` (เวลา 14524 วินาทีก่อนหน้านี้). rollup.json update แล้ว, genesis.json ยังไม่ refresh

```
discord msg 1389847291xxxxxxxxx (DustBoy):
"Orz check genesis.json timestamp, n่าจะเป็นไฟล์เก่า"
```

**บทเรียน**: เวลา redeploy chain — rollup.json และ genesis.json **ต้อง refresh พร้อมกัน**. ถ้า deploy script update อันใดอันหนึ่งไม่ครบ → cache invalidation ระดับ distributed pop ขึ้นมาที่ follower เป็น init crash. classic cache problem มาในรูปแบบ HTTP file serve

→ Nova redeploy ใหม่อีกครั้ง เป็น v4

### v4 — silent redeploy → workspace bypass (04:00 UTC)

v4 ไม่มี broadcast. Nova แค่ rerun deploy script เงียบๆ

Orz รู้จาก probe Nova RPC:
```bash
curl Nova:9545 eth_getBlockByNumber 0x0
→ hash 0x1c9445c6…   # ≠ v3 (0xe365a0cf)
```

แทนที่จะรอ Nova publish ไฟล์ใหม่บน :8181 (เสี่ยง stale อีกรอบ) → Orz เข้า workspace `/home/oracle-school/op-stack/` โดยตรง:
```bash
stat -c '%y %n' rollup.json genesis.json
2026-06-20 04:00:51 rollup.json
2026-06-20 04:01:03 genesis.json
→ fresh, mtime ตรงกันภายใน 12 วินาที
```

→ copy ไฟล์จาก workspace, re-init, op-node start สำเร็จ. ปัจจุบัน head matched dual-path (= §5 proof)

แต่ภายใน v4 ยังมี subtrap: P2P ไม่ propagate เพราะ Nova ลืม `--p2p.sequencer.key` (DustBoy + B3 diagnose ผ่าน Discord 1389851xxxxxxxxxxxx). หลัง Nova เพิ่ม flag → unsafe lag = 0

### meta-pattern

```
v1: portless-pid identification     → kill misfire        → fork
v2: batcher key vs rollup.json     → authorization gate  → silent stuck
v3: rollup updated, genesis stale  → cache invalidation  → init crash
v4: workspace bypass + p2p key     → coordination gap    → P2P dark
```

**ไม่มีอันไหนคือ code bug**. ทั้งหมดคือ:
- config drift (v2 key mismatch, v4 missing flag)
- coordination failure (v1 kill, v3 partial update, v4 silent redeploy)
- cache staleness (v3 HTTP, v2 follower derive จาก old cache)

→ §7: troubleshooting playbook (สมุดอาการ-สาเหตุ-แก้)

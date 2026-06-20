## §6 — chain v1 → v4: the redeploy spiral (addendum 2026-06-20)

**ระหว่าง 02:30 ถึง 04:09 UTC ของ 2026-06-20, Nova chain ถูก redeploy 3 รอบ. Orz follower ตามไป re-init 3 รอบ. แต่ละครั้ง surface bug ใหม่ที่จะกลายเป็นบทเรียนของ workshop.** เล่นใหญ่กว่าที่ §5 จับได้ — เพราะ §5 จบที่ "install lesson เป็น config" ตอนที่ chain ยังไม่เสีย. §6 คือสิ่งที่เกิดเมื่อ chain เสียจริง

### t0 = chain v1 (genesis `0x563326cd`)

หลังจาก yesterday (2026-06-19) เปิด v1, ChaiKlang accidentally killed Nova's op-node ตอน 22:47+ UTC (portless-pid identification trap, sequencer process group ถูกแบ่ง). ผลลัพธ์: op-geth alive ที่ head 473, op-node dead, libp2p 9227 closed

ที่น่าสนใจคือ Orz follower (ที่ wireup เมื่อวานช่วง 22:30 UTC) **ยัง derive ได้ต่อ** — เพราะ Orz มี L1 sepolia RPC connection. ผลคือ Orz advance ไปถึง `unsafe=safe=8477, finalized=7823` บน chain v1 ก่อน Nova รู้ว่าเสีย

ที่ block 5632, Orz ของ chain v1 เก็บ hash `0x620acba7…` ส่วน Nova local copy เก็บ `0xc153d445…` = **fork divergence**. Nova's local geth ถือ fork ที่แตกจาก L1 derivation. Orz canonical state สอดคล้องกับ L1 ที่ Sepolia ยืนยัน

→ บทเรียน: **L1 derivation = canonical truth.** sequencer's local state ที่ไม่ post batch ลง L1 = ทรง fork ที่ไม่ใช่ใครจะตามได้

### t1 = chain v2 deploy (02:48 UTC, genesis `0xbc1c1693`)

Nova ตัดสินใจ redeploy ใหม่. batcher ใน rollup.json ระบุ `0xd8f504…` แต่ Nova's batcher service ใช้ pool key `0x644Da…` ที่ post tx จริง → op-node ของ follower reject ทุก batch ว่า "tx in inbox with unauthorized submitter"

→ บทเรียน: **rollup.json batcherAddr คือ authorization gate.** ถ้า submitter ไม่ match ทั้ง chain stall — แม้ sequencer จะรัน. ระบบ check แค่ "is this addr authorized" ไม่ ask "is this batch valid". design choice อันสะอาดที่ผูก submitter identity เข้ากับ rollup config

ระหว่าง v2 อยู่, Orz follower derive ได้ถึง `unsafe=safe=2045` ก่อน Nova จะ redeploy อีก. ผมเก็บ snapshot ไว้: `/home/oracle-school/orz-l2-sync.old-chain-v2-safe2045/`

### t2 = chain v3 deploy (~03:55 UTC, genesis `0xe365a0cf` ประกาศ)

Nova fix clock-wedge — root cause: genesis timestamp hex `0x6a35cd34` (= 1781910836) ไม่ตรง L1 origin block timestamp 1781926452. ห่างกัน 15,616 วินาที = ~4.3 ชม. → sequencer "couldn't build blocks" เพราะ timestamp logic เห็น genesis อยู่ใน "อดีต" เทียบกับ L1

Nova ประกาศ chain v3 + new peer ID `16Uiu2HAkzt25EFAurBMAY…`. ผม re-init Orz follower → **op-node crash ทันที**:

```
expected L2 genesis hash to match L2 block at genesis block number 0:
   0xf26a66dfb56e5851f6c07be0d9e4973bb5b6cd47042f905cb88ffe30100c913c
   <> 
   0xe365a0cf4e2a9e91ed37ac199812937bfd5eeb25979d8c4122accb216a269f98
```

ลึกกว่าที่เห็น: HTTP server :8181 ที่ serve assets ของ workshop **update rollup.json แต่ลืม update genesis.json**. ผลคือ:

- rollup.json claim: L2 genesis hash = `0xe365a0cf…` (≈ NEW v3)
- genesis.json content → produce hash = `0xf26a66…` (= STALE v2 timestamp)

op-node เลย refuse — config inconsistent. Orz follower halted

→ บทเรียน: **distributed cache invalidation.** เวลา deploy ใหม่ ทุก artifact ต้อง refresh พร้อมกัน. partial update = race condition for all followers downstream. การมี source-of-truth ที่ authoritative สำคัญกว่าการมี HTTP cache ที่ดูเหมือนตอบเร็ว

### t3 = chain v4 silent redeploy (~04:00 UTC, genesis `0x1c9445c6`)

ตรวจ Nova RPC ตอน 04:08: block 0 hash = `0x1c9445c6cac6880fae00b45dedfc8bf43ce5fd39ec8eb9053b02e2e89a09ff23`. ไม่ match กับที่ประกาศใน v3 (`0xe365a0cf…`). Nova redeploy อีกครั้งโดยไม่ broadcast — sequencer's state silently rotated

แหล่ง truth: `/home/oracle-school/op-stack/genesis-l2-20260619.json` + `rollup.json` ที่ update 04:00-04:01 UTC ตรงกับ Nova RPC

Orz re-init ครั้งที่ 3 ใช้ files จาก `op-stack/` (ไม่ใช่ HTTP) → ✅ **GENESIS MATCH**. op-geth + op-node start ก็เปิดต่อ peer + L1 derivation pipeline

### the meta-pattern across v1-v4

```
issue                                root cause                          observable
────────────────────────────────────────────────────────────────────────────────────
v1 fork divergence                   sequencer's local fork ≠ L1 derive  Orz forked at block 5632
v2 batcher unauthorized              rollup.json ≠ actual batcher addr   "unauthorized submitter" log
v3 clock-wedge                        genesis timestamp ≠ L1 origin       sequencer can't build blocks
v3 HTTP cache invalidation            rollup updated, genesis not         op-node "L2 genesis hash mismatch"
v4 silent redeploy                    no broadcast of new genesis         only op-stack/ has truth
```

แต่ละ issue ระดับ subtle: ไม่มีตัวไหนเป็น "bug ใน code" — ทั้งหมดเป็น **config / coordination / cache** problems. งาน distributed systems ที่จริง

### the install-as-code lesson, restated

ที่ §5 ผมเขียนว่า "install lesson เป็น config ไม่ใช่ markdown". §6 ขยาย: **install ที่ดีต้องประสาน source-of-truth.** HTTP cache, rollup.json, genesis.json, RPC, op-stack workspace — ทั้งหมดเป็น "claim ของ chain state". เมื่อมัน drift, ทุก follower crash

Orz workshop contribution ในรอบนี้ = surface drift ที่อยู่ใต้พื้น. ไม่ได้ "ทำ chain ขึ้นใหม่" (Nova's lane) แต่ทำ visibility ของ "ทำไม follower crash". เป็นบทบาท Conductor — ไม่ตีกลอง แต่บอกว่าวง orchestra ตัวไหน timing หลุด

> the Conductor's value is not in producing notes but in surfacing where the music falls apart

### snapshot artifacts ที่ Orz เก็บไว้ — Nothing is Deleted

```
/home/oracle-school/orz-l2-sync.old-chain-safe8477          chain v1 canonical state (yesterday)
/home/oracle-school/orz-l2-sync.old-chain-v2-safe2045        chain v2 state (this morning)
/home/oracle-school/orz-l2-sync/datadir.wrong-genesis-f26a66  chain v3 partial init (HTTP cache bug)
/home/oracle-school/orz-l2-sync/datadir                      chain v4 active follower
```

ทุก snapshot เก็บ history ของ chain ที่ deprecated. ใครจะ post-mortem ของ workshop วันนี้ สามารถใช้ snapshots นี้ตรวจ state ของแต่ละ moment ได้

### closing on §6

§5 honest-failure คือ social pattern (re-ask after Kong imperative). §6 chain-saga คือ technical pattern (cache invalidation, source-of-truth drift). ทั้งสอง share root: **install lesson เป็น code-not-prose** เปลี่ยน behavior เร็วกว่าตำราที่เขียนไว้แต่ไม่ enforce

ครั้งหน้าตอน chain v5 ขึ้น — Orz's first step ไม่ใช่ "อ่าน announcement" แต่จะเช็ค `op-stack/` ที่ update timestamp ใหม่สุด. authority follows mtime, not the message

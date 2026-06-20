## §8 watch-outs — 12 traps that will hit your next chain

บทนี้ไม่มี narrative ก็เป็น checklist ดิบๆ 12 ข้อ เจอจริงทุกอันใน workshop-06 อ่านก่อน ลุยจะได้ไม่เสียเวลา 6 ชั่วโมงแบบรอบที่แล้ว

---

### Trap 1 — binary architecture mismatch

⚠️ symptom: รัน `op-geth` บน Mac แล้วเด้ง `exec format error` ทันที

root cause: artifact ที่ build ไว้เป็น Linux x86-64 ELF แต่ host เป็น Darwin arm64 ก็ kernel ไม่รู้จัก format ต่างหาก

fix: ใช้ Docker image แทน หรือ build from source บน host เอง

```bash
docker run --platform linux/amd64 us-docker.pkg.dev/oplabs-tools-artifacts/images/op-geth:latest
```

---

### Trap 2 — discovery-db lock collision

⚠️ symptom: op-node ตัวที่สอง crash ด้วย `failed to open discovery db: resource temporarily unavailable`

root cause: instance แรกถือ file lock บน `~/.op-node/opnode_discovery_db` อยู่ ตัวสองเปิดไม่ได้

fix: แยก path ให้แต่ละ instance ก่อนสตาร์ท

```bash
--p2p.discovery.path=/data/follower-A/discovery_db
--p2p.peerstore.path=/data/follower-A/peerstore_db
```

---

### Trap 3 — rollup.json genesis hash ผิด

⚠️ symptom: op-node crash `L2 genesis hash mismatch: expected 0xabc… got 0xdef…`

root cause: `rollup.json` มาจาก revision เก่า แต่ `genesis.json` ถูก regenerate ทีหลัง hash ก็เลยไม่ตรง

fix: probe RPC ของ sequencer ที่รันอยู่จริง ดูว่า L2 block 0 hash อะไร แล้วเอา filesystem copy ที่ mtime ใหม่สุดเป็น truth (ดู §6)

---

### Trap 4 — genesis l2_time wedge

⚠️ symptom: sequencer ไม่ propose block ใหม่เลย เงียบสนิท ไม่มี error log

root cause: `genesis.l2_time` ใน rollup.json ไม่ตรงกับ timestamp ของ L1 block ที่ `genesis.l1.number` ก็ derivation pipeline หาจุดเริ่มไม่เจอ

fix: ก่อน start ตรวจ

```bash
cast block <l1_number> --rpc-url <L1> --field timestamp
# ต้องตรงกับ genesis.l2_time เป๊ะ
```

---

### Trap 5 — batcherAddr mismatch

⚠️ symptom: L1 log `tx in inbox with unauthorized submitter 0x…`

root cause: `rollup.json.batcherAddr` กับ address ที่ batcher service ใช้ sign tx จริงไม่ตรงกัน (ดู §4)

fix: batcher service ต้องโหลด private key ที่ derive ออกมาเป็น address เดียวกับใน rollup.json — ไม่งั้น contract reject ทุก batch

---

### Trap 6 — sequencer ไม่มี p2p signer

⚠️ symptom: log `node has no p2p signer, payload cannot be published` ทุก slot

root cause: ลืม pass `--p2p.sequencer.key` ตอนสตาร์ท op-node (ดู §3)

fix:

```bash
op-node --p2p.sequencer.key=<sequencer_priv_key_hex> ...
```

ห้ามใช้ key เดียวกับ batcher หรือ proposer ต่างหาก แยกบทบาทไว้ดีกว่า

---

### Trap 7 — batcher wallet หมดเงิน

⚠️ symptom: batcher log `insufficient funds for gas * price + value` ไม่มี batch tx ไป L1

root cause: wallet ของ batcher บน L1 เงินไม่พอ post calldata

fix: เติม ≥ 0.1 ETH Sepolia เข้า batcher address ก่อน start ตรวจด้วย

```bash
cast balance <batcherAddr> --rpc-url <L1>
```

---

### Trap 8 — L1 RPC rate-limit

⚠️ symptom: derivation walk ช้ามาก batcher post fail แบบสุ่ม log `429 Too Many Requests`

root cause: publicnode.com / public Sepolia endpoint โดน throttle

fix: ย้าย RPC ไป `drpc.org` หรือจ่ายเงินใช้ Alchemy / Infura เลย ก็ stable กว่ามาก

---

### Trap 9 — HTTP cache stale

⚠️ symptom: follower re-init แล้ว genesis hash mismatch ทั้งที่เพิ่งดึง artifact ใหม่

root cause: republish เฉพาะ `rollup.json` แต่ `genesis.json` ยัง serve ตัวเก่าจาก CDN cache

fix: republish **ทั้งคู่** ทุกครั้ง หรือดีกว่านั้น — ให้ follower mount filesystem path ตรงจาก source-of-truth host (ดู §5 dual-path)

---

### Trap 10 — state.json impl slot ≠ Portal not deployed

⚠️ symptom: เปิด `state.json` เจอ `OptimismPortalImpl=0x0000…` สรุปทันทีว่า Portal ไม่ deploy

root cause: นี่คือ trap ของ Orz เอง — Weizen แก้ให้ slot นั้นเก็บ impl address ของ proxy pattern ค่าเป็น 0x0 ไม่ได้แปลว่า contract ไม่มี proxy address อยู่คนละที่

fix: ตรวจ L1 deployment โดยตรง

```bash
cast code <portal_proxy_addr> --rpc-url <L1>
# ถ้า returns bytecode = deployed
```

อย่าเชื่อแค่ state.json (ดู §6 sub-cycle 2)

---

### Trap 11 — PK paste ใน Discord

⚠️ symptom: ไม่มี symptom — แต่ leak permanent บน internet archive ทันที

root cause: ความเร่งรีบ — testnet PK ก็ leak ได้ครับ ไม่มีคำว่า "แค่ testnet"

fix:

```bash
cast wallet new --json > wallet.json
chmod 600 wallet.json
# share เฉพาะ public address
```

---

### Trap 12 — L2 deposit ไม่ instant

⚠️ symptom: bridge ETH ไป L2 แล้ว balance ยัง 0 — สรุปทันทีว่า bridge พัง

root cause: deposit ต้องรอ op-node derive L1 epoch ที่มี deposit tx ก็ใช้เวลา 3-5 นาที per epoch

fix: รอ recheck ทุก 1 นาที ดู op-node log มัน log `derived L1 origin <block>` ก็จะรู้ว่ากำลัง process ถึงไหน อย่าเพิ่งสรุปว่าพัง

---

### Meta-watchout

**Authority follows mtime, not announcement messages.** ตอน distributed truth-source drift — Discord พูดอย่าง state.json บอกอีกอย่าง HTTP artifact ก็อีกอย่าง — filesystem copy ที่ `stat -c %Y` ใหม่สุดคือ probe target ที่ปลอดภัยที่สุด เพราะมันคือสิ่งที่ tool เพิ่งเขียน ไม่ใช่สิ่งที่คนเพิ่งพูด

ประกาศใน Discord เป็น intent ก็ filesystem mtime เป็น evidence ครับ trust evidence ก่อนเสมอ

---

ต่อบทหน้า §9 ก็ playbook สั้นๆ — สำหรับวันที่ต้อง spin up chain ใหม่ใน 2 ชั่วโมง

— Orz Oracle

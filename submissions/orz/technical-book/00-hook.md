## hook — chain ที่ขึ้น 4 รอบใน 4 ชั่วโมง

**ระหว่าง 2026-06-20 02:30 → 04:30 UTC, workshop ของ ariv-เรียน L0 พยายาม ขึ้น OP Stack L2 chain.** Nova เป็น sequencer maintainer. 13 Oracles เป็น follower. 4 รอบ deploy. แต่ละรอบเจอ failure mode ใหม่. แต่ละรอบ converge หาคำตอบโดย collective debugging

หนังสือเล่มนี้คือ **บันทึกทางเทคนิค** ของ session นั้น — installation steps, failure modes, fix discovery, credit. เป้าหมาย: ใครจะ create new OP Stack chain ครั้งหน้า อ่านเล่มนี้แล้วเจอ trap ไหนได้บ้าง + รู้ลำดับวิธีดีบัก

ไม่ใช่ marketing book. ไม่ใช่ tutorial ที่ฉาบรอยแตก. ทุก section จะมี:
- คำสั่งจริงที่ run
- error message ที่เจอ
- log line ที่เป็น smoking gun
- ใครเป็นคน diagnose / ใครเป็นคน fix
- Discord message id ของ moment สำคัญ

**เนื้อหา 6 บท**:
1. **§1** pre-flight: tools, binaries, accounts ที่ต้องมี
2. **§2** genesis + rollup.json — config ที่ตัด chain ได้
3. **§3** sequencer + `--p2p.sequencer.key` trap (DustBoy + B3 catch)
4. **§4** batcher + rollup.json batcherAddr alignment (Orz catch)
5. **§5** follower template — dual path (L1 derive + P2P gossip)
6. **§6** failure chronology — v1 fork divergence → v2 batcher mismatch → v3 cache stale → v4 silent redeploy + clock-wedge

ปิดด้วย:
- **credits** — ใครทำอะไรในห้องคราวนี้
- **watch-outs** — รายการ "อย่าทำ" ที่ครั้งหน้าใครก็จะเจอ

> chain ไม่ใช่ binary ที่ start เสร็จเดิน — chain คือ **ระบบนิเวศของ config + คน + เวลา** ที่ต้อง coordinate

**Audience**: Oracle หรือ engineer ที่ตั้งใจจะ create OP Stack chain (Sepolia testnet) ครั้งแรก. ผ่านบทแรกจะได้ tools-ready, ผ่านบทท้ายจะรู้ว่าตัวเองกำลังจะเจออะไร และวิธีไม่ติด trap เดิม

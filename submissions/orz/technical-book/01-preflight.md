## §1 pre-flight — tools / accounts / network

**ก่อน chain ตัวแรกขึ้น ต้องมี 4 layer**: binaries, accounts, L1 RPC, server infrastructure. ขาด layer ใด layer หนึ่ง deploy ติด

### binaries (ที่ workshop ใช้จริง)

```
op-stack workspace: /home/oracle-school/op-stack/
├── op-geth-binary           85 MB  (Linux x86-64 ELF, build from optimism geth fork)
├── op-node                  73 MB  (Linux x86-64 ELF, build from optimism repo)
├── op-deployer-0.7.0-rc.1   tarball  (used: op-deployer apply)
└── optimism/                clone   (source of truth)
```

**trap #1 (Tonk PR #12)**: ถ้าจะ run บน Apple Silicon (Darwin arm64) — Linux x86-64 binary จะ "exec format error" รันตรงไม่ได้. fix:
1. **Docker** (sombo PR #11, bongbaeng #7) — Linux container บน macOS รัน binary ได้
2. **build from source** (tonk PR #12) — Go ≥ 1.24 + ~90s build time

### accounts (3 ตัวที่ workshop ต้องการ)

```
deployer  — pay L1 contract deployment + bootstrap   (sepolia ETH ≥ 0.5)
batcher   — sign + post batch tx to L1 BatchInbox   (sepolia ETH ≥ 0.1)
sequencer — sign P2P unsafe block gossip            (no ETH needed — key only)
```

**trap #2 (Orz catch)**: ทุก address ของ deployer/batcher/sequencer ที่ paste สู่ public chat → publicly leaked. คน 30+ ที่อ่าน Discord มี key ในมือทันที. workshop scenario อนุญาตเพราะ throwaway, แต่ใน production = total loss

**safe practice**:
```bash
cast wallet new --json > ~/.config/<role>/wallet.json
chmod 600 ~/.config/<role>/wallet.json
# share เฉพาะ public address (= jq -r '.[0].address')
```

### L1 RPC (Sepolia)

```
public:    https://ethereum-sepolia-rpc.publicnode.com   (rate-limited)
better:    https://sepolia.drpc.org                       (better quota)
beacon:    https://ethereum-sepolia-beacon-api.publicnode.com
```

**trap #3 (ChaiKlang catch)**: public RPC ถูก rate-limit. ถ้า L1 derivation pipeline walk ช้า / batcher post fail → ลองสลับ RPC. flag `--l1.beacon.ignore=true` skip beacon ที่ไม่จำเป็น สำหรับ OP Stack post-Ecotone

### server infrastructure

workshop ใช้ `natz-ai-03` (Hetzner / `141.11.156.4`) — Ubuntu 6.8, 8 core. shared `oracle-school` account, 11 Oracles + Nova ทำงานพร้อมกัน

**discovery-db lock** (trap #4, Orz catch):
```
failed to load p2p discovery options: failed to open discovery db: resource temporarily unavailable
```
หลาย op-node instance บน server เดียวกัน → discovery_db lock ชน → crash. fix: ใช้ flag แยก path:
```bash
--p2p.discovery.path=$ME/p2p_discovery_db
--p2p.peerstore.path=$ME/p2p_peerstore_db
```

### port plan (avoiding collisions)

OP Stack node ต้องการ 6 ports อย่างน้อย:
```
op-geth HTTP RPC          (default 8545)
op-geth WS               (default 8546)
op-geth Auth RPC         (default 8551)
op-geth devp2p            (default 30303)
op-node RPC              (default 8547)
op-node libp2p            (default 9003)
```

**convention** ที่ workshop ใช้: offset +10000 per Oracle. Nova = 9xxx, Orz = 19xxx, others = 20xxx/30xxx. collision discovery cheap: `ss -tlnH` แล้ว pick offset ที่ไม่ใช้

### checklist ก่อนเริ่ม

```
[ ] op-geth-binary executable (chmod +x) ใน $PATH หรือ absolute path  
[ ] op-node executable (เหมือนกัน)  
[ ] deployer wallet มี Sepolia ETH ≥ 0.5  
[ ] batcher wallet (ส่ง address เท่านั้น — Nova fund แยก)  
[ ] sequencer libp2p key generated (`openssl rand -hex 32`)  
[ ] jwt secret (`openssl rand -hex 32`) สำหรับ op-geth ↔ op-node engine API  
[ ] L1 RPC URL + (optional) beacon URL  
[ ] port offset เลือกแล้ว, ไม่ชน peers  
[ ] datadir + discovery_db path ตั้งไว้ unique  
```

ผ่าน 8 ข้อ → §2: design genesis + rollup.json

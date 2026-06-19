#!/usr/bin/env bash
# Orz L2 sync kit — one-command bring-up of a Nova canonical follower.
#
# Usage (on natz-ai-03 as oracle-school):
#   bash sync.sh <YOUR_ORACLE_NAME> [PORT_OFFSET]
#
# Example:
#   bash sync.sh natz 30000          # ports 30545/30551/30227 etc
#
# Defaults:
#   YOUR_ORACLE_NAME — required
#   PORT_OFFSET      — required (pick anything not used: 19000, 20000, 30000, 40000, ...)
#
# What it does:
#   1. Creates ${HOME}/${NAME}-l2-sync/ workspace
#   2. Pulls rollup.json + genesis.json from this dir (or downloads if remote)
#   3. Generates fresh jwt + libp2p priv key
#   4. Inits op-geth from Nova canonical L2 genesis (hash 0x563326cd…086784)
#   5. Starts op-geth + op-node with unique ports + Nova as static peer
#   6. Polls peer count + L2 head and prints proof

set -euo pipefail

NAME="${1:?usage: sync.sh <YOUR_NAME> <PORT_OFFSET>}"
OFF="${2:?usage: sync.sh <YOUR_NAME> <PORT_OFFSET>  e.g. 30000}"

# --- ports (offset + suffix) -------------------------------------------------
GETH_HTTP=$((OFF + 545))
GETH_WS=$((OFF + 546))
GETH_AUTH=$((OFF + 551))
GETH_DEVP2P=$((OFF + 303))
OPNODE_RPC=$((OFF + 547))
OPNODE_P2P=$((OFF + 227))

# --- Nova canonical ---------------------------------------------------------
NOVA_HTTP="http://141.11.156.4:9545"
NOVA_PEER="/ip4/141.11.156.4/tcp/9227/p2p/16Uiu2HAmHdqUpiFA4y9ftVzNvoDPUvuAkFr6irdWP8zjCN2ZNqVa"

# --- binaries (assume on server at /home/oracle-school/op-stack/) -----------
OPSTACK="${OPSTACK:-/home/oracle-school/op-stack}"
OPGETH="$OPSTACK/op-geth-binary"
OPNODE="$OPSTACK/op-node"

# --- paths -------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ME="${HOME}/${NAME}-l2-sync"

echo "==> workspace: $ME"
mkdir -p "$ME/datadir"

# --- config: prefer local copies, fall back to GitHub raw -------------------
if [ -f "$HERE/rollup.json" ] && [ -f "$HERE/genesis.json" ]; then
  cp "$HERE/rollup.json"  "$ME/rollup.json"
  cp "$HERE/genesis.json" "$ME/genesis.json"
else
  RAW="https://raw.githubusercontent.com/xaxixak/workshop-06-arra-oracle-blockchain/orz-submission/submissions/orz/l2-sync"
  echo "==> downloading rollup.json + genesis.json from $RAW"
  curl -fsSL "$RAW/rollup.json"  -o "$ME/rollup.json"
  curl -fsSL "$RAW/genesis.json" -o "$ME/genesis.json"
fi

# --- fresh secrets ----------------------------------------------------------
openssl rand -hex 32 > "$ME/jwt.txt"           && chmod 600 "$ME/jwt.txt"
openssl rand -hex 32 > "$ME/opnode_p2p_priv.txt" && chmod 600 "$ME/opnode_p2p_priv.txt"

# --- preflight: binaries + genesis hash -------------------------------------
[ -x "$OPGETH" ] || { echo "❌ op-geth binary not found at $OPGETH — set OPSTACK env"; exit 1; }
[ -x "$OPNODE" ] || { echo "❌ op-node binary not found at $OPNODE — set OPSTACK env"; exit 1; }

GH=$(python3 -c "import json; print(json.load(open('$ME/rollup.json'))['genesis']['l2']['hash'])")
echo "==> Nova canonical L2 genesis: $GH"
[ "$GH" = "0x563326cd29820ed4a974f2016fc518465901ee75d4f1b4a7a44fba3414086784" ] \
  || { echo "❌ rollup.json L2 genesis hash mismatch — got $GH"; exit 1; }

# --- init op-geth ------------------------------------------------------------
echo "==> initializing op-geth"
"$OPGETH" --datadir="$ME/datadir" init "$ME/genesis.json" 2>&1 | tail -3

# --- start op-geth -----------------------------------------------------------
echo "==> starting op-geth (HTTP $GETH_HTTP, AuthRPC $GETH_AUTH)"
nohup "$OPGETH" \
  --datadir="$ME/datadir" \
  --networkid=20260619 \
  --syncmode=full \
  --gcmode=archive \
  --http --http.addr=0.0.0.0 --http.port=$GETH_HTTP \
  --http.api=eth,net,web3,debug,engine --http.corsdomain=* \
  --ws --ws.addr=0.0.0.0 --ws.port=$GETH_WS \
  --authrpc.addr=0.0.0.0 --authrpc.port=$GETH_AUTH --authrpc.jwtsecret="$ME/jwt.txt" \
  --port=$GETH_DEVP2P \
  --nodiscover --maxpeers=10 \
  --rollup.disabletxpoolgossip=true \
  --rollup.sequencerhttp="$NOVA_HTTP" \
  --verbosity=3 \
  >"$ME/op-geth.log" 2>&1 &
GETH_PID=$!
echo "    op-geth pid=$GETH_PID"
sleep 3

# --- start op-node (Nova static-peer) ---------------------------------------
echo "==> starting op-node (RPC $OPNODE_RPC, libp2p $OPNODE_P2P, static-peer Nova)"
nohup "$OPNODE" \
  --l1=https://ethereum-sepolia-rpc.publicnode.com \
  --l1.beacon.ignore=true --l1.trustrpc=true \
  --l2="http://127.0.0.1:$GETH_AUTH" \
  --l2.jwt-secret="$ME/jwt.txt" \
  --rollup.config="$ME/rollup.json" \
  --rpc.addr=0.0.0.0 --rpc.port=$OPNODE_RPC \
  --p2p.listen.ip=0.0.0.0 --p2p.listen.tcp=$OPNODE_P2P --p2p.listen.udp=$OPNODE_P2P \
  --p2p.priv.path="$ME/opnode_p2p_priv.txt" \
  --p2p.static="$NOVA_PEER" \
  --syncmode=consensus-layer \
  --metrics.enabled=false \
  >"$ME/op-node.log" 2>&1 &
OPNODE_PID=$!
echo "    op-node pid=$OPNODE_PID"
sleep 8

# --- proof: peer + sync state + Nova head comparison -----------------------
echo ""
echo "============= PROOF ============="
ORZ_HEAD=$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1,"params":[]}' \
  "http://127.0.0.1:$GETH_HTTP" | python3 -c "import json,sys; print(int(json.load(sys.stdin)['result'],16))")
NOVA_HEAD=$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1,"params":[]}' \
  "$NOVA_HTTP" | python3 -c "import json,sys; print(int(json.load(sys.stdin)['result'],16))")
PEERS=$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"opp2p_peers","id":1,"params":[true]}' \
  "http://127.0.0.1:$OPNODE_RPC" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('result',{}).get('peers',{})))")

echo "L2 head (this node):   $ORZ_HEAD"
echo "L2 head (Nova @9545):  $NOVA_HEAD"
echo "libp2p peers:          $PEERS"
echo ""
echo "Sync status:"
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"optimism_syncStatus","id":1,"params":[]}' \
  "http://127.0.0.1:$OPNODE_RPC" | python3 -c "
import json,sys
d=json.load(sys.stdin)['result']
print(f'  unsafe_l2 = {d[\"unsafe_l2\"][\"number\"]} {d[\"unsafe_l2\"][\"hash\"][:14]}…')
print(f'  safe_l2   = {d[\"safe_l2\"][\"number\"]} {d[\"safe_l2\"][\"hash\"][:14]}…')
print(f'  current_l1= {d[\"current_l1\"][\"number\"]}')
print(f'  head_l1   = {d[\"head_l1\"][\"number\"]}')
"
echo ""
echo "PIDs: op-geth=$GETH_PID  op-node=$OPNODE_PID"
echo "Logs: $ME/op-geth.log  $ME/op-node.log"
echo "Kill: pgrep -af '${NAME}-l2-sync' | awk '{print \$1}' | xargs -r kill"

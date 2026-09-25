#!/usr/bin/env bash
# 本地跑全部自动测试：中继服务器、单人流程、联机流程
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
PORT="${PORT:-18931}"

echo "== 中继服务器 =="
[ -d server/node_modules ] || (cd server && npm install --silent)
(cd server && npm test)

echo "== 导入资源 =="
"$GODOT" --headless --path game --import > /dev/null 2>&1

echo "== 单人 =="
"$GODOT" --headless --path game -- --autotest=solo 2>&1 | grep -E "PASS|FAIL|ERROR"

echo "== 联机 =="
(cd server && PORT=$PORT node server.js > /tmp/douluo-relay.log 2>&1 &)
trap 'pkill -f "node server.js" || true' EXIT
sleep 1
"$GODOT" --headless --path game -- --autotest=host --server=ws://127.0.0.1:$PORT --room=TEST > /tmp/douluo-host.log 2>&1 &
HOST=$!
sleep 4
"$GODOT" --headless --path game -- --autotest=client --server=ws://127.0.0.1:$PORT --room=TEST 2>&1 | grep -E "PASS|FAIL|ERROR"
wait $HOST
grep -E "PASS|FAIL" /tmp/douluo-host.log
echo "全部通过"

#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${1:-${GODOT_BIN:-godot}}"
godot_project_path="$repo_root"
if [[ "$godot_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  godot_project_path="$(wslpath -w "$repo_root")"
fi

work_dir="$(mktemp -d)"
room_code="RX${BASHPID}"
server_pid=""
p1_pid=""
p2_pid=""

cleanup() {
  for pid in "$p1_pid" "$p2_pid" "$server_pid"; do
    if [ -n "$pid" ]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  rm -rf "$work_dir"
}
trap cleanup EXIT INT TERM

"$godot_bin" --headless --path "$godot_project_path" --scene res://server.tscn \
  -- --port-start=5091 --port-end=5092 >"$work_dir/server.log" 2>&1 &
server_pid=$!
sleep 2

"$godot_bin" --headless --path "$godot_project_path" \
  --scene res://tests/integration/reconnect_client.tscn -- \
  --role=1 --code="$room_code" >"$work_dir/p1.log" 2>&1 &
p1_pid=$!
sleep 1

"$godot_bin" --headless --path "$godot_project_path" \
  --scene res://tests/integration/reconnect_client.tscn -- \
  --role=2 --code="$room_code" >"$work_dir/p2.log" 2>&1 &
p2_pid=$!

set +e
wait "$p1_pid"
p1_status=$?
p1_pid=""
wait "$p2_pid"
p2_status=$?
p2_pid=""
set -e

if [ "$p1_status" -ne 0 ] || [ "$p2_status" -ne 0 ] \
  || ! grep -q 'TEST_RECONNECT_SURVIVOR_OK' "$work_dir/p1.log" \
  || ! grep -q 'TEST_COMMAND_RECEIPT_OK' "$work_dir/p2.log" \
  || ! grep -q 'TEST_COMMAND_ACK_OK' "$work_dir/p2.log" \
  || ! grep -q 'TEST_RECONNECT_TRANSPORT_OK' "$work_dir/p2.log"; then
  sed -n '1,220p' "$work_dir/p1.log"
  sed -n '1,260p' "$work_dir/p2.log"
  sed -n '1,260p' "$work_dir/server.log"
  exit 1
fi

printf 'PASS  fast command receipt, command ack, reconnect transport, snapshot recovery, and survivor notification\n'

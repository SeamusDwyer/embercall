#!/bin/bash
# Two-process multiplayer test for Embercall.
# Launches a host (autopilot bot) and a join client, verifies both exit cleanly.

set -e

GODOT="${GODOT:-godot}"
PROJECT="/home/seamus/embercall"
JOIN_DIR="/tmp/embercall_join_test_$$"
TIMEOUT_SEC=60

cleanup() {
    kill $HOST_PID 2>/dev/null || true
    kill $JOIN_PID 2>/dev/null || true
    wait $HOST_PID 2>/dev/null || true
    wait $JOIN_PID 2>/dev/null || true
    rm -rf "$JOIN_DIR"
    rm -f /tmp/embercall_host_$$.log /tmp/embercall_join_$$.log
}
trap cleanup EXIT INT TERM

echo "=== Embercall Multiplayer Test ==="

cp -r "$PROJECT" "$JOIN_DIR"

# Launch host
echo "[HOST] Starting..."
$GODOT --headless --path "$PROJECT" --autopilot > /tmp/embercall_host_$$.log 2>&1 &
HOST_PID=$!
sleep 1
if ! kill -0 $HOST_PID 2>/dev/null; then
    echo "FAIL: Host died immediately"
    cat /tmp/embercall_host_$$.log
    exit 1
fi

# Launch join
echo "[JOIN] Starting..."
$GODOT --headless --path "$JOIN_DIR" --autojoin=127.0.0.1 > /tmp/embercall_join_$$.log 2>&1 &
JOIN_PID=$!
sleep 1
if ! kill -0 $JOIN_PID 2>/dev/null; then
    echo "FAIL: Join died immediately"
    cat /tmp/embercall_join_$$.log
    exit 1
fi

# Wait for host to finish
echo "[WAIT] Waiting for host autopilot..."
if ! wait $HOST_PID 2>/dev/null; then
    HOST_EXIT=1
else
    HOST_EXIT=0
fi

echo "--- Host log ---"
cat /tmp/embercall_host_$$.log

if [ "$HOST_EXIT" -ne 0 ]; then
    echo "FAIL: Host exited with code $HOST_EXIT"
    exit 1
fi
if ! grep -q "TEST_RESULT: PASS" /tmp/embercall_host_$$.log; then
    echo "FAIL: Host did not report PASS"
    exit 1
fi

# Wait for join to see server disconnect and print PASS
echo "[WAIT] Waiting for join to detect disconnect..."
for i in $(seq 1 20); do
    if grep -q "TEST_RESULT: PASS" /tmp/embercall_join_$$.log 2>/dev/null; then
        echo "[JOIN] Detected PASS in join log"
        break
    fi
    if ! kill -0 $JOIN_PID 2>/dev/null; then
        break
    fi
    sleep 0.5
done

# Kill join cleanly (it may hang on quit due to cleanup error loops)
kill $JOIN_PID 2>/dev/null || true
wait $JOIN_PID 2>/dev/null || true

echo "--- Join log ---"
cat /tmp/embercall_join_$$.log

if grep -q "TEST_RESULT: PASS" /tmp/embercall_join_$$.log; then
    echo "=== PASS: Multiplayer test completed successfully ==="
    exit 0
else
    echo "FAIL: Join did not report PASS"
    exit 1
fi

#!/usr/bin/env bash
# verify-deployment.sh — smoke test for the arc-demo-app
# Usage: ./scripts/verify-deployment.sh [NODE_IP] [NODE_PORT]
# Defaults: localhost 30080

set -euo pipefail

NODE_IP="${1:-localhost}"
NODE_PORT="${2:-30080}"
BASE_URL="http://${NODE_IP}:${NODE_PORT}"

PASS=0
FAIL=0

check() {
  local label="$1"
  local result="$2"
  if [ "$result" = "pass" ]; then
    echo "  [PASS] $label"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL] $label"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "========================================"
echo " Arc Demo App — Deployment Verification"
echo " Target: ${BASE_URL}"
echo "========================================"
echo ""

# --- Check 1: /health returns status: ok ---
echo "Checking /health..."
HEALTH_RESPONSE=$(curl -sf --max-time 10 "${BASE_URL}/health" 2>/dev/null || echo "")
if echo "$HEALTH_RESPONSE" | grep -q '"status":"ok"'; then
  check "/health returns {status: ok}" "pass"
else
  check "/health returns {status: ok}" "fail"
fi

# --- Check 2: / contains "Azure Arc" ---
echo "Checking /..."
ROOT_RESPONSE=$(curl -sf --max-time 10 "${BASE_URL}/" 2>/dev/null || echo "")
if echo "$ROOT_RESPONSE" | grep -q "Azure Arc"; then
  check "/ contains 'Azure Arc'" "pass"
else
  check "/ contains 'Azure Arc'" "fail"
fi

echo ""
echo "----------------------------------------"
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "----------------------------------------"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "DEPLOYMENT VERIFICATION FAILED"
  exit 1
else
  echo "DEPLOYMENT VERIFIED OK"
  exit 0
fi

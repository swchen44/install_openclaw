#!/usr/bin/env bash
# setup-visualization.sh
# 安裝 OpenClaw 可視化工具
# 用法：bash setup-visualization.sh

set -e

echo "=== OpenClaw 可視化工具安裝 ==="
echo ""

# ── 1. OpenClaw Office（3D 虛擬辦公室）─────────────────
echo "[1/3] 安裝 OpenClaw Office..."
echo "  GitHub: https://github.com/WW-AI-Lab/openclaw-office"

# 確認 Node.js 22+
NODE_VER=$(node -e "console.log(process.versions.node.split('.')[0])" 2>/dev/null || echo "0")
if [ "$NODE_VER" -lt 22 ]; then
  echo "  ⚠️  需要 Node.js 22+，目前版本: $NODE_VER"
  echo "  請先升級 Node.js：https://nodejs.org"
  echo "  或使用 nvm：nvm install 22 && nvm use 22"
else
  echo "  ✅ Node.js $NODE_VER OK"
  # 安裝到 tools/openclaw-office
  mkdir -p tools/openclaw-office
  cat > tools/openclaw-office/.env.local << 'EOF'
# OpenClaw Gateway 連線設定
VITE_GATEWAY_URL=http://127.0.0.1:3000
VITE_GATEWAY_WS=ws://127.0.0.1:3000
EOF
  echo "  ✅ OpenClaw Office 設定完成"
  echo "  啟動指令：npx @ww-ai-lab/openclaw-office"
  echo "  網址：http://localhost:5173"
fi
echo ""

# ── 2. ClawMetry（費用監控）──────────────────────────
echo "[2/3] 安裝 ClawMetry..."
echo "  GitHub: https://github.com/vivekchand/clawmetry"

if command -v pip3 &>/dev/null || command -v pip &>/dev/null; then
  PIP=$(command -v pip3 || command -v pip)
  $PIP install clawmetry --quiet
  echo "  ✅ ClawMetry 安裝完成"
  echo "  啟動指令：clawmetry"
  echo "  網址：http://localhost:8900"
else
  echo "  ⚠️  找不到 pip，請先安裝 Python 3.8+"
fi
echo ""

# ── 3. openclaw-dashboard（Docker）───────────────────
echo "[3/3] openclaw-dashboard (Docker)"
echo "  GitHub: https://github.com/tugcantopaloglu/openclaw-dashboard"

if command -v docker &>/dev/null; then
  echo "  Docker 已安裝，啟動指令："
  echo "  docker run -d -p 3001:3001 \\"
  echo "    -e OPENCLAW_GATEWAY_URL=http://127.0.0.1:3000 \\"
  echo "    --name openclaw-dashboard \\"
  echo "    tugcantopaloglu/openclaw-dashboard"
  echo "  網址：http://localhost:3001"
else
  echo "  ⚠️  未安裝 Docker，請先安裝：https://docs.docker.com/get-docker/"
fi
echo ""

# ── 完成摘要 ─────────────────────────────────────────
echo "=== 安裝完成摘要 ==="
echo ""
echo "工具              網址                    用途"
echo "─────────────────────────────────────────────────────"
echo "OpenClaw 內建     http://localhost:18789   Session 管理"
echo "OpenClaw Office   http://localhost:5173    3D 虛擬辦公室（主推）"
echo "ClawMetry         http://localhost:8900    費用 / Token 監控"
echo "openclaw-dashboard http://localhost:3001   安全管理（MFA）"
echo ""
echo "Telegram: 設定 config.yaml 中的 TELEGRAM_BOT_TOKEN 和 TELEGRAM_USER_ID"

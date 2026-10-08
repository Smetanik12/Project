#!/bin/bash
# Подготовка облачной сессии Claude Code: Godot 4.5, программный Vulkan (lavapipe)
# и Xvfb для скриншотов без монитора, MCP-сервер Godot. Безопасно запускать повторно.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GODOT_VER="4.5-stable"
GODOT_BIN=/usr/local/bin/godot

if ! "$GODOT_BIN" --version 2>/dev/null | grep -q "^4\.5\.stable"; then
  tmp=$(mktemp -d)
  curl -sSL --retry 4 -o "$tmp/godot.zip" \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VER}/Godot_v${GODOT_VER}_linux.x86_64.zip"
  unzip -q -o "$tmp/godot.zip" -d "$tmp"
  install -m 755 "$tmp/Godot_v${GODOT_VER}_linux.x86_64" "$GODOT_BIN"
  rm -rf "$tmp"
fi

# Forward+ без видеокарты: Vulkan на процессоре + виртуальный экран
if [ ! -f /usr/share/vulkan/icd.d/lvp_icd.json ] || ! command -v xvfb-run >/dev/null; then
  apt-get update -qq || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mesa-vulkan-drivers xvfb >/dev/null
fi

# MCP-сервер Godot (подключается через .mcp.json)
if ! command -v godot-mcp >/dev/null; then
  npm install -g --no-audit --no-fund @coding-solo/godot-mcp >/dev/null 2>&1 || true
fi

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export GODOT_PATH=$GODOT_BIN" >> "$CLAUDE_ENV_FILE"
fi

# Импорт ресурсов, чтобы class_name и ассеты были доступны тестам сразу
cd "${CLAUDE_PROJECT_DIR:-.}"
"$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true

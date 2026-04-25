#!/usr/bin/env bash
# install.sh — install claude-notify hook into Claude Code
set -euo pipefail

SERVER_URL="${1:-}"
SHARED_SECRET="${2:-}"

HOOK_SRC="$(cd "$(dirname "$0")" && pwd)/claude-notify.py"
HOOK_DST="$HOME/.claude/hooks/claude-notify.py"
CONFIG_DIR="$HOME/.claude-notify"
CONFIG_FILE="$CONFIG_DIR/config.json"

usage() {
  echo "Usage: $0 <server-url> [shared-secret]"
  echo "  server-url     e.g. https://notify.example.com"
  echo "  shared-secret  random string; generated if omitted"
  exit 1
}

[[ -n "$SERVER_URL" ]] || usage

# Generate secret if not provided
if [[ -z "$SHARED_SECRET" ]]; then
  if command -v openssl &>/dev/null; then
    SHARED_SECRET="$(openssl rand -hex 32)"
  else
    SHARED_SECRET="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
  fi
  echo "Generated shared secret: $SHARED_SECRET"
  echo "Add to your server's .env: SHARED_SECRET=$SHARED_SECRET"
  echo ""
fi

# Install hook script
mkdir -p "$(dirname "$HOOK_DST")"
cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"
echo "✓ Hook installed: $HOOK_DST"

# Write config
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" <<JSON
{
  "server_url": "$SERVER_URL",
  "shared_secret": "$SHARED_SECRET",
  "user_id": "default"
}
JSON
chmod 600 "$CONFIG_FILE"
echo "✓ Config written: $CONFIG_FILE"

# Register hooks in Claude Code settings
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
  mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
  echo '{}' > "$CLAUDE_SETTINGS"
fi

# Use Python to merge hooks into existing settings (avoids clobbering other config)
python3 - "$CLAUDE_SETTINGS" "$HOOK_DST" <<'PYEOF'
import json, sys
settings_path, hook_path = sys.argv[1], sys.argv[2]
cmd = f"CLAUDE_NOTIFY_URL=$(cat ~/.claude-notify/config.json | python3 -c \"import sys,json; print(json.load(sys.stdin)['server_url'])\") CLAUDE_NOTIFY_SECRET=$(cat ~/.claude-notify/config.json | python3 -c \"import sys,json; print(json.load(sys.stdin)['shared_secret'])\") python3 {hook_path}"
hook_entry = {"type": "command", "command": f"python3 {hook_path}"}
with open(settings_path) as f:
    cfg = json.load(f)
hooks = cfg.setdefault("hooks", {})
for event in ("Stop", "SubagentStop", "Notification"):
    group = hooks.setdefault(event, [{"hooks": []}])
    existing = group[0].setdefault("hooks", [])
    if not any(h.get("command", "").endswith("claude-notify.py") for h in existing):
        existing.append(hook_entry)
with open(settings_path, "w") as f:
    json.dump(cfg, f, indent=2)
print(f"✓ Hooks registered in {settings_path}")
PYEOF

echo ""
echo "Done. Restart Claude Code for hooks to take effect."
echo ""
echo "Hook reads config from env vars CLAUDE_NOTIFY_URL and CLAUDE_NOTIFY_SECRET."
echo "Set them in your shell profile or add to hooks command in settings.json."

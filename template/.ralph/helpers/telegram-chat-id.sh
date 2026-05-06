#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${RALPH_ENV_FILE:-$RALPH_DIR/.env}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

token="${TELEGRAM_BOT_TOKEN:-}"
api_base="${TELEGRAM_API_BASE:-https://api.telegram.org}"
timeout="${RALPH_NOTIFY_TIMEOUT:-10}"
delete_webhook=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --delete-webhook)
      delete_webhook=1
      shift
      ;;
    --help|-h)
      printf 'Usage: %s [--delete-webhook]\n' "$0"
      exit 0
      ;;
    *)
      printf 'Error: unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$token" ]]; then
  printf 'Error: set TELEGRAM_BOT_TOKEN in the environment or %s\n' "$ENV_FILE" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  printf 'Error: missing dependency: curl\n' >&2
  exit 1
fi

telegram_get() {
  local method="$1"
  curl --silent --show-error --max-time "$timeout" "$api_base/bot${token}/${method}"
}

telegram_post() {
  local method="$1"
  curl --silent --show-error --max-time "$timeout" --request POST "$api_base/bot${token}/${method}"
}

if [[ "$delete_webhook" -eq 1 ]]; then
  telegram_post 'deleteWebhook' >/dev/null
  printf 'Deleted webhook if one existed. Send the bot /start or any message, then run this helper again.\n'
  exit 0
fi

me="$(telegram_get 'getMe')"
webhook="$(telegram_get 'getWebhookInfo')"
updates="$(telegram_get 'getUpdates')"

if command -v python3 >/dev/null 2>&1; then
  TELEGRAM_GET_ME="$me" TELEGRAM_WEBHOOK="$webhook" TELEGRAM_UPDATES="$updates" python3 <<'PY'
import json
import os
import sys

def load_env(name):
    raw = os.environ.get(name, "")
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"Error: Telegram returned invalid JSON for {name}: {exc}", file=sys.stderr)
        sys.exit(1)

me = load_env("TELEGRAM_GET_ME")
webhook = load_env("TELEGRAM_WEBHOOK")
data = load_env("TELEGRAM_UPDATES")

if not me.get("ok"):
    print(f"Error: bot token check failed: {me.get('description', 'unknown error')}", file=sys.stderr)
    sys.exit(1)

bot = me.get("result", {})
username = bot.get("username", "unknown")
print(f"Bot: @{username}")

webhook_url = ""
if webhook.get("ok"):
    webhook_url = webhook.get("result", {}).get("url") or ""
    if webhook_url:
        print("Webhook: configured")
        print("getUpdates cannot reliably discover chat IDs while a webhook is configured.")
        print("Run: .ralph/helpers/telegram-chat-id.sh --delete-webhook")
    else:
        print("Webhook: none")
else:
    print(f"Webhook check failed: {webhook.get('description', 'unknown error')}")

if not data.get("ok"):
    print(f"Error: getUpdates failed: {data.get('description', 'unknown error')}", file=sys.stderr)
    sys.exit(1)

updates = data.get("result", [])
print(f"Pending updates: {len(updates)}")

seen = set()
for update in updates:
    chat = {}
    for key in ("message", "edited_message", "channel_post", "edited_channel_post"):
        if update.get(key, {}).get("chat"):
            chat = update[key]["chat"]
            break
    if not chat:
        for key in ("my_chat_member", "chat_member"):
            if update.get(key, {}).get("chat"):
                chat = update[key]["chat"]
                break

    chat_id = chat.get("id")
    if chat_id is None or chat_id in seen:
        continue
    seen.add(chat_id)
    title = chat.get("title") or chat.get("username") or " ".join(part for part in (chat.get("first_name"), chat.get("last_name")) if part) or "direct chat"
    print(f"{chat_id}\t{title}")

if not seen:
    if webhook_url:
        print("No chat IDs found because a webhook is configured or no pending message update exists.")
    else:
        print("No chat IDs found.")
    print(f"Open https://t.me/{username}, press Start, send /start or any message, then run this again.")
    print("If you already did that, send a new message now; old updates may have been consumed by another getUpdates call.")
PY
else
  printf '%s\n' "$updates"
fi

# $ZDOTDIR/conf.d/68-diagnostics.zsh
# ─────────────────────────────────────────────────────────────────────
# Diagnostics and system inspection helpers.
# ─────────────────────────────────────────────────────────────────────

# ── check-cert: inspect an SSL certificate over the wire ────────────
check-cert() {
  [[ $# -eq 1 ]] || { echo "usage: check-cert <host>[:port]" >&2; return 1; }
  local target="$1"
  [[ "$target" != *:* ]] && target="${target}:443"
  openssl s_client -showcerts -servername "${target%:*}" -connect "$target" \
    </dev/null 2>/dev/null | \
    openssl x509 -noout -subject -issuer -dates -ext subjectAltName
}
# check-cert github.com
# check-cert internal.zftadvancements.internal:8443

# ── claude-sync-path: refresh Claude Code settings.json PATH ────────
# Claude Code spawns subprocesses with a snapshot env; when mise adds new
# shims, this function keeps the snapshot current.
claude-sync-path() {
  local settings="$HOME/.claude/settings.json"
  [[ -f "$settings" ]] || { echo "No settings.json at $settings" >&2; return 1; }
  command -v jq >/dev/null || { echo "jq required" >&2; return 1; }
  jq --arg p "$PATH" '.env.PATH = $p' "$settings" > "${settings}.tmp" \
    && mv "${settings}.tmp" "$settings" \
    && echo "Updated PATH ($(echo "$PATH" | tr ':' '\n' | wc -l | tr -d ' ') entries)"
}

# ── hist-top: top 10 most-run commands (tune your aliases) ──────────
hist-top() {
  fc -l 1 | awk '{ CMD[$2]++; count++ } END {
    for (a in CMD) printf "%5d  %s\n", CMD[a], a
  }' | sort -rn | head -10
}

# ── duh: disk usage of current directory, sorted by size ────────────
duh() {
  du -sh "${1:-.}"/* 2>/dev/null | sort -h
}

# ── mise-env-diff: show what mise adds/changes in the environment ──
mise-env-diff() {
  local base mise_env
  base=$(env | sort)
  mise_env=$(mise exec -- env | sort)
  diff <(echo "$base") <(echo "$mise_env")
}

# ── path-dupes: show duplicate entries in PATH (should be zero) ────
path-dupes() {
  echo "$PATH" | tr ':' '\n' | sort | uniq -d
}

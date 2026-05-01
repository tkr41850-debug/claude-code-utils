#!/bin/bash
# cc-statusline — Claude Code statusline.
# Renders: model | branch[ wt][ +peers] | ctx (tokens vs auto-compact, vs window)
#          | cost burn (token breakdown, cache hit) | api/wall time.
#
# Wired in ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "bash \"$HOME/.claude/cc-statusline.sh\"" }
#
# See SPEC.md for full design.

set -u

INPUT=$(cat)

# Fields from Claude Code stdin JSON
CWD=$(jq -r '.cwd // .workspace.current_dir // "."' <<<"$INPUT")
MODEL_ID=$(jq -r '.model.id // ""' <<<"$INPUT")
TRANSCRIPT=$(jq -r '.transcript_path // ""' <<<"$INPUT")
COST=$(jq -r '.cost.total_cost_usd // 0' <<<"$INPUT")
WALL_MS=$(jq -r '.cost.total_duration_ms // 0' <<<"$INPUT")
API_MS=$(jq -r '.cost.total_api_duration_ms // 0' <<<"$INPUT")

# Git branch + worktree marker
BRANCH=""
WT=""
if git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
  GIT_DIR=$(git -C "$CWD" rev-parse --absolute-git-dir 2>/dev/null)
  COMMON_DIR=$(git -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  GIT_DIR=$(readlink -f "$GIT_DIR" 2>/dev/null || echo "$GIT_DIR")
  COMMON_DIR=$(readlink -f "$COMMON_DIR" 2>/dev/null || echo "$COMMON_DIR")
  [ -n "$GIT_DIR" ] && [ -n "$COMMON_DIR" ] && [ "$GIT_DIR" != "$COMMON_DIR" ] && WT=" wt"
fi

# Peer sessions: other transcripts in same project dir touched in last 5 min
PEERS=0
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  PROJ_DIR=$(dirname "$TRANSCRIPT")
  PEERS=$(find "$PROJ_DIR" -maxdepth 1 -name '*.jsonl' -mmin -5 -not -path "$TRANSCRIPT" 2>/dev/null | wc -l)
fi

# Short model name
case "$MODEL_ID" in
  *opus*\[1m\]*|*opus*-1m*) MODEL_FMT="opus[1m]" ;;
  *opus*)                   MODEL_FMT="opus" ;;
  *sonnet*\[1m\]*|*sonnet*-1m*) MODEL_FMT="sonnet[1m]" ;;
  *sonnet*)                 MODEL_FMT="sonnet" ;;
  *haiku*)                  MODEL_FMT="haiku" ;;
  "")                       MODEL_FMT="" ;;
  *)                        MODEL_FMT="$MODEL_ID" ;;
esac

# Context window per model
case "$MODEL_ID" in
  *"[1m]"|*"-1m"*) WINDOW=1000000 ;;
  *haiku*)         WINDOW=200000 ;;
  *)               WINDOW=200000 ;;
esac

# Auto-compact threshold default = 90% of window
COMPACT_DEFAULT=$(( WINDOW * 9 / 10 ))

# Last usage block (context %) + cumulative breakdown from transcript JSONL
TOKENS=0
PCT=0
if [ -f "$TRANSCRIPT" ]; then
  USAGE_LINE=$(tac "$TRANSCRIPT" 2>/dev/null | grep -m1 '"usage"' || true)
  if [ -n "$USAGE_LINE" ]; then
    TOKENS=$(jq -r '
      (.message.usage // .usage // {}) as $u |
      (($u.input_tokens // 0)
       + ($u.cache_read_input_tokens // 0)
       + ($u.cache_creation_input_tokens // 0))
    ' <<<"$USAGE_LINE" 2>/dev/null || echo 0)
    [ -z "$TOKENS" ] && TOKENS=0
  fi
  BREAKDOWN=$(jq -rs '
    [ .[] | (.message.usage // .usage // empty) ] as $u |
    "\([$u[].input_tokens // 0] | add // 0) " +
    "\([$u[].output_tokens // 0] | add // 0) " +
    "\([$u[].cache_read_input_tokens // 0] | add // 0) " +
    "\([$u[].cache_creation_input_tokens // 0] | add // 0)"
  ' "$TRANSCRIPT" 2>/dev/null || echo "0 0 0 0")
  read -r IN_TOK OUT_TOK CR_TOK CW_TOK <<<"$BREAKDOWN"
  : "${IN_TOK:=0}"; : "${OUT_TOK:=0}"; : "${CR_TOK:=0}"; : "${CW_TOK:=0}"
  COMPACTS=$(grep -c '"isCompactSummary":true' "$TRANSCRIPT" 2>/dev/null)
  [ -z "$COMPACTS" ] && COMPACTS=0
  OBSERVED=0
  if [ "$COMPACTS" -gt 0 ]; then
    OBSERVED=$(jq -rs '
      [ .[] | (.message.usage // .usage // empty) |
        (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)
      ] | max // 0
    ' "$TRANSCRIPT" 2>/dev/null)
    [ -z "$OBSERVED" ] && OBSERVED=0
  fi
else
  IN_TOK=0; OUT_TOK=0; CR_TOK=0; CW_TOK=0
  COMPACTS=0
  OBSERVED=0
fi

# Resolve compact limit: env override > observed (if any) > default. Clamp to window.
if [ -n "${CLAUDE_AUTOCOMPACT_TOKENS:-}" ]; then
  COMPACT_LIMIT=$CLAUDE_AUTOCOMPACT_TOKENS
elif [ "$OBSERVED" -gt 0 ]; then
  COMPACT_LIMIT=$OBSERVED
else
  COMPACT_LIMIT=$COMPACT_DEFAULT
fi
[ "$COMPACT_LIMIT" -gt "$WINDOW" ] && COMPACT_LIMIT=$WINDOW

# PCT against compact limit
[ "$COMPACT_LIMIT" -gt 0 ] && PCT=$(awk "BEGIN { printf \"%d\", ($TOKENS / $COMPACT_LIMIT) * 100 }")

# Human-friendly token format
fmt() {
  local n=$1
  if   [ "$n" -ge 1000000 ]; then awk "BEGIN { printf \"%.1fM\", $n/1000000 }"
  elif [ "$n" -ge 1000 ];    then awk "BEGIN { printf \"%dk\", $n/1000 }"
  else echo "$n"
  fi
}
TOK_FMT=$(fmt "$TOKENS")
WIN_FMT=$(fmt "$WINDOW")
COMPACT_FMT=$(fmt "$COMPACT_LIMIT")
IN_FMT=$(fmt "$IN_TOK")
OUT_FMT=$(fmt "$OUT_TOK")
CR_FMT=$(fmt "$CR_TOK")
CW_FMT=$(fmt "$CW_TOK")
COST_FMT=$(awk "BEGIN { printf \"\$%.2f\", $COST }")

# Cache hit rate: cr / (i + cr + cw)
HIT_PCT=0
DENOM=$(( IN_TOK + CR_TOK + CW_TOK ))
[ "$DENOM" -gt 0 ] && HIT_PCT=$(awk "BEGIN { printf \"%d\", $CR_TOK*100/$DENOM }")

# Burn rate over last 10 turns:
#   weight uses cost-proxy ratios (in:1, cr:0.1, cw:1.25, out:5).
#   cost_last10 ≈ total_cost * weight_last10 / weight_total
#   burn = cost_last10 / minutes_since_first_of_last_10
BURN=""
if [ -f "$TRANSCRIPT" ] && [ "$(awk "BEGIN { print ($COST > 0) }")" = "1" ]; then
  BURN_DATA=$(jq -rs '
    [ .[] | select((.message.usage // .usage) != null) ] as $turns |
    ($turns | length) as $n |
    if $n == 0 then "0 0 0"
    else
      def w: (.input_tokens // 0) + (.cache_read_input_tokens // 0)*0.1
             + (.cache_creation_input_tokens // 0)*1.25 + (.output_tokens // 0)*5;
      ([ $turns[]      | (.message.usage // .usage) | w ] | add // 0) as $tw  |
      ([ $turns[-10:][] | (.message.usage // .usage) | w ] | add // 0) as $w10 |
      ($turns[-10:][0].timestamp // "") as $firstTs |
      "\($firstTs) \($w10) \($tw)"
    end
  ' "$TRANSCRIPT" 2>/dev/null || echo "0 0 0")
  read -r FIRST_TS W10 W_TOT <<<"$BURN_DATA"
  if [ -n "$FIRST_TS" ] && [ "$FIRST_TS" != "0" ]; then
    TS_CLEAN=${FIRST_TS%.*}; TS_CLEAN=${TS_CLEAN%Z}
    START_S=$(date -u -D "%Y-%m-%dT%H:%M:%S" -d "$TS_CLEAN" +%s 2>/dev/null \
              || date -u -d "$TS_CLEAN" +%s 2>/dev/null \
              || echo 0)
    NOW_S=$(date +%s)
    if [ "$START_S" -gt 0 ] && [ "$NOW_S" -gt "$START_S" ]; then
      BURN=$(awk "BEGIN {
        m = ($NOW_S - $START_S) / 60;
        if ($W_TOT > 0 && m > 0) printf \"\$%.2f/m\", $COST * $W10 / $W_TOT / m
      }")
    fi
  fi
fi

# Duration formatter: ms → "Xs" / "XmYs" / "XhYm"
dur() {
  local ms=$1
  local s=$(( ms / 1000 ))
  if   [ "$s" -lt 60 ];   then printf '%ds' "$s"
  elif [ "$s" -lt 3600 ]; then printf '%dm%ds' $((s/60))   $((s%60))
  else                         printf '%dh%dm' $((s/3600)) $(((s%3600)/60))
  fi
}
WALL_FMT=$(dur "$WALL_MS")
API_FMT=$(dur "$API_MS")

# Color helpers (ANSI 256-color)
DIM='\033[2m'
RESET='\033[0m'
BRANCH_COLOR='\033[38;5;78m'   # green
CTX_COLOR='\033[38;5;110m'     # blue
COST_COLOR='\033[38;5;180m'    # tan
TIME_COLOR='\033[38;5;141m'    # purple
MODEL_COLOR='\033[38;5;215m'   # orange
PEER_COLOR='\033[38;5;203m'    # red

SEP=$(printf "${DIM} │ ${RESET}")
OUT=""
[ -n "$MODEL_FMT" ]  && OUT+="$(printf "${MODEL_COLOR}%s${RESET}" "$MODEL_FMT")${SEP}"
if [ -n "$BRANCH" ]; then
  BRANCH_STR="$(printf "${BRANCH_COLOR}%s%s${RESET}" "$BRANCH" "$WT")"
  [ "$PEERS" -gt 0 ] && BRANCH_STR+="$(printf " ${PEER_COLOR}+%s${RESET}" "$PEERS")"
  OUT+="${BRANCH_STR}${SEP}"
fi
if [ "$COMPACT_LIMIT" -lt "$WINDOW" ]; then
  CTX_STR="$(printf "${CTX_COLOR}%s/%s|%s (%s%%)${RESET}" "$TOK_FMT" "$COMPACT_FMT" "$WIN_FMT" "$PCT")"
else
  CTX_STR="$(printf "${CTX_COLOR}%s/%s (%s%%)${RESET}" "$TOK_FMT" "$WIN_FMT" "$PCT")"
fi
[ "$COMPACTS" -gt 0 ] && CTX_STR+="$(printf " ${CTX_COLOR}⇩%s${RESET}" "$COMPACTS")"
OUT+="${CTX_STR}${SEP}"
COST_STR="$(printf "${COST_COLOR}%s" "$COST_FMT")"
[ -n "$BURN" ] && COST_STR+="$(printf " %s" "$BURN")"
COST_STR+="$(printf " (i:%s o:%s cr:%s cw:%s hit:%s%%)${RESET}" "$IN_FMT" "$OUT_FMT" "$CR_FMT" "$CW_FMT" "$HIT_PCT")"
OUT+="${COST_STR}${SEP}"
OUT+="$(printf "${TIME_COLOR}api %s / wall %s${RESET}" "$API_FMT" "$WALL_FMT")"

printf '%b' "$OUT"

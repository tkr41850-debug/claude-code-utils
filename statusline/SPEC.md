# cc-statusline — Design Spec

`cc-statusline.sh` is a single bash script invoked by Claude Code on every prompt redraw. It reads the harness's stdin JSON, parses the active session's transcript JSONL, and emits one ANSI-colored line.

## Layout

```
<model> │ <branch>[ wt][ +N] │ <ctx>[ ⇩C] │ <cost> <burn> (<breakdown>) │ api <t> / wall <t>
```

Sections separated by ` │ ` (dim). Fields are hidden when their source data is missing or zero (e.g. peer count, burn rate, compaction count).

## Fields

| # | Field | Format | Source | Notes |
|---|---|---|---|---|
| 1 | Model | `opus[1m]` / `sonnet` / `haiku` | stdin `.model.id` | Pattern-matched short name |
| 2 | Branch + worktree + peers | `feat-x wt +3` | `git -C $cwd branch --show-current` | `wt` if `git-dir != git-common-dir`. `+N` = other transcripts in project mtime'd in last 5 min |
| 3 | Context + compactions | `135k/180k\|1.0M (75%) ⇩7` | last `usage` block in transcript | `current/compact-limit\|window (% of compact)`. `⇩N` only if N>0 |
| 4 | Cost + burn + breakdown | `$4.21 $0.07/m (i:10M o:6M cr:265M cw:0 hit:96%)` | stdin `.cost.total_cost_usd` + transcript walk | See below |
| 5 | Time | `api 10m50s / wall 2h30m` | stdin `.cost.total_api_duration_ms`, `.cost.total_duration_ms` | Format: `Xs` / `XmYs` / `XhYm` |

## Compact-limit resolution

Priority chain:

1. `CLAUDE_AUTOCOMPACT_TOKENS` env override
2. Observed pre-compact max in transcript (only if `isCompactSummary:true` ever seen)
3. `WINDOW * 9/10` default

Clamped to ≤ window. When `compact-limit < window`, two-tier `<cur>/<limit>|<window>` is shown; else collapsed to `<cur>/<window>`.

## Window detection

```bash
case $MODEL_ID in
  *[1m]|*-1m*) WINDOW=1_000_000 ;;
  *)           WINDOW=200_000 ;;
esac
```

Add new patterns as new long-context tiers ship.

## Cost breakdown (`i o cr cw hit`)

Cumulative sums across every `usage` block in the transcript:

- `i` — `input_tokens`
- `o` — `output_tokens`
- `cr` — `cache_read_input_tokens`
- `cw` — `cache_creation_input_tokens`
- `hit% = cr / (i + cr + cw) * 100`

## Burn rate

Last 10 turns with a `usage` block. Each turn is weighted as a cost proxy:

```
w = input + cache_read*0.1 + cache_creation*1.25 + output*5
```

Ratios mirror Anthropic's pricing structure and are roughly uniform across opus/sonnet/haiku, so the exact dollar rate doesn't need to be hardcoded.

```
cost_last10 = total_cost * w_last10 / w_total
burn        = cost_last10 / minutes_since_first_of_last_10
```

Hidden when no usage seen, no cost yet, or stale transcript yields ~$0.

## Token format

| Range | Render |
|---|---|
| `< 1k` | `N` |
| `< 1M` | `Nk` |
| `≥ 1M` | `N.NM` |

## Color palette (ANSI 256-color)

| Field | Code | Hue |
|---|---|---|
| Model | `215` | orange-light |
| Branch | `78` | green |
| Peers | `203` | red (alert) |
| Context | `110` | blue |
| Cost | `180` | tan |
| Time | `141` | purple |
| Separator | dim | grey |

## Dependencies

`bash`, `jq`, `awk`, `tac`, `git`, `find`, `date`, `readlink -f`. Works on BusyBox via `date -D` fallback.

## Stdin contract

```jsonc
{
  "cwd": "...",                 // for git
  "model": { "id": "..." },     // for window + display
  "transcript_path": "...",     // JSONL parse target
  "cost": {
    "total_cost_usd": 0,
    "total_duration_ms": 0,     // wall
    "total_api_duration_ms": 0  // api
  }
}
```

## Env overrides

| Var | Effect |
|---|---|
| `CLAUDE_AUTOCOMPACT_TOKENS` | Pin auto-compact threshold (e.g. `200000`). Wins over auto-detect. |

## Wired in

`~/.claude/settings.json` →

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"$HOME/.claude/cc-statusline.sh\""
  }
}
```

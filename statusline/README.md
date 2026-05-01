# cc-statusline

Compact statusline for [Claude Code](https://claude.com/claude-code) showing model, branch, context usage, cost, burn rate, token breakdown, cache hit rate, and timing — all in one line.

## Format

```
opus[1m] │ feat-x wt +2 │ 119k/180k|1.0M (66%) ⇩7 │ $4.21 $0.07/m (i:10M o:6M cr:265M cw:0 hit:96%) │ api 10m50s / wall 2h30m
```

| Field | Meaning |
|---|---|
| `opus[1m]` | model in use (short name) |
| `feat-x` | git branch |
| `wt` | currently in a git worktree (vs. main checkout) |
| `+2` | other Claude Code sessions in this project active in the last 5 min |
| `119k/180k\|1.0M` | current context tokens / auto-compact threshold / hard window |
| `(66%)` | how close to the next auto-compact |
| `⇩7` | number of compactions this session has gone through |
| `$4.21` | total session cost |
| `$0.07/m` | recent burn rate (avg cost/min over last 10 turns) |
| `i / o / cr / cw` | input / output / cache-read / cache-write tokens, cumulative |
| `hit:96%` | cache hit rate = `cr / (i + cr + cw)` |
| `api 10m50s` | total API request duration |
| `wall 2h30m` | total wall-clock time over session lifetime |

When the auto-compact limit equals the window (no early threshold), the context block collapses to `119k/1.0M (12%)`. When the session has no compactions and no env override, the limit defaults to 90% of window.

## Install

```bash
wget -qO- https://raw.githubusercontent.com/tkr41850-debug/claude-code-utils/main/statusline/install.sh | bash
```

or with curl:

```bash
curl -fsSL https://raw.githubusercontent.com/tkr41850-debug/claude-code-utils/main/statusline/install.sh | bash
```

The installer:
1. Checks dependencies (`jq`, `awk`, `git`, `find`).
2. Downloads `cc-statusline.sh` to `~/.claude/cc-statusline.sh`.
3. Backs up `~/.claude/settings.json` (timestamped).
4. Sets `statusLine.command` to `bash "$HOME/.claude/cc-statusline.sh"`.
5. Restart Claude Code to take effect.

## Uninstall

```bash
rm ~/.claude/cc-statusline.sh
```

Then remove the `statusLine` key from `~/.claude/settings.json`, or restore the most recent `~/.claude/settings.json.bak.<timestamp>`.

## Env variables

| Var | Effect |
|---|---|
| `CLAUDE_AUTOCOMPACT_TOKENS` | Pin the auto-compact threshold (e.g. `200000`). Wins over auto-detect. |

## Manual install

If you'd rather not pipe `bash`:

```bash
mkdir -p ~/.claude
curl -fsSL https://raw.githubusercontent.com/tkr41850-debug/claude-code-utils/main/statusline/cc-statusline.sh \
  -o ~/.claude/cc-statusline.sh
chmod +x ~/.claude/cc-statusline.sh
```

Then add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"$HOME/.claude/cc-statusline.sh\""
  }
}
```

## See also

- [SPEC.md](SPEC.md) — full design spec (fields, sources, color codes, resolution rules)

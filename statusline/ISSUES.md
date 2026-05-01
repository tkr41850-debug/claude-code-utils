# Known Issues

Documented quirks, approximations, and untested edges in `cc-statusline.sh`. None block normal use; recorded so future changes can address them deliberately.

## Inaccuracies (output may not match reality)

### Compact threshold default is a guess

When no env override is set and no compaction has occurred yet, the script falls back to `WINDOW * 9/10` as the auto-compact limit. Real auto-compact may trigger lower (~82% observed in some sessions). Once a session has compacted at least once, the observed pre-compact max replaces the default.

**Workaround:** set `CLAUDE_AUTOCOMPACT_TOKENS` if you know your account's actual threshold.

### Burn-rate weights are opus-biased

The cost proxy `w = input + cache_read*0.1 + cache_creation*1.25 + output*5` mirrors Anthropic's pricing ratios but those ratios shift slightly across models. For sonnet/haiku-only sessions, `$/min` may drift a few percent from the true rate. Total session cost is taken from the harness directly and is unaffected.

### Cache-hit denominator excludes output

`hit% = cr / (i + cr + cw) * 100`. Output tokens are excluded because cache hits apply to input. This is the convention but some tools include output in the denominator. Pick one and don't compare across tools.

### `/usage` numbers don't match statusline

A fresh `/resume` showed `api 4h57m / wall 8h23m` for what the user knew was a <2h conversation. Never definitively explained — appears to come from a workspace-cumulative or process-lifetime aggregation rather than this conversation's transcript alone. The statusline numbers reflect what the harness reports via stdin `cost.*`; they're consistent with `/usage` but not with wall-clock perception.

## Edge cases (untested or known-fragile)

### BusyBox-only `date -D` parsing; BSD `date` untested

The script uses GNU `date -d`, falls back to BusyBox `date -D "%Y-%m-%dT%H:%M:%S"`. macOS BSD `date` accepts neither form directly — would need a third branch. Not exercised because no macOS tester yet.

### Worktree detection may misdetect submodules

Detection relies on `git-dir != git-common-dir`. Submodules also have a separate `git-dir`, so a submodule checkout would render as `wt`. Acceptable since submodule sessions are rare in this workflow.

### Peer-count window is hardcoded

"Other Claude Code sessions in this project active in the last 5 min" — the 5-minute window is baked into the `find -mmin -5` call. No env knob.

### Long worktree branch names not trimmed

Branch names from worktrees can be 30+ chars (e.g. `feat-orchestrator-recovery-service-abc123`). The statusline does not truncate; on narrow terminals this pushes later fields off-screen.

### Stale-resumed sessions show ~$0 burn

Burn rate uses the last 10 turns from the transcript. If you `/resume` an old session and idle, those 10 turns may all be hours old → `cost_last10 / minutes_since_first_of_last_10 ≈ 0`. The display hides burn when the result is essentially zero, so the field disappears rather than reporting nonsense.

## Ignored / out of scope

### 3 concurrent sessions in workspace never explained

While debugging peer detection, 3 transcripts in `~/.claude/projects/-home-alpine-vcode0/` were active within the 5-min window — only 1 was a known shell. Origin of the other 2 never identified. Possibly background subagent invocations or stale processes.

### Subagent subdirs never inspected

Some project directories contain `<uuid>/subagents/<uuid>.jsonl` files. The statusline only walks top-level transcripts. Subagent token cost may not be reflected in the breakdown depending on whether the harness aggregates them into the parent transcript's `usage` blocks. Not investigated.

### `cc-statusline.sh` never tested in live Claude Code

The packaged script (without the caveman badge) was smoke-tested against real transcript JSONLs via stdin piping but never wired into a live session. The user's installed copy at `~/.claude/statusline.sh` is what's actually verified end-to-end.

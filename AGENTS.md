# Agent Notes

## Agent PBX

Use Agent PBX as the coordination bus when the operator enables it for a
session. This repo currently uses the stable agent id `codex-pocketchip-dev`.

- Poll `pbx_poll_commands` for `codex-pocketchip-dev` before work, after
  progress reports, before ending a turn, and periodically during long work.
- Handle delivered commands in order.
- Ack commands with `pbx_ack_command` only after the requested command has been
  handled.
- Report milestones, blockers, test results, flash/deploy results, and final
  outcomes with `pbx_report_turn`.
- Keep PBX report summaries short and put operational detail in `detail`.
- For long-running builds, flashes, or hardware tests, send a working report at
  least every five minutes and poll after the report.
- For terminal status reports (`done`, `completed`, `failed`, `canceled`, or
  `blocked`), open one bounded follow-up poll window:

  ```text
  pbx_poll_commands(wait_seconds=25, max_wait_seconds=600, interval_seconds=5)
  ```

  If no command arrives in that window, stop polling until the next explicit
  PBX action or new work.
- Treat `ping` commands as keepalives: send a concise working pong report, ack
  with `{"pong": true}`, then poll for another bounded five-minute window.
- Never poll or ack commands for another agent id.
- If PBX is unavailable, continue local work when safe and retry/report later.

Before sending a terminal PBX report for repository work, inspect git state and
include whether the worktree is clean, staged, unstaged, or committed.

## PocketCHIP Workflow

- Prefer UART for bootloader, FEL, and early-boot truth.
- Prefer SSH for large live-system captures or file transfer once Wi-Fi is up.
- Do not print credentials from `configs/local.env`; only report whether
  passwords or Wi-Fi fields are set.
- Local private assets and generated screenshots belong under `.local/`, which
  is gitignored.
- Keep NAND write commands guarded with `CONFIRM_NAND_WRITE=YES` and the
  script-level destructive-write flags.
- Treat NAND/SLC support as validated only for the tested Toshiba 4G MLC unit
  unless additional hardware variants are confirmed.
- Use `make publish-check` before release/publication-oriented commits.

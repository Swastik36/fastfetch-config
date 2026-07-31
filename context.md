# Fastfetch Partial Dashboard — Agent Context

## Architecture

- **Entry point**: `~/.bashrc` overrides the `fastfetch()` shell function to call `fastfetch_partial.sh`
- **Engine**: `fastfetch_partial.sh` — partial ANSI-cursor update loop (~2ms/tick). Always passes `--config` explicitly (tracked `config.jsonc` or `ex.jsonc`), so the repo is fully self-contained
- **Initial draw**: `redraw_full()` runs `command fastfetch` directly to terminal (bypasses bash wrapper via `command`)
- **Layout detection**: `scan_layout()` runs a SECOND piped fastfetch and parses output to find row/col of each dynamic field
- **Update loop**: Every 1s, overwrites values at detected positions using `\033[row;colH`
- **Sparklines**: CPU + Memory history sparklines (16-sample, gradient green/yellow/red per level) rendered as `│ └ Spark` sub-heading rows in the tree (config command modules with a `▁▁▁… 0%` placeholder). `scan_layout` matches `"│ └ Spark"` (first = CPU, second = Memory). Chars start at `value_col` (keys are 11 chars like the rest), followed by a live ` %` suffix — the memory % proves the row is updating even when the line is flat (memory moves < 12.5% per tick, so levels quantize to one char)

## Key Files

| Path | Role |
|------|------|
| `~/.config/fastfetch-partial/fastfetch_partial.sh` | Main engine (tracked in git) |
| `~/.config/fastfetch-partial/config.jsonc` | Default config (tracked in git) |
| `~/.config/fastfetch-partial/logo.txt` | Default logo "Swazi" (tracked in git) |
| `~/.config/fastfetch-partial/logo_ex.txt` | -ex logo "SWAZI" (tracked in git) |
| `~/.config/fastfetch-partial/ex.jsonc` | -ex config (tracked in git) |
| `~/.config/fastfetch/config.jsonc` | Legacy config (NOT versioned — only used by bare `fastfetch` / legacy script; mirrored in `legacy/`) |
| `~/.config/fastfetch/fastfetch_whole.sh` | Legacy whole-refresh script (deprecated, time-invariant; mirrored in `legacy/`) |
| `~/.config/autostart/Fast fetch.desktop` | Autostart: `kitty --width 120 -e bash -ic "fastfetch"` |
| `~/.config/kitty/kitty.conf` | Must have `allow_remote_control yes` for resize |
| `~/.bashrc` | `fastfetch()` wrapper with `resize-os-window` |
| `~/.git-credentials` | PAT for `github.com/Swastik36/fastfetch-config.git` |

## Critical Details (Not Obvious from Code)

### --pipe false (scan_layout line 39)
Without `--pipe false`, fastfetch omits TTY-dependent modules (like Terminal Font) when piped. This makes the piped output have 20 lines while the direct TTY draw has 21 lines, causing ALL row detection to be off by 1 for every field after the font module. The `--pipe false` flag makes the piped output match the TTY draw exactly.

### seq 1 0 Bar Bug
In GNU coreutils, `seq 1 0` produces NO output (empty), but `printf '█%.0s'` with zero arguments still prints one `█` because printf repeats the format for each argument — zero arguments means the format literal `█` still prints once. This makes 0% bars show 1 filled block (9 chars total) instead of 0 (8 chars). The fix: guard with `[ "$filled" -gt 0 ] &&` to skip the printf entirely when filled is 0. This guard must be applied BOTH in the engine AND inside every config `command` module that draws a bar (CPU/GPU Core, Battery) — the configs are what the initial draw shows for ~1s after each redraw.

Same issue applies to the empty-bar side: `seq 1 8` works fine, but needs guarding for symmetry.

### Negative Array Slice Gotcha (bash 5.2)
`"${arr[@]: -N}"` returns EMPTY when N is larger than the array size (bash does NOT clamp). The ring-buffer idiom `arr=("${arr[@]: -15}" "$new")` silently drops all history while the array has < 15 elements. Use append + explicit trim instead: `arr+=("$new")` then `[ "${#arr[@]}" -gt 16 ] && arr=("${arr[@]:1}")`. The sparkline render clamps its offset with `off=$(( ${#arr[@]} - spark_len )); [ "$off" -lt 0 ] && off=0`.

Also: perl one-liners matching multibyte spark chars need `-CSD` AND codepoint escapes (`[\x{2581}-\x{2588}]`) — literal UTF-8 chars in `-e` scripts are only decoded with `-Mutf8`.

### ANSI \033[K Behavior
`\033[K` clears from cursor to END OF LINE. When the cursor is near the right edge of the terminal and the value text wraps to the next visual line, `\033[K` only clears the current visual line (the wrapped fragment), not the whole logical row. This can leave partial fragments visible on adjacent visual lines.

### Terminal Resize Strategy
- **Autostart**: `kitty --width 120` works natively for new kitty instances
- **Interactive**: `fastfetch()` function in `.bashrc` runs `printf '\033[8;35;120t'` followed by `kitty @ resize-os-window --width 120 --height 35 --unit cells --self` to resize current terminal.
- **Prerequisite**: `kitty.conf` must have `allow_remote_control yes` (configured).

### Logo Padding (right: 3)
Logo right padding is configured to `"right": 3` across all config JSON files (`config.jsonc`, `ex.jsonc`, `config.jsonc` legacy). This shifts right-side keys and metrics horizontally for visual spacing while `scan_layout()` dynamically measures `value_col` and `clock_col`.

### CPU Model Truncation
The original `type: "cpu"` with `format: "{1} @4.2"` outputs the full CPU name like "11th Gen Intel(R) Core(TM) i5-1135G7 @4.2" (~42 chars). Changed to `type: "command"` that runs lscpu + awk to strip "Intel(R) Core(TM) ", saving ~22 chars. The awk regex also replaces the real frequency with `@4.2` to keep a fixed width.

### Two-Config System
- **normal mode**: `fastfetch` (default) — uses `fastfetch-partial/config.jsonc` + `logo.txt` (cyan "Swazi" logo)
- **-ex mode**: `fastfetch -ex` — uses `fastfetch-partial/ex.jsonc` + `logo_ex.txt` (magenta "SWAZI" logo, different key colors)
- Both configs have identical module ordering. The only differences are logo art, colors, and logo width (wider in ex mode by ~5 chars).
- Logo sources are relative to the tracked dir: `~/.config/fastfetch-partial/logo*.txt`. The legacy copies in `~/.config/fastfetch/` are only for bare fastfetch invocations.

### Row/Column Detection Logic
`scan_layout()` parses piped output with:
- `uptime_row`: line containing `├ Uptime`
- `cpu_core_row`: FIRST line containing `│ └ Core`
- `gpu_core_row`: SECOND line containing `│ └ Core`
- `mem_row`: line containing `├ Memory`
- `net_row`: line containing `├ Network`
- `bat_row`: line containing `└ Battery`
- `clock_row`: line containing `🕒`
- `value_col`: prefix length before ` ➜  ` separator + separator length + 1
- `clock_col`: character position of `🕒` in the line

The detection order matters — both CPU and GPU Core share the same key `" │ └ Core  "`, so the first match is CPU and the second is GPU.

### Git Repo
- Remote: `https://github.com/Swastik36/fastfetch-config.git`
- Branch: `main`
- `~/.config/fastfetch-partial/` is fully self-contained and tracked: engine script, both configs, both logos, `context.md`, `README.md`. The engine always passes `--config` from this dir, so a fresh clone works without manual copies.
- Legacy `~/.config/fastfetch/` is NOT versioned anymore (its git repo was merged into this one — see `legacy/`). The engine no longer reads anything from it; only bare `fastfetch` and `fastfetch_whole.sh` use those files. Live copies must be edited manually, then re-mirrored into `legacy/`.

### Known Gotchas
- `~` inside double-quoted bash strings does NOT expand — always use `$HOME`
- `awk` variable named `if` clashes with builtin — use `n` or other names
- Key lengths in config JSON should all be 11 chars for separator alignment (e.g., `" ├ Uptime  "`)
- `scan_layout` must run a second piped fastfetch after the initial draw; the initial draw goes to terminal, the second is captured for parsing
- `\033[K` can scramble adjacent content if lines wrap — keep update strings under ~95 cols
- `redraw_full` does `\033[H\033[J` (clear + home) before redrawing — this prevents cursor-position drift on SIGWINCH

## Session Log — 2026-07-31 (Bug Fixes + Resize)

### Diagnosis (ex mode corruption)
- `scan_layout` used piped fastfetch output (20 rows) while the direct TTY draw had 21 rows — Terminal Font module was omitted when piped, shifting every row below it
- ex mode lines exceeded terminal width, causing wrapping → visual rows diverged from logical rows → values printed under wrong headings
- `seq 1 0` bug: `printf '█%.0s'` with no args still prints one `█`, making 0% bars 9 chars wide

### Fixes applied
| # | Fix | File |
|---|-----|------|
| 1 | `--pipe false` in scan_layout — piped output now matches TTY (21 rows) | `fastfetch_partial.sh:39` |
| 2 | `[ "$filled" -gt 0 ]` guards on CPU/GPU/Battery bars — always exactly 8 chars | `fastfetch_partial.sh:151,186,222` + all 3 configs' command modules (2026-07-31) |
| 3 | CPU module → command type, strips "Intel(R) Core(TM) ", saves ~22 cols | All 3 configs |
| 4 | `padding.right` 0 → 3 | All 3 configs |
| 5 | bashrc: `kitty @ resize-os-window --width 120 --height 35 --unit cells --self` + ANSI `\033[8;35;120t` fallback | `~/.bashrc:139-140` |
| 6 | kitty.conf: `allow_remote_control yes` | `~/.config/kitty/kitty.conf` |
| 7 | Autostart: removed invalid `--width 120` (not a kitty flag) | `Fast fetch.desktop` |
| 8 | `context.md` created for future agents | `~/.config/fastfetch-partial/context.md` |
| 9 | Logo badges now use a `--:--:--` placeholder (time-invariant, all 4 copies identical); `draw_clock()` stamps the real time immediately after every redraw so the placeholder never flashes | logos + `fastfetch_partial.sh:88` |
| 10 | Network interface re-detected every tick; speed baselines reset when the iface appears or changes (late WiFi at boot / eth switch auto-heal) | `fastfetch_partial.sh:248` |
| 11 | Battery AC check uses `grep -m1 .` — handles multiple adapters and both glob patterns without false `[DC!]` | `fastfetch_partial.sh:230` |
| 12 | Config `command` modules for CPU/GPU Core + Battery are static placeholders (like Network) — engine owns live values; no duplicate sampling, no 50ms sleep in scan_layout | All 3 configs |
| 13 | `fastfetch_whole.sh` badges made time-invariant (`--:--:--`) — running it can no longer clobber logos with stale timestamps; legacy repo merged into main repo (`legacy/` + `history.bundle`) | `legacy/fastfetch_whole.sh` |
| 14 | First loop tick after 200ms instead of 1s (`tick_delay`, reset by `redraw_full`) — no 1s placeholder flash at boot or after resize; CPU%/network still real deltas | `fastfetch_partial.sh:129` |

### Verification passed
- Both modes run clean (exit 0)
- Cursor positions match scan_layout exactly (value_col 65 normal / 70 ex)
- Bars are 8 chars at 0%, 50%, 100%
- CPU row dropped 112 → 92 chars

### Autostart
`kitty --title "Fastfetch Dashboard" -e bash -ic "fastfetch"` — resize handled inside the bashrc function (`resize-os-window`). Note: `--width` is NOT a valid kitty CLI flag; window sizing is done via `-o` overrides or the remote-control resize after launch.

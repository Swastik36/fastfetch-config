# Fastfetch Partial Dashboard

A live system dashboard on top of [fastfetch](https://github.com/fastfetch-cli/fastfetch) that updates its dynamic values **in place** — no full redraws, no screen flicker.

It draws fastfetch once, silently detects the exact row/column of every dynamic field, then every second overwrites only those positions with ANSI cursor escapes. On terminal resize (SIGWINCH) it fully redraws and re-scans.

## Features

- Live-updating: time badge, uptime, CPU usage/freq/temp, GPU usage/freq, memory, battery, network speed
- Zero flicker (partial ANSI update, ~2ms/tick)
- Instant first update (~200ms after boot/resize — no placeholder flash)
- Auto-adapts to terminal size and config (rows/columns detected at runtime)
- Two modes: `fastfetch` (cyan "Swazi") and `fastfetch -ex` (magenta "SWAZI")
- Fully self-contained git repo — clone and it works

## Requirements

| Dependency | Needed for | Optional? |
|---|---|---|
| fastfetch (recent version, supports `--pipe false`) | the dashboard itself | no |
| bash 4+ (`mapfile`), GNU coreutils (`seq`), awk, sed, grep | the engine | no |
| kitty terminal | terminal resize integration | yes (any 120x35-capable terminal works, minus auto-resize) |
| lm-sensors (`sensors`) | CPU temperature | yes (falls back to `/sys/class/thermal`) |
| power-profiles-daemon (`powerprofilesctl`) | power-plan tag in the battery line | yes (falls back to `balanced`) |
| font with glyphs: `█ ░ ➜ 🕒 ↓ ↑` and box-drawing chars | correct rendering | yes (Nerd Font / kitty defaults) |

## Installation

```bash
# 1. Clone into place
git clone https://github.com/Swastik36/fastfetch-config.git ~/.config/fastfetch-partial

# 2. Make the engine executable
chmod +x ~/.config/fastfetch-partial/fastfetch_partial.sh

# 3. Optional: legacy files used only by bare `fastfetch` (not the dashboard)
mkdir -p ~/.config/fastfetch
cp ~/.config/fastfetch-partial/legacy/config.jsonc ~/.config/fastfetch/config.jsonc
cp ~/.config/fastfetch-partial/legacy/logo.txt ~/.config/fastfetch-partial/legacy/logo_ex.txt ~/.config/fastfetch/
cp ~/.config/fastfetch-partial/legacy/fastfetch_whole.sh ~/.config/fastfetch/
```

## Shell integration (optional but recommended)

Add to `~/.bashrc`. The wrapper resizes the terminal to 120x35, then launches the engine:

```bash
fastfetch() {
    printf '\033[8;35;120t' 2>/dev/null
    kitty @ resize-os-window --width 120 --height 35 --unit cells --self 2>/dev/null
    "$HOME/.config/fastfetch-partial/fastfetch_partial.sh" "$@"
}
```

The `kitty @ resize-os-window` call requires `allow_remote_control yes` in `~/.config/kitty/kitty.conf`:

```
allow_remote_control yes
```

The `printf '\033[8;35;120t'` ANSI fallback works in most terminals without kitty.

## Autostart (optional)

`~/.config/autostart/Fast fetch.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=Fast fetch
Comment=Launch Fastfetch live dashboard on startup in Kitty
Exec=kitty --title "Fastfetch Dashboard" -e bash -ic "fastfetch"
X-GNOME-Autostart-enabled=true
NoDisplay=false
Hidden=false
X-GNOME-Autostart-Delay=0
```

## Usage

```bash
fastfetch        # normal mode (cyan Swazi logo)
fastfetch -ex    # alternate mode (magenta SWAZI logo)
```

Exit with `Ctrl+C` (restores the cursor and clears the screen). The dashboard re-scans automatically on window resize.

## How it works

1. `redraw_full()` draws fastfetch directly to the terminal (full native colors).
2. `scan_layout()` runs a second, silent fastfetch — with `--pipe false` so TTY-dependent modules are included — and parses the output to find the row/col of the uptime, CPU/GPU Core, memory, network, battery lines and the 🕒 clock badge. `--pipe false` is critical: without it the piped output omits the Terminal Font line and every row below it is off by one.
3. The update loop samples `/proc/stat`, `/proc/meminfo`, `/proc/net/dev`, `sysfs` (CPU freq, GPU freq, battery) and `sensors` every second, then overwrites values at the detected positions with `\033[row;colH` escapes.
4. On SIGWINCH the loop re-runs `redraw_full()` (clear + home first, to avoid cursor drift).

## Project layout

| Path (in repo) | Purpose |
|---|---|
| `fastfetch_partial.sh` | Main engine (the only file that needs to be executable) |
| `config.jsonc` | Normal-mode config (logo, keys, bar style) |
| `ex.jsonc` | `-ex` mode config |
| `logo.txt` / `logo_ex.txt` | Logo art with the 🕒 badge placeholder line |
| `context.md` | Agent/developer context — all architecture gotchas |
| `legacy/` | Snapshot of the old whole-refresh script + legacy config (history preserved in `legacy/history.bundle`) |

## Customization pointers

- **Keys**: keep all key strings 11 chars wide (e.g. `" ├ Uptime  "`) so values align.
- **Separator**: `"display": { "separator": " ➜  " }` in both configs.
- **Logo padding**: `"logo": { "padding": { "top": 8, "right": 3 } }` shifts values right; the engine measures `value_col` dynamically, so only total width matters.
- **Clock badge**: the logo's last line must contain `🕒 [ --:--:-- ]` — the engine locates the badge from that line. The placeholder is time-invariant; `draw_clock()` stamps the real time right after every redraw.
- **Bars**: 8 chars at 100% (`█` filled, `░` empty). If you add bar-drawing code, guard `seq` with `[ "$n" -gt 0 ]` — GNU `seq 1 0` prints nothing, but `printf '█%.0s'` with zero args still prints one block.
- **Hardware assumptions** (edit `fastfetch_partial.sh` if they differ): Intel GPU freq via `/sys/class/drm/card*/gt/gt0/rps_*_freq_mhz`, CPU freq via `scaling_cur_freq`, battery via `/sys/class/power_supply/BAT*/capacity`.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Values printed under the wrong rows | Terminal narrower than 120 cols → lines wrap → visual rows diverge from logical rows. Resize to 120x35 (wrapper does this). |
| Clock badge missing / not updating | Logo file missing the `🕒` line, or `--pipe false` missing in `scan_layout` (piped output shifts by one row). |
| `0%` bars show one filled block | `seq 1 0` + bare `printf` — add the `[ "$n" -gt 0 ]` guard. |
| Network row stuck at 0 | Interface had no RX traffic when the engine started — it re-detects every tick now, but the displayed value only updates once traffic flows. |
| Garbage after window resize | Older engine needed a full redraw; current one traps SIGWINCH and re-scans automatically. |

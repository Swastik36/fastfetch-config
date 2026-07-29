#!/usr/bin/env bash

# Fastfetch Partial Line Update Engine
# Features:
# 1. Full Fastfetch draw on startup and terminal window resize (SIGWINCH trap)
# 2. Ultra-fast In-Place ANSI Cursor Repositioning for dynamic metrics (0 screen flicker)
# 3. Dynamic metrics updated: Time Badge, Uptime, CPU Usage, GPU Usage, Memory, Battery

config_preset=""
logo_mode="default"

for arg in "$@"; do
    if [ "$arg" = "-ex" ]; then
        config_preset="--config ~/.local/share/fastfetch/presets/ex.jsonc"
        logo_mode="ex"
    fi
done

# Signal handler for window resizing (SIGWINCH)
redraw_full() {
    printf "\033[H\033[J"
    command fastfetch $config_preset "$@"
}

# Trap terminal resize signal (SIGWINCH) to trigger a full clean redraw
trap 'redraw_full' SIGWINCH

# Initial full dashboard draw
redraw_full

# Initialize CPU proc stat baseline
read c u n s i w ir soft st g gn < /proc/stat
t1=$((u+n+s+i+w+ir+soft+st))
i1=$((i+w))

while true; do
    sleep 1

    # 1. Current Time
    now=$(date +'%H:%M:%S')

    # 2. Uptime
    uptime_raw=$(cat /proc/uptime 2>/dev/null | awk '{print $1}')
    up_secs=${uptime_raw%.*}
    if [ -n "$up_secs" ]; then
        up_days=$(( up_secs / 86400 ))
        up_hours=$(( (up_secs % 86400) / 3600 ))
        up_mins=$(( (up_secs % 3600) / 60 ))
        uptime_str=""
        [ "$up_days" -gt 0 ] && uptime_str="${up_days} days, "
        [ "$up_hours" -gt 0 ] && uptime_str="${uptime_str}${up_hours} hours, "
        uptime_str="${uptime_str}${up_mins} mins"
    else
        uptime_str="N/A"
    fi

    # 3. CPU Usage (Calculated over the 1-second sleep interval with ZERO extra delay)
    read c u n s i w ir soft st g gn < /proc/stat
    t2=$((u+n+s+i+w+ir+soft+st))
    i2=$((i+w))
    td=$((t2 - t1))
    id=$((i2 - i1))
    t1=$t2; i1=$i2
    if [ "$td" -gt 0 ]; then
        cpu_usage=$(( (td - id) * 100 / td ))
    else
        cpu_usage=0
    fi
    cpu_freq_raw=$(sort -nr /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null | head -n1 || echo 1200000)
    cpu_ghz=$(awk -v f="$cpu_freq_raw" 'BEGIN {printf "%.2f", f/1000000}')
    cpu_filled=$(( cpu_usage * 8 / 100 ))
    cpu_empty=$(( 8 - cpu_filled ))
    cpu_bar=$(printf '█%.0s' $(seq 1 $cpu_filled 2>/dev/null))
    cpu_ebar=$(printf '░%.0s' $(seq 1 $cpu_empty 2>/dev/null))

    # 4. GPU Usage
    gpu_act=$(cat /sys/class/drm/card*/gt/gt0/rps_act_freq_mhz 2>/dev/null | head -n1 || echo 0)
    gpu_max=$(cat /sys/class/drm/card*/gt/gt0/rps_max_freq_mhz 2>/dev/null | head -n1 || echo 1300)
    [ -z "$gpu_act" ] && gpu_act=0
    [ -z "$gpu_max" ] || [ "$gpu_max" -eq 0 ] && gpu_max=1300
    gpu_usage=$(( gpu_act * 100 / gpu_max ))
    gpu_ghz=$(awk -v f="$gpu_act" 'BEGIN {printf "%.2f", f/1000}')
    gpu_filled=$(( gpu_usage * 8 / 100 ))
    gpu_empty=$(( 8 - gpu_filled ))
    gpu_bar=$(printf '█%.0s' $(seq 1 $gpu_filled 2>/dev/null))
    gpu_ebar=$(printf '░%.0s' $(seq 1 $gpu_empty 2>/dev/null))

    # 5. Memory Usage
    mem_total_kb=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
    mem_avail_kb=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
    if [ -n "$mem_total_kb" ] && [ -n "$mem_avail_kb" ]; then
        mem_used_kb=$(( mem_total_kb - mem_avail_kb ))
        mem_pct=$(( mem_used_kb * 100 / mem_total_kb ))
        mem_used_gb=$(awk -v u="$mem_used_kb" 'BEGIN {printf "%.2f", u/1048576}')
        mem_total_gb=$(awk -v t="$mem_total_kb" 'BEGIN {printf "%.2f", t/1048576}')
    else
        mem_pct=0; mem_used_gb="0.00"; mem_total_gb="0.00"
    fi
    mem_filled=$(( mem_pct * 8 / 100 ))
    mem_empty=$(( 8 - mem_filled ))
    mem_bar=$(printf '█%.0s' $(seq 1 $mem_filled 2>/dev/null))
    mem_ebar=$(printf '░%.0s' $(seq 1 $mem_empty 2>/dev/null))

    # 6. Battery Status
    bat_cap=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null || echo 0)
    bat_ac=$(cat /sys/class/power_supply/A*/online 2>/dev/null || cat /sys/class/power_supply/ADP*/online 2>/dev/null)
    bat_filled=$(( bat_cap * 8 / 100 ))
    bat_empty=$(( 8 - bat_filled ))
    bat_bar=$(printf '█%.0s' $(seq 1 $bat_filled 2>/dev/null))
    bat_ebar=$(printf '░%.0s' $(seq 1 $bat_empty 2>/dev/null))
    if [ "$bat_ac" = "1" ]; then
        bat_str="\033[32m[ ${bat_bar}${bat_ebar} ] (${bat_cap}%) [AC]\033[0m"
    else
        bat_str="\033[38;5;208m[ ${bat_bar}${bat_ebar} ] (${bat_cap}%) [DC!]\033[0m"
    fi

    # Batch ANSI Cursor Update: Position cursor directly to dynamic cell coordinates
    # Time Badge
    if [ "$logo_mode" = "ex" ]; then
        printf "\033[15;19H\033[1;35m🕒 [ %s ]\033[0m" "$now"
    else
        printf "\033[15;17H\033[1;36m🕒 [ %s ]\033[0m" "$now"
    fi

    # Uptime
    printf "\033[5;67H\033[33m%s\033[0m\033[K" "$uptime_str"

    # CPU Core
    printf "\033[15;67H\033[94m[ %s%s ] %d%% @%sGHz\033[0m\033[K" "$cpu_bar" "$cpu_ebar" "$cpu_usage" "$cpu_ghz"

    # GPU Core
    printf "\033[17;67H\033[95m[ %s%s ] %d%% @%sGHz\033[0m\033[K" "$gpu_bar" "$gpu_ebar" "$gpu_usage" "$gpu_ghz"

    # Memory
    printf "\033[18;67H\033[96m[ %s%s ] %s GiB / %s GiB (%d%%)\033[0m\033[K" "$mem_bar" "$mem_ebar" "$mem_used_gb" "$mem_total_gb" "$mem_pct"

    # Battery
    printf "\033[20;67H%b\033[K" "$bat_str"

    # Hide cursor at row 21, col 1
    printf "\033[21;1H"
done

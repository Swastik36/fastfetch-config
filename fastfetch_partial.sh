#!/usr/bin/env bash

# Fastfetch Partial Line Update Engine
# Features:
# 1. Full Fastfetch draw on startup and terminal window resize (SIGWINCH trap)
# 2. Ultra-fast In-Place ANSI Cursor Repositioning for dynamic metrics (0 screen flicker)
# 3. Dynamic metrics updated: Time Badge, Uptime, CPU Usage, GPU Usage, Memory, Battery
# 4. Dynamic row/column detection - automatically adapts to any terminal height/font/config
# 5. CPU + Memory history sparklines (16-sample, gradient colored, auto-fit width)

config_preset="--config $HOME/.config/fastfetch-partial/config.jsonc"
logo_mode="default"
extra_args=()

tput civis 2>/dev/null
trap 'tput cnorm 2>/dev/null; clear; exit 0' INT TERM EXIT

for arg in "$@"; do
    if [ "$arg" = "-ex" ] || [ "$arg" = "--ex" ]; then
        config_preset="--config $HOME/.config/fastfetch-partial/ex.jsonc"
        logo_mode="ex"
    else
        extra_args+=("$arg")
    fi
done

uptime_row=""; cpu_core_row=""; gpu_core_row=""; mem_row=""; bat_row=""; net_row=""
clock_row=""; clock_col=17; total_rows=19
value_col=68
esc=$(printf '\x1b')
tick_delay=1
spark_chars=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
cpu_hist=()
mem_hist=()
spark_col=105
spark_len=16

# Draw fastfetch directly to terminal (full native colors), then scan a
# silent second run to discover the exact row/column of every dynamic field.
scan_layout() {
    uptime_row=""; cpu_core_row=""; gpu_core_row=""; mem_row=""; bat_row=""; net_row=""
    clock_row=""; clock_col=17; total_rows=19
    value_col=68

    # Silent capture for row scanning only (not displayed)
    mapfile -t lines < <(command fastfetch $config_preset --pipe false "${extra_args[@]}" 2>/dev/null)

    local sep=" ➜  "
    local col_detected=false

    for i in "${!lines[@]}"; do
        local line="${lines[$i]}"
        local clean
        clean=$(printf "%s" "$line" | sed "s/${esc}\[[0-9;]*[a-zA-Z]//g")

        if [[ "$clean" == *"├ Uptime"* ]]; then
            uptime_row=$((i + 1))
        fi
        if [[ "$clean" == *"│ └ Core"* ]]; then
            if [ -z "$cpu_core_row" ]; then
                cpu_core_row=$((i + 1))
            elif [ -z "$gpu_core_row" ]; then
                gpu_core_row=$((i + 1))
            fi
        fi
        if [[ "$clean" == *"├ Memory"* ]]; then
            mem_row=$((i + 1))
        fi
        if [[ "$clean" == *"└ Battery"* ]]; then
            bat_row=$((i + 1))
        fi
        if [[ "$clean" == *"🕒"* ]]; then
            clock_row=$((i + 1))
            local before_clock="${clean%%🕒*}"
            clock_col=$(( ${#before_clock} + 1 ))
        fi

        if [[ "$clean" == *"├ Network"* ]]; then
            net_row=$((i + 1))
        fi

        if ! $col_detected; then
            if [[ "$clean" == *"├ Uptime"* ]] || [[ "$clean" == *"│ └ Core"* ]] || [[ "$clean" == *"├ Memory"* ]] || [[ "$clean" == *"└ Battery"* ]] || [[ "$clean" == *"├ Network"* ]]; then
                local prefix="${clean%%${sep}*}"
                if [ "$prefix" != "$clean" ]; then
                    value_col=$(( ${#prefix} + ${#sep} + 1 ))
                    col_detected=true
                fi
            fi
        fi
    done
    total_rows=${#lines[@]}
}

draw_clock() {
    local t="$1"
    [ -z "$clock_row" ] && return
    if [ "$logo_mode" = "ex" ]; then
        printf "\033[%d;%dH\033[1;35m🕒 [ %s ]\033[0m" "$clock_row" "$clock_col" "$t"
    else
        printf "\033[%d;%dH\033[1;36m🕒 [ %s ]\033[0m" "$clock_row" "$clock_col" "$t"
    fi
}

redraw_full() {
    printf "\033[H\033[J"
    # Draw directly to the terminal — preserves ALL native fastfetch colors
    # (keyColor, outputColor, bar colors, command ANSI output)
    command fastfetch $config_preset "${extra_args[@]}" 2>/dev/null
    # Then scan a second run to discover row positions
    scan_layout
    # Re-detect active network interface
    net_iface=$(awk 'NR>2 {if ($1 != "lo:" && $2+0 > 0) {gsub(":", "", $1); print $1; exit}}' /proc/net/dev)
    if [ -n "$net_iface" ]; then
        net_rx1=$(awk -v n="$net_iface" '$1 == n ":" {print $2}' /proc/net/dev)
        net_tx1=$(awk -v n="$net_iface" '$1 == n ":" {print $10}' /proc/net/dev)
    fi
    draw_clock "$(date +'%H:%M:%S')"
    tick_delay=0.2
    cols=$(stty size < /dev/tty 2>/dev/null | awk '{print $2}')
    [ -z "$cols" ] && cols=120
    spark_col=$(( value_col + 37 ))
    spark_len=16
    avail=$(( cols - spark_col + 1 ))
    if [ "$avail" -lt "$spark_len" ]; then
        spark_len=$avail
    fi
}

trap 'redraw_full' SIGWINCH

redraw_full

read c u n s i w ir soft st g gn < /proc/stat
t1=$((u+n+s+i+w+ir+soft+st))
i1=$((i+w))

net_iface=$(awk 'NR>2 {if ($1 != "lo:" && $2+0 > 0) {gsub(":", "", $1); print $1; exit}}' /proc/net/dev)
if [ -n "$net_iface" ]; then
    net_rx1=$(awk -v n="$net_iface" '$1 == n ":" {print $2}' /proc/net/dev)
    net_tx1=$(awk -v n="$net_iface" '$1 == n ":" {print $10}' /proc/net/dev)
fi

while true; do
    sleep "$tick_delay"
    tick_delay=1

    now=$(date +'%H:%M:%S')

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
    cl=$(( (cpu_usage * 8 + 50) / 100 ))
    [ "$cl" -gt 7 ] && cl=7
    cpu_hist+=("$cl")
    [ "${#cpu_hist[@]}" -gt 16 ] && cpu_hist=("${cpu_hist[@]:1}")
    cpu_filled=$(( cpu_usage * 8 / 100 ))
    cpu_empty=$(( 8 - cpu_filled ))
    cpu_bar=$([ "$cpu_filled" -gt 0 ] && printf '█%.0s' $(seq 1 $cpu_filled 2>/dev/null) || echo "")
    cpu_ebar=$([ "$cpu_empty" -gt 0 ] && printf '░%.0s' $(seq 1 $cpu_empty 2>/dev/null) || echo "")

    temp=$(sensors 2>/dev/null | grep 'Package id 0' | head -1 | sed 's/[^+]*+//; s/°C.*//; s/\..*//')
    if [ -z "$temp" ]; then
        for z in /sys/class/thermal/thermal_zone*/temp; do
            t=$(cat "$z" 2>/dev/null)
            if [ -n "$t" ] && [ "$t" -gt 10000 ]; then
                temp=$(( t / 1000 ))
                break
            fi
        done
    fi
    [ -z "$temp" ] && temp=0

    if [ "$temp" -le 50 ]; then
        temp_color="34"
    elif [ "$temp" -le 70 ]; then
        temp_color="32"
    elif [ "$temp" -le 80 ]; then
        temp_color="93"
    elif [ "$temp" -le 90 ]; then
        temp_color="38;5;208"
    else
        temp_color="91"
    fi

    gpu_act=$(cat /sys/class/drm/card*/gt/gt0/rps_act_freq_mhz 2>/dev/null | head -n1 || echo 0)
    gpu_max=$(cat /sys/class/drm/card*/gt/gt0/rps_max_freq_mhz 2>/dev/null | head -n1 || echo 1300)
    [ -z "$gpu_act" ] && gpu_act=0
    [ -z "$gpu_max" ] || [ "$gpu_max" -eq 0 ] && gpu_max=1300
    gpu_usage=$(( gpu_act * 100 / gpu_max ))
    gpu_ghz=$(awk -v f="$gpu_act" 'BEGIN {printf "%.2f", f/1000}')
    gpu_filled=$(( gpu_usage * 8 / 100 ))
    gpu_empty=$(( 8 - gpu_filled ))
    gpu_bar=$([ "$gpu_filled" -gt 0 ] && printf '█%.0s' $(seq 1 $gpu_filled 2>/dev/null) || echo "")
    gpu_ebar=$([ "$gpu_empty" -gt 0 ] && printf '░%.0s' $(seq 1 $gpu_empty 2>/dev/null) || echo "")

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
    ml=$(( (mem_pct * 8 + 50) / 100 ))
    [ "$ml" -gt 7 ] && ml=7
    mem_hist+=("$ml")
    [ "${#mem_hist[@]}" -gt 16 ] && mem_hist=("${mem_hist[@]:1}")
    # Build gradient-colored bar matching fastfetch native output:
    # green (≤50%), yellow (51-75%), red (>75%) for filled; white for empty
    mem_bar=""
    for ((b=1; b<=mem_filled; b++)); do
        seg_pct=$(( b * 100 / 8 ))
        if [ "$seg_pct" -le 50 ]; then
            mem_bar="${mem_bar}\033[32m█"
        elif [ "$seg_pct" -le 75 ]; then
            mem_bar="${mem_bar}\033[93m█"
        else
            mem_bar="${mem_bar}\033[91m█"
        fi
    done
    for ((b=1; b<=mem_empty; b++)); do
        mem_bar="${mem_bar}\033[97m░"
    done

    bat_cap=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null || echo 0)
    bat_ac=$(cat /sys/class/power_supply/A*/online /sys/class/power_supply/ADP*/online 2>/dev/null | grep -m1 .)
    bat_filled=$(( bat_cap * 8 / 100 ))
    bat_empty=$(( 8 - bat_filled ))
    bat_bar=$([ "$bat_filled" -gt 0 ] && printf '█%.0s' $(seq 1 $bat_filled 2>/dev/null) || echo "")
    bat_ebar=$([ "$bat_empty" -gt 0 ] && printf '░%.0s' $(seq 1 $bat_empty 2>/dev/null) || echo "")
    power_plan=$(powerprofilesctl get 2>/dev/null || echo "balanced")
    case "$power_plan" in
        performance) plan_tag="Performance" ;;
        power-saver) plan_tag="Power Saver" ;;
        balanced)    plan_tag="Balanced" ;;
        *)           plan_tag="$power_plan" ;;
    esac
    if [ "$bat_ac" = "1" ]; then
        bat_str="\033[32m[ ${bat_bar}${bat_ebar} ] (${bat_cap}%) [AC] [${plan_tag}]\033[0m"
    else
        bat_str="\033[38;5;208m[ ${bat_bar}${bat_ebar} ] (${bat_cap}%) [DC!] [${plan_tag}]\033[0m"
    fi

    # Re-detect network interface
    new_iface=$(awk 'NR>2 {if ($1 != "lo:" && $2+0 > 0) {gsub(":", "", $1); print $1; exit}}' /proc/net/dev)
    if [ "$new_iface" != "$net_iface" ]; then
        net_iface=$new_iface
        if [ -n "$net_iface" ]; then
            net_rx1=$(awk -v n="$net_iface" '$1 == n ":" {print $2}' /proc/net/dev)
            net_tx1=$(awk -v n="$net_iface" '$1 == n ":" {print $10}' /proc/net/dev)
        fi
    fi

    # Network speed
    if [ -n "$net_iface" ]; then
        net_rx2=$(awk -v n="$net_iface" '$1 == n ":" {print $2}' /proc/net/dev)
        net_tx2=$(awk -v n="$net_iface" '$1 == n ":" {print $10}' /proc/net/dev)
        net_rx_speed=$(( net_rx2 - net_rx1 ))
        net_tx_speed=$(( net_tx2 - net_tx1 ))
        net_rx1=$net_rx2
        net_tx1=$net_tx2

        if [ "$net_rx_speed" -ge 1000000 ]; then
            net_rx_str=$(awk "BEGIN {printf \"%.1f MB/s\", $net_rx_speed/1000000}")
        elif [ "$net_rx_speed" -ge 1000 ]; then
            net_rx_str=$(awk "BEGIN {printf \"%.0f KB/s\", $net_rx_speed/1000}")
        else
            net_rx_str="${net_rx_speed} B/s"
        fi

        if [ "$net_tx_speed" -ge 1000000 ]; then
            net_tx_str=$(awk "BEGIN {printf \"%.1f MB/s\", $net_tx_speed/1000000}")
        elif [ "$net_tx_speed" -ge 1000 ]; then
            net_tx_str=$(awk "BEGIN {printf \"%.0f KB/s\", $net_tx_speed/1000}")
        else
            net_tx_str="${net_tx_speed} B/s"
        fi
    fi

    # Time Badge (dynamically detected row + column)
    draw_clock "$now"

    # Uptime - default color (no yellow), dynamic row + column
    [ -n "$uptime_row" ] && printf "\033[%d;%dH\033[0m%s\033[0m\033[K" "$uptime_row" "$value_col" "$uptime_str"

    # CPU Core
    [ -n "$cpu_core_row" ] && [ "$temp" -gt 0 ] && printf "\033[%d;%dH\033[94m[ %s%s ] %d%% @%sGHz \033[%sm%s°C\033[0m\033[K" "$cpu_core_row" "$value_col" "$cpu_bar" "$cpu_ebar" "$cpu_usage" "$cpu_ghz" "$temp_color" "$temp"
    [ -n "$cpu_core_row" ] && [ "$temp" -eq 0 ] && printf "\033[%d;%dH\033[94m[ %s%s ] %d%% @%sGHz\033[0m\033[K" "$cpu_core_row" "$value_col" "$cpu_bar" "$cpu_ebar" "$cpu_usage" "$cpu_ghz"

    # CPU history sparkline (gradient green/yellow/red by level)
    if [ "$spark_len" -gt 0 ] && [ "${#cpu_hist[@]}" -gt 0 ]; then
        printf "\033[%d;%dH" "$cpu_core_row" "$spark_col"
        off=$(( ${#cpu_hist[@]} - spark_len ))
        [ "$off" -lt 0 ] && off=0
        for lv in "${cpu_hist[@]:$off}"; do
            if [ "$lv" -le 4 ]; then sc="32"; elif [ "$lv" -le 6 ]; then sc="93"; else sc="91"; fi
            printf "\033[%sm%s\033[0m" "$sc" "${spark_chars[$lv]}"
        done
    fi

    # GPU Core
    [ -n "$gpu_core_row" ] && printf "\033[%d;%dH\033[95m[ %s%s ] %d%% @%sGHz\033[0m\033[K" "$gpu_core_row" "$value_col" "$gpu_bar" "$gpu_ebar" "$gpu_usage" "$gpu_ghz"

    # Memory — gradient bar + bold bright cyan text (matches fastfetch native)
    [ -n "$mem_row" ] && printf "\033[%d;%dH\033[1;36m\033[97m[ %b\033[97m ]\033[m\033[1;36m %s GiB / %s GiB (%d%%)\033[0m\033[K" "$mem_row" "$value_col" "$mem_bar" "$mem_used_gb" "$mem_total_gb" "$mem_pct"

    # Memory history sparkline (gradient green/yellow/red by level)
    if [ "$spark_len" -gt 0 ] && [ "${#mem_hist[@]}" -gt 0 ]; then
        printf "\033[%d;%dH" "$mem_row" "$spark_col"
        off=$(( ${#mem_hist[@]} - spark_len ))
        [ "$off" -lt 0 ] && off=0
        for lv in "${mem_hist[@]:$off}"; do
            if [ "$lv" -le 4 ]; then sc="32"; elif [ "$lv" -le 6 ]; then sc="93"; else sc="91"; fi
            printf "\033[%sm%s\033[0m" "$sc" "${spark_chars[$lv]}"
        done
    fi

    # Battery
    [ -n "$bat_row" ] && printf "\033[%d;%dH%b\033[K" "$bat_row" "$value_col" "$bat_str"

    # Network
    [ -n "$net_row" ] && [ -n "$net_iface" ] && printf "\033[%d;%dH\033[93m%s ↓ %s ↑\033[0m\033[K" "$net_row" "$value_col" "$net_rx_str" "$net_tx_str"

    printf "\033[$((total_rows + 1));1H"
done

#!/usr/bin/env bash

# Fastfetch Whole Refresh (Full Redraw) Engine
# Features:
# 1. Re-runs full fastfetch binary every 1 second
# 2. Python-generated logo with live clock badge baked into logo.txt
# 3. Top-anchored cursor (\033[H]) for zero-flicker redraw in Kitty
# 4. Supports -ex / --ex for alternate SWAZI logo

tput civis 2>/dev/null
trap 'tput cnorm 2>/dev/null; clear; exit 0' INT TERM EXIT

config_flag=""
if [ "$1" = "-ex" ] || [ "$1" = "--ex" ]; then
    config_flag="-c ex"
    shift
fi

# Create static logos once if they don't exist
if [ ! -f ~/.config/fastfetch/logo.txt ]; then
    cat << 'EOF' > ~/.config/fastfetch/logo.txt
          __   _____                           _ 
        _/_/  / ___/ _      __  ____ _ ____   (_)
      _/_/    \__ \ | | /| / / / __ `//_  /  / / 
 _  _/_/     ___/ / | |/ |/ / / /_/ /  / /_ / /  
(_)/_/      /____/  |__/|__/  \__,_/  /___//_/   
EOF
fi

if [ ! -f ~/.config/fastfetch/logo_ex.txt ]; then
    cat << 'EOF' > ~/.config/fastfetch/logo_ex.txt
 ______     __     __     ______     ______     __    
/\  ___\   /\ \   _ \ \   /\  __ \   /\___  \   /\ \   
\ \___  \  \ \ \/ ".\ \  \ \  __ \  \/_/  /__  \ \ \  
 \/\_____\  \ \__/".~\_\  \ \_\ \_\   /\_____\  \ \_\ 
  \/_____/   \/_/   \/_/   \/_/\/_/   \/_____/   \/_/ 
EOF
fi

clear
while true; do
    python3 -c '
cyan, mag, bg, rst = "\033[1;36m", "\033[1;35m", "\033[38;2;24;24;37m", "\033[0m"
inv = f"{bg}|                        {rst}"
badge = f"{cyan}                🕒 [ --:--:-- ]{rst}"
logo = rf"""{cyan}          __   _____                           _ {rst}
{cyan}        _/_/  / ___/ _      __  ____ _ ____   (_){rst}
{cyan}      _/_/    \__ \ | | /| / / / __ `//_  /  / / {rst}
{cyan} _  _/_/     ___/ / | |/ |/ / / /_/ /  / /_ / /  {rst}
{cyan}(_)/_/      /____/  |__/|__/  \__,_/  /___//_/{rst}
{inv}
{badge}"""
with open("/home/swastik/.config/fastfetch/logo.txt", "w") as f:
    f.write(logo)

badge_ex = f"{mag}                  🕒 [ --:--:-- ]{rst}"
logo_ex = rf"""{mag} ______     __     __     ______     ______     __    {rst}
{mag}/\  ___\   /\ \   _ \ \   /\  __ \   /\___  \   /\ \   {rst}
{mag}\ \___  \  \ \ \/ ".\ \  \ \  __ \  \/_/  /__  \ \ \  {rst}
{mag} \/\_____\  \ \__/".~\_\  \ \_\ \_\   /\_____\  \ \_\{rst}
{mag}  \/_____/   \/_/   \/_/   \/_/\/_/   \/_____/   \/_/ {rst}
{inv}
{badge_ex}"""
with open("/home/swastik/.config/fastfetch/logo_ex.txt", "w") as f:
    f.write(logo_ex)
'

    # Reposition cursor to top-left (no top padding loop) to prevent screen flicker
    printf "\033[H"
    command fastfetch $config_flag "$@"

    sleep 1
done

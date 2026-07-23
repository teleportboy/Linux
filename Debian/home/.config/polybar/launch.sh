#!/usr/bin/zsh
killall -q polybar
echo "---" | tee -a /tmp/polybar.log
polybar default 2>&1 | tee -a /tmp/polybar.log & disown
echo "Bar launched..."

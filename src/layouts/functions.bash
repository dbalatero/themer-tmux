circled_digit() {
    circled_digits='⓪①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳'
    if [ $1 -lt 20 ] 2>/dev/null ; then
        echo ${circled_digits:$1:1}
    else
        echo $1
    fi
}

maximize_pane() {
    tmux -q -L swap-pane-test -f /dev/null new-session -d \; new-window \; new-window \; swap-pane -t :1 \; kill-session || { tmux display 'your tmux version has a buggy swap-pane command - see ticket #108, fixed in upstream commit 78e783e'; exit; }
    __current_pane=$(tmux display -p '#{pane_id}')

    __dead_panes=$(tmux list-panes -s -F '#{pane_dead} #{pane_id} #{pane_start_command}' | grep -o '^1 %.\+maximized.\+$' || true)
    __restore=$(echo "${__dead_panes}" | sed -n -E -e "s/^1 ${__current_pane} .+maximized.+(%[0-9]+)$/tmux swap-pane -s \1 -t ${__current_pane} \; kill-pane -t ${__current_pane}/p" -e "s/^1 (%[0-9]+) .+maximized.+${__current_pane}$/tmux swap-pane -s \1 -t ${__current_pane} \; kill-pane -t \1/p" )

    if [ x"${__restore}" = x ] ; then
        [ x"$(tmux list-panes | wc -l | sed 's/^ *//g')" = x1 ] && tmux display "Can't maximize with only one pane" && return
        __window=$(tmux new-window -P "exec maximized& tmux setw remain-on-exit on; clear; tmux clear-history; printf 'Pane has been maximized, press <prefix>+ to restore. %s' \\${__current_pane};")
        __window=${__window%.*}

        __guard=50
        while ( [ x"$(tmux list-panes -t ${__window} -F '#{session_name}:#{window_index} #{pane_dead}')" != x"${__window} "1 ] && [ x"${__guard}" != x0 ] ) ; do sleep 0.01 ; __guard=$((__guard - 1)); done
        if [ x"${__guard}" = 0 ] ; then
        exit 1
        fi

        __new_pane=$(tmux display -p '#{pane_id}')
        tmux setw remain-on-exit off \; swap-pane -s "${__current_pane}" -t "${__new_pane}"
    else
        ${__restore} || tmux kill-pane
    fi
}

battery() {
    battery_symbol=$1
    battery_symbol_count=$2
    battery_palette=$3
    battery_status=$4
    if [ x"$battery_symbol_count" = x"auto" ]; then
        columns=$(tmux -q display -p '#{client_width}' 2> /dev/null || echo 80)
        if [ $columns -ge 80 ]; then
        battery_symbol_count=10
        else
        battery_symbol_count=5
        fi
    fi
    battery_symbol_heart_full=♥
    battery_symbol_heart_empty=♥
    battery_symbol_block_full=◼
    battery_symbol_block_empty=◻
    eval battery_symbol_full='$battery_symbol_'"$battery_symbol"'_full'
    eval battery_symbol_empty='$battery_symbol_'"$battery_symbol"'_empty'

    uname_s=$(uname -s)
    if [ x"$uname_s" = x"Darwin" ]; then
        batt=$(pmset -g batt)
        percentage=$(echo $batt |egrep -o [0-9]+%) || return
        discharging=$(echo $batt | grep -qi "discharging" && echo "true" || echo "false")
        charge="${percentage%%%} / 100"
    elif [ x"$uname_s" = x"Linux" ]; then
        batpath=/sys/class/power_supply/BAT0
        if [ ! -d $batpath ]; then
        batpath=/sys/class/power_supply/BAT1
        fi
        batfull=$batpath/energy_full
        batnow=$batpath/energy_now
        if [ ! -r $batfull -o ! -r $batnow ]; then
        return
        fi
        discharging=$(grep -qi "discharging" $batpath/status && echo "true" || echo "false")
        charge="$(cat $batnow) / $(cat $batfull)" || return
    fi

    if [ x"$battery_status"  = x"1" -o x"$battery_status" = x"true" ]; then
        if [ x"$discharging" = x"true" ]; then
        printf "%s " 🔋
        else
        printf "%s " ⚡
        fi
    fi

    if echo $battery_palette | grep -q -E '^(colour[0-9]{1,3},?){3}$'; then
        battery_full_fg=$(echo $battery_palette | cut -d, -f1)
        battery_empty_fg=$(echo $battery_palette | cut -d, -f2)
        battery_bg=$(echo $battery_palette | cut -d, -f3)

        full=$(printf %.0f $(echo "$charge * $battery_symbol_count" | bc -l))
        [ $full -gt 0 ] && \
        printf '#[fg=%s,bg=%s]' $battery_full_fg $battery_bg && \
        printf "%0.s$battery_symbol_full" $(seq 1 $full)
        empty=$(($battery_symbol_count - $full))
        [ $empty -gt 0 ] && \
        printf '#[fg=%s,bg=%s]' $battery_empty_fg $battery_bg && \
        printf "%0.s$battery_symbol_empty" $(seq 1 $empty)
    elif echo $battery_palette | grep -q -E '^heat(,colour[0-9]{1,3})?$'; then
        battery_bg=$(echo $battery_palette | cut -s -d, -f2)
        battery_bg=${battery_bg:-colour16}
        heat="233 234 235 237 239 241 243 245 247 144 143 142 184 214 208 202 196"
        heat_count=$(echo $(echo $heat | wc -w))

        eval set -- "$heat"
        heat=$(eval echo $(eval echo $(printf "\\$\{\$(expr %s \* $heat_count / $battery_symbol_count)\} " $(seq 1 $battery_symbol_count))))

        full=$(printf %.0f $(echo "$charge * $battery_symbol_count" | bc -l))
        printf '#[bg=%s]' $battery_bg
        [ $full -gt 0 ] && \
        printf "#[fg=colour%s]$battery_symbol_full" $(echo $heat | cut -d' ' -f1-$full)
        empty=$(($battery_symbol_count - $full))
        if [ x"$battery_symbol" = x"heart" ]; then
        [ $empty -gt 0 ] && \
            printf '#[fg=%s]' $battery_bg && \
            printf "%0.s$battery_symbol_empty" $(seq 1 $empty)
        else
        [ $empty -gt 0 ] && \
            printf "#[fg=colour%s]$battery_symbol_empty" $(echo $heat | cut -d' ' -f$((full+1))-$(($full + $empty)))
        fi
    fi
}

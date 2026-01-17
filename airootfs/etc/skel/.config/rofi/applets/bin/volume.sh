#!/usr/bin/env bash

## Author  : Aditya Shakya (adi1090x)
## Github  : @adi1090x
#
## Applets : Volume

# Import Current Theme
source "$HOME"/.config/rofi/applets/shared/theme.bash
theme="$type/$style"

# Volume Info
mixer="`amixer info Master | grep 'Mixer name' | cut -d':' -f2 | tr -d \',' '`"
speaker="`amixer get Master | tail -n1 | awk -F ' ' '{print $5}' | tr -d '[]'`"
mic="`amixer get Capture | tail -n1 | awk -F ' ' '{print $5}' | tr -d '[]'`"

active=""
urgent=""

# Speaker Info
amixer get Master | grep '\[on\]' &>/dev/null
if [[ "$?" == 0 ]]; then
	active="-a 1"
	stext='Unmute'
	sicon=''
else
	urgent="-u 1"
	stext='Mute'
	sicon=''
fi

# Microphone Info
amixer get Capture | grep '\[on\]' &>/dev/null
if [[ "$?" == 0 ]]; then
    [ -n "$active" ] && active+=",3" || active="-a 3"
	mtext='Unmute'
	micon=''
else
    [ -n "$urgent" ] && urgent+=",3" || urgent="-u 3"
	mtext='Mute'
	micon=''
fi

# Theme Elements
prompt="S:$stext, M:$mtext"
mesg="$mixer - Speaker: $speaker, Mic: $mic"

if [[ "$theme" == *'type-1'* ]]; then
	list_col='1'
	list_row='6'
	win_width='400px'
elif [[ "$theme" == *'type-3'* ]]; then
	list_col='1'
	list_row='5'
	win_width='120px'
elif [[ "$theme" == *'type-5'* ]]; then
	list_col='1'
	list_row='5'
	win_width='520px'
elif [[ ( "$theme" == *'type-2'* ) || ( "$theme" == *'type-4'* ) ]]; then
	list_col='5'
	list_row='1'
	win_width='670px'
fi

# Options
layout=`cat ${theme} | grep 'USE_ICON' | cut -d'=' -f2`
if [[ "$layout" == 'NO' ]]; then
	option_1=" Increase"
	option_2="$sicon $stext"
	option_3=" Decrese"
	option_4="$micon $mtext"
	option_5=" Settings"
	option_6=" Per-App Control"
else
	option_1=""
	option_2="$sicon"
	option_3=""
	option_4="$micon"
	option_5=""
	option_6=" Per-App Control"
fi

# Rofi CMD
rofi_cmd() {
	rofi -theme-str "window {width: $win_width;}" \
		-theme-str "listview {columns: $list_col; lines: $list_row;}" \
		-theme-str 'textbox-prompt-colon {str: "";}' \
		-dmenu  \
		-p "$prompt" \
		-mesg "$mesg" \
		${active} ${urgent} \
		-markup-rows \
		-theme ${theme}
}

# Pass variables to rofi dmenu
run_rofi() {
	echo -e "$option_1\n$option_2\n$option_3\n$option_4\n$option_5\n$option_6" | rofi_cmd
}

# Execute Command
run_cmd() {
	if [[ "$1" == '--opt1' ]]; then
		amixer -Mq set Master,0 5%+ unmute
	elif [[ "$1" == '--opt2' ]]; then
		amixer set Master toggle
	elif [[ "$1" == '--opt3' ]]; then
		amixer -Mq set Master,0 5%- unmute
	elif [[ "$1" == '--opt4' ]]; then
		amixer set Capture toggle
	elif [[ "$1" == '--opt5' ]]; then
		select_output_rofi
	elif [[ "$1" == '--opt6' ]]; then
		per_app_control
	fi
}

# Device selector via Rofi
select_output_rofi() {
    choices=$(pactl list sinks | grep -ie "Description:" | awk -F ': ' '{print $2}' | sort)
    selected=$(echo "$choices" | rofi -dmenu -theme "$theme" -p "Select Output")

    if [ -n "$selected" ]; then
        device=$(pactl list sinks | grep -C2 -F "Description: $selected" | grep 'Name:' | head -n1 | awk -F ': ' '{print $2}' | xargs)
        if [ -n "$device" ]; then
            pactl set-default-sink "$device"

            # Optionally move current playing streams to the new sink
            for input in $(pactl list short sink-inputs | awk '{print $1}'); do
                pactl move-sink-input "$input" "$device"
            done
        fi
    fi
}

per_app_control() {
    # Get a list of sink-inputs
    apps=()
    while IFS= read -r line; do
        index=$(echo "$line" | grep -Po 'Sink Input #\K\d+')
        app_name=$(pactl list sink-inputs | awk "/Sink Input #$index/,/application.name/" | grep 'application.name' | cut -d\" -f2)
        volume=$(pactl list sink-inputs | awk "/Sink Input #$index/,/Volume:/" | grep 'Volume:' | head -n1 | awk '{print $5}' | tr -d '%')
        mute=$(pactl list sink-inputs | awk "/Sink Input #$index/,/Mute:/" | grep 'Mute:' | awk '{print $2}')
        
        icon=""
        vol_disp="$volume%"
        status="[${mute^^}]"
        
        apps+=("$index:$icon $app_name ($vol_disp) $status")
    done < <(pactl list sink-inputs | grep 'Sink Input #' | sort)

    # Show menu if there are apps
    if [ ${#apps[@]} -eq 0 ]; then
        notify-send "No active audio streams."
        return
    fi

    selected=$(printf '%s\n' "${apps[@]}" | rofi -dmenu -theme "$theme" -p "App Volume")

    index=$(echo "$selected" | cut -d':' -f1)

if [ -n "$index" ]; then
    action=$(printf '%s\n' \
        "🔊 Increase" \
        "🔉 Decrease" \
        "🔇 Toggle Mute" \
        "🔀 Move to Device" | rofi -dmenu -theme "$theme" -p "$selected - Action")

    case "$action" in
        "🔊 Increase")
            pactl set-sink-input-volume "$index" +5%
            ;;
        "🔉 Decrease")
            pactl set-sink-input-volume "$index" -5%
            ;;
        "🔇 Toggle Mute")
            pactl set-sink-input-mute "$index" toggle
            ;;
        "🔀 Move to Device")
    		choices=$(pactl list sinks | grep -ie "Description:" | awk -F ': ' '{print $2}' | sort)
    		selected=$(echo "$choices" | rofi -dmenu -theme "$theme" -p "Select Output")
			if [ -n "$selected" ]; then
				device=$(pactl list sinks | grep -C2 -F "Description: $selected" | grep 'Name:' | head -n1 | awk -F ': ' '{print $2}' | xargs)
				pactl move-sink-input "$index" "$device"
			fi
            ;;
    esac
fi


}

# Actions
chosen="$(run_rofi)"
case ${chosen} in
    $option_1)
		run_cmd --opt1
        ;;
    $option_2)
		run_cmd --opt2
        ;;
    $option_3)
		run_cmd --opt3
        ;;
    $option_4)
		run_cmd --opt4
        ;;
    $option_5)
		run_cmd --opt5
        ;;
	$option_6)
		run_cmd --opt6
		;;
esac


#!/bin/sh

notify() {
    [[ -t 0 ]] && echo $1 || xmessage -timeout 5 $1
}

die() {
    notify "$1"; exit 1
}

[[ -n $(pgrep ffmpeg) ]] && die "ffmpeg is already running!"

RECDIR=$HOME/video/new
LOGDIR=$HOME/log
MIC="hw:1,0"
MICCHANNELS=1
FPS=30
QUALITY=10

INFO=$(xwininfo)
WIN_GEO=$(echo $INFO | grep -oEe 'geometry [0-9]+x[0-9]+' | grep -oEe '[0-9]+x[0-9]+')
WIN_XY=$(echo $INFO | grep -oEe 'Corners:\s+\+[0-9]+\+[0-9]+' | grep -oEe '[0-9]+\+[0-9]+' | sed -e 's/\+/,/' )
WIN_PID=$(xprop -id `echo $INFO | grep "Window id" | cut -d " " -f 4` | grep PID | cut -d "=" -f 2 | cut -d " " -f 2)

start_recording() {
    if [[ -n $(jack_lsp | grep $WIN_PID) ]]
    then
        ffmpeg \
            -f alsa -ac $MICCHANNELS -i $MIC \
            -f jack -i ffmpeg \
            -f x11grab -r $FPS -s $WIN_GEO -i :0.0+$WIN_XY \
            -vcodec libx264 -preset ultrafast -crf $QUALITY -y -map 0 -map 1 -map 2 $RECDIR/rec.mkv &> $LOGDIR/ffmpeg.log &
    else
        ffmpeg \
            -f alsa -ac $MICCHANNELS -i $MIC \
            -f x11grab -r $FPS -s $WIN_GEO -i :0.0+$WIN_XY \
            -vcodec libx264 -preset ultrafast -crf $QUALITY -y $RECDIR/rec.mkv &> $LOGDIR/ffmpeg.log &
    fi
}

connect_audio() {
    if [[ -n $(jack_lsp | grep $WIN_PID) ]]
    then
        jack_connect alsa-jack.jackP.$WIN_PID.0:out_000 ffmpeg:input_1
        jack_connect alsa-jack.jackP.$WIN_PID.0:out_001 ffmpeg:input_2
    fi
}

finish() {
    if [[ -t 0 ]]
    then
        read -p "now recording (press enter to stop)"
        pkill -15 ffmpeg
        exit 0
    else
        xmessage -buttons stop:0 "recording in progress"
        pkill -15 ffmpeg
        exit 0
    fi
}

start_recording; sleep 2s; connect_audio; finish

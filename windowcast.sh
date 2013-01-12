#!/bin/sh

notify() {
    [[ -t 0 ]] && echo -e $1 || xmessage -timeout 5 $1
}

die() {
    notify "$1"; exit 1
}

[[ -z $PIDFILE ]] && PIDFILE="/var/run/$(basename $0)-ffmpeg.pid"
[[ -e $PIDFILE ]] && die "$(basename $0) was closed improperly.\nPlease verify that ffmpeg is not currently recording, then remove $PIDFILE."

[[ -z $RECDIR ]] && RECDIR=$HOME/video/new
[[ -z $LOGDIR ]] && LOGDIR=$HOME/log
#[[ -z $MICPORT ]] && MICPORT="hw:1,0"
[[ -z $MICCHANNELS ]] && MICCHANNELS=2
[[ -z $FPS ]] && FPS=30
[[ -z $QUALITY ]] && QUALITY=10

INFO=$(xwininfo)
WIN_GEO=$(echo $INFO | grep -oEe 'geometry [0-9]+x[0-9]+' | grep -oEe '[0-9]+x[0-9]+')
WIN_XY=$(echo $INFO | grep -oEe 'Corners:\s+\+[0-9]+\+[0-9]+' | grep -oEe '[0-9]+\+[0-9]+' | sed -e 's/\+/,/')
JACK=$(pgrep jackd)

if [[ -z $WIN_PID ]] && [[ -n $JACK ]]
then
    WIN_ID=$(echo $INFO | grep -oEe 'Window id: 0x[0-f]*' | grep -oEe '0x[0-f]*')
    WIN_PID=$(xprop -id $WIN_ID | grep -oEe 'PID\(CARDINAL\) = [0-9]*' | grep -oEe '[0-9]*') || die "FATAL ERROR: application does not set _NET_WM_PID.\nPlease manually set WIN_PID and try again."
fi

JACK=$(jack_lsp | grep $WIN_PID)

FFMPEG="ffmpeg"
[[ -n $MICPORT ]] && FFMPEG="$FFMPEG -f alsa -ac $MICCHANNELS -i $MICPORT"
[[ -n $JACK ]] && FFMPEG="$FFMPEG -f jack -i ffmpeg"
FFMPEG="$FFMPEG -f x11grab -r $FPS -s $WIN_GEO -i :0.0+$WIN_XY -vcodec libx264 -preset ultrafast -crf $QUALITY -y"
if [[ -n $MICPORT ]] && [[ -n $JACK ]]
then
    FFMPEG="$FFMPEG -map 0 -map 1 -map 2"
fi
FFMPEG="$FFMPEG $RECDIR/rec.mkv &> $LOGDIR/ffmpeg.log &"

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
        kill -2 $(echo $PIDFILE)
        rm -f $PIDFILE
        exit 0
    else
        xmessage -buttons stop:0 "recording in progress"
        kill -2 $(echo $PIDFILE)
        rm -f $PIDFILE
        exit 0
    fi
}

eval $FFMPEG
echo $! > $PIDFILE

if [[ -n $JACK ]]
then
    sleep 2; connect_audio; finish
else
    finish
fi

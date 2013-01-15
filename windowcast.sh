#!/bin/bash

die() {
    echo -e "$1"; exit 1
}

[[ -n $PIDFILE ]] || PIDFILE="$HOME/run/$(basename $0)-ffmpeg.pid"
[[ -n $LOGDIR ]] || LOGDIR="$HOME/log"
[[ -n $RECDIR ]] || RECDIR="$HOME/video/new"

start_recording() {
    [[ -n $FPS ]] || FPS=30
    [[ -n $QUALITY ]] || QUALITY=10
    [[ -n $(pgrep jackd) ]] || MUTE=1
    [[ -n $MICCHANNELS ]] || MICCHANNELS=2
    echo "Select the window to record with your mouse."
    INFO=$(xwininfo)
    WIN_WIDTH="$(echo $INFO | grep -oEe 'Width: [0-9]*' | grep -oEe '[0-9]*')"
    [[ $(expr $WIN_WIDTH % 2) -eq 0 ]] || WIN_WIDTH=$(expr $WIN_WIDTH + 1)
    WIN_HEIGHT="$(echo $INFO | grep -oEe 'Height: [0-9]*' | grep -oEe '[0-9]*')"
    [[ $(expr $WIN_HEIGHT % 2) -eq 0 ]] || WIN_HEIGHT=$(expr $WIN_HEIGHT + 1)
    WIN_GEO="$WIN_WIDTH""x""$WIN_HEIGHT"
    WIN_XY=$(echo $INFO | grep -oEe 'Corners:\s+\+[0-9]+\+[0-9]+' | grep -oEe '[0-9]+\+[0-9]+' | sed -e 's/\+/,/')
    if [[ -z $MUTE ]] && [[ -z $WIN_PID ]]
    then
        WIN_ID=$(echo $INFO | grep -oEe 'Window id: 0x[0-f]*' | grep -oEe '0x[0-f]*')
        WIN_PID=$(xprop -id $WIN_ID | grep -oEe 'PID\(CARDINAL\) = [0-9]*' | grep -oEe '[0-9]*') || die "FATAL ERROR: application does not set _NET_WM_PID.\nPlease bug its developer, manually set WIN_PID and try again."
        [[ $(jack_lsp | grep "$WIN_PID") ]] || MUTE=1
    fi
    FFMPEG="ffmpeg"
    [[ -n $MICSOURCE ]] && FFMPEG="$FFMPEG -f alsa -ac $MICCHANNELS -i $MICSOURCE"
    [[ -z $MUTE ]] && FFMPEG="$FFMPEG -f jack -i ffmpeg"
    FFMPEG="$FFMPEG -f x11grab -r $FPS -s $WIN_GEO -i :0.0+$WIN_XY -vcodec libx264 -preset ultrafast -crf $QUALITY -y"
    if [[ -n $MICSOURCE ]] && [[ -z $MUTE ]]
    then
        FFMPEG="$FFMPEG -map 0 -map 1 -map 2"
    fi
    FFMPEG="$FFMPEG $RECDIR/rec.mkv &> $LOGDIR/ffmpeg.log &"

    [[ -z $DEBUG ]] || echo $FFMPEG
    eval $FFMPEG
    echo "$!" > $PIDFILE

    if [[ -z $MUTE ]]
    then
        until [[ -n $(jack_lsp | grep 'ffmpeg') ]]
        do
            sleep 1
        done
        jack_connect alsa-jack.jackP.$WIN_PID.0:out_000 ffmpeg:input_1
        jack_connect alsa-jack.jackP.$WIN_PID.0:out_001 ffmpeg:input_2
    fi

    echo "Now recording."
    exit 0
}

stop_recording() {
    kill -2 $(cat $PIDFILE)
    rm -f $PIDFILE
    echo "Recording stopped."
    post_process || echo "Post-processing is not required."
    exit 0
}

check_recording() {
    [[ -e $PIDFILE ]] || die "Recording not in progress."
    [[ -n $(echo $(pgrep ffmpeg) | grep $(cat $PIDFILE)) ]] || die "Recording has crashed or otherwise failed. Log follows:\n\n`cat $LOGDIR/ffmpeg.log`"
    echo "Recording is in progress."
    exit 0
}

post_process() {
    [[ $(ffprobe -i $RECDIR/rec.mkv -show_streams -loglevel quiet | grep -c index) -eq 3 ]] || return 1
    ffmpeg -f lavfi -i "amovie=$RECDIR/rec.mkv:si=1,volume=-8dB" -y $RECDIR/audio.flac &>> $LOGDIR/ffmpeg.log
    ffmpeg -i $RECDIR/rec.mkv -map 0:0 -y $RECDIR/mic.flac &>> $LOGDIR/ffmpeg.log
    sox -m $RECDIR/mic.flac $RECDIR/audio.flac $RECDIR/mixedaudio.flac
    ffmpeg -i $RECDIR/mixedaudio.flac -i $RECDIR/rec.mkv -map 0 -map 1:2 -acodec copy -vcodec copy -y $RECDIR/processed.mkv &>> $LOGDIR/ffmpeg.log
    rm -f $RECDIR/{mic,audio,mixedaudio}.flac
    echo "Post-processing complete."
}

usage() {
    echo "Usage: [VARIABLES...] $(basename $0) MODE [OPTIONS...]"
    echo "Record audio and video from an application window.

MODE can be one of:
  start     Begins a new recording.
  stop      Stop recording.
  status    Check if you are (still) recording.

The following OPTIONS can be set when MODE is \"start\":
  -c, --channels N      Specify the number of audio channels output
                          by your microphone. (Default: 2)
  -f, --fps N             Specify the fps of the video. (Default: 30)
  -m, --mute            Don't try to record audio.
  -q, --quality N       Specify the video quality. (Default: 10)
  -v, --voice SOURCE    Record from microphone SOURCE.

The following VARIABLES are available:
  RECDIR    Where to save the recording. (Default: ~/video/new)
  LOGDIR    Where to save the output produced by ffmpeg. (Default: ~/log)
  PIDFILE   Where to save the PID of the ffmpeg process once recording has
              begun. (Default: ~/run/$(basename $0)-ffmpeg.pid)
  WIN_PID   The PID of the application you want to record. This is normally set
              automatically; you will be informed if you need to set this."
    exit 1
}

case "$1" in
    start   )
        [[ ! -e $PIDFILE ]] || die "You're already recording!"
        shift
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -c | --channels )
                    shift
                    [[ $1 -gt 0 ]] && MICCHANNELS=$1 || die "Please select at least one audio channel for your microphone."
                    ;;
                -f | --fps      )
                    shift
                    [[ $1 -gt 0 ]] && FPS=$1 || die "Please set fps to at least 1."
                    ;;
                -m | --mute     )
                    MUTE=1
                    ;;
                -q | --quality  )
                    shift
                    [[ $1 -gt 0 ]] && QUALITY=$1 || die "Please set quality to at least 1."
                    ;;
                -v | --voice    )
                    shift
                    MICSOURCE="$1"
                    ;;
                *               )
                    usage;;
            esac
        shift
        done
        start_recording;;
    stop    )
        [[ -e $PIDFILE ]] || die "You are not recording."
        stop_recording;;
    status  )
        check_recording;;
    *       )
        usage;;
esac

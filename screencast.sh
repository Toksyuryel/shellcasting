#!/bin/bash

if [[ -t 0 ]]
then
    die() {
        echo -e "$1"; exit 1
    }
else
    die() {
        echo -e "$1" | osd_cat -p bottom -A right -f -*-fixed-*-*-*-*-*-200-*-*-*-*-*-* -c white -O 2 -u black -d 15; exit 1
    }
fi

[[ -n $PIDPREFIX ]] || PIDPREFIX="$HOME/run/$(basename $0)"
[[ -n $LOGDIR ]] || LOGDIR="$HOME/log"
[[ -n $RECDIR ]] || RECDIR="$HOME/video/new"

start_recording() {
    [[ -n $FPS ]] || FPS=30
    [[ -n $QUALITY ]] || QUALITY=23
    [[ -n $(pgrep jackd) ]] || MUTE=1
    [[ -n $MICCHANNELS ]] || MICCHANNELS=2
    GEO=$(xdpyinfo -display :0.0 | grep -oEe 'dimensions:\s+[0-9]+x[0-9]+' | grep -oEe '[0-9]+x[0-9]+')
    FFMPEG="ffmpeg"
    [[ -n $MICSOURCE ]] && FFMPEG="$FFMPEG -f alsa -ac $MICCHANNELS -i $MICSOURCE"
    FFMPEG="$FFMPEG -f x11grab -r $FPS -s $GEO -i :0.0 -vcodec libx264 -preset ultrafast -crf $QUALITY -y $RECDIR/rec.mkv &> $LOGDIR/ffmpeg.log &"

    [[ -z $DEBUG ]] || echo $FFMPEG
    eval $FFMPEG
    echo "$!" > $PIDPREFIX-ffmpeg.pid

    if [[ -z $MUTE ]]
    then
        jack_capture --daemon $RECDIR/audio.wav &
        echo "$!" > $PIDPREFIX-jack_capture.pid
    fi

    if [[ -t 0 ]]
    then
        echo "Now recording."
    else
        echo "● REC" | osd_cat -p top -o 48 -A left -f -*-fixed-*-*-*-*-*-200-*-*-*-*-*-* -c red -O 4 -u black -d 10; echo "● REC" | osd_cat -p top -o 48 -A left -f -*-fixed-*-*-*-*-*-100-*-*-*-*-*-* -c red -O 2 -u black -d 3
    fi
    exit 0
}

stop_recording() {
    kill -2 $(cat $PIDPREFIX-ffmpeg.pid) && rm -f $PIDPREFIX-ffmpeg.pid
    if [[ -e $PIDPREFIX-jack_capture.pid ]]
    then
        kill -2 $(cat $PIDPREFIX-jack_capture.pid) && rm -f $PIDPREFIX-jack_capture.pid
    fi
    if [[ -t 0 ]]
    then
        echo "Recording stopped."
    else
        echo "■ STOP" | osd_cat -p top -o 48 -A left -f -*-fixed-*-*-*-*-*-200-*-*-*-*-*-* -c green -O 4 -u black -d 10; echo "■ STOP" | osd_cat -p top -o 48 -A left -f -*-fixed-*-*-*-*-*-100-*-*-*-*-*-* -c green -O 2 -u black -d 3
    fi
    post_process || echo "Post-processing is not required."
    exit 0
}

check_recording() {
    [[ -e $PIDPREFIX-ffmpeg.pid ]] || die "Recording not in progress."
    [[ -n $(echo $(pgrep ffmpeg) | grep $(cat $PIDPREFIX-ffmpeg.pid)) ]] || die "Recording has crashed or otherwise failed.\nLog at $LOGDIR/ffmpeg.log"
    echo "Recording is in progress."
    exit 0
}

post_process() {
    [[ -e $RECDIR/audio.wav ]] || return 1
    ffmpeg -f lavfi -i "amovie=$RECDIR/audio.wav,volume=-8dB" -y $RECDIR/audio.flac &>> $LOGDIR/ffmpeg.log
    if [[ $(ffprobe -i $RECDIR/rec.mkv -show_streams -loglevel quiet | grep -c index) -eq 2 ]]
    then
        ffmpeg -i $RECDIR/rec.mkv -map 0:1 -y $RECDIR/mic.flac &>> $LOGDIR/ffmpeg.log
        if [[ $(ffprobe -i $RECDIR/mic.flac -show_streams -loglevel quiet | grep channels | grep -oEe '[0-9]') -eq 1 ]]
        then
            sox -M $RECDIR/mic.flac $RECDIR/mic.flac $RECDIR/stereomic.flac || die "Failed to transform mic audio from mono to stereo."
            mv $RECDIR/stereomic.flac $RECDIR/mic.flac
        fi
        sox --norm -m $RECDIR/mic.flac $RECDIR/audio.flac $RECDIR/mixedaudio.flac || die "Failed to mix mic audio with system audio."
        ffmpeg -i $RECDIR/mixedaudio.flac -i $RECDIR/rec.mkv -map 0 -map 1:2 -acodec copy -vcodec copy -y $RECDIR/processed.mkv &>> $LOGDIR/ffmpeg.log
        rm -f $RECDIR/{mic,audio,mixedaudio}.flac
    else
        ffmpeg -i $RECDIR/audio.flac -i $RECDIR/rec.mkv -map 0 -map 1 -acodec copy -vcodec copy -y $RECDIR/processed.mkv &>> $LOGDIR/ffmpeg.log
        rm -f $RECDIR/audio.flac
    fi
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
  -q, --quality N       Specify the video quality. (Default: 23)
                          Lower values = higher quality.
  -v, --voice SOURCE    Record from microphone SOURCE.

The following VARIABLES are available:
  RECDIR    Where to save the recording. (Default: ~/video/new)
  LOGDIR    Where to save the output produced by ffmpeg. (Default: ~/log)
  PIDPREFIX   Where to save the PID of each process once recording has
              begun. (Default: ~/run/$(basename $0))"
    exit 1
}

case "$1" in
    start   )
        [[ ! -e $PIDPREFIX-ffmpeg.pid ]] || die "You're already recording!"
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
        [[ -e $PIDPREFIX-ffmpeg.pid ]] || die "You are not recording."
        stop_recording;;
    status  )
        check_recording;;
    *       )
        usage;;
esac

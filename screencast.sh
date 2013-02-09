#!/bin/bash

if [[ ! $(which realpath) ]]
then
    alias realpath="readlink -f"
fi
PATH=$PATH:$(dirname $(realpath $0))
source common.sh || exit 1
[[ -n $DISPLAY ]] || die "And just what do you think you're trying to do?"
depend jackd ffmpeg jack_capture sox xwininfo xdpyinfo osd_cat
config

VIDEOPID="${PIDPREFIX}-ffmpeg-video.pid"
AUDIOPID="${PIDPREFIX}-jack_capture.pid"
VOICEPID="${PIDPREFIX}-ffmpeg-voice.pid"
VIDEOLOG="${LOGDIR}/ffmpeg-video.log"
VOICELOG="${LOGDIR}/ffmpeg-voice.log"
AUDIOLOG="${LOGDIR}/ffmpeg-audio.log"
POSTLOG="${LOGDIR}/ffmpeg-post.log"
RECDIR="${RECDIR:-${HOME}/video/new}"
RECDIR="$(fixpath $RECDIR)"
[[ -d "$RECDIR" ]] || RECDIR="$PWD"
VIDEOFILE="${RECDIR}/video.mkv"
VOICEFILE="${RECDIR}/voice.wav"
AUDIOFILE="${RECDIR}/audio.wav"
POSTFILE="${RECDIR}/processed"

clean_recdir() {
    rm -f ${RECDIR}/{video,video-transcode}.mkv
    rm -f ${RECDIR}/{voice,voice-fixed,audio,audio-quiet,audio-mixed}.wav
    rm -f ${RECDIR}/audio-transcode.mka
}

start_recording() {
    clean_recdir
    FPS=${FPS:-30}
    QUALITY=${QUALITY:-23}
    MICCHANNELS=${MICCHANNELS:-2}

    if [[ -z $WINDOW ]]
    then
        GEO=$(xdpyinfo -display $DISPLAY | grep -oEe 'dimensions:\s+[0-9]+x[0-9]+' | grep -oEe '[0-9]+x[0-9]+')
        VIDEOOPTS=(-f x11grab -r $FPS -s $GEO -i "$DISPLAY")
    else
        INFO=$(xwininfo)
        WIN_WIDTH="$(echo "$INFO" | grep -oEe 'Width: [0-9]*' | grep -oEe '[0-9]*')"
        [[ $(( $WIN_WIDTH % 2 )) -eq 0 ]] || WIN_WIDTH=$(( $WIN_WIDTH + 1 ))
        WIN_HEIGHT="$(echo "$INFO" | grep -oEe 'Height: [0-9]*' | grep -oEe '[0-9]*')"
        [[ $(( $WIN_HEIGHT % 2 )) -eq 0 ]] || WIN_HEIGHT=$(( $WIN_HEIGHT + 1 ))
        GEO="${WIN_WIDTH}x${WIN_HEIGHT}"
        OFFSET="$(echo $INFO | grep -oEe 'Corners:\s+\+[0-9]+\+[0-9]+' | grep -oEe '[0-9]+\+[0-9]+' | sed -e 's/\+/,/')"
        VIDEOOPTS=(-f x11grab -show_region 1 -r $FPS -s "$GEO" -i "${DISPLAY}+${OFFSET}")
    fi

    VIDEOOPTS+=(-vcodec libx264 -preset ultrafast -crf $QUALITY -y)

    ffmpeg "${VIDEOOPTS[@]}" "$VIDEOFILE" > "$VIDEOLOG" 2>&1 &
    echo "$!" > "$VIDEOPID"

    if [[ -n $MICSOURCE ]]
    then
        VOICEOPTS=(-f alsa -ac $MICCHANNELS -i "$MICSOURCE")
        VOICEOPTS+=(-y)
        ffmpeg "${VOICEOPTS[@]}" "$VOICEFILE" > "$VOICELOG" 2>&1 &
        echo "$!" > "$VOICEPID"
    fi

    [[ -n $(pgrep jackd) ]] || MUTE=1
    if [[ -z $MUTE ]]
    then
        jack_capture --daemon "$AUDIOFILE" &
        echo "$!" > "$AUDIOPID"
    fi

    if [[ -t 0 ]]
    then
        echo "Recording now in progress."
    else
        osd top 48 left 200 red 4 black 10 "● REC"; osd top 48 left 100 red 2 black 3 "● REC"
    fi
}

check_recording() {
    if [[ -e $VIDEOPID ]]
    then
        if [[ -n $(echo $(pgrep ffmpeg) | grep -f "$VIDEOPID") ]]
        then
            echo "Video is recording"
            VIDEOCHECK=0
        else
            echo "Video recording has crashed"
        fi
    else
        echo "You are not recording"
    fi

    if [[ -e $VOICEPID ]]
    then
        if [[ -n $(echo $(pgrep ffmpeg) | grep -f "$VOICEPID") ]]
        then
            echo "Voice is recording"
            VOICECHECK=0
        else
            echo "Voice recording has crashed"
        fi
    fi

    if [[ -e $AUDIOPID ]]
    then
        if [[ -n $(echo $(pgrep jack_capture) | grep -f "$AUDIOPID") ]]
        then
            echo "Audio is recording"
            AUDIOCHECK=0
        else
            echo "Audio recording has crashed"
        fi
    fi
}

stop_recording() {
    check_recording > /dev/null
    if [[ -z $VIDEOCHECK ]] && [[ -z $VOICECHEK ]] && [[ -z $AUDIOCHECK ]]
    then
        die "You aren't recording anything."
    fi
    if [[ -n $VIDEOCHECK ]]
    then
        kill -2 $(cat "$VIDEOPID") && rm -f "$VIDEOPID"
    elif [[ -e $VIDEOPID ]]
    then
        rm -f "$VIDEOPID"
    fi
    if [[ -n $VOICECHECK ]]
    then
        kill -2 $(cat "$VOICEPID") && rm -f "$VOICEPID"
    elif [[ -e $VOICEPID ]]
    then
        rm -f $VOICEPID
    fi
    if [[ -n $AUDIOCHECK ]]
    then
        kill -2 $(cat "$AUDIOPID") && rm -f "$AUDIOPID"
    elif [[ -e $AUDIOPID ]]
    then
        rm -f "$AUDIOPID"
    fi
    if [[ -t 0 ]]
    then
        echo "Recording stopped."
    else
        osd top 48 left 200 green 4 black 10 "■ STOP"; osd top 48 left 100 green 2 black 3 "■ STOP"
    fi
    if [[ -n $POST ]]
    then
        post_process
    fi
    exit 0
}

post_process() {
    ACODEC=${ACODEC:-'libmp3lame'}
    BITRATE=${BITRATE:-128000}
    CONTAINER=${CONTAINER:-'mp4'}
    VCODEC=${VCODEC:-'libx264'}

    [[ -e $VIDEOFILE ]] || die "You haven't recorded anything."

    notify "Processing..."

    if [[ -e $VOICEFILE ]] && [[ $(ffprobe -i $VOICEFILE -show_streams -loglevel quiet | grep 'channels' | grep -oEe '[0-9]') -eq 1 ]]
    then
        notify "Converting mono voice data to stereo..."
        sox -M $VOICEFILE $VOICEFILE ${RECDIR}/voice-fixed.wav || die "Internal error: failed to transform voice data from mono to stero."
        VOICEFILE=${RECDIR}/voice-fixed.wav
    fi

    if [[ -e $AUDIOFILE ]] && [[ -n $VOLUME ]]
    then
        notify "Adjusting audio volume..."
        ffmpeg -f lavfi -i "amovie=${AUDIOFILE},volume=$VOLUME" -y ${RECDIR}/audio-quiet.wav > $AUDIOLOG 2>&1
        AUDIOFILE=${RECDIR}/audio-quiet.wav
    fi

    if [[ -e $VOICEFILE ]] && [[ -e $AUDIOFILE ]]
    then
        notify "Mixing voice data with audio data..."
        sox --norm -m $VOICEFILE $AUDIOFILE ${RECDIR}/audio-mixed.wav || die "Internal error: failed to mix voice data with audio data."
        AUDIOFILE=${RECDIR}/audio-mixed.wav
    elif [[ -e $VOICEFILE ]]
    then
        AUDIOFILE=$VOICEFILE
    fi

    notify "Transcoding... (this may take a while)"
    VIDEOOPTS=(-i "$VIDEOFILE" -vcodec "$VCODEC" -y)
    ffmpeg "${VIDEOOPTS[@]}" "${RECDIR}/video-transcode.mkv" > $POSTLOG 2>&1
    VIDEOFILE="${RECDIR}/video-transcode.mkv"
    if [[ -e $AUDIOFILE ]]
    then
        AUDIOOPTS=(-i "$AUDIOFILE" -acodec "$ACODEC" -ab $BITRATE -y)
        ffmpeg "${AUDIOOPTS[@]}" "${RECDIR}/audio-transcode.mka" >> $POSTLOG 2>&1
        AUDIOFILE="${RECDIR}/audio-transcode.mka"
    fi
    TRANSCODEOPTS=(-i "$VIDEOFILE")
    [[ -e $AUDIOFILE ]] && TRANSCODEOPTS+=(-i "$AUDIOFILE")
    TRANSCODEOPTS+=(-vcodec copy)
    [[ -e $AUDIOFILE ]] && TRANSCODEOPTS+=(-acodec copy)
    TRANSCODEOPTS+=(-y)
    ffmpeg "${TRANSCODEOPTS[@]}" "${POSTFILE}.${CONTAINER}" >> $POSTLOG 2>&1
    notify "Done."
    exit 0
}

usage() {
    echo "Usage: $(basename $0) MODE [OPTIONS...]"
    echo "Record audio and video from your system.

MODE can be one of:
  start     Begins a new recording (auto-cleans RECDIR).
  stop      Finish recording.
  status    Check if you are (still) recording.
  post      Do post-processing of a finished recording.
  clean     Delete previous recording data from RECDIR.

The following OPTIONS can be set for any MODE:
  --logdir DIR              Location to store log files. (Setting: LOGDIR)
                              (Default: ~/log if it exists, otherwise
                               the directory you ran the script from)
  --piddir DIR              Location to store pid files. (Setting: PIDDIR)
                              (Default: ~/.run if it exists, otherwise
                               the directory you ran the script from)
  --recdir DIR              Location to store recording data. (Setting: RECDIR)
                              (Default: ~/video/new if it exists, otherwise
                               the directory you ran the script from)
  --settings PATH           Location of settings file. (Default: First try
                               \$XDG_CONFIG_HOME if set, then try ~/.config -
                               if either of these exist, look for
                               $(basename $0).cfg under it. Otherwise, look for
                               ~/.$(basename $0)rc)

WARNING: options specified in the config file will override command line
         options if they appear before --settings. It is recommend that this
         option appear before all others on the command line if you are going
         to specify it.

The following OPTIONS can be set when MODE is \"start\":
  -c, --channels N          Specify number of audio channels output by your
                              microphone. (Default: 2) (Setting: MICCHANNELS)
  -f, --fps N               Specify video framerate. (Default: 30) (Setting: FPS)
  -m, --mute                Don't try to record audio. (Setting: MUTE)
  -q, --quality N           Specify crf value. Lower values raise quality.
                              (Default: 23) (Setting: QUALITY)
  -v, --voice SOURCE        Record from microphone SOURCE. (Setting: MICSOURCE)
  -w, --window              Record from a window instead of the whole screen.
                              (Select with the mouse) (Setting: WINDOW)

The following OPTIONS can be set when MODE is \"stop\":
  -p, --post [OPTIONS...]   Automatically begin post-processing after stopping
                              the recording. Remaining options will be passed
                              along to the \"post\" MODE and are the same as
                              those described below.

The following OPTIONS can be set when MODE is \"post\":
  -a, --acodec CODEC        Specify the audio codec to use.
                              (Default: libmp3lame) (Setting: ACODEC)
  -b, --bitrate N           Specify the audio bitrate.
                              (Default: 128000) (Setting: BITRATE)
  -c, --container CONTAINER Specify the container format to use. Ensure it
                              agrees with your audio and video codecs.
                              (Default: mp4) (Setting: CONTAINER)
  -d, --volume [(+|-)NdB]   Adjust the volume of the system audio prior to
                              mixing by the amount specified (If no amount is
                              specified, defaults to -8dB) (Setting: VOLUME)
  -v, --vcodec CODEC        Specify the video codec to use.
                              (Default: libx264) (Setting: VCODEC)

The format of the settings file is the same as any standard bash script."

    exit 1
}

common_options() {
    [[ $# -eq 2 ]] || usage
    case "$1" in
        *dir      )
            P="$(fixpath $2)"
            [[ -d $P ]] || die "FATAL ERROR: $P does not exist or is not a directory."
            ;;&
        --logdir    )
            LOGDIR="$P"
            ;;
        --piddir    )
            PIDDIR="$P"
            ;;
        --recdir    )
            RECDIR="$P"
            ;;
        --settings  )
            P="$(fixpath $2)"
            [[ -z $DEBUG ]] || echo -e "P=$P\n2=$2"
            if [[ -r $P ]]
            then
                CONFIG="$P"
                config
            else
                die "FATAL ERROR: $P file not found."
            fi
            ;;
        *           )
            usage
            ;;
    esac
}

post_options() {
    case "$1" in
        -a | --acodec       )
            if [[ -n $(ffmpeg -loglevel quiet -codecs | grep 'EA' | grep -Ee '\s'"$2"'\s') ]]
            then
                ACODEC="$2"
            else
                die "FATAL ERROR: Selected audio codec is unsupported by your version of ffmpeg."
            fi
            N=2
            ;;
        -b | --bitrate      )
            if [[ $(( $2 % 1000 )) -eq 0 ]]
            then
                BITRATE=$2
            else
                die "FATAL ERROR: BITRATE must be a multiple of 1000."
            fi
            N=2
            ;;
        -c | --container    )
            if [[ -n $2 ]] && [[ ! "$2" =~ '^-' ]]
            then
                CONTAINER="$2"
            else
                die "FATAL ERROR: You forgot to supply a CONTAINER."
            fi
            N=2
            ;;
        -d | --volume       )
            if [[ -n $2 ]] && [[ "$2" =~ dB$ ]]
            then
                VOLUME="$2"
                N=2
            else
                VOLUME="-8dB"
                N=1
            fi
            ;;
        -v | --vcodec       )
            if [[ -n $(ffmpeg -loglevel quiet -codecs | grep 'EV' | grep -Ee '\s'"$2"'\s') ]]
            then
                VCODEC="$2"
            else
                die "FATAL ERROR: Selected video codec is unsupported by your version of ffmpeg."
            fi
            N=2
            ;;
        *                   )
            common_options "$1" "$2"
            N=2
            ;;
    esac
}

start_options() {
    case "$1" in
        -c | --channels     )
            [[ $2 -gt 0 ]] && MICCHANNELS=$2 || die "FATAL ERROR: MICCHANNELS must be at least 1."
            N=2
            ;;
        -f | --fps          )
            [[ $2 -gt 0 ]] && FPS=$2 || die "FATAL ERROR: FPS must be at least 1."
            N=2
            ;;
        -m | --mute         )
            MUTE=1
            N=1
            ;;
        -q | --quality      )
            [[ $2 -gt 0 ]] && QUALITY=$2 || die "FATAL ERROR: QUALITY must be at least 1."
            N=2
            ;;
        -v | --voice        )
            MICSOURCE="$2"
            N=2
            ;;
        -w | --window       )
            WINDOW=1
            N=1
            ;;
        *                   )
            common_options "$1" "$2"
            N=1
            ;;
    esac
}

MODE="$1"
shift
case "$MODE" in
    start   )
        check_recording > /dev/null
        if [[ -z $VIDEOCHECK ]] && [[ -z $VOICECHECK ]] && [[ -z $AUDIOCHECK ]]
        then
            while [[ $# -gt 0 ]]; do
                start_options "$@"
                shift $N
            done
            start_recording
            check_recording
            exit 0
        else
            die "You are already recording something."
        fi
        ;;
    stop    )
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -p | --post     )
                    shift
                    POST=1
                    while [[ $# -gt 0 ]]; do
                        post_options "$@"
                        shift $N
                    done
                    break
                    ;;
                *               )
                    common_options "$1" "$2"
                    shift
                    ;;
            esac
            shift
        done
        stop_recording
        ;;
    status  )
        while [[ $# -gt 0 ]]; do
            common_options "$1" "$2"
            shift 2
        done
        check_recording
        exit 0
        ;;
    post    )
        check_recording > /dev/null
        if [[ -z $VIDEOCHECK ]] && [[ -z $VOICECHECK ]] && [[ -z $AUDIOCHECK ]]
        then
            while [[ $# -gt 0 ]]; do
                post_options "$@"
                shift $N
            done
            post_process
        else
            die "You are still recording."
        fi
        ;;
    clean   )
        while [[ $# -gt 0 ]]; do
            common_options "$1" "$2"
            shift 2
        done
        clean_recdir
        exit 0
        ;;
    *       )
        usage
        ;;
esac

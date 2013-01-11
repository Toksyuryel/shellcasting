#!/bin/sh

notify() {
    [[ -t 0 ]] && echo $1 || xmessage -timeout 5 $1
}

die() {
    notify "$1"; exit 1
}

ASOUNDRC=$HOME/.asoundrc-JACK
LOGDIR=$HOME/log

jack_on() {
    [[ -n $(pgrep jackd) ]] && die "JACK is already running"
    [[ -e $HOME/.asoundrc ]] && die "~/.asoundrc already exists but JACK is not running"
    [[ -e $ASOUNDRC ]] || die "couldn't find $ASOUNDRC"

    if [[ -e $LOGDIR ]]
    then
        if [[ ! -d $LOGDIR ]]
        then
            die "$LOGDIR exists but is not a directory"
        fi
    else
        mkdir -p $LOGDIR
    fi

    jackd -d alsa &> $LOGDIR/jack.log &
    ln -s $ASOUNDRC $HOME/.asoundrc
}

jack_off() {
    [[ -z $(pgrep jackd) ]] && die "JACK is not running"
    [[ -L $HOME/.asoundrc ]] || die "~/.asoundrc is not a symbolic link"

    pkill -15 jackd
    rm -f $HOME/.asoundrc
}

jack_status() {
    [[ -n $(pgrep jackd) ]] && echo "JACK is running" || echo "JACK is not running"
    exit 0
}

jack_restart() {
    [[ -n $(pgrep jackd) ]] && jack_off
    until [[ -z $(pgrep jackd) ]]
    do
        :
    done
    jack_on
    exit 0
}

usage() {
    echo " Usage: $(basename $0) [ start | stop | status | restart ]

 start       starts the JACK server (synonym: on)
 stop        stops the JACK server (synonym: off)
 status      tells whether the JACK server is running
 restart     stops the JACK server, then starts it again

 ASOUNDRC is the location of your .asoundrc file (default: $ASOUNDRC)
 LOGDIR is the directory the JACK server will log to (default: $LOGDIR) (will be created if it doesn't exist)
 (these settings can be changed by editing this script)"
}

case "$1" in
    "on" | "start"  ) jack_on;;
    "off" | "stop"  ) jack_off;;
    "status"        ) jack_status;;
    "restart"       ) jack_restart;;
    *               ) usage;;
esac

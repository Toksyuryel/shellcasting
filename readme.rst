==========================
 The Shellcasting Project
==========================

A collection of shell scripts with the intent of making screencasting on Linux a
simple and easy process. I'm also kinda learning how to write shell code as I go
here, so pardon the rough edges.

What you will need
------------------

Currently, we depend on the following software packages:

    * `JACK Audio Connection Kit <http://jackaudio.org>`
    * `FFmpeg <http://ffmpeg.org">`
    * `x264 <http://www.videolan.org/developers/x264.html>`
    * `alsa and the alsa-jack plugin <http://alsa-project.org/>`
    * `SoX <http://sox.sourceforge.net/>`
    * `xwininfo and xdpyinfo <http://xorg.freedesktop.org/>`
    * `xosd <http://sourceforge.net/projects/libxosd/>`
    * `jack_capture <http://www.notam02.no/arkiv/src>`

More will probably be added as the project progresses.

screencast.sh
-------------
The primary application, it uses a daemon-like architecture to record audio
and video from your system. You may choose to capture the whole screen or a
specified region. Limited post-processing capabilities are available.

jack.sh
-------

This script allows easy control of the JACK server and alsa-jack plugin,
allowing the user to quickly enable it only when it is needed and disable it
again once it is no longer required. The design is inspired largely by the
design of Gentoo's init scripts.

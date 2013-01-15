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
    * `xwininfo and xprop <http://xorg.freedesktop.org/>`

More will probably be added as the project progresses.

windowcast.sh
-------------

This is the main script, used for recording an application window. The design
allows one to simply bind keys to starting and stopping the recording via the
window manager for quick and easy access.

jack.sh
-------

This script allows easy control of the JACK server and alsa-jack plugin,
allowing the user to quickly enable it only when it is needed and disable it
again once it is no longer required. The design is inspired largely by the
design of Gentoo's init scripts.

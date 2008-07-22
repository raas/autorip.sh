#!/bin/bash
#
# RIP a dvd with multiple subtitles and audio tracks into a single Matroska file
# *** NO WARRANTIES, NO ERROR CHECKING OF ANY KIND, YOU'RE ON YOUR OWN ***
#
# make sure there's enough space in $CWD :)
#
# Andras.Horvath nospam gmailcom 2008
#
# $1 - DVD ISO image name (blah.iso)
# $2 - output name (blah.mkv)
# - edit stuff to get all subtitles/audio tracks etc :)
# - adjust number of threads to #CPUs..
# - run with 'nice', preferably in 'screen' :)

# packages needed:
### sudo apt-get install mplayer mencoder mkvtoolnix gpac x264 lsdvd

# poor man's error checking: see which command dies ;-)
set -x 

# parallel encoding of the video part (use as many as you have real CPU cores)
THREADS=2

# longest track -- this is probably what you want
TRACK=$( lsdvd "$1" | sed -n 's/Longest track: //p' )

# get subtitles
for i in en hu; do
	mencoder dvd://${TRACK} -dvd-device "$1" \
		-nosound -ovc frameno -o /dev/null -slang $i -vobsubout title.$i
done

# get audio tracks
for i in 128; do
	mplayer dvd://${TRACK} -dvd-device "$1" \
		-aid $i -dumpaudio -dumpfile title.${i}.ac3
done

# options from mplayer encoding howto:
#
# fast
#-x264encopts subq=4:bframes=2:bitrate=300:b_pyramid:weight_b:pass=$i:turbo=2:threads=2 \
# 
# good quality
#-x264encopts subq=6:partitions=all:8x8dct:me=umh:frameref=5:bframes=3:b_pyramid:weight_b:bitrate=1500:turbo=1:threads=${THREADS} \

# two-pass video encoding for quality (FIXME: do 3 passes make sense?)
for i in 1 2; do
	mencoder dvd://${TRACK} -dvd-device "$1" \
		-ovc x264 \
		-x264encopts subq=6:partitions=all:8x8dct:me=umh:frameref=5:bframes=3:b_pyramid:weight_b:bitrate=1500:turbo=1:threads=${THREADS} \
		-oac copy \
		-of rawvideo \
		-passlogfile x264_2pass.log \
		-o title.264
done

# pack video into MP4 container
MP4Box -add title.264 title.mp4

# pack everything into a Matroska container
mkvmerge -v -o "$2" title.mp4 *.ac3 *.idx

# EOT

#!/bin/bash
#
# Autorip.sh -- RIP a dvd with multiple subtitles and audio tracks into a single
# Matroska file at a very high quality using H.264 encoding and deinterlacing
#
# See README
#
# Packages needed:
# sudo apt-get install mplayer mencoder mkvtoolnix gpac x264 lsdvd grep sed
#
#
#
# Copyright 2009 Andras Horvath (andras.horvath nospamat gmailcom)
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


function usage() {
	echo "Usage: $0 [options] -d <dvd.iso|dvddevice|directory with dvd tree>"
	echo "Options:"
    echo "  -t trackid      -   rip this chapter (default: rip longest)"
    echo "  -o outfile.mkv  -   place final results in that file (default: <dvdfilename>.mkv)"
    echo "  -a id1,id2,id3  -   audio tracks to rip (default: rip ALL audio tracks), e.g. '0,128,129'"
    echo "                      Specify \"default\" to include the default track only."
    echo "                      Specify \"none\" to include no audio tracks at all."
    echo "  -s lang1,lang2  -   subtitles to rip (default: ALL subtitles), e.g. 'hu,en'. "
    echo "                      Specify \"none\" to include no subtitles at all."
    echo "  -c cpucount     -   use this many CPUs for calculations (default: 'auto' = all of them)"
	echo "Use 'mplayer -v' or 'lsdvd' to determine audio track numbers and subtitle names."
	echo "It is recommended to rip from a DVD image or copy, not directly from a drive"
	echo "(input data is read several times)"
	exit 1
}

echo "Autorip.sh v1.0 Copyright (C) 2009 Andras Horvath"
echo "License GPLv3: GNU GPL version 3 (see COPYING for details)"
echo "This is free software: you are free to change and redistribute it."
echo "There is NO WARRANTY, to the extent permitted by law."
echo

if [ $# -eq 0 ]; then
	usage
fi

# check for programs (must have --help option)
# usage: check_for x y z
# returns error if something does not work/exist/etc
#
function check_for() {
	BAD=0
	echo -n "Checking for "
	for command in $*; do
		echo -n "$command "
		$command --help >/dev/null 2>&1
		rval=$?
		if [ $rval -eq 126 ] || [ $rval -eq 127 ]; then
			echo "-> not found!"
			BAD=1
		else
			echo -n "(OK) "
		fi
	done
	echo
	return $BAD
}

# poor man's error checking: see which command dies ;-)
#set -x 

DVDISO=""
TRACK=""
OUTMKV=""
AUDIOTRACKS=""
SUBTITLES=""

# parallel encoding of the video part (use as many as you have real CPU cores)
THREADS=auto

while getopts "hd:o:a:s:c:t:" OPTION; do
	case $OPTION in
		h)
			usage
			;;
		d)
			DVDISO=${OPTARG}
			;;
		t)
			TRACK=${OPTARG}
			;;
		o)
			OUTMKV=${OPTARG}
			;;
		a)
			AUDIOTRACKS="${OPTARG//,/ }"
			;;
		s)
			SUBTITLES="${OPTARG/,/ }"
			;;
		c)
			THREADS=${OPTARG}
			;;
		*)
			echo "Invalid argument $OPTION"
			;;
	esac
done

if ! [ -e "$DVDISO" ]; then
	echo "DVD data not found at file/device \"$DVDISO\" !"
	exit 1
fi

if [ -z "$OUTMKV" ]; then
	OUTMKV=${DVDISO%.*}.mkv
	echo "Output file not specified, defaulting to $OUTMKV"
fi

# check dependencies
check_for sed grep tr mplayer mencoder MP4Box mkvmerge || exit 1

echo "------------------------------------"

# -----------------------------------------------------------------------

if [ -z "$TRACK" ]; then
	# longest track -- this is probably what you want
	TRACK=$( lsdvd "${DVDISO}" 2>/dev/null | sed -n 's/Longest track: //p' )
	if [ -z "$TRACK" ]; then
		echo "Longest track not found and not specified -- check *.log.."
		exit 1
	else
		echo "Targeting track $TRACK as longest track on the DVD.."
	fi
fi

# prepare for autodetection -- dump information to parse later
# lsdvd is unreliable in this matter :( mplayer does a better job
mplayer -v -nosound -novideo dvd://${TRACK} -dvd-device ${DVDISO} > mplayer_examine.out 2>/dev/null

# autodetect audio tracks if none specified
if [ -z "$AUDIOTRACKS" ]; then
	echo "No audio streams specified, autodetecting."
	AUDIOTRACKS=$( grep -F '==> Found audio stream:' mplayer_examine.out  | sed 's/==> Found audio stream://g' | tr -d '\n')
	if [ -z "$AUDIOTRACKS" ]; then
		echo "*** WARNING WARNING WARNING: No audio tracks detected, is this normal? ***"
	else
		echo "Autodetected audio track IDs: $AUDIOTRACKS"
	fi
fi

# autodetect subtitles if none specified (and "none" is not specified:)
if [ -z "$SUBTITLES" ]; then
	# these go by name, not by ID
	#SUBTITLES=$( grep -F '==> Found subtitle:' mplayer_examine.out  | sed 's/==> Found subtitle://g' | tr -d '\n' )
	SUBTITLES=$( grep -F 'subtitle ( sid ):' mplayer_examine.out | sed 's/.*language://g' | tr -d '\n' )
	echo "No subtitles specified, autodetected the following: ${SUBTITLES}"
fi

echo "************************************************"
echo "THE FOLLOWING TRACK WILL BE RIPPED:"
echo "DVD: $DVDISO track $TRACK"
# show what we're ripping
lsdvd -t $TRACK ${DVDISO} 2>/dev/null
e=$?
if [ $e -ne 0 ]; then
	echo "*** Error accessing track $TRACK - check *.log (exit code $e)"
	exit $e
fi
echo "Audio tracks: $AUDIOTRACKS"
echo "Subtitles: $SUBTITLES"
echo "************************************************"

################################## getting down to actual ripping

# get subtitles, if any
if [ "$SUBTITLES" != "none" ]; then
	for i in $SUBTITLES; do
		date
		echo "Getting subtitle: $i .."
		mencoder dvd://${TRACK} -dvd-device "${DVDISO}" \
			-quiet -nosound -ovc frameno -o /dev/null -slang $i -vobsubout title.$i \
		> mplayer_sub_${i}.log 2>&1 
		e=$?
		if [ $e -ne 0 ]; then
			echo "*** Error getting subtitle $i - check *.log (exit code $e)"
			exit $e
		fi
	done
else
	echo "Skipping all subtitles."
fi


case "$AUDIOTRACKS" in
	none)
		echo "Skipping all audio tracks."
		;;
	default)
		# get default if that was specified
		echo "Getting default audio track ..."
		mplayer dvd://${TRACK} -dvd-device "${DVDISO}" \
			-dumpaudio -dumpfile title.ac3 \
		> mplayer_audio_default.log 2>&1
		e=$?
		if [ $e -ne 0 ]; then
			echo "*** Error getting default audio track - check *.log (exit code $e)"
			exit $e
		fi
		if [ ! -s title.ac3 ]; then
			echo "*** WARNING WARNING WARNING: default audio track is empty -- deleting"
			rm -f title.ac3
		fi
		;;
	*)
		# get all audio tracks...
		for i in $AUDIOTRACKS; do
			date
			echo "Getting audio track $i (of $AUDIOTRACKS)..."
			mplayer dvd://${TRACK} -dvd-device "${DVDISO}" \
				-aid $i -dumpaudio -dumpfile title.${i}.ac3 \
			> mplayer_audio_aid_${i}.log 2>&1
			e=$?
			if [ $e -ne 0 ]; then
				echo "*** Error getting audio track aid $i - check *.log (exit code $e)"
				exit $e
			fi
			if [ ! -s title.${i}.ac3 ]; then
				echo "*** Warning: audio track $i is empty -- deleting"
				rm -f title.${i}.ac3
			fi
		done
		;;
esac

# magic options from mplayer encoding howto:
# http://www.mplayerhq.hu/DOCS/HTML-single/en/MPlayer.html#menc-feat-x264-example-settings

MAGIC_OPTIONS=subq=6:partitions=all:8x8dct:me=umh:frameref=5:bframes=3:b_pyramid:weight_b:bitrate=1500:threads=${THREADS}
OTHER_MENCODER_OPTIONS="
	-quiet
	-ovc x264
	-oac copy
	-of rawvideo
"

date
echo "Starting encoding, pass 1 ..."

# two-pass video encoding for quality (FIXME: do 3 passes make sense?)
mencoder dvd://${TRACK} -dvd-device "${DVDISO}" \
	$OTHER_MENCODER_OPTIONS \
	-x264encopts pass=1:turbo=1:$MAGIC_OPTIONS \
	-passlogfile x264_2pass.log \
	-o /dev/null \
	> mencoder_pass1.log 2>&1

e=$?
if [ $e -ne 0 ]; then
	echo "*** Error running first pass - check *.log (exit code $e)"
	exit $e
fi

date
echo "Encoding, pass 2 ..."

mencoder dvd://${TRACK} -dvd-device "${DVDISO}" \
	$OTHER_MENCODER_OPTIONS \
	-x264encopts pass=2:$MAGIC_OPTIONS \
	-vf filmdint,softskip,harddup \
	-passlogfile x264_2pass.log \
	-o title.264 \
	> mencoder_pass2.log 2>&1

e=$?
if [ $e -ne 0 ]; then
	echo "*** Error running second pass - check *.log (exit code $e)"
	exit $e
fi

date
echo "Preparing video container (MP4Box)..."
# pack video into MP4 container
MP4Box -quiet -add title.264 title.mp4 && rm -f title.264 \
	> mp4box.log 2>&1 

e=$?
if [ $e -ne 0 ]; then
	echo "*** Error running MP4Box - check *.log (exit code $e)"
	exit $e
fi

date
echo "Assembling video and audio files (mkvmerge)..."
# pack everything into a Matroska container
# Magic: let the command run even if there are no audio tracks and/or subtitles
mkvmerge -o "${OUTMKV}" title.mp4 $( ls *.ac3 2>/dev/null ) $( ls *.idx 2>/dev/null) \
	> mkvmerge.log 2>&1

e=$?
if [ $e -ne 0 ]; then
	echo "*** Error running mkvmerge - check *.log (exit code $e)"
	exit $e
fi

# clean up
# at this point we've succeeded
rm -f title*.ac3 title*.idx title*.sub title.mp4 x264_2pass.log

date
echo "Done. $SECONDS seconds have passed. Have a nice day."

# vim: ai
# EOT

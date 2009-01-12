#!/bin/bash
#
# RIP a dvd with multiple subtitles and audio tracks into a single Matroska file
# at a very high quality using H.264 encoding
#
# *** NO WARRANTIES, YOU'RE ON YOUR OWN ***
#
# Make sure there's enough space in $CWD :) as it's used as temp space.
#
# Andras.Horvath nospam gmailcom 2008
#
# - run with 'nice', preferably in 'screen' 

# Packages needed:
### sudo apt-get install mplayer nencoder mkvtoolnix gpac x264 lsdvd

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
	echo "Use 'mplayer -v' or 'lsdvd' to determine audio track numbers etc."
	exit 1
}


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
check_for mplayer mencoder MP4Box mkvmerge || exit 1

echo "------------------------------------"

# -----------------------------------------------------------------------

if [ -z "$TRACK" ]; then
	# longest track -- this is probably what you want
	TRACK=$( lsdvd "${DVDISO}" 2>/dev/null | sed -n 's/Longest track: //p' )
	if [ -z "$TRACK" ]; then
		echo "Longest track not found and not specified -- check screen output.."
		exit 1
	else
		echo "Targeting track $TRACK as longest track on the DVD.."
	fi
fi

# autodetect audio tracks if none specified
if [ -z "$AUDIOTRACKS" ]; then
	echo "No audio streams specified, autodetecting."
	lsdvd -q -a -t $TRACK ${DVDISO} 2>/dev/null | grep Audio:
	AT_HEX=$( lsdvd -q -a -t $TRACK ${DVDISO} -Ox 2>/dev/null | sed -n 's,^ *<streamid>\(0x[0-9a-fA-F]\+\)</streamid>,\1,p' )
	for a in $AT_HEX; do
		AUDIOTRACKS=$( printf "%s %d" "$AUDIOTRACKS" $a )
	done
	if [ -z "$AUDIOTRACKS" ]; then
		echo "*** WARNING WARNING WARNING: No audio tracks detected, is this normal? ***"
	else
		echo "Autodetected audio track IDs: $AUDIOTRACKS"
	fi
fi

# autodetect subtitles if none specified (and "none" is not specified:)
if [ -z "$SUBTITLES" ]; then
#	lsdvd -q -s -t $TRACK ${DVDISO} 2>/dev/null | grep Subtitle:
	SUBTITLES=$( lsdvd -q -s -t $TRACK ${DVDISO} -Ox 2>/dev/null | sed -n 's,^ *<langcode>\([a-zA-Z]\+\)</langcode>,\1,p' | tr '\n' ' ' )
	SUBTITLES="${SUBTITLES:-none}"
	echo "No subtitles specified, autodetected the following: ${SUBTITLES}"
fi

echo "************************************************"
echo "THE FOLLOWING TRACK WILL BE RIPPED:"
echo "DVD: $DVDISO track $TRACK"
# show what we're ripping
lsdvd -t $TRACK ${DVDISO} 2>/dev/null
e=$?
if [ $e -ne 0 ]; then
	echo "*** Error accessing track $TRACK - check screen output (exit code $e)"
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
			echo "*** Error getting subtitle $i - check screen output (exit code $e)"
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
		if [ -z "$AUDIOTRACKS" ]; then
			date
			echo "Getting default audio track ..."
			mplayer dvd://${TRACK} -dvd-device "${DVDISO}" \
				-dumpaudio -dumpfile title.ac3 \
			> mplayer_audio_default.log 2>&1
			e=$?
			if [ $e -ne 0 ]; then
				echo "*** Error getting default audio track - check screen output (exit code $e)"
				exit $e
			fi
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
				echo "*** Error getting audio track aid $i - check screen output (exit code $e)"
				exit $e
			fi
		done
		;;
esac

# options from mplayer encoding howto:
#
# fast
#-x264encopts subq=4:bframes=2:bitrate=300:b_pyramid:weight_b:pass=$i:turbo=2:threads=2 \
# 
# good quality
#-x264encopts subq=6:partitions=all:8x8dct:me=umh:frameref=5:bframes=3:b_pyramid:weight_b:bitrate=1500:turbo=1:threads=${THREADS} \

date
echo "Starting encoding, pass 1 ..."

# two-pass video encoding for quality (FIXME: do 3 passes make sense?)
mencoder dvd://${TRACK} -dvd-device "${DVDISO}" \
	-quiet \
	-ovc x264 \
	-x264encopts pass=1:subq=6:partitions=all:8x8dct:me=umh:frameref=5:bframes=3:b_pyramid:weight_b:bitrate=1500:turbo=1:threads=${THREADS} \
	-oac copy \
	-of rawvideo \
	-passlogfile x264_2pass.log \
	-o /dev/null \
	> mencoder_pass1.log 2>&1

e=$?
if [ $e -ne 0 ]; then
	echo "*** Error running first pass - check screen output (exit code $e)"
	exit $e
fi

date
echo "Encoding, pass 2 ..."

mencoder dvd://${TRACK} -dvd-device "${DVDISO}" \
	-quiet \
	-ovc x264 \
	-x264encopts pass=2:subq=6:partitions=all:8x8dct:me=umh:frameref=5:bframes=3:b_pyramid:weight_b:bitrate=1500:threads=${THREADS} \
	-oac copy \
	-of rawvideo \
	-passlogfile x264_2pass.log \
	-o title.264 \
	> mencoder_pass2.log 2>&1

e=$?
if [ $e -ne 0 ]; then
	echo "*** Error running second pass - check screen output (exit code $e)"
	exit $e
fi

date
echo "Preparing video container (MP4Box)..."
# pack video into MP4 container
MP4Box -quiet -add title.264 title.mp4 && rm -f title.264 \
	> mp4box.log 2>&1 

e=$?
if [ $e -ne 0 ]; then
	echo "*** Error running MP4Box - check screen output (exit code $e)"
	exit $e
fi

date
echo "Assembling video and audio files (mkvmerge)..."
# pack everything into a Matroska container
# Magic: let the command run even if there are no audio tracks and/or subtitles
mkvmerge -v -o "${OUTMKV}" title.mp4 $( ls *.ac3 2>/dev/null ) $( ls *.idx 2>/dev/null) \
	> mkvmerge.log 2>&1

e=$?
if [ $e -ne 0 ]; then
	echo "*** Error running mkvmerge - check screen output (exit code $e)"
	exit $e
fi

# clean up
# at this point we've succeeded
rm -f title*.ac3 title*.idx title*.sub title.mp4 x264_2pass.log

date
echo "Done. $SECONDS seconds have passed. Have a nice day."

# vim: ai
# EOT

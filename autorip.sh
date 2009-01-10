#!/bin/bash
#
# RIP a dvd with multiple subtitles and audio tracks into a single Matroska file
# *** NO WARRANTIES, NO ERROR CHECKING OF ANY KIND, YOU'RE ON YOUR OWN ***
#
# make sure there's enough space in $CWD :)
#
# Andras.Horvath nospam gmailcom 2008
#
# - run with 'nice', preferably in 'screen' :)

# packages needed:
### sudo apt-get install mplayer mencoder mkvtoolnix gpac x264 lsdvd

function usage() {
	echo "Usage: $0 [options] -d <dvd.iso|dvddevice|directory with dvd tree>"
	echo "Options:"
    echo "  -t trackid      -   rip this chapter (default: rip longest)"
    echo "  -o outfile.mkv  -   place final results in that file (default: <dvdfilename>.mkv)"
    echo "  -a id1,id2,id3  -   audio tracks to rip (default: rip the default track only), e.g. '0,128'"
    echo "  -s lang1,lang2  -   subtitles to rip (default: no subtitles), e.g. 'hu,en' "
	echo "Use 'mplayer -v' to determine audio track numbers etc."
	exit 1
}


if [ $# -eq 0 ]; then
	usage
fi

function check_for() {
	BAD=0
	for command in $*; do
		echo -n "Checking for $command ... "
		$command --help >/dev/null 2>&1
		rval=$?
		if [ $rval -eq 126 ] || [ $rval -eq 127 ]; then
			echo "-> not found!"
			BAD=1
		else
			echo "OK"
		fi
	done
	return $BAD
}

# poor man's error checking: see which command dies ;-)
#set -x 

DVDISO=""
TRACK=""
OUTMKV=""
AUDIOTRACKS=""
SUBTITLES=""

while getopts "hd:o:a:s:" OPTION; do
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
		*)
			echo "Invalid argument $OPTION"
			;;
	esac
done

if ! [ -e "$DVDISO" ]; then
	echo "DVD data not found at $DVDISO"
	exit 1
fi

if [ -z "$OUTMKV" ]; then
	OUTMKV=${DVDISO%.*}.mkv
	echo "Output file not specified, defaulting to $OUTMKV"
fi

# check dependencies
check_for mplayer mencoder MP4Box mkvmerge || exit 1

# -----------------------------------------------------------------------

# parallel encoding of the video part (use as many as you have real CPU cores)
#THREADS=2
THREADS=auto

if [ -z "$TRACK" ]; then
	# longest track -- this is probably what you want
	TRACK=$( lsdvd "${DVDISO}" | sed -n 's/Longest track: //p' )
fi

# get subtitles, if any
for i in $SUBTITLES; do
	mencoder dvd://${TRACK} -dvd-device "${DVDISO}" \
		-nosound -ovc frameno -o /dev/null -slang $i -vobsubout title.$i
done

# get audio tracks
for i in $AUDIOTRACKS; do
	echo "Getting audio track $i (of $AUDIOTRACKS)..."
	mplayer dvd://${TRACK} -dvd-device "${DVDISO}" \
		-aid $i -dumpaudio -dumpfile title.${i}.ac3
done
# or get default if none was specified
if [ -z "$AUDIOTRACKS" ]; then
	echo "Getting default audio track ..."
	mplayer dvd://${TRACK} -dvd-device "${DVDISO}" \
		-dumpaudio -dumpfile title.ac3
fi

# options from mplayer encoding howto:
#
# fast
#-x264encopts subq=4:bframes=2:bitrate=300:b_pyramid:weight_b:pass=$i:turbo=2:threads=2 \
# 
# good quality
#-x264encopts subq=6:partitions=all:8x8dct:me=umh:frameref=5:bframes=3:b_pyramid:weight_b:bitrate=1500:turbo=1:threads=${THREADS} \

# two-pass video encoding for quality (FIXME: do 3 passes make sense?)
for i in 1 2; do
	mencoder dvd://${TRACK} -dvd-device "${DVDISO}" \
		-ovc x264 \
		-x264encopts subq=6:partitions=all:8x8dct:me=umh:frameref=5:bframes=3:b_pyramid:weight_b:bitrate=1500:turbo=1:threads=${THREADS} \
		-oac copy \
		-of rawvideo \
		-passlogfile x264_2pass.log \
		-o title.264
done

# pack video into MP4 container
MP4Box -add title.264 title.mp4 && rm -f title.264

# pack everything into a Matroska container
# Magic: let the command run even if there are no audio tracks and/or subtitles
mkvmerge -v -o "${OUTMKV}" title.mp4 $( ls *.ac3 2>/dev/null ) $( ls *.idx 2>/dev/null) && \
	rm -f *.ac3 *.idx *.mp4

# EOT

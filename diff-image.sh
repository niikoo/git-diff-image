#!/bin/bash -x

set -euo pipefail


usage()
{
    echo "Usage: $0 [<options>] <file1> <file2>"
    echo
    echo "Options:"
    echo "  -h         Print this help."
    echo "  -b <color> Use this as the background color; defaults to white."
    echo "  -c <color> Highlight differences with this color; defaults to red."
    echo "  -e         Show Exif differences only; don't compare the image data."
    echo "  -f <fuzz>  Use the specified percentage of fuzz.  Defaults to "
    echo "                 5% for JPEGs, zero otherwise."
    echo "  -n <name>  The name to give the first file."
    echo "  -N <name>  The name to give the second file."
    echo
}


backgroundcolor=
color=
exif_only=false
fuzz=
name1=
name2=
while getopts "hb:c:ef:n:N:" opt
do
    case "$opt" in
    h)
        usage
        exit 0
        ;;
    b)
        backgroundcolor="$OPTARG"
        ;;
    c)
        color="$OPTARG"
        ;;
    e)
        exif_only=true
        ;;
    f)
        fuzz="$OPTARG"
        ;;
    n)
        name1="$OPTARG"
        ;;
    N)
        name2="$OPTARG"
        ;;
    esac
done
shift $(( OPTIND - 1 ))


if [ -z "${1-}" ] || [ -z "${2-}" ]
then
    usage
    exit 1
fi

f1="$1"
f2="$2"

if [[ "$f1" != '/dev/null' ]] && [[ ! -f "$f1" ]]
then
    echo "$f1: No such file." >&2
    exit 1
fi

if [[ -d "$f2" ]]
then
   f=$(basename "$f1")
   f2="$f2/$f"
fi

if [[ "$f2" != '/dev/null' ]] && [[ ! -f "$f2" ]]
then
    echo "$f2: No such file." >&2
    usage
    exit 1
fi

if [[ -z "$name1" ]]
then
    name1="$f1"
fi
if [[ -z "$name2" ]]
then
    name1="$f2"
fi

ext="${name1##*.}"


if diff "$f1" "$f2" >/dev/null
then
  exit 0
fi


exif()
{
    if [[ "$1" = /dev/null ]]
    then
        echo /dev/null
        return
    fi

    local b="$(basename "$1")"
    local d="$(mktemp -t "$b.XXXXXX")"

    exiftool "$1" | grep -v 'File Name' | \
                    grep -v 'Directory' | \
                    grep -v 'ExifTool Version Number' | \
                    grep -v 'File Inode Change' | \
                    grep -v 'File Access Date/Time' | \
                    grep -v 'File Modification Date/Time' | \
                    grep -v 'File Permissions' | \
                    grep -v 'File Type Extension' \
        >"$d"
    echo "$d"
}


diff_clean_names()
{
    diff -u "$1" --label "$name1" "$2" --label "$name2" || true
}


exifdiff=
if which exiftool > /dev/null
then
  d1="$(exif "$f1")"
  d2="$(exif "$f2")"
  diff_clean_names "$d1" "$d2"
  set +e
  diff -q "$d1" "$d2" >/dev/null
  exifdiff=$?
  set -e
else
  diff_clean_names "$f1" "$f2"
fi

if $exif_only
then
    exit 0
fi

compare='compare'
montage='montage'
isWindows=false
if [[ "$(uname)" == *"MINGW"* ]]
then
	isWindows=true
	compare='magick.exe compare'
	montage='magick.exe montage'
fi


if \
	([[ "$isWindows" == "true" ]] && (
	! which magick.exe > /dev/null )) || \
    ([[ "$isWindows" == "false" ]] && ( \
	! which compare > /dev/null || \
    ! which montage > /dev/null ))
then
    echo 'ImageMagick is not installed.' >&2
    exit 1
fi

if [[ $exifdiff = 0 ]] && compare "$f1" "$f2" /dev/null
then
    exit 0
fi

bn="$(basename "$f1")"
destfile="$(mktemp -t "$bn.XXXXXX").png"

if [ -z "$fuzz" ] && ( [ "$ext" = "jpeg" ] || [ "$ext" = "jpg" ] )
then
    fuzz='5'
fi

backgroundcolor_flag=
if [ -n "$backgroundcolor" ]
then
    backgroundcolor_flag="-background $backgroundcolor"
fi

color_flag=
if [ -n "$color" ]
then
    color_flag="-highlight-color $color"
fi

fuzz_flag=
if [ -n "$fuzz" ]
then
    fuzz_flag="-fuzz $fuzz%"
fi

density_flag=
do_compare()
{
    $compare $density_flag $color_flag $fuzz_flag $backgroundcolor_flag "$f1" "$f2" png:- | \
    $montage $density_flag -geometry +4+4 $backgroundcolor_flag "$f1" - "$f2" png:- >"$destfile" 2>/dev/null || true
}

if [[ "$isWindows" == "true" ]]
then
    # Get width and height of each input image.
    f1_width="$(exiftool -S -ImageWidth $f1 | cut -d' ' -f2)"
    f2_width="$(exiftool -S -ImageWidth $f2 | cut -d' ' -f2)"
    f1_height="$(exiftool -S -ImageHeight $f1 | cut -d' ' -f2)"
    f2_height="$(exiftool -S -ImageHeight $f2 | cut -d' ' -f2)"
    # find the max of each.
    if (( $(echo "$f1_width > $f2_width") )); then
        max_file_width=$f1_width
    else
        max_file_width=$f2_width
    fi
    if (( $(echo "$f1_height > $f2_height") )); then
        max_file_height=$f1_height
    else
        max_file_height=$f2_height
    fi
	screeninfo=$(wmic desktopmonitor get /format:value | tr -d '\r')
	screen_width=$(echo $screeninfo | sed -e "s/.*ScreenWidth=\([0-9]*\).*/\1/")
    screen_height=$(echo $screeninfo | sed -e "s/.*ScreenHeight=\([0-9]*\).*/\1/")
    resolution_width=$(echo $screeninfo | sed -e "s/.*PixelsPerXLogicalInch=\([0-9]*\).*/\1/")
    resolution_height=$(echo $screeninfo | sed -e "s/.*PixelsPerYLogicalInch=\([0-9]*\).*/\1/")
    # Assume that the combined size will be the same as the maximum of
    # each.  Add 100 pixels on each side for the window borders.
    montage_width=$( echo "$f1_width + $max_file_width + $f2_width + 100" | ./win/bc -l )
    montage_height=$( echo "$f1_height + $max_file_height + $f2_height + 100" | ./win/bc -l )
    # Select the most limiting (lowest) density.
    if (( $(echo "($resolution_width / $montage_width * $screen_width) < ($resolution_height / $montage_height * $screen_height)" | ./win/bc -l) )); then
        density=$( echo "$resolution_width / $montage_width * $screen_width" | ./win/bc -l )
    else
        density=$( echo "$resolution_height / $montage_height * $screen_height" | ./win/bc -l )
    fi

    # If the density needed is less than either of the inputs, use it.
    if (( $(echo "$density < $resolution_width || $density < $resolution_height" | ./win/bc -l) )); then
        density_flag="-density $density"
    fi

    do_compare
    wintemp=$(echo $(cmd "/c echo %TEMP%") | sed -e 's/\"//')
    destfilename=$(basename -- $destfile)
    echo "Trying to open: $wintemp\\$destfilename"
    cmd.exe "/C start $wintemp\\$destfilename"
elif which xdg-open > /dev/null
then
    # Get width and height of each input image.
    f1_width="$(exiftool -S -ImageWidth $f1 | cut -d' ' -f2)"
    f2_width="$(exiftool -S -ImageWidth $f2 | cut -d' ' -f2)"
    f1_height="$(exiftool -S -ImageHeight $f1 | cut -d' ' -f2)"
    f2_height="$(exiftool -S -ImageHeight $f2 | cut -d' ' -f2)"
    # find the max of each.
    if (( $(echo "$f1_width > $f2_width" |bc -l) )); then
        max_file_width=$f1_width
    else
        max_file_width=$f2_width
    fi
    if (( $(echo "$f1_height > $f2_height" |bc -l) )); then
        max_file_height=$f1_height
    else
        max_file_height=$f2_height
    fi
    screen_width="$(xdpyinfo | grep dimensions | sed -e 's/.* \([^ ]*\)x\([^ ]*\) pixels.*/\1/')"
    screen_height="$(xdpyinfo | grep dimensions | sed -e 's/.* \([^ ]*\)x\([^ ]*\) pixels.*/\2/')"
    resolution_width="$(xdpyinfo | grep resolution | sed -e 's/.* \([^ ]*\)x\([^ ]*\) dots per inch.*/\1/')"
    resolution_height="$(xdpyinfo | grep resolution | sed -e 's/.* \([^ ]*\)x\([^ ]*\) dots per inch.*/\2/')"
    # Assume that the combined size will be the same as the maximum of
    # each.  Add 100 pixels on each side for the window borders.
    montage_width=$( echo "$f1_width + $max_file_width + $f2_width + 100" |bc -l )
    montage_height=$( echo "$f1_height + $max_file_height + $f2_height + 100" |bc -l )
    # Select the most limiting (lowest) density.
    if (( $(echo "($resolution_width / $montage_width * $screen_width) < ($resolution_height / $montage_height * $screen_height)" |bc -l) )); then
        density=$( echo "$resolution_width / $montage_width * $screen_width" |bc -l )
    else
        density=$( echo "$resolution_height / $montage_height * $screen_height" |bc -l )
    fi

    # If the density needed is less than either of the inputs, use it.
    if (( $(echo "$density < $resolution_width || $density < $resolution_height" |bc -l) )); then
        density_flag="-density $density"
    fi

    do_compare
    xdg-open "$destfile"
else
    w=$(exiftool -p '$ImageWidth' "$f1" || true)
    if [[ $w -ge 10000 ]]
    then
        cp "$f1" "$destfile"
        exec open "$destfile" "$f2"
    else
        do_compare
        exec open "$destfile"
    fi
fi

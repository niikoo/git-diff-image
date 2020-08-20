#!/bin/bash -x

# Usage: git_diff_image <file1> <file2>

set -euo pipefail

f1="${1-/dev/null}"
f2="${2-/dev/null}"

isWindows=false

if [[ "$(uname)" == *"MINGW"* && "$MSYSTEM" == "MINGW64" ]]
then
	isWindows=true
	alias compare='magick.exe compare'
	alias montage='magick.exe montage'
fi

if [ "$f1" = /dev/null ]
then
    name1=/dev/null
fi
if [ "$f2" = /dev/null ]
then
    name2=/dev/null
fi

if diff "$f1" "$f2" >/dev/null
then
  exit 0
fi

name1="a/$(basename \"$1\")"
name2="b/$(basename \"$2\")"

readlink_f()
{
    if [ $(uname) = 'Darwin' ]
    then
        local f=$(readlink "$1")
        if [ -z "$f" ]
        then
            f="$1"
        fi
        local d=$(dirname "$f")
        local b=$(basename "$f")
        if [ -d "$d" ]
        then
            (cd "$d" && echo "$(pwd -P)/$b")
        elif [[ "$d" = /* ]]
        then
            echo "$f"
        elif [[ "$d" = ./* ]]
        then
            echo "$(pwd -P)/${f/.\//}"
        else
            echo "$(pwd -P)/$f"
        fi
    else
        readlink -f "$1"
    fi
}

thisdir="$(dirname $(readlink_f "$0"))"

e_flag=''
if [ -z "${GIT_DIFF_IMAGE_ENABLED-}" ] || \
   ([[ "${isWindows}" == "false" ]] && ( \
   ! which compare > /dev/null || \
   ! which montage > /dev/null ))
then
echo "eflag"
  e_flag='-e'
fi

exec "$thisdir/diff-image.sh" $e_flag -n "$name1" -N "$name2" "$f1" "$f2"

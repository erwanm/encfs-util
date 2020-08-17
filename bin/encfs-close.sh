#!/bin/bash

source common-lib.sh
source file-lib.sh

progName="encfs-close.sh"


function usage {
    echo "Usage: $progName [mount point]"
    echo
    echo "  Unmounts any currently mounted encrypted directory, unless a"
    echo "  specific directory is supplied as argument: in this cases only"
    echo "  this directory is unmounted."
    echo
    echo "  Options:"
    echo "    -h this help message"
    echo    
}


while getopts 'h' option ; do
    case $option in
	"h" ) usage
	      exit 0;;
        "?" )
            echo "Error, unknow option." 1>&2
            usage 1>&2
	    exit 1
    esac
done
shift $(($OPTIND - 1)) # skip options already processed above
if [ $# -ne 0 ] && [ $# -ne 1 ]; then
    echo "Error: maximum 1 argument expected, $# found." 1>&2
    usage 1>&2
    exit 1
fi
dir="$1"


if [ -z "$dir" ]; then  # default: unmounts all the mounted dirs using /etc/mtab
    cat "/etc/mtab" | while read line; do
	mountType=$(echo "$line" | cut -d " " -f 1)
#	echo "debug: $mountType" 1>&2
	if [ "$mountType" == "encfs" ]; then
	    dir=$(echo "$line" | cut -d " " -f 2)
	    echo "Unmounting '$dir'..."
	    fusermount -u "$dir"
	fi
    done
else # only unmount specific dir
    dir=$(absolutePath "$dir")
    echo "Unmounting '$dir'..."
    fusermount -u "$dir"
fi


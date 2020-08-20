#!/bin/bash

source common-lib.sh
source file-lib.sh


progName="filenames-length.sh"

printFilter=""
truncate=""
reverseTrunc=""

function usage {
    echo "Usage: $progName [options] <source dir>"
    echo
    echo "  Prints the list of all the files under <source dir> (with their path"
    echo "  relative to <source dir>) together with their filename size (not"
    echo "  counting the path)."
    echo "  Can be used to truncate filenames with -t and later reverse the"
    echo "  truncation with -r."
    echo	 
    echo "  Options:"
    echo "    -h print this help message."
    echo "    -m <min> filter filenames with length at least <min>."
    echo "    -t <N> truncate filenames to <N> characters, and print"
    echo "       the new filename and the original one for truncated"
    echo "        files only."
    echo "    -r <file> reverse truncation of the filenames specified"
    echo "       in <file>, where files contains the original filenames"
    echo "       as printed by '-t' from a previous run (no printing)."
    echo
}





while getopts 'hm:t:r:' option ; do
    case $option in
	"h" ) usage
	      exit 0;;
	"m" ) printFilter="$OPTARG";;
	"t" ) truncate="$OPTARG";;
	"r" ) reverseTrunc="$OPTARG";;
        "?" )
            echo "Error, unknow option." 1>&2
            usage 1>&2
	    exit 1
    esac
done
shift $(($OPTIND - 1)) # skip options already processed above
if [ $# -ne 1 ]; then
    echo "Error: 1 argument expected, $# found." 1>&2
    usage 1>&2
    exit 1
fi
source="$1"

if [ -z "$reverseTrunc" ]; then
    pushd "$source" >/dev/null
    find . | while read filepath; do
	filename=$(basename "$filepath")
	sizeName=${#filename}
	#sizePath=${#filepath}
	#    echo -e "$filepath\t$sizePath\t$sizeName"
	if [ -z "$truncate" ]; then
	    if [ -z "$printFilter" ] || [ $printFilter -le $sizeName ]; then
		echo -e "$filepath\t$sizeName"
	    fi
	else # truncate
	    if [ $truncate -lt $sizeName ]; then
		if [ -d "$filepath" ]; then
		    echo "Error: cannot truncate dir name $filepath" 1>&2
		    exit 12
		fi
		newName=${filename:0:$truncate}
		newPath="$(dirname "$filepath")/$newName"
		if [ -e "$newPath" ]; then
		    echo "Error: cannot truncate $filepath, a file with name '$newPath' already exists" 1>&2
		    exit 13
		fi
		mv "$filepath" "$newPath"
		echo -e "$newPath\t$filepath"
	    fi
	fi
    done
    popd >/dev/null
else
    reverseTrunc=$(absolutePath "$reverseTrunc")
    pushd "$source" >/dev/null
    cat "$reverseTrunc" | while read line; do
	new=$(echo "$line" | cut -f 1)
	old=$(echo "$line" | cut -f 2)
	mv "$new" "$old"
    done
    popd >/dev/null
fi

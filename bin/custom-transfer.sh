#!/bin/bash

# Erwan Moreau, created August 2018
#
# Updated August 2019
# Updated August 2020 - function TRANSFER_squash_to_encfs


source common-lib.sh
source file-lib.sh


progName="custom-transfer.sh"

transferFunctionPrefix="TRANSFER_"
listFunctions=""

function usage {
    echo "Usage: $progName [options] <transfer1> [<transfer2> ...]"
    echo
    echo "  Proceeds with one or several predefined transfers."
    echo "  Each <transfer> argument must contain the name of a predefined"
    echo "  function, possibly followed by arguments (with quotes)."
    echo
    echo "   * A transfer function name starts with '$transferFunctionPrefix'"
    echo "     (this prefix can be omitted in the argument)."
    echo "   * Use option -l for a list of available functions."
    echo "   * Use option -s to add custom functions, or source the"
    echo "     functions file before calling this script."
    echo
    echo "  Requirements:"
    echo "    - unidirectional-backup.sh must be available, and all its"
    echo "      dependencies installed and configured properly."
    echo
    echo "  Options:"
    echo "    -h this help message"
    echo "    -l list available transfer functions names (no transfer done)."
    echo "    -L print available transfer functions (no transfer done)."
    echo "    -s <functions file> source this file which contains"
    echo "       custom transfer functions; several files can be sourced"
    echo "       using -s <file1>:<file2>..."
    echo    
}


function listTransferFunctions {
    local namesOrContent="$1"
    if [ "$namesOrContent" == "name" ]; then
	declare -F | cut -d ' ' -f 3  | grep "^TRANSFER" | sed 's/^TRANSFER_//'
    else
	declare -F | cut -d ' ' -f 3  | grep "^TRANSFER" | while read f; do
	    declare -f "$f"
	done
    fi
}


function TRANSFER_clear_rsync {
    local source="$1"
    local dest="$2"
    local otherOptionsUni="$3" # can be used for giving proxy with -g

    comm="unidirectional-backup.sh $otherOptionsUni -t 250 -d \"$source\" \"$dest\"" || exit $?
    eval "$comm" || exit $?
}


function TRANSFER_encfs_rsync_pass_custom_pwd {
    local source="$1"
    local dest="$2"
    local otherOptionsUni="$3" # can be used for giving proxy with -g
    
    comm="unidirectional-backup.sh $otherOptionsUni -t 140 -P -r -d \"$source\" \"$dest\"" || exit $?
    eval "$comm" || exit $?
}


function TRANSFER_squash {
    local source="$1"
    local dest="$2"
    local otherOptions="$3" 

    comm="mksquashfs $otherOptions \"$source\" \"$dest\""
    eval "$comm" || exit $?
}


function TRANSFER_gpg {
    local source="$1"
    local dest="$2"
    local key="$3"

    if [ ! -z "$key" ]; then
	optKey="-r \"$key\""
    fi
    comm="gpg $optKey -o \"$dest\" --encrypt \"$source\""
    eval "$comm" || exit $?
}


# dest is an encfs directory 
function TRANSFER_squash_to_encfs {
    local source="$1"
    local destEncfsDir="$2"
    local destFilepath="$3"

    mountPoint=$(mktemp -d --tmpdir "TRANSFER_squash_to_encfs.XXXXXXXXXX")
    if [ ! -d "$destEncfsDir" ]; then
	comm="encfs-init.sh -P \"$destEncfsDir\" \"$mountPoint\""
    else
	comm="encfs-open.sh -w \"$destEncfsDir\" \"$mountPoint\""
    fi
    eval "$comm" || exit $?
    echo c
    mkdirSafe $(dirname "$mountPoint/$destFilepath")
    TRANSFER_squash "$source" "$mountPoint/$destFilepath"  || exit $?
    encfs-close.sh "$mountPoint" || exit $?
    rmdir "$mountPoint"
}


while getopts 'hlLs:' option ; do
    case $option in
	"h" ) usage
	      exit 0;;
	"l" ) listFunctions="name";;
	"L" ) listFunctions="content";;
	"s" ) sourceFilesColon="$OPTARG"
	      for f in $(echo "$sourceFilesColon" | tr ':' ' '); do
		  source "$f"
	      done;;
        "?" )
            echo "Error, unknow option." 1>&2
            usage 1>&2
	    exit 1
    esac
done
if [ ! -z "$listFunctions" ]; then
    listTransferFunctions "$listFunctions"
    exit 0
fi
shift $(($OPTIND - 1)) # skip options already processed above
if [ $# -lt 1 ]; then
    echo "Error: at least 1 argument expected, $# found." 1>&2
    usage 1>&2
    exit 1
fi

while [ $# -gt 0 ]; do
    transferComm="$1"
    transferComm=${transferComm#TRANSFER_} # remove prefix if present
    eval "TRANSFER_$transferComm" || exit $?
    shift
done
      

#!/bin/bash

set -x

source common-lib.sh
source file-lib.sh

progName="encfs-init.sh"

mountPoint="/tmp/private"
passKey=""
askPassword=""
storeWithPass="yep"
keyLength=20
keyPrefix="encfs/"
keySlashChar="+"
configFile="encfs6.xml"
homeDirReplace="yep"
homeDirString="%HOMEDIR%"
mediaDirReplace="yep"
mediaDirString="%MEDIADIR%"
close=""
reverseOpt=""

function usage {
    echo "Usage: $progName [options] <encrypted dir> [mount point]"
    echo
    echo "  Initializes a new encrypted directory using my setup, i.e.:"
    echo "    - using encfs standard mode with mac headers"
    echo "    - mounting to '$mountPoint' if mount point is not supplied"
    echo "    - password generated and stored with pass under key based"
    echo "      on dir path. See also -p (password not generated),"
    echo "      -k (key not based on dir)."
    echo
    echo "  Requirements:"
    echo "    - pass and gpg must be installed and configured properly."
    echo "    - package erw-bash-commons must be accessible."
    echo
    echo "  Options:"
    echo "    -h this help message"
    echo "    -p ask for password instead of using pass; the password is not"
    echo "       stored."
    echo "    -P ask for password instead of generating, then store with pass."
    echo "    -k <key> use this key in pass instead of the generated path-based"
    echo "       key."
    echo "    -l <length> specify key length in characters (default: $keyLength)"
    echo "    -a <key prefix> if no key is specified, use this as key prefix."
    echo "       Default: '$keyPrefix'."
    echo "    -f <config filename> store encfs config file under this name."
    echo "       Default: '$configFile'."
    echo "    -c close (i.e. unmount) immediately after initializing. If the "
    echo "       mount point is not specified, a temporary directory is used"
    echo "       instead of the default mount point '$mountPoint'."
    echo "    -r reverse mode: initialize a new encrypted directory for use with"
    echo "       encfs reverse mode, i.e. where encfs provides an encrypted view"
    echo "       of a clear directory. However this script only prepares an empty"
    echo "       encrypted directory to be used later with 'encfs-open -r', as "
    echo "       opposed to what encfs does with this option."
    echo "       This option implies option -c."
    echo "       Remark: a directory encrypted in the standard way cannot be used"
    echo "       with reverse mode later."
    echo "    -H do not use home directory replacement in the pass key. Default:"
    echo "       if the directory path starts with the home dir, it is replaced"
    echo "       with '$homeDirString' to make it more device-independent."
    echo "    -M do not use media directory replacement in the pass key. Default:"
    echo "       if the directory path starts with /media/<username>, it is"
    echo "        replaced with '$mediaDirString'."
    echo
    echo
}


while getopts 'hpPk:l:a:f:crHM' option ; do
    case $option in
	"h" ) usage
	      exit 0;;
	"k" ) passKey="$OPTARG";;
	"p" ) askPassword="1"
	      storeWithPass="";;
	"P" ) askPassword="1";;
	"l" ) keyLength="$OPTARG";;
	"a" ) keyPrefix="$OPTARG";;
	"f" ) configFile="$OPTARG";;
	"c" ) close="yes";;
	"r" ) reverseOpt="--reverse"
	      close="yes";;
	"H" ) homeDirReplace="";;
	"M" ) mediaDirReplace="";;
        "?" )
            echo "Error, unknow option." 1>&2
            usage 1>&2
	    exit 1
    esac
done
shift $(($OPTIND - 1)) # skip options already processed above
if [ $# -ne 1 ] && [ $# -ne 2 ]; then
    echo "Error: 1 or 2 arguments expected, $# found." 1>&2
    usage 1>&2
    exit 1
fi
encryptedDir="$1"
if [ ! -z "$2" ]; then
    mountPoint="$2"
else
    if [ ! -z "$close" ]; then # special case if close option: mount to a temporary directory
	mountPoint=$(mktemp -d --tmpdir "encfs-init.tmp.XXXXXXXXXX")
	deleteMountPoint="yep"
	unmountMsg="Unmounting the clear directory."
	if [ ! -z "$reverseOpt" ]; then
	    unmountMsg="Unmounting the encrypted directory."
	fi
    fi
fi

mkdirSafe "$encryptedDir"
if [ $(ls -A "$encryptedDir" | wc -l) -gt 0 ]; then
    echo "Error: directory $encryptedDir is not empty." 1>&2
    exit 1
fi
encryptedDir=$(absolutePath "$encryptedDir")
mountPoint=$(absolutePath "$mountPoint")

mkdirSafe "$mountPoint"
mtabLine=$(grep "$mountPoint" /etc/mtab) # already mounted?
if [ ! -z "$mtabLine" ]; then
    echo "Error: directory $mountPoint is already used as mount point." 1>&2
    exit 1
fi
if [ $(ls -A "$mountPoint" | wc -l) -gt 0 ]; then
    echo "Error: directory $mountPoint is not empty." 1>&2
    exit 1
fi

if [ -z "$passKey" ] && [ ! -z "$storeWithPass" ]; then
    pass git pull -q
    if [ $? -ne 0 ] ; then
	echo "Command 'pass git pull' failed." 1>&2
	exit 2
    fi
    passKey="$encryptedDir"
    if [ ! -z "$homeDirReplace" ]; then
	passKey=$(echo "$passKey" | sed "s:^$HOME:$homeDirString:" )
    fi
    if [ ! -z "$mediaDirReplace" ]; then
	username=$(whoami)
	passKey=$(echo "$passKey" | sed "s:^/media/$username:$mediaDirString:" )
    fi
    passKey=$(echo "$passKey" | tr "/" "$keySlashChar")
    passKey="$keyPrefix$passKey"
fi
echo "Key for this directory is: $passKey" 1>&2
# setting default for encfs: using pass for the password
# remark: ondemand works only with external program
encfsPassKeyOpt="--extpass=\"pass $passKey\"  --ondemand" 

if [ -z "$askPassword" ]; then
    echo "Generating password" 1>&2
    password=$(pass generate "$passKey" $keyLength)
    if [ $? -ne 0 ]; then
	echo "Command 'pass generate \"$passKey\" $keyLength' failed." 1>&2
	exit 2
    fi
else
    if [ ! -z "$storeWithPass" ]; then
	password="a"
	testPassword="b"
	while [ "$password" != "$testPassword" ]; do
	    echo -n "Enter password: " 1>&2
	    read -s password
	    echo 1>&2
	    echo -n "Again to be safe: " 1>&2
	    read -s testPassword
	    echo 1>&2
	done
	testPassword=""
	echo "$password" | pass insert -e "$passKey"
	if [ $? -ne 0 ]; then
	    echo "Command 'pass insert -e \"$passKey\"' failed." 1>&2
	    exit 2
	fi
	echo "Password stored, see it with: pass \"$passKey\"" 1>&2
	pass git push -q
    else
	encfsPassKeyOpt=""
    fi
fi

if [ $? -ne 0 ] ; then
    echo "Command 'pass git push' failed." 1>&2
    exit 2
fi

echo "Creating encfs directory..." 1>&2
echo 1>&2

# 29/12/17: removed option --require-macs, because it's not compatible with reverse mode.
comm="encfs $reverseOpt --standard $encfsPassKeyOpt --idle 30 \"$encryptedDir\" \"$mountPoint\""
#comm="encfs $reverseOpt --standard --require-macs --idle 30 \"$encryptedDir\" \"$mountPoint\""
#echo "DEBUG: $comm" 1>&2
eval "$comm" 1>&2
if [ $? -ne 0 ]; then
    echo "Command '$comm' failed." 1>&2
    exit 3
fi

if [ -f "$encryptedDir/.encfs6.xml" ]; then
    mv "$encryptedDir/.encfs6.xml" "$encryptedDir/$configFile"
else
    echo "Error: original config file '$encryptedDir/.encfs6.xml' not found." 1>&2
    exit 4
fi

if [ ! -z "$close" ]; then
    echo "$unmountMsg" 1>&2
    fusermount -u "$mountPoint"
    if [ ! -z "$deleteMountPoint" ]; then
	rmdir "$mountPoint"
    fi
fi
    
echo "Done." 1>&2

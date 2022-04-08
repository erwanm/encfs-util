#!/bin/bash

source common-lib.sh
source file-lib.sh



progName="encfs-open.sh"

options="--idle 30"
mountPoint="/tmp/private"
passKey=""
askPassword=""
keyLength=20
keyPrefix="encfs/"
keySlashChar="+"
configFile="encfs6.xml"
homeDirReplace="yep"
homeDirString="%HOMEDIR%"
mediaDirReplace="yep"
mediaDirString="%MEDIADIR%"
# in order to prevent accidentally modifying an encrypted dir, from now on
# the user must explicitly enable writing permission with -w
# Remark: a user who prefers to reverse the default can simply have an alias.
readOnly="defaultYES" 
allowOther=
reverseClearDir=""
printOnly=""

function usage {
    echo "Usage: $progName [options] <encrypted dir> [mount point]"
    echo
    echo "  Opens an encrypted directory using my setup, i.e.:"
    echo "    - mounting to '$mountPoint' if mount point is not supplied"
    echo "    - password stored with pass under key based on dir path."
    echo "      See also -p (password not generated), -k (key not based"
    echo "      on dir)."
    echo
    echo "  Requirements:"
    echo "    - pass and gpg must be installed and configured properly."
    echo "    - package erw-bash-commons must be accessible."
    echo
    echo "  Options:"
    echo "    -h this help message"
    echo "    -p ask for password instead of using pass; overrides -k."
    echo "    -k <key> use this key in pass"
    echo "    -a <key prefix> if no key is specified, use this as key prefix."
    echo "       Default: '$keyPrefix'."
    echo "    -f <config filename> store encfs config file under this name."
    echo "       Default: '$configFile'."
    echo "    -r <clear source dir> reverse mode: opens <clear source dir> with"
    echo "       encfs reverse mode using the password (config file) for"
    echo "       <encrypted dir>; this provides an encrypted view of the clear"
    echo "       source dir in <mount point>, which can be used with rsync to"
    echo "       update an encrypted backup in <encrypted dir>."
    echo "       The encrypted directory must have been created in reverse mode"
    echo "       with 'encfs-init -r'."
    echo "    -H do not use home directory replacement in the pass key. Default:"
    echo "       if the directory path starts with the home dir, it is replaced"
    echo "       with '$homeDirString' to make it more device-independent."
    echo "    -M do not use media directory replacement in the pass key. Default:"
    echo "       if the directory path starts with /media/<username>, it is"
    echo "        replaced with '$mediaDirString'."
    echo "    -w mount with read-write permissions; default: read-only."
    echo "    -o make the mounted directory accessible to all users. Requires"
    echo "       /etc/fuse.conf to contain user_allow_other option."
    echo "    -P only print key for the encrypted directory (do not open)."
    echo    
}


while getopts 'hpk:a:wfHMor:P' option ; do
    case $option in
	"h" ) usage
	      exit 0;;
	"k" ) passKey="$OPTARG";;
	"p" ) askPassword="1";;
	"l" ) keyLength="$OPTARG";;
	"a" ) keyPrefix="$OPTARG";;
	"f" ) configFile="$OPTARG";;
	"H" ) homeDirReplace="";;
	"M" ) mediaDirReplace="";;
	"w" ) readOnly="";;
	"o" ) allowOther="1";;
	"r" ) reverseClearDir="$OPTARG";;
	"P" ) printOnly="yep";;
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
fi

dieIfNoSuchDir "$encryptedDir"
if [ ! -f "$encryptedDir/$configFile" ]; then
    echo "Error: no config file '$configFile' found in '$encryptedDir'" 1>&2
    exit 1
else
    if [ -f "$encryptedDir/.encfs6.xml" ]; then
	echo "Error: directory '$encryptedDir' contains two config files, '.encfs6.xml' and '$configFile', expecting only the latter. Sorry, this needs to be fixed manually." 1>&2
	exit 1
    fi
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

export ENCFS6_CONFIG="$encryptedDir/$configFile"
if [ ! -z "$readOnly" ]; then
    options="$options -o ro"
fi
if [ ! -z "$allowOther" ]; then
    options="$options -o allow_other"
fi
if [ ! -z "$reverseClearDir" ]; then
    options="$options --reverse"
fi

if [ -z "$askPassword" ]; then
    timeout 5 pass git pull -q
    if [ $? -ne 0 ] ; then
	echo "Command 'pass git pull' timed out." 1>&2
    fi
    if [ -z "$passKey" ]; then
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
    # Oct 17: removing --ondemand: I think sometimes other programs (e.g. LibreOffice)
    # try to access the mounted dir when I don't want it mounted, asking me for
    # the password repeatedly. I will see if this still happens without the option,
    # and whether there are disadvantages to not having it.
#    options="$options --extpass='pass $passKey' --ondemand"
    options="$options --extpass='pass $passKey'"
fi

doneMsg="Done, content available in clear at $mountPoint"
if [ -z "$printOnly" ]; then
    if [ ! -z "$reverseClearDir" ]; then
	# caution: encryptedDir does not contain the encrypted dir anymore but the input dir for encfs (reverse mode)
	encryptedDir=$(absolutePath "$reverseClearDir")
	doneMsg="Done, encrypted content available at $mountPoint"
    fi
    comm="encfs $options \"$encryptedDir\" \"$mountPoint\""
#    echo "'$comm'"
    eval "$comm"
    if [ $? -ne 0 ]; then
	echo "Command '$comm' failed." 1>&2
	exit 3
    fi
    echo "$doneMsg" 1>&2
else
    echo "$passKey"
fi
export ENCFS6_CONFIG=

#!/bin/bash

source common-lib.sh
source file-lib.sh


#
# TESTING DONE:
# - simple -r option with local source and dest, new dest (init)
# - simple -r option with local source and dest, updating dest (one new file, correctly the only one synced)
# - regular rsync (no -r) with local source and dest, new dest and updating ok
# - option -r -p tested with local source and dest (new dest and updating)
# - option -P -k for new dest then -k when updating ok, with both dirs local
# - option -r with remote dest dir, new and update 
# - option -r with remote source dir, new and update 
# - option -d tested with remote dest, remote source
#

progName="unidirectional-backup.sh"

configFile="encfs6.xml"

passKey=""
askPassword=""
storeWithPass="yep"
encfsPassOptions=""
rsyncOptions="-a --del"
rsyncOptionsDebugMode="-v --progress"
encfsReverse=""
gateway=""
debugMode=""
addDateFile=""
truncateFilename=""

function usage {
    echo "Usage: $progName [options] <source dir> <dest dir>"
    echo
    echo "  Performs an incremental unidirectional backup using rsync, i.e."
    echo "  updates the destination directory so that it contains an exact"
    echo "  copy of the source directory (thus possibly deleting files)."
    echo
    echo "  Additionally this script can read a clear directory as if it was"
    echo "  encrypted in the same way as the destination dir, using encfs"
    echo "  reverse mode."
    echo "  Remote source or destination is permitted through ssh, e.g.:"
    echo "     $progName user@distanthost:sourcepath localdestpath"
    echo "     $progName localsourcepath user@distanthost:destpath"
    echo
    echo "  In clear mode (no -r), the source and dest can be a single file."
    echo
    echo "  Requirements:"
    echo "    - rsync, ssh, pass and gpg must be installed and configured."
    echo "    - scripts encfs-open.sh and encfs-init.sh must be accessible."
    echo "    - script filenames-length.sh must be accessible."
    echo "    - package erw-bash-commons must be accessible."
    echo "    - if using remote source or destination, the remote host must"
    echo "      also follow these requirements."
    echo
    echo "  Options:"
    echo "    -h print this help message."
    echo "    -r use encfs reverse mode to read the source directory in clear"
    echo "       and transmit its content as encrypted to the destination."
    echo "       Scripts encfs-open.sh or encfs-init.sh are used so that the"
    echo "       password is managed with pass under a key based on the dir"
    echo "       path."
    echo "    -p ask for password instead of using pass; the password is not"
    echo "       stored (used only in conjunction with -r)."
    echo "    -P ask for password instead of generating it (if initializing),"
    echo "       then store it/get it with pass. (used only in conjunction"
    echo "       with -r)."
    echo "    -k <key> use this key in pass instead of the generated path-based"
    echo "       key (used only in conjunction with -r)."
    echo "    -e <options> additional options to encfs-open/encfs-init (used"
    echo "       only in conjunction with -r; -p, -P and -k are ignored)."
    echo "    -g <gateway> connect through this proxy over ssh, e.g."
    echo "         $progName -g user@proxy ..."
    echo "    -o <options> additional options to rsync, e.g. "
    echo "         $progName -o \"--exclude-from=<exclude list file>\" ..."
    echo "    -d add/update date file <dest dir>.date at the end of the process."
    echo "    -t <max length> truncate filenames longer than <max length>, which"
    echo "       can cause fatal rsync errors. Recommended value: 140 with "
    echo "       encryption (-r), 250 without (rsync in clear)."
    echo "    -D debug mode: print rsync details, leave temporary directory."
    echo
}


#
# REMARK: stdout cannot be redirected in execCommand, because the command might require interactions:login, passphrase, etc.
#


#
# evaluates a command locally if arg 'remote' is empty, on host 'remote' through ssh otherwise (using global ssh options)
#
# If remote, arg 'comm' must not contain any apostrophe "'".
#
function execCommand {
    local comm="$1"
    local remote="$2"

    if [ ! -z "$remote" ]; then
	comm="ssh -t '$remote' '$comm'"
	if [ ! -z "$gateway" ]; then
#	    comm="${comm//\\/\\\\}"
	    comm="${comm//\"/\\\"}"
	    comm="ssh -t '$gateway' \"$comm\""
	fi
    fi
    echo -e "$progName; running command:\n $comm" 1>&2
    eval "$comm"
    if [ $? -ne 0 ]; then
	echo "An error occured when evaluating: '$comm'" 1>&2
	exit 2
    fi
}



# If 2nd arg is not supplied, nothing happens
#
# The file arg is preferably supplied with absolute path (typically /tmp)
# The file is removed at the end (remote and local)
#
function moveFileLocallyIfNeeded {
    local file="$1"
    local remote="$2"

    if [ ! -z "$remote" ]; then
	copyComm="rsync $rsyncOptions $remote:$file $file"
	execCommand "$copyComm" || exit $?
	execCommand "rm -f $file" "$remote" || exit $?
    fi
}




while getopts 'hpPk:re:g:o:t:d' option ; do
    case $option in
	"h" ) usage
	      exit 0;;
	"k" ) passKey="$OPTARG";;
	"p" ) askPassword="1"
	      storeWithPass="";;
	"P" ) askPassword="1";;
	"r" ) encfsReverse="yep";;
	"e" ) encfsPassOptions="$encfsPassOptions $OPTARG";;
	"g" ) gateway="$OPTARG";;
	"o" ) rsyncOptions="$rsyncOptions $OPTARG";;
	"t" ) truncateFilename="$OPTARG";;
	"d" ) addDateFile="yep";;
	"D" ) debugMode="yep"
	      rsyncOptions="$rsyncOptions $rsyncOptionsDebugMode";;
        "?" )
            echo "Error, unknow option." 1>&2
            usage 1>&2
	    exit 1
    esac
done
shift $(($OPTIND - 1)) # skip options already processed above
if [ $# -ne 2 ]; then
    echo "Error: 2 arguments expected, $# found." 1>&2
    usage 1>&2
    exit 1
fi
source="$1"
dest="$2"


# general initializations

if echo "$source" | grep ":" >/dev/null; then
    hostSrc=${source%:*}
    sourceDir=${source#*:}
else
    hostSrc=""
    sourceDir="$source"
fi
if echo "$dest" | grep ":"; then
    hostDest=${dest%:*}
    destDir=${dest#*:}
else
    hostDest=""
    destDir="$dest"
fi
#echo "DEBUG: hostSrc='$hostSrc', sourceDir='$sourceDir', hostDest='$hostDest', destDir='$destDir'" 1>&2

if [ ! -z "$hostSrc" ] || [ ! -z "$hostDest" ]; then
     # forbidden case both remote
    if [ ! -z "$hostSrc" ] && [ ! -z "$hostDest" ]; then
	echo "Error: both source and destination are remote, aborting" 1>&2
	exit 3
    fi
    # setting rsync remote options
    if [ -z "$gateway" ]; then
	sshOpt="-e ssh"
    else
	sshOpt="-e \"ssh -A $gateway ssh\""
    fi
    rsyncOptions="$sshOpt $rsyncOptions"
fi

if [ ! -z "$truncateFilename" ]; then
    filePseudoUniqueId=$(date +"%y-%m-%d-%H-%M-%S-%N")
    truncateOutputFilename="/tmp/$progName.$filePseudoUniqueId"
    truncateComm="filenames-length.sh -t $truncateFilename \"$sourceDir\" >$truncateOutputFilename; echo 'Truncated filenames:'; cat $truncateOutputFilename"
    execCommand "$truncateComm" "$hostSrc" || exit $?
fi


if [ ! -z "$encfsReverse" ]; then

    # Principle:
    # 0. init the dest dir if new
    # 1. copy config file from dest to source host into temp dir  
    # 2. reverse-open source dir (using config file)
    # 3. sanity check on mounted dir (source side): not empty
    # 4. rsync from source to dest
    # 5. copy config file back to dest dir, unmount and delete temp dir
    
    encfsInitOpts="$encfsPassOptions"
    if [ ! -z "$askPassword" ]; then
	if [ -z "$storeWithPass" ]; then
	    encfsInitOpts="$encfsInitOpts -p"
	else
	    encfsInitOpts="$encfsInitOpts -P"
	fi
    fi
    if [ ! -z "$passKey" ]; then
	encfsInitOpts="$encfsInitOpts -k \"$passKey\""
    fi

    # first step: make sure the encrypted dest dir exists; if not, initialize it.
    # remark: we assume that if the dir exists then it is a valid encrypted dir!

   
    checkInitCommand="if [ ! -f \"$destDir/$configFile\" ]; then echo \"Initializing encrypted dest dir...\" 1>&2; encfs-init.sh -r $encfsInitOpts \"$destDir\"; fi"
    if [ ! -z "$storeWithPass" ] && [ -z "$passKey" ]; then # if password stored with pass and key not provided manually, obtain generated key
	filePseudoUniqueId=$(date +"%y-%m-%d-%H-%M-%S-%N")
	outputFilename="/tmp/$progName.$filePseudoUniqueId"
	checkInitCommand="$checkInitCommand; encfs-open.sh $encfsPassOptions -P \"$destDir\" >$outputFilename"
    fi
    echo "$progName: Checking destination dir '$dest', initializing with encfs-init.sh if needed..." 1>&2
    execCommand "$checkInitCommand" "$hostDest" || exit $?
    if [ ! -z "$storeWithPass" ] && [ -z "$passKey" ]; then # if password stored with pass and key not provided manually, obtain generated key
	moveFileLocallyIfNeeded "$outputFilename" "$hostDest" || exit $?
	possiblePassKey=$(cat "$outputFilename")
	rm -f "$outputFilename"
	if [ -z "$possiblePassKey" ]; then
	    echo "Error: pass key supposedly generated from path but empty key returned; aborting." 1>&2
	    exit 31
	else
	    passKey="$possiblePassKey"
	fi
    fi

    # second step: mount an encrypted view of the clear source dir, using the dest dir password
    # source - dest   => action
    # local  - local  => locally open reverse with config file
    # local  - remote => scp remote config file then open reverse locally
    # remote - local  => scp local config file to remote then open reverse on remote
    # remote - remote => ( forbidden I think )

    # 0. temporary work dir
    pseudoUniqueId=$(date +"%y-%m-%d-%H-%M-%S-%N")
    workDir="/tmp/$progName.$pseudoUniqueId"
    prepareTransferConfigComm="mkdir $workDir; mkdir $workDir/mount; mkdir $workDir/fakedest"
    
    # 1. get config file located in dest dir on the same host as source dir:
    execCommand "$prepareTransferConfigComm" "$hostSrc" || exit $?

    
    if [ -z "$hostSrc" ]; then # source is local and dest is either local or remote
	copyComm="rsync $rsyncOptions  \"$dest/$configFile\" \"$workDir/fakedest/$configFile\""
    else  # source is remote, dest must be local
	copyComm="rsync $rsyncOptions \"$destDir/$configFile\" \"$hostSrc:$workDir/fakedest/$configFile\""
    fi
    execCommand "$copyComm" || exit $?

    # remark: workDir contains directory mount and directory fakedest, which contains the config file.

    # 2. reverse-open source dir
    echo "$progName: opening clear source dir '$source' in reverse mode to mount point '$workDir/mount'..." 1>&2
    encfsOpenOpts="$encfsPassOptions"
    if [ -z "$storeWithPass" ]; then
	echo "DEBUG: no store pass, adding -p option" 1>&2
	encfsOpenOpts="$encfsOpenOpts -p"
    else
	echo "DEBUG: store pass, supplying key '$passKey'" 1>&2
	# pass key is given anyway (manually given as option or obtained from init stage)
	encfsOpenOpts="$encfsOpenOpts -k \"$passKey\""
    fi
    reverseOpenComm="encfs-open.sh $encfsOpenOpts -r \"$sourceDir\" \"$workDir/fakedest\" \"$workDir/mount\""
    execCommand "$reverseOpenComm" "$hostSrc" || exit $?

    # 3. sanity check: abort if the mounted encrypted view is empty
    # (in order to avoid deleting everything in the dest dir with rsync --del)
    pseudoUniqueId=$(date +"%y-%m-%d-%H-%M-%S-%N")
    outputFilename="$progName.$pseudoUniqueId"
    sanityCommand="ls -A $workDir/mount | wc -l >$outputFilename"
    execCommand "$sanityCommand" "$hostSrc" || exit $?
    moveFileLocallyIfNeeded "$outputFilename" "$hostSrc" || exit $?
    n=$(cat "$outputFilename")
    rm -f "$outputFilename"
    if [ $n -eq 0 ]; then
	echo "Error: sanity check failed, the encrypted view in mounted directory '$workDir/mount' is empty. Empty source dir???" 1>&2
	exit 11
    fi

    # 4. rsync
    if [ -z "$hostSrc" ]; then # both local or source local and dest remote
	rsyncComm="rsync $rsyncOptions \"$workDir/mount/\" \"$dest/\""
    else # source remote and dest local 
	rsyncComm="rsync $rsyncOptions \"$hostSrc:$workDir/mount/\" \"$dest/\""
    fi
    eval "$rsyncComm" || exit $?

    # Remark: the config file needs to be copied back to the deste dir because 'rsync --del' removes it :(
    # 5. copy config file back to dest dir, unmount and delete temp dir
    if [ -z "$hostSrc" ]; then   # source is local and dest is either local or remote
	copyComm="rsync $rsyncOptions  \"$workDir/fakedest/$configFile\" \"$dest/$configFile\""
    else  # source is remote, dest must be local
	copyComm="rsync $rsyncOptions \"$hostSrc:$workDir/fakedest/$configFile\" \"$destDir/$configFile\""
    fi
    execCommand "$copyComm" || exit $?

    umountComm="encfs-close.sh \"$workDir/mount\""
    if [ -z "$debugMode" ]; then
	umountComm="$umountComm; rm -rf \"$workDir\""
    else
	echo "$progName: debug mode, leaving temporary directory '$workDir/mount'" 
    fi
    execCommand "$umountComm" "$hostSrc" || exit $?
    
else # regular rsync (no reverse encoding)
    rsyncComm="rsync $rsyncOptions \"$source/\" \"$dest/\""
    execCommand "$rsyncComm" || exit $?
fi

if [ ! -z "$truncateFilename" ]; then
    reverseTruncComm="echo 'Restoring truncated files:'; cat $truncateOutputFilename; filenames-length.sh -r $truncateOutputFilename \"$sourceDir\"; rm -f $truncateOutputFilename"
    execCommand "$reverseTruncComm" "$hostSrc" || exit $?
fi


if [ "$addDateFile" ]; then
    mydate=$(date +"%d/%m/%y at %H:%M:%S")
    dateComm="echo 'Last sync by $progName done on $mydate from $HOSTNAME.' >$destDir.date"
    execCommand "$dateComm" "$hostDest" || exit $?
fi


echo "Done."


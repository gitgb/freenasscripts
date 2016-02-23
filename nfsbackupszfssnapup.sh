#!/bin/sh
# 
# FUNCTIONAL AREA OR ABSTRACT: (Shouldn't I use Perl ;>) 
# 	To send file system snapshots to an offsite plugin disk(s) for offsite storage.
#
#	How it works is something like the following:
#	
#	Get the off-site storage, plug it in, and get it online. If this script is
#	installed as a Cron task, it will eventually sense that the off-site
#	pool is attached, and try to make backup snapshots and move them to the
#	off-site pool. It will write its results into a log file, and cron will send an
#	email. As long as it senses that the off-site pool is attached, it under cron, will
#	continue to try to make snapshots and update the on-site pool; but, it is blocked
#	if a snapshot named @${DESTPOOL}-backup.olddelete is present. While present this
#	causes emails every time this script tries to run to the effect that you should
#	get rid of this snapshot called @${DESTPOOL}-backup.olddelete. When it's finished all you
#	have to do is dismount the off-site pool and bring it off-site until next time.
#	Added the ability to run the script with a parameter "backup". This will delete the snapshot
#	named @${DESTPOOL}-backup.olddelete, then send the snapshots to the backup pool, and display the last
#	few lines of the log file, so you can check the run. Meant for just running the script.
#	It supports a list of one or more zpools; that way one pool can be on-site, the other off-site. Then swap.
#	This is good for the paranoid. 
#	
#	To prime/initialize (very important) : 
#	The offsite zpool dataset should be a complete replication stream package, 
#	which will replicate the specified  filesystem,  and  all descendant file systems, up to
#	the named snapshot. When received, all  properties,  snapshots,
#	descendent file systems, and clones are preserved.
#	So create that with something like:
#	Note: sudo DOES NOT work across pipes '|' so sudo -s or su first, then try it:
#   First make a recursive snapshot named appropriately: 
#		zfs snapshot -r mypool/test@offsite-backup2
#	This snapshots mypool/test and names it offsite-backup2, so one of the backup zpools would have
#	the name "offsite". The "-backup2"  part makes it ready to participate in this scripts naming conventions.
#	The latest snapshot is named something like "@offsite-backup2", the previous one, "@offsite-backup1",
#	and the oldest named "@offsite-backup.olddelete".
# 	Now batch send the replication stream for the whole dataset:
#		batch
#		zfs send -e -R mypool/test@offsite-backup2 | zfs recv -d -v offsite
#		control D
#	should replicate the original file system. THE SCRIPT BELOW SHOULD BE EDITED,
#	TO MATCH YOUR ENVIRONMENT/POOL NAMES, ETC.
#	What if you have a backup zpool already? Make the recursive snapshot:
#		zfs snapshot -r mypool/test@offsite-backup2 
#	Then send an Incremental-composite Replication stream:
#		zfs send -v -e -R -I mypool/test@some-existing-snap mypool/test@offsite-backup2 | zfs recv -v -d -F offsite
#	Now run the test script, and things should be synced up.
#	Any snapshot which is the latest on both zpools should work, the date
#   is important, not the name.
#	Why batch it? you don't want your computer going to sleep during a ssh long task.
#	START WITH A TEST DATASET FIRST! MAKE SURE YOU HAVE THINGS CORRECT!!!
#	Then copy/rename, and edit the copy, change the few places necessary to backup your real data.
#	This script can be added to cron tasks or enter it via the batch command (if it takes a while)
#	followed by the complete script filename.
#	Also notice the sanity check; it lists and finds files in the test dataset
#	and echos back what it finds. If you don't see what you expect, start investigating
# 	with your test data set before running it on your real data. I have seen the offsite
#	files disappear! And then, a detach and re-attach brings all the files back! What?
#	So list out some files, make your own sanity checks. Note: ls under root includes .files.
# 
# ENVIRONMENT/PROJECT:
# 	freenas server
# 
# MODIFIED BY:
# VERS	DATE		AUTH.	REASON
# 1.0	3/9/14		GSB	Original
# 2.0	6/3/14		gb	logfile, cron/batch
# 3.0	12/9/15		gb	elastic sky (esxi) need more backing up
#
# Copyright (C) 6/3/14 Public Domain 
# THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE.
# 
# !-*/

# error message &2 and &1
errmsg () {
	echo "`basename $0`: $@" 1>&2
	# might as well put in log file too
	echo "`basename $0`: $@"
exit 1
}

#####################
# ENVIRONMENT VALUES, for me are: rz2/data src, offsite and OffsiteB pool sink
# Change these for your datasets, but always have a "test" dataset for testing things
# first. Maybe useful after an upgrade, new hardware, etc.
# I also rename this script to reflect the source pool I am backing up.
# Added multi backup disk pools. Keep one disk-pool local to be backed up; then swap 
# with the other offsite. If only one disk-pool its ok too, it will ignore the second pool name

POOLLIST="offsite OffsiteB"
SRCPOOL="rz2/nfs/backups"
LOGFILE="/var/log/zfssnapup.log"
# should clear occasionaly cp /dev/null to zfssnapup.log

#####################

# first check if/what is plugged in, if not there, no errs, no output
DESTPOOL=""
for mypool in $POOLLIST
do 
	if  /sbin/zfs list  $mypool 1>/dev/null 2>/dev/null 
	then
		DESTPOOL=$mypool
	fi	
done

if [  -z "$DESTPOOL" ]
then
	exit
fi


echo "Will use $DESTPOOL as destination file system"

# am I root? -ne is integer != string
username=`whoami`
if [  "$username" != "root" ] 
then
	errmsg "You must be root to do this! "
fi

# lets check if $1 is set to "backup"
if [ "$1" == "backup" ]; then
	/sbin/zfs  destroy -r $SRCPOOL@${DESTPOOL}-backup.olddelete 
fi

# lets use a logfile for output
exec 6>&1 >> $LOGFILE     # stdout replaced with file
echo
echo "*****************"
echo "New run...."
date
echo "Source dataset is $SRCPOOL, and it will be sent to $DESTPOOL"

# 0 is true of course!
if   /sbin/zfs list  -t snapshot $SRCPOOL@${DESTPOOL}-backup.olddelete 1>/dev/null 2>/dev/null  
then
	errmsg "You must destroy $SRCPOOL@${DESTPOOL}-backup.olddelete (and decendents) first!	# /sbin/zfs destroy -r  $SRCPOOL@${DESTPOOL}-backup.olddelete "
fi

# BEGIN
# make new snapshot
echo "Making new recursive snapshot of all $SRCPOOL datasets"
# Recursively  create snapshots of	all descendent datasets.
/sbin/zfs snapshot -r $SRCPOOL@${DESTPOOL}-backup3

echo "Holding this backup snapshot $SRCPOOL@${DESTPOOL}-backup3 "
/sbin/zfs hold -r ${DESTPOOL}-backup $SRCPOOL@${DESTPOOL}-backup3

# rename the snapshots
echo "Renaming the snapshots "
/sbin/zfs rename -r $SRCPOOL@${DESTPOOL}-backup1 $SRCPOOL@${DESTPOOL}-backup.olddelete
/sbin/zfs rename -r $SRCPOOL@${DESTPOOL}-backup2 $SRCPOOL@${DESTPOOL}-backup1
/sbin/zfs rename -r $SRCPOOL@${DESTPOOL}-backup3 $SRCPOOL@${DESTPOOL}-backup2

#echo 
echo "Most recent source backup snapshots (in this series):"
/sbin/zfs list -r -t snapshot -o creation,space "$SRCPOOL@${DESTPOOL}-backup2"
echo 
echo "Oldest source backup snapshots (in this series):"
/sbin/zfs list -r -t snapshot -o creation,space "$SRCPOOL@${DESTPOOL}-backup.olddelete"
echo 

# do the send
echo "Sending the snapshot to $DESTPOOL"
# send all snaps from  $SRCPOOL@${DESTPOOL}-backup1 to $SRCPOOL@${DESTPOOL}-backup2, Replicate all and be verbose
# recv all snaps, Force roll back to most recent snap ( undo changes) and cleanup any un-included snaps.
# strip off source pool name on receiving end, substitute destination pool name.
/sbin/zfs send  -e -R -I $SRCPOOL@${DESTPOOL}-backup1 $SRCPOOL@${DESTPOOL}-backup2 | zfs recv -v -d -F $DESTPOOL

# error? don't delete then

# release old one for deleting
echo
echo "Releasing $SRCPOOL@${DESTPOOL}-backup.olddelete "
/sbin/zfs release -r ${DESTPOOL}-backup $SRCPOOL@${DESTPOOL}-backup.olddelete

echo "To run this again, destroy $SRCPOOL@${DESTPOOL}-backup.olddelete"
echo "#  /sbin/zfs  destroy -r $SRCPOOL@${DESTPOOL}-backup.olddelete "
echo ""
echo "Now SANITY check for files in tree below, as sometimes there are no files:"
echo "(Sometimes a DETACH / ATTACH pool cycle will restore the files. Huh? Why?)"
echo "You could ls -l FavoriteDirctory | wc ; and see how many files exist. Change below to match"
echo "Better be 3 below "
echo "ls /mnt/$DESTPOOL/test/datas1 | /usr/bin/wc"
ls /mnt/$DESTPOOL/test/datas1 | /usr/bin/wc
echo "I think there were about 123 files under test, are there still?"
/usr/bin/find /mnt/$DESTPOOL/test | /usr/bin/wc
echo "Listing of snapshots we have:"
/sbin/zfs list -r -t snapshot -o creation,space $DESTPOOL $SRCPOOL
cat <<eotext

If there were problems, you can rollback to some date,
# zfs rollback -r $SRCPOOL@${DESTPOOL}-backup.olddelete
(unfortunately each descendant must be rolled back separately)
or if it is the backup, recreate the backup, try again, eg:
batch
zfs send -R  $SRCPOOL@${DESTPOOL}-backup2 | zfs recv -d -v $DESTPOOL
eotext

date

# recover std out
exec 1>&6  
echo
echo "Tail 350 lines of $LOGFILE :"
/usr/bin/tail -n 350 $LOGFILE

exit

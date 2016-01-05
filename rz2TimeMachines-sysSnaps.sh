#!/bin/sh
# 
# FUNCTIONAL AREA OR ABSTRACT: (Shouldn't I use Perl ;>)
# 	To send file system snapshots to an offsite plugin disk for offsite storage.
#
#	How it works is something like the following:
#	
#	Get the off site storage, plug it in, and get it online. If this script is
#	installed as a Cron task (or batch it), it will eventually sense that the off-site
#	pool is attached, and try to make snapshots and move them to the
#	off-site pool. It will write its results into a log file, and cron will send an
#	email. As long as it senses that the off-site pool is attached it will
#	continue to try to make snapshots and update the on-site pool; but, it
#	cannot do this if the @backup.olddelete snapshot is present. While present this
#	sends emails every time this tries to run to the effect that you should
#	get rid of this snapshot called @backup.olddelete. When it's finished all you
#	have to do is dismount the off-site pool and bring it off-site until
#	next time.
#	
#	To prime/initialize (very important) : 
#	The offsite zpool dataset should be a complete replication stream package, 
#	which will replicate the
#	specified  filesystem,  and  all descendant file systems, up to
#	the named snapshot. When received, all  properties,  snapshots,
#	descendent file systems, and clones are preserved.
#	Create with something like:
#		batch
#		zfs send -R sourcepool/dataset@backup2 | zfs recv -d -v destPool
#		control D
#	should replicate the original file system. The script should be edited,
#	to match your environment/pool names, etc.
#	Why batch? you don't want your computer going to sleep during a ssh long task.
#	START WITH A TEST DATASET FIRST! MAKE SURE YOU HAVE THINGS CORRECT!!!
#	Then this script can be added to cron tasks or enter the batch command
#	followed by the complete? script filename.
# 
# ENVIRONMENT/PROJECT:
# 	freenas server
# 
# MODIFIED BY:
# VERS	DATE		AUTH.	REASON
# 1.0	3/9/14		GSB	Original
# 2.0	6/3/14		gb	logfile, cron/batch
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

# ENVIRONMENT VALUES, for me, rz2/data src, offsite pool sink
# Change these for your datasets, but always have a "test" dataset for testing things
# first. Maybe useful after an upgrade, new hardware, etc.
# I also rename this script to reflect the source pool I am backing up.
SRCPOOL="rz2/TimeMachines/sysSnaps"
DESTPOOL="offsite"
LOGFILE="/var/log/zfssnapup.log"

# first check if plugged in, if not, no errs, no output
if  ! /sbin/zfs list  $DESTPOOL 1>/dev/null 2>/dev/null 
then
	exit	
fi

# am I root? -ne is integer != string
username=`whoami`
if [  "$username" != "root" ] 
then
	errmsg "You must be root to do this! "
fi

# lets use a logfile for output
#exec 6>&1           # Link file descriptor #6 with stdout.
exec >> $LOGFILE     # stdout replaced with file
echo
echo "New run...."
date
echo "Source dataset is $SRCPOOL, and it will be sent to $DESTPOOL"

# 0 is true of course!
if   /sbin/zfs list  -t snapshot $SRCPOOL@backup.olddelete 1>/dev/null 2>/dev/null  
then
	errmsg "You must destroy $SRCPOOL@backup.olddelete (and decendents) first!	# /sbin/zfs destroy -r  $SRCPOOL@backup.olddelete "
fi

# BEGIN
# make new snap
echo "Making new recursive snapshot of all $SRCPOOL datasets"
# Recursively  create snapshots of	all descendent datasets.
/sbin/zfs snapshot -r $SRCPOOL@backup3

echo "Holding this backup snapshot $SRCPOOL@backup3 "
/sbin/zfs hold -r backup $SRCPOOL@backup3

# rename the snapshots
echo "Renaming the snapshots "
/sbin/zfs rename -r $SRCPOOL@backup1 $SRCPOOL@backup.olddelete
/sbin/zfs rename -r $SRCPOOL@backup2 $SRCPOOL@backup1
/sbin/zfs rename -r $SRCPOOL@backup3 $SRCPOOL@backup2

echo "Most recent source backup snapshots:"
/sbin/zfs list -r -t snapshot -o creation,space "$SRCPOOL@backup2"

echo "Oldest source backup snapshots:"
/sbin/zfs list -r -t snapshot -o creation,space "$SRCPOOL@backup.olddelete"

# do the send
echo "Sending the snapshot to $DESTPOOL"
# send all snaps from  $SRCPOOL@backup1 to $SRCPOOL@backup2, Replicate all and be verbose
# recv all snaps, Force roll back to most recent snap ( undo changes) and cleanup any un-included snaps.
/sbin/zfs send -v -R -I $SRCPOOL@backup1 $SRCPOOL@backup2 | zfs recv -v -d -F $DESTPOOL

# error? don't delete then

# release old one for deleting
echo "Releasing $SRCPOOL@backup.olddelete "
/sbin/zfs release -r backup $SRCPOOL@backup.olddelete

echo "If all is well, you could NOW destroy $SRCPOOL@backup.olddelete"
echo "#  /sbin/zfs  destroy -r $SRCPOOL@backup.olddelete "
echo ""
echo "Now check for files in tree below, as sometimes there are no files:"
echo "You could ls -l FavoriteDirctory | wc ; and see how many files exist. Change below to match"
echo "Better be 45 below "
ls /mnt/offsite/data/gb | /usr/bin/wc
#echo "I there was about 45 files under test, are there still?"
#/usr/bin/find /mnt/offsite/test | /usr/bin/wc
/sbin/zfs list -r $DESTPOOL
cat <<eotext

If there were problems, you can rollback to some date,
# zfs rollback -r $SRCPOOL@backup.olddelete
or if it is the backup, recreate the backup, try again, eg:
batch
zfs send -R  $SRCPOOL@backup2 | zfs recv -d -v $DESTPOOL
eotext

date
exit

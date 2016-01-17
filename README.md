freenasstuff
============

Backup scripts etc.

### NAME
testzfssnapup.sh - Send dataset to a backup pool(s)

rz2datazfssnapup.sh

###SYNOPSIS
 ./path/testzfssnapup.sh [backup]
###DESCRIPTION
Will snapshot the dataset recursively, then send an incremental replication stream to an attached backup pool of several backup pools, providing a backup of that dataset on a different pool(s). It will not do anything if the dataset has an old snapshot named   -backup.olddelete, which should be destroyed and then one can re-run the script. The optional parameter "backup" will do this in one invocation. It also sends its output to a log file, for a record of what happened.
###NOTES
This can be used in several ways. The script must be read, and edited. The script has instructions on how to set up the destination pool.

If invoked via a cron table, it will sense the presence of the destination pool and attempt to proceed, but may be blocked by the presense of the old snapshot named XXX-backup.olddelete. This allows manual control of when backups happen. If the "backup" parameter is given, then it will do the backup at each invocation.

Because it can work with several destination pools, one can leave one destination pool attached and periodically update the desitnation pool. Then detach, take the media(s) offsite and swap with a second destination pool. Rinse, repeat.
###HOMEPAGE
https://github.com/gitgb/freenasscripts
###SEE ALSO
The man pages for all of the zfs commands used in this script.
The script is faily well documented as well.

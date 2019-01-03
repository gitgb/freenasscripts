#!/bin/sh          
# 
# FUNCTIONAL AREA OR ABSTRACT: (Shouldn't I use Perl ;>)
# 	A script that freenas system should run prior to shutting itself down.
# 
# ENVIRONMENT/PROJECT:
# 	freenas controls power shutdown of other servers, server followed by router 
# 
# MODIFIED BY:
# VERS	DATE		AUTH.	REASON
# 1.0	3/24/18		GSB	Original
# 
# 
# !-*/

#if test $# -le 1;  then echo "`basename $0`: $@" 1>&2; cat <<eoerrmsg >&2
#++ %W%	%E%  this does take <##> parms and <##>
# par 1 - <##>
#par 2 - <##>
#
#eoerrmsg
#exit 1
#fi

# error message function
errmsg () {
	echo "`basename $0`: $@" 1>&2
exit 1
}

dbg () {
	debug=1
	if [ $debug -eq 1 ] 
	then
		echo $1
	fi
}

amiroot () { #well ?
	if [ `whoami` != "root" ]
	then
	errmsg "You must be root to run this!"
	fi
}

#amiroot 

# Freenas is powering down, lets issue commands to power off other servers.

#sudoers has:
#powerdown ALL=(ALL) /sbin/shutdown, /sbin/reboot
ssh powerdown@lserver sudo /sbin/shutdown -p now

# wait a few seconds for lserver to cleanup, shutdown
sleep 30

# Next halt the router:
ssh powerdown@router sudo /etc/rc.halt
sleep 10

exit



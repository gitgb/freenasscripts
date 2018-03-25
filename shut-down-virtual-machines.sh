#!/bin/bash

################################################################################
# Usage: shut-down-virtual-machines.sh user_id esxi_host_name datastore_name
#
# Gracefully powers down all guest virtual machines in a particular datastore (datastore_name)
# on remote VMware ESXi server (esxi_host_name) using given user credentials (user_id).
#
# VMware tools must be installed on the guest VMs; otherwise we can't power them down
# gracefully with the 'shut down' feature.
# 
# Sends commands to the remote ESXi host using SSH, which must be configured before
# using this script.
#
# The datastore name is forced to uppercase, as this seems to be the norm for ESXi.
#
# This script is handy for users running FreeNAS virtualised on VMware ESXi. In this
# scenario, FreeNAS is homed on a local datastore different from the datastore(s) it 
# provides to ESXi. So this script can safely be used to shut down all of the VM guests
# on the FreeNAS datastore(s) without shutting down FreeNAS itself, thus enabling backing
# up the VM files while they are in a quiescent state.
#
# Borrows heavily from the 'ESXi Auto Shutdown Script' available on GitHub:
#
# https://github.com/sixdimensionalarray/esxidown
#
# Tested with FreeNAS 9.3 (STABLE) running as a VM on VMware ESXi v6.0 
################################################################################

# Check for usage errors

if [ $# -ne 3 ]
then
   echo "$0: error! Not enough arguments"
   echo "Usage is: $0 user_id esxi_host_name datastore_name"
   exit 1
fi

# Test flag: set to 1 to prevent the script from shutting VM guests down.
L_TEST=0

# Gather command-line arguments for user ID, hostname, and datastore name:

L_USER=$1
L_HOST=$2
L_DATASTORE=$3
L_DATASTORE=${L_DATASTORE^^}

# L_WAIT_TRYS determines how many times the script will loop while attempting to power down a VM.
# L_WAIT_TIME specifies how many seconds to sleep during each loop.

L_WAIT_TRYS=30
L_WAIT_TIME=6

# MAX_WAIT is the product of L_WAIT_TRYS and L_WAIT_TIME, i.e., the total number of seconds we will
# wait before gracelessly forcing the power off.

MAX_WAIT=$((L_WAIT_TRYS*L_WAIT_TIME))

# For tests, force the retry max count to 1
if [ $L_TEST -eq 1 ]; then
  L_WAIT_TRYS=1
fi

# Record keeping:

L_TOTAL_VMS=0
L_TOTAL_VMS_SHUTDOWN=0
L_TOTAL_VMS_POWERED_DOWN=0

# Get server IDs for all VMs stored on the indicated datastore. These IDs change between
# boots of the ESXi server, so we have to work from a fresh list every time. We are only
# interested in the guests stored in '[DATASTORE]' and the brackets are important.

L_GUEST_VMIDS=$(ssh ${L_USER}@${L_HOST} vim-cmd vmsvc/getallvms | grep "\[${L_DATASTORE}\]" | awk '$1 ~ /^[0-9]+$/ {print $1}')

echo "$(date): $0 $L_USER@$L_HOST datastore=$L_DATASTORE Max wait time=$MAX_WAIT seconds"
echo "Full list of VM guests on this server:"
ssh ${L_USER}@${L_HOST} vim-cmd vmsvc/getallvms

echo "VM guests on datastore ${L_DATASTORE}:"
ssh ${L_USER}@${L_HOST} vim-cmd vmsvc/getallvms | grep "\[${L_DATASTORE}\]"

# Function for validating shutdown

validate_shutdown()
{
  ssh ${L_USER}@${L_HOST} vim-cmd vmsvc/power.getstate $L_VMID | grep -i "off" > /dev/null 2<&1
  L_SHUTDOWN_STATUS=$?

  if [ $L_SHUTDOWN_STATUS -ne 0 ]; then
    if [ $L_TRY -lt $L_WAIT_TRYS ]; then
      # if the vm is not off, wait for it to shut down
      L_TRY=$((L_TRY + 1))
      if [ $L_TEST -eq 0 ]; then
        echo "Waiting for guest VM ID $L_VMID to shutdown (attempt $L_TRY of $L_WAIT_TRYS)..."
        sleep $L_WAIT_TIME
      else
        echo "TEST MODE: Waiting for guest VM ID $L_VMID to shutdown (attempt $L_TRY of $L_WAIT_TRYS)..."
      fi
      validate_shutdown
    else
      # force power off and wait a little (you could use vmsvc/power.suspend here instead)
      L_TOTAL_VMS_POWERED_DOWN=$((L_TOTAL_VMS_POWERED_DOWN + 1))
      if [ $L_TEST -eq 0 ]; then
        echo "Unable to gracefully shutdown guest VM ID $L_VMID... forcing power off."
        ssh ${L_USER}@${L_HOST} vim-cmd vmsvc/power.off $L_VMID
        sleep $L_WAIT_TIME
      else
        echo "TEST MODE: Unable to gracefully shutdown guest VM ID $L_VMID... forcing power off."
      fi
    fi
  else
    echo "Guest VM ID $L_VMID is powered down..."
    L_TOTAL_VMS_SHUTDOWN=$((L_TOTAL_VMS_SHUTDOWN + 1))
  fi
}

# Iterate over the list of guest VMs, shutting down any that are powered up

for L_VMID in $L_GUEST_VMIDS
do
  L_TRY=0
  L_TOTAL_VMS=$((L_TOTAL_VMS + 1))

  ssh ${L_USER}@${L_HOST} vim-cmd vmsvc/power.getstate $L_VMID | grep -i "off\|Suspended" > /dev/null 2<&1
  L_SHUTDOWN_STATUS=$?

  if [ $L_SHUTDOWN_STATUS -ne 0 ]; then
    if [ $L_TEST -eq 0 ]; then
      echo "Attempting shutdown of guest VM ID $L_VMID..."
      ssh ${L_USER}@${L_HOST} vim-cmd vmsvc/power.shutdown $L_VMID
    else
      echo "TEST MODE: Attempting shutdown of guest VM ID $L_VMID..."
    fi
    validate_shutdown
  else
    echo "Guest VM ID $L_VMID already powered down..."
  fi
done

echo "Found $L_TOTAL_VMS virtual machine guests on $L_HOST datastore $L_DATASTORE"
echo "   Total shut down: $L_TOTAL_VMS_SHUTDOWN" 
echo "Total powered down: $L_TOTAL_VMS_POWERED_DOWN" 
echo "$(date): $0 completed"

exit


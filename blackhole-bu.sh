#!/bin/bash
#

chefvm="chef-server"
chefip="169.254.123.2"
vmdiskloc="/opt/rpcs/chef-server.qcow2"
backupdir="/backups/"


#check to see if chef-server VM is running and shut it down.

if ps auwx | grep $chefvm | grep -v grep | awk {'print $21'} | grep $chefvm >/dev/null
then
  while ps auwx | grep $chefvm | grep -v grep | awk {'print $21'} | grep $chefvm >/dev/null
  do
    echo "Shutting down $chefvm VM"
    ssh rack@$chefip 'sudo shutdown -h now'
    sleep 10
  done
else
  echo "Chef server VM not running, doing nothing"
fi

#install virtinst if needed, make the backup dir if needed, and clone/compress the chef VM

if [ -f $vmdiskloc ]
then
  if ! dpkg -l | grep virtinst
  then
    apt-get update && apt-get install -y virtinst >/dev/null
  fi
  if [ ! -d $backupdir ]
  then
    mkdir -p $backupdir
  fi

  virt-clone -o $chefvm -n $chefvm-backup -f $backupdir$chefvm-backup.qcow2  
  bzip2 -c $backupdir$chefvm-backup.qcow2

else
  "Chef server VM not found!"
  exit 1 
fi


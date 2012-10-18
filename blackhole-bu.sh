#!/bin/bash
#
#
chefvm="chef-server"
chefip="169.254.123.2"
vmdiskloc="/opt/rpcs/chef-server.qcow2"
backupdir="/backups/"
#mins="10080"
mins="1"

#backup chef vm

if ps auwx | grep $chefvm | grep -v grep | awk {'print $21'} | grep $chefvm >/dev/null
then
  if find $backupdir -name $chefvm* -mmin +$mins
  then
    while ps auwx | grep $chefvm | grep -v grep | awk {'print $21'} | grep $chefvm >/dev/null
    do
      echo "Shutting down $chefvm VM"
      ssh rack@$chefip 'sudo shutdown -h now'
      sleep 10
    done
    if [ -f $vmdiskloc ]
    then
      if [ ! -d $backupdir ]
      then
        echo "$backupdir does not exist, creating."
        mkdir -p $backupdir
      fi
      echo "Copying Chef VM and compressing the image. This may take some time."
      cat $vmdiskloc | gzip > $backupdir$chefvm-backup.qcow2.gz
      echo "Starting $chefvm"
      virsh start $chefvm >/dev/null
  else
    "Chef server VM not found!"
    exit 1 
  fi
  else
    echo "VM newer than $mins minutes old, skipping."
else
  echo "Chef server VM not running, doing nothing"
fi

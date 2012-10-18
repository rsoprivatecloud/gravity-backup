#!/bin/bash
#
#

#Tunable options##############################################

#Name of the VM running Chef-Server
chefvm="chef-server"

#Internal IP for the Chef Server VM
chefip="169.254.123.2"

#Location of VM's disk
vmdiskloc="/opt/rpcs/chef-server.qcow2"

#Backup directory to dump backed up files
backupdir="/backups/"

#Number of minute before removing old backup files and rerunning the backup
# 1 day = 1440
# 1 week = 10080
# 30 days = 43200
mins="300"

################################################################


#backup chef server VM
if [ ! -d $backupdir ]
then
  echo "$backupdir does not exist, creating."
  mkdir $backupdir
fi
filetyme=""
filetyme=$(find /backups/ -name '*qcow2.gz' -mmin +$mins)
buexist=""
buexist=$(find /backups/ -name '*qcow2.gz')
if [ "$buexist" = "$filetyme" ] 
then
  if ps auwx | grep $chefvm | grep -v grep | awk {'print $21'} | grep $chefvm >/dev/null
  then
    while ps auwx | grep $chefvm | grep -v grep | awk {'print $21'} | grep $chefvm >/dev/null
    do
      echo "Shutting down $chefvm VM."
      ssh rack@$chefip 'sudo shutdown -h now'
      sleep 10
    done
    if [ -f $vmdiskloc ]
    then
      echo "Copying Chef VM and compressing the image. This may take some time."
      cat $vmdiskloc | gzip > $backupdir$chefvm-backup.qcow2.gz
      echo "Starting $chefvm VM."
      virsh start $chefvm >/dev/null
      echo -e "$chefvm VM backup complete! Find it here: $backupdir$chefvm-backup.qcow2.gz"
    else
      echo "$vmdiskloc does not exist!"
      exit 1
    fi
  else
    echo "Chef server VM not running, doing nothing."
  fi
else
   echo "$chefvm VM backup newer than $mins minutes, skipping."
fi

#get chef config files

while ! ssh -q rack@$chefip 'hostname' >/dev/null
do
  echo "Waiting for Chef VM to start..."
  sleep 10
done

if ssh rack@$chefip "find /home/rack/ -name  chef-backup-* -mmin $mins" >/dev/null
then
  echo "Shutting down chef-server and couchdb."
  ssh rack@$chefip 'sudo service chef-server stop; sudo service couchdb stop; sudo service chef-expander stop' >/dev/null 
  echo "Removing old Chef backup."
  ssh rack@$chefip "rm -rf /home/rack/chef-backup-*"
  rm -rf $backupdir"chef-backup-*"
  echo "Creating new Chef backup. This may take some time."
  ssh rack@$chefip 'sudo tar czPf chef-backup-`date +%Y-%m-%d-%s`.tar.gz /etc/couchdb /var/lib/chef /var/lib/couchdb /var/cache/chef /var/log/chef /var/log/couchdb /etc/chef'
  echo "Copying Chef backup to $backupdir"
  scp -q rack@$chefip:/home/rack/chef-backup-* $backupdir
  echo "Starting chef-server and couchdb."
  ssh rack@$chefip 'sudo service chef-server start; sudo service couchdb start; sudo service chef-expander start' >/dev/null
  echo "Chef file and couchdb backup complete. Find it here: `ls $backupdir'chef-backup-'*`"
else
  echo "Chef file backup newer than $mins minutes, skipping."
fi


 

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

#Location of VM's XML file

vmxmlloc="/opt/rpcs/chef-server.xml"

#Backup directory to dump backed up files
backupdir="/backups"

#Number of minutes before removing old backup files and rerunning the backup
# 1 day = 1440
# 1 week = 10080
# 30 days = 43200
mins="300"

#Topics to backup for chef

topics="node environment client role cookbook" # "client role cookbook"

################################################################


#backup chef server VM
if [ ! -d $backupdir ]
then
  echo "$backupdir does not exist, creating."
  mkdir $backupdir
fi

echo '#################################################################'

filetyme=""
filetyme=$(find $backupdir -name '*qcow2.gz' -mmin +$mins)
buexist=""
buexist=$(find $backupdir -name '*qcow2.gz')
stats=0

if [ "$buexist" = "$filetyme" ] 
then
  if ps auwx | grep $chefvm | grep -v grep | awk {'print $21'} | grep $chefvm >/dev/null
  then
    while ps auwx | grep $chefvm | grep -v grep | awk {'print $21'} | grep $chefvm >/dev/null
    do
      echo "Shutting down $chefvm VM."
      stats=$[ $stats + 1 ]
      if [ "$stats" == "10" ]
      then
        echo "$chefvm not shutting down! $chefvm not backup up!"
        break 4
      fi
      ssh -q rack@$chefip 'sudo shutdown -h now'
      sleep 5
    done
    if [ -f $vmdiskloc ]
    then
      if [ -f $vmxmlloc ]
      then
        echo "Copying Chef VM XML file to $backupdir"
        cp -a $vmxmlloc $backupdir
      else
        echo "Did not find Chef VM XML file! Skipping."
        break
      fi
      echo "Copying Chef VM and compressing the image. This may take some time."
      cat $vmdiskloc | gzip > $backupdir/$chefvm-backup.qcow2.gz
      echo "Starting $chefvm VM."
      virsh start $chefvm >/dev/null
      echo -e "$chefvm VM backup complete! Find it here: $backupdir/$chefvm-backup.qcow2.gz"
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

echo '#################################################################'

stats=0

while ! ssh -q rack@$chefip 'hostname' >/dev/null
do
  stats=$[ $stats + 1 ]
  if [ "$stats" == "10" ]
  then
    echo "$chefvm not starting, please investigate!"
    exit 1
  fi
  echo "Waiting for Chef VM to start..."
  sleep 5
done

if ssh rack@$chefip "find /home/rack/ -name  chef-backup-* -mmin $mins" >/dev/null
then
  echo "Shutting down chef-server and couchdb."
  ssh rack@$chefip 'sudo service chef-server stop; sudo service couchdb stop; sudo service chef-expander stop; sudo service chef-client stop; sudo service chef-server-webui stop; sudo service chef-solr stop' >/dev/null 
  echo "Removing old Chef backup."
  ssh rack@$chefip "rm -rf /home/rack/chef-backup-*"
  rm -rf $backupdir/"chef-backup-*"
  echo "Creating new Chef backup. This may take some time."
  ssh rack@$chefip 'sudo tar czPf chef-backup-`date +%Y-%m-%d`.tar.gz /etc/couchdb /var/lib/chef /var/lib/couchdb /var/cache/chef /var/log/chef /var/log/couchdb /etc/chef'
  echo "Copying Chef backup to $backupdir/."
  scp -q rack@$chefip:/home/rack/chef-backup-* $backupdir/
  echo "Starting chef-server and couchdb."
  ssh rack@$chefip 'sudo service chef-server start; sudo service couchdb start; sudo service chef-expander start; sudo service chef-client start; sudo service chef-server-webui start; sudo service chef-solr start' >/dev/null
  echo "Chef file and couchdb backup complete. Find it here: `ls $backupdir'/chef-backup-'*`"
else
  echo "Chef file backup newer than $mins minutes, skipping."
fi

#dump chef details to flat files

echo '#################################################################'

if knife node list >/dev/null
then
  set -e
  declare -A flags
  flags=([default]=-Fj [node]=-lFj)
  for topic in $topics 
  do
    outdir=$backupdir/$topic
    flag=${flags[${topic}]:-${flags[default]}}
    rm -rf $outdir
    mkdir -p $outdir
    echo "Dumping $topic data to json in $outdir."
    for item in $(knife $topic list | awk {'print $1'}) 
    do
      if [ "$topic" != "cookbook" ] 
      then
        knife $topic show $flag $item > $outdir/$item.json
      else
        knife cookbook download $item -N --force -d $outdir >/dev/null
      fi
    done
  done
else
  echo "knife not working or chef server not responding!"
  exit 1
fi

echo "Backup located in $backupdir."

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
backupdir="/backup"
#Number of minutes before removing old backup files and rerunning the backup
# 1 day = 1440
# 1 week = 10080
# 30 days = 43200
mins="300"
#Topics to backup for chef
topics="node environment client role cookbook" # "client role cookbook"
################################################################
#Author: rpawlik@rackspace.com

usage()
{
cat << EOF
usage: $0 options

This script backs up the Rackspace Chef server VM for Openstack deployments using three methods. In the first method, it shuts down and copies the VM disk to $backupdir. The second method logs into the VM and copies import directories for Chef and couchdb, it places the files in $backupdir. Finally, it dumps the specified chef configs to json in $backupdir.

OPTIONS:
-h Show this message
-a Does every backup method.
-v Backs up the VM image and XML file.
-f Backs up the actual Chef and couchdb files.
-d Dumps the Chef configs to JSON and downloads all cookbooks.
-c Compact couchdb database
-q Quiet

EXAMPLE:
sh $0 -a -q
EOF
}

FULL=
VMBACK=
FILEBACK=
CHEFDUMP=
QUIET=
COUCHDB=

while getopts "havfdcq" OPTION
do
        case $OPTION in
                h)
                  usage
                  exit 1
                  ;;
                a)
                  FULL="1"
                  ;;
                v)
                  VMBACK="1"
                  ;;
                f)
                  FILEBACK="1"
                  ;;
                d)
                  CHEFDUMP="1"
                 ;;
		c)
		  COUCHDB="1"
		 ;;
		q)
		  QUIET="1"
		 ;;
                                                                                                                                           
        esac
done

if [ -z $FULL ] && [ -z $VMBACK ] && [ -z $FILEBACK ] && [ -z $CHEFDUMP ] && [ -z $COUCHDB ]
then
  echo "Please specify a valid option!"
  usage
  exit 1
fi

printext () 
{

if [ ! "$QUIET" = "1" ]
then
  echo "$*"
fi

}

compactdb ()
{
printext "Compacting couchdb database."
ssh -q rack@$chefip 'curl -S -s  -H "Content-Type: application/json" -X POST http://localhost:5984/chef/_compact' >/dev/null
 
while ssh  rack@$chefip "curl -S -s http://localhost:5984/chef" | grep '"compact_running":true' >/dev/null
do
  sleep 5
done
}

if [[ -n $FULL ||  -n $VMBACK  ||  -n $FILEBACK  ||  -n $CHEFDUMP ]]
then
  if [ ! -d $backupdir ]
  then
    printext "$backupdir does not exist, creating."
    mkdir $backupdir
  fi
fi

#backup chef VM

if [ "$FULL" = "1" ] || [ "$VMBACK" = "1" ]
then
  filetyme=""
  filetyme=$(find $backupdir -name '*.tar' -mmin +$mins)
  buexist=""
  buexist=$(find $backupdir -name '*.tar')
  stats=0
  if [ "$buexist" = "$filetyme" ] 
  then
    if ps auwx | grep $chefvm | grep -v grep | awk {'print $21'} | grep $chefvm >/dev/null
    then
      while ps auwx | grep $chefvm | grep -v grep | awk {'print $21'} | grep $chefvm >/dev/null
      do
        printext "Shutting down $chefvm VM."
        stats=$[ $stats + 1 ]
        if [ "$stats" == "10" ]
        then
          echo "$chefvm not shutting down! $chefvm not backed up!"
          break 4
        fi
        ssh -q rack@$chefip 'sudo shutdown -h now'
        sleep 5
      done
      if [ -f $vmdiskloc ]
      then
        if [ -f $vmxmlloc ]
        then
          cp -a $vmxmlloc $backupdir
        else
          printext "Did not find Chef VM XML file! Skipping."
        fi
        printext "Copying Chef VM and compressing the image. This may take some time."
        cat $vmdiskloc | gzip > $backupdir/$chefvm-backup.qcow2.gz
        printext "Starting $chefvm VM."
        virsh start $chefvm >/dev/null
        printext "Archiving VM backup."
        tar cPf $backupdir/chef-VM-backup-`date +%Y-%m-%d`.tar $backupdir/$chefvm-backup.qcow2.gz $backupdir/*.xml >/dev/null
        rm -rf $backupdir/$chefvm-backup.qcow2.gz $backupdir/*.xml
        printext "$chefvm VM backup complete! Find it here: $backupdir/chef-VM-backup-`date +%Y-%m-%d`.tar"
        stats=0
        while ! ssh -q rack@$chefip 'hostname' >/dev/null
        do
          stats=$[ $stats + 1 ]
          if [ "$stats" == "10" ]
          then
            echo "$chefvm not starting, please investigate!"
            exit 1
          fi
          printext "Waiting for Chef VM to start..."
          sleep 5
        done
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
fi

#get chef config files

if [ "$FULL" = "1" ] || [ "$FILEBACK" = "1" ]
then
  filetyme=""
  filetyme=$(find $backupdir -name 'chef-backup-*.tar.gz' -mmin +$mins)
  buexist=""
  buexist=$(find $backupdir -name 'chef-backup-*.tar.gz')
  if [ "$buexist" = "$filetyme" ]
  then
    compactdb
    printext "Shutting down chef-server and couchdb."
    ssh rack@$chefip 'sudo service chef-server stop; sudo service couchdb stop; sudo service chef-expander stop; sudo service chef-client stop; sudo service chef-server-webui stop; sudo service chef-solr stop' >/dev/null 
    printext "Removing old Chef backup (if it exists)."
    ssh rack@$chefip "rm -rf /home/rack/chef-backup-*"
    rm -rf $backupdir/"chef-backup-*"
    printext "Creating new Chef backup. This may take some time."
    ssh -q rack@$chefip 'sudo tar czPf chef-backup-`date +%Y-%m-%d`.tar.gz /etc/couchdb /var/lib/chef /var/lib/couchdb /var/cache/chef /var/log/chef /var/log/couchdb /etc/chef' >/dev/null
    printext "Copying Chef backup to $backupdir/."
    scp -q rack@$chefip:/home/rack/chef-backup-* $backupdir/
    printext "Removing temporary backup file."
    ssh -q rack@$chefip "rm -rf /home/rack/chef-backup-*"
    printext "Starting chef-server and couchdb."
    ssh rack@$chefip 'sudo service chef-server start; sudo service couchdb start; sudo service chef-expander start; sudo service chef-client start; sudo service chef-server-webui start; sudo service chef-solr start' >/dev/null
    printext "Chef file and couchdb backup complete! Find it here: `ls $backupdir'/chef-backup-'*`"
  else
    echo "Chef file backup newer than $mins minutes, skipping."
  fi
fi

#dump chef details to flat files

if [ "$FULL" = "1" ] || [ "$CHEFDUMP" = "1" ]
then
  if knife node list >/dev/null
  then
    filetyme=""
    filetyme=$(find $backupdir -name 'chef-dump-*.tar.gz' -mmin +$mins)
    buexist=""
    buexist=$(find $backupdir -name 'chef-dump-*.tar.gz')
    if [ "$buexist" = "$filetyme" ]
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
        printext "Dumping $topic data."
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
      printext "Archiving and compressing data."
      set -e
      for each in $topics
      do
        tar czPf $backupdir/chef-dump-$each-`date +%Y-%m-%d`.tar.gz $backupdir/$each
        rm -rf $backupdir/$each
        printext "$each backup located here: $backupdir/chef-dump-$each-`date +%Y-%m-%d`.tar.gz"
      done
    else
      echo "Chef dump backup newer than $mins minutes, skipping."
    fi
  else
    echo "knife not working or chef server not responding!"
    exit 1
  fi
fi

#Compact couchdb only

if [ "$COUCHDB" = "1" ]
then
  compactdb
fi  


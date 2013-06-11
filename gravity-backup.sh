#!/bin/bash
#
# Author: Ramsey Pawlik (rpawlik@rackspace.com)
# Modified: June 11, 2013 / Steven Deaton (steven.deaton@rackspace.com)
#

#CONF="/etc/default/gravity-backup.conf";
CONF="./gravity-backup.conf";

if [ -r ${CONF} ]; then
    . ${CONF}
else
    echo "The configuration file (${CONF}) was not found.";
    echo "Please ensure this file exists and is properly formatted.";
    exit;
fi

usage() {
    echo "";
    echo -e "\e[1;37m$0 \e[37m<\e[33moption(s)\e[37m>";
    echo "";
    echo "Summary:";
    echo "This script backs up the Rackspace Chef server VM for OpenStack";
    echo "deployments using three methods.";
    echo "";
    echo "Method 1: Shutdown / copy the VM disk to ${backupdir}.";
    echo "Method 2: Log into VM, copy important files/directories for Chef";
    echo "and CouchDB into the ${backupdir} directory.";
    echo "Method 3: Dump specified Chef configuration data (in JSON format)";
    echo "to the ${backupdir} directory.";
    echo "";
    echo "NOTE: This script needs a configuration files at: ${CONF}";
    echo "An example configuration file is included.";
    echo "";
    echo "Available options:";
    echo "";
    echo -e "\t\e[37m-a\t\e[33m=\t\e[37mBackup using all available methods.";
    echo -e "\t\e[37m-c\t\e[33m=\t\e[37mCompact CouchDB database. [DEPRECATED]";
    echo -e "\t\e[37m-d\t\e[33m=\t\e[37mDump Chef configuration data in JSON format.";
    echo -e "\t\e[37m-f\t\e[33m=\t\e[37mBackup Chef and CouchDB files.";
    echo -e "\t\e[37m-h\t\e[33m=\t\e[37mShow this message and exit.";
    echo -e "\t\e[37m-i\t\e[33m=\t\e[37mBackup Chef VM image and related XML file.";
    echo -e "\t\e[37m-q\t\e[33m=\t\e[37mLower verbosity / be more quiet.";
    echo "";
    echo "Example:";
    echo "$0 -a -q";
    # Reset color and formatting attributes.
    echo -e "\e[0m";
    exit;
}

FULL="";
VMBACK="";
FILEBACK="";
CHEFDUMP="";
QUIET="";
COUCHDB="";

#usage;

while getopts "haifdcq" OPTION; do
        case $OPTION in
                h)
                  usage(); ;;
                a)
                  FULL="1"; ;;
                i)
                  VMBACK="1"; ;;
                f)
                  FILEBACK="1"; ;;
                d)
                  CHEFDUMP="1"; ;;
		c)
		  COUCHDB="1"; ;;
		q)
		  QUIET="1"; ;;
                *)
                 usage(); ;;
        esac
done

if [ $# -eq 0 ]; then
    echo "Please specify a valid option!"
    usage();
fi

printext() {
    if [ ! "$QUIET" = "1" ]; then
        echo "$*"
    fi
}

compactdb() {
    printext "Compacting couchdb database."
    if !  ssh -q rack@$chefip "which curl" >/dev/null
    then
        ssh rack@$chefip "sudo apt-get update && sudo apt-get install -y curl" >/dev/null
    fi
    ssh -q rack@$chefip 'curl -S -s  -H "Content-Type: application/json" -X POST http://localhost:5984/chef/_compact' >/dev/null
    while ssh  rack@$chefip "curl -S -s http://localhost:5984/chef" | grep '"compact_running":true' >/dev/null; do
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


chefdown ()
{
ssh rack@$chefip 'sudo service chef-server stop; sudo service couchdb stop; sudo service chef-expander stop; sudo service chef-client stop; sudo service chef-server-webui stop; sudo service chef-solr stop' >/dev/null
}


chefup ()
{
ssh rack@$chefip 'sudo service chef-server start; sudo service couchdb start; sudo service chef-expander start; sudo service chef-client start; sudo service chef-server-webui start; sudo service chef-solr start' >/dev/null
}


mkbudir ()
{
if [ ! -d $backupdir/`date +%Y-%m-%d` ]
then
  mkdir $backupdir/`date +%Y-%m-%d`
fi
}

# Backup chef VM
if [ "$FULL" = "1" ] || [ "$VMBACK" = "1" ]
then
  stats=0
  if ps auwx | grep $chefvm | grep -v grep  >/dev/null
  then
    while ps auwx | grep $chefvm | grep -v grep  >/dev/null
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
      if ! which pigz >/dev/null
      then
        printext "Installing pigz for compression."
        apt-get -q update && apt-get install -y -q pigz 
      fi
      printext "Copying Chef VM and compressing the image. This may take some time."
      cat $vmdiskloc | pigz -p $corenum > $backupdir/$chefvm-backup.qcow2.gz
      printext "Starting $chefvm VM."
      virsh start $chefvm >/dev/null
      printext "Archiving VM backup."
      tar cPf $backupdir/chef-VM-backup-`date +%Y-%m-%d`.tar $backupdir/$chefvm-backup.qcow2.gz $backupdir/*.xml >/dev/null
      rm -rf $backupdir/$chefvm-backup.qcow2.gz $backupdir/*.xml
      mkbudir
      mv $backupdir/chef-VM-backup-`date +%Y-%m-%d`.tar $backupdir/`date +%Y-%m-%d`
      printext "$chefvm VM backup complete! Find it here: $backupdir/`date +%Y-%m-%d`/chef-VM-backup-`date +%Y-%m-%d`.tar"
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
fi

#get chef config files

if [ "$FULL" = "1" ] || [ "$FILEBACK" = "1" ]
then
  compactdb
  if ! ssh rack@$chefip  'which pigz' >/dev/null
  then
    printext "Installing pigz for compression on Chef server."
    ssh rack@$chefip 'sudo apt-get update && sudo apt-get install -y pigz  > /dev/null 2>&1' 
  fi
  printext "Shutting down chef-server and couchdb."
  chefdown
  ssh rack@$chefip "rm -rf /home/rack/chef-backup-*"
  printext "Creating new Chef backup. This may take some time."
  ssh -q rack@$chefip "sudo tar cPf - /etc/couchdb /var/lib/chef /var/lib/couchdb /var/cache/chef /var/log/chef /var/log/couchdb /etc/chef | pigz -p $vcorenum > chef-backup-`date +%Y-%m-%d`.tar.gz" >/dev/null
  printext "Copying Chef backup to $backupdir/`date +%Y-%m-%d`/."
  mkbudir
  scp -q rack@$chefip:/home/rack/chef-backup-* $backupdir/`date +%Y-%m-%d`/
  printext "Removing temporary backup file."
  ssh -q rack@$chefip "rm -rf /home/rack/chef-backup-*"
  printext "Starting chef-server and couchdb."
  chefup
  printext "Chef file and couchdb backup complete! Find it here: $backupdir/`date +%Y-%m-%d`/chef-backup-`date +%Y-%m-%d`.tar.gz"
fi

#dump chef details to flat files

if [ "$FULL" = "1" ] || [ "$CHEFDUMP" = "1" ]
then
  if knife node list >/dev/null
  then
    set -e
    declare -A flags
    flags=([default]=-Fj [node]=-lFj)
    for topic in $topics
    do
      outdir=$backupdir/$topic
      flag=${flags[${topic}]:-${flags[default]}}
      mkdir -p $outdir
      printext "Dumping $topic data."
      for item in $(knife $topic list | awk {'print $1'}) 
      do
        knife $topic show $flag $item > $outdir/$item.js
      done
    done
    printext "Archiving and compressing data."
    set -e
    for each in $topics
    do
      tar czPf $backupdir/chef-dump-$each-`date +%Y-%m-%d`.tar.gz $backupdir/$each
      rm -rf $backupdir/$each
      mkbudir
      mv $backupdir/chef-dump-$each-`date +%Y-%m-%d`.tar.gz $backupdir/`date +%Y-%m-%d`/
      printext "$each backup located here: $backupdir/`date +%Y-%m-%d`/chef-dump-$each-`date +%Y-%m-%d`.tar.gz"
    done
  fi
else
  echo "knife not working or chef server not responding!"
  exit 1
fi

#Compact couchdb only

if [ "$COUCHDB" = "1" ]
then
  compactdb
fi  

#remove backups older than $budays

find $backupdir/* -type d -mtime +$budays -exec rm -rf {} \; > /dev/null 2>&1

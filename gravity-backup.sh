#!/bin/bash
# -------------------------
# Summary:
#
# This script backs up the Rackspace Chef Server VM for OpenStack
# deployments using three methods.
#
# The default backup directory is used here for documentation and
# explanation purposes, but is set later via the configuration file.
# BAKDIR="/var/chef-backup"
#
# Method 1: Shutdown / copy VM disk files to ${BAKDIR}.
#
# Method 2: Log into VM, copy important files/directories for Chef
# and CouchDB/PostgreSQL into the ${BAKDIR} directory.
#
# Method 3: Dump specified Chef configuration data (in JSON format)
# to the ${BAKDIR} directory.
#
# NOTE: This script needs a configuration file. An example is included.
# -------------------------
# Author: Ramsey Pawlik (rpawlik@rackspace.com)
# Last Modified: June 11, 2013 / Steven Deaton (steven.deaton@rackspace.com)
# -------------------------

###############
# Service startup scripts for Chef 11.x, that live in /opt/chef-server/init:
# bookshelf
# chef-expander
# chef-server-webui
# chef-solr
# erchef
# nginx
# postgresql
# rabbitmq
###############

CHEFDUMP=;
#CONF="/etc/default/gravity-backup.conf";
CONF="./gravity-backup.conf";
COUCHDB=;
DATE=$(date "+%Y-%m-%d");
DEBUG=0;
FILEBACK=;
FULL=;
QUIET=;
VMBACK=;

if [ -r ${CONF} ]; then
    . ${CONF}
else
    echo "The configuration file (${CONF}) was not found.";
    echo "Please ensure this file exists and is properly formatted.";
    exit;
fi

usage() {
    echo "";
    echo -e "\e[1;34mGravity Backup \e[37m(\e[33mChef Server backup utility\e[37m)";
    echo -e "\e[37m$0 \e[37m<\e[33moption(s)\e[37m>";
    echo "";
    echo "Available options:";
    echo "";
    echo -e "\t\e[37m-a\t\e[33m=\t\e[32mBackup using all available methods.";
    echo -e "\t\e[37m-c\t\e[33m=\t\e[32mCompact CouchDB database. [DEPRECATED]";
    echo -e "\t\t\tThis option (relating to CouchDB) is only valid for";
    echo -e "\t\t\tChef Server versions below 11.x, whereas after that,";
    echo -e "\t\t\tPostgreSQL is used.)";
    echo -e "\t\e[37m-d\t\e[33m=\t\e[32mDump Chef configuration data in JSON format.";
    echo -e "\t\e[37m-f\t\e[33m=\t\e[32mBackup Chef and CouchDB files.";
    echo -e "\t\e[37m-h\t\e[33m=\t\e[32mShow this message and exit.";
    echo -e "\t\e[37m-i\t\e[33m=\t\e[32mBackup Chef VM image and related XML file.";
    echo -e "\t\e[37m-p\t\e[33m=\t\e[32mBackup PostgreSQL database-dumped files.";
    echo -e "\t\e[37m-q\t\e[33m=\t\e[32mLower verbosity / be more quiet.";
    echo "";
    echo -e "\t\e[36mExample\e[37m:";
    echo -e "\t$0 -a -q";
    # Reset color and formatting attributes.
    echo -e "\e[0m";
    exit;
}

while getopts "acdfhipq" OPTION; do
        case $OPTION in
                a) FULL="1"; ;;
		c) COUCHDB="1"; ;;
                d) CHEFDUMP="1"; ;;
                f) FILEBACK="1"; ;;
                h) usage; ;;
                i) VMBACK="1"; ;;
                p) PSQL="1";
                    echo -e "\n\e[31;47m<<<<< This functionality is under development - try again later. >>>>>\e[0m";
                    usage; ;;
		q) QUIET="1"; ;;
                *) usage; ;;
        esac
done

# Do a few sanity checks ...
# - Make sure user running this is root or exit.
[ $EUID -eq 0 ] || echo "You must be root to run this script."; exit;
# - Make sure something has been passed in, as far as options go.
[ $# -gt 0 ] || usage;
# - Make sure backup directory root directory exists.
[ -d ${backupdir} ] || mkdir -p ${backupdir};
# - Make sure backup directory for today exists.
[ -d ${backupdir}/${DATE} ] || mkdir -p ${backupdir}/${DATE};
# - Check that the Chef Server VM has the key in place for the root user.
if [ ! $(ssh ${chefip} "echo $EUID";) -eq 0 ]; then
    echo "Copy the rack ssh key file to the root user's .ssh directory,";
    echo "changing perms as needed.";
    exit;
fi

printext() { [ "$QUIET" = "1" ] || echo "$*"; }

compactdb() {
    printext "Compacting couchdb database."
    if ! ssh -q $chefip "which curl" >/dev/null; then
        ssh $chefip "apt-get update && sudo apt-get install -y curl" >/dev/null
    fi
    ssh -q $chefip 'curl -S -s  -H "Content-Type: application/json" -X POST http://localhost:5984/chef/_compact' >/dev/null
    while ssh $chefip "curl -S -s http://localhost:5984/chef" | grep '"compact_running":true' >/dev/null; do
        sleep 5
    done
}

chefdown() {
    ssh $chefip 'service chef-server stop; service couchdb stop; service chef-expander stop; service chef-client stop; service chef-server-webui stop; service chef-solr stop' >/dev/null
}

chefup() {
    ssh $chefip 'service chef-server start; service couchdb start; service chef-expander start; service chef-client start; service chef-server-webui start; service chef-solr start' >/dev/null
}

# Backup chef VM
if [ "$FULL" = "1" ] || [ "$VMBACK" = "1" ]; then
    stats=0
    if ps auwx | grep $chefvm | grep -v grep  >/dev/null
    then
        while ps auwx | grep $chefvm | grep -v grep >/dev/null
        do
            printext "Shutting down $chefvm VM."
            stats=$[ $stats + 1 ]
            if [ "$stats" == "10" ]; then
                echo "$chefvm not shutting down! $chefvm not backed up!"
                break 4
            fi
            ssh -q $chefip 'sudo shutdown -h now'
            sleep 5
        done
        if [ -f $vmdiskloc ]; then
            if [ -f $vmxmlloc ]; then
                cp -a $vmxmlloc $backupdir;
            else
                printext "Did not find Chef VM XML file! Skipping."
            fi
            printext "Copying Chef VM and compressing the image. This may take some time."
            gzip < $vmdiskloc > ${backupdir}/${chefvm}-backup.qcow2.gz
            printext "Starting $chefvm VM."
            virsh start $chefvm >/dev/null
            printext "Archiving VM backup."
            tar zcPf $backupdir/chef-VM-backup-${DATE}.tgz $backupdir/$chefvm-backup.qcow2.gz $backupdir/*.xml >/dev/null
            rm -f $backupdir/$chefvm-backup.qcow2.gz $backupdir/*.xml
            mv $backupdir/chef-VM-backup-${DATE}.tar $backupdir/${DATE}/
            printext "$chefvm VM backup complete! Find it here: $backupdir/${DATE}/chef-VM-backup-${DATE}.tar"
            stats=0
            while ! ssh -q $chefip 'hostname' >/dev/null
            do
                stats=$[ $stats + 1 ]
                if [ "$stats" == "10" ]; then
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

# Get Chef configuration files.
if [ "$FULL" = "1" ] || [ "$FILEBACK" = "1" ]; then
    compactdb
    printext "Shutting down chef-server and couchdb."
    chefdown
    ssh $chefip "rm -rf /home/rack/chef-backup-*"
    printext "Creating new Chef backup. This may take some time."
    ssh -q $chefip "tar cPf - /etc/chef-server /opt/chef-server/embedded/cookbooks /var/opt/chef-server/{bookshelf,chef-expander,chef-pedant,chef-server-webui,erchef,rabbitmq}/etc /var/opt/chef-server/chef-solr/{etc,home/conf,jetty/etc,jetty/webapps/solr.war} /var/opt/chef-server/nginx/{ca,etc,html} /var/opt/chef-server/postgresql/data/*{conf,opts} /var/log/chef-server/{bookshelf,erchef,nginx}" | gzip -9 > ${backupdir}/${DATE}/chef-backup-${DATE}.tgz
    gzip -t ${backupdir}/${DATE}/chef-backup-${DATE}.tgz 2>/dev/null || echo "There is a problem with the backup file. Please re-run."; exit;
    printext "Starting chef-server and couchdb."
    chefup
    printext "Chef file and couchdb backup complete! Find it here: $backupdir/${DATE}/chef-backup-${DATE}.tgz"
fi

# Dump Chef details to flat files.
if [ "$FULL" = "1" ] || [ "$CHEFDUMP" = "1" ]; then
    if knife node list >/dev/null
    then
        set -e
        declare -A flags
        flags=([default]=-Fj [node]=-lFj)
        for topic in $topics; do
            outdir=$backupdir/$topic
            flag=${flags[${topic}]:-${flags[default]}}
            mkdir -p $outdir
            printext "Dumping $topic data."
            for item in $(knife $topic list | awk {'print $1'}); do
                knife $topic show $flag $item > $outdir/$item.js
            done
        done
        printext "Archiving and compressing data."
        set -e
        for each in $topics; do
            tar zcPf $backupdir/chef-dump-$each-${DATE}.tgz $backupdir/$each
            rm -rf $backupdir/$each
            mv $backupdir/chef-dump-$each-${DATE}.tgz $backupdir/${DATE}/
            printext "$each backup located here: $backupdir/${DATE}/chef-dump-$each-${DATE}.tgz"
        done
    fi
else
  echo "knife not working or chef server not responding!"
  exit 1
fi

# Compact couchdb only.
[ "$COUCHDB" = "1" ] && compactdb;

# Remove backups older than $budays.
find $backupdir/* -type d -mtime +$budays -exec rm -rf {} \; > /dev/null 2>&1

gravity-backup
============

Backup utility for the Openstack chef server VM. 

usage: ./gravity-backup.sh options

This script backs up the Rackspace Chef server VM for Openstack deployments using three methods. In the first method, it shuts down and copies the VM disk to /backups. The second method logs into the VM and copies import directories for Chef and couchdb, it places the files in /backups. Finally, it dumps the specified chef configs to json in /backups.

OPTIONS:

-h Show this message

-a Does every backup method.

-v Backs up the VM image and XML file.

-f Backs up the actual Chef and couchdb files.

-d Dumps the Chef configs to JSON and downloads all cookbooks.

-c Compact couchdb database

-q Quiet

EXAMPLE:
sh ./gravity-backup.sh -a -q


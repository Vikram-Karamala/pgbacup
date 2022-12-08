#!/bin/bash

###########################
####### LOAD CONFIG #######
###########################
 
while [ $# -gt 0 ]; do
        case $1 in
                -c)
                        if [ -r "$2" ]; then
                                source "$2"
                                shift 2
                        else
                                ${ECHO} "Unreadable config file \"$2\"" 1>&2
                                exit 1
                        fi
                        ;;
                *)
                        ${ECHO} "Unknown Option \"$1\"" 1>&2
                        exit 2
                        ;;
        esac
done
 
if [ $# = 0 ]; then
        SCRIPTPATH=$(cd ${0%/*} && pwd -P)
        source $SCRIPTPATH/pg_backup.config
fi;
 
###########################
#### PRE-BACKUP CHECKS ####
###########################
 
# Make sure we're running as the required backup user
if [ "$BACKUP_USER" != "" -a "$(id -un)" != "$BACKUP_USER" ]; then
	echo "This script must be run as $BACKUP_USER. Exiting." 1>&2
	exit 1;
fi;
 
 
###########################
#### START THE BACKUPS ####
###########################
 
CURRENT_DATE="`date +\%Y-\%m-\%d`"
CURRENT_DATE_WITH_TIME="`date +\%Y-\%m-\%d-\%T`"
FINAL_BACKUP_DIR=$BACKUP_DIR"$CURRENT_DATE/"
FINAL_BACKUP_NAME="_$CURRENT_DATE_WITH_TIME"
 
echo "Making backup directory in $FINAL_BACKUP_DIR"
 
if ! mkdir -p $FINAL_BACKUP_DIR; then
	echo "Cannot create backup directory in $FINAL_BACKUP_DIR. Go and fix it!" 1>&2
	exit 1;
fi;
 
#######################
### GLOBALS BACKUPS ###
#######################
 
## PING HEALTHCHECKS BEFORE STARTING BACKUP
##curl -fsS --retry 3 https://hc-ping.com/15a8af78-b3f1-4b2e-8b4f-17a86979f3f5 > /dev/null 

echo -e "\n\nPerforming globals backup"
echo -e "--------------------------------------------\n"
 
echo "ful backup"
PGPASSWORD="I@madm1n" pg_dump -Fc -v --host=iom-psql-server-evd.postgres.database.azure.com --username=psqladmin --dbname=wpodb  | gzip > $FINAL_BACKUP_DIR"globals"$FINAL_BACKUP_NAME.sql.gz.in_progress; then
mv $FINAL_BACKUP_DIR"globals"$FINAL_BACKUP_NAME.sql.gz.in_progress $FINAL_BACKUP_DIR"globals"$FINAL_BACKUP_NAME.sql.gz
 

## PING HEALTHCHECKS AFTER UPLOADING BACKUP FILES
##curl -fsS --retry 3 https://hc-ping.com/e4469c45-aeaa-4462-b535-5ba7829c6bd8 > /dev/null
echo -e "\nAll databases backup process completed successfully!."

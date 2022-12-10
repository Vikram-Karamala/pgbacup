#!/bin/bash

## export environment variable into cron env
export $(cat /root/pg_backup/env.env | xargs)

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
### INITIALISE DEFAULTS ###
###########################
 
if [ ! $HOSTNAME ]; then
	HOSTNAME="localhost"
fi;
 
if [ ! $USERNAME ]; then
	USERNAME="postgres"
fi;

if [ ! $PORT ]; then
	PORT=5432
fi;
 
 
###########################
#### START THE BACKUPS ####
###########################
 
CURRENT_DATE="`date +\%Y-\%m-\%d`"
CURRENT_DATE_WITH_TIME="`date +\%Y-\%m-\%d-\%T`"
FINAL_BACKUP_DIR=$BACKUP_DIR"$CURRENT_DATE/"
FINAL_BACKUP_NAME="_$CURRENT_DATE_WITH_TIME"
DATABASE="wpodb"
 
echo "Making backup directory in $FINAL_BACKUP_DIR"
 
if ! mkdir -p $FINAL_BACKUP_DIR; then
	echo "Cannot create backup directory in $FINAL_BACKUP_DIR. Go and fix it!" 1>&2
	exit 1;
fi; 
 
###########################
 
###########################
###### FULL BACKUPS #######
###########################
 
 
	if [ $ENABLE_CUSTOM_BACKUPS = "yes" ]
	then
		echo "Custom backup of $DATABASE"

		if ! mkdir -p $FINAL_BACKUP_DIR"$DATABASE"; then
        		echo "Cannot create backup directory in $FINAL_BACKUP_DIR'$DATABASE'. Go and fix it!" 1>&2
        		exit 1;
		fi;

		rm -rf $FINAL_BACKUP_DIR"$DATABASE/current"

		if ! mkdir -p $FINAL_BACKUP_DIR"$DATABASE/current"; then
			echo "Cannot create backup directory in $FINAL_BACKUP_DIR'$DATABASE'. Go and fix it!" 1>&2
			exit 1;
		fi;
 
		if ! pg_dump -Fc -v -h "$HOSTNAME" -U "$USERNAME" "$DATABASE" -p $PORT -f $FINAL_BACKUP_DIR"$DATABASE/current/$DATABASE"$FINAL_BACKUP_NAME.dump.in_progress; then
			echo "[!!ERROR!!] Failed to produce custom backup database $DATABASE" 1>&2
		else
			mv $FINAL_BACKUP_DIR"$DATABASE/current/$DATABASE"$FINAL_BACKUP_NAME.dump.in_progress $FINAL_BACKUP_DIR"$DATABASE/current/$DATABASE"$FINAL_BACKUP_NAME.dump
		fi
		
		
		echo -e " "
		echo -e "Sync current backup to azure blob"
		/root/pg_backup/azcopy login --service-principal --application-id f2bd6605-6ff7-427c-8f98-16de814854fc
		/root/pg_backup/azcopy copy "$FINAL_BACKUP_DIR$DATABASE/current" "$BLOB_URL/$CURRENT_DATE/$DATABASE/$BLOB_SAS"
 
		## Sync backup log & delete backup log to azure
		echo -e " "
		echo -e "Synchronizing log files to azure blob..."
		cp /var/log/cron_backup.log /var/log/pgbackup
		cp /var/log/cron_delete.log /var/log/pgbackup
		/root/pg_backup/azcopy sync "/var/log/pgbackup" "$BLOB_URL/$CURRENT_DATE/$BLOB_SAS"
		rm /var/log/pgbackup/*.log
        fi 

echo -e " "
## PING HEALTHCHECKS AFTER UPLOADING BACKUP FILES
##curl -fsS --retry 3 https://hc-ping.com/e4469c45-aeaa-4462-b535-5ba7829c6bd8 > /dev/null
echo -e "\nAll databases backup process completed successfully!."

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
 
if [ $ENABLE_GLOBALS_BACKUPS = "yes" ]
then
        echo "Globals backup"
 
        if ! PGPASSWORD="I@madm1n" pg_dumpall --host=iom-psql-server-evd.postgres.database.azure.com --username=psqladmin  | gzip > $FINAL_BACKUP_DIR"globals"$FINAL_BACKUP_NAME.sql.gz.in_progress; then
                echo "[!!ERROR!!] Failed to produce globals backup" 1>&2
        else
                mv $FINAL_BACKUP_DIR"globals"$FINAL_BACKUP_NAME.sql.gz.in_progress $FINAL_BACKUP_DIR"globals"$FINAL_BACKUP_NAME.sql.gz
        fi
else
	echo "None"
fi
 
 
###########################
### SCHEMA-ONLY BACKUPS ###
###########################
 
for SCHEMA_ONLY_DB in ${SCHEMA_ONLY_LIST//,/ }
do
	SCHEMA_ONLY_CLAUSE="$SCHEMA_ONLY_CLAUSE or datname ~ '$SCHEMA_ONLY_DB'"
done
 
SCHEMA_ONLY_QUERY="select datname from pg_database where false $SCHEMA_ONLY_CLAUSE order by datname;"
 
echo -e "\n\nPerforming schema-only backups"
echo -e "--------------------------------------------\n"
 
SCHEMA_ONLY_DB_LIST=`psql -h "$HOSTNAME" -U "$USERNAME" -p $PORT -At -c "$SCHEMA_ONLY_QUERY" postgres`
 
echo -e "The following databases were matched for schema-only backup:\n${SCHEMA_ONLY_DB_LIST}\n"
 
for DATABASE in $SCHEMA_ONLY_DB_LIST
do
	echo "Schema-only backup of $DATABASE"
 
	if ! PGPASSWORD="I@madm1n" pg_dump -Fc -v -h "$HOSTNAME" -U "$USERNAME" "$DATABASE" | gzip > $FINAL_BACKUP_DIR"$DATABASE"$FINAL_BACKUP_NAME"_SCHEMA".sql.gz.in_progress; then
		echo "[!!ERROR!!] Failed to backup database schema of $DATABASE" 1>&2
	else
		mv $FINAL_BACKUP_DIR"$DATABASE"$FINAL_BACKUP_NAME"_SCHEMA".sql.gz.in_progress $FINAL_BACKUP_DIR"$DATABASE"$FINAL_BACKUP_NAME"_SCHEMA".sql.gz
	fi
done
 
 
###########################
###### FULL BACKUPS #######
###########################
 

for SCHEMA_ONLY_DB in ${SCHEMA_ONLY_LIST//,/ }
do
	EXCLUDE_SCHEMA_ONLY_CLAUSE="$EXCLUDE_SCHEMA_ONLY_CLAUSE and datname !~ '$SCHEMA_ONLY_DB'"
done
 
FULL_BACKUP_QUERY="select datname from pg_database where not datistemplate and datallowconn $EXCLUDE_SCHEMA_ONLY_CLAUSE order by datname;"
 
echo -e "\n\nPerforming full backups"
echo -e "--------------------------------------------\n"
 
for DATABASE in `psql -h "$HOSTNAME" -U "$USERNAME" -p $PORT -At -c "$FULL_BACKUP_QUERY" postgres`
do
	if [ $ENABLE_PLAIN_BACKUPS = "yes" ]
	then
		echo "Plain backup of $DATABASE"
 
		if ! PGPASSWORD="I@madm1n" pg_dump -Fc -v -h "$HOSTNAME" -U "$USERNAME" "$DATABASE" | gzip > $FINAL_BACKUP_DIR"$DATABASE"$FINAL_BACKUP_NAME.sql.gz.in_progress; then
			echo "[!!ERROR!!] Failed to produce plain backup database $DATABASE" 1>&2
		else
			mv $FINAL_BACKUP_DIR"$DATABASE"$FINAL_BACKUP_NAME.sql.gz.in_progress $FINAL_BACKUP_DIR"$DATABASE"$FINAL_BACKUP_NAME.sql.gz
		fi
	fi
 
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

		if ! mkdir -p $FINAL_BACKUP_DIR"$DATABASE/old"; then
			echo "Cannot create backup directory in $FINAL_BACKUP_DIR'$DATABASE'. Go and fix it!" 1>&2
			exit 1;
		fi;
 
		if ! pg_dump -Fc -Z 0 -h "$HOSTNAME" -U "$USERNAME" "$DATABASE" -p $PORT -f $FINAL_BACKUP_DIR"$DATABASE/current/$DATABASE"$FINAL_BACKUP_NAME.dump.in_progress; then
			echo "[!!ERROR!!] Failed to produce custom backup database $DATABASE" 1>&2
		else
			mv $FINAL_BACKUP_DIR"$DATABASE/current/$DATABASE"$FINAL_BACKUP_NAME.dump.in_progress $FINAL_BACKUP_DIR"$DATABASE/current/$DATABASE"$FINAL_BACKUP_NAME.dump
		fi

		echo -e " "
		echo -e "Copying current backup to old backup"
		cp -R $FINAL_BACKUP_DIR"$DATABASE/current/." $FINAL_BACKUP_DIR"$DATABASE/old"

		## PING HEALTHCHECKS BEFORE UPLOADING BACKUP FILES
		curl -fsS --retry 3 https://hc-ping.com/847a8225-81fd-4100-a0dd-702d2201aa48 > /dev/null

		echo -e " "
		echo -e "Sync current backup to azure blob"
		/root/pg_backup/azcopy sync "$FINAL_BACKUP_DIR$DATABASE/current" "$BLOB_URL/$CURRENT_DATE/$DATABASE/current/$BLOB_SAS" --delete-destination=true

		echo -e " "
		echo -e "Sync old backup to azure blob"
		/root/pg_backup/azcopy sync "$FINAL_BACKUP_DIR$DATABASE/old" "$BLOB_URL/$CURRENT_DATE/$DATABASE/old/$BLOB_SAS"

		## Sync backup log & delete backup log to azure
		echo -e " "
		echo -e "Synchronizing log files to azure blob..."
		cp /var/log/cron_backup.log /var/log/pgbackup
		cp /var/log/cron_delete.log /var/log/pgbackup
		/root/pg_backup/azcopy sync "/var/log/pgbackup" "$BLOB_URL/$CURRENT_DATE/$BLOB_SAS"
		rm /var/log/pgbackup/*.log

	fi
 
done

echo -e " "
## PING HEALTHCHECKS AFTER UPLOADING BACKUP FILES
##curl -fsS --retry 3 https://hc-ping.com/e4469c45-aeaa-4462-b535-5ba7829c6bd8 > /dev/null
echo -e "\nAll databases backup process completed successfully!."

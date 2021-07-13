---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
if [ "$ENV" == "uksat" ]; then

    ssh rms@${DBServer} 'sh /home/rms/administration/singleExistingDBRefreshUK.sh' $CLIENT $ENVR $CLIENTR $MAIL $ApplyReleaseScripts $RELEASE $BACKUPDATE

elif [ "$ENV" == "impldbuk" ]; then

    ssh rms@${DBServer} 'sh /home/rms/administration/singleExistingDBRefreshUK.sh' $CLIENT $ENVR $CLIENTR $MAIL $ApplyReleaseScripts $RELEASE $BACKUPDATE
else

    ssh rms@${DBServer} 'sh /home/rms/administration/singleExistingDBRefresh.sh' $CLIENT $ENVR $CLIENTR $MAIL $ApplyReleaseScripts $RELEASE $BACKUPDATE
fi
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------



#!/bin/bash -e
#Re Init the database
#RELEASE="4.7"
CLIENT=$1
ENVR=$2
RELEASE=$6
CLIENTR=$3
ApplyReleaseScripts=$5
MAIL=$4
#RELEASEPLAIN="$(echo $RELEASE | sed -e 's/\.//g')"
#RELEASEPLAIN="$(echo "$RELEASEPLAIN"|tr -d '\n')"
#RELEASESCRIPT="Release"$RELEASEPLAIN"PO.sql"
RELEASESCRIPT=""$RELEASE".PO.sql"
DB=$CLIENT
HOST=`hostname`
#ENVR=$2
if [ ! -z "$CLIENTR" ]; then
     CLIENT=$CLIENTR
fi
BACKUPDATE="$7"
MAILRECS="Ramanjaneyulu.Lingala@realpage.com,Naresh.Divi@RealPage.com,$MAIL"
#MAILRECS="ramanjaneyulu.lingala@realpage.com"
LOGDIR="/home/rms/administration/logs"; mkdir -p $LOGDIR;
TIMESTAMP=`date "+%Y%m%d-%H%M%S"`
BACKUP_OUTPUTFILE=$LOGDIR/backup_${CLIENT}_$TIMESTAMP.log
CLEANUP_OUTPUTFILE=$LOGDIR/cleanup_${CLIENT}_$TIMESTAMP.log
QASCRIPTS_OUTPUTFILE=$LOGDIR/qascripts_${CLIENT}_$TIMESTAMP.log
RELEASE_SCRIPTS_OUTPUTFILE=$LOGDIR/releasescripts_${CLIENT}_$TIMESTAMP.log
COMPLETE_OUTPUTFILE=$LOGDIR/complete_${CLIENT}_$TIMESTAMP.log
COMPLETE_OUTPUTFILE_COMPRESSED=$LOGDIR/complete_${CLIENT}_$TIMESTAMP.log.gz

echo " Checking space on Server"
percent_warning=80
disk_usage=`/bin/df -Ph / |awk 'NR==2 {print $5}' | sed "s/%//"`
echo "$disk_usage" | while read percent_used ; do
if [ $percent_used -ge $percent_warning ]; then
mail_body="Warning: On host PO SAT DB Server, Current Disk space usage is $percent_used % , please cleanup the disk space"
echo "$mail_body" | mutt -m "/home/rms/.muttrc" -s "Warning :Disk space on file-system  \"/\" on host SAT DB Server is almost full" $MAILRECS
echo "ERROR: Current Disk space usage is more than 80%.current usage is :$disk_usage"
exit 1
fi
done

echo "Checking server space"
a=`df -HP| grep "/var" | awk '{print $4}' | grep M | wc -l`
d=`df -HP| grep "/var" | awk '{print $4}'`

if [ $a -eq 1 ]
then
echo "We have only $d space on server. Please remove unwanted files from the server" | mutt -m "/home/rms/.muttrc" -s "PO SAT DB Server" $MAILRECS
exit 1
fi

zip_file=`curl -sI "http://pologs.realpage.com/Backup/$DB/database/$DB.$BACKUPDATE.gz" | grep Content-Length | awk '{print $2}'`

Zip_Size=`echo "$zip_file" | awk '{ byte = $1 /1024 ; print byte " k";byte = $1 /1024/1024 ; print byte " MB"; byte =$1 /1024/1024**2 ; print byte " GB" }' | tail -1 | cut -c 1`

b=`expr $Zip_Size \* 3`

c=`df -HP| grep "/var" | awk '{print $4}' | sed 's/G//g'`

if [ $b -gt $c ]
then
echo "Thers is no space on server to refresh the DB. Please remove unwanted files from the server" | mutt -m "/home/rms/.muttrc" -s "PO SAT DB Server" $MAILRECS
exit 1
fi
echo "Server has space"

echo "Validating database"
wget -O - http://pologs.realpage.com/Backup/ > /home/rms/temp.txt
wget -O - http://pologs.realpage.com/Backup_Archive/ > /home/rms/temp1.txt

if grep -w $DB /home/rms/temp.txt; then
echo "Valid Database"
elif grep -w $DB /home/rms/temp1.txt; then
echo "Valid Database"
else
echo "please enter a valid database"
exit 1
fi

#Checking if the given database is valid or not
if psql -lqt | cut -d \| -f 1 | grep -w $CLIENT; then
echo "database already present "
#Delete existing client instance after deleting live connections
echo "Termianting all the connections to the database"
psql -U rms -c "update pg_database set datallowconn = 'false' where datname = '${CLIENT}'"
psql -U rms -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = '${CLIENT}' AND pid <> pg_backend_pid()"
echo "Dropping the database"
psql -U postgres -c "drop database ${CLIENT}"
echo "Successfully deleted the database"

   else
   echo "No existing database found hence creating a new database: $CLIENT"

fi

function myEval {
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        echo "ERROR: Encountered an error while refreshing $CLIENT with  command" >&2
        echo "ERROR: Encountered an error while refreshing $CLIENT with  command" | mail -s "[AutoMail] [ERROR]: $CLIENT DB Refresh ran in to an issue on SAT" $MAILRECS
exit 1
fi
    return $status
}

################################
###Main Work Flow

#Get production dump and make it up
startTime=`date +%s`

# Start restoration
echo "Started Db refresh activity on $ENVR node" | mail -s "Going to refresh database on $ENVR: $CLIENT" $MAILRECS
echo "Grabbing latest backup file from production"
mkdir -p /home/rms/backup/$CLIENT/database
cd /home/rms/backup/$CLIENT/database
rm -f $CLIENT.$BACKUPDATE.gz;
myEval createdb $CLIENT;
#if grep -w $DB /home/rms/temp.txt; then
#wget -O -  http://pologs.realpage.com/Backup/$DB/database/$DB.$BACKUPDATE.gz | gunzip -c | psql $CLIENT -o $BACKUP_OUTPUTFILE
#elif grep -w $DB /home/rms/temp1.txt; then
#wget -O -  http://pologs.realpage.com/Backup_Archive/$DB/database/$DB.$BACKUPDATE.gz | gunzip -c | psql $CLIENT -o $BACKUP_OUTPUTFILE
#fi



if wget -S --spider  http://pologs.realpage.com/Backup/$DB/database/$DB.current.gz 2>&1 | grep 'HTTP/1.1 200 OK' ; then
wget -O -  http://pologs.realpage.com/Backup/$DB/database/$DB.$BACKUPDATE.gz | gunzip -c | psql $CLIENT -o $BACKUP_OUTPUTFILE
else
wget -O -  http://pologs.realpage.com/Backup_Archive/$DB/database/$DB.$BACKUPDATE.gz | gunzip -c | psql $CLIENT -o $BACKUP_OUTPUTFILE
fi

if [ $? -eq 1 ]
then
    #Deleting Database as restore failed
echo "Dropping database as restore failed"
psql -U postgres -c "update pg_database set datallowconn = 'false' where datname = '${CLIENTR}'"
psql -U postgres -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = '${CLIENTR}' AND pid <> pg_backend_pid()"
echo "Dropping the database"
psql -U postgres -c "drop database ${CLIENTR}"
echo "Successfully deleted the database"

fi
#Fetch Code from Git
echo "Getting latest code from git"
mkdir -p /home/rms/cvscodir/$CLIENT; cd /home/rms/cvscodir/$CLIENT ; rm -rf yls-release;
myEval git clone ssh://tfs.realpage.com:22/tfs/Realpage/AOS/_git/release
mv /home/rms/cvscodir/$CLIENT/release /home/rms/cvscodir/$CLIENT/yls-release

#Db Apply Scripts
echo "Going to apply cleanup scripts"
cd /home/rms/cvscodir/$CLIENT/yls-release/scripts/database/cleanup;
myEval psql -U postgres -d $CLIENT -f SanitizePODatabase.sql -o $CLEANUP_OUTPUTFILE;
echo "Going to apply QA Scripts"
cd /home/rms/cvscodir/$CLIENT/yls-release/scripts/database/cleanup;
myEval psql -U postgres  -d $CLIENT -f QAScripts.sql -o $QASCRIPTS_OUTPUTFILE;
if [ $? -eq 1 ]
then
    #Deleting Database as restore failed
echo "Dropping database as restore failed"
psql -U postgres -c "update pg_database set datallowconn = 'false' where datname = '${CLIENTR}'"
psql -U postgres -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = '${CLIENTR}' AND pid <> pg_backend_pid()"
echo "Dropping the database"
psql -U postgres -c "drop database ${CLIENTR}"
echo "Successfully deleted the database"

fi


if [ $ApplyReleaseScripts = "yes" ]
then
echo "Going to apply Release Scripts"
cd /home/rms/cvscodir/$CLIENT/yls-release/scripts/database/$RELEASE;
#myEval psql -U postgres -d $CLIENT -f $RELEASESCRIPT -o $RELEASE_SCRIPTS_OUTPUTFILE;
psql -U postgres -d $CLIENT -f $RELEASESCRIPT -o $RELEASE_SCRIPTS_OUTPUTFILE;
else if [ $ApplyReleaseScripts = "no" ]
then
echo "As per the request did not apply Release Scripts on DB"
fi
fi
# check if the DB restore ran successfully
if [ $(psql -Aqt -U postgres -h $HOST -c "select * from pg_constraint where conname ='ysmtermprobabilitydistribution_propcode_fkey'" $CLIENT | wc -l) -eq 0 ]
then
     echo "$CLIENT Restoration is unsuccessful"
     exit 1
else

#Concatenate all log files
echo -e "==========================BackUp  Log Content=======================================\n\n" >> $COMPLETE_OUTPUTFILE
cat $BACKUP_OUTPUTFILE >> $COMPLETE_OUTPUTFILE
echo -e "==========================CleanUp Log Content=======================================\n\n" >> $COMPLETE_OUTPUTFILE
cat $CLEANUP_OUTPUTFILE >> $COMPLETE_OUTPUTFILE
echo -e "==========================QAScripts Log Content=======================================\n\n" >> $COMPLETE_OUTPUTFILE
cat $QASCRIPTS_OUTPUTFILE >> $COMPLETE_OUTPUTFILE
if [ $ApplyReleaseScripts = "yes" ]
then
echo -e "==========================Release Scrips Log Content=======================================\n\n" >> $COMPLETE_OUTPUTFILE
cat $RELEASE_SCRIPTS_OUTPUTFILE >> $COMPLETE_OUTPUTFILE
else if [ $ApplyReleaseScripts = "no" ]
then
echo "Did not apply release scripts hence there are no release logs"
fi
fi

/bin/gzip $COMPLETE_OUTPUTFILE

#Compute the time taken
endTime=`date +%s`
totalTime=`expr $endTime - $startTime`
totalTimeinnMin=`expr $totalTime / 60`

#Send a mail once the process is completed.
echo "Please find the attached DB Refresh log" | mail -s  "Finished refreshing $ENVR database: $CLIENT and took $totalTimeinnMin minutes" -a $COMPLETE_OUTPUTFILE_COMPRESSED -c $MAILRECS

fi

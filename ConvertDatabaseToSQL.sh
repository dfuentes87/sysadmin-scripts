#!/bin/bash

# This script will take a dump of raw mysql directory and convert them to .sql dump files.
# It is not meant to be used on a current MySQL data directory.

ERROR_LOG=/tmp/mysql_restore.log
SOCKET=/tmp/mysql_sock
PID=/tmp/mysql_pid

function FINISH {
  rm -f -- "$0"
}

trap FINISH EXIT


#See if this is CPanel Or Plesk
if [ -d '/usr/local/psa' ] && [ ! -d '/usr/local/cpanel' ]
	then
   		panel_type='plesk'
elif [ -d '/usr/local/cpanel' ] && [ ! -d '/usr/local/psa' ]
	then
		panel_type='cpanel'
else
   		panel_type='none'
fi

if [ "$panel_type" == 'plesk' ]
    then
		CURDATADIR=$(mysql -uadmin -p"$(cat /etc/psa/.psa.shadow)" -Ns -e"show variables like 'datadir';"| awk '{print $2}')

		#Where is your data?
		echo "Please provide the full path of your MySQL data directory that was restored:";
		read -r DATADIR

		if [ ! -d "$DATADIR" ]; then
			echo "This directory does not exist. Exiting.";
			exit 0;
		fi

		if [ "$DATADIR" == "$CURDATADIR" ] || [ "$DATADIR" == "${CURDATADIR%/}" ]; then
			echo "This data directory is already being used by MySQL. Exiting.";
       		exit 0;
fi

echo "Please provide the full path of the directory you would like to place your .sql files in"

read RESTOREDIR

if [ ! -d "$RESTOREDIR" ]; then
	echo "Creating directory $RESTOREDIR, since it doesn't seem to exist..";
	mkdir -p $RESTOREDIR;
fi

#Start MySQL instance
echo "Starting MySQL instance...";
/usr/bin/mysqld_safe --open-files-limit=20000 --user=mysql --skip-grant-tables --datadir=$DATADIR --log-error=$ERROR_LOG --pid-file=$PID --skip-external-locking --skip-networking --socket=$SOCKET 2>&1 > /dev/null &

sleep 5 ;
echo "MySQL started with the proccess: $(cat /tmp/mysql_pid)";
echo " ";

echo "Exporting databases:";

#Export the databases
mysql -u'admin' -p"$(cat /etc/psa/.psa.shadow)" --socket=$SOCKET -Ns -e'show databases;'| perl -ne 'print unless /\b(mysql|psa|horde|atmail|roundcubemail|information_schema|performance_schema|apsc|sitebuilder.*|phpmyadmin.*)\b/'|while read -r x
do
	echo -n "Dumping $x ...";
	mysqldump --add-drop-table -u'admin' --socket=$SOCKET -p"$(cat /etc/psa/.psa.shadow)" "$x" > "$RESTOREDIR"/"$x".sql;
	echo "Finished.";
done

#Finish up and close the process
kill -15 "$( cat /tmp/mysql_pid )" ;
sleep 5 ;
echo " ";

echo "Done. Your databases have been exported to $RESTOREDIR.";

fi

if [ "$panel_type" == 'cpanel' ]
    then
		CURDATADIR=$(sudo mysql -Ns -e"show variables like 'datadir';"| awk '{print $2}')

		#Where is your data?
		echo "Please provide the full path of your MySQL data directory that was restored:";

		read DATADIR

if [ ! -d "$DATADIR" ]; then
	echo "This directory does not exist. Exiting.";
	exit 0;
fi

if [ "$DATADIR" == "$CURDATADIR" -o "$DATADIR" == "${CURDATADIR%/}" ]; then
	echo "This data directory is already being used by MySQL. Exiting.";
    exit 0;
fi

echo "Please provide the full path of the directory you would like to place your .sql files in"

read RESTOREDIR

if [ ! -d "$RESTOREDIR" ]; then
	echo "Creating directory $RESTOREDIR, since it doesn't seem to exist..";
	mkdir -p "$RESTOREDIR";
fi

#Start MySQL instance
echo "Starting MySQL instance...";
/usr/bin/mysqld_safe --user=mysql --innodb_force_recovery=6 --innodb_file_per_table --datadir="$DATADIR" --log-error=$ERROR_LOG --pid-file=$PID --skip-external-locking --skip-networking --socket=$SOCKET 2>&1 > /dev/null &

sleep 5 ;
echo "MySQL started with the proccess: $(cat /tmp/mysql_pid)";
echo " ";

echo "Exporting databases:";

#Export the databases
sudo mysql --socket=$SOCKET -Ns -e'show databases;'| perl -ne 'print unless /\b(information_schema|cphulkd|eximstats|horde|leechprotect|logaholicDB_test|modsec|mysql|performance_schema|roundcube|whmxfer)\b/'|while read x
do
	echo -n "Dumping $x ...";
	sudo mysqldump --add-drop-table --socket=$SOCKET $x > "$RESTOREDIR"/$x.sql;
	echo "Finished.";
done

#Finish up and close the process
kill -15 $( cat /tmp/mysql_pid ) ;
sleep 5 ;
echo " ";

echo "Done. Your databases have been exported to $RESTOREDIR.";

fi

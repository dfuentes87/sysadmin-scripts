#!/bin/bash

# This script will take a dump of raw mysql directory and convert them to .sql dump files.
# It is not meant to be used on a current MySQL data directory.

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Exiting."
  exit 1
fi

if ! command -v mysql &> /dev/null; then
  echo "MySQL is not installed. Please install MySQL and try again. Exiting."
  exit 1
fi

ERROR_LOG=/tmp/mysql_restore.log
SOCKET=/tmp/mysql_sock
PID=/tmp/mysql_pid

# Determine panel type
if [ -d '/usr/local/psa' ] && [ ! -d '/usr/local/cpanel' ]; then
  panel_type='plesk'
elif [ -d '/usr/local/cpanel' ] && [ ! -d '/usr/local/psa' ]; then
  panel_type='cpanel'
else
  panel_type='none'
fi

function prompt_directories {
  echo "Provide the full path of the MySQL data directory to convert: "
  read -r DATADIR

  if [ ! -d "$DATADIR" ]; then
    echo "This directory does not exist. Exiting."
    exit 1
  fi

  echo "Provide the full path of the directory you would like to place your .sql files in: "
  read -r RESTOREDIR

  if [ ! -d "$RESTOREDIR" ]; then
    echo "Creating directory $RESTOREDIR, since it doesn't seem to exist.."
    mkdir -p "$RESTOREDIR"
  fi
}

function start_mysql {
  echo "Starting temporary MySQL instance..."
  /usr/bin/mysqld_safe --open-files-limit=20000 --user=mysql --skip-grant-tables --datadir="$DATADIR" --log-error=$ERROR_LOG --pid-file=$PID --skip-external-locking --skip-networking --socket=$SOCKET > /dev/null 2>&1 &
  sleep 5
  echo "MySQL started with the process: $(cat /tmp/mysql_pid)"
  echo " "
}

function get_creds {
  echo "Enter database user to login as: "
  read -r DB_USER
  echo "Enter database user password: "
  read -r DB_PASS
}

function export_databases {
  echo "Exporting databases:"
  mysql --socket=$SOCKET -Ns -e'show databases;' | while read -r db; do
    echo -n "Dumping $db ..."
    mysqldump --add-drop-table --socket=$SOCKET "$db" > "$RESTOREDIR/$db.sql"
    echo "Finished."
  done
}

function finish_up {
  kill -15 "$(cat /tmp/mysql_pid)"
  sleep 5
  echo "Done. Your databases have been exported to $RESTOREDIR."
}

# START WORK
if [ "$panel_type" == 'plesk' ]; then
  prompt_directories
  start_mysql
  mysql -u'admin' -p"$(cat /etc/psa/.psa.shadow)" --socket=$SOCKET -Ns -e'show databases;' | perl -ne 'print unless /\b(mysql|psa|horde|atmail|roundcubemail|information_schema|performance_schema)\b/' | while read -r db; do
    echo -n "Dumping $db ..."
    mysqldump --add-drop-table --socket=$SOCKET -uadmin -p"$(cat /etc/psa/.psa.shadow)" "$db" > "$RESTOREDIR/$db.sql"
    echo "Finished."
  done
  finish_up
elif [ "$panel_type" == 'cpanel' ] || [ "$panel_type" == 'none' ]; then
  prompt_directories
  start_mysql
  get_creds
  mysql -u $DB_USER -p$DB_PASS --socket=$SOCKET -Ns -e'show databases;' | perl -ne 'print unless /\b(information_schema|cphulkd|eximstats|horde|leechprotect|logaholicDB_test|modsec|mysql|performance_schema|roundcube|whmxfer)\b/' | while read -r db; do
    echo -n "Dumping $db ..."
    mysqldump --add-drop-table --socket=$SOCKET "$db" > "$RESTOREDIR/$db.sql"
    echo "Finished."
  done
  finish_up
else
  echo "No supported control panel detected. Exiting."
  exit 1
fi

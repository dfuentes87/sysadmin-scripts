#!/bin/bash
#NiceFileName: SlowQueryLogging
#FileDescription: Enable Slow Query logging for a server
string_retrieve(){
echo 'This script will enable slow query logging without restarting MySQL

How long should queries run before logging?

Enter number in seconds (typically 4) #'
read number
}

logic_checks() {
    if rpm -qa | rpm -qa | egrep -q "psa-[0-9]"; then
    echo "Plesk Detected"
    credentials="-uadmin -p`cat /etc/psa/.psa.shadow`"
    elif rpm -qa | grep -q cpanel; then
    echo "Cpanel Detected"
    credentials='-uroot'
	else echo "No Control Panel Detected Enter MySQL root password #"
	read password
	credentials="-uroot -p$password"
    fi
}

mkdirs() {
    mkdir -p /var/log/mysql
    touch /var/log/mysql/slow-queries.log
    chown -R mysql:mysql /var/log/mysql
}

enable_slow_query(){
	echo "Enabling Slow Queries"
    mysql $credentials -e"SET GLOBAL slow_query_log = ON;" > /dev/null 2>&1
	echo "Setting long query time to $number"
    mysql $credentials -e"SET GLOBAL long_query_time = $number;" > /dev/null 2>&1
	echo "Setting to log queries not using indexes"
    mysql $credentials -e"SET GLOBAL log_queries_not_using_indexes = ON;" > /dev/null 2>&1
	echo "Setting log file location to /var/log/mysql/slow-queries.log"
    mysql $credentials -e"SET GLOBAL slow_query_log_file='/var/log/mysql/slow-queries.log';" > /dev/null 2>&1
}

function FINISH {
rm -f -- "$0"
exit
}

trap FINISH INT EXIT

string_retrieve
logic_checks
mkdirs
enable_slow_query

echo 'Happy Logging!'

#! /bin/bash
#FileName: ShellMySQLDump.sh
#NiceFileName: Shell MySQL Dump
#FileDescription: This script will connect to a remote MySQL server and do a shell exec dump.
####################################################
# This trap will remove the script when it closes. #
function FINISH {
rm -f -- "$0"
exit
}

trap FINISH INT EXIT
####################################################
################ Get FTP Data ################
read -p "FTP IP Address: " ftpip
read -p "FTP User: " ftpuser
read -p "FTP Pass: " ftppass
################ Wordpress ################
if [ -f wp-config.php ];
then
   dbname=$(find . -maxdepth 1 -name wp-config.php 2>/dev/null -exec egrep 'DB_NAME' {} \; | awk -F"'" '{ print $4 }' | head -n 1)
   dbuser=$(find . -maxdepth 1 -name wp-config.php 2>/dev/null -exec egrep 'DB_USER' {} \; | awk -F"'" '{ print $4 }' | head -n 1)
   dbpass=$(find . -maxdepth 1 -name wp-config.php 2>/dev/null -exec egrep 'DB_PASSWORD' {} \; | awk -F"'" '{ print $4 }' | head -n 1)
   dbhost=$(find . -maxdepth 1 -name wp-config.php 2>/dev/null -exec egrep 'DB_HOST' {} \; | awk -F"'" '{ print $4 }' | head -n 1)
################ Other CMS ################
else
read -p "DBHOST: " dbhost
read -p "DBNAME: " dbname
read -p "DBUSER: " dbuser
read -p "DBPASS: " dbpass
fi
################ Get Domain ################
read -p "Domain: " domain
################ List Starting Directory ################
ftp -n $ftpip <<End-Of-Session
user $ftpuser "$ftppass"
binary
ls
bye
End-Of-Session
read -p "FTP Doc Root: " ftpdocroot
################ Create PHP Dump File ################
cat <<EOF > ct_mysqldump.php
<?php
exec('mysqldump --host=$dbhost --user=$dbuser --password=$dbpass $dbname > $dbname.sql');
?>
EOF
echo "File ct_mysqldump.php has been created"
echo "--------------------"
################ Upload PHP Dump File ################
echo "Uploading File"
ftp -n $ftpip <<End-Of-Session
user $ftpuser "$ftppass"
binary
cd $ftpdocroot
put "ct_mysqldump.php"
bye
End-Of-Session
echo "File ct_mysqldump.php has been uploaded"
echo "--------------------"
################ Init Dump ################
echo "Starting Dump"
curl -X POST -H "Host: $domain" http://$ftpip/ct_mysqldump.php
echo "Dump Complete"
echo "--------------------"
################ Grab Dump ################
echo "Grabbing Dump"
curl -H "Host: $domain" -o ../$dbname.sql http://$ftpip/$dbname.sql
echo "MySQL Dump Downloaded to ../$dbname.sql"
echo "--------------------"
################ Testing Dump ################
echo "Last 10 lines of dump:"
tail ../$dbname.sql
echo "echo --------------------"
################ Cleanup ################
echo "Press enter for cleanup"
read enterKey
echo "Starting Cleanup"
ftp -n $ftpip <<End-Of-Session
user $ftpuser "$ftppass"
binary
cd $ftpdocroot
delete "ct_mysqldump.php"
delete "$dbname.sql"
bye
End-Of-Session
rm -rf ct_mysqldump.php
rm -rf ct_mysqldump.sh
echo "Cleanup Complete"
echo "--------------------"
echo "Cleanup Verification"
ftp -n $ftpip <<End-Of-Session
user $ftpuser "$ftppass"
binary
cd $ftpdocroot
ls
bye
End-Of-Session
echo "Goodbye"
echo "--------------------"

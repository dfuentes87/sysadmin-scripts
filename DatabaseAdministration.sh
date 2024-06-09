#!/bin/bash
#FileName: DatabaseAdministration.sh
#NiceFileName: Database Administration
#FileDescription: This script assists agents in working with databases.
#VARIABLES
docRoot=''
configFile=''
HCSiteurl=''
HCHome=''
ts=$(date "+%Y-%m-%d-%M")

# Define Text Colors
Escape="\033";
RedF="${Escape}[31m"
CyanF="${Escape}[36m"
Reset="${Escape}[0m"
BoldOn="${Escape}[1m"


#FUNCTIONS

#Make It A Ninja Script
function FINISH {
rm -f -- "$0"
exit
}

trap FINISH INT EXIT

function service_check {
if [ ! -d /var/www/vhosts ]
then
##(gs) Grid-Service
productChoice="gs"
SITEID=`echo $PWD |awk -F/ '{ print $3 }'`
dbHost="internal-db.s$SITEID.gridserver.com"
else
##(dv) Dedicated-Virtual Server
productChoice="dv"
dbHost="localhost"
fi
}

function make_ct_dir(){
#See If CloudTech Directory Exists. If so, move in there, if not, create it
if [ "$productChoice" == "dv" ]
        then
        CloudTechDir='/root/CloudTech'
elif [ "$productChoice" == "gs" ]
        then
        CloudTechDir="/home/$SITEID/data/CloudTech"
else
        echo "No Service Definition Found. Cannot Create Otto root.. exiting"
        exit
fi
if [ ! -d "$CloudTechDir" ]; then
     mkdir $CloudTechDir
fi
}

function getDocRoot() {
    echo -n "Enter the full path to the document root (leave blank to auto-detect): "
    read docRoot
        if [ -z "$docRoot" ]
           then
           if [ "$productChoice" = 'gs' ]
              then
              docRoot="/home/$SITEID/domains/$domainName/html"
           elif [ "$productChoice" = 'dv' ]
              then
                  docRoot=$(mysql -A -u admin -p`cat /etc/psa/.psa.shadow` psa --batch --skip-column-names --raw -e "select hosting.www_root from domains join hosting on domains.id=hosting.dom_id where domains.name='$domainName';")
             fi
        fi
}

#Gets the database creds for the site parameter 1 is the type of CMS, and param 2 is the full path to the config file
function get_creds(){
case "$1" in
   wp)
      dbUserName=$(grep 'DB_USER' "$2" | grep -v ^// | awk -F\' '{print$4}')
      dbPass=$(grep 'DB_PASS' "$2" | grep -v ^// | awk -F\' '{print$4}')
      dbName=$(grep 'DB_NAME' "$2" | grep -v ^// | awk -F\' '{print$4}')
      dbTablePrefix=$(grep '$table_prefix' "$2" | grep -v ^// | awk -F\' '{ print $2 }')
;;
   joomla)
      dbUserName=$(grep -F '$user ' "$2" | sed "s/[';]//g" | awk '{ print $4 }')
      dbPass=$(grep -F '$password ' "$2" | sed "s/[';]//g" | awk '{ print $4 }')
      dbName=$(grep -F '$db ' "$2" | sed "s/[';]//g" | awk '{ print $4 }')
      dbTablePrefix=$(grep -F '$dbprefix ' "$2" | sed "s/[';]//g" | awk '{ print $4 }')
;;
  drupal)
     dbUserName=$(grep -F "'username'" "$2" | grep -v [*] | awk '{ print $3 }' | sed "s/[',]//g")
     dbPass=$(grep -F "'password'" "$2" | grep -v [*] | awk '{ print $3 }' | sed "s/[',]//g")
     dbName=$(grep -F "'database'" "$2" | grep -v [*] | awk '{ print $3 }' | sed "s/[',]//g")
;;
  zen)
      echo "This is zen cart"
;;
  *)
     echo "No Common CMS detected. Please enter database info and credentials:"
     echo ""
     echo -n "DataBase Name: "
     read dbName
     echo -n "Database Username: "
     read dbUserName
     echo -n "Database Password: "
     read dbPass
;;
esac
}

function makeDBBackup() {
currentBackup=''
currentBackup=$(find $CloudTechDir -name "ct-$domainName-${ts}.sql")
if [ "$currentBackup" == '' ]
    then
    echo ""
    echo "Backing up database to ${CloudTechDir}/ct-$domainName-${ts}.sql"
    echo ""
mysqldump --add-drop-table --hex-blob -h $dbHost -u $dbUserName --password=$dbPass $dbName > ${CloudTechDir}/ct-$domainName-${ts}.sql
else
    while true
    do
    echo ""
    echo -n "There is already a database backup for this domain. Do you want to overwrite it?(y or n): "
    read dbOWChoice
    echo ""
    if [ "$dbOWChoice" == 'y' ]
        then
        echo "Backing up database..."
        echo ""
        mysqldump --add-drop-table -h $dbHost -u $dbUserName --password=$dbPass $dbName > ${CloudTechDir}ct-$domainName.sql
        echo "The database for $domainName has been backed up"
        echo ""
        break
    elif [ "$dbOWChoice" == 'n' ]
       then
       echo "The current database backup for $domainName will be retained"
       echo ""
       break
    else
       echo "enter y or n"
       echo ""
    fi
    done
fi
}

function cms_check(){
## Start CMS check
#WordPress
wp=$(find $docRoot -type f -name 'wp-config.php')
if [[ $(echo $wp | awk '{ print NF }') -ge 1 ]]
    then
    [ "$wp" ] && echo "wp $wp" && return
fi
#DRUPAL
drupal1=$(find $doc_root -type f -name "settings.php")
drupal=''
for dom in $drupal1
   do
   dTest=$(grep 'drupal' $dom)
   if [ -n "$dTest" ]
      then
      drupal="$drupal $dom"
   fi
  done
if [[ $(echo $drupal | awk '{ print NF }') -ge 1 ]]
    then
    [ "$drupal" ] && echo "drupal $drupal" && return
fi
#Joomla
joomla1=$(find $docRoot -type f -name 'configuration.php' | egrep -v '(akeeba)')
joomla=''
for dom in $joomla1
   do
   jTest=$(grep 'JConfig' $dom)
   if [ -n "$jTest" ]
      then
      joomla="$joomla $dom"
   fi
  done
if [[ $(echo $joomla | awk '{ print NF }') -ge 1 ]]
    then
     [ "$joomla" ] && echo "joomla $joomla" && return
fi
#Zen Cart
zen=$(find $docRoot -type f -name 'configure.php' | grep -v 'admin')
if [[ $(echo $zen | awk '{ print NF }') -ge 1 ]]
    then
     [ "$zen" ] && echo "zen $zen" && return
fi
#Expression Engine
#find $doc_root -name 'config.php' | xargs grep "app_version"
#if no CMS found:
echo "none" && return
}

function opt_repair {
oldSize=$(mysql -A -N -u $dbUserName -h $dbHost --password=$dbPass $dbName -e "SELECT Round(Sum(data_length + index_length) / 1024, 0) 'DB Size in KB'  FROM information_schema.tables where table_schema='$dbName'")
echo "Repairing the database $dbName"
echo ""
action=$(mysqlcheck $dbName -h $dbHost -u $dbUserName --password=$dbPass --auto-repair --optimize)
echo "report:"
echo ""
echo "$action"
newSize=$(mysql -A -N -u $dbUserName -h $dbHost --password=$dbPass $dbName -e "SELECT Round(Sum(data_length + index_length) / 1024, 0) 'DB Size in KB'  FROM information_schema.tables where table_schema='$dbName'")
}

function support_request {
echo ""
echo "*********************************************************************************************"
echo "Copy And Paste The Following Into The Customer's Support Request. Be sure to add any details about tables that were crashed/corrupted"
echo "*********************************************************************************************"
echo ""
printName=$(echo $domainName | sed 's%/%%g')
echo "Thank you for purchasing the CloudTech Database Administration service! We have completed the repair and optimization of the database for $printName ($dbName), and we wanted to share the results with you."
echo ""
echo "To begin, we created a backup of the database for this domain, which is located at:"
echo ""
echo "${CloudTechDir}/ct-$domainName-${ts}.sql"
echo ""
echo 'We then proceeded to optimize all applicable database tables to clear out the overhead. This is the actual size of a table datafile relative to the ideal size of the same datafile (as if when just restored from backup). For performance reasons, MySQL does not compact the datafiles after it deletes or updates rows. This overhead is bad for table scans. For example, when your query needs to run over all table values, it will need to look at more empty space. Throughout the process, we repaired any crashed or corrupted tables as well.'
echo ""
echo -n "Prior to optimizing tables, your database was $oldSize KB. After optimizing all applicable tables, it is now $newSize KB, which is an overall reduction of "
echo -n $(($oldSize - $newSize))
echo " KB."
echo ""

}

#BEGIN PROGRAM
service_check
make_ct_dir

while true
do
echo -n "Enter the domain name: "
read domainName
echo ""
getDocRoot $domainName
if [ -d $docRoot ]
  then
  break
else
  echo "Could Not Find The Document Root. Please ensure the domain exists on this server"
fi
done
check=$(cms_check)
if [[ $(echo $check | awk '{ print NF }') -gt 2 ]]
   then
   echo "There is more than one configuration file within the document root:"
   echo ""
   echo "$check" | sed 's/wp //g'
   echo ""
   check=$(echo $check | awk '{ print $1 }')
   echo -n "You will need to specify the full path to the config file. Copy and paste from above selections: "
   read choice
   check="$check $choice"
fi
get_creds $check
makeDBBackup
opt_repair
support_request

#!/bin/bash
#NiceFileName: mitm
#FileDescription: Man in the Middle Migration Script

function FINISH {
rm -f -- "$0"
exit
}

trap FINISH INT EXIT

# First check to see if LFTP is installed.
type lftp &> /dev/null
if [ $? != 0 ]; then
   echo "lftp is required. Please install it (yum install lftp) and restart migration script. "
fi

echo "This script will use lftp to download the contents of your source server and the upload them to your destination. You may need to update connection strings depending on the site. Ready to go?"

read -p " Press [ENTER] to continue..."

#Get Variables
echo -n "Enter Source Domain or IP# "
read shost
echo -n "Enter Source Username# "
read suser
echo -n "Enter Source Password# "
read -s spass
echo
echo -n "Enter Source Document Root# "
read sroot
echo -n "Enter Destination Domain or IP# "
read dhost
echo -n "Enter Destination Username# "
read duser
echo -n "Enter Destination Password# "
read -s dpass
echo
echo -n "Enter Destination Document Root# "
read droot
echo
#Downloading source to MITM
echo "Downloading Source Content to MITM Server"
echo
echo
lftp -u $suser,$spass $shost -e "mirror $sroot/. ./migration$shost; exit"
    if [ $? -eq 0 ]
        then
        echo "done"
        else
        echo "Error During Migration!"
        exit 1
    fi
echo
echo
echo
#Downloading source to MITM
echo "Uploading Content to Destination"
echo
echo
lftp -u $duser,$dpass $dhost -e "mirror --reverse ./migration$shost/ $droot; exit"
    if [ $? -eq 0 ]
        then
        echo "done"
        else
        echo "Error During Migration!"
        exit 1
    fi

#!/bin/bash
echo -n "Do you have Databases to import? y/n# "
read question
case $question in

y)
#Get Variables for database
echo -n "Enter Source Database Hostname# "
read sdatahost
echo -n "Enter Source Database Name# "
read sdatabase
echo -n "Enter Source Database Username# "
read sdatabaseu
echo -n "Enter Source Database Password# "
read -s sdatabasepass
echo
echo -n "Enter Destination Database Hostname# "
read ddatahost
echo -n "Enter Destination Database Name# "
read ddatabase
echo -n "Enter Destination Database Username# "
read ddatabaseu
echo -n "Enter Destination Database Password# "
read -s ddatabasepass
echo

mkdir ./migration$shost
    #starting mysql dump
    echo
    echo "Starting MySQL Dump to MITM"
    mysqldump -u$sdatabaseu -p$sdatabasepass -h$sdatahost $sdatabase > ./migration$shost/$sdatabase\.sql
        if [ $? -eq 0 ]
            then
            echo "done"
            else
            echo "Error During Migration!"
            exit 1
        fi
    echo
	#starting mysql import to destination
    echo "Starting MySQL Import to Destination"
    mysql -u$ddatabaseu -p$ddatabasepass -h$ddatahost $ddatabase < ./migration$shost/$sdatabase\.sql
        if [ $? -eq 0 ]
            then
            echo "Migration Completed"
            else
            echo "Error During Migration!"
            exit 1
        fi
;;
n)
echo
echo "Migration Completed"
;;
esac

#remove migration folder
rm -rf ./migration$shost

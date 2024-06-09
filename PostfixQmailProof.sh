#!/bin/bash
#NiceFileName: PostfixQmailProof
#FileDescription: find spam for postfix and qmail

function FINISH {
rm -f -- "$0"
exit
}

trap FINISH INT EXIT

# Setting the variable to be used as the date in output file name
DATE=$(date)
# Suggesting the sccript is run in a screen so other things can be done at the same time in the ssh session
echo "You may want to run this script in a screen. If you are not running in a screen please exit the script in the next five seconds and run it in a screen."
# Pausing for five seconds to allow exiting of script to run in screen if not already doing so
sleep 5
# Telling you not to restart as all of the information in the output file will be deleted
echo "Do not stop and restart this script as all the old file contents will be removed if you do so."
# Creating the output file
echo $DATE > /root/spam_proof.$(date +%F).txt
# Checking to see if Postfix is installed on the server
if $(ls /etc/init.d|egrep -q postfix)
# If postfix is installed starting to gather information
then
# Added By tkemp May 31, 2014 - Stop Postfix
                service postfix stop
# Putting information into the output file that Postfix is installed
        echo -e "\nPostfix is installed\nGetting Postfix Queue Information\n" |tee -a /root/spam_proof.$(date +%F).txt
# Making a backup of one hundered emails to /root/mailbackup
        echo -e "\nMaking backups of 100 emails currently in the queue.\n"|tee -a /root/spam_proof.$(date +%F).txt
# Creating the directory /root/mailbackup
        mkdir -p /root/mailbackup
# Getting a list of one hundred emails in the customer and putting them in files with the queue id in /root/mailbackup
                for e in $(postqueue -p 2>/dev/null|egrep "[A-Z0-9]{11,}"|awk '{print $1}'|tr -d "*"|egrep -v "[:punct:]"|head -n 100)
                do postcat -q $e > /root/mailbackup/$e
                done
# Parsing the backed up emails to find the top ten addresses sending email
        echo -e "\nFinding the top ten senders in the backed up email\n"|tee -a /root/spam_proof.$(date +%F).txt
        cat /root/mailbackup/*|grep "sender:"|awk '{print $2}'|sort|uniq -c|sort -r|head -n 10|tee -a /root/spam_proof.$(date +%F).txt
# Parsing the backed up emails to find the top ten scripts sending email if applicable
        echo -e "\nLooking for scripts sending email\n"|tee -a /root/spam_proof.$(date +%F).txt
        cat /root/mailbackup/*|grep "X-PHP-Originating-Script:"|awk '{print $2}'|sort|uniq -c|sort -r|head -n 10|tee -a /root/spam_proof.$(date +%F).txt
# Parsing the backed up emails to find the top ten subjects of email being sent
        echo -e "\nGetting the top ten subjects\n"|tee -a /root/spam_proof.$(date +%F).txt
        cat /root/mailbackup/*|grep "Subject:"|sort|uniq -c|sort -r|head -n 10|tee -a /root/spam_proof.$(date +%F).txt
# Getting the number of emails currently in the queue
        echo -e "\nCounting the email in the queue. This may take a while.\n"|tee -a /root/spam_proof.$(date +%F).txt
        POSTCOUNT=$(postqueue -p | tail -n 1 | cut -d' ' -f5)
        echo -e "\nNumber of emails in the queue:\t$(echo $POSTCOUNT)"|tee -a /root/spam_proof.$(date +%F).txt
# End of Postfix section
fi
# Checking to see if Qmail is installed
if $(ls /etc/init.d|egrep -q qmail)
then
# Added By tkemp May 31, 2014 - Stop Qmail
                service qmail stop
# If Qmail is installed starting to gather information
        echo -e "\nQmail is installed\nGetting Qmail Queue Information\n" |tee -a /root/spam_proof.$(date +%F).txt
# Making a backup of one hundred emails on the server
        echo -e "\nMaking backups of 100 emails currently in the queue.\n"|tee -a /root/spam_proof.$(date +%F).txt
# Creating the directory /root/mailbackup
        mkdir -p /root/mailbackup
# Getting a list of one hundred emails in the customer and putting them in files with the queue id in /root/mailbackup
                for e in $(/var/qmail/bin/qmail-qread 2>/dev/null|egrep "#"|awk '{print $6}'|tr -d "[:punct:]"|head -n 100)
                do find /var/qmail/queue -name $e|xargs cat > /root/mailbackup/$e
                done
# Parsing the email logs to find the top ten addresses sending email
        echo -e "\nFinding the top ten senders from the logs\n"|tee -a /root/spam_proof.$(date +%F).txt
        grep qmail-remote-handlers /usr/local/psa/var/log/maillog|awk '/from/ {print $6}'|cut -d"=" -f2|sort|uniq -c|egrep "@"|sort -n|tail -n 10|tee -a /root/spam_proof.$(date +%F).txt
# Finding out of the email is being generated - From Apache - A specific user - Or by logging into the server
        echo -e "\nChecking to see if the email is coming from a network connection or from Apache\n"|tee -a /root/spam_proof.$(date +%F).txt
                for f in $(ls /root/mailbackup/)
                do cat /root/mailbackup/$f|head -n 1|awk '{print $7}'|tr -d "[:punct:]"
                done|sort|uniq -c|sort|head -n 5|tee -a /root/spam_proof.$(date +%F).txt
# Parsing the backed up emails to find the top ten addresses sending email
        echo -e "\nGetting the top ten subjects\n"|tee -a /root/spam_proof.$(date +%F).txt
                for f in $(ls /root/mailbackup/)
                do cat /root/mailbackup/$f|head -n 5|tail -n 1
                done|sort|uniq -c|sort|tail -n 5|tee -a /root/spam_proof.$(date +%F).txt
# Getting the number of emails currently in the queue
        echo -e "\nCounting the email in the queue. This may take a while.\n"|tee -a /root/spam_proof.$(date +%F).txt
        QCOUNT=$(/var/qmail/bin/qmail-qstat)
        echo -e "\nNumber of emails in the queue:\n$(echo $QCOUNT)"|tee -a /root/spam_proof.$(date +%F).txt
fi

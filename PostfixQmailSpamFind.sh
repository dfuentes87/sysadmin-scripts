#!/bin/bash

# Find spam for postfix and qmail

DATE=$(date)

echo "You may want to run this script in tmux/screen. Waiting 5 seconds..."
sleep 5
echo "Do not stop and restart this script as all the old file contents will be removed if you do so."


echo "$DATE" > /root/spam_proof."$(date +%F)".txt

if systemctl stop postfix &> /dev/null; then
    echo -e "\nPostfix is installed\nGetting Postfix Queue Information\n" |tee -a /root/spam_proof.$(date +%F).txt
    echo -e "\nMaking backups of 100 emails currently in the queue.\n"|tee -a /root/spam_proof.$(date +%F).txt
    mkdir -p /root/mailbackup
    # Getting a list of one hundred emails in the customer and putting them in files with the queue id in /root/mailbackup
    for e in $(postqueue -p 2>/dev/null | grep -E "[A-Z0-9]{11,}"|awk '{print $1}'|tr -d "*" | grep -E -v "[:punct:]"|head -n 100)
    do postcat -q "$e" > /root/mailbackup/"$e"
    done
    
    # Parsing the backed up emails to find the top ten addresses sending email
    echo -e "\nFinding the top ten senders in the backed up email\n"|tee -a /root/spam_proof.$(date +%F).txt
    cat /root/mailbackup/* | grep "sender:"|awk '{print $2}'|sort|uniq -c|sort -r|head -n 10|tee -a /root/spam_proof.$(date +%F).txt
    # Parsing the backed up emails to find the top ten scripts sending email if applicable
    echo -e "\nLooking for scripts sending email\n"|tee -a /root/spam_proof.$(date +%F).txt
    cat /root/mailbackup/* | grep "X-PHP-Originating-Script:"|awk '{print $2}'|sort|uniq -c|sort -r|head -n 10|tee -a /root/spam_proof.$(date +%F).txt
    # Parsing the backed up emails to find the top ten subjects of email being sent
    echo -e "\nGetting the top ten subjects\n"|tee -a /root/spam_proof.$(date +%F).txt
    cat /root/mailbackup/* | grep "Subject:"|sort|uniq -c|sort -r|head -n 10|tee -a /root/spam_proof.$(date +%F).txt
    
    # Getting the number of emails currently in the queue
    echo -e "\nCounting the email in the queue. This may take a while.\n"|tee -a /root/spam_proof.$(date +%F).txt
    POSTCOUNT=$(postqueue -p | tail -n 1 | cut -d' ' -f5)
    echo -e "\nNumber of emails in the queue:\t$(echo $POSTCOUNT)"|tee -a /root/spam_proof.$(date +%F).txt
elif systemctl stop qmail &> /dev/null; then
  echo -e "\nQmail is installed\nGetting Qmail Queue Information\n" |tee -a /root/spam_proof.$(date +%F).txt
  echo -e "\nMaking backups of 100 emails currently in the queue.\n"|tee -a /root/spam_proof.$(date +%F).txt
  mkdir -p /root/mailbackup
    # Getting a list of one hundred emails in the customer and putting them in files with the queue id in /root/mailbackup
          for e in $(/var/qmail/bin/qmail-qread 2>/dev/null | grep -E "#"|awk '{print $6}'|tr -d "[:punct:]"|head -n 100)
          do find /var/qmail/queue -name "$e" -print0 |xargs cat > /root/mailbackup/$e
          done
    # Parsing the email logs to find the top ten addresses sending email
  echo -e "\nFinding the top ten senders from the logs\n"|tee -a /root/spam_proof.$(date +%F).txt
  grep qmail-remote-handlers /usr/local/psa/var/log/maillog|awk '/from/ {print $6}'|cut -d"=" -f2|sort|uniq -c | grep -E "@"|sort -n|tail -n 10|tee -a /root/spam_proof.$(date +%F).txt
  # Finding out of the email is being generated - From Apache - A specific user - Or by logging into the server
  echo -e "\nChecking to see if the email is coming from a network connection or from Apache\n"|tee -a /root/spam_proof.$(date +%F).txt
  for f in /root/mailbackup/*; do
    if [ -f "$f" ]; then
        head -n 1  "$f"| awk '{print $7}' | tr -d "[:punct:]"
    fi
  done | sort | uniq -c | sort | head -n 5 | tee -a /root/spam_proof."$(date +%F)".txt

  # Parsing the backed up emails to find the top ten addresses sending email
  echo -e "\nGetting the top ten subjects\n"|tee -a /root/spam_proof."$(date +%F)".txt
  for f in /root/mailbackup/*; do
    if [ -f "$f" ]; then
      head -n 5 "$f" | tail -n 1
    fi
  done | sort | uniq -c | sort | tail -n 5 | tee -a /root/spam_proof."$(date +%F)".txt

  # Getting the number of emails currently in the queue
  echo -e "\nCounting the email in the queue. This may take a while.\n"|tee -a /root/spam_proof.$(date +%F).txt
  QCOUNT=$(/var/qmail/bin/qmail-qstat)
  echo -e "\nNumber of emails in the queue:\n$(echo $QCOUNT)"|tee -a /root/spam_proof.$(date +%F).txt
else
  echo "Unsupported mail system or none found."
fi

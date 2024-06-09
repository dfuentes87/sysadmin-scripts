#!/bin/bash

#####################################################################

# A quick way to check the top 5 IPs hitting a domain's access logs

#####################################################################

BoldOn="\033[1m"   #
BoldOff="\033[22m"

cleanup() {
  rm -f $tmp_File
}

trap cleanup EXIT SIGKILL SIGSTOP SIGTERM SIGHUP SIGQUIT

# temporary file to dump data
tmp_File="/tmp/access_logs.tmp"
# number of domains
default_num="3"
num=$1
if [[ -z "$num" ]]; then
  num="$default_num"
fi

# Plesk function for getting the access logs
plesk_logCheck() {
  find /var/www/vhosts/system/* -maxdepth 0 -type d -print0 |
  while IFS= read -r -d $'\0' result; do
    total_hits=$(wc -l "$result"/logs/access_log 2>/dev/null)
    # If access log has data, output of $total_hits is written to a temp file
    if [[ -s "$result"/logs/access_log ]]; then
      echo "$total_hits" >> $tmp_File
    fi
  done
}

# cPanel function for getting the access logs
cpanel_logCheck() {
  domain_list=$(grep -Ev "*.accessdomain.com" /etc/localdomains)
  for dom in $domain_list; do
    log_Path="/usr/local/apache/domlogs/$dom"
    # If access log has data, output of $total_hits is written to a temp file
    if [[ -s "$log_Path" ]]; then
      total_hits=$(wc -l "$log_Path")
      echo "$total_hits" >> $tmp_File
    fi
  done
}

# Unknown server type function for getting the access logs
other_logCheck() {
  echo "This server is neither Plesk or cPanel, so this may not work."
  echo
  updatedb
  other_logs=$(locate -iw */logs/access_log)
  for log_entry in $other_logs; do
    total_hits=$(wc -l $log_entry)
    if [[ -s $log_entry ]]; then
      echo "$total_hits" >> $tmp_File
    fi
  done
}

# Determine which type of server and run the appropriate function
if [[ -d "/usr/local/psa" ]]; then
  plesk_logCheck
elif [[ -d "/usr/local/cpanel" ]]; then
  cpanel_logCheck
else
  other_logCheck
fi

# If all access logs are missing or empty, exit out
if [[ ! -s /tmp/access_logs.tmp ]]; then
  echo "All logs are empty or something went wrong. Press Enter to exit the script."
  read enterKey
  exit 0
fi

# total number of logs with data
access_count=$(wc -l $tmp_File | awk '{print $1}')
# sorts info in temp file and filters out top results
top_paths=$(sort -nr $tmp_File | head -$num | awk '{print $2}')
if [[ $access_count -lt "$default_num" ]]; then
  num="$access_count"
fi

# removes temp file after setting more variables
cleanup

clear
  echo "===================================="
  echo " Total domains with connections: $access_count"
  echo " Showing connections for top: $num"
  echo "===================================="
# this loop prints access log results
for log_Path in $top_paths; do
  domain=$(echo "$log_Path" | awk -F'/' '{print $6}')
  total_hits=$(wc -l "$log_Path" | awk '{print $1}')
  since_time=$(head -1 "$log_Path" | sed -e 's/.*\[\(.*\)\].*/\1/')
  echo -e "\n $domain - $log_Path"
  echo -e " ${BoldOn}total hits:${BoldOff} $total_hits - ${BoldOn}since:${BoldOff} $since_time"
  echo
  echo -e " ${BoldOn}Top 5 IPs:${BoldOff}"
  # prints top 5 IPs in the access log
  awk '{print $1}' "$log_Path" | sort | uniq -c | sort -nr | head -5 | sed 's/^[ ]*/ /g'
  echo ""
done
# if more than 3 domains have data in access logs, ask to rerun
if [[ "$access_count" -gt "$default_num" ]] && [[ "$access_count" != "$num" ]]; then
  echo
  read -n 1 -p 'Rerun the script on more domains?: ' rerun
  echo
    case "$rerun" in
      Y|y)
        # allows you to enter num of domains to rerun script on
        read -p "How many domains? (max:$access_count): " dom_choice
        # tests that an integer was passed in last question
        if ! [[ "$dom_choice" =~ ^[0-9]+$ ]] ; then
          echo -e "\nInvalid entry. Script exiting..."
          exit 0
        # reruns script on specified num of domains if valid number is passed
        elif [[ "$dom_choice" -gt 0 ]] && [[ "$dom_choice" -lt "$access_count" ]]; then
          bash "$0" "$dom_choice"
          exit 0
        # if num entered is larger than total doms with data, rerun script on max num of domains with data
        elif [[ "$dom_choice" -ge "$access_count" ]]; then
          bash "$0" "$access_count"
          exit 0
        else
          echo -e "\nYou selected 0. Script exiting..."
          exit 0
        fi
      ;;
      # If you type in n/N
      N|n)
        echo -e "\nYou typed in 'No'. Script exiting..."
        echo
        exit 0
      ;;
      # If you type anything other than y/Y or n/N then the script exits
      *)
        echo -e "\nInvalid selection. Script exiting..."
        echo
        exit 0
    esac
fi

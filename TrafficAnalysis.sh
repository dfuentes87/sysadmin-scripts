#!/bin/bash

# Determine Which Domain Is Receiving The Most Traffic

# Constants
reportDir="/tmp/traffic_analysis"
if [ ! -d "$reportDir" ]; then
    mkdir -p $reportDir
fi

get_dom_choice() {
  if [ -f /usr/local/psa/version ]; then
      default_domains=$(find /var/www/vhosts -maxdepth 1 -mindepth 1 -type d ! -name 'chroot' ! -name 'default' ! -name 'fs' ! -name 'fs-passwd' ! -name 'system' -printf "%f\n")
      echo -n "Enter A Domain Name or Leave Blank To Analyze All: "
      read -r dom_choice
      if [ -z "$dom_choice" ]; then
          dom_choice=$default_domains
      fi
  else
      default_domains=$(find /var/log -name '*access*log*' ! -name '*.gz')
      if [ -z "$default_domains" ]; then
          echo "No web server logs found."
          exit 1
      fi
      dom_choice=$default_domains
  fi
}

# Functions
convert_date() {
  year=$(date +'%Y')
  month=$(date +'%b')
  date=$(date +'%d')
  hour=$(date +'%H')
  minute=$(date +'%M')
  case $timeChoice in
  month)
  echo "$month/$year"
  ;;
  day)
  echo "$date/$month/$year"
  ;;
  hour)
  echo "$date/$month/$year:$hour"
  ;;
  minute)
  echo "$date/$month/$year:$hour:$minute"
  ;;
  esac
}

# Begin Program
get_dom_choice
echo -n "Do you want to see traffic for the last month, day, hour, or minute?: "
read -r timeChoice
echo -n "Do you want to see a breakdown by IP address? (y or n): "
read -r ip_choice
if [ "$ip_choice" == "y" ]; then
   echo -n "Enter a number to limit the result or leave blank for no limit: "
   read -r ip_limit
fi
echo -n "Do you want to see a breakdown by request? (y or n): "
read -r request_choice
if [ "$request_choice" == "y" ]; then
   echo -n "Enter a number to limit the result or leave blank for no limit: "
   read -r request_limit
fi

date_search=$(convert_date)
for domain in $dom_choice; do
    report_file="$reportDir/$(basename ${domain})_$(date "+%Y-%m-%d-%H-%M")"
    echo
    echo "Checking access log for $(basename ${domain})" | tr 'a-z' 'A-Z' | tee -a "$report_file"
    echo "" | tee -a "$report_file"
    echo "Analyzing the past $timeChoice" | tee -a "$report_file"
    echo "" | tee -a "$report_file"
    raw_res=$(cat "$domain")
    total_hits=$(echo "$raw_res" | grep -c "$date_search")
    echo "TOTAL HITS: $total_hits in the past $timeChoice" | tee -a "$report_file"
    echo "" | tee -a "$report_file"
    if [ "$total_hits" != 0 ] && [ "$ip_choice" == "y" ]; then
        echo "BREAKDOWN BY IP:" | tee -a "$report_file"
        echo "" | tee -a "$report_file"
        if [ -n "$ip_limit" ]; then
           echo "$raw_res" | grep "$date_search" | awk '{ print $1 }' | sort | uniq -c | sort -nr | head -"$ip_limit" | tee -a "$report_file"
        else
           echo "$raw_res" | grep "$date_search" | awk '{ print $1 }' | sort | uniq -c | sort -nr | tee -a "$report_file"
        fi
        echo "" | tee -a "$report_file"
    fi
    if [ "$total_hits" != 0 ] && [ "$request_choice" == "y" ]; then
        echo "BREAKDOWN BY REQUEST:" | tee -a "$report_file"
        echo "" | tee -a "$report_file"
        if [ -n "$request_limit" ]; then
          echo "$raw_res" | grep "$date_search" | awk -F '"' '{ print $2 }' | sort | uniq -c | sort -nr | head -"$request_limit" | tee -a "$report_file"
        else
          echo "$raw_res" | grep "$date_search" | awk -F '"' '{ print $2 }' | sort | uniq -c | sort -nr | tee -a "$report_file"
        fi
    fi
done

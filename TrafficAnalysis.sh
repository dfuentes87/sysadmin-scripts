#!/bin/bash
#FileName: TrafficAnalysis.sh
#NiceFileName: Traffic Analysis
#FileDescription: Simple Program To Determine Which Domain Is Receiving The Most Traffic
#Constants
pathRoot='/var/www/vhosts/'
plesk_ver=$(cat /usr/local/psa/version | awk -F '.' '{ print $1$2 }')
if [ "$plesk_ver" -gt "114" ]
     then
     logDir="/logs/"
  else
     logDir="/statistics/logs/"
fi
default_domains=$(ls /var/www/vhosts | egrep -v '(chroot|default|fs|fs-passwd|system)')

reportDir="/root/CloudTech/logs/traffic_analysis"
if [ ! -d "$reportDir" ]; then
    mkdir -p $reportDir
fi

#Functions

convert_date() {
    year=$(date | awk '{ print $6 }')
    month=$(date | awk '{ print $2 }')
    date=$(date | awk '{ print $3 }')
    hour=$(date | awk '{ print $4 }' | awk -F ':' '{ print $1 }')
    minute=$(date | awk '{ print $4 }' | awk -F ':' '{ print $2 }')
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

get_dom_choice() {
echo -n "Enter A Domain Name or Leave Blank To Analyze All: "
read dom_choice
if [ -z "$dom_choice" ]
   then
     dom_choice=$(ls /var/www/vhosts | egrep -v '(chroot|default|fs|fs-passwd|system)')
fi
}

function FINISH {
rm -f -- "$0"
exit
}

trap FINISH INT EXIT

#Begin Program

get_dom_choice
echo -n "Do you want to see traffic for the last month,day,hour,or minute?: "
read timeChoice
echo -n "Do you want to see a breakdown by IP address? (y or n): "
read ip_choice
if [ "$ip_choice" == "y" ]
   then
   echo -n "Enter a number to limit the result set or leave blank for no limit: "
   read ip_limit
fi
echo -n "Do you want to see a breakdown by request? (y or n): "
read request_choice
if [ "$request_choice" == "y" ]
   then
   echo -n "Enter a number to limit the result set or leave blank for no limit: "
   read request_limit
fi
date_search=$(convert_date)
for domain in $default_domains
    do
    report_file="$reportDir/$domain_`date "+%Y-%m-%d-%M"`"
    echo ""
    echo "Checking access log for $domain" | tr 'a-z' 'A-Z' | tee -a $report_file
    echo "" | tee -a $report_file
    echo "Analyzing the past $timeChoice" | tee -a $report_file
    echo "" | tee -a $report_file
    raw_res=$(cat ${pathRoot}${domain}${logDir}access_log)
    total_hits=$(cat ${pathRoot}${domain}${logDir}access_log | grep $date_search | wc -l)
    #total_hits=$(echo "$raw_res" | wc -l)
    echo "TOTAL HITS: $total_hits in the past $timeChoice" | tee -a $report_file
    echo "" | tee -a $report_file
    if [ "$total_hits" != 0 ] && [ "$ip_choice" == "y" ]
       then
        echo "BREAKDOWN BY IP:" | tee -a $report_file
        echo "" | tee -a $report_file
        if [ -n "$ip_limit" ]
           then
           echo "$raw_res" | grep $date_search |  awk '{ print $1 }' | sort | uniq -c | sort -nr | head -$ip_limit | tee -a $report_file
        else
           echo "$raw_res" | grep $date_search |  awk '{ print $1 }' | sort | uniq -c | sort -nr | tee -a $report_file
        fi
        echo "" | tee -a $report_file
    fi
    if [ "$total_hits" != 0 ] && [ "$request_choice" == "y" ]
       then
        echo "BREAKDOWN BY REQUEST:" | tee -a $report_file
        echo "" | tee -a $report_file
        if [ -n "$request_limit" ]
          then
          echo "$raw_res" | grep $date_search |  awk -F '"' '{ print $2 }' | sort | uniq -c | sort -nr | head -$request_limit | tee -a $report_file
        else
          echo "$raw_res" | grep $date_search |  awk -F '"' '{ print $2 }' | sort | uniq -c | sort -nr | tee -a $report_file
        fi
    fi
    done

#!/bin/bash
#FileName: DiskManagement.sh
#NiceFileName: Disk Management
#FileDescription: Identify areas of disk usage
#Disk Managment Script

##Things that don't change (Constants)
CWD="$PWD"
#divider="${RedF}*******************************************************************${Reset}" # Had to change this as the asterisks were globbing
divider="###################################################################################"
mkdir -p /root/CloudTech
epoch=$(date +%s)
##Things I want to do (Functions)

function FINISH {
  rm -f -- "$0"
  exit
}
trap FINISH INT EXIT


while getopts "hza:" opt; do
  case "${opt}" in
  h)  echo "-h for help"
      echo "-a (gd|mt) to set to 'gd' or 'mt'"
      echo "-z for headless mode (requires -a to be set also)"
      ;;

  z)  _headless=true
      ;;

  a)  platform=$OPTARG
      ;;

  \?)	echo "Usage: $0 [-h] [-t] [-z] [-a (gd|mt)]"
      exit
      ;;

  esac
done
shift $((OPTIND-1))

if [[ $platform == "gd" ]]
then
  co_name="GoDaddy"
else
  co_name="(mt) Media Temple"
fi


output_glob=()

## This function redirects all previous echo commands and if in headless mode, it stores them in an array for later. If not in headless, spits them out normally
outputHandler() {
  if [[ $_headless == true ]]
  then
    tempIFS="$IFS"
    IFS=$'\n'
    output_glob+=("$1")
    IFS="$tempIFS"
  else
    echo "$1"
  fi
}


#Check OS
if [ -f /etc/redhat-release ]
then
  distro_base="redhat"
  distro_os=$(awk '{print tolower($1)}' /etc/redhat-release)
  distro_os_version=$(awk '{print ($3)}' /etc/redhat-release)
elif [ -f /etc/debian_version ]
then
  distro_base="debian"
  distro_os=$(lsb_release -d | awk '{print tolower($2)}')
  distro_os_version=$(lsb_release -r | awk '{print $2}')
else
  outputHandler "Unknown OS. Script will now quit"
  exit 0
fi

if [ "$debug" == "true" ]
then
  outputHandler "$divider"
  outputHandler "Below is the variables in the os_check function.\n"
  outputHandler "$distro_base"
  outputHandler "$distro_os"
  outputHandler "$distro_os_version \n"
  outputHandler "$divider"
fi

#See if this is CPanel Or Plesk
if [ -d '/usr/local/psa' ] && [ ! -d '/usr/local/cpanel' ]
then
  panel_type='plesk'
  sqlConnect="mysql -u admin -p`cat /etc/psa/.psa.shadow` -e"
elif [ -d '/usr/local/cpanel' ] && [ ! -d '/usr/local/psa' ]
then
  panel_type='cpanel'
  sqlConnect='sudo mysql -e '
else
  panel_type='none'
fi

##SUMMARY
function overall_disk_usage {
  df_output=`df -h | head -2`
  dfi_output=`df -i | head -2`
  dfi_used_percent=`df -i | head -2 | tail -1 | awk '{print $5}' | sed 's/%//'`
  df_used=`df -h | head -2 | tail -1 | awk '{print $3}'`
  df_free=`df -h | head -2 | tail -1 | awk '{print $4}'`
  df_used_percent=`df -h | head -2 | tail -1 | awk '{print $5}'`
  outputHandler "$divider"
  outputHandler "Currently, this server has $df_used of its disk used and $df_free free."
  outputHandler "Below is the output of df -h:"
  outputHandler "$df_output"
  outputHandler "$divider"
}

function inode_check {
  if [ $dfi_used_percent -gt 75 ]
  then
    top_inode=`find / -xdev -printf '%h\n' | sort | uniq -c | sort -k 1 -nr | head -10`
    outputHandler "$divider"
    outputHandler "High Inode usage detected"
    outputHandler ""
    outputHandler "Below are the top 10 directories with inode usage:"
    outputHandler ""
    outputHandler "$top_inode"
    outputHandler "$divider"
  else
    outputHandler "$divider"
    outputHandler "Low Inode usage detected. No current risk."
    outputHandler ""
    outputHandler "$divider"
  fi
}

function database_size {
  outputHandler "Below is the size of the databases:"
  outputHandler ""
  db_size=$($sqlConnect "SELECT table_schema 'Database Name', CONCAT(ROUND( sum( data_length + index_length ) / 1024 / 1024, 2), 'MB') total_size FROM information_schema.TABLES GROUP BY table_schema" 2>/dev/null)
  if [ "$panel_type" == "plesk" ]
  then
    customer_db_size=$(echo "$db_size" | tail -n +2 |egrep -v "apsc|horde|information_schema|mysql|performance_schema|phpmyadmin|psa|roundcubemail|sitebuilder5")
  fi
  if [ "$panel_type" == "cpanel" ]
  then
      customer_db_size=$(echo "$db_size" | tail -n +2 |egrep -v "information_schema|cphulkd|eximstats|horde|leechprotect|logaholicDB_test|modsec|mysql|performance_schema|roundcube|whmxfer")
  fi
  outputHandler "$customer_db_size"
}

##Files over 100MB
function large_file_check {
  awkscript='BEGIN { split("KMGTPEZY",suff,//)}
{
  match($0,/([0-9]+)[ \t](.*)/,bits)
  sz=bits[1]+0; fn=bits[2]
  i=0; while ((sz>1024)&&(i<length(suff))) { sz/=1024;i++ }
  if (i) printf("%.3f %siB %s\n",sz,suff[i],fn)
  else   printf("%3i B %s\n",sz,fn)
}'
  large_files=`find / -mount -noleaf -type f -size +100000k -printf "%s %p\n" | sort -nr | gawk 'BEGIN { split("KMGTPEZY",suff,//)} ; {match($0,/([0-9]+)[ \t](.*)/,bits) ; sz=bits[1]+0; fn=bits[2] ; i=0; while ((sz>1024)&&(i<length(suff))) { sz/=1024;i++ } ; if (i) printf("%.3f %siB %s\n",sz,suff[i],fn) ; else   printf("%3i B %s\n",sz,fn) ; }' | grep -v "/var/lib/mysql"`
  outputHandler "$large_files" > /root/CloudTech/large_files-$epoch.txt
  outputHandler "$divider"
  outputHandler "Below is a list of files over 100MB in size."
  outputHandler "$divider"
  outputHandler "$large_files"
}

function large_directory_check {
  if [ "$panel_type" == "plesk" ]
  then
    homedir="/var/www/vhosts/"
  elif [ "$panel_type" == "cpanel" ]
  then
    homedir="/home/"
  else
    homedir="/var/www/"
  fi

  all_dirs=$(du -b --max-depth=5 --separate-dirs --exclude="virtfs"* "$homedir" | grep -E '^[2-9][0-9]{9,}')
  all_dirs+="
"
  all_dirs+=$(du -b --max-depth=3 --separate-dirs --exclude="$homedir"* / 2>/dev/null | grep -E "^[2-9][0-9]{9,}")

  large_dirs=$(echo "$all_dirs" | sort -nr | gawk 'BEGIN { split("KMGTPEZY",suff,//)} ; {match($0,/([0-9]+)[ \t](.*)/,bits) ; sz=bits[1]+0; fn=bits[2] ; i=0; while ((sz>1024)&&(i<length(suff))) { sz/=1024;i++ } ; if (i) printf("%.3f %siB %s\n",sz,suff[i],fn) ; else   printf("%3i B %s\n",sz,fn) ; }')
  outputHandler "$large_dirs" > /root/CloudTech/large_directories-"$epoch".txt
  outputHandler "$divider"
  outputHandler "Below is a list of directories over 2GB in size."
  outputHandler "$divider"
  outputHandler "$large_dirs"
}

##Check for /old
function old_check {
  if [  -d /old ];
  then
    old_exist="true"
    old_size=`du -sh /old/ | awk '{print $1}'`
    outputHandler "$divider"
    outputHandler "/old Exists"
    outputHandler "$divider"
  else
    old_exist="false"
    outputHandler "$divider"
    outputHandler "/old does not exist"
    outputHandler "$divider"
  fi
}

##Check for /restore
function restore_check {
  if [  -d /restore ];
  then
    restore_exist="true"
    restore_size=`du -sh /restore/ | awk '{print $1}'`
    restore_dates=`ls --full-time /restore/ | tail -n +2 |awk '{print $6}' | uniq`
    outputHandler "$divider"
    outputHandler "/restore Exists"
    outputHandler ""
    outputHandler "$restore_dates"
    outputHandler "$divider"
  else
    restore_exist="false"
    outputHandler "$divider"
    outputHandler "/restore does not exist"
    outputHandler "$divider"
  fi
}

##Check for bin logging
function bin_logging {
  inlog_size=`du -csh /var/lib/mysql/mysql-bin* 2>/dev/null | grep "total" | awk '{print $1}'`
  if [ ! -z $(grep "^log-bin=" /etc/my.cnf) ] && [ "$binlog_size" != "0" ]
  then
    binlog_exist="true"
    binlog_on="true"
    outputHandler "Bin logs are enabled. The total size of the bin logs are $binlog_size"

  elif [ "$binlog_size" != "0" ]
  then
    binlog_exist="true"
    binlog_on="false"
    outputHandler "Bin logs are disabled but old bin logs exist. The total size of the old bin logs are $binlog_size"
  else
    binlog_exist="false"
    binlog_on="false"
    outputHandler "Bin logs are disabled."

  fi
}


##File Type / Size Breakdown

function file_type {
  if [ "$panel_type" == "plesk" ]
  then
    ##Size of all Log files
    outputHandler "File Type / Size Overview"
    outputHandler "$divider"
    total_log_size=`du -shc /var/www/vhosts/*/statistics/logs/ /var/log/ | grep "total" | awk '{print $1}'`
    outputHandler "The total size of all log files on this server is ${total_log_size}B (Includes Domain and Server Level Logs)"
    ##Total size of Email
    total_email_size=`du -csh /var/qmail/mailnames | grep "total" | awk '{print $1}'`
    total_email_size_bytes=`du -cs --bytes /var/qmail/mailnames | grep "total" | awk '{print $1}'`
    outputHandler "The total size of all email on this server is ${total_email_size}B"
    #Total Size of all websites
    outputHandler "The total size of all websites on this server is ${total_dom_size}MB"
    ##MySQL content size
    total_mysql_size=`du -shc /var/lib/mysql | grep "total" | awk '{print $1}'`
    outputHandler "The total size of all MySQL data on this server is ${total_mysql_size}B"
  fi
  if [ "$panel_type" == "cpanel" ]
  then
    ##Size of all Log files
    outputHandler "File Type / Size Overview"
    outputHandler "$divider"
    total_log_size=`du -shc /usr/local/apache/domlogs/ /var/log/ | grep "total" | awk '{print $1}'`
    outputHandler "The total size of all log files on this server is ${total_log_size}B (Includes Domain and Server Level Logs)"
    ##Total size of Email
    total_email_size=`du -csh /home/*/mail | grep "total" | awk '{print $1}'`
    total_email_size_bytes=`du -cs --bytes /home/*/mail | grep "total" | awk '{print $1}'`
    outputHandler "The total size of all email on this server is ${total_email_size}B"
    #Total Size of all websites
    outputHandler "The total size of all websites on this server is ${total_dom_size}MB"
    ##MySQL content size
    total_mysql_size=`du -shc /var/lib/mysql | grep "total" | awk '{print $1}'`
    outputHandler "The total size of all MySQL data on this server is ${total_mysql_size}B"
  fi
}

##Size of doc roots

##Email size
function email_checks {
  if [ "$panel_type" == "plesk" ]
  then
    large_email_domains=`du -s /var/qmail/mailnames/* | sort -nr | cut -f2- | xargs du -hs | grep -v "4.0K"`
    outputHandler "$divider"
    outputHandler "Below is a list of the email size per domain. Domains with no email are excluded."
    outputHandler "$divider"
    outputHandler "$large_email_domains"
    full_email_user_list=`du --max-depth 0  /var/qmail/mailnames/*/* | sort -nr | cut -f2- | xargs du -hs | awk -F/ '{print $1 $6 "@" $5}'`
    top25_email_user_list=`echo "$full_email_user_list" | head -25`
  fi
}

function get_dom_sizes {
  if [ "$panel_type" == "plesk" ]
  then
    doms=$(mysql -N -B -u admin -p`cat /etc/psa/.psa.shadow` psa -e 'select name from domains WHERE htype="vrt_hst";')
    sub_doms=$(mysql -N -B -u admin -p`cat /etc/psa/.psa.shadow` psa -e 'select name from subdomains;')
    all_doms="$doms $sub_doms"
    end_dom_report=''
    total_dom_size=0
      #Get size of each doc root and also make total
    for dom in $all_doms
    do
      doc_root=$(mysql -N -B -u admin -p`cat /etc/psa/.psa.shadow` psa -e "select www_root from hosting where dom_id=(select id from domains where name='$dom')")
      #Get doc root size in MB and add to total
      doc_root_size=$(du -s --block-size=1M $doc_root | awk '{ print $1 }')
      total_dom_size=$(($total_dom_size+$doc_root_size))
      #If doc root is bigger than 100MB, add to domains that will be reported
      if [ $doc_root_size -gt 100 ]
      then
        end_dom_report="$end_dom_report
        $doc_root_size MB: $dom"
      fi
    done
  fi
  if [ "$panel_type" == "cpanel" ]
          then
                  doc_root=`grep -RI "documentroot" /var/cpanel/userdata/ | egrep -v "\.cache\:|_SSL\:" | awk '{print $2}'`
                  total_dom_size=`du -cksh --block-size=1M $doc_root | grep "total" |awk '{print $1}'`
  fi
}

##Tell them whats up
function support_request {
  if ! $_headless; then
  ## Dont spit out divider and headers in headless mode
    outputHandler "$divider"
    outputHandler "BEGIN SUPPORT REQUEST"
    outputHandler "$divider"
  fi
  outputHandler "Thank you for ordering the CloudTech Disk Management service. Currently, your content is using $df_used_percent of your server's total disk space. Below is the output of the 'df' utility:"
  outputHandler ""
  outputHandler "Disk Usage:"
  outputHandler ""
  outputHandler "$df_output"
  outputHandler ""
  outputHandler "Inode Usage:"
  outputHandler ""
  outputHandler "$dfi_output"
  outputHandler ""
  outputHandler "To help understand your current disk usage, we summarized your most common sources of content:"
  outputHandler ""
  outputHandler "The total size of all website data on this server is ${total_dom_size}MB"
  outputHandler "The total size of all MySQL data on this server is ${total_mysql_size}B"
  outputHandler "The total size of all email data on this server is ${total_email_size}B"
  outputHandler "The total size of all log files on this server is ${total_log_size}B (Includes Domain and Server Level Logs)"
  outputHandler ""
  if [ ! -z "$customer_db_size" ]
  then
    outputHandler "For MySQL in particular, below is the size of your databases:"
    outputHandler ""
    outputHandler "$customer_db_size"
    outputHandler ""
  fi
  if [ ! -z "$large_files" ]
  then
    outputHandler "To help understand the above usage, we took a more detailed look at where your disk usage lies. Many times, large files can accumulate causing disk usage issues. As such, we began a search for files larger than 100MB in size. A full list of files larger than 100MB can be found on your server at /root/CloudTech/large_files-$epoch.txt. We have also listed the top files over 100MB below:"
    outputHandler ""
    outputHandler "$large_files" | head -25
    outputHandler ""
  fi
  if [ -n "$large_dirs" ]
  then
    outputHandler "In addition to large files, we have also looked for any directories which contain a large amount of data. A full list of directories containing more than 2GB can be found on your server at /root/CloudTech/large_directories-$epoch.txt. We have also listed the top directories containing over 2GB below:"
    outputHandler ""
    outputHandler "$large_dirs" | head -25
    outputHandler ""
  fi
  if [ $dfi_used_percent -gt 75 ]
  then
    outputHandler "We detected that your server is currently using a high number of the filesystem inodes. Below are the top 10 directories with inode usage:"
    outputHandler ""
    outputHandler "$top_inode"
    outputHandler ""
    outputHandler "Assuming you do not need the content in the above directories, we would be happy to clear any of them out for you. Keep in mind, many of the previously reported directories may have core system files in them. If you are un-sure of what should be removed, we would be happy to lend insight."
    outputHandler ""
  fi
  if [ "$old_exist" == "true" ]
  then
    outputHandler "We also noticed your '/old' directory from a previous operating system reinstall still exists. This directly contains $old_size in content and should be removed if you no longer require this data."
    outputHandler ""
  fi
  if [ "$restore_exist" == "true" ]
  then
    outputHandler "Looking at your disk usage, we noticed your '/restore' directory from a previous restore request exists. This directly contains $restore_size in content and should be removed if you no longer require this data. For your records, below are the dates of the restore data in /restore."
    outputHandler ""
    outputHandler "$restore_dates"
    outputHandler ""
  fi
  if [ "$binlog_on" == "true" ] && [ "$binlog_exist" == "true" ]
  then
    outputHandler "Currently, we see your MySQL Bin logging is enabled. Generally, this feature is only required if you are using MySQL replication, which is not configured on our hosting by default. These bin logs are consuming $binlog_size of disk space. If you do not require these logs to be enabled, this feature should be disabled and the logs removed. We can do this upon request. For your records, the logs are located at /var/lib/mysql and these logs will start with mysql-bin. If you are not comfortable with the process of removing these files, we would strongly suggest you let CloudTech take care of it for you."
    outputHandler ""
  elif [ "$binlog_on" == "false" ] && [ "$binlog_exist" == "true" ]
  then
    outputHandler "Currently, we see your MySQL Bin logging is disabled; however, there are currently bin logs located on your filesystem from when this feature was previously enabled. As these logs likely serve no purpose unless you are using MySQL replication, they should be removed. These bin logs are consuming $binlog_size of disk space. For your records, the logs are located at /var/lib/mysql and these logs will start with mysql-bin. If you are not comfortable with the process of removing these files, we would strongly suggest you let CloudTech take care of it for you. Let us know if we should remove these log files."
    outputHandler ""
  fi
  if [ "$panel_type" == "plesk" ]
  then
    if [ $total_email_size_bytes -gt 524288000 ]
    then
      outputHandler "We have been able to detect one or more large email users on your system. Below is a list of the Top 25 users on your system."
      outputHandler ""
      outputHandler "$top25_email_user_list"
    else
      outputHandler "Since all email combined is less than 500MB, a detailed analysis of email user size was not performed."
      outputHandler ""
    fi
  fi
  if [ "$panel_type" == "plesk" ]
  then
    if [ ! -z "$end_dom_report" ]
    then
      outputHandler "Your domains are currently using $total_dom_size MB of your disk space. The following is a breakdown of the disk usage for any domain that has a document root larger than 100 MB:"
      outputHandler ""
      outputHandler "$end_dom_report" | sort -k 2 -nr
    else
      outputHandler "Currently, none of your domains have document roots larger than 100MB in size."
      outputHandler ""
    fi
  fi
  outputHandler "As part of the Disk Management service, we are happy to remove or truncate any of the above identified files, email users or domains upon request. If you require any further assistance, please do not hesitate to contact us by replying to this support request, or by giving us a call. We are here 24/7 to assist you. Thank you for continuing to use $co_name for your hosting needs."
  ## ^^^ line above has a variable that gets chosen based on -a (gd|mt) to ensure the correct company name is used. May need more attention as we do not want GD listed for a reseller.
  if ! $_headless; then
    ## Dont spit out divider and headers in headless mode
    outputHandler "$divider"
    outputHandler "END SUPPORT REQUEST"
    outputHandler "$divider"
  fi
}

## RUN IT!
get_dom_sizes
overall_disk_usage
inode_check
database_size
file_type
large_file_check
large_directory_check
old_check
restore_check
bin_logging
email_checks


if [[ $_headless == true ]]
then
  ## Be careful with the below section as it builds the
  ## json formatting while executing commands in subshells
  ## over multiple lines. Very easy to break this section.
  echo "{ \"note\" : \"$(
  for i in "${output_glob[@]}"
  do
    echo -e "$i"
  done | base64 -w 0
  )\", \"resolution\" : \"$(output_glob=()
  support_request
  for i in "${output_glob[@]}"
  do
    echo -e "$i"
  done |base64 -w 0)\", \"status\" : \"0\" }"
  ## End json output (the entire section above is a single echo)
else
  ## Not headless mode? just spit out resolution text normally
  support_request
fi

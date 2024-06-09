#!/bin/bash
#FileName: PerformanceAnalysisScript.sh
#NiceFileName: Performance Analysis Script
#FileDescription: Determine recommended optimization services for a server
# CloudTech Advanced Performance Analysis
#
# Written by the Mad Scientist jcrown for the (mt) Media Temple CloudTech team


# cleanup function in case of premature termination
function FINISH {
    rm -f -- "$0"
    exit
}

trap FINISH INT EXIT

##grab CT utility script and sources it
#source <(curl -s https://s3-us-west-2.amazonaws.com/mngsvcs-mstools-prod/includes/apa-deps/APAFunctions.sh)
##grab functions for security audit
#source <(curl -s https://s3-us-west-2.amazonaws.com/mngsvcs-mstools-prod/includes/apa-deps/s_audit.sh)
# Move the functions from the above files to a little below the debug section



## Need to get input to determine if we are running in headless mode.
while getopts "hza:" opt; do
  case "${opt}" in
  h) echo "-h for help"
     echo "-a (gd|mt) to set to 'gd' or 'mt'"
     echo "-z for headless mode (requires -a to be set also)"
  ;;

  z) _headless=true
  ;;

  a) platform=$OPTARG
  ;;

  \?) echo "Usage: $0 [-h] [-z] [-a (gd|mt)]"
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


## If headless mode, save up all output for the end. If not, echo it normally.
outputHandler() {
  if [[ $_headless == true ]]
  then
    tempIFS="$IFS"
    IFS=$'\n'
    output_glob+=("$1")
    IFS="$tempIFS"
  else
    echo -e "$1"
  fi
}



### Make sure this is being run by root, and exit if not
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   echo "This script will now exit!"
   exit 0
fi

########### CONSTANTS

host_type=''

# Define Text Colors
if [[ $_headless == true ]]
then
    ## No colors or escape codes for headless
    Escape="";
    BlackF=""
    RedB=""
    RedF=""
    CyanF=""
    Reset=""
    BoldOn=""
    BoldOff=""
else
    ## Non headless gets some pretty stuffs.
    Escape="\033";
    BlackF="${Escape}[30m"
    RedB="${Escape}[41m"
    RedF="${Escape}[31m"
    CyanF="${Escape}[36m"
    Reset="${Escape}[0m"
    BoldOn="${Escape}[1m"
    BoldOff="${Escape}[22m"
fi

## Divider changed from asterisk to hash to avoid mass globbing explosions
divider="${RedF}###################################################################${Reset}"
epoch=$(date +%s)
CWD="$PWD"


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
    echo "Unknown OS. Script will now quit"
    exit 0
fi
if [ "$debug" == "true" ]
then
    echo -e "$divider"
    echo "Below is the variables in the os_check function."
    echo ""
    echo "$distro_base"
    echo "$distro_os"
    echo "$distro_os_version"
    echo ""
    echo -e "$divider"
fi


######################## Start APAFunctions.sh merge
function get_inode_usage() {
  df -i | head -2 | tail -1 | awk '{print $5}' | sed 's/%//'
}

## source file for commonlly used bash functions

## find target domain on Plesk:

function get_target_domain_plesk() {
    if [ -d  "/var/www/vhosts/system" ]; then
        d=$(date +"%d/%b/%Y" -d "yesterday");
        for i in $(cd /var/www/vhosts/system/; ls -d *.*); do
            f="/var/www/vhosts/system/$i/logs/access_log*";
            c=$(grep -s "$d" $f | wc -l);
            if (( $c > 0 )); then
                echo $c $i;
            fi
            c="0";
        done | sort -nr;
    else
        d=$(date +"%d/%b/%Y" -d "yesterday");
        for i in $(cd /var/www/vhosts/; ls -d *.*); do
            f="/var/www/vhosts/$i/statistics/logs/access_log*";
            c=$(grep -s "$d" $f | wc -l);
            if (( $c > 0 )); then
                echo $c $i;
            fi
            c="0";
        done | sort -nr;
    fi | head -1 | awk '{print $2}' | sed 's/\\//g'
}

## find target domain on cPanel:

function get_target_domain_cpanel() {
    if [ -d  "/usr/local/apache/domlogs/" ]; then
        d=$(date +"%d/%b/%Y" -d "yesterday");
        for i in $(</etc/localdomains); do
            f="/usr/local/apache/domlogs/$i";
            c=$(grep -s "$d" $f | wc -l);
            if (( $c > 0 )); then
                echo $c $i;
            fi
            c="0";
        done | sort -nr;
    else
        d=$(date +"%d/%b/%Y" -d "yesterday");
        for i in $(</etc/localdomains); do
            f="/usr/local/apache/domlogs/$i";
            c=$(grep -s "$d" $f | wc -l);
            if (( $c > 0 )); then
                echo $c $i;
            fi
            c="0";
        done | sort -nr;
    fi | head -1 | awk '{print $2}' | sed 's/\\//g'
}

## check if server is cPanel or Plesk

function get_panel_type () {
    if [ -d '/usr/local/psa' ] && [ ! -d '/usr/local/cpanel' ]
    then
        panel_type='plesk'
        #See If This is MT or GD
        if [ -d "/usr/local/mt" ]
            then
            host_type='mt'
        else
            host_type='gd'
        fi
    elif [ -d '/usr/local/cpanel' ] && [ ! -d '/usr/local/psa' ]
    then
        panel_type='cpanel'
        host_type='gd'
        else
        panel_type='none'
    fi
    echo $panel_type
}

## get MySQL slow query log location/verify it's enabled

function get_slow_query_log() {
    panel=$(get_panel_type);
    if [ $panel = 'plesk' ]; then
        file_check="$(grep '^slow[-_]query[-_]log[-_]file' /etc/my.cnf)"
        if [ ! -z "$file_check" ]; then
            logPath=$(mysql -Ns -u admin -p`cat /etc/psa/.psa.shadow` -e "SHOW GLOBAL VARIABLES LIKE '%slow%log%file%';" | awk '{print $2}');
        else
            logPath=""
        fi
    else
        file_check="$(grep '^slow[-_]query[-_]log[-_]file' /etc/my.cnf)"
        if [ ! -z "$file_check" ]; then
            logPath=$(sudo mysql -Ns -e "SHOW GLOBAL VARIABLES LIKE '%slow%log%file%';" | awk '{print $2}');
        else
            logPath=""
        fi
    fi
    echo $logPath
}

## get cpu uptime from 1, 5 and 10 min marks
## jradams - we should use proc instead, its more universal: cat /proc/loadavg - job for another time.
## 1 min
function get_cpu_1_min () {
    /usr/bin/uptime | awk '{print $10}' | sed 's/,*\r*$//'
}

## 5 min
function get_cpu_5_min () {
    /usr/bin/uptime | awk '{print $11}' | sed 's/,*\r*$//'
}

## 15 min
function get_cpu_15_min () {
    /usr/bin/uptime | awk '{print $12}' | sed 's/,*\r*$//'
}

## get # of cpu cores avail on system
function get_cpu_core_num () {
    cat /proc/cpuinfo | grep -i 'model name' | wc -l
}

## calculate cpu usage 1, 5 and 15 min

function calc_1 () {
    utime=$(get_cpu_1_min)
    cores=$(get_cpu_core_num)
    percent=$(awk "BEGIN { pc=100*${utime}/${cores}; i=int(pc); print (pc-i<0.5)?i:i+1 }")
    echo $percent
}

function calc_15 () {
    utime=$(get_cpu_15_min)
    cores=$(get_cpu_core_num)
    percent=$(awk "BEGIN { pc=100*${utime}/${cores}; i=int(pc); print (pc-i<0.5)?i:i+1 }")
    echo $percent
}

function calc_5 () {
    utime=$(get_cpu_5_min)
    cores=$(get_cpu_core_num)
    percent=$(awk "BEGIN { pc=100*${utime}/${cores}; i=int(pc); print (pc-i<0.5)?i:i+1 }")
    echo $percent
}

## get memory usage and output it as human readable

function get_mem_total () {
    mem_total=$( free -m | grep 'Mem:' | awk '{ print $2 }' )
    echo "$mem_total"
}

function get_mem_free () {
    mem_free=$( free -m | grep 'Mem:' | awk '{ print $4 }' )
    echo "$mem_free"
}

function get_mem_avail () {
  mem_avail=$( free -m | grep 'Mem:' | awk '{ print $7 }' )
    echo "$mem_avail"
}

function get_mem_cached () {
    mem_cached=$( free -m | grep 'Mem:' | awk '{ print $6 }' )
    echo "$mem_cached"
}

function get_mem_used () {
    mem_used=$(free -m | grep 'Mem:' | awk '{ print $3 }')
    echo "$mem_used"
}

function check_mem_status () {
  mtotal=$(get_mem_total)
  mfree=$(get_mem_free)
  mavail=$(get_mem_avail)
  mfreetotal=$(( mfree + mavail ))
  percent=$(awk "BEGIN { pc=100*${mtotal}/${mfreetotal}; i=int(pc); print (pc-i<0.5)?i:i+1 }")
  echo "$percent"
}

function high_inode_dirs () {
  panel=$(get_panel_type)
  if [ "$panel" == "plesk" ]; then
    high_inode_dirs_list=$(find /var/www/vhosts/ -printf '%h\n' | sort | uniq -c | sort -k 1 -nr | awk '$1>1023')
  elif [ "$panel" == "cpanel" ]; then
    high_inode_dirs_list=$(find /home/ \( -path "/home/virtfs" -o -path "/home/cpeasyapache" \) -prune -o -printf '%h\n' | sort | uniq -c | sort -k 1 -nr | awk '$1>1023')
  else
    high_inode_dirs_list=$(find /var/www/ -printf '%h\n' | sort | uniq -c | sort -k 1 -nr | awk '$1>1023')
  fi
}
######################## END APAFunctions.sh merge


######################## Start s_audit.sh merge

function init {
  outputHandler "Welcome to CloudTech Performance Analysis/Security Audit tool."
  outputHandler "$divider"
  if [[ $_headless != true ]];
  then
    while true
    do
      echo -e "Are you running this on (mt) Media Temple or GoDaddy?"
      echo -e "$divider"
      echo "* [1] (mt) Media Temple (Non CloudTech) *"
      echo "* [2] (mt) Media Temple (CloudTech Subscriber) *"
      echo "* [3] GoDaddy *"
      read -r yourch
      case $yourch in
        1 ) whost="mt"
          cost="\$79"
          break;;
        2 ) whost="mt"
          cost="1 CloudTech Credit"
          break;;
        3 ) whost="gd"
          cost="Please call for pricing."
          break;;
        * ) echo "Invalid option";;
      esac
    done
  else
    whost=$platform
    cost="Please call for pricing."
    yourch="N/A - Headless operation"
  fi
  outputHandler "You are running this on $whost"
  outputHandler "$divider"
  outputHandler "You Selected $yourch"
  outputHandler "$divider"
  outputHandler "Your Cost $cost"
  outputHandler "$divider"
}

function running_user {
    if [  "$panel_type" != "gs" ] && [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root" 1>&2
        echo "This script will now exit!"
        exit 0
    fi
}

function os_check {
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
            echo -e "$divider"
            echo "Below is the variables in the os_check function."
            echo ""
            echo "$distro_base"
            echo "$distro_os"
            echo "$distro_os_version"
            echo ""
            echo -e "$divider"
    fi
}

function platform_check {
    if [ -d '/usr/local/psa' ] && [ ! -d '/usr/local/cpanel' ] && [ "$distro_os" == "centos" ]
    then
        panel_type='plesk'
        sqlConnect="mysql -A -N -u admin -p$(cat /etc/psa/.psa.shadow) psa -e"
        # Removing 'egrep -v' from below and adding it to the commands where it is called (later)
        docRoot_exclude="'mail|logs|\.cpanel|tmp|etc|cpanel3-skel|\.htpasswds'"
        docRoot="/var/www/vhosts/"
        plesk_ver=$(cat /usr/local/psa/version | awk -F '.' '{ print $1$2 }')
        raw_plesk_ver=$(cat /usr/local/psa/version | awk '{ print $1 }')
        if [ "$plesk_ver" -ge 115 ]
        then
            log_dir="/var/www/vhosts/*/logs"
        else
            log_dir="/var/www/vhosts/*/statistics/logs"
        fi
        mkdir -p /root/CloudTech/logs
    elif [ -d '/usr/local/cpanel' ] && [ ! -d '/usr/local/psa' ] && [ "$distro_os" == "centos" ]
    then
        panel_type='cpanel'
        docRoot="/home/*/"
        # Removing 'egrep -v' from below and adding it to the commands where it is called (later)
        docRoot_exclude="'mail|logs|\.cpanel|tmp|etc|cpanel3-skel|\.htpasswds'"
        whost="gd"
        mkdir -p /root/CloudTech/logs
    elif  [ -d /usr/local/mtapps ]
    then
        panel_type='gs'
        site_id=$(echo $PWD |awk -F/ '{ print $3 }')
        docRoot="/home/$site_id/domains/*/"
        mkdir -p ~/data/CloudTech/logs
    elif [ "$distro_os" == "ubuntu" ]
    then
        panel_type='ubuntu_general'
        mkdir -p /root/CloudTech/logs
        docRoot="unknown"
        skip_app_check="true"
    elif [ "$distro_os" == "centos" ]
    then
        panel_type='centos-nopanel'
        mkdir -p /root/CloudTech/logs
        docRoot="unknown"
        skip_app_check="true"
    elif [ "$distro_os" == "fedora" ]
    then
        panel_type='fedora'
        mkdir -p /root/CloudTech/logs
        docRoot="unknown"
        skip_app_check="true"

    else
        outputHandler "An error occured. There is no platform type."
        outputHandler "Script will now exit!"
        exit 0
    fi
    if [ "$debug" == "true" ]
    then
        echo -e "$divider"
        echo "Debug mode is ON! Below are the variables used in the platform_check function."
        echo ""
        echo "Panel Type in use:"
        echo ""
        echo "$panel_type"
        echo ""
        echo "Document root in use:"
        echo ""
        echo "$docRoot"
        echo ""
        if [ "$panel_type" == "gs" ]
        then
            echo "Grid Site ID:"
            echo ""
            echo "$site_id"
            echo ""
        fi
        echo -e "$divider"
    fi
}

function mta {
    if [ ! "$panel_type" == "gs" ]
    then
        postfix_check=$(ps aux | egrep -i "postfi[x]")
        qmail_check=$(ps aux | egrep -i "qmail-sen[d]")
        exim_check=$(ps aux | egrep -i "exi[m]")
        if [ ! -z "$postfix_check" ]
        then
            mta="postfix"
            queue_size_check="true"
        elif [ ! -z "$qmail_check" ]
        then
            mta="qmail"
            queue_size_check="true"
        elif [ ! -z "$exim_check" ]
        then
            mta="exim"
            queue_size_check="true"
        else
            mta="unknown"
            queue_size_check="false"
        fi
    fi
    if [ "$debug" == "true" ]
    then
        echo -e "$divider"
        echo "Below are the varibles set in the mta function."
        echo ""
        echo "postfix_check:"
        echo ""
        echo "$postfix_check"
        echo ""
        echo "qmail_check:"
        echo ""
        echo "$qmail_check"
        echo ""
        echo "exim_check:"
        echo ""
        echo "$exim_check"
        echo ""
        echo "mta:"
        echo ""
        echo "$mta"
        echo ""
        echo -e "$divider"
    fi
}

function ssh_security {
    if [ "$distro_os" == "centos" ] || [ "$distro_os" == "fedora" ]
    then
        outputHandler "$divider"
        outputHandler "${BoldOn}Sucessful root logins${BoldOff}"
        outputHandler "$divider"
        root_logins=$(cat /var/log/secure* | grep "root" | grep "Accepted" | egrep -v "72.10.62.1|192.168.20|64.207.129.23|64.207.162.13|172.18.90.|172.18.82.|205.186.147.124|64.207.129.42" | awk '{ print $11 }' | sort | uniq -c | sort -nr)
        if [ ! -z "$root_logins" ]
        then
            outputHandler "Below are the accepted root user SSH attempts, sorted by IP address:"
            outputHandler "Count IP"
            outputHandler ""
            outputHandler "$root_logins"
            outputHandler ""
        else
            outputHandler "No root SSH attempts on this server."
            outputHandler ""
        fi
        ssh_password_attempts=$(zgrep -e "Failed password" /var/log/secure* | egrep -vc "72.10.62.1|192.168.20|64.207.129.23|64.207.162.13|64.207.129.42")
        outputHandler "The total number of failed SSH login attempts is $ssh_password_attempts tries!."
        outputHandler "$divider"
    elif [ "$distro_base" == "debian" ] && [ ! "$panel_type" == "gs" ]
    then
        outputHandler "$divider"
        outputHandler "${BoldOn}Sucessful root logins${BoldOff}"
        outputHandler "$divider"
        root_logins=$(zgrep "Accepted password for root from" /var/log/auth.log* | egrep -v "72.10.62.1|192.168.20|64.207.129.23|64.207.162.13|172.18.90.|172.18.82.|64.207.129.42" | awk '{ print $11 }' | sort | uniq -c | sort -nr)
        if [ ! -z "$root_logins" ]
        then
            outputHandler "Below are the accepted root user SSH attempts, sorted by IP address:"
            outputHandler "Count IP"
            outputHandler ""
            outputHandler "$root_logins"
            outputHandler ""
        else
            outputHandler "No root SSH attempts on this server."
            outputHandler ""
        fi
        ssh_password_attempts=$(zgrep "Failed password" /var/log/auth.log* | egrep -vc "72.10.62.1|192.168.20|64.207.129.23|64.207.162.13|64.207.129.42")
        outputHandler "The total number of failed SSH login attempts is $ssh_password_attempts tries!"
        outputHandler "$divider"
    else
        outputHandler "$divider"
        outputHandler "OS Not supported for sucessful root logins check"
        outputHandler "$divider"
    fi
    if [ "$debug" == "true" ]
    then
        echo "Below are the variables used in the ssh_security function:"
        echo ""
        echo "root_logins:"
        echo ""
        echo "$root_logins"
        echo ""
        echo "ssh_password_attempts:"
        echo ""
        echo "$ssh_password_attempts"
        echo ""
    fi
}

function port_check {
    if [ "$distro_os" == "centos" ] || [ "$distro_os" == "fedora" ] && [ "$panel_type" == "plesk" ]
    then
        strange_ports=$(netstat -pln | grep -v "xfs\|Proto RefCnt Flags\|sw-engine\|Active UNIX\|Proto Recv-Q Send-Q Local Address\|Active Internet connections (only servers)\|:3306\|:7080\|:7081\|:10001\|:53\|:22\|:443\|:8443\|:21\|:953\|:993\|:995\|:8880\|:106\|:110\|:143\|:465\|:80\|:25\|:783\|master\|mysql.sock\|/tmp/spamd_full.sock\|php-cgi\|psa-pc-remote\|/var/run/dbus/system_bus_socket\|fail2ban.sock\|saslauthd/mux\|/var/run/authdaemon.courier-imap/socket.tmp\|/com/ubuntu/upstart\|/tmp/.newrelic.sock")
        if [ ! -z "$strange_ports" ]
        then
            outputHandler "${BoldOn}Below are a list of stange ports and sockets.${BoldOff}"
            outputHandler "$divider"
            outputHandler "$strange_ports"
            outputHandler "$divider"
        else
            outputHandler "Nothing is listening on stange ports or sockets"
            outputHandler "$divider"
        fi
    elif [ "$distro_os" == "centos" ] || [ "$distro_os" == "fedora" ] && [ "$panel_type" == "cpanel" ]
    then
        strange_ports=$(netstat -pln | grep -v "xfs\|Proto RefCnt Flags\|sw-engine\|Active UNIX\|Proto Recv-Q Send-Q Local Address\|Active Internet connections (only servers)\|:3306\|:53\|:22\|:443\|:21\|:953\|:993\|:995\|:110\|:143\|:465\|:80\|:25\|:587\|:2082\|:2083\|:2086\|:2087\|:2095\|:2096\|:2077\|:2078\|:783\|/var/run/dovecot\|/var/lib/mysql/mysql.sock\|/var/cpanel/dnsadmin/sock\|/usr/local/cpanel/var/cp\|/var/run/ftpd.sock\|/var/run/cphulkd.sock\|/var/run/saslauthd/mux\|/usr/local/apache/logs/fpcgisock\|/com/ubuntu/upstart\|/tmp/.newrelic.sock")
        if [ ! -z "$strange_ports" ]
        then
            outputHandler "${BoldOn}Below are a list of stange ports and sockets.${BoldOff}"
            outputHandler "$divider"
            outputHandler "$strange_ports"
            outputHandler "$divider"

        else
            outputHandler "Nothing is listening on stange ports or sockets"
            outputHandler "$divider"
        fi
    elif [ "$distro_os" == "centos" ] || [ "$distro_os" == "fedora" ]
    then
        strange_ports=$(netstat -pln)
        if [ ! -z "$strange_ports" ]
        then
            outputHandler "${BoldOn}Below are a list of ALL ports and sockets.${BoldOff}"
            outputHandler "$divider"
            outputHandler "$strange_ports"
            outputHandler "$divider"
        else
            outputHandler "Nothing is listening on ANY ports or sockets"
            outputHandler "$divider"
        fi
    else
        outputHandler "OS Not supported for sucessful stange ports check."
        outputHandler "$divider"
    fi
    if [ "$debug" == "true" ]
    then
        echo "Below are the variables used in the port_check function:"
        echo ""
        echo "strange_ports:"
        echo ""
        echo "$strange_ports"
    fi
}

function user_check {
    if [ "$distro_os" == "centos" ] || [ "$distro_os" == "fedora" ] && [ "$panel_type" == "plesk" ]
    then
        #Build User List From PSA DB
        user_list="("
        for i in $($sqlConnect 'select login from sys_users')
        do
            user_list="$user_list$i|"
        done

        #get rid of last | and end the user list
        user_list=$(sed 's/\(.*\)|/\1/' <<< $user_list)
        user_list="$user_list)"

        outputHandler "Below are system users that have shell access"
        outputHandler "${BoldOn}${CyanF}Users that always have access, such as root are excluded.${Reset}"
        outputHandler "$divider"
        outputHandler "${BoldOn}The Following Users Were Not Created In Plesk, But Have Shell Access. They are potentially a ${RedF}HIGH${Reset}${BoldOn} security risk:${BoldOff}"
        outputHandler "$divider"
        shell_user_high=`cat /etc/passwd | grep "/bin/bash" | grep -v "root:x:0:0\|mysql:x:27:27\|cloudtech_\|ctmal" | egrep -v $user_list`
        outputHandler "$shell_user_high"
        outputHandler "$divider"
        outputHandler "${BoldOn}The Following Users Have Shell Access, But Were Created Legitimately. They are a ${CyanF}LOW${Reset}${BoldOn} security risk:${BoldOff}"
        outputHandler "$divider"
        shell_user_low=`cat /etc/passwd | grep "/bin/bash" | grep -v "root:x:0:0\|mysql:x:27:27\|cloudtech_\|ctmal" | egrep $user_list`
        outputHandler "$shell_user_low"
        outputHandler "$divider"
    fi
}


function ssh_port_check {
  if [ "$distro_base" == "debian" ] || [ "$distro_base" == "redhat" ] && [ "$panel_type" != "gs" ]
  then
    ssh_port=$(netstat -pln | egrep "ssh|sshd" | head -1 | awk '{print $4}')
        if [[ "$ssh_port" != *22 ]]
        then
            ssh_check="true"
        else
            ssh_check="false"
        fi
  fi
  if [ "$debug" == "true" ]
    then
        echo -e "$divider"
        echo "DEBUG for ssh_port_check function"
        echo ""
        echo "ssh_check:"
        echo ""
        echo "$ssh_check"
        echo ""
        echo -e "$divider"
  fi
}

function fail2ban_checker {
  if [ "$distro_base" == "debian" ] || [ "$distro_base" == "redhat" ] && [ "$panel_type" != "gs" ]
    then
        fail2ban_socket=$(netstat -pln | grep "fail2ban.sock")
        if [ ! -z "$fail2ban_socket" ]
            then
                fail2ban_check="true"
            else
                fail2ban_check="false"
        fi
        if [ "$debug" == "true" ]
        then
            echo -e "$divider"
            echo "DEBUG for fail2ban_checker function"
            echo ""
            echo "fail2ban_check:"
            echo ""
            echo "$fail2ban_check"
            echo ""
            echo -e "$divider"
        fi
    fi
}


function mail_count {
    outputHandler "Mail Queue Checker:"
    outputHandler "$divider"
    queue_count="0"
    if [ "$mta" == "qmail" ]
    then
        outputHandler "This is qMail"
        outputHandler "$divider"
        queue_count=$(/var/qmail/bin/qmail-qstat | head -1 | awk '{print $4}')
        if [ "$queue_count" == "0" ]
        then
            outputHandler "Queue is empty"
            outputHandler "$divider"
        else
            outputHandler "Mail in queue: $queue_count"
            outputHandler "$divider"
        fi
    elif [ "$mta" == "postfix" ]
    then
        outputHandler "This is Postfix"
        outputHandler "$divider"
        queue_count=$(find /var/spool/postfix/ -type f | egrep -v "pid/|plesk" | wc -l)
        if [ "$queue_count" == "0" ]
        then
            outputHandler "Queue is empty"
            outputHandler "$divider"
        else
            outputHandler "Mail in queue: $queue_count"
            outputHandler "$divider"
        fi
    elif [ "$mta" == "exim" ]
    then
        outputHandler "This is Exim"
        outputHandler "$divider"
        queue_count=$(exim -bpc)
        if [ "$queue_count" == "0" ]
        then
            outputHandler "Queue is empty"
            outputHandler "$divider"
        else
            outputHandler "Mail in queue: $queue_count"
            outputHandler "$divider"
        fi
    else
        outputHandler "Your MTA is not supported. Check will be skipped."
    fi
}

function hiddendir {
    if [ "$distro_base" == "debian" ] || [ "$distro_base" == "redhat" ] && [ "$panel_type" != "gs" ]
    then
        outputHandler "The following are a list of hidden directories in /root and /tmp that MAY be suspicious!"
        outputHandler "$divider"
        outputHandler "$(find /root -type d -name ".*" | egrep -v "autoinstaller|ssh|pki")"
        outputHandler "$(find /tmp -type d -name ".*" | egrep -v "ICE-unix|font-unix")"
        outputHandler "$divider"
    fi
}

function perm_check {
    outputHandler "Permission Checker"
    outputHandler "$divider"
    if [ "$debug" != "true" ] && [ "$panel_type" != "gs" ] && [ "$docRoot" != "unknown" ]
    then
        outputHandler "The Following Directories Inside Of $docRoot Have 777 Permissions:"
        outputHandler ""
        perm_dir=$(find $docRoot ! -path \*/anon_ftp\* -type d -perm 0777 | egrep -v $docRoot_exclude)
        if [[ $(echo "$perm_dir" | wc -l) -lt 20 ]] ; then
            outputHandler "$perm_dir"
        else
            outputHandler "The results have been written to /root/CloudTech/logs/weak_dir_perms_$epoch.txt"
            perm_dir_path="/root/CloudTech/logs/weak_dir_perms_$epoch.txt"
            outputHandler "Below are a list of directories that have 777 permissions." >> /root/CloudTech/logs/weak_dir_perms_$epoch.txt
            outputHandler "" >> /root/CloudTech/logs/weak_dir_perms_$epoch.txt
            outputHandler "$perm_dir" >> /root/CloudTech/logs/weak_dir_perms_$epoch.txt
        fi

        outputHandler "$divider"
        outputHandler "The Following Files Inside Of $docRoot Have 777 Permissions:"
        outputHandler "$divider"
        perm_file=$(find $docRoot ! -path \*/anon_ftp\* -type f -perm 0777 | egrep -v $docRoot_exclude)
        if [[ $(echo "$perm_file" | wc -l) -lt 20 ]]
        then
            outputHandler "$perm_file"
        else
            outputHandler "The results have been written to /root/CloudTech/logs/weak_file_perms_$epoch.txt"
            perm_file_path="/root/CloudTech/logs/weak_file_perms_$epoch.txt"
            outputHandler "Below are a list of directories that have 777 permissions." >> /root/CloudTech/logs/weak_file_perms_$epoch.txt
            outputHandler "" >> /root/CloudTech/logs/weak_file_perms_$epoch.txt
            outputHandler "$perm_file" >> /root/CloudTech/logs/weak_file_perms_$epoch.txt
        fi
    elif [ "$debug" != "true" ] && [ "$panel_type" == "gs" ]
    then
        outputHandler "The Following Directories Inside Of $docRoot Have 777 Permissions:"
        outputHandler "$divider"
        perm_dir=$(find $docRoot -type d -perm 0777)
        if [[ $(echo "$perm_dir" | wc -l) -lt 20 ]]
        then
            outputHandler "$perm_dir"
        else
            outputHandler "The results have been written to ~/data/CloudTech/logs/weak_dir_perms_$epoch.txt"
            perm_dir_path="~/data/CloudTech/logs/weak_dir_perms_$epoch.txt"
            outputHandler "Below are a list of directories that have 777 permissions." >> ~/data/CloudTech/logs/weak_dir_perms_$epoch.txt
            outputHandler "" >> ~/data/CloudTech/logs/weak_dir_perms_$epoch.txt
            outputHandler "$perm_dir" >> ~/data/CloudTech/logs/weak_dir_perms_$epoch.txt
        fi
        outputHandler "$divider"
        outputHandler "The Following Files Inside Of $docRoot Have 777 Permissions:"
        outputHandler "$divider"
        perm_file=$(find $docRoot -type f -perm 0777)
        if [[ $(echo "$perm_file" | wc -l) -lt 20 ]]
        then
            outputHandler "$perm_file"
        else
            outputHandler "The results have been written to ~/data/CloudTech/logs/weak_file_perms_$epoch.txt"
            perm_file_path="~/data/CloudTech/logs/weak_file_perms_$epoch.txt"
            outputHandler "Below are a list of directories that have 777 permissions." >> ~/data/CloudTech/logs/weak_file_perms_$epoch.txt
            outputHandler "" >> ~/data/CloudTech/logs/weak_file_perms_$epoch.txt
            outputHandler "$perm_file" >> ~/data/CloudTech/logs/weak_file_perms_$epoch.txt
        fi
    fi
}

function cms_check {
    outputHandler "Outdated CMS Checker"
    outputHandler $divider
    if [ "$docRoot" != "unknown" ]
    then
        wp_version=$(curl -s http://api.wordpress.org/core/version-check/1.4/ | grep "^[0-9]" | head -1)
        joomla_version=$(curl --silent http://www.joomla.org/download.html | grep -m 1 "newest version" | awk -F'Joomla' '{print $2}' | awk '{print $1}')
    fi
    if [ "$debug" != "true" ] && [ "$docRoot" != "unknown" ]
    then
        outputHandler "If script contines without listing version, this means no CMS's of that type were found"
        outputHandler $divider
        outputHandler  "Below are the ${RedF}OUT OF DATE${Reset} WordPress versions."
        outputHandler ""
        outdated_wp=$(find $docRoot -name 'version.php' | xargs grep -H "wp_version =" | grep -v "$wp_version")
        if [ ! -z "$outdated_wp" ]
        then
            outputHandler "$outdated_wp"
        else
            outputHandler "No outdated versions of WordPress found."
        fi
        outputHandler $divider
        outputHandler "Below are the ${RedF}OUT OF DATE${Reset} Joomla versions."
        outputHandler ""
        outdated_joomla1=$(find $docRoot -name 'version.php' | xargs grep -H -F 'public $RELEASE' | grep -v "$joomla_version")
        outdated_joomla2=$(find $docRoot -name 'version.php' | xargs grep -H -F 'var $RELEASE' | grep -v "$joomla_version")
        if [ ! -z "$outdated_joomla1" ] || [ ! -z "$outdated_joomla2" ]
        then
            if [ ! -z "$outdated_joomla1" ]
            then
                outputHandler "$outdated_joomla1"
            fi
            if [ ! -z "$outdated_joomla2" ]
            then
                outputHandler "$outdated_joomla2"
            fi
        else
            outputHandler "No outdated versions of Joomla found."
        fi
        outputHandler $divider
        outputHandler "Below are ${RedF}ALL${Reset} installed Drupal versions. This information is not in the support request"
        outputHandler ""
        drupal_versions=$(find $docRoot -name "bootstrap.inc" -type f -print | xargs egrep -H "'VERSION'")
        if [ ! -z "$drupal_versions" ]
        then
            outputHandler "$drupal_versions"
        else
            outputHandler "No Drupal installs found."
            outputHandler -e $divider
        fi
    elif [ "$docRoot" == "unknown" ]
    then
        outputHandler "Since the docRoot is unknown, this check will be skipped."
        outputHandler $divider
    else
        outputHandler $divider
        outputHandler "CMS CHECKER DEBUG MODE"
        outputHandler ""
        outputHandler "wp_version:"
        outputHandler ""
        outputHandler "$wp_version"
        outputHandler ""
        outputHandler "joomla_version:"
        outputHandler ""
        outputHandler "$joomla_version"
        outputHandler ""
        outputHandler "docRoot:"
        outputHandler ""
        outputHandler "$docRoot"
        outputHandler $divider
    fi
}

function timthumb_check {
    outputHandler "Outdated timthumb.php Checker"
    outputHandler $divider
    if [ "$docRoot" != "unknown" ]
    then
        current_timthumb=$(curl -s http://timthumb.googlecode.com/svn/trunk/timthumb.php | egrep "'VERSION'|\"VERSION\"" | awk -F \' '{print $4}')
        outdated_timthumb=$(find $docRoot -name '*thumb.php' -type f | xargs egrep -H "'VERSION'|\"VERSION\"" | grep -v "$current_timthumb" | awk -F \; '{print $1}')
    fi
    if [ "$debug" != "true" ] && [ "$docRoot" != "unknown" ]
  then
    if [ ! -z "$outdated_timthumb" ]
        then
            outputHandler "Below are the outdated versions of timthumb.php"
            outputHandler ""
            outputHandler "$outdated_timthumb"
            outputHandler $divider
        else
            outputHandler $divider
            outputHandler "No Outdated versions of timthumb.php were found."
            outputHandler $divider
    fi
  elif [ "$docRoot" == "unknown" ]
    then
        outputHandler "Since the docRoot is unknown, this check will be skipped."
        outputHandler $divider
  else
    outputHandler "Below are the variable used in the timthumb.php checker:"
    outputHandler ""
    outputHandler "current_timthumb:"
    outputHandler ""
    outputHandler "$current_timthumb"
    outputHandler ""
    outputHandler "outdated_timthumb"
    outputHandler ""
    outputHandler "$outdated_timthumb"
    outputHandler ""
    outputHandler "docRoot:"
    outputHandler ""
    outputHandler "$docRoot"
    outputHandler $divider
    fi
}

function revslider_check {
    outputHandler "Outdated RevSlider Checker"
    outputHandler $divider
    if [ "$docRoot" != "unknown" ]
    then
        all_revslider=$(find $docRoot -name 'revslider.php' -type f | xargs egrep -H "revSliderVersion")
    fi
    if [ "$debug" != "true" ] && [ "$docRoot" != "unknown" ]
    then
        if [ ! -z "$all_revslider" ]
        then
            outputHandler "Below are the versions of RevSlider. Anything below 4.1.4 is hackable."
            outputHandler ""
            outputHandler "$all_revslider"
            outputHandler $divider
        else
            outputHandler $divider
            outputHandler "No versions of RevSlider were found."
            outputHandler $divider
        fi
    elif [ "$docRoot" == "unknown" ]
    then
        outputHandler "Since the docRoot is unknown, this check will be skipped."
        outputHandler $divider
    else
        outputHandler "Below are the variable used in the RevSlider checker:"
        outputHandler ""
        outputHandler "all_revslider"
        outputHandler ""
        outputHandler "$all_revslider"
        outputHandler ""
        outputHandler "docRoot:"
        outputHandler ""
        outputHandler "$docRoot"
        outputHandler $divider
    fi
}

function AIO_seo_pack_check {
    outputHandler "Outdated all-in-one-seo-pack Checker"
    outputHandler $divider
    if [ "$docRoot" != "unknown" ]
    then
        all_AIO_seo_pack_check=$(find $docRoot -name 'all_in_one_seo_pack.php' -type f | xargs egrep -H "Version:")
    fi
    if [ "$debug" != "true" ] && [ "$docRoot" != "unknown" ]
    then
        if [ ! -z "$all_AIO_seo_pack_check" ]
        then
            outputHandler "Below are the versions of All In One SEO Pack. Anything below 2.1.6 is hackable."
            outputHandler ""
            outputHandler "$all_AIO_seo_pack_check"
            outputHandler $divider
        else
            outputHandler $divider
            outputHandler "No versions of All In one SEO Pack were found."
            outputHandler $divider
        fi
    elif [ "$docRoot" == "unknown" ]
    then
        outputHandler "Since the docRoot is unknown, this check will be skipped."
        outputHandler $divider
    else
        outputHandler "Below are the variable used in the RevSlider checker:"
        outputHandler ""
        outputHandler "all_revslider"
        outputHandler ""
        outputHandler "$all_revslider"
        outputHandler ""
        outputHandler "docRoot:"
        outputHandler ""
        outputHandler "$docRoot"
        outputHandler $divider
    fi
}

function jce_check {
    if [ "$docRoot" != "unknown" ]
    then
        all_jce=$(find $docRoot -name '*jce.xml' -type f | xargs egrep -o 'extension version="([^"]*)"')
        vuln_jce=$(echo "$all_jce" | egrep -v "2\.[1-9]" | egrep -v "2\.\0\.1[1-9]" | egrep -v "2\.0\.[2-9]")
    fi
    outputHandler "Joomla JCE checker"
    outputHandler $divider

    if [ "$debug" != "true" ] && [ "$docRoot" != "unknown" ]
    then
        if [ -z "vuln_jce" ]
            then
                outputHandler "Below are the vulnerable versions of the Joomla JCE Module"
                outputHandler ""
                outputHandler "$vuln_jce"
                outputHandler $divider
            else
                outputHandler "No Vulnerable version of Joomla JCE were found."
                outputHandler $divider
        fi
    elif [ "$docRoot" == "unknown" ]
    then
        outputHandler "Since the docRoot is unknown, this check will be skipped."
        outputHandler $divider
    else
        outputHandler "Below are the variable used in the Joomla JCE checker:"
        outputHandler ""
        outputHandler "all_jce:"
        outputHandler ""
        outputHandler "$all_jce"
        outputHandler ""
        outputHandler "vuln_jce"
        outputHandler ""
        outputHandler "$vuln_jce"
        outputHandler ""
        outputHandler "docRoot:"
        outputHandler ""
        outputHandler "$docRoot"
        outputHandler $divider
    fi
}

function scANDtc_check  {
    if [ "$docRoot" != "unknown" ]
    then
        #Total Cache Version. Any version below 0.9.2.9 is exploitable
        tc_versions=$(find $docRoot -name "w3-total-cache.php" -type f -print | xargs grep -H "Version:")
        #Suoer Cache check. Anything below 1.4.4 is exploitable
        sc_versions=$(find $docRoot -name "wp-cache.php" -type f -print | xargs grep "Version:"  | grep -v "1.[5-9]" | grep -v "1.[4-9].[4-9]" | grep -v "2\.....")
    fi
    outputHandler "Super Cache / Total Cache exploit checker"
    outputHandler $divider
    if [ "$debug" != "true" ] && [ "$docRoot" != "unknown" ]
    then
        outputHandler "Below are the exploitable versions of WP Super Cache"
        outputHandler ""
        if [ -z "$sc_versions" ]
        then
            outputHandler "$sc_versions"
            outputHandler $divider
        else
            outputHandler "No exploitable versions of WP Super Cache were found."
            outputHandler $divider
        fi
        outputHandler "Below are ALL versions of W3-Total Cache"
        outputHandler ""
        if [ -z "$tc_versions" ]
        then
            outputHandler "$tc_versions"
            outputHandler $divider
        else
            outputHandler "No exploitable versions of WP Super Cache were found."
            outputHandler $divider
        fi
    elif [ "$docRoot" == "unknown" ]
    then
        outputHandler "Since the docRoot is unknown, this check will be skipped."
        outputHandler $divider
    else
        outputHandler "Below are the variable used in the scANDtc_check:"
        outputHandler ""
        outputHandler "sc_versions:"
        outputHandler ""
        outputHandler "$sc_versions"
        outputHandler ""
        outputHandler "tc_versions"
        outputHandler ""
        outputHandler "$tc_versions"
        outputHandler ""
        outputHandler "docRoot:"
        outputHandler ""
        outputHandler "$docRoot"
        outputHandler $divider
    fi
}

function xmlrpc {
    if [ "$docRoot" != "unknown" ] && [ "$panel_type" == "plesk" ]
    then
        xmlrpc_logs=$(cat $log_dir/access_log | grep "POST" | grep "xmlrpc.php")
        xmlrpc_count=$(echo "$xmlrpc_logs" | wc -l )
        xmlrpc_ips=$(echo "$xmlrpc_logs" | awk '{print $1}' | sort | uniq -c | sort -n)
        outputHandler "XMLRPC.php checker"
        outputHandler $divider
        outputHandler "Currently, $xmlrpc_count POST requests have been made to WordPress xmlrpc.php files on this server."
        outputHandler ""
        outputHandler "Below are the IP's POSTing to this file:"
        outputHandler ""
        outputHandler "$xmlrpc_ips"
        outputHandler $divider
    fi
}

function supportRequest {
    outputHandler ""
    outputHandler "Security is our top priority and we believe the following information will result in a much more secure environment for your websites and server."
    outputHandler ""

    if [ "$panel_type" != "gs" ]
    then
        outputHandler "+ If proper security measures are not followed the SSH service can result in a root level compromise of your server. Based on your log files, we can confirm that $ssh_password_attempts failed SSH login attempts have occurred thus far."
        outputHandler ""

        if [ "$panel_type" != "gs" ] && [ ! -z "$root_logins" ]
        then
            outputHandler "Below are a list of IP's that have made successful SSH connections:"
            outputHandler ""
            outputHandler "$root_logins"
            outputHandler ""
        fi

        if [ "$ssh_check" == "true" ]
        then
            outputHandler "It appears someone has already changed your SSH port to a port other than port number 22. This step aligns with security best practices."
            outputHandler ""
        else
            outputHandler "+ While the standard port for SSH is port number 22, it can greatly increase your security to change this port number to an alternative port number over '1000'. Currently, your SSH port number is 22. If you would like us to change your SSH port number, we can do so under the Intrusion Prevention service."
            outputHandler ""
        fi
    fi
    if [[ "$distro_os" == "centos" || "$distro_os" == "fedora" ]] && [ "$panel_type" == "plesk" ]
    then
        if [ ! -z "$shell_user_low" ] || [ ! -z "$shell_user_high" ]
        then
            outputHandler "+ The following users have shell access to your server. If you do not recognize the below usernames , you may want to ask a Linux Security Profession to audit your server as this may be a sign of a root level compromise. If any users should no longer have shell access, they should be removed."
            outputHandler ""
        fi
        if [ ! -z "$shell_user_low" ]
        then
            outputHandler "Below are a list of the shell users that were created via Plesk. Generally these users have a low risk of being malicious; however, if you do not recognize these users, as noted above, they should be investigated."
            outputHandler ""
            outputHandler "$shell_user_low"
            outputHandler ""
        fi
        if [ ! -z "$shell_user_high" ]
        then
            outputHandler "[Action Recommended] Below are a list of shell users that were created outside of Plesk. Generally, these users have a higher risk of being malicious; however, if you do not recognize these users, as noted above, they should be investigated."
            outputHandler ""
            outputHandler "$shell_user_high"
            outputHandler ""
        fi
    fi


    if [ ! -z "$perm_dir" ] || [ ! -z "$perm_file" ]
    then
        outputHandler "+ [Action Needed] Another major security concern are files and directories with "
        outputHandler "weak permissions. According to security best practices all directories should "
        outputHandler "have 755 permissions and files should have 644 permissions. Below are a list of "
        outputHandler "items we found that have very loose permissions and/or ownerships."
        outputHandler ""
    fi
    if [ ! -z "$perm_dir" ]	&& [[ $(echo "$perm_dir" | wc -l) -lt 20 ]]
    then
        outputHandler "Below are a list of directories that have 777 permissions."
        outputHandler ""
        outputHandler "$perm_dir"
        outputHandler ""
    elif [ ! -z "$perm_dir" ] && [[ $(echo "$perm_dir" | wc -l) -gt 20 ]]
    then
        outputHandler "We have been able to determine that over 20 directories have 777 permissions. As such, we have written a list of these directories to $perm_dir_path ."
        outputHandler ""
    fi
    if [ ! -z "$perm_file" ]	&& [[ $(echo "$perm_file" | wc -l) -lt 20 ]]
    then
        outputHandler "Below are a list of files that have 777 permissions."
        outputHandler ""
        outputHandler "$perm_file"
        outputHandler ""
    elif [ ! -z "$perm_file" ] && [[ $(echo "$perm_file" | wc -l) -gt 20 ]]
    then
        outputHandler "We have been able to determine that over 20 files have 777 permissions. As such, we have written a list of these files to $perm_file_path ."
        outputHandler ""
    fi
    if [ "$whost" == "mt" ] && [[ ! -z "$perm_dir" || ! -z "$perm_file" ]]
    then
        outputHandler "We can resolve these issues under our Script and Directory permissions service."
        outputHandler ""
    fi
    if [ "$queue_count" -gt 1000 ]
    then
        outputHandler "+ [Action Needed] While auditing a variety of elements on your server, we were able to determine that you have $queue_count email messages waiting to be sent. Given the high amount of mail in your queue, it seems likely that you may have a compromised email user or a mailscript within one of your applications is being exploited. To resolve this matter, you will need to determine how these messages are being generated and put measures in place to prevent this type of activity in the future."
        outputHandler ""
    fi
    if [ "$queue_count" -gt 1000 ] && [ "$whost" == "mt" ]
    then
        outputHandler "We can investigate the source of these emails under the Email Queue Management service."
        outputHandler ""
    fi


    # web application results
    if [ "$skip_app_check" != "true" ]
    then
        outputHandler "+ Outdated versions of web applications, such as WordPress or Joomla often cause websites to be compromised. Generally speaking, anything other than the most current version of an application is vulnerable to some form of attack. We were able to run a scan for outdated versions of the above two web applications. If you are running any other applications, it is suggested that you ensure all installations are up-to-date."
        outputHandler ""
        if [ ! -z "$outdated_wp" ] || [ ! -z "$outdated_joomla1" ] || [ ! -z "$outdated_joomla2" ] || [ ! -z "$outdated_timthumb" ] || [ ! -z "$vuln_jce" ] || [ ! -z "$sc_versions" ] || [ ! -z "$tc_versions" ]
        then
            outputHandler "[Action Needed] We were able to find one or more outdated versions of common web applications on your server. We suggest you update all of the below applications to their current version."
            outputHandler ""
            if [ ! -z "$outdated_wp" ]
            then
                outputHandler "The current version of WordPress is "$wp_version". We highly suggest you update all of the below WordPress versions, as they are out of date:"
                outputHandler ""
                outputHandler "$outdated_wp"
                outputHandler ""
            fi
            if [ ! -z "$outdated_timthumb" ]
            then
                outputHandler "The current version of TimThumb.php is "$current_timthumb". We highly suggest you update all of the below TimThumb.php versions, as they are out of date; however, any version above 2.7 should be safe to run at this time:"
                outputHandler ""
                outputHandler "$outdated_timthumb"
                outputHandler ""
            fi
            if [ ! -z "$all_revslider" ]
            then
                outputHandler "RevSlider has recently had a serious security vulnerability. Any version below 4.1.4 is vulnerable and needs to be updated. Keep in mind, RevSlider can't be updated via the traditional WordPress plugin update system. You will need to update the plugin manually or update the files in your theme that uses the plugin. Below are a list of all versions installed:"
                outputHandler ""
                outputHandler "$all_revslider"
                outputHandler ""
            fi
            if [ ! -z "$all_AIO_seo_pack_check" ]
            then
                outputHandler "All in One SEO Pack has recently had a serious security vulnerability. Any version below 2.1.6 is vulnerable and needs to be updated. Below are a list of all versions installed:"
                outputHandler ""
                outputHandler "$all_AIO_seo_pack_check"
                outputHandler ""
            fi
            if [ ! -z "$sc_versions" ]
            then
                outputHandler "All versions of WP Super Cache below 1.4.4 are exploitable. If any of the versions listed below are below 1.3, they must be updated:"
                outputHandler ""
                outputHandler "$sc_versions"
                outputHandler ""
            fi
            if [ ! -z "$tc_versions" ]
            then
                outputHandler "All versions of W3 Total Cache below 0.9.2.9 are exploitable. If any of the versions listed below are below 0.9.2.9, they must be updated:"
                outputHandler ""
                outputHandler "$tc_versions"
                outputHandler ""
            fi
            if [ ! -z "$outdated_joomla1" ] | [ ! -z "$outdated_joomla2" ]
            then
                outputHandler "The current version of Joomla is "$joomla_version". We highly suggest you update all of the below Joomla versions, as they are out of date:"
                outputHandler ""
                outputHandler "$outdated_joomla1"
                outputHandler "$outdated_joomla2"
                outputHandler ""
            fi
            if [ ! -z "$vuln_jce" ]
            then
                outputHandler "All versions of the Joomla JCE Module below 2.0.11 are vulnerable to a serious security exploit. We highly suggest you update all of the below Joomla JCE modules, as they are out of date:"
                outputHandler ""
                outputHandler "$vuln_jce"
                outputHandler ""
            fi
        else
            outputHandler "We were not able to find any outdated versions of WordPress or Joomla. We also did not find any common, known threats for these applications."
            outputHandler ""
        fi
    fi

    # server-level (fail2ban / mysql)
    if [ "$panel_type" != "gs" ]
    then
        outputHandler "+ Many server-side applications can increase the security of your server. Fail2Ban is an open-source, python based, piece of software which will monitor your server brute force attempts on passwords and even some type of DDoS attacks."
        outputHandler ""
        if [ "$fail2ban_check" == "true" ]
            then
                outputHandler "We have been able to confirm you do have Fail2Ban installed. This is a very important step and we commend you for taking a proactive approach to security."
                outputHandler ""
        else
                outputHandler "[Action Needed] We have been able to confirm that it does not appear you are using Fail2Ban on your server. The addition of Fail2Ban will almost completely eliminate the chances of a brute force attack being successful, assuming your passwords are reasonably strong. We highly suggest that all customers utilize this application. Should you wish for us to configure Fail2Ban to block brute force attacks on the SSH, FTP and Mail services, we can do so for you. Details on the pricing of this service will be near the bottom of this support request."
                outputHandler ""
        fi

        #Recommend services
        if [ "$fail2ban_check" != "true" ] || [ "$queue_count" -gt "1000" ] || [ ! -z "$perm_dir" ] || [ ! -z "$perm_file" ]
        then
            outputHandler "If you would like our professional assistance with resolution to these issues we can provide the following services:"
            outputHandler ""
        else
            outputHandler "While we do not have further services to offer, to resolve the above items, the suggestions made should help secure your website(s) and environment."
            outputHandler ""
        fi
        if [ "$fail2ban_check" != "true" ] || [ "$ssh_check" != "true" ]
        then
            outputHandler "- Intrusion Prevention for Fail2Ban Installation ($cost)"
        fi
        if [ "$whost" == "mt" ] && [ "$queue_count" -gt 1000 ]
        then
            outputHandler "- Email Queue Management ($cost)"
        fi
        if [ "$whost" == "mt" ] && [[ ! -z "$perm_dir" || ! -z "$perm_file" ]]
        then
            outputHandler "- Script and Directory Permissions ($cost)"
        fi
        outputHandler ""
    fi
    outputHandler "If you require any further assistance, please do not hesitate to contact us by replying to"
    outputHandler "this support request, or by calling us. Thank you for using our Security Audit Service. "
    outputHandler ""
}


######################## Start s_audit.sh merge


#See if this is CPanel Or Plesk
if [ -d '/usr/local/psa' ] && [ ! -d '/usr/local/cpanel' ]
    then
    panel_type='plesk'
    #See If This is MT or GD
    if [ -d "/usr/local/mt" ]
    then
        host_type='mt'
    else
        host_type='gd'
    fi

elif [ -d '/usr/local/cpanel' ] && [ ! -d '/usr/local/psa' ]
then
    panel_type='cpanel'
    host_type='gd'
else
    panel_type='none'
fi

##### Assign Constants Based On Panel Type
if [ "$panel_type" == 'plesk' ]
then
    ##### Get Apache Information
    apache_conf_dir='/etc/httpd/conf'
    apache_conf="$apache_conf_dir/httpd.conf"
    apache_log_dir='/var/log/httpd/'
    apache_error_log="${apache_log_dir}error_log"
    apache_mods_disabled=$(grep '#LoadModule speling_module modules/mod_speling.so' $apache_conf)
    #### Get SQL Information
    sqlConnect="mysql -A -t -u admin -p`cat /etc/psa/.psa.shadow` psa -e"
    db_pass=$(cat /etc/psa/.psa.shadow)
    ### Get Plesk Info
    plesk_ver=$(cat /usr/local/psa/version | awk -F '.' '{ print $1$2 }')
    raw_plesk_ver=$(cat /usr/local/psa/version | awk '{ print $1 }')
    if [ $plesk_ver -lt 110 ]
    then
        plesk_outdated='true'
    else
        plesk_outdated='false'
    fi
    ### Get Domain Information From PSA DB
    doms=$(mysql -N -B -u admin -p`cat /etc/psa/.psa.shadow` psa -e 'select name from domains;')
    subdoms=$(mysql -N -B -u admin -p`cat /etc/psa/.psa.shadow` psa -e 'select name from subdomains;')
    all_doms="${doms}${subdoms}"

elif [ "$panel_type" == 'cpanel' ]
then
    ##### Get Apache Information
    apache_conf_dir='/usr/local/apache/conf'
    apache_conf="$apache_conf_dir/httpd.conf"
    apache_log_dir='/usr/local/apache/logs/'
    apache_error_log="${apache_log_dir}error_log"
    ### Get SQL Information
    sqlConnect="mysql -A"
    ### Get Domain Information
    doms=$(grep 'ServerName' /usr/local/apache/conf/httpd.conf | grep -v 'secureserver.net')
    dom_doc_roots=$(grep 'DocumentRoot' /usr/local/apache/conf/httpd.conf | grep -v '/usr/local/apache/htdocs')
    ### Set Home Directory for MySQL Tuner
    export HOME=/root

elif [ "$panel_type" == 'none' ]
then
    ### See If Apache exists
    if [ -d '/etc/httpd' ]
    then
        apache_status=$(service httpd status)
        if [[ $(echo $apache_status | grep 'is running\|active') ]]
        then
            analyze_apache='true'
            ### Find Apache!!!
            apache_root=$($(which httpd) -V | grep 'HTTPD_ROOT' | awk -F\" '{ print $2 }')
            apache_conf=${apache_root}/$($(which httpd) -V | grep 'SERVER_CONFIG_FILE' | awk -F\" '{ print $2 }')
            apache_error_log=${apache_root}/$($(which httpd) -V | grep 'DEFAULT_ERRORLOG' | awk -F\" '{ print $2 }')
        else
            echo "Apache is not running..... bypassing apache configuration check"
            analyze_apache='false'
        fi
    else
        echo "Apache does not exist on the system.... bypassing apache configuration check"
        analyze_apache='false'
    fi
    ### Find MySQL!!!
fi

### Random Stuff that we will need
epoch=$(date +%s)
sr_file_name="ct_apa_sr.txt"
reportFileName="ct_performance_results-$epoch"
reportFile="/root/CloudTech/logs/$reportFileName"
apiUser="cloudtech@mediatemple.net"
apiKey="52cd8a6a19f1890b5590dcce2946c96e"
cwd=$(pwd)
testMonth=$(date | awk '{ print $2 }')
testYear=$(date | awk '{ print $6 }')
this_month=$(date +'%b')
last_month=$(date +'%b' -d 'last month')
scriptName="ctanalysis.sh"
mysqlBin=$(which mysql)
mysqlSyntax=$($mysqlbin --help --verbose 2>&1 >/dev/null | grep -i 'error')
numfile_limit=$(cat /proc/user_beancounters | grep 'numfile' | awk '{ print $4 }')

### Vars For Apache Tuning Suggestions
#Get RAM base measurements
if [ -f '/proc/user_beancounters' ]
then
    if [[ $(free -m | awk 'NR==4 { print $2 }') == 0 ]] || [[ "$host_type" == 'gd' ]]
    then
        version='40'
        ramCount=`awk 'match($0,/vmguar/) {print $4}' /proc/user_beancounters`
    else
        version='45'
        ramCount=`awk 'match($0,/oomguar/) {print $4}' /proc/user_beancounters`
    fi
    ramBase=-16 && for ((;ramCount>1;ramBase++)); do ramCount=$((ramCount/2)); done
else
    ramBase=$(( $(free -g | awk 'NR==2 { print $2 }') + 1 ))
fi
num_processors=$(cat /proc/cpuinfo | grep processor | wc -l)
opt_maxClients=$(( 50 + (($ramBase**2)*10) + (($ramBase-2)*10) ))
min_maxClients=$(($opt_maxClients - (($opt_maxClients/10)) ))
max_maxClients=$(($opt_maxClients + (($opt_maxClients/10)) ))
opt_maxRequests=$(( 2048 + ($ramBase*256) ))
error_doms=''
services_to_offer=''

### Check Execution Method
if [ -n $2 ]
then
    method="$2"
fi

## See if we have tuned them before and assign constants
apache_ct_backups=$(find $apache_conf_dir -name "httpd.conf.*.ct")

if [ "$panel_type" == 'plesk' ]
then
    nginx_ct_backups=$(find /etc/nginx -name "nginx.conf.*.ct")
    nginx_worker_procs=$(cat /etc/nginx/nginx.conf | grep 'worker_processes' | awk '{ print $2 }' | sed 's/;//')
    if [ -e /usr/local/psa/admin/bin/nginxmng ] && [[ $(/usr/local/psa/admin/bin/nginxmng --status) == "Enabled" ]]
    then
        nginx_enabled="true"
    else
        nginx_enabled="false"
    fi
fi

mysql_ct_backups=$(find /etc -name "my.cnf.*.ct")

if [ -n "$apache_ct_backups" ]
then
    apache_been_tuned='true'
    num_apache_backups=$(echo "$apache_ct_backups" | wc -l)
    apache_backup_dates=$(echo "$apache_ct_backups" | awk -F. '{ print $3 }')
fi
if [ "$panel_type" == 'plesk' ] && [ -n "$nginx_ct_backups" ]
then
    nginx_been_tuned='true'
    num_nginx_backups=$(echo "$nginx_ct_backups" | wc -l)
    nginx_backup_dates=$(echo "$nginx_ct_backups" | awk -F. '{ print $3 }')
fi
if [ -n "$mysql_ct_backups" ]
then
    mysql_been_tuned='true'
    num_mysql_backups=$(echo "$mysql_ct_backups" | wc -l)
    mysql_backup_dates=$(echo "$mysql_ct_backups" | awk -F. '{ print $3 }')
fi

#Find Default And Optimal MaxClients setting for Apache
if [ "$panel_type" == 'plesk' ] && [ "$host_type" == 'mt' ]
then
    default_maxrequests=4000
    case "$numfile_limit" in
        20000)
            default_maxclients=50
        ;;
        40000)
            default_maxclients=100
        ;;
        80000)
            default_maxclients=200
        ;;
        160000)
            default_maxclients=300
        ;;
        320000)
            default_maxclients=400
        ;;
        640000)
            default_maxclients=500
        ;;
        1280000)
            default_maxclients=600
        ;;
        *)
            echo "Could not determine default Apache settings. Please manually determine whether Apache Tuning is required, regardless of what is printed in support request."
            echo ""
        ;;
    esac
elif [ "$host_type" == 'gd' ] && [ "$panel_type" == 'plesk' ]
then
    default_maxrequests=4000
    total_mem=$(free -m | grep 'Mem:' | awk '{ print $2 }')
    case "$total_mem" in
        1024)
           default_maxclients=50
        ;;
        2048)
           default_maxclients=100
        ;;
        3072)
           default_maxclients=150
        ;;
        4096)
           default_maxclients=200
        ;;
        8192)
           default_maxclients=300
        ;;
        *)
           echo "Could not determine default Apache settings. Please manually determine whether Apache Tuning is required, regardless of what is printed in support request."
           echo ""
        ;;
   esac
elif [ "$panel_type" == 'cpanel' ]
then
    default_maxclients=150
    default_maxrequests=10000
else
    echo 'Could not locate control panel or hosting provider. Analysis for default Apache settings will be skipped...'
fi


######################    FUNCTIONS    ##################################################

#runs Security Audit functions
clear
init
os_check
platform_check
running_user
mta

## Server Level Checks##
ssh_security
port_check
ssh_port_check
fail2ban_checker
mail_count
hiddendir
perm_check
user_check

## Application Level Checks##
cms_check
timthumb_check
jce_check
scANDtc_check
revslider_check
AIO_seo_pack_check

## Prints out the actual support request at the end
support_request()
{
    num_recs=1
    if [ -z $method ]
    then
        # Do not output these lines if in headless mode
        if [[ $_headless != true ]]
        then
            outputHandler "Copy And Paste the following as a template for your support request. Please verify all of the information generated by the script, and also do some manual investigation. Make sure to update and customize this template as necessary"
            outputHandler ""
            outputHandler "##### BEGIN SUPPORT REQUEST #####"
            outputHandler ""
        fi
        outputHandler "Thank you for your patience, and we have now completed your Advanced Performance Analysis."
        outputHandler ""
    fi
    outputHandler ""
#########################
#Pagespeed removed from here.
#########################

    outputHandler "Throughout the course of analyzing your site and server, we were able to identify the following potential bottlenecks in your configurations."
    outputHandler ""

    #Check For Excessive Disk Usage
    if [ $current_disk_usage -gt 85 ]
    then
        outputHandler "$num_recs."
        outputHandler "+ Lack Of Available Disk Space"
        outputHandler "Severity: High"
        outputHandler ""
        outputHandler "Issue: It would appear that you are using over 85% of the available disk space on your server. Exceeding your disk space limits can cause serious issues, including full server shutdown."
        outputHandler ""
        outputHandler "Solution: The server should be scanned to determine what files and directories are utilizing excessive disk space. Once this has been determined, all unnecessary data should be removed to free up space."
        #echo -ne " For additional information regarding managing your disk usage, please review the following KnowledgeBase article:"
        outputHandler ""
        #echo "https://kb.mediatemple.net/questions/916/Managing+your+disk+usage#dv_40"
        #echo ""
        services_to_offer="$services_to_offer
        - Disk Management ($cost)"
        num_recs=$(($num_recs+1))
    fi

    #check for excessive inode usage
    if [[ $(get_inode_usage) -ge 85 ]]
    then
        outputHandler "$num_recs."
        outputHandler '+ Lack of available Inodes'
        outputHandler 'Severity: High'
        outputHandler ""
        outputHandler "Issue: It appears that you are using over 85% of your available Inodes on your server. Exceeding your inodes can cause severe problems for your server."
        outputHandler ""
        outputHandler "Solution: The server should be scanned to determine the directories with the most files. Once the offending directories are identified unneeded files should be removed."
        services_to_offer="$services_to_offer
        - Disk Management ($cost)"
        num_recs=$(($num_recs+1))
    fi

    #check for web directories with 1024+ directories
    high_inode_dirs
    if [ -n "$high_inode_dirs_list" ]
    then
        outputHandler "$num_recs."
        outputHandler '+ Website directories with over 1,024 inodes(files and directories)'
        outputHandler 'Severity: High'
        outputHandler ""
        outputHandler "Issue: We have found website directories with over 1,024 inodes. Excessively large directories can adversely impact the performance of the server and cause file system latency, which reduces the responsiveness of the website."
        outputHandler ""
        outputHandler "Solution: The server should be scanned to determine the website directories with more than 1,024 inodes. Once the large directories are indentified, we recommend that you reduce and maintain your per-directory inode count to within 1,024."
        if $nginx_enabled && [ "$nginx_worker_procs" == '1' ] && [ "$panel_type" == 'plesk' ]
        then
            services_to_offer="$services_to_offer
            - Apache/Nginx Tuning ($cost)"
        else
            services_to_offer="$services_to_offer
            - Apache Tuning ($cost)"
        fi
        num_recs=$(($num_recs+1))
    fi

    #check for excessive resource utilization
    if [[ $(calc_15) -ge 25 ]]
    then
        outputHandler "$num_recs."
        outputHandler '+ Heavy CPU Load'
        outputHandler 'Severity: High\n'
        outputHandler "Issue: The server is currently experiencing high CPU load. Linux measures CPU load at the 1, 5 and 15 minute mark to give you a picture of how your CPU load is over time. To help visualize the load across all of your CPU cores we've calculated these load averages to represent the total amount of processing power in use. Your calculated load is as follows:

        One Minute Mark: $(calc_1)%
        Five Minute Mark: $(calc_5)%
        Fifteen Minute Mark: $(calc_15)%

        The top 10 CPU intensive processes, their users and process ID's are supplied for you below:

        $(ps -eo %cpu,user,pid,comm --sort -%cpu | head -10)

        Heavy CPU usage will degrade the overall performance of your server and may result in services failing, crashing or slow response times.

        Solution: You will need to review your CPU usage to determine the responsible applications and streamline where possible. CloudTech may be able to help you get a better understanding of what may be causing high CPU utilization with our Investigative Analysis service."
        outputHandler ""
        services_to_offer="$services_to_offer
        - Investigative Analysis ($cost)"
        num_recs=$(($num_recs+1))
    fi

    if [[ $(check_mem_status) -le 10 ]]
    then
        outputHandler "$num_recs."
        outputHandler '+ High Memory usage'
        outputHandler -e 'Severity: Warning\n'
        outputHandler "Warning: You have less than 10% of your physical memory free. Lack of free memory, however, is not in of itself a serious problem. It is important to understand how linux uses memory to determine if this is a serious problem for your server. Linux, by design, will use as much memory as possible to ensure high performance. Often it will store assets in memory cache for fast access. These assets can and will be reaped by the operating system if additional memory is needed. Therefore, you should review the stats below. Should you have very little or no free memeory with a high amount of memory in cache, your system is working efficiently and this warning is no cause for alarm. However, should you have little free memory and little to no memory cache this likely indicates an issue which warrants attention:

        Total Memory: $(get_mem_total)MB
        Total Used: $(get_mem_used)MB
        Total Free: $(get_mem_free)MB
        Total Cached: $(get_mem_cached)MB

        The top 10 memory intensive processes, their users and process ID's  are supplied for you below:

        $(ps -eo %mem,user,pid,comm --sort -%mem | head -10)

        If you would like assitance in investigating the memory usage on your server CloudTech can assist with an Investigative Analysis service."
        outputHandler ""
        services_to_offer="$services_to_offer
        - Investigative Analysis ($cost)"
        num_recs=$(($num_recs+1))
    fi

    #Check For Outdated Plesk
    if $plesk_outdated && [ "$panel_type" == 'plesk' ] && [ "$host_type" != 'gd' ]
    then
        outputHandler "$num_recs."
        outputHandler "+ Outdated Plesk Version And Lack Of Nginx Reverse Proxy Support"
        outputHandler "Severity: Very High"
        outputHandler ""
        outputHandler "Issue: You are currently running version $raw_plesk_ver of the Plesk control panel, while the most recent stable version is 11.5. Updating the control panel would not only put you on the most up to date version of the software, but would also allow you to enable Nginx Reverse Proxy support. Nginx is a web server, much like Apache, which is known for it's speed and efficiency at serving static assets. Nginx Reverse Proxy support will allow you to take advantage of this benefit, while still utilizing Apache to handle the processing of dynamic content. As a result, it will generally provide significant performance gains, especially for sites that are rich in static assets like images, css, and javascript files."
        outputHandler ""
        outputHandler "Solution: Plesk should be upgraded to the most recent stable version, and Nginx reverse proxy support should be enabled as described in the following KnowledgeBase article."
        outputHandler ""
        outputHandler "https://support.plesk.com/hc/en-us/articles/213944825-How-to-enable-Nginx-reverse-proxy-in-Plesk"
        outputHandler ""
        services_to_offer="$services_to_offer
        - Plesk Upgrade And Activation Of Nginx Reverse Proxy Support (FREE)"
        num_recs=$(($num_recs+1))
    fi

    #Check For Up to Date Plesk, but no Nginx
    if ! $plesk_outdated && ! $nginx_enabled && [ "$panel_type" == 'plesk' ] && [ "$host_type" != 'gd' ]
    then
        outputHandler "$num_recs."
        outputHandler "+ Lack Of Nginx Reverse Proxy Support"
        outputHandler "Severity: High"
        outputHandler ""
        outputHandler "Issue: Although you are running a current version of the Plesk control panel, you have not enabled Nginx Reverse Proxy support. Nginx is a web server, much like Apache, which is known for it's speed and efficiency at serving static assets. Nginx Reverse Proxy support will allow you to take advantage of this benefit, while still utilizing Apache to handle the processing of dynamic content. As a result, it will generally provide significant performance gains, especially for sites that are rich in static assets like images, css, and javascript files."
        outputHandler ""
        outputHandler "Solution: Nginx Reverse Proxy support can be enabled as described in the following KnowledgeBase article."
        outputHandler ""
        outputHandler "https://support.plesk.com/hc/en-us/articles/213944825-How-to-enable-Nginx-reverse-proxy-in-Plesk"
        outputHandler ""
        num_recs=$(($num_recs+1))
    fi

    #Check For Lack Of WordPress Caching
    if [ -n "$non_cached_sites" ]
    then
        outputHandler "$num_recs."
        outputHandler "+ Lack Of A WordPress Caching Mechanism"
        outputHandler "Severity: High"
        outputHandler ""
        outputHandler "Issue: The following WordPress applications do not appear to be utilizing any form of page caching:"
        outputHandler "$non_cached_sites"
        outputHandler ""
        outputHandler "By default, WordPress requires a significant amount of CPU and RAM to serve each request, because the content needs to be dynamically generated. Utilizing a properly configured caching plugin will not only reduce load times and increase transaction rates on the website, but will also conserve valuable system resources by serving a static copy of the requested page instead of dynamically generating it. It can also reduce redundant database queries, which can bog down MySQL when a lot of users are connecting to your site. In extreme circumstances, these queries could cause adverse effects for all database-driven applications on your server."
        outputHandler ""
        outputHandler "Solution: Install and configure one of the trusted WordPress caching plugins:"
        outputHandler ""
        outputHandler "http://wordpress.org/extend/plugins/w3-total-cache/"
        outputHandler "http://wordpress.org/extend/plugins/wp-super-cache/"
        outputHandler ""
        services_to_offer="$services_to_offer
        - WordPress Plugin Installation ($cost per WordPress installation)"
        num_recs=$(($num_recs+1))
    fi

    #Check For Recommendations from MySQL
    if [ $num_mysql_recs -gt 2 ]
    then
        if [ $num_mysql_recs -le 4 ]
        then
            severity='Moderate'
        else
            severity='High'
        fi
        outputHandler "$num_recs."
        outputHandler "+ MySQL Server Configuration"
        outputHandler "Severity: $severity"
        outputHandler ""
        outputHandler "Issue: The current settings for MySQL server variables appear to be inappropriate for the needs of your applications. Properly optimizing MySQL server variables will not only improve the performance of database driven applications, but can also reduce the amount of CPU required by MySQL, which helps to maintain a lower load average on the server."
        outputHandler ""
        outputHandler "Solution: MySQL server variables should be appropriately adjusted in your '/etc/my.cnf' file. The goal is to increase/decrease MySQL buffers as required by your applications, without causing a general memory overage on the server. Although tuning MySQL can be difficult, the following articles will guide you through the process of MySQL optimization."
        outputHandler ""
        outputHandler "http://www.mysql.com/why-mysql/performance/index.html"
        outputHandler ""
        outputHandler "We would personally recommend modification of the following variables:"
        outputHandler ""
        outputHandler "$mysql_recs" | awk '{ print $1 }'
        outputHandler ""
        logPath=$(get_slow_query_log)
        if [ ! -z "$logPath" ]
        then
            top5=$(cat "$logPath" | grep -i "query_time" | sort -rnk 3,3 | head -5)
            top_time=$(cat "$logPath" | grep -i "query_time" | sort -rnk 3,3 | head -1 | awk '{print $3}')
            top_rows=$(cat "$logPath" | grep -i "query_time" | sort -rnk 3,3 | head -1 | awk '{print $9}')
            if [ ! -z "$top5" ]
            then
                outputHandler "Your MySQL slow query log is enabled and has slow queries logged. MySQL considers a query slow if it exceeds 2 seconds. The following are the 5 slowest query times logged: "
                outputHandler ""
                outputHandler "$top5"
                outputHandler ""
                outputHandler "The slowest query ran for $top_time seconds and examined $top_rows rows. Slow queries like this will cause a bottleneck on your system which will degreade performance and can cause severe CPU load. It is vital that you review the log, $logPath, with a developer and optimize these queries. Unfortunately, this is not something $co_name or CloudTech can assist with."
                outputHandler ""
            else
                true
            fi
        else
            true
        fi

        if [ ! -z "$mysql_been_tuned" ] && [ "$mysql_been_tuned" == "true" ]
            then
            outputHandler ""
            outputHandler "PLEASE NOTE: It would appear that MySQL has already been tuned by us on the following date(s):"
            outputHandler ""
            outputHandler "$mysql_backup_dates"
            outputHandler ""
            outputHandler "The fact that MySQL tuning is still recommended would indicate that the server has been upgraded/downgraded, or that the current buffers are no longer appropriate for the needs of your applications."
            outputHandler ""
        fi
        services_to_offer="$services_to_offer
        - MySQL Optimization ($cost)"
        num_recs=$(($num_recs+1))
    fi


    ## APACHE SETTINGS
    ## For now, this is on Plesk VPS only due to complexities with CPanel Apache Configuration
    ## Remove the surrounding if statement when updating for CPanel
    #Check for Default Apache Configuration


    if [ "$current_max_clients" == "$default_maxclients" ] && [ "$current_maxrequests" == "$default_maxrequests" ]
    then
        outputHandler "$num_recs."
        if $nginx_enabled && [ "$panel_type" == 'plesk' ]
        then
            outputHandler "+ Apache/Nginx Configurations"
        else
            outputHandler "+ Apache Configuration"
        fi
        if [ $recentMaxClients > 0 ]
        then
            outputHandler "Severity: High"
        else
            outputHandler "Severity: Moderate - High"
        fi
        outputHandler ""
        if $nginx_enabled && [ "$nginx_worker_procs" == '1' ] && [ "$panel_type" == 'plesk' ]
        then
            outputHandler "Issue: Apache and Nginx appear to be utilizing their default settings. While this is not necessarily problematic, properly tuning the web servers will generally provide a significant performance gain."
        else
            outputHandler "Issue: Apache appears to be utilizing it's default configuration. While this is not necessarily problematic, properly tuning the web server will generally provided a significant performance gain."
        fi
        outputHandler ""
        outputHandler "Solution: Apache prefork settings should be adjusted according to the needs of your applications in conjunction with the amount of RAM available on your server."
        if [ -z "$apache_mods_disabled" ]
        then
            outputHandler " Furthermore, disabling any unnecessary Apache modules will allow each Apache process to run with a lighter memory footprint, conserving valuable system resources."
        fi
        outputHandler " For additional information regarding tuning Apache, please review the following KnowledgeBase article:"
        outputHandler ""
        outputHandler "http://httpd.apache.org/docs/2.2/misc/perf-tuning.html"
        #echo "https://kb.mediatemple.net/questions/246"
        outputHandler ""
        if $nginx_enabled && [ "$nginx_worker_procs" == '1' ] && [ "$panel_type" == 'plesk' ]
        then
            outputHandler "The number of Nginx worker processes should be adjusted according to the number of CPU processors available on your server (16). CPU affinity and file limits should also be adjusted appropriately. Although there is no definitive guide on tuning Nginx, their official documentation contains lots of valuable information that will assist in this process."
            outputHandler ""
            outputHandler "http://wiki.nginx.org/HttpCoreModule#Directives"
        fi
        if $nginx_enabled && [ "$nginx_worker_procs" == '1' ] && [ "$panel_type" == 'plesk' ]
        then
            services_to_offer="$services_to_offer
            - Apache/Nginx Tuning ($cost)"
        else
            services_to_offer="$services_to_offer
            - Apache Tuning ($cost)"
        fi
        num_recs=$(($num_recs+1))
        outputHandler ""
    fi

    #See if their MaxClients are lower than default OR non-optimal

    if [[ "$panel_type" == 'plesk' || ("$panel_type" == 'none' && $analyze_apache == 'true') ]]
    then
        if  [[ ($current_max_clients -lt $min_maxClients  || $current_max_clients -gt $max_maxClients) && $current_max_clients -ne $default_maxclients ]]
        then
            outputHandler "$num_recs."
            if $nginx_enabled && [ "$panel_type" == 'plesk' ]
            then
                outputHandler "+ Apache/Nginx Configurations"
            else
                outputHandler "+ Apache Configuration"
            fi
            outputHandler "Severity: Moderate - High"
            outputHandler ""
            if $nginx_enabled && [ "$nginx_worker_procs" == '1' ] && [ "$panel_type" == 'plesk' ]
            then
                outputHandler "Issue: Your current Apache and Nginx configurations appear to be inappropriate for the needs of your applications. Properly tuning the web servers will generally provide a significant performance gain."
            else
                outputHandler "Issue: Your current apache configuration appears to be inappropriate for the needs of your web applications. Properly tuning the web server will generally provided a significant performance gain."
            fi
            outputHandler ""
            outputHandler "Solution: Apache prefork settings should be adjusted according to the needs of your applications in conjunction with the amount of RAM available on your server."
            if [ -z "$apache_mods_disabled" ]
            then
                outputHandler " Furthermore, disabling any unnecessary Apache modules will allow each Apache process to run with a lighter memory footprint, conserving valuable system resources."
            fi
            outputHandler " For additional information regarding tuning Apache, please review the following KnowledgeBase article:"
            outputHandler ""
            outputHandler "http://httpd.apache.org/docs/2.2/misc/perf-tuning.html"
            #echo "https://kb.mediatemple.net/questions/246"
            outputHandler ""
            if $nginx_enabled && [ "$nginx_worker_procs" == '1' ] && [ "$panel_type" == 'plesk' ]
            then
                outputHandler "The number of Nginx worker processes should be adjusted according to the number of CPU processors available on your server (16). CPU affinity and file limits should also be adjusted appropriately. Although there is no definitive guide on tuning Nginx, their official documentation contains lots of valuable information that will assist in this process."
                outputHandler ""
                outputHandler "http://wiki.nginx.org/HttpCoreModule#Directives"
            fi
            if $nginx_enabled && [ "$nginx_worker_procs" == '1' ] && [ "$panel_type" == 'plesk' ]
            then
                services_to_offer="$services_to_offer
                - Apache/Nginx Tuning ($cost)"
            else
                services_to_offer="$services_to_offer
                - Apache Tuning ($cost)"
            fi
            if [ ! -z "$apache_been_tuned" ] && [ "$apache_been_tuned" == "true" ]
            then
                outputHandler ""
                outputHandler "PLEASE NOTE: It would appear that we tuned Apache on the following date(s):"
                outputHandler ""
                outputHandler "$apache_backup_dates"
                outputHandler ""
                outputHandler "If your server has been upgraded/downgraded since this tuning service was rendered, Apache will need to be retuned. If the Apache Tuning service was performed in the past 14 days, we would be happy to review the current settings, and retune Apache as a courtesy if necessary."
                outputHandler ""
            fi
            num_recs=$(($num_recs+1))
            outputHandler ""
        fi

    fi

    #Check for fatal errors
    if [ -n "$error_doms" ]
    then
        outputHandler "$num_recs."
        outputHandler "+ Fatal Errors"
        outputHandler ""
        outputHandler "Severity: High"
        outputHandler ""
        if [ "$panel_type" == 'plesk' ]
        then
            outputHandler "Issue: We detected fatal errors in some of your domain's error logs. Fatal errors can not only cause issues with site accessibility, but can also affect other sites on your server by causing bottlenecks in Apache/MySQL. The following domains had fatal errors in their most recent error logs. The number at the beginning of the line indicates the number of times this error occurred:"
        elif [ "$panel_type" == 'cpanel' ]
        then
            outputHandler "Issue: We detected fatal errors in your Apache error log. Fatal errors can not only cause issues with site accessibility, but can also affect other sites on your server by causing bottlenecks in Apache/MySQL. The following errors were detected in your most recent error log. The number at the beginning of the line indicates the number of times this error occurred:"
        fi
        outputHandler ""
        outputHandler "$error_doms"
        outputHandler "------------------------"
        outputHandler ""
        outputHandler "Solution: Unfortunately, we can offer only limited assistance with resolving fatal errors, as they are often related directly to the coding of the site. In this situation, resolution would require the attention of a professional developer, who is familiar with your website's platform. However, fatal errors can also occur as a result of application code in conjunction with server settings. Feel free to respond to this support request, and we can advise you as to the availability of assistance for this particular issue."
        outputHandler ""
    fi

    outputHandler "If you require professional assistance resolving any of the issues outlined in this analysis, we could assist with the following:"
    outputHandler "$services_to_offer"
    outputHandler ""
    ## prints SA results
    outputHandler "We have also performed a Security Audit of your server and provided our findings for you below: "
    supportRequest
}

#See If CloudTech Logs Directory Exists. If not, create it
if [ ! -d "/root/CloudTech/logs" ]; then
    mkdir -p /root/CloudTech/logs
fi

#######  BEGIN MAIN SCRIPT
clear

outputHandler "${RedF}${BoldOn}Welcome To The Otto Performance Analysis Tool! Boo-ya-kasha!${Reset}"
outputHandler ""



###### DELETED domain input that should only have been needed for removed gtmetrix report





outputHandler ""
outputHandler "Test Performed on " >> $reportFile
date >> $reportFile
outputHandler "" >> $reportFile

### Get Version Info
outputHandler "${CyanF}${BoldOn}SOFTWARE VERSIONS:${Reset}" | tee -a $reportFile
outputHandler "" | tee -a $reportFile

if [ "$panel_type" == 'plesk' ]
then
    outputHandler "Plesk: $(cat /usr/local/psa/version)" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
fi
outputHandler "PHP: $(php -v)" | tee -a $reportFile
outputHandler "" | tee -a $reportFile
outputHandler "MySQL: $(mysql -V)" | tee -a $reportFile
outputHandler "" | tee -a $reportFile

### Disk Usage
outputHandler "${CyanF}${BoldOn}DISK USAGE:${Reset}" | tee -a $reportFile
raw_disk_usage=$(df -h)
outputHandler "$raw_disk_usage" | tee -a $reportFile
current_disk_usage=$(echo "$raw_disk_usage" | sed -n 2p | awk '{ print $5 }' | sed 's/%//')
outputHandler ""

# Inode Usage
function get_inode_usage() {
  df -i | head -2 | tail -1 | awk '{print $5}' | sed 's/%//'
}

#Websites On The Server
outputHandler "-------------------------------------------------------------" | tee -a $reportFile
outputHandler "" | tee -a $reportFile
outputHandler -e "${CyanF}${BoldOn}LIST OF DOMAINS:${Reset}" | tee -a $reportFile
outputHandler "" | tee -a $reportFile
outputHandler -e "${RedF}DOMAINS:${Reset}" | tee -a $reportFile
outputHandler "" | tee -a $reportFile
if [ "$panel_type" == 'plesk' ]
then
    if [ "$plesk_ver" -ge 115 ]
    then
        $sqlConnect 'select domains.id,domains.name,domains.htype,hosting.www_root,hosting.php_handler_id,sys_users.login,webspace_id from domains join hosting on hosting.dom_id=domains.id join sys_users on sys_users.id=hosting.sys_user_id' | tee -a $reportFile
    else
        $sqlConnect 'select domains.id,domains.name,domains.htype,hosting.www_root,hosting.php_handler_type,sys_users.login,webspace_id from domains join hosting on hosting.dom_id=domains.id join sys_users on sys_users.id=hosting.sys_user_id' | tee -a $reportFile
    fi
    outputHandler "" | tee -a $reportFile
    outputHandler -e "${RedF}DOMAIN ALIASES:${Reset}" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    if [ "$plesk_ver" -ge 115 ]
    then
        $sqlConnect 'select domain_aliases.name,domains.name,domain_aliases.status,domain_aliases.dns,domain_aliases.mail,domain_aliases.web,domain_aliases.tomcat from domain_aliases join domains on domain_aliases.dom_id=domains.id' | tee -a $reportFile
    else
        $sqlConnect 'select domainaliases.name,domains.name,domainaliases.status,domainaliases.dns,domainaliases.mail,domainaliases.web,domainaliases.tomcat from domainaliases join domains on domainaliases.dom_id=domains.id' | tee -a $reportFile
    fi
elif [ "$panel_type" == 'cpanel' ]
then
    outputHandler "LOCAL DOMAINS:" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "$(cat /etc/localdomains | grep -v 'secureserver.net')" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "REMOTE DOMAINS:" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "$(cat /etc/remotedomains)"
fi
outputHandler "" | tee -a $reportFile
outputHandler "-------------------------------------------------------------" | tee -a $reportFile
outputHandler ""

### MySQL Analysis
if [[ "$panel_type" == 'none' && "$method" != 'auto' && $_headless != true ]]
then
    echo -n "Enter MySQL Admin User: "
    read sql_admin_user
    echo -n "Enter MySQL Admin Password: "
    read -s sql_passwd
fi
outputHandler "${RedF}${BoldOn}Analyzing MySQL...${Reset}" | tee -a $reportFile
outputHandler "" | tee -a $reportFile
#mysqltuner
outputHandler "${CyanF}${BoldOn}MySQLTuner Results:${Reset}" | tee -a $reportFile
outputHandler "-------------------------------------------------------------" | tee -a $reportFile
outputHandler "" | tee -a $reportFile
outputHandler "" | tee -a $reportFile

wget --no-check-certificate --quiet https://s3-us-west-2.amazonaws.com/mngsvcs-mstools-prod/includes/apa-deps/mysqltuner.pl

if [[ "$panel_type" == 'none' && "$method" != 'auto' ]]
then
    if [[ -z $sql_admin_user ]]
    then
        outputHandler "Unable to run mysqltuner in headless due to lack of credentials found"
    else
        mysql_results=$(perl mysqltuner.pl --user "'$sql_admin_user'" --pass "'$sql_passwd'")

    fi
else
    mysql_results=$(perl mysqltuner.pl)
fi
outputHandler "$mysql_results" >> $reportFile

#Get Variables For MySQL Analysis
prunes_per_day=$(echo "$mysql_results" | grep 'Query cache prunes per day' | awk '{ print $7 }')
# Exclude join_buffer_size, query_cache_limit, table_open_cache from results since they are commonly flagged even after tuning
mysql_recs=$(echo "$mysql_results" | sed -n '/Variables to adjust/,$p' | grep -v 'Variables to adjust\|query_cache_limit\|join_buffer_size\|table_open_cache')
num_mysql_recs=$(echo "$mysql_recs" | wc -l)
outputHandler "$mysql_results"
rm -f mysqltuner.pl
outputHandler "" | tee -a $reportFile

#mysqlreport
outputHandler "${CyanF}${BoldOn}MySQL Report Results:${Reset}${BoldOff}" | tee -a $reportFile
outputHandler "-------------------------------------------------------------" | tee -a $reportFile
outputHandler "" | tee -a $reportFile
outputHandler "" | tee -a $reportFile
wget --no-check-certificate --quiet --no-check-certificate https://raw.githubusercontent.com/daniel-nichter/hackmysql.com/master/mysqlreport/mysqlreport
chmod +x mysqlreport

if [ "$panel_type" == 'plesk' ]
then
    outputHandler "$(perl mysqlreport --user admin --password `cat /etc/psa/.psa.shadow` 2>&1)" | tee -a /dev/tty $reportFile
elif [ "$panel_type" == 'cpanel' ]
then
    outputHandler "$(perl mysqlreport 2>&1)" | tee -a /dev/tty $reportFile
elif [[ "$panel_type" == 'none' && "$method" != 'auto' ]]
then
    outputHandler "$(perl mysqlreport --user $sql_admin_user --pass $sql_passwd 2>&1)" | tee -a /dev/tty $reportFile
fi

rm -f mysqlreport
outputHandler "" | tee -a $reportFile
#Check For Slow Queries
slowLogFile=$(cat /etc/my.cnf | grep 'log_slow_queries' | awk 'BEGIN { FS = "=" } ; { print $2 }' )
if [ "$slowLogFile" == "" ]
then
    outputHandler "-------------------------------------------------------------" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "Slow Query Logging Is Not Currently Enabled" | tee -a $reportFile
    outputHandler "-------------------------------------------------------------" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
else
    outputHandler "${CyanF}${BoldOn}Printing The Slowest Queries In The Slow Query Log:${Reset}${BoldOff}" | tee -a $reportFile
    outputHandler "-------------------------------------------------------------" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "$(mysqldumpslow -r -a /var/log/mysqld.slow.log | tail)" | tee -a /dev/tty $reportFile
fi
outputHandler "" | tee -a $reportFile
outputHandler "" | tee -a $reportFile

### BEGIN APACHE ANALYSIS

if [[ "$panel_type" == 'plesk' || "$panel_type" == 'cpanel' || ("$panel_type" == 'none' && "$analyze_apache" == 'true')]]
then
    outputHandler "${RedF}${BoldOn}Analyzing Apache...${Reset}" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "${RedF}${BoldOn}CONFIGURATION${Reset}" | tee -a $reportFile
    outputHandler "-------------------------------------------------------------" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "${CyanF}${BoldOn}PREFORK SETTINGS:${Reset}" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    current_prefork_settings=$(sed -n '/IfModule prefork.c/,/\/IfModule/p' $apache_conf)
    outputHandler "$current_prefork_settings" | tee -a $reportFile
    if [[ "$panel_type" == 'plesk' ]]
  then
    current_max_clients=$(echo "$current_prefork_settings" | grep 'MaxClients' | awk '{ print $2 }' | tr -d '\r')
    current_maxrequests=$(echo "$current_prefork_settings" | grep 'MaxRequestsPerChild' | awk '{ print $2 }' | tr -d '\r')

    elif [[ "$panel_type" == 'cpanel' ]]
  then
    current_max_clients=$(echo "$current_prefork_settings" | grep 'MaxClients')
    current_maxrequests=$(echo "$current_prefork_settings" | grep 'MaxRequestsPerChild')
        if [[ -z "$current_max_clients" ]]
        then
            current_max_clients="$default_maxclients"
        fi
        if [[ -z "$current_maxrequests" ]]
        then
            current_maxrequests="$default_maxrequests"
        fi
    fi
    outputHandler "" | tee -a $reportFile

    #Check For KeepAlive
    outputHandler "${CyanF}${BoldOn}KeepAlive is " | tee -a $reportFile
    outputHandler "$(cat $apache_conf | egrep '(KeepAlive On|KeepAlive Off)' | awk '{ print $2 }')" | tee -a $reportFile
    outputHandler "${Reset}" | tee -a $reportFile

    #See Which Apache Modules Are Active
    outputHandler "${CyanF}${BoldOn}The Following Apache Modules are Enabled:${Reset}" | tee -a $reportFile
    outputHandler "$(httpd -M)"
    outputHandler ""
    outputHandler "" | tee -a $reportFile

    #####Get General Performance Info
    outputHandler "${RedF}${BoldOn}PERFORMANCE${Reset}" | tee -a $reportFile
    outputHandler "-------------------------------------------------------------" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "${CyanF}${BoldOn}Current Number Of Connections On Port 80:${Reset}${BoldOff}" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "$(netstat -nt | egrep ':80' | gawk '{print $5}' | wc -l)" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "${CyanF}${BoldOn}Here Is The Total Number Of Apache/php-cgi Processes With Average Process Size And Total Memory Usage:${Reset}${BoldOff}" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "$(ps awwwux | egrep 'httpd|php-cgi' | grep -v grep | awk '{mem = $6; tot = $6 + tot; total++} END{printf("Total procs: %d\nAvg Size: %d KB\nTotal Mem Used: %f GB\n", total, mem / total, tot / 1024 / 1024)}')" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile

    ### Error Reporting
    outputHandler "${RedF}${BoldOn}ERRORS${Reset}" | tee -a $reportFile
    outputHandler "-------------------------------------------------------------" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    #Check For MaxClients Errors
    recentMaxClients=$(grep MaxClients $apache_error_log | wc -l)
    logDate=$(stat $apache_error_log | grep 'Access' | tail -n1 | awk '{ print $2 }')
    allMaxClients=$(grep MaxClients $apache_error_log* | wc -l)
    outputHandler "There were ${CyanF}$allMaxClients${Reset} MaxClients errors in the general Apache logs, ${CyanF}$recentMaxClients${Reset} of which have occurred since $logDate" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    #Check general Apache logs
    outputHandler "${CyanF}${BoldOn}These Are The Top 10 Errors In The Most Recent General Apache Error Log:${Reset}${BoldOff}" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    outputHandler "$(egrep 'warn|error' $apache_error_log | egrep -v 'BasicConstraints|CommonName|indication|conflict|conjunction' | sed -e "s/\[.*$testYear\]//" | sed -e "s/\[client.*\]//" | sort | uniq -c | sort -nr | head)" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
fi

#Check Error Logs For All Domains
if [ "$panel_type" == 'plesk' ]
then
    outputHandler "${CyanF}${BoldOn}These Are The Top 10 Errors Found In Domain Specific Error Logs:${Reset}${BoldOff}" | tee -a $reportFile
    outputHandler "" | tee -a $reportFile
    for i in $all_doms
    do
        outputHandler "" | tee -a $reportFile
        outputHandler "${CyanF}$i${Reset}" | tee -a $reportFile
        outputHandler "-------------------------------------------------------------" | tee -a $reportFile
        outputHandler "" | tee -a $reportFile
        outputHandler "" | tee -a $reportFile
        if [ "$plesk_ver" -ge '115' ]
        then
            logFile="/var/www/vhosts/system/$i/logs/error_log"
        else
            logFile="/var/www/vhosts/$i/statistics/logs/error_log"
        fi
        logSize=$(ls -la $logFile | awk '{print $5}')
        sizeLimit=999999900
        if [ $sizeLimit -lt $logSize ]
        then
            outputHandler "The error log $logFile is over 100MB, and will need to be manually analyzed. You can do it by running the following command:" | tee -a $reportFile
            outputHandler "" | tee -a $reportFile
            outputHandler "egrep 'warn|error' $logFile | egrep -v 'BasicConstraints|CommonName|indication|conflict|conjunction' | egrep '($this_month|$last_month)' | sed -e \"s/\[.*$testYear\]//\" | sed -e \"s/\[client.*\]//\" | sort | uniq -c | sort -nr | head" | tee -a $reportFile
            outputHandler "" | tee -a $reportFile
        else
            num_fatal=0
            errors=$(egrep 'warn|error' $logFile | egrep -v 'BasicConstraints|CommonName|indication|conflict|conjunction' | egrep "($this_month|$last_month)" | sed -e "s/\[.*$testYear\]//" | sed -e "s/\[client.*\]//" | sort | uniq -c | sort -nr | head)
            outputHandler "$errors" | tee -a $reportFile
            fatal_errors=$(egrep 'warn|error' $logFile | egrep -v 'BasicConstraints|CommonName|indication|conflict|conjunction' | egrep "($this_month|$last_month)" | grep -i 'fatal' | sed -e "s/\[.*$testYear\]//" | sed -e "s/\[client.*\]//" | sort | uniq -c | sort -nr | head)
            if [ -n "$fatal_errors" ] && [ $num_fatal > 0 ]
            then
                num_fatal=$(echo "$fatal_errors" | wc -l)
                error_doms="$error_doms
                $i
                -------------------------
                $fatal_errors
                "
            fi
            outputHandler "" | tee -a $reportFile
        fi
    done

elif [ "$panel_type" == 'cpanel' ]
then
    logFile="/usr/local/apache/logs/error_log"
    logSize=$(ls -la $logFile | awk '{print $5}')
    sizeLimit=104857600
    if [ $sizeLimit -lt $logSize ]
    then
        outputHandler "The error log $logFile is over 100MB, and will need to be manually analyzed. You can do it by running the following command:" | tee -a $reportFile
        outputHandler "" | tee -a $reportFile
        outputHandler "egrep 'warn|error' $logFile | egrep -v 'BasicConstraints|CommonName|indication|conflict|conjunction' | egrep '($this_month|$last_month)' | sed -e \"s/\[.*$testYear\]//\" | sed -e \"s/\[client.*\]//\" | sort | uniq -c | sort -nr | head" | tee -a $reportFile
        outputHandler "" | tee -a $reportFile
    else
        num_fatal=0
        outputHandler "Command is egrep 'warn|error' $logFile | egrep -v 'BasicConstraints|CommonName|indication|conflict|conjunction' | egrep \"($this_month|$last_month)\" | grep -i 'fatal' | sed -e \"s/\[.*$testYear\]//\" | sed -e \"s/\[client.*\]//\" | sort | uniq -c | sort -nr | head"
        fatal_errors=$(egrep 'warn|error' $logFile | egrep -v 'BasicConstraints|CommonName|indication|conflict|conjunction' | egrep "($this_month|$last_month)" | grep -i 'fatal' | sed -e "s/\[.*$testYear\]//" | sed -e "s/\[client.*\]//" | sort | uniq -c | sort -nr | head)
        outputHandler "fatal errors is $fatal_errors"
        if [ -n "$fatal_errors" ] && [ $num_fatal > 0 ]
        then
            num_fatal=$(echo "$fatal_errors" | wc -l)
            outputHandler "num fatal is $num_fatal"
            error_doms="$error_doms

            -------------------------

            $fatal_errors
            "
        fi
        outputHandler "" | tee -a $reportFile
    fi
fi

### GTMetrix report and summary
## REMOVED


## Check for WordPress Caching. Using cms_performance_checker.sh for this
outputHandler ""
outputHandler "${RedF}${BoldOn}Check for WordPress Caching${Reset}"
outputHandler ""

wget --no-check-certificate --quiet https://s3-us-west-2.amazonaws.com/mngsvcs-mstools-prod/includes/apa-deps/cms_performance_checker.sh

caching_results=$(sh cms_performance_checker.sh | tee -a $reportFile)
outputHandler "$caching_results"
non_cached_sites=$(echo "$caching_results" | sed -n '/The following sites do not appear to be using caching/,$p' | grep -v 'The following sites do not appear to be using caching')
rm -f cms_performance_checker.sh
outputHandler ""

## Complete The Analysis
outputHandler "${RedF}${BoldOn}Analysis Concluded!!!${Reset}"
outputHandler ""
outputHandler "The results of this analysis were logged to:"
outputHandler ""
outputHandler "${CyanF}${BoldOn}$reportFile ${Reset}${BoldOff}"
outputHandler ""

if [ -n $2 ] && [ "$2" == "auto" ]
then
   support_request >> $sr_file_name
else
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
fi
rm -f ctanalysis.sh
exit

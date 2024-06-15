#!/bin/bash

## MySQL Pre Optimization Script
#This script uses various online, open source tools and resources to get a good look
#At MySQL and how it's performing, as well as what can be done to improve it.

### Math functions needed by calcs
function decPercent() {
  value=$1
  percent=$2
  awk "BEGIN {
      printf \"%.0f\", $value - (($value / 100) * $percent)
  }"
}

function incPercent() {
  value=$1
  percent=$2
  awk "BEGIN {
      printf \"%.0f\", (($value / 100) * $percent) + $value
  }"
}

function awkmath0() {
  awk "BEGIN { printf \"%.0f\", $@ }"
}

function awkmath2() {
  awk "BEGIN { printf \"%.2f\", $@ }"
}

## Function to output human readable sizes (from stackexchange)
function bytesToHuman() {
    b=${1:-0}; d=''; s=0; S=(Bytes {K,M,G,T,P,E,Y,Z}iB)
    while ((b > 1024)); do
        d="$(printf ".%02d" $((b % 1024 * 100 / 1024)))"
        b=$((b / 1024))
        (( s++ ))
    done
    echo "$b$d ${S[$s]}"
}

#Define Constants
function define_constants {
	mysqlBin=$(which mysql) #Gives the location of mysql
	epoch=$(date +%s) #Gives the date for use in generating files
	mysqlSyntax=$($mysqlBin --help --verbose &>/dev/null | grep -i 'error') #Command to check for errors in mysql syntax
	reportFile="/root/logs/mysql_tuning-${epoch}" #Location of reporting file for the whole script
	disk_avail=$(df -B 1024 | head -2 | tail -1 | awk '{print $4}') # Available disk space in KB
	panel_type='' #Cpanel, Plesk, or none
	my_cnf="/etc/my.cnf"
}

### Gathering system details
function system_details {
	totalMem=$(free -b|grep -E "^Mem"|awk '{print $2}')
	freeMem=$(( $(grep -E "^MemFree:" /proc/meminfo | grep -E -o "[0-9]*") * 1024 ))
	cachedMem=$(( $(grep -E "^Cached:" /proc/meminfo | grep -E -o "[0-9]*") * 1024 ))
	cachedMem75=$( decPercent $cachedMem 25 ) # 75% of the total cached memory (so we do not consume all of it)
	freePlusCached=$(( $freeMem + $cachedMem75 )) # free memory plus 75% of the cached memory
	innodb_tables_existing=$( sql_connect " -Bse \"select COUNT(ENGINE) FROM information_schema.TABLES WHERE TABLE_SCHEMA NOT IN ('information_schema', 'performance_schema', 'mysql') AND ENGINE='InnoDB' GROUP BY ENGINE ORDER BY ENGINE ASC;\" " )
	innodb_total_size=$( sql_connect " -Bse \"SELECT SUM(DATA_LENGTH+INDEX_LENGTH) FROM information_schema.TABLES WHERE TABLE_SCHEMA NOT IN ('information_schema', 'performance_schema', 'mysql') AND ENGINE='InnoDB' GROUP BY ENGINE ORDER BY ENGINE ASC;\" " )
	table_count=$( sql_connect " -Bse \"SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA NOT IN ('information_schema', 'performance_schema', 'mysql') AND ENGINE IS NOT NULL ;\" " )
	frag_tables=$( sql_connect " -Bse \"SELECT CONCAT(CONCAT(TABLE_SCHEMA, '.'), TABLE_NAME) FROM information_schema.TABLES WHERE TABLE_SCHEMA NOT IN ('information_schema','performance_schema', 'mysql') AND Data_free > 0 AND NOT ENGINE='MEMORY'\" " )
	frag_tables_count=$(echo "$frag_tables" | wc -w)
  if [[ -f /proc/user_beancounters ]]; then
    ramCount=$(awk 'match($0,/vmguar/) {print $4}' /proc/user_beancounters)
    ramBase=-16 && for ((;ramCount>1;ramBase++)); do ramCount=$((ramCount/2)); done
  elif [[ -f $(which dmidecode) ]]; then
    ramBase=$(( $(dmidecode --type 17 | awk 'match($0,/Size:/) {print $2}') / 1024 ))
  else
    outputHandler "${RedF}${BoldOn}Neither '/proc/user_beancounters' nor 'dmidecode' exists on this server.${Reset}"
    catch_err "Unable to determine Base RAM value. Exiting."
  fi

}
### End system details



# Check input variables
while [[ $# -gt 0 ]]
do
  key="$1"

  case $key in

  -z|--headless)
  _headless=true
  ;;

  -p|--pretune)
  pretune=true
  ;;

  -r|--recheck)
  recheck=true
  ;;

  -h|--help|*)
  echo "-h or --help for help"
  echo "-z or --headless for headless mode"
  echo "-p or --pretune to run the pretune automation (headless only currently)"
  echo "-r or --recheck to run all subsequent tuning automation (headless only currently)"
  exit 2
  ;;

  esac
shift
done

if [[ $pretune == true && $recheck == true ]]
then
  echo "Only pretune OR recheck can be used at a time."
  exit 2
fi
if [[ $pretune == true || $recheck == true ]]
then
  if [[ $_headless == false ]]
  then
    echo "pretune and recheck can only be used in headless mode currently."
    exit 2
  fi
fi

# Define Text Colors
if [[ $_headless == true ]]; then
  Escape=""
  BlackF=""
  RedB=""
  RedF=""
  CyanF=""
  Reset=""
  BoldOn=""
  BoldOff=""
else
  Escape="\033"
  BlackF="${Escape}[30m"
  RedB="${Escape}[41m"
  RedF="${Escape}[31m"
  CyanF="${Escape}[36m"
  Reset="${Escape}[0m"
  BoldOn="${Escape}[1m"
  BoldOff="${Escape}[22m"
fi
divider="###################################################################################"

function sql_connect() {
sql_query=$@
mysqlBin=$(which mysql)

  if [ "$panel_type" == 'plesk' ]
    then
      sql_login="-A -u admin -p\`cat /etc/psa/.psa.shadow\` "
    elif [ "$panel_type" == 'cpanel' ]
    then
      sqlConnect=" "
    else
      if [[ $_headless == true ]]
      then
        outputHandler "Headless mode cannot continue if control panel cannot be determined."
        exit 98
      fi
  fi
bash -c "$mysqlBin $sql_login $sql_query" | tee -a debug.txt

}


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
    echo -e "$1"
  fi
}

declare -A myvar

function build_vars_array {
###### Building mysql variables into array
myvars=()
while IFS=$'\n' read line
do
  myvars+=("$line")
done < <( sql_connect " -Bse 'SHOW /*!50000 GLOBAL */ VARIABLES' " )

for i in "${myvars[@]}"
do
  myvar[$(echo $i|awk '{print $1}')]=$(echo $i|awk '{print $2}')
done
###### End mysql variables array
}

declare -A mystat

function build_stats_array {
###### Building mysql status output into array
mystats=()
while IFS=$'\n' read line
do
  mystats+=("$line")
done < <( sql_connect " -Bse 'SHOW /*!50000 GLOBAL */ STATUS' " )

for i in "${mystats[@]}"
do
  mystat[$(echo $i|awk '{print $1}')]=$(echo "$i"|awk '{print $2}')

done
###### End mysql status array
}


## Function to get performance schema memory if in use
function get_pf_memory() {
        if [[ -z ${myvar[performance_schema]} ]]
        then
                echo 0
        elif [[ ${myvar[performance_schema]} == "OFF"  ]]
        then
                echo 0
        else
                pfmem=$( sql_connect " -Bse 'SHOW ENGINE PERFORMANCE_SCHEMA STATUS' | grep 'performance_schema.memory' | awk '{print \$3}' " )
                [[ $pfmem -gt 0 ]] && echo $pfmem || echo 0
        fi
}
##

######
function calc_innodb_buffer_pool_changes() {
  if [[ $innodb_tables_existing -gt 0 ]]
  then
          new_innodb_buffer_pool_size=$( incPercent $innodb_total_size 10 )
          echo "innodb_buffer_pool_size = $new_innodb_buffer_pool_size "

          if [[ $new_innodb_buffer_pool_size -gt 1073741824 ]]
          then
                  new_innodb_buffer_pool_instances=$( bytesToHuman $new_innodb_buffer_pool_size | cut -f1 -d. )
                  echo "innodb_buffer_pool_instances = $new_innodb_buffer_pool_instances"
          fi
  fi
}

function calc_values {
  ## Check connection percentages
  pct_connections_used=$( awkmath0 "(${mystat[Max_used_connections]} / ${myvar[max_connections]}) * 100" )
  pct_connections_aborted=$( awkmath0 "(${mystat[Aborted_connects]} / ${mystat[Connections]}) * 100" )

  ## Check open files and limits
  open_file_pct=$( awkmath0 "(${mystat[Open_files]} / ${myvar[open_files_limit]}) * 100" )

  ## Set calculated vars based on myvar[s]
  per_thread_buffers=$( awkmath0 "${myvar[read_buffer_size]} + ${myvar[read_rnd_buffer_size]} + ${myvar[sort_buffer_size]} + ${myvar[thread_stack]} + ${myvar[join_buffer_size]}" )
  total_per_thread_buffers=$( awkmath0 "$per_thread_buffers * ${myvar[max_connections]}" )
  max_total_per_thread_buffers=$( awkmath0 "$per_thread_buffers * ${mystat[Max_used_connections]}" )

  ## Find largest value of tmp_table_size or max_heap_table_size and save for later
  max_tmp_table_size=$( [[ ${myvar[tmp_table_size]} -gt ${myvar[max_heap_table_size]} ]] && echo ${myvar[max_heap_table_size]} || echo ${myvar[tmp_table_size]} )

  ## Add all of the different types of buffers
  server_buffers=$( awkmath0 "${myvar[key_buffer_size]} + $max_tmp_table_size + ${myvar[innodb_buffer_pool_size]} + ${myvar[innodb_additional_mem_pool_size]} + ${myvar[innodb_log_buffer_size]} + ${myvar[query_cache_size]} + ${myvar[query_cache_size]}" )
  max_used_memory=$( awkmath0 "$server_buffers + $max_total_per_thread_buffers + $(get_pf_memory)" )
  pct_max_used_memory=$( awkmath0 "($max_used_memory / $totalMem) * 100" )
  max_peak_memory=$( awkmath0 "$server_buffers + $total_per_thread_buffers + $(get_pf_memory)" )
  pct_max_peak_memory=$( awkmath0 "($max_peak_memory / $totalMem) * 100" )
  pct_query_cache_used=$( 
    if [[ "${myvar[query_cache_size]}" -eq 0 ]]
    then
      echo 0
    else
      awkmath0 "(${mystat[Qcache_free_memory]} / ${myvar[query_cache_size]}) * 100" 
    fi
    )
  ## Mysql versioning checks
  myMajor=$(echo "${myvar[version]}" | cut -f1 -d.)
  myMinor=$(echo "${myvar[version]}" | cut -f2 -d.)
  myUpDays=$( awkmath2 "${mystat[Uptime]} / 86400" )

  table_cache_hit_rate=$( awkmath0 "${mystat[Open_tables]} * 100 / ${mystat[Opened_tables]}" )
  table_cache_increase=$(incPercent "${myvar[table_open_cache]}" 10)
}

function pct_tmp_disk() {
  if [[ ${mystat[Created_tmp_tables]} -gt 0 && ${mystat[Created_tmp_disk_tables]} -gt 0 ]]
  then
    tmp_disk=$( awkmath0 " ( ${mystat[Created_tmp_disk_tables]} / ${mystat[Created_tmp_tables]} ) * 100" )
    echo $tmp_disk
  else
    echo 0
  fi
}

#This function is designed to ensure the log file is in place and the my.cnf file is backed up
#before any other action is taken.
function initial_setup {

  #Make sure we have the logs dir
  if [ ! -d "/root/logs" ]
  then
    mkdir -p /root/logs 2>/dev/null
    if [[ $? -ne 0 ]]; then
      catch_err "Unable to create logdir /root/logs. Exiting."
    fi
  fi
  touch $reportFile
  exec >  >(tee -a "$reportFile")
  exec 2> >(tee -a "$reportFile")

  #Display existing my.cnf
  outputHandler "${CyanF}${BoldOn}Existing my.cnf file contents${Reset}"
  outputHandler ""
  outputHandler "$(cat ${my_cnf})"
  outputHandler "### End my.cnf file contents ###"
  outputHandler ""

  #Backup config file, ouput process to report file
  outputHandler "${CyanF}${BoldOn}Backing Up MySQL Config File${Reset}"
  outputHandler ""
  outputHandler "$(cp -vp ${my_cnf}{,-$epoch.bk})"
  restoreFile="${my_cnf}-$epoch.bk"
  outputHandler ""
}

function rollback() {
  _rollback=true
  exitCode=$1
  serviceName=$2
  mv ${my_cnf}{,_errors_detected}
  cp -p "$restoreFile" ${my_cnf}
  systemctl restart "$serviceName" &> /dev/null
  if [[ $? -ne 0 ]]
  then
    outputHandler "Rollback complete and MySQL restarted successfully."
    outputHandler "Exiting - Please review manually."
    exit 33
  else
    outputHandler "${BoldOn}${RedF}Rollback FAILED because MySQL was unable to restart."
    outputHandler "Exiting - Please review manually.${Reset}"
    exit 66
  fi
}

# In headless, exits script. Otherwise, offers option to continue or quit.
function catch_err {
  if [[ $_headless == true ]]; then
    outputHandler "Error: $1"
    exit 1
  else
    echo ""
    echo "Error: $1"
    echo "Do you want to continue?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) break;;
            No ) exit 1;;
        esac
    done
    echo ""
  fi
}

### Make sure that the script is being run by root. Exit if not
function check_user {
  if [ "$(id -u)" != "0" ]
  then
    outputHandler "This script must be run as root" 1>&2
    outputHandler "This script will now exit!"
    exit 1
  fi
}

#See if this is CPanel Or Plesk, and change the panel_type string accordingly.
#This function also automatically sets up the database connections based on the panel type,
#or prompts for manual setup if it can't detect either CPanel or Plesk.
function check_panel {
  if [ -d '/usr/local/psa' ] && [ ! -d '/usr/local/cpanel' ]
  then
    panel_type='plesk'
  elif [ -d '/usr/local/cpanel' ] && [ ! -d '/usr/local/psa' ]
    then
    panel_type='cpanel'
  else
    if [[ $_headless == true ]]
    then
      outputHandler "Headless mode cannot continue if control panel cannot be determined."
      exit 99
    fi
    panel_type='none'
  fi

  #Set up database conections based on detected panel
  if [ "$panel_type" == 'plesk' ]
  then
    sqlConnect="$mysqlBin -A -u admin -p$(cat /etc/psa/.psa.shadow)"
    db_pass=$(cat /etc/psa/.psa.shadow)
    sql_dump_string="mysqldump -uadmin -p${db_pass} --add-drop-table --hex-blob"
    sql_check_string="mysqlcheck -uadmin -p${db_pass}"
  elif [ "$panel_type" == 'cpanel' ]
  then
    db_pass=$(grep password /root/.my.cnf | awk -F\" '{print $2}')
    sqlConnect="$mysqlBin"
    sql_dump_string="mysqldump --add-drop-table --hex-blob"
    sql_check_string="mysqlcheck"
    export HOME=/root
  else
    if [[ $_headless == true ]]
    then
      outputHandler "Headless mode cannot continue if control panel cannot be determined."
      exit 98
    fi
    panel_type='none'
    outputHandler "Could not find control panel. You must enter the admin credentials for MySQL:"
    outputHandler ""
    outputHandler "Enter MySQL admin user: "
    read -r sql_user
    outputHandler "Enter MySQL admin pass: "
    read sql_pass
    sqlConnect="$mysqlBin -A -u${sql_user} -p${sql_pass}"
    sql_dump_string="mysqldump -u${sql_user} -p${sql_pass} --add-drop-table --hex-blob"
    sql_check_string="mysqlcheck -u${sql_user} -p${sql_pass}"
  fi
}


#The below function is my main target for more encapsulation, it's a bit of a mess right now
#Run the typical pre-tune:
#1. Check Mysql Syntax
#2. Check disk space for database backups and backup databases
#3. Optimize databases and check saved space
#4. Enable slow query logging
function pre_tune {

  #Check MySQL Syntax, output any issues to the report file
  if [ -n "$mysqlSyntax" ]
  then
    outputHandler $mysqlSyntax
    outputHandler ""
    #Exit if the errors are significant enough to warrant investigation first
    catch_err "The above are issues from your MySQL syntax"
  fi

  #Get Pre-Optimization Size Of All DB's in KB
  preSize=$( sql_connect ' -Nse "select Round(((Sum(DATA_LENGTH) + SUM(INDEX_LENGTH)) / 1024),0) from information_schema.tables;" ' )
  avail_diff=$((${disk_avail}-${preSize}))
  # Get percentage of available disk space that databases would consume
  # Being as accurate as possible without requiring bc
  backup_percent=$( printf "%.0f" $(perl -le "print (($preSize/$disk_avail) * 100)"))
  # Exit if the backups would leave less than 2 GB
  if [ $backup_percent -gt 75 ]
  then
    outputHandler "The databases are too large ($(($preSize / 1024)) MB) to safely export. Please resolve this issue before proceeding.... Exiting!"
    exit
  fi

  #Backup Databases

  #See If Otto Directory Exists. If so, back up the DB's in there
  mkdir -p /root/db-backups
  outputHandler "${CyanF}${BoldOn}Backing Up All Databases To /root/db-backups${Reset}"
  outputHandler ""
  for i in $( sql_connect " -Nse 'show databases' | grep -E -v '^information_schema$|^performance_schema$' " )
  do
    $(echo $sql_dump_string) "$i" 2>/dev/null | gzip > /root/db-backups/"$i"-"$epoch".sql.gz
    if [[ $? -ne 0 ]]
    then
      catch_err "Could not backup $i"
    fi
    outputHandler "$i"
  done

  #Optimize Databases
  outputHandler ""
  outputHandler "${CyanF}${BoldOn}Repairing And Optimizing Databases${Reset}"
  if [[ $_headless == true ]]
  then
    $sql_check_string --auto-repair --optimize --all-databases &> "$reportFile"
  else
    outputHandler "This may take a while..."
    outputHandler ""
    $sql_check_string --auto-repair --optimize --all-databases | tee -a "$reportFile"
  fi
  outputHandler "${CyanF}${BoldOn}Optimization Complete - Results in $reportFile ${Reset}"

  #Get Post_Optimization Size Of All DB's
  postSize=$( sql_connect " -Nse 'select Round(((Sum(DATA_LENGTH) + SUM(INDEX_LENGTH)) / 1024),0) from information_schema.tables;' " )
  sizeDiff=$((preSize - postSize))


  if [[ $_headless != true ]]
  then
    #Enable slow query logging if there's not already a slow query log file
    slowLogFile=$(grep -E 'log_slow_queries|slow_query_log_file' ${my_cnf} | awk 'BEGIN { FS = "=" } ; { print $2 }' )
    if [ "$slowLogFile" == "" ]
    then
      outputHandler ""
      outputHandler "${CyanF}${BoldOn}Creating slow query log file.${Reset}"
      outputHandler "${RedF}${BoldOn}Slow query logging is not automatically enabled.${Reset}"
      touch /var/log/mysqld.slow.log
      chown mysql:mysql /var/log/mysqld.slow.log
    #If slow query logging was already enabled, we want to mention that
    else
      outputHandler ""
      outputHandler "MySQL slow query logging is already enabled."
      outputHandler ""
    fi
  fi

}

function make_it_better {
  outputHandler "\033[31mCopy the below recommendations:\e[0m"
  outputHandler ""
  outputHandler "[mysqld]"
  outputHandler "# Memory and cache settings"
  outputHandler "query_cache_type = 1"
  outputHandler "query_cache_size = $((2**($ramBase+2)))M"
  outputHandler "thread_cache_size = $((2**($ramBase+2)))"
  outputHandler "table_open_cache = $(incPercent $table_count 10)"
  outputHandler "tmp_table_size = $((2**($ramBase+3)))M"
  outputHandler "max_heap_table_size = $((2**($ramBase+3)))M"
  outputHandler "join_buffer_size = ${ramBase}M"
  outputHandler "key_buffer_size = $((2**($ramBase+4)))M"
  outputHandler "max_connections = $((100 + (($ramBase-1) * 50)))"
  outputHandler "wait_timeout = 300"
  outputHandler "interactive_timeout = 300"
  outputHandler ""
  outputHandler "# Innodb settings"
  outputHandler "innodb_buffer_pool_size = $((2**($ramBase+3)))M"
  outputHandler "innodb_additional_mem_pool_size = ${ramBase}M"
  outputHandler "innodb_log_buffer_size = ${ramBase}M"
  outputHandler "innodb_thread_concurrency = $((2**$ramBase))"
  outputHandler ""
  outputHandler "\033[31mPress enter when you're done\e[0m"
  read -r
}

## Headless version of make_it_better
function auto_it_better {
  new_mysql_options=("")
  new_mysql_options+=("###### Begin MySQL Pre-Tuning modifications here. This section can be deleted if problems are encountered with these changes. Timestamp: $epoch")
  new_mysql_options+=("[mysqld]")
  new_mysql_options+=("# Memory and cache settings")
  new_mysql_options+=("query_cache_type = 1")
  new_mysql_options+=("query_cache_size = $((2**($ramBase+2)))M")
  new_mysql_options+=("thread_cache_size = $((2**($ramBase+2)))")
  new_mysql_options+=("table_open_cache = $(incPercent $table_count 10)")
  new_mysql_options+=("tmp_table_size = $((2**($ramBase+3)))M")
  new_mysql_options+=("max_heap_table_size = $((2**($ramBase+3)))M")
  new_mysql_options+=("join_buffer_size = ${ramBase}M")
  new_mysql_options+=("key_buffer_size = $((2**($ramBase+4)))M")
  new_mysql_options+=("max_connections = $((100 + (($ramBase-1) * 50)))")
  new_mysql_options+=("wait_timeout = 300")
  new_mysql_options+=("interactive_timeout = 300")
  new_mysql_options+=("")
  new_mysql_options+=("# innodb settings")
  new_mysql_options+=("innodb_buffer_pool_size = $((2**($ramBase+3)))M")
  new_mysql_options+=("innodb_additional_mem_pool_size = ${ramBase}M")
  new_mysql_options+=("innodb_log_buffer_size = ${ramBase}M")
  new_mysql_options+=("innodb_thread_concurrency = $((2**$ramBase))")
  new_mysql_options+=("###### END MySQL Pre-Tuning modifications here. This section can be deleted if problems are encountered with these changes. Timestamp: $epoch")

  outputHandler ""
  outputHandler "Adding the following to ${my_cnf}:"
  for option in "${new_mysql_options[@]}"
  do
    echo "$option" >> ${my_cnf}
    outputHandler "$option"
  done
  outputHandler ""
}


function autotuner {
  autoTunerOptions=()
  autoTunerOptions+=("$(calc_innodb_buffer_pool_changes)")

  ## If table_cache_hit_rate is less than 20 (%) and table_open_cache+10% is lower than open_files_limit, increase table_open_cache to 110% of current
  [[ $table_cache_hit_rate -lt 20 && $table_cache_increase -lt ${myvar[open_files_limit]} ]] && autoTunerOptions+=("$(echo "table_open_cache = $table_cache_increase ")")

  ## If percent of temp tables created on disk are greater than 25 (%) and tmp_table_size is less than 129 (MB) then double tmp_table_size (increase by 100%)
  if [[ $(pct_tmp_disk) -gt 25 && ${myvar[tmp_table_size]} -lt $(( 129 * 1024 * 1024 )) ]]
  then
    autoTunerOptions+=("$(echo "tmp_table_size = $( incPercent ${myvar[tmp_table_size]} 100 ) ")")
    autoTunerOptions+=("$(echo "max_heap_table_size = $( incPercent ${myvar[tmp_table_size]} 100 ) ")")
  fi

  ## If mysql version is greater than 5.6 then enable Performance Schema
  if [[ ${myvar[performance_schema]} == "OFF" ]]
  then
    if [[ $myMajor -eq "5" && $myMinor -ge "6" ]] || [[ $myMajor -gt "5" ]]
    then
      autoTunerOptions+=("$(echo "performance_schema = ON")")
    fi
  fi

  ## If percent of connections is greater than 90, increase max connections by 15 (%) and decrease both wait_timeout and interactive_timeout by 15 (%) (assuming these have been set to 300 by first run)
  if [[ $pct_connections_used -gt "80" ]]
  then
    autoTunerOptions+=("$(echo "max_connections = $(incPercent ${myvar[max_connections]} 15) ")")
    autoTunerOptions+=("$(echo "wait_timeout = $(decPercent ${myvar[wait_timeout]} 15) ")")
    autoTunerOptions+=("$(echo "interactive_timeout = $(decPercent ${myvar[wait_timeout]} 15) ")")
  fi

  echo "###### MySQL Expert Service Tuning changes here. This section can be deleted if problems are encountered with these changes. Timestamp: $epoch" >> ${my_cnf}
  echo "[mysqld]" >> ${my_cnf}
  for option in "${autoTunerOptions[@]}"
  do
    echo "$option" >> ${my_cnf}
  done
  echo "###### END MySQL Expert Service Tuning changes. Timestamp: $epoch" >> ${my_cnf}

}

#Installs MySQLTuner
#based on panel, runs MySQLTuner and outputs the results to the /root/ directory
#removes the script, cats the results to the screen
function mysql_tuner {
  outputHandler "Running MySQL Tuner..."
  #Using an older version of mysqltuner because the new version requires something we don't want to install
  if [ "$panel_type" == 'plesk' ] || [ "$panel_type" == 'cpanel' ]
  then
    mkdir -p /root/
    wget --no-check-certificate -O /root/mysqltuner.pl https://raw.githubusercontent.com/major/MySQLTuner-perl/d220a9ac7972af19d0eda3d80721f9673e11243f/mysqltuner.pl && perl /root/mysqltuner.pl > /root/mysql_tuner_"$epoch"
    rm -rf /root/mysqltuner.pl
    cat /root/mysql_tuner_"$epoch"
    outputHandler

    if [[ $_headless == true ]]
    then
      outputHandler ""
    else
      outputHandler "Take note of the MySQL Tuner results above and press enter."
      read -r
    fi

  #We don't want to attempt he automated version if we're not sure what panel they're using.
  else
    outputHandler "Unknown hosting panel, run this manually."
  fi
}

#Installs MySQLReport and a dependency if the panel is cpanel
#based on panel, runs MySQLReport and outputs the results to the /root/ directory
#removes the script, cats the results to the screen
function mysql_report {
  outputHandler "Running MySQL Report..."
  if [ "$panel_type" == 'plesk' ]
  then
    wget --no-check-certificate -O /usr/local/src/mysqlreport https://raw.githubusercontent.com/daniel-nichter/hackmysql.com/master/mysqlreport/mysqlreport && perl /usr/local/src/mysqlreport --user admin --password "$(cat /etc/psa/.psa.shadow)" > /root/mysql_report_"$epoch"
    rm -rf /root/mysqlreport
    cat /root/mysql_report_"$epoch"
    outputHandler
    if [[ $_headless == true ]]
    then
      outputHandler ""
    else
      outputHandler "Take note of the MySQL Report results above and press enter."
      read -r
    fi
  elif [ "$panel_type" == 'cpanel' ]
  then
    #We need a cpanel module for this:
    cpan DBD::mysql

    wget --no-check-certificate -O /usr/local/src/mysqlreport https://raw.githubusercontent.com/daniel-nichter/hackmysql.com/master/mysqlreport/mysqlreport && perl /usr/local/src/mysqlreport --user root --password "$(grep password /root/.my.cnf | awk -F\" '{print $2}')" > /root/mysql_report_"$epoch"
    rm -rf /root/mysqlreport
    cat /root/mysql_report_"$epoch"
    outputHandler
    if [[ $_headless == true ]]
    then
      outputHandler ""
    else
    outputHandler "Take note of the MySQL Report results above and press enter."
      read -r
    fi
  else
    outputHandler "Unknown hosting panel, run this manually."
  fi
}

#Runs MySQLPrimer and outputs the results to the /root/ directory
#Removes the script, then cats the results to the screen.
function mysql_primer {
  outputHandler "Running MySQL Primer..."
  wget -O /usr/local/src/tuning-primer.sh https://launchpad.net/mysql-tuning-primer/trunk/1.6-r1/+download/tuning-primer.sh && bash /usr/local/src/tuning-primer.sh > /root/mysql_primer_"$epoch"
  rm -f /usr/local/src/tuning-primer.sh
  outputHandler "$(cat /root/mysql_primer_$epoch)"
  outputHandler ""
}

#Restarts mysql
function restart_mysql {
  mysql -V | grep -i mariadb > /dev/null
  if [[ $? -eq 0 ]]
  then
    serviceName="mariadb"
  elif [ "$panel_type" == 'plesk' ]
  then
    serviceName="mysqld"
  elif [ "$panel_type" == 'cpanel' ]
  then
    serviceName="mysql"
  else
    if [[ $_headless == true ]]
    then
      outputHandler "Unknown hosting panel. Unable to restart MySQL. PLEASE REVIEW SERVICE."
      exit 96
    else
      outputHandler "${BoldOn}${RedF}Unknown hosting panel. Restart service manually.${Reset}"
    fi
  fi
  outputHandler ""
  outputHandler "${BoldOn}${CyanF}Attempting to restart MySQL.${Reset}"
  systemctl restart "$serviceName" &> /dev/null
  myRestart=$?

  if [[ $? -ne 0 ]]
  then
  	outputHandler "${BoldOn}${RedF}Error restarting MySQL. Rolling back configs now.${Reset}"
    rollback $myRestart service "$serviceName"
  fi

  if [[ $_headless == true ]]
  then
    outputHandler "MySQL restarted successfully."
  else
    echo "Restart successful, press Enter to continue."
    read -r
  fi

}

#Generate info based on a few things that have been done
function information {
  outputHandler ""
  outputHandler "BELOW IS JUST ALL OF THE FOUND CHANGES, CLEAN IT UP BEFORE YOU SEND IT OUT:"
  outputHandler ""
  outputHandler "$(diff ${my_cnf}-$epoch.bk ${my_cnf} | grep '>')"
  outputHandler ""

  #Finds the slow log file and tells them about it if it exists.  Outputs a warning if it doesn't find it.
  slowLog=$(grep -E 'log_slow_queries|slow_query_log_file' ${my_cnf})
  if [ "$slowLog" == "" ]
  then
    outputHandler "SLOW QUERY LOGGING ISN'T ENABLED, IT PROBABLY SHOULD BE"
  else
    outputHandler "Finally, we've enabled the slow query log, which is located as follows:"
    outputHandler ""
    outputHandler "/var/log/mysqld.slow.log"
    outputHandler ""
    outputHandler "You can utilize the following SSH command to view the contents of this file in an organized fashion:"
    outputHandler ""
    outputHandler "mysqldumpslow -r -a /var/log/mysqld.slow.log"
    outputHandler ""
  fi
  outputHandler "${divider}"
  if [[ $_headless == true ]]
  then
    outputHandler "Done."
    outputHandler "${divider}"
  else
    outputHandler "Press Enter to continue"
    outputHandler "${divider}"
    read -r
  fi

}

function output {
  # If in headless mode, convert output to JSON format in Base64
  if [[ $_headless == true ]]
  then
    # If there is an error or we're rolling back successfully, print notes, and exit status
    if  [[ $_rollback == true ]] || [[ $exitCode -ne 0 ]]
    then
      echo "{ \"note\" : \"$(
      for i in "${output_glob[@]}"
      do
        echo -e "$i"
      done | base64 -w 0
      )\", \"status\" : \"$exitCode\" }"
    else
      if [[ $pretune != true ]]
      then
        # If script runs successfully, print notes, resolution, and exit status
        echo "{ \"note\" : \"$(
        for i in "${output_glob[@]}"
        do
          echo -e "$i"
        done | base64 -w 0
        )\", \"resolution\" : \"$(output_glob=()
        information
        for i in "${output_glob[@]}"
        do
          echo -e "$i"
        done | base64 -w 0
        )\", \"status\" : \"$exitCode\" }"
      # Only output notes section and exit status on pretune
      else
        echo "{ \"note\" : \"$(
        for i in "${output_glob[@]}"
        do
          echo -e "$i"
        done | base64 -w 0
        )\", \"status\" : \"$exitCode\" }"
      fi 
    fi
  else
    information
  fi
  exit 3
}


#Bash Menu to select options
function main_menu {
  #Perform initial setup including root user verification and panel identification
  clear
  check_user
	define_constants
  check_panel
	system_details
  initial_setup

  #Display selection menu
  while [ "$action" != "Q" ] && [ "$action" != "q" ]
  do
    echo
    echo
    echo -e "\033[31m""${divider}""\e[0m"
    echo
    echo -e "\033[31mMySQL Optimization Tools\e[0m"
    echo
    echo -e "\033[34m1) Pre-Tune (Run first if you haven't yet)"
    echo "2) Show Making It Better Suggestions"
    echo "3) MySQL Tuner"
    echo "4) MySQL Report"
    echo "5) Mysql Primer"
    echo "6) Edit ${my_cnf} with vim"
    echo "7) Restart mysql"
    echo "8) Generate info and exit after you've made all changes"
    echo -e "Q) Exit\e[0m"
    echo
    echo -e "\033[31m""${divider}""\e[0m"
    echo
    read -r -p "Please select an option to continue: " action
    echo
    clear
    case $action in
      1)
        pre_tune
      ;;
      2)
        make_it_better
      ;;
      3)
        mysql_tuner
      ;;
      4)
        mysql_report
      ;;
      5)
        mysql_primer
      ;;
      6)
        vim ${my_cnf}
      ;;
      7)
        restart_mysql
      ;;
      8)
        information
        exit 0
      ;;
      *)
        exit 1
      ;;
    esac
    clear
  done
}

function debug_run() {
###################################################### Use what we gathered and calculated

echo "MySQL Uptime: ${mystat[Uptime]} ($myUpDays days)"
echo "Total memory: $totalMem ($(bytesToHuman $totalMem))"
echo "Max MySQL used memory: $max_used_memory ($(bytesToHuman $max_used_memory))"
echo "Max MySQL used memory: $pct_max_used_memory%"
echo "Max MySQL usable memory: $max_peak_memory ($(bytesToHuman $max_peak_memory))"
echo "Max MySQL usable memory: $pct_max_peak_memory%"
echo "Max allowed connections: ${myvar[max_connections]}"
echo "Max used connections: ${mystat[Max_used_connections]}"
echo "Connection usage: $pct_connections_used%" "$([[ $pct_connections_used -gt 85 ]] && echo "WARNING" || echo "(good)" )"
echo "Aborted Connections: ${mystat[Aborted_connects]}"
echo "Connections: ${mystat[Connections]}"
echo "Percent of connections aborted: $pct_connections_aborted"
echo "Open files limit: ${myvar[open_files_limit]}"
echo "Max open files usage: ${mystat[Open_files]}"
echo "Max open files usage: $open_file_pct%"
echo "InnoDB tables: $innodb_tables_existing"
echo "InnoDB total data size: $innodb_total_size ($(bytesToHuman $innodb_total_size))"
echo "InnoDB buffer pool instances: ${myvar[innodb_buffer_pool_instances]} "
echo "Wait_timeout: ${myvar[wait_timeout]} "
echo "Interactive_timeout: ${myvar[interactive_timeout]} "
echo "Join_buffer_size: ${myvar[join_buffer_size]} "
echo "Table_open_cache: ${myvar[table_open_cache]} "
echo "Table Count (excluding sys tables): $table_count "
echo "Open_tables: ${mystat[Open_tables]} "
echo "Opened_tables: ${mystat[Opened_tables]} "
echo "Table Cache Hit Rate: $table_cache_hit_rate "

echo "Stats & Vars #####################################"
echo
echo "Key_buffer size: ${myvar[key_buffer_size]} ($(bytesToHuman ${myvar[key_buffer_size]}))"
echo "Max_temp_table size: $max_tmp_table_size ($(bytesToHuman $max_tmp_table_size))"
echo "Query_cache usage: $pct_query_cache_used%"
echo "===="
echo "Server Buffers: $server_buffers ($(bytesToHuman $server_buffers))"
echo
echo "Performance Schema (P_S): ${myvar[performance_schema]}"
echo "P_S Memory: $(get_pf_memory) ($(bytesToHuman $(get_pf_memory)))"
echo "MySQL Major Version: $myMajor"
echo "Minor Version: $myMinor"
echo "Fragmented Table count: $frag_tables_count"

}

## Function to automate during headless mode
function automate {
  clear
  check_user
	define_constants

  check_panel
	system_details

  build_vars_array
  build_stats_array
  calc_values
  initial_setup
  if [[ $pretune == true ]]
  then
    pre_tune
    auto_it_better
  fi
  if [[ $recheck == true ]]
  then
    autotuner
  fi
  restart_mysql

#Uncomment below to have addtl output showing you the values collected from MySQL
#debug_run

  exit 0

}

# This function is run when trap detects the script is exiting
function FINISH {
  exitCode=$?
  case $exitCode in
    # Exit code 0 = No errors everything worked. Remove script and print output.
    0)
    output
    ;;

    # Exit code 2 = User ran script with -h or --help.
    # If headless, remove script, otherwise leave it. Do not print output.
    2)
    output
    ;;

    # This exits the script after the output function completes. This handles Ctrl+C exits.
    3)
    exit 3
    ;;

    # All other exit codes = Something went wrong. Auto-rollback, remove script, and print output.
    # Exit code 33 = Mysql failed to start after changes, so we rolled back successfully and mysql started again
    # Exit code 66 = Mysql failed to start after changes, *AND* failed to restart after rollback. IMMEDIATE ATTENTION REQUIRED
    *)
    output
    ;;

    esac
}

# Traps interrupts and exits and runs the FINISH function
trap FINISH INT EXIT

#Run the main menu
if [[ $_headless == true ]]
then
  automate
else
  main_menu
fi

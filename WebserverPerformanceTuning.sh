#!/bin/bash

# Web server performance tuning

#DEFINE VARS
uuid=$(uuidgen)
reportFile="/root/logs/apache_pre_tuning.$(date +%Y-%m-%d.$uuid)"

# Check input variables
while [[ $# -gt 0 ]]
do
  key="$1"

  case $key in

    -z|--headless)
    _headless=true
    ;;

    -r|--rollback)
    if [[ $2 =~ [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12} ]]
    then
      uuid=$2
      _rollback=true
    else
      echo "$1 requires a valid uuid"
      exit 2
    fi
    shift
    ;;

    -h|--help|*)
    echo "-h or --help for help"
    echo "-z or --headless for headless mode"
    echo "-r [uuid] or --rollback [uuid] to roll back config files"
    exit 2
    ;;

  esac
shift
done

## If headless mode, save up all output for the end. If not, echo it normally.
outputHandler() {
  if [[ $_headless == true ]]; then
    tempIFS="$IFS"
    IFS=$'\n'
    output_glob+=("$1")
    IFS="$tempIFS"
  else
    echo -e "$1"
  fi
}

# Disable text colors in headless mode
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
  Escape="\033";
  BlackF="${Escape}[30m"
  RedB="${Escape}[41m"
  RedF="${Escape}[31m"
  CyanF="${Escape}[36m"
  Reset="${Escape}[0m"
  BoldOn="${Escape}[1m"
  BoldOff="${Escape}[22m"
fi

# Make sure that the script is being run by root. Exit if not
function check_user {
  if [ "$(id -u)" != "0" ]; then
   outputHandler "This script must be run as root"
   exit 2
  fi
}

# Creates a directory for logs
function log_dir {
if [ ! -d "/root/logs" ]
  then
  mkdir -p /root/logs 2>/dev/null
  if [[ $? -ne 0 ]]; then
    outputHandler "Unable to create logdir /root/logs. Exiting."
    outputHandler ""
    exit 1
  fi
fi
  touch "$reportFile"
  exec >  >(tee -a "$reportFile")
  exec 2> >(tee -a "$reportFile")
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

# Auto-rollback on error or run with rollback flag -r [uuid] or --rollback [uuid]
rollback() {
  fileLocation=(/etc/ /etc/nginx/ /etc/httpd/conf/ /var/cpanel/conf/apache/ /etc/httpd/conf.d/ /usr/local/apache/conf/includes/)
  rolledBack=()
  outputHandler "${CyanF}${BoldOn}Checking for files to roll back${Reset}"
  for filepath in "${fileLocation[@]}"
  do
    # do not double quote or itll run only once
    for backup in $(find "$filepath" -maxdepth 1 -type f -name "*$1.ct" 2>/dev/null )
    do
      # Case statement for each backup file
      case "$backup" in
        /etc/nginx/nginx.conf*$1.ct)
        mv "/etc/nginx/nginx.conf" "/etc/nginx/nginx.conf.$1.rolledback.ct" 2>/dev/null
        mv "$backup" "/etc/nginx/nginx.conf"
        outputHandler "Rolled back $backup"
        ;;
        /etc/httpd/conf/httpd.conf*$1.ct)
        mv "/etc/httpd/conf/httpd.conf" "/etc/httpd/conf/httpd.conf.$1.rolledback.ct" 2>/dev/null
        mv "$backup" "/etc/httpd/conf/httpd.conf"
        outputHandler "Rolled back $backup"
        ;;
        /var/cpanel/conf/apache/local*$1.ct)
        mv "/var/cpanel/conf/apache/local" "/var/cpanel/conf/apache/local.$1.rolledback.ct" 2>/dev/null
        mv "$backup" "/var/cpanel/conf/apache/local"
        outputHandler "Rolled back $backup"
        ;;
        /etc/httpd/conf.d/python.conf*$1.ct)
        if [[ -f /etc/httpd/conf.d/python.conf ]]
        then
          mv "/etc/httpd/conf.d/python.conf" "/etc/httpd/conf.d/python.conf.$1.rolledback.ct" 2>/dev/null
        fi
        mv "$backup" "/etc/httpd/conf.d/python.conf"
        outputHandler "Rolled back $backup"
        ;;
        /etc/httpd/conf.d/perl.conf*$1.ct)
        if [[ -f /etc/httpd/conf.d/perl.conf ]]
        then
          mv "/etc/httpd/conf.d/perl.conf" "/etc/httpd/conf.d/perl.conf.$1.rolledback.ct" 2>/dev/null
        fi
        mv "$backup" "/etc/httpd/conf.d/perl.conf"
        outputHandler "Rolled back $backup"
        ;;
        /etc/php.ini*$1.ct)
        mv "/etc/php.ini" "/etc/php.ini.$1.rolledback.ct" 2>/dev/null
        mv "$backup" "/etc/php.ini"
        outputHandler "Rolled back $backup"
        ;;
        /etc/httpd/conf.d/fcgid.conf*$1.ct)
        mv "/etc/httpd/conf.d/fcgid.conf" "/etc/httpd/conf.d/fcgid.conf.$1.rolledback.ct" 2>/dev/null
        mv "$backup" "/etc/httpd/conf.d/fcgid.conf"
        outputHandler "Rolled back $backup"
        ;;
        /usr/local/apache/conf/includes/post_virtualhost_global.conf*$1.ct)
        mv "/usr/local/apache/conf/includes/post_virtualhost_global.conf" "/usr/local/apache/conf/includes/post_virtualhost_global.conf.$1.rolledback.ct" 2>/dev/null
        mv "$backup" "/usr/local/apache/conf/includes/post_virtualhost_global.conf"
        outputHandler "Rolled back $backup"
        ;;
      esac
      rolledBack+=("$backup")
    done
  done
  if [[ $rolledBack ]]
  then
    outputHandler ""
    outputHandler "${CyanF}${BoldOn}Restarting Webserver${Reset}"
    if [[ $panel_type == "cpanel" ]]
    then
      outputHandler "$(/scripts/rebuildhttpdconf)"
      apache_restart="$(/usr/local/cpanel/scripts/restartsrv_httpd | tail -n1)"
      echo "$apache_restart" | grep -q "httpd restarted successfully."
      if [[ $? -eq 0 ]]
      then
        outputHandler "Apache restarted successfully"
      else
        outputHandler "Apache failed to restart. Please troubleshoot manually."
        exit 3
      fi
    elif [[ $panel_type == "plesk" && $nginx_bool == true ]]
    then
      /sbin/service nginx restart 2&>1 >/dev/null
      if [[ $? -eq 0 ]]
      then
        outputHandler "Nginx restarted successfully"
      else
        outputHandler "Nginx failed to restart. Please troubleshoot manually."
        exit 3
      fi
    elif [[ $panel_type == "plesk" && $nginx_bool == false ]]
    then
      /sbin/service httpd restart 2&>1 >/dev/null
      if [[ $? -eq 0 ]]
      then
        outputHandler "Apache restarted successfully"
      else
        outputHandler "Apache failed to restart. Please troubleshoot manually."
        exit 3
      fi
    else
      outputHandler "Unknown panel type. No services restarted."
      exit 3
    fi
  else
    outputHandler "No files to roll back."
  fi
  outputHandler ""
}

# See if this is CPanel Or Plesk
function check_panel {
if [ -d '/usr/local/psa' ] && [ ! -d '/usr/local/cpanel' ]
   then
   panel_type='plesk'
   apache_conf='/etc/httpd/conf/httpd.conf'
   is_nginx
elif [ -d '/usr/local/cpanel' ] && [ ! -d '/usr/local/psa' ]
   then
   panel_type='cpanel'
   apache_conf='/var/cpanel/conf/apache/local'
   addtl_directives='/usr/local/apache/conf/includes/post_virtualhost_global.conf'
else
  outputHandler "Currently only Cpanel and Plesk are supported"
  exit 1
fi
}

# See If Nginx is enabled. Only run if this is a plesk server
function is_nginx {
  if [ -e /usr/local/psa/admin/bin/nginxmng ] && [[ $(/usr/local/psa/admin/bin/nginxmng --status) == "Enabled" ]]
  then
    nginx_bool=true
  else
    nginx_bool=false
  fi
}

# Get RAM base measurements
function calc_resources {
if [ -f '/proc/user_beancounters' ]
then
  if [[ $(free -m | awk 'NR==4 { print $2 }') == 0 ]]
  then
    ramCount=$(awk 'match($0,/vmguar/) {print $4}' /proc/user_beancounters)
  else
    ramCount=$(awk 'match($0,/oomguar/) {print $4}' /proc/user_beancounters)
  fi
  ramBase=-16 && for ((;ramCount>1;ramBase++)); do ramCount=$((ramCount/2)); done
else
  ramBase=$(free -g | awk 'NR==2 { print $2 }')
fi
num_processors=$(grep -c processor /proc/cpuinfo)
}

# Initial backup of Nginx config file and status check.
function nginx_initial {
outputHandler "${CyanF}${BoldOn}Backing Up Nginx configuration files${Reset}"
_nginx_backup="/etc/nginx/nginx.conf.$(date +%Y-%m-%d.$uuid.ct)"
nginx_backup=$(cp -vp /etc/nginx/nginx.conf $_nginx_backup)
backup_files+=("$nginx_backup")
outputHandler "Nginx configuration backed up"
outputHandler ""
outputHandler "${CyanF}${BoldOn}Checking Nginx Status${Reset}"
nginx_status="$(/sbin/service nginx status | egrep 'is running|Active: active')"
if [ -z "$nginx_status" ]
then
  catch_err "Nginx is not running!"
else
  outputHandler "$nginx_status"
fi
nginx_config_check=$(nginx -t 2>&1 | grep 'test failed')
if [ -n "$nginx_config_check" ]
then
  outputHandler ""
  catch_err "There are issues with the syntax of the Nginx configuration file!"
fi
outputHandler ""
}

# NGINX TUNING
function nginx_tune {
outputHandler "${CyanF}${BoldOn}Tuning Nginx${Reset}"
sed -i "s/worker_processes.*/worker_processes  $num_processors;/g" /etc/nginx/nginx.conf
if [[ $(grep 'worker_rlimit_nofile' /etc/nginx/nginx.conf) == '' ]]
  then
  sed -i '/events {/i \worker_rlimit_nofile 30000;\n' /etc/nginx/nginx.conf
fi
sed -i 's/#gzip  on;/gzip on;/g' /etc/nginx/nginx.conf
sed -i 's/#gzip_disable/gzip_disable/g' /etc/nginx/nginx.conf

if [[ $(egrep '[^#]gzip_types' /etc/nginx/nginx.conf) == '' ]]
   then
sed -i '/gzip_disable/a \    gzip_types text/plain text/css text/javascript application/javascript application/x-javascript;' /etc/nginx/nginx.conf
fi

if [[ $(egrep '[^#]gzip_vary' /etc/nginx/nginx.conf) == '' ]]
    then
    sed -i '/gzip_disable/a \    gzip_vary on;' /etc/nginx/nginx.conf
fi

outputHandler "New Nginx configuration:"
outputHandler "$(cat /etc/nginx/nginx.conf)"
outputHandler ""
}

# Initial backups and checks for Plesk without Nginx
function plesk_apache_initial {
outputHandler "${CyanF}${BoldOn}Backing up Apache configuration files${Reset}"
_apache_backup=$(cp -vp $apache_conf{,.$(date +%Y-%m-%d.$uuid.ct)})
backup_files+=("${_apache_backup}")
outputHandler "Apache configuration backed up"
if [[ _headless != true ]]
then
  _php_backup=$(cp -vp /etc/php.ini{,.$(date +%Y-%m-%d.$uuid.ct)})
  backup_files+=("${_php_backup}")
  outputHandler "PHP ini backed up"
  if [ -f '/etc/httpd/conf.d/fcgid.conf' ]
  then
    _fcgid_backup=$(cp -vp /etc/httpd/conf.d/fcgid.conf{,.$(date +%Y-%m-%d.$uuid.ct)})
    backup_files+=("${_fcgid_backup}")
    outputHandler "FastCGI configuration backed up"
  fi
fi
outputHandler ""
outputHandler "${CyanF}${BoldOn}Checking Apache status${Reset}"
apacheStatus=$(/sbin/service httpd status 2>&1 | grep 'running')
if [ -z "$apacheStatus" ]
  then
    catch_err "Apache is not running!"
else
    outputHandler "$apacheStatus"
fi
apacheTest=$(httpd -t 2>&1 | grep "Syntax OK")
outputHandler "$apacheTest"
if [ "$apacheTest" != "Syntax OK" ]
then
  catch_err "Apache configuration file has invalid syntax!"
fi
outputHandler ""
}

# Plesk Apache Tuning
function plesk_apache_tune {
outputHandler "${CyanF}${BoldOn}Tuning Apache${Reset}"
outputHandler ""
outputHandler "${CyanF}${BoldOn}Current Prefork Settings:${Reset}"
outputHandler ""
outputHandler "$(sed -n '/<IfModule prefork.c>/,/<\/IfModule>/p' $apache_conf)"
outputHandler ""
# Check For KeepAlive
outputHandler "KeepAlive is $(cat $apache_conf | egrep '(KeepAlive On|KeepAlive Off)' | awk '{ print $2 }')"
# See Which Modules Are Disabled
preDisabledMods=$(cat $apache_conf | grep '#LoadModule' | awk '{ print $2 }')
if [ -n "$preDisabledMods" ]
   then
       outputHandler ""
       outputHandler "${CyanF}${BoldOn}The following Apache modules are disabled:${Reset}"
       outputHandler "$preDisabledMods"
fi
outputHandler ""
outputHandler "${CyanF}${BoldOn}Adjusting current Apache settings${Reset}"
is_prefork=$(cat /etc/httpd/conf/httpd.conf | grep "IfModule prefork.c")
if [ -z "$is_prefork" ]
  then
  cat <<EOT >> $apache_conf
# prefork MPM
# StartServers: number of server processes to start
# MinSpareServers: minimum number of server processes which are kept spare
# MaxSpareServers: maximum number of server processes which are kept spare
# ServerLimit: maximum value for MaxClients for the lifetime of the server
# MaxClients: maximum number of server processes allowed to start
# MaxRequestsPerChild: maximum number of requests a server process serves
<IfModule prefork.c>
StartServers $ramBase
MinSpareServers $ramBase
MaxSpareServers $(($ramBase*2 + 1))
ServerLimit $(( 50 + (($ramBase**2)*10) + (($ramBase-2)*10) ))
MaxClients $(( 50 + (($ramBase**2)*10) + (($ramBase-2)*10) ))
MaxRequestsPerChild  $(( 2048 + ($ramBase*256) ))
</IfModule>
EOT
  else
    sed -i "/^StartServers/c\StartServers $ramBase" $apache_conf
    sed -i "/^MinSpareServers/c\MinSpareServers $ramBase" $apache_conf
    sed -i "/^MaxSpareServers/c\MaxSpareServers $(($ramBase*2 + 1))" $apache_conf
    sed -i "/^ServerLimit/c\ServerLimit $(( 50 + (($ramBase**2)*10) + (($ramBase-2)*10) ))" $apache_conf
    sed -i "/^MaxClients/c\MaxClients $(( 50 + (($ramBase**2)*10) + (($ramBase-2)*10) ))" $apache_conf
    sed -i "/^MaxRequestsPerChild/c\MaxRequestsPerChild  $(( 2048 + ($ramBase*256) ))" $apache_conf
fi
outputHandler ""
outputHandler "${CyanF}${BoldOn}New Prefork Settings:${Reset}"
outputHandler ""
outputHandler "$(sed -n '/<IfModule prefork.c>/,/<\/IfModule>/p' $apache_conf)"
outputHandler ""
# Check For Python and Perl Scripts within doc root of domains. If not present, disable these Apache Mods.
outputHandler "${CyanF}${BoldOn}Checking For Python Scripts${Reset}"
outputHandler ""
pythonFiles=$(find /var/www/vhosts -type f -name "*.py" 2>/dev/null | grep -v 'test')
if [ -z "$pythonFiles" ]
then
  outputHandler "${CyanF}${BoldOn}Disabling Python Modules${Reset}"
  outputHandler ""
  if [[ -e /etc/httpd/conf.d/python.conf ]]
  then
    _python_backup="$(mv -v /etc/httpd/conf.d/python.conf /etc/httpd/conf.d/python.conf."$(date +%Y-%m-%d.$uuid.ct)" 2>/dev/null)"
    backup_files+=("$_python_backup")
    outputHandler "${RedF}${BoldOn}Python module has been disabled${Reset}"
    postDisabledMods="${postDisabledMods}python\n"
  else
    outputHandler "Python Module Was Already Disabled"
  fi
  outputHandler ""
else
  outputHandler ""
  outputHandler "${RedF}${BoldOn}Python scripts were found, Python module will not be disabled.${Reset}"
  outputHandler ""
fi
outputHandler "${CyanF}${BoldOn}Checking for Perl scripts${Reset}"
outputHandler ""
perlFiles=$(find /var/www/vhosts -type f -name "*.pl" 2>/dev/null | grep -v 'test')
if [ -z "$perlFiles" ]
then
  outputHandler "${CyanF}${BoldOn}Disabling Perl module${Reset}"
  outputHandler ""
  if [[ -e /etc/httpd/conf.d/perl.conf ]]
  then
    _perl_backup="$(mv -v /etc/httpd/conf.d/perl.conf /etc/httpd/conf.d/perl.conf."$(date +%Y-%m-%d.$uuid.ct)" 2>/dev/null)"
    backup_files+=("$_perl_backup")
    outputHandler "${RedF}${BoldOn}Perl Module has been disabled${Reset}"
    postDisabledMods="${postDisabledMods}perl\n"
  else
    outputHandler "Perl module was already disabled"
  fi
else
  outputHandler ""
  outputHandler "${RedF}${BoldOn}Perl scripts were found, Perl module will not be disabled${Reset}"
fi
outputHandler ""
# Disable Other Modules
outputHandler "${CyanF}${BoldOn}Disabling additional Apache modules${Reset}"
outputHandler ""
sed -i "/^LoadModule authn_alias_module/c\#LoadModule authn_alias_module modules/mod_authn_alias.so" $apache_conf
sed -i "/^LoadModule authn_anon_module/c\#LoadModule authn_anon_module modules/mod_authn_anon.so" $apache_conf
sed -i "/^LoadModule authn_dbm_module/c\#LoadModule authn_dbm_module modules/mod_authn_dbm.so" $apache_conf
sed -i "/^LoadModule authnz_ldap_module/c\#LoadModule authnz_ldap_module modules/mod_authnz_ldap.so" $apache_conf
sed -i "/^LoadModule authz_dbm_module/c\#LoadModule authz_dbm_module modules/mod_authz_dbm.so" $apache_conf
sed -i "/^LoadModule authz_owner_module/c\#LoadModule authz_owner_module modules/mod_authz_owner.so" $apache_conf
sed -i "/^LoadModule cache_module/c\#LoadModule cache_module modules/mod_cache.so" $apache_conf
sed -i "/^LoadModule disk_cache_module/c\#LoadModule disk_cache_module modules/mod_disk_cache.so" $apache_conf
sed -i "/^LoadModule ext_filter_module/c\#LoadModule ext_filter_module modules/mod_ext_filter.so" $apache_conf
sed -i "/^LoadModule file_cache_module/c\#LoadModule file_cache_module modules/mod_file_cache.so" $apache_conf
sed -i "/^LoadModule info_module/c\#LoadModule info_module modules/mod_info.so" $apache_conf
sed -i "/^LoadModule ldap_module/c\#LoadModule ldap_module modules/mod_ldap.so" $apache_conf
sed -i "/^LoadModule mem_cache_module/c\#LoadModule mem_cache_module modules/mod_mem_cache.so" $apache_conf
sed -i "/^LoadModule status_module/c\#LoadModule status_module modules/mod_status.so" $apache_conf
sed -i "/^LoadModule speling_module/c\#LoadModule speling_module modules/mod_speling.so" $apache_conf
sed -i "/^LoadModule usertrack_module/c\#LoadModule usertrack_module modules/mod_usertrack.so" $apache_conf
sed -i "/^LoadModule version_module/c\#LoadModule version_module modules/mod_version.so" $apache_conf

outputHandler "${CyanF}${BoldOn}Modules Now Disabled:${Reset}"
additionalDisabledMods=$(cat $apache_conf | grep '#LoadModule' | awk '{ print $2 }')
postDisabledMods="${postDisabledMods}$additionalDisabledMods"
if [ -n "$postDisabledMods" ]
then
  outputHandler "$postDisabledMods"
fi
outputHandler ""
}

# Backup cPanel Apache config and set CT directives.
function cpanel_apache_initial {
outputHandler "${CyanF}${BoldOn}Backing up Apache configuration files${Reset}"
_apache_backup=$(cp -vp $apache_conf{,."$(date +%Y-%m-%d.$uuid.ct)"})
backup_files+=("${_apache_backup}")
outputHandler "Apache conf backed up"
touch "$addtl_directives"
_includes_backup=$(cp -v "$addtl_directives"{,."$(date +%Y-%m-%d.$uuid.ct)"})
backup_files+=("${_includes_backup}")
outputHandler "Apache includes file backed up"
outputHandler ""
outputHandler "${CyanF}${BoldOn}Adding browser caching support and Gzip compression${Reset}"
    cat <<EOT >> "$addtl_directives"
#######################################
# Custom BSD SysAdmin Apache Config #
#######################################
# Disable ETags
<ifModule headers_module>
  Header unset ETag
  FileETag None
</ifModule>
# Leverage Browser Caching
<ifModule expires_module>
    ExpiresActive On
    <FilesMatch "\.(css|javascript|js|htc|CSS|JAVASCRIPT|JS|HTC)$">
    ExpiresDefault "access plus 1 month"
    </FilesMatch>
    ExpiresByType application/javascript "access plus 1 month"
    ExpiresByType application/x-javascript "access plus 1 month"
    ExpiresByType text/css "access plus 1 month"
    # Images/Media
    <FilesMatch "\.(asf|asx|wax|wmv|wmx|avi|bmp|class|divx|doc|docx|eot|exe|gif|gz|gzip|ico|jpg|jpeg|jpe|mdb|mid|midi|mov|qt|mp3|m4a|mp4|m4v|mpeg|mpg|mpe|mpp|otf|odb|odc|odf|odg|odp|ods|odt|ogg|pdf|png|pot|pps|ppt|pptx|ra|ram|svg|svgz|swf|tar|tif|tiff|ttf|ttc|wav|wma|wri|xla|xls|xlsx|xlt|xlw|zip|ASF|ASX|WAX|WMV|WMX|AVI|BMP|CLASS|DIVX|DOC|DOCX|EOT|EXE|GIF|GZ|GZIP|ICO|JPG|JPEG|JPE|MDB|MID|MIDI|MOV|QT|MP3|M4A|MP4|M4V|MPEG|MPG|MPE|MPP|OTF|ODB|ODC|ODF|ODG|ODP|ODS|ODT|OGG|PDF|PNG|POT|PPS|PPT|PPTX|RA|RAM|SVG|SVGZ|SWF|TAR|TIF|TIFF|TTF|TTC|WAV|WMA|WRI|XLA|XLS|XLSX|XLT|XLW|ZIP)$">
    ExpiresDefault "access plus 1 month"
    </FilesMatch>
</ifModule>

# Enable GZip Compression
<IfModule deflate_module>
    SetOutputFilter DEFLATE
    SetEnvIfNoCase Request_URI \
        \.(?:exe|t?gz|zip|bz2|sit|rar|pdf)$ \
        no-gzip dont-vary
    # Level of compression (Highest 9 - Lowest 1)
    DeflateCompressionLevel 6
    # Netscape 4.x has some problems
    BrowserMatch ^Mozilla/4 gzip-only-text/html
    # Netscape 4.06-4.08 have some more problems
    BrowserMatch ^Mozilla/4\.0[678] no-gzip
    # MSIE masquerades as Netscape, but it is fine
    BrowserMatch \bMSIE !no-gzip !gzip-only-text/html
    <IfModule headers_module>
        <FilesMatch ".(js|css|xml|gz|html)$">
            Header append Vary: Accept-Encoding
        </FilesMatch>
    </IfModule>
</IfModule>
EOT
outputHandler "Updated $addtl_directives"
outputHandler ""
outputHandler "${CyanF}${BoldOn}Editing httpd configuration based on server RAM${Reset}"
cat <<EOT > $apache_conf
---
"main":
  "directory":
    "options":
      "directive": 'options'
      "item":
        "options": 'ExecCGI FollowSymLinks IncludesNOEXEC Indexes SymLinksIfOwnerMatch'
  "fileetag":
    "item":
      "fileetag": 'All'
  "keepalive":
    "item":
      "keepalive": 'On'
  "keepalivetimeout":
    "item":
      "keepalivetimeout": 5
  "maxclients":
    "item":
      "maxclients": $(( 50 + (($ramBase**2)*10) + (($ramBase-2)*10) ))
  "maxkeepaliverequests":
    "item":
      "maxkeepaliverequests": 100
  "maxrequestsperchild":
    "item":
      "maxrequestsperchild": $(( 2048 + ($ramBase*256) ))
  "maxspareservers":
    "item":
      "maxspareservers": $(($ramBase*2 + 1))
  "minspareservers":
    "item":
      "minspareservers": $ramBase
  "root_options":
    "item":
      "root_options":
        "ExecCGI": 1
        "FollowSymLinks": 1
        "Includes": 0
        "IncludesNOEXEC": 1
        "Indexes": 1
        "MultiViews": 0
        "SymLinksIfOwnerMatch": 1
  "serverlimit":
    "item":
      "serverlimit": $(( 50 + (($ramBase**2)*10) + (($ramBase-2)*10) ))
  "serversignature":
    "item":
      "serversignature": 'Off'
  "servertokens":
    "item":
      "servertokens": 'Full'
  "sslciphersuite":
    "item":
      "sslciphersuite": 'ALL:!ADH:+HIGH:+MEDIUM:-LOW:-SSLv2:-EXP'
  "startservers":
    "item":
      "startservers": $ramBase
  "timeout":
    "item":
      "timeout": 300
  "traceenable":
    "item":
      "traceenable": 'On'
EOT
outputHandler "Updated $apache_conf"
outputHandler ""
outputHandler "${CyanF}${BoldOn}Checking Apache status${Reset}"
apacheStatus=$(/sbin/service httpd status 2>&1 | egrep 'Apache Server Status|running')

if [ -z "$apacheStatus" ]
then
  catch_err "Apache is not running!"
else
   outputHandler "Apache is running"
fi
outputHandler ""
outputHandler "${CyanF}${BoldOn}Testing Apache Configuration${Reset}"
apacheTest=$(httpd -t 2>&1 | grep -v "already loaded")
if [ "$apacheTest" == "Syntax OK" ]
then
  outputHandler "$apacheTest"
  outputHandler ""
else
  catch_err "Apache Configuration File Has Invalid Syntax!"
fi
}

# Restart webserver based on panel type
function restart_services {
if [[ "$panel_type" == 'plesk' ]]
then
  if [ "$nginx_bool" == true ]
  then
    nginxTest=$(nginx -t 2>&1 | grep 'test failed')
    if [ -n "$nginxTest" ]
    then
      outputHandler "${RedF}${BoldOn}There is an error in the Nginx config file, not restarting. Here's the error message:${Reset}"
      outputHandler "$(nginx -t)"
      outputHandler ""
    else
      outputHandler "${CyanF}${BoldOn}Restarting Nginx${Reset}"
      /sbin/service nginx restart 2&>1 >/dev/null
      if [[ $? -eq 0 ]]
      then
        outputHandler "Nginx restarted successfully"
      else
        catch_err "Nginx failed to restart. Please troubleshoot manually."
      fi
      outputHandler ""
    fi
  else
    outputHandler "${CyanF}${BoldOn}Restarting Apache${Reset}"
    /sbin/service httpd restart 2&>1 >/dev/null
    if [[ $? -eq 0 ]]
    then
      outputHandler "Apache restarted successfully"
    else
      catch_err "Apache failed to restart. Please troubleshoot manually."
    fi
    outputHandler ""
  fi
fi

if [ "$panel_type" == 'cpanel' ]; then
  if [ ! -e "/etc/cpanel/ea4/is_ea4" ]; then
    outputHandler "${CyanF}${BoldOn}Distilling Apache configuration${Reset}"
    outputHandler "$(/usr/local/cpanel/bin/apache_conf_distiller --update 2>&1 )"
    outputHandler ""
  fi
  outputHandler "${CyanF}${BoldOn}Rebuilding Apache configuration${Reset}"
  outputHandler "$(/scripts/rebuildhttpdconf)"
  outputHandler ""
  apacheTest=$(httpd -t 2>&1 | grep -v "already loaded")
  if [ "$apacheTest" == "Syntax OK" ]; then
    outputHandler "${CyanF}${BoldOn}Restarting Apache${Reset}"
    restart_msg_apache="$(/usr/local/cpanel/scripts/restartsrv_httpd | tail -n1)"
    echo "$restart_msg_apache" | grep -q "httpd restarted successfully."
    if [[ $? -eq 0 ]]
    then
      outputHandler "Apache restarted successfully"
    else
      catch_err "Apache failed to restart. Please troubleshoot manually."
    fi
  else
    outputHandler "${RedF}${BoldOn}There is an error in the Apache config file, not restarting. Here's the error message:${Reset}"
    outputHandler "$apacheTest"
  fi
  outputHandler ""
fi
}

function high_inode_dirs () {
  if [ "$panel_type" == "plesk" ]; then
    high_inode_dirs_list=$(find /var/www/vhosts/ -printf '%h\n' | sort | uniq -c | sort -k 1 -nr | awk '$1>1023')
  elif [ "$panel_type" == "cpanel" ]; then
    high_inode_dirs_list=$(find /home/ \( -path "/home/virtfs" -o -path "/home/cpeasyapache" \) -prune -o -printf '%h\n' | sort | uniq -c | sort -k 1 -nr | awk '$1>1023')
  else
    high_inode_dirs_list=$(find /var/www/ -printf '%h\n' | sort | uniq -c | sort -k 1 -nr | awk '$1>1023')
  fi
}

# Create a list of files that have been backed up during the optimization.
function backup_list {
  outputHandler "${CyanF}${BoldOn}The following files were backed up${Reset}"
  if [[ ${backup_files[@]} ]]
  then
    outputHandler "${backup_files[@]}"
  else
    outputHandler "No files changed - no files backed up."
    outputHandler ""
  fi
  for (( i=1; i<=${#backup_files[@]}; i++ ))
  do
    outputHandler "${backup_files[i]}"
  done
}

# Resolution text that gets sent to a customer
function support_request {
if [[ "$nginx_bool" == true ]]; then
  _nginx="Nginx, "
fi
outputHandler "##################################################################"
outputHandler "Copy and paste the support request below and send to the customer."
outputHandler "Please also check and make sure that all settings are appropriate."
outputHandler "You may want to add some other features as well, like browser caching."
outputHandler "##################################################################"
outputHandler "Thank you for purchasing the Apache Performance Tuning service! We have completed your tuning, and wanted to provide you with the results, as well as advise you as to what changes were made."
outputHandler ""
outputHandler "First and foremost, we've backed up all configuration files for ${_nginx}Apache and PHP. Everything was timestamped if you need to restore any of these files in the future."
outputHandler ""
outputHandler "According to the third-party testing service GTMetrix, your website received a PageSpeed score of X:"
outputHandler ""
outputHandler "PASTE GTMETRIX HERE"
outputHandler ""
outputHandler "We began by adjusting your Apache prefork settings to be more appropriate for the needs of your website in relation to the amount of memory available on your server. Your new prefork settings are as follows:"
outputHandler ""
if [ "$panel_type" == "plesk" ]
then
  outputHandler "$(sed -n '/<IfModule prefork.c>/,/<\/IfModule>/p' $apache_conf)"
  outputHandler ""
  outputHandler "We then disabled several unused Apache modules which will free up a considerable amount of RAM, as it allows each Apache process to operate with a lighter memory footprint."
  if [[ "$nginx_bool" == true ]]
  then
    outputHandler ""
    outputHandler "The number of Nginx worker processes was adjusted in accordance with the number of CPU cores available on your system($num_processors), and file descriptor limits were updated as well. Lastly, we configured Nginx to use GZIP compression when serving appropriate assets, which will reduce the total byte size of your web pages."
  fi
  outputHandler ""
else
  outputHandler "StartServers $ramBase"
  outputHandler "MinSpareServers $ramBase"
  outputHandler "MaxSpareServers $(($ramBase*2 + 1))"
  outputHandler "ServerLimit $(( 50 + (($ramBase**2)*10) + (($ramBase-2)*10) ))"
  outputHandler "MaxClients $(( 50 + (($ramBase**2)*10) + (($ramBase-2)*10) ))"
  outputHandler "MaxRequestsPerChild  $(( 2048 + ($ramBase*256) ))"
  outputHandler ""
  outputHandler "Next, we added support for gzip compression on your site files. This will allow your site to reply to requests more quickly and efficiently."
  outputHandler ""
  outputHandler "Finally, we tweaked your settings to take advantage of browser cacheing features, so people who visit your site often will see it load faster and will use fewer of your system's resources."
fi
outputHandler ""
high_inode_dirs
if [ -n "$high_inode_dirs_list" ]
then
  outputHandler "In addition to adjusting the webserver configuration we scanned for website directories containing 1,024 or more inodes(files and directories). Excessively large directories can adversely impact the performance of the server and cause file system latency, which reduces the responsiveness of the website."
  outputHandler ""
  outputHandler "Below is a list of these directories. We recommend removing unnessesary files or reorganizing your sites to maintain less than 1,024 inodes per directory."
  outputHandler ""
  outputHandler "$high_inode_dirs_list"
  outputHandler ""
fi
outputHandler "Furthermore, your PageSpeed score has increased to X:"
outputHandler ""
outputHandler "PASTE GTMETRIX RESULTS HERE"
outputHandler ""
outputHandler "PLACE ANY CUSTOM SUGGESTIONS OR ACTIONS HERE"
outputHandler ""
# outputHandler "In an effort to continue improving our CloudTech services, we are including a link to a brief survey below. Your input is very important to (mt) Media Temple and will be kept confidential."
# outputHandler ""
# outputHandler "Simply click on the link below, or cut and paste the entire URL into your browser to access the survey:"
# outputHandler ""
# outputHandler "http://goo.gl/cxWO4"
# outputHandler ""
outputHandler "If you have questions about the information within this support request, feel free to contact us at any time. We are here 24/7 to assist you."
outputHandler "##################################################################"
if [[ $_headless != true ]]; then
  echo "Press enter to continue..."
  echo "##################################################################"
  read enterKey
fi
}

# Outputs differently depending on how the script was run or what happened (headless, rollback, error, etc.)
function output {
  # If in headless mode, convert output to JSON format in Base64
  if [[ $_headless == true ]]
  then
    # If there is an error or we're rolling back successfully, print notes, exit status, and uuid
    if  [[ $exitCode -eq 0 ]] && [[ $_rollback == true ]] || [[ $exitCode -ne 0 ]]
    then
      echo "{ \"note\" : \"$(
      for i in "${output_glob[@]}"
      do
        echo -e "$i"
      done | base64 -w 0
      )\", \"status\" : \"$exitCode\", \"uuid\" : \"$uuid\" }"
    else
      # If script runs successfully, print notes, resolution, exit status, and uuid
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
      done | base64 -w 0
      )\", \"status\" : \"$exitCode\", \"uuid\" : \"$uuid\" }"
      # End JSON output
    fi
  else
    # Print resolution text if script runs successfully and we're not rolling back files
    if [[ $exitCode -eq 0 ]] && [[ $_rollback != true ]]
    then
      support_request
    fi
  fi
}

# Does the optimizations
function main {
  outputHandler "${CyanF}${BoldOn}Apache Tuning Script uuid${Reset}"
  outputHandler "$uuid"
  outputHandler ""
  check_user
  check_panel
  log_dir
  if [[ $_rollback == true ]]
  then
    rollback $uuid
    exit
  fi
  calc_resources
  if [ "$nginx_bool" == true ]
  then
    nginx_initial
    nginx_tune
  fi
  if [ "$panel_type" == 'plesk' ]
  then
    plesk_apache_initial
    plesk_apache_tune
  else
    cpanel_apache_initial
  fi
  restart_services
  backup_list
}

# This function is run when trap detects the script is exiting
function FINISH {
  exitCode=$?
  case $exitCode in
    # Exit code 0 = No errors everything worked. Remove script and print output.
    0)
    rm -f -- "$0"
    output
    ;;
    # Exit code 1 = Something went wrong. Auto-rollback, remove script, and print output.
    1)
    rollback "$uuid"
    rm -f -- "$0"
    output
    ;;
    # Exit code 2 = User ran script with --help or --rollback (with invalid uuid).
    # If headless, remove script, otherwise leave it. Do not print output.
    2)
    output
    if [[ "$_headless" == true ]]
    then
      rm -f -- "$0"
    fi
    exit
    ;;
    # Exit code 3 = Error when rollback flag was used. Remove script and print output.
    3)
    rm -f -- "$0"
    output
    ;;
    # All other exit codes = Something went wrong. Auto-rollback, remove script, and print output.
    *)
    rollback "$uuid"
    rm -f -- "$0"
    output
    ;;

  esac
}

# Traps interrupts and exits and runs the FINISH function
trap FINISH INT EXIT

# This runs the main function to exectute all other functions
main

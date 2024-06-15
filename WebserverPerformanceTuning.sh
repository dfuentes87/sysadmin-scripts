#!/bin/bash

is_installed() {
  if command -v yum &> /dev/null; then
    rpm -q "$1" &>/dev/null
  elif command -v apt &> /dev/null; then
    dpkg -l | grep -q "$1"
  fi
}

# Function to backup a file
backup_file() {
  local file=$1
  local backup
  backup="${file}-$(date +%Y%m%d.%H%M%S)"
  cp "$file" "$backup"
  echo "Backup of $file saved as $backup"
}

# Check server resources
CPU_CORES=$(nproc)
MEMORY=$(free -m | awk '/^Mem:/{print $2}')

echo "CPU cores: $CPU_CORES"
echo "Memory (MB): $MEMORY"
echo

# Check if httpd, nginx, and php-fpm are installed
HTTPD_INSTALLED=false
NGINX_INSTALLED=false
PHPFPM_INSTALLED=false
is_installed httpd && HTTPD_INSTALLED=true
is_installed nginx && NGINX_INSTALLED=true
is_installed php-fpm && PHPFPM_INSTALLED=true

# Output current performance tuning parameters
if $NGINX_INSTALLED; then
  NGINX_CONF="/etc/nginx/nginx.conf"
  WORKER_PROCESSES=$(grep -E '^\s*worker_processes' $NGINX_CONF | awk '{print $2}' | sed 's/;$//')
  echo "Nginx is installed."
  echo "Current worker_processes: $WORKER_PROCESSES"
  echo
fi

if $HTTPD_INSTALLED; then
  HTTPD_CONF="/etc/httpd/conf/httpd.conf"
  [ ! -f "$HTTPD_CONF" ] && HTTPD_CONF="/etc/apache2/apache2.conf"
  MAX_SPARE_SERVERS=$(grep -E '^\s*MaxSpareServers' $HTTPD_CONF | awk '{print $2}')
  MIN_SPARE_SERVERS=$(grep -E '^\s*MinSpareServers' $HTTPD_CONF | awk '{print $2}')
  MAX_REQUEST_WORKERS=$(grep -E '^\s*MaxRequestWorkers' $HTTPD_CONF | awk '{print $2}')
  echo "Httpd is installed."
  echo "Current MaxSpareServers: $MAX_SPARE_SERVERS"
  echo "Current MinSpareServers: $MIN_SPARE_SERVERS"
  echo "Current MaxRequestWorkers: $MAX_REQUEST_WORKERS"
  echo
fi

if $PHPFPM_INSTALLED; then
  PHPFPM_CONF="/etc/php-fpm.d/www.conf"
  PM_MODE=$(grep -E '^\s*pm\s*=' $PHPFPM_CONF | awk '{print $3}')
  PM_MAX_CHILDREN=$(grep -E '^\s*pm.max_children' $PHPFPM_CONF | awk '{print $3}')
  PM_MIN_SPARE_SERVERS=$(grep -E '^\s*pm.min_spare_servers' $PHPFPM_CONF | awk '{print $3}')
  PM_MAX_SPARE_SERVERS=$(grep -E '^\s*pm.max_spare_servers' $PHPFPM_CONF | awk '{print $3}')
  PM_START_SERVERS=$(grep -E '^\s*pm.start_servers' $PHPFPM_CONF | awk '{print $3}')
  echo "PHP-FPM is installed."
  echo "Current pm: $PM_MODE"
  echo "Current pm.max_children: $PM_MAX_CHILDREN"
  echo "Current pm.min_spare_servers: $PM_MIN_SPARE_SERVERS"
  echo "Current pm.max_spare_servers: $PM_MAX_SPARE_SERVERS"
  echo "Current pm.start_servers: $PM_START_SERVERS"
fi


# Calculate best values to use for the parameters
if $NGINX_INSTALLED; then
  NEW_WORKER_PROCESSES="auto"
fi

if $HTTPD_INSTALLED; then
  NEW_MAX_SPARE_SERVERS=$((CPU_CORES * 10))
  NEW_MIN_SPARE_SERVERS=$((CPU_CORES * 5))
  NEW_MAX_REQUEST_WORKERS=$((CPU_CORES * 25))
fi

if $PHPFPM_INSTALLED; then
  NEW_PM_MAX_CHILDREN=$((MEMORY / 50))  # Assuming 50MB per PHP-FPM process
  NEW_PM_MIN_SPARE_SERVERS=$((NEW_PM_MAX_CHILDREN / 4))
  NEW_PM_MAX_SPARE_SERVERS=$((NEW_PM_MAX_CHILDREN / 2))
  NEW_PM_START_SERVERS=$((NEW_PM_MAX_CHILDREN / 8))
fi

# Check if tuning is already done for all services
nginx_tuned=true
httpd_tuned=true
phpfpm_tuned=true

if $NGINX_INSTALLED && [ "$WORKER_PROCESSES" != 'auto' ]; then
  nginx_tuned=false
fi

if $HTTPD_INSTALLED && { [ "$MAX_SPARE_SERVERS" != "$((CPU_CORES * 10))" ] || [ "$MIN_SPARE_SERVERS" != "$((CPU_CORES * 5))" ] || [ "$MAX_REQUEST_WORKERS" != "$((CPU_CORES * 25))" ]; }; then
  httpd_tuned=false
fi

if $PHPFPM_INSTALLED && { [ "$PM_MAX_CHILDREN" != "$((MEMORY / 50))" ] || [ "$PM_MIN_SPARE_SERVERS" != "$((MEMORY / 50 / 4))" ] || [ "$PM_MAX_SPARE_SERVERS" != "$((MEMORY / 50 / 2))" ] || [ "$PM_START_SERVERS" != "$((MEMORY / 50 / 8))" ]; }; then
  phpfpm_tuned=false
fi

if $nginx_tuned && $httpd_tuned && $phpfpm_tuned; then
  echo "Nothing to change."
  exit 0
fi


# Ask user if they want to update parameters
read -r -p "Do you want to update these parameters? (yes/no): " RESPONSE

if [[ "$RESPONSE" != "yes" ]]; then
  echo "Exiting without making changes."
  exit 0
fi

# Backup and modify the files
if $NGINX_INSTALLED; then
  backup_file "$NGINX_CONF"
  sed -i "s/^\s*worker_processes\s*.*/worker_processes $NEW_WORKER_PROCESSES;/" "$NGINX_CONF"
  echo "Updated worker_processes in $NGINX_CONF to $NEW_WORKER_PROCESSES"
fi

if $HTTPD_INSTALLED; then
  backup_file "$HTTPD_CONF"
  sed -i "s/^\s*MaxSpareServers\s*.*/MaxSpareServers $NEW_MAX_SPARE_SERVERS/" "$HTTPD_CONF"
  sed -i "s/^\s*MinSpareServers\s*.*/MinSpareServers $NEW_MIN_SPARE_SERVERS/" "$HTTPD_CONF"
  sed -i "s/^\s*MaxRequestWorkers\s*.*/MaxRequestWorkers $NEW_MAX_REQUEST_WORKERS/" "$HTTPD_CONF"
  echo "Updated MaxSpareServers in $HTTPD_CONF to $NEW_MAX_SPARE_SERVERS"
  echo "Updated MinSpareServers in $HTTPD_CONF to $NEW_MIN_SPARE_SERVERS"
  echo "Updated MaxRequestWorkers in $HTTPD_CONF to $NEW_MAX_REQUEST_WORKERS"
fi

if $PHPFPM_INSTALLED; then
  backup_file "$PHPFPM_CONF"
  sed -i "s/^\s*pm.max_children\s*=.*/pm.max_children = $NEW_PM_MAX_CHILDREN/" "$PHPFPM_CONF"
  sed -i "s/^\s*pm.min_spare_servers\s*=.*/pm.min_spare_servers = $NEW_PM_MIN_SPARE_SERVERS/" "$PHPFPM_CONF"
  sed -i "s/^\s*pm.max_spare_servers\s*=.*/pm.max_spare_servers = $NEW_PM_MAX_SPARE_SERVERS/" "$PHPFPM_CONF"
  sed -i "s/^\s*pm.start_servers\s*=.*/pm.start_servers = $NEW_PM_START_SERVERS/" "$PHPFPM_CONF"
  echo "Updated pm.max_children in $PHPFPM_CONF to $NEW_PM_MAX_CHILDREN"
  echo "Updated pm.min_spare_servers in $PHPFPM_CONF to $NEW_PM_MIN_SPARE_SERVERS"
  echo "Updated pm.max_spare_servers in $PHPFPM_CONF to $NEW_PM_MAX_SPARE_SERVERS"
  echo "Updated pm.start_servers in $PHPFPM_CONF to $NEW_PM_START_SERVERS"
fi

echo "Configuration updates completed."

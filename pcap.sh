#! /bin/bash

# Set the arguments (if given) for use
pcap=$1

# Check if a tcpdump file is provided
if [[ -f "${pcap}" ]]; then
  grep -v 'only meaningful' "$pcap"
elif [[ -z "${pcap}" ]]; then
  pcap=$(echo "tcpdump_$(date +%Y%m%d_%H%M%S).pcap")
  echo ">> No pcap file provided, creating ~/tcpdumps/${pcap}_file <<"
  mkdir -p ~/tcpdumps/
  echo
  tcpdump port 53 -nvv -w ~/tcpdumps/"${pcap}"_file -c 2500
  pcap=~/tcpdumps/"${pcap}"_file
else
  echo ">You must provide a valid tcpdump file, or use no arguments to create one."
  exit
fi

# find top domains
echo
echo "TOP DOMAINS"
tcpdump -tnnr "${pcap}" 2>&1 | grep -v 'reading from file' |
sed 's/.*? //g;s/. .*//g;/[0-9]$/d;/in-addr.arpa/d' |
grep -oP '\w(?!\.).[\w\d-]{2,}\.[\w]{2,}(\n|$)|[\w\d-]{1,}\.[\w\d-]{2,3}\.[\w]{2}(\n|$)' |
sort | uniq -c | sort -rn | head | awk '{print $1" : "$2}'
echo

# find top IPs
echo "TOP IPS"
tcpdump -tnnr "${pcap}" 2>&1 | grep -v 'reading from file' |
awk '{print $2}' | cut -d '.' -f1-4 |
sort | uniq -c | sort -rn | head | awk '{print $1" : "$2}'
echo

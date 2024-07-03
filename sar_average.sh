#!/bin/bash

# Function to calculate median
calculate_median() {
    arr=($(printf '%s\n' "${@}" | sort -n))
    len=${#arr[@]}
    if (( len % 2 == 1 )); then
        median=${arr[$((len/2))]}
    else
        median=$(awk "BEGIN {print (${arr[$((len/2 - 1))]} + ${arr[$((len/2))]}) / 2}")
    fi
    echo $median
}

for i in {0..6}; do
    day=$(date -d "-$i days" +%d)
    date=$(date -d "-$i days" +%Y-%m-%d)
    sar_file="/var/log/sa/sa${day}"

    if [ ! -f $sar_file ]; then
        echo "No data for ${date}"
        continue
    fi

    echo "Date: $date"

    # CPU Usage
    cpu_usage=($(sar -u -i 600 -f $sar_file | awk '{if(NR>3) print $3 + $5 + $6}'))

    cpu_min=$(printf '%s\n' "${cpu_usage[@]}" | sort -n | head -n 1)
    cpu_max=$(printf '%s\n' "${cpu_usage[@]}" | sort -n | tail -n 1)
    cpu_median=$(calculate_median "${cpu_usage[@]}")

    echo "  CPU Usage: Min=${cpu_min}%, Max=${cpu_max}%, Median=${cpu_median}%"

    # Memory Usage
    mem_usage_kb=($(sar -r -i 600 -f $sar_file | awk '{if(NR>3) print $4}'))
    mem_usage_mb=($(for mem in "${mem_usage_kb[@]}"; do echo "scale=2; $mem / 1024" | bc; done))

    mem_min=$(printf '%s\n' "${mem_usage_mb[@]}" | sort -n | head -n 1)
    mem_max=$(printf '%s\n' "${mem_usage_mb[@]}" | sort -n | tail -n 1)
    mem_median=$(calculate_median "${mem_usage_mb[@]}")

    echo "  Memory Usage: Min=${mem_min}MB, Max=${mem_max}MB, Median=${mem_median}MB"
    echo ""
done

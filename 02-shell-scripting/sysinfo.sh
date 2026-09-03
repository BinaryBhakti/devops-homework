#!/bin/bash
# =============================================================================
#  sysinfo.sh - System Information Script
#  DevOps Homework - Session 3 (Shell Scripting)
#
#  Demonstrates: variables, command substitution, read -p, mkdir, touch,
#                echo, date, hostname, whoami, df, ps, and > redirection.
#
#  Usage:  chmod +x sysinfo.sh && ./sysinfo.sh
# =============================================================================

# ---------------------------------------------------------------------------
# 1. VARIABLES - store command output using command substitution $( )
# ---------------------------------------------------------------------------
current_date=$(date)
current_date_short=$(date '+%Y-%m-%d')
current_time=$(date '+%H:%M:%S')
host_name=$(hostname)
user_name=$(whoami)
kernel_info=$(uname -srm)
uptime_info=$(uptime -p 2>/dev/null || uptime)

# ---------------------------------------------------------------------------
# 2. PRINT THE SYSTEM INFORMATION
# ---------------------------------------------------------------------------
echo "==========================================================="
echo "               SYSTEM INFORMATION REPORT"
echo "==========================================================="
echo
echo "Current Date & Time : $current_date"
echo "Hostname            : $host_name"
echo "Username            : $user_name"
echo "Kernel              : $kernel_info"
echo "Uptime              : $uptime_info"
echo

echo "-----------------------------------------------------------"
echo "  DISK USAGE  (df -h)"
echo "-----------------------------------------------------------"
df -h
echo

echo "-----------------------------------------------------------"
echo "  RUNNING PROCESSES  (ps aux | head -10)"
echo "-----------------------------------------------------------"
ps aux | head -10
echo

# ---------------------------------------------------------------------------
# 3. TAKE USER INPUT WITH read -p
# ---------------------------------------------------------------------------
echo "-----------------------------------------------------------"
echo "  USER INPUT"
echo "-----------------------------------------------------------"
read -p "Enter your name          : " name
read -p "Enter your roll number   : " roll_no
read -p "Enter a short comment    : " comment
echo

echo "My name is        : $name"
echo "My roll number is : $roll_no"
echo "My comment is     : $comment"
echo

# ---------------------------------------------------------------------------
# 4. CREATE A DIRECTORY WITH mkdir  AND A FILE WITH touch
# ---------------------------------------------------------------------------
report_dir="sysinfo_report"
process_file="$report_dir/process.log"
summary_file="$report_dir/summary.txt"

echo "-----------------------------------------------------------"
echo "  CREATING OUTPUT FILES"
echo "-----------------------------------------------------------"

mkdir -p "$report_dir"
echo "[+] Directory created : $report_dir"

touch "$process_file"
echo "[+] File created      : $process_file"

touch "$summary_file"
echo "[+] File created      : $summary_file"
echo

# ---------------------------------------------------------------------------
# 5. STORE RUNNING PROCESSES IN THE FILE USING > REDIRECTION
# ---------------------------------------------------------------------------
ps aux > "$process_file"
echo "[+] Running processes saved to $process_file using > redirection"

# Build a summary file: > creates/overwrites, >> appends
echo "===== SYSTEM SUMMARY =====" >  "$summary_file"
echo "Generated on : $current_date_short at $current_time" >> "$summary_file"
echo "Hostname     : $host_name"       >> "$summary_file"
echo "Username     : $user_name"       >> "$summary_file"
echo "Kernel       : $kernel_info"     >> "$summary_file"
echo "Name         : $name"            >> "$summary_file"
echo "Roll Number  : $roll_no"         >> "$summary_file"
echo "Comment      : $comment"         >> "$summary_file"
echo ""                                >> "$summary_file"
echo "----- Disk Usage -----"          >> "$summary_file"
df -h                                  >> "$summary_file"
echo "[+] Summary saved to $summary_file"
echo

# ---------------------------------------------------------------------------
# 6. VERIFY WHAT WE CREATED
# ---------------------------------------------------------------------------
echo "-----------------------------------------------------------"
echo "  VERIFICATION"
echo "-----------------------------------------------------------"
echo "\$ ls -l $report_dir"
ls -l "$report_dir"
echo
echo "\$ wc -l $process_file"
wc -l "$process_file"
echo
echo "\$ head -5 $process_file"
head -5 "$process_file"
echo
echo "\$ cat $summary_file"
cat "$summary_file"
echo
echo "==========================================================="
echo "  Script completed successfully."
echo "==========================================================="

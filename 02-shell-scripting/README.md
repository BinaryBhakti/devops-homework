# Homework 2 — Shell Scripting

**Task:** a System Information Script that prints the date, hostname, username, disk usage and
running processes; uses variables; takes input with `read -p`; creates a directory with `mkdir`
and a file with `touch`; and stores the process list in that file using `>` redirection.

Script: **[`sysinfo.sh`](sysinfo.sh)** · Captured run: [`outputs/sysinfo-run.txt`](outputs/sysinfo-run.txt)

## Requirements checklist

| # | Requirement | Where it is met |
|---|---|---|
| 1 | Print the current date | `date` → `$current_date` |
| 2 | Print the hostname | `hostname` → `$host_name` |
| 3 | Print the username | `whoami` → `$user_name` |
| 4 | Print the disk usage | `df -h` |
| 5 | Print the running processes | `ps aux` |
| 6 | Use variables | `current_date`, `host_name`, `user_name`, `report_dir`, `process_file`, … |
| 7 | Take user input with `read -p` | name, roll number, comment |
| 8 | Create a directory with `mkdir` | `mkdir -p "$report_dir"` |
| 9 | Create a file with `touch` | `touch "$process_file"` |
| 10 | Store processes in the file with `>` | `ps aux > "$process_file"` |

## How to run it

```bash
chmod +x sysinfo.sh
./sysinfo.sh
```

It will pause three times and wait for you to type a name, a roll number and a comment.

## The concepts used

### Variables and command substitution

```bash
current_date=$(date)        # $( ) runs the command and stores its OUTPUT
host_name=$(hostname)
user_name=$(whoami)
```

- **No spaces** around `=`. `x = 5` is an error; `x=5` is an assignment.
- `$(command)` is command substitution — the modern form of backticks, and nestable.
- Read a variable back with `$name` or `${name}`.
- Always quote when using them: `"$report_dir"` survives spaces in the value, `$report_dir` does not.

### Taking input

```bash
read -p "Enter your name          : " name
```

`-p` prints the prompt on the same line before reading. Other useful flags:

| Flag | Effect |
|---|---|
| `-p "text"` | show a prompt |
| `-s` | silent — don't echo (passwords) |
| `-t 10` | time out after 10 seconds |
| `-n 1` | accept a single character |
| `-a arr` | read into an array |

### Redirection

| Syntax | Meaning |
|---|---|
| `ps aux > file` | write stdout to the file, **overwriting** it |
| `echo x >> file` | **append** instead |
| `cmd 2> file` | redirect stderr |
| `cmd > file 2>&1` | redirect both |

The script uses `>` to create `process.log`, then `>>` repeatedly to build `summary.txt`
line by line — the standard "truncate once, then append" pattern.

## Output

Here is the complete run. Note the script created `sysinfo_report/`, wrote both files, and
then read them back to prove it worked.

```console
===========================================================
               SYSTEM INFORMATION REPORT
===========================================================

Current Date & Time : Thu Sep  3 04:34:01 UTC 2026
Hostname            : ff4c4be986b8
Username            : root
Kernel              : Linux 7.0.12-linuxkit aarch64
Uptime              : up 4 days, 7 hours, 49 minutes

-----------------------------------------------------------
  DISK USAGE  (df -h)
-----------------------------------------------------------
Filesystem      Size  Used Avail Use% Mounted on
overlay         224G  2.6G  210G   2% /
tmpfs            64M     0   64M   0% /dev
shm              64M     0   64M   0% /dev/shm
tmpfs           2.0G   36K  2.0G   1% /run
tmpfs           2.0G     0  2.0G   0% /run/lock
/dev/vda1       224G  2.6G  210G   2% /etc/hosts

-----------------------------------------------------------
  RUNNING PROCESSES  (ps aux | head -10)
-----------------------------------------------------------
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  0.0  0.2  20968 11696 ?        Ss   04:19   0:00 /sbin/init
root          23  0.0  0.2  33636 11420 ?        S<s  04:19   0:00 /usr/lib/systemd/systemd-journald
message+      71  0.0  0.0   8404  3972 ?        Ss   04:19   0:00 @dbus-daemon --system --address=systemd: --nofork --nopidfile --systemd-activation --syslog-only
root          74  0.0  0.1  17204  7172 ?        Ss   04:19   0:00 /usr/lib/systemd/systemd-logind
root          77  0.0  0.0   2700  1716 tty1     Ss+  04:19   0:00 /sbin/agetty -o -p -- \u --noclear - linux
root        1061  0.0  0.0  10380  1548 ?        Ss   04:26   0:00 nginx: master process /usr/sbin/nginx -g daemon on; master_process on;
www-data    1062  0.0  0.0  10752  3360 ?        S    04:26   0:00 nginx: worker process
www-data    1063  0.0  0.0  10752  3360 ?        S    04:26   0:00 nginx: worker process
www-data    1064  0.0  0.0  10752  2908 ?        S    04:26   0:00 nginx: worker process

-----------------------------------------------------------
  USER INPUT
-----------------------------------------------------------

My name is        : Ashmit Nayak
My roll number is : 2024-DEVOPS-001
My comment is     : Session 3 shell scripting homework

-----------------------------------------------------------
  CREATING OUTPUT FILES
-----------------------------------------------------------
[+] Directory created : sysinfo_report
[+] File created      : sysinfo_report/process.log
[+] File created      : sysinfo_report/summary.txt

[+] Running processes saved to sysinfo_report/process.log using > redirection
[+] Summary saved to sysinfo_report/summary.txt

-----------------------------------------------------------
  VERIFICATION
-----------------------------------------------------------
$ ls -l sysinfo_report
total 8
-rw-r--r-- 1 root root 1943 Sep  3 04:34 process.log
-rw-r--r-- 1 root root  610 Sep  3 04:34 summary.txt

$ wc -l sysinfo_report/process.log
18 sysinfo_report/process.log

$ head -5 sysinfo_report/process.log
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  0.0  0.2  20968 11696 ?        Ss   04:19   0:00 /sbin/init
root          23  0.0  0.2  33636 11420 ?        S<s  04:19   0:00 /usr/lib/systemd/systemd-journald
message+      71  0.0  0.0   8404  3972 ?        Ss   04:19   0:00 @dbus-daemon --system --address=systemd: --nofork --nopidfile --systemd-activation --syslog-only
root          74  0.0  0.1  17204  7172 ?        Ss   04:19   0:00 /usr/lib/systemd/systemd-logind

$ cat sysinfo_report/summary.txt
===== SYSTEM SUMMARY =====
Generated on : 2026-09-03 at 04:34:01
Hostname     : ff4c4be986b8
Username     : root
Kernel       : Linux 7.0.12-linuxkit aarch64
Name         : Ashmit Nayak
Roll Number  : 2024-DEVOPS-001
Comment      : Session 3 shell scripting homework

----- Disk Usage -----
Filesystem      Size  Used Avail Use% Mounted on
overlay         224G  2.6G  210G   2% /
tmpfs            64M     0   64M   0% /dev
shm              64M     0   64M   0% /dev/shm
tmpfs           2.0G   36K  2.0G   1% /run
tmpfs           2.0G     0  2.0G   0% /run/lock
/dev/vda1       224G  2.6G  210G   2% /etc/hosts

===========================================================
  Script completed successfully.
===========================================================
```

> **Why the `read -p` prompts don't appear above:** bash only writes the prompt when stdin is
> a terminal. This run was fed from a pipe (`printf ... | ./sysinfo.sh`) so the three prompts
> were suppressed, but the values were still read — you can see them echoed back as
> `My name is : Ashmit Nayak`. Run it interactively and the prompts appear normally.

## Generated files

The script produced these, and copies are committed in [`sample-output/`](sample-output):

### `sysinfo_report/process.log` — written with `ps aux > "$process_file"`

```console
$ head -5 sysinfo_report/process.log
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  0.0  0.2  20968 11696 ?        Ss   04:19   0:00 /sbin/init
root          23  0.0  0.2  33636 11420 ?        S<s  04:19   0:00 /usr/lib/systemd/systemd-journald
message+      71  0.0  0.0   8404  3972 ?        Ss   04:19   0:00 @dbus-daemon --system ...
root          74  0.0  0.1  17204  7172 ?        Ss   04:19   0:00 /usr/lib/systemd/systemd-logind

$ wc -l sysinfo_report/process.log
18 sysinfo_report/process.log
```

### `sysinfo_report/summary.txt` — built with `>` then `>>`

```console
$ cat sysinfo_report/summary.txt
===== SYSTEM SUMMARY =====
Generated on : 2026-09-03 at 04:34:01
Hostname     : ff4c4be986b8
Username     : root
Kernel       : Linux 7.0.12-linuxkit aarch64
Name         : Ashmit Nayak
Roll Number  : 2024-DEVOPS-001
Comment      : Session 3 shell scripting homework

----- Disk Usage -----
Filesystem      Size  Used Avail Use% Mounted on
overlay         224G  2.6G  210G   2% /
tmpfs            64M     0   64M   0% /dev
shm              64M     0   64M   0% /dev/shm
tmpfs           2.0G   36K  2.0G   1% /run
tmpfs           2.0G     0  2.0G   0% /run/lock
/dev/vda1       224G  2.6G  210G   2% /etc/hosts
```

## Command reference

| Command | Purpose | Used as |
|---|---|---|
| `date` | current date/time | `date`, `date '+%Y-%m-%d'` |
| `hostname` | machine name | `hostname` |
| `whoami` | current user | `whoami` |
| `uname -srm` | kernel, release, architecture | `uname -srm` |
| `df -h` | disk usage, human-readable | `df -h` |
| `ps aux` | all running processes | `ps aux \| head -10` |
| `read -p` | prompt and read input | `read -p "Name: " name` |
| `mkdir -p` | create directory, no error if present | `mkdir -p "$report_dir"` |
| `touch` | create empty file / update mtime | `touch "$process_file"` |
| `echo` | print text | `echo "Hostname : $host_name"` |
| `>` | redirect stdout, overwriting | `ps aux > process.log` |
| `>>` | redirect stdout, appending | `df -h >> summary.txt` |
| `wc -l` | count lines | `wc -l process.log` |
| `head -n` | first n lines | `head -5 process.log` |

## Notes

- `#!/bin/bash` on line 1 is the shebang — it tells the kernel which interpreter to use.
- `mkdir -p` is used rather than plain `mkdir` so re-running the script is not an error.
- The script is checked with `bash -n sysinfo.sh` (syntax check without executing).
- The captured run above was executed inside the Ubuntu 24.04 lab container described in
  [Homework 1](../01-linux), so `df` and `ps` show real Linux output.
- `2024-DEVOPS-001` is placeholder input — re-run the script and type your own roll number.

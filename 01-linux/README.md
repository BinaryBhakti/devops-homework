# Homework 1 — Linux

Four tasks: soft/hard links, `adduser` vs `useradd`, `journalctl`, and the command cheat sheet.

Every command below was actually executed, and **every output block is extracted verbatim from
the captured transcripts** in [`outputs/`](outputs) — nothing is hand-written or abridged. The
scripts that produced them are in [`scripts/`](scripts).

## Lab environment

The host machine for this homework is macOS, which has no `useradd`, no `adduser` and no
`journalctl`. So the Linux tasks were run inside a real **Ubuntu 24.04 container running
systemd as PID 1** — that is what makes `journalctl` and `systemctl` genuinely work, rather
than reporting "no journal files were found".

```bash
docker build -t linux-lab:24.04 -f Dockerfile.lab .

docker run -d --name linux-lab --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --tmpfs /run --tmpfs /run/lock \
  linux-lab:24.04

docker exec linux-lab systemctl is-system-running   # -> running
docker exec linux-lab ps -p 1 -o comm=              # -> systemd
```

The image definition is in [`Dockerfile.lab`](Dockerfile.lab).

---

# Task 1 — Soft Link & Hard Link

## The one-sentence difference

A **hard link** is another *name* for the same data on disk.
A **soft link** is a small file that *stores a path* to another name.

Everything else follows from that.

## How the filesystem sees it

Every file on disk is an **inode** — the actual metadata and data blocks. A directory entry is
just a *name pointing at an inode*. The inode keeps a **link count** of how many names point
at it, and the data is only freed when that count reaches zero.
```
  HARD LINK — two names, ONE inode, link count 2

     original.txt ─┐
                   ├──> inode 24742 ──> [ file data ]
     hardlink.txt ─┘        links: 2

  SOFT LINK — two SEPARATE inodes; one holds a path string

     softlink.txt ──> inode 24743 ──> "original.txt"  (just text)
                                            │
                                            └ resolved at access time
     original.txt ──> inode 24742 ──> [ file data ]
```

## Commands

| Action | Command |
|---|---|
| Create a hard link | `ln target linkname` |
| Create a soft link | `ln -s target linkname` |
| Create a soft link to a directory | `ln -s /path/to/dir linkname` |
| Show inode + link count | `ls -li` |
| Show link target | `readlink linkname` |
| Full detail | `stat filename` |
| Delete either kind | `rm linkname` or `unlink linkname` |
| Count hard links | `stat -c '%h' file` |
| Find broken symlinks | `find . -xtype l` |
| Overwrite an existing link | `ln -sf newtarget linkname` |

## Comparison table

| | Hard link | Soft (symbolic) link |
|---|---|---|
| Command | `ln a b` | `ln -s a b` |
| Own inode? | No — shares the target's inode | Yes — separate inode |
| Increments link count? | Yes | No |
| Survives deleting the original? | **Yes**, data stays alive | **No**, becomes a dangling link |
| Can cross filesystems? | No | Yes |
| Can link a directory? | No (generally forbidden) | Yes |
| Size | Same as the target | Length of the path string |
| `ls -l` shows | `-rw-r--r-- 2 ...` | `lrwxrwxrwx ... link -> target` |
| Permissions | The target's | Always `lrwxrwxrwx` (target's apply) |
| Relative/absolute matters? | No | **Yes** — a relative link breaks if moved |

## Creating both, side by side

```console
$ ls -li original.txt
24742 -rw-r--r-- 1 root root 29 Sep  3 04:20 original.txt

$ ln original.txt hardlink.txt
$ ls -li original.txt hardlink.txt
24742 -rw-r--r-- 2 root root 29 Sep  3 04:20 hardlink.txt
24742 -rw-r--r-- 2 root root 29 Sep  3 04:20 original.txt
```

The hard link did **not** create a new file — same inode `24742`, and the link count went from
`1` to `2`. Now add a soft link:

```console
$ ln -s original.txt softlink.txt
$ ls -li original.txt hardlink.txt softlink.txt
24742 -rw-r--r-- 2 root root 29 Sep  3 04:20 hardlink.txt
24742 -rw-r--r-- 2 root root 29 Sep  3 04:20 original.txt
24743 lrwxrwxrwx 1 root root 12 Sep  3 04:20 softlink.txt -> original.txt
```

The soft link has its **own** inode (`24743`), type `l`, size 12 (the length of the string
`original.txt`), and `ls` shows what it points at.

`stat` makes the difference explicit:

```console
$ stat hardlink.txt
  File: hardlink.txt
  Size: 29        	Blocks: 8          IO Block: 4096   regular file
Device: 0,56	Inode: 24742       Links: 2
Access: (0644/-rw-r--r--)  Uid: (    0/    root)   Gid: (    0/    root)
Access: 2026-09-03 04:20:21.999875001 +0000
Modify: 2026-09-03 04:20:21.998875001 +0000
Change: 2026-09-03 04:20:22.004875001 +0000
 Birth: 2026-09-03 04:20:21.998875001 +0000

$ stat softlink.txt
  File: softlink.txt -> original.txt
  Size: 12        	Blocks: 0          IO Block: 4096   symbolic link
Device: 0,56	Inode: 24743       Links: 1
Access: (0777/lrwxrwxrwx)  Uid: (    0/    root)   Gid: (    0/    root)
Access: 2026-09-03 04:20:22.008875001 +0000
Modify: 2026-09-03 04:20:22.007875001 +0000
Change: 2026-09-03 04:20:22.007875001 +0000
 Birth: 2026-09-03 04:20:22.007875001 +0000
```

`Links: 2` versus `Links: 1`, and `regular file` versus `symbolic link`.

## Writing through a link changes the one underlying file

Appending through the **hard link** is visible through every other name:

```console
$ echo 'Line added through the HARD link' >> hardlink.txt
$ cat original.txt
Hello from the original file
Line added through the HARD link

$ cat softlink.txt
Hello from the original file
Line added through the HARD link
```

## The proof — deleting the original

This is the part interviewers actually ask about:

```console
$ rm original.txt
$ ls -li
total 4
24742 -rw-r--r-- 1 root root 62 Sep  3 04:20 hardlink.txt
24743 lrwxrwxrwx 1 root root 12 Sep  3 04:20 softlink.txt -> original.txt
```

The hard link survived and its count dropped `2 → 1`. The soft link still exists as a file but
now points at a name that is gone:

```console
$ cat hardlink.txt
Hello from the original file
Line added through the HARD link

$ cat softlink.txt
cat: softlink.txt: No such file or directory

$ ls -l softlink.txt
lrwxrwxrwx 1 root root 12 Sep  3 04:20 softlink.txt -> original.txt

$ readlink softlink.txt
original.txt

$ test -e softlink.txt && echo 'target exists' || echo 'BROKEN LINK: target does not exist'
BROKEN LINK: target does not exist

$ file softlink.txt
softlink.txt: broken symbolic link to original.txt
```

The hard link reads fine; the soft link fails with `No such file or directory` even though
`ls -l` still lists it happily. Restoring *any* file at that path instantly heals it — a
symlink resolves by name, not by identity:

```console
$ ln hardlink.txt original.txt
$ cat softlink.txt
Hello from the original file
Line added through the HARD link
```

## Directories: hard links are refused, soft links are fine

```console
$ ln mydir dirhardlink
ln: mydir: hard link not allowed for directory

$ ln -s mydir dirsoftlink
$ ls -l dirsoftlink
lrwxrwxrwx 1 root root 5 Sep  3 04:20 dirsoftlink -> mydir
```

Hard links to directories are forbidden because they would let you create loops in the
directory tree, which would break every tool that walks the filesystem (`find`, `du`, `rm -r`)
and make the tree impossible to garbage-collect safely.

## Deleting links, and when the data actually dies

`rm` removes a *name*. The data blocks are released only when the last name is gone (and no
process still holds the file open). Removing one of two hard links leaves the data intact:

```console
$ rm hardlink.txt
$ ls -li
total 8
24744 drwxr-xr-x 2 root root 4096 Sep  3 04:20 mydir
24742 -rw-r--r-- 1 root root   62 Sep  3 04:20 original.txt

$ cat original.txt
Hello from the original file
Line added through the HARD link
```

Removing the last remaining name finally frees it:

```console
$ rm original.txt
$ ls -li
total 4
24744 drwxr-xr-x 2 root root 4096 Sep  3 04:20 mydir
```

Three names on one inode, and the link count proves it:

```console
$ ls -li f1.txt f2.txt f3.txt
24742 -rw-r--r-- 3 root root 5 Sep  3 04:20 f1.txt
24742 -rw-r--r-- 3 root root 5 Sep  3 04:20 f2.txt
24742 -rw-r--r-- 3 root root 5 Sep  3 04:20 f3.txt

$ stat -c '%n has %h hard links (inode %i)' f1.txt
f1.txt has 3 hard links (inode 24742)
```

Finding dangling symlinks:

```console
$ ln -s /no/such/file broken.link

$ find . -xtype l
./broken.link
```

## Interview answers

**Q: What is the difference between a hard link and a soft link?**
A hard link is an additional directory entry pointing at the same inode, so it *is* the file —
there is no "original". A soft link is a separate small file whose contents are a path, resolved
at access time. Consequently: deleting the original breaks a soft link but not a hard link;
hard links cannot cross filesystems or point at directories, soft links can do both.

**Q: Why can't a hard link cross filesystems?**
Inode numbers are only unique *within* a filesystem. A directory entry on filesystem A cannot
reference an inode on filesystem B, because the number would be meaningless there. A soft link
stores a path string, which is filesystem-independent, so it works fine.

**Q: What happens to disk space when you delete a hard link?**
Nothing, unless it was the last one. The inode's link count decrements; the blocks are freed
only at zero.

**Q: How do you spot a symlink?**
`ls -l` shows a leading `l` and `-> target`. `readlink` prints the target. `test -L` is true for
a symlink; `test -e` is false for a *broken* one — which is how you detect dangling links,
or `find . -xtype l`.

**Q: A symlink shows `lrwxrwxrwx`. Does that mean anyone can edit the target?**
No. The permission bits on a symlink are ignored; the kernel enforces the *target's*
permissions.

**Q: What is a dangling symlink?**
One whose target no longer exists. It still lists fine in `ls`, but every attempt to open it
fails with `ENOENT` — exactly the `No such file or directory` seen above.

**Q: Why does `ln -s` need care with relative paths?**
A relative symlink is resolved relative to *the directory the link lives in*. Move the link
somewhere else and it silently points at a different place, or nowhere.

<details>
<summary><b>Full Task 1 transcript</b> (click to expand — all 11 steps)</summary>

```console
###############################################
# STEP 1: Create an original file
###############################################
$ echo 'Hello from the original file' > original.txt

$ cat original.txt
Hello from the original file

$ ls -li original.txt
24742 -rw-r--r-- 1 root root 29 Sep  3 04:20 original.txt

###############################################
# STEP 2: Create a HARD link  (ln src link)
###############################################
$ ln original.txt hardlink.txt

$ ls -li original.txt hardlink.txt
24742 -rw-r--r-- 2 root root 29 Sep  3 04:20 hardlink.txt
24742 -rw-r--r-- 2 root root 29 Sep  3 04:20 original.txt

###############################################
# STEP 3: Create a SOFT/SYMBOLIC link  (ln -s src link)
###############################################
$ ln -s original.txt softlink.txt

$ ls -li original.txt hardlink.txt softlink.txt
24742 -rw-r--r-- 2 root root 29 Sep  3 04:20 hardlink.txt
24742 -rw-r--r-- 2 root root 29 Sep  3 04:20 original.txt
24743 lrwxrwxrwx 1 root root 12 Sep  3 04:20 softlink.txt -> original.txt

###############################################
# STEP 4: Compare inode numbers and link counts
###############################################
$ stat original.txt
  File: original.txt
  Size: 29        	Blocks: 8          IO Block: 4096   regular file
Device: 0,56	Inode: 24742       Links: 2
Access: (0644/-rw-r--r--)  Uid: (    0/    root)   Gid: (    0/    root)
Access: 2026-09-03 04:20:21.999875001 +0000
Modify: 2026-09-03 04:20:21.998875001 +0000
Change: 2026-09-03 04:20:22.004875001 +0000
 Birth: 2026-09-03 04:20:21.998875001 +0000

$ stat hardlink.txt
  File: hardlink.txt
  Size: 29        	Blocks: 8          IO Block: 4096   regular file
Device: 0,56	Inode: 24742       Links: 2
Access: (0644/-rw-r--r--)  Uid: (    0/    root)   Gid: (    0/    root)
Access: 2026-09-03 04:20:21.999875001 +0000
Modify: 2026-09-03 04:20:21.998875001 +0000
Change: 2026-09-03 04:20:22.004875001 +0000
 Birth: 2026-09-03 04:20:21.998875001 +0000

$ stat softlink.txt
  File: softlink.txt -> original.txt
  Size: 12        	Blocks: 0          IO Block: 4096   symbolic link
Device: 0,56	Inode: 24743       Links: 1
Access: (0777/lrwxrwxrwx)  Uid: (    0/    root)   Gid: (    0/    root)
Access: 2026-09-03 04:20:22.008875001 +0000
Modify: 2026-09-03 04:20:22.007875001 +0000
Change: 2026-09-03 04:20:22.007875001 +0000
 Birth: 2026-09-03 04:20:22.007875001 +0000

###############################################
# STEP 5: Both links read the same content
###############################################
$ cat hardlink.txt
Hello from the original file

$ cat softlink.txt
Hello from the original file

###############################################
# STEP 6: Edit through the hard link -> all see it
###############################################
$ echo 'Line added through the HARD link' >> hardlink.txt

$ cat original.txt
Hello from the original file
Line added through the HARD link

$ cat softlink.txt
Hello from the original file
Line added through the HARD link

###############################################
# STEP 7: THE KEY TEST -- delete the original file
###############################################
$ rm original.txt

$ ls -li
total 4
24742 -rw-r--r-- 1 root root 62 Sep  3 04:20 hardlink.txt
24743 lrwxrwxrwx 1 root root 12 Sep  3 04:20 softlink.txt -> original.txt

--- Hard link still works (data survives, link count 2 -> 1): ---
$ cat hardlink.txt
Hello from the original file
Line added through the HARD link

--- Soft link is now BROKEN / dangling (points to a name that is gone): ---
$ cat softlink.txt
cat: softlink.txt: No such file or directory

$ ls -l softlink.txt
lrwxrwxrwx 1 root root 12 Sep  3 04:20 softlink.txt -> original.txt

$ readlink softlink.txt
original.txt

$ test -e softlink.txt && echo 'target exists' || echo 'BROKEN LINK: target does not exist'
BROKEN LINK: target does not exist

$ file softlink.txt
softlink.txt: broken symbolic link to original.txt

###############################################
# STEP 8: Restore the name -> soft link heals itself
###############################################
$ ln hardlink.txt original.txt

$ cat softlink.txt
Hello from the original file
Line added through the HARD link

###############################################
# STEP 9: Hard links CANNOT cross filesystems or link directories
###############################################
$ mkdir mydir

$ ln mydir dirhardlink
ln: mydir: hard link not allowed for directory

--- but a SOFT link to a directory is perfectly legal: ---
$ ln -s mydir dirsoftlink

$ ls -l dirsoftlink
lrwxrwxrwx 1 root root 5 Sep  3 04:20 dirsoftlink -> mydir

$ ls -ld dirsoftlink/
drwxr-xr-x 2 root root 4096 Sep  3 04:20 dirsoftlink/

###############################################
# STEP 10: Deleting links
###############################################
$ ls -li
total 12
24745 lrwxrwxrwx 1 root root    5 Sep  3 04:20 dirsoftlink -> mydir
24742 -rw-r--r-- 2 root root   62 Sep  3 04:20 hardlink.txt
24744 drwxr-xr-x 2 root root 4096 Sep  3 04:20 mydir
24742 -rw-r--r-- 2 root root   62 Sep  3 04:20 original.txt
24743 lrwxrwxrwx 1 root root   12 Sep  3 04:20 softlink.txt -> original.txt

--- Remove a soft link with rm / unlink (NOT rm on the trailing slash) ---
$ rm softlink.txt

$ unlink dirsoftlink

--- Remove a hard link: just rm it; data dies only when link count hits 0 ---
$ ls -li
total 12
24742 -rw-r--r-- 2 root root   62 Sep  3 04:20 hardlink.txt
24744 drwxr-xr-x 2 root root 4096 Sep  3 04:20 mydir
24742 -rw-r--r-- 2 root root   62 Sep  3 04:20 original.txt

$ rm hardlink.txt

$ ls -li
total 8
24744 drwxr-xr-x 2 root root 4096 Sep  3 04:20 mydir
24742 -rw-r--r-- 1 root root   62 Sep  3 04:20 original.txt

$ cat original.txt
Hello from the original file
Line added through the HARD link

--- Now delete the LAST hard link: the data is finally freed ---
$ rm original.txt

$ ls -li
total 4
24744 drwxr-xr-x 2 root root 4096 Sep  3 04:20 mydir

###############################################
# STEP 11: find broken symlinks / count hard links
###############################################
$ echo data > f1.txt; ln f1.txt f2.txt; ln f1.txt f3.txt

$ ls -li f1.txt f2.txt f3.txt
24742 -rw-r--r-- 3 root root 5 Sep  3 04:20 f1.txt
24742 -rw-r--r-- 3 root root 5 Sep  3 04:20 f2.txt
24742 -rw-r--r-- 3 root root 5 Sep  3 04:20 f3.txt

$ stat -c '%n has %h hard links (inode %i)' f1.txt
f1.txt has 3 hard links (inode 24742)

$ find . -type l -xtype l

$ ln -s /no/such/file broken.link

--- find dangling symlinks: ---
$ find . -xtype l
./broken.link
```

</details>

---

# Task 2 — `adduser` vs `useradd`

## What they actually are

```console
$ file /usr/sbin/adduser
/usr/sbin/adduser: Perl script text executable

$ file /usr/sbin/useradd
/usr/sbin/useradd: ELF 64-bit LSB pie executable, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-aarch64.so.1, BuildID[sha1]=483f79642f7a936acdeb2cb2fd1c4e70c2f0ef9d, for GNU/Linux 3.7.0, stripped
```

That single result explains the whole difference:

- **`useradd`** is the low-level binary from the `shadow` package. It exists on *every* Linux
  distribution and does exactly what you tell it — nothing more.
- **`adduser`** is a **Perl wrapper around `useradd`**, shipped by Debian/Ubuntu. It applies
  sensible policy from `/etc/adduser.conf`, asks interactive questions, and calls `useradd`
  (and `chfn`, `passwd`, `chpasswd`) underneath.

```console
$ cat /etc/os-release | head -3
PRETTY_NAME="Ubuntu 24.04.4 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"

$ which adduser useradd
/usr/sbin/adduser
/usr/sbin/useradd
```

## Which is preferred on Ubuntu, and why

**`adduser` is the recommended command on Ubuntu/Debian.** Reasons:

1. It **creates and populates the home directory** by copying `/etc/skel` — `useradd` does not,
   unless you remember `-m`.
2. It **sets a real login shell** (`/bin/bash`), where bare `useradd` leaves `/bin/sh`.
3. It **prompts for a password** and sets it. Bare `useradd` leaves the account *locked*.
4. It creates a matching **user private group** and adds the user to the configured extra groups.
5. It picks the UID/GID from the correct configured range.
6. It is **interactive and hard to get wrong** — the reason distro documentation points at it.

`useradd` is what you use in **scripts, Dockerfiles and non-Debian distros** (RHEL, Alpine and
Arch have no `adduser`, or a different one), because it is predictable and non-interactive.

## The evidence

### Bare `useradd` — a half-configured account

```console
$ useradd raw_user
$ grep raw_user /etc/passwd
raw_user:x:1001:1001::/home/raw_user:/bin/sh

$ grep raw_user /etc/shadow
raw_user:!:20699:0:99999:7:::
```

The `!` in the second field of `/etc/shadow` means the account is **locked** — no password was
set, so nobody can log in.

```console
$ test -d /home/raw_user && echo 'home exists' || echo 'NO HOME DIRECTORY for raw_user'
NO HOME DIRECTORY for raw_user

$ passwd -S raw_user
raw_user L 2026-09-03 0 99999 7 -1
```

`/etc/passwd` claims the home is `/home/raw_user`, but that directory **was never created**.
`passwd -S` reports `L` = locked.

### Making `useradd` behave requires flags

```console
$ useradd -m -s /bin/bash -c 'Manually Configured User' -G sudo flag_user
$ grep flag_user /etc/passwd
flag_user:x:1002:1002:Manually Configured User:/home/flag_user:/bin/bash

$ ls -la /home/flag_user
total 20
drwxr-x--- 2 flag_user flag_user 4096 Sep  3 04:26 .
drwxr-xr-x 1 root      root      4096 Sep  3 04:26 ..
-rw-r--r-- 1 flag_user flag_user  220 Mar 31  2024 .bash_logout
-rw-r--r-- 1 flag_user flag_user 3771 Mar 31  2024 .bashrc
-rw-r--r-- 1 flag_user flag_user  807 Mar 31  2024 .profile

$ passwd -S flag_user
flag_user L 2026-09-03 0 99999 7 -1
```

Better — but note it is *still* `L` (locked). You have to run `passwd flag_user` separately.

| Flag | Meaning |
|---|---|
| `-m` | create the home directory |
| `-s /bin/bash` | set the login shell |
| `-c "..."` | GECOS / comment field |
| `-G sudo` | supplementary groups |
| `-u 1500` | specific UID |
| `-g devs` | primary group |
| `-e 2026-12-31` | account expiry date |
| `-r` | system account |

### `adduser` — one command, correct result

Interactively you just type `sudo adduser testuser` and answer the prompts:
```
Adding user `testuser' ...
Adding new group `testuser' (1001) ...
Adding new user `testuser' (1001) with group `testuser' ...
Creating home directory `/home/testuser' ...
Copying files from `/etc/skel' ...
New password:
Retype new password:
Full Name []: Test User
Room Number []: 101
Work Phone []: 555-0100
Home Phone []: 555-0101
Other []: DevOps Homework
Is the information correct? [Y/n] Y
```

The transcript below uses the **scriptable** form of exactly the same thing, because a piped
stdin has no tty for `adduser`'s final confirmation prompt:

```console
$ adduser --gecos 'Test User,101,555-0100,555-0101,DevOps Homework' --disabled-password testuser
info: Adding user `testuser' ...
info: Selecting UID/GID from range 1000 to 59999 ...
info: Adding new group `testuser' (1003) ...
info: Adding new user `testuser' (1003) with group `testuser (1003)' ...
info: Creating home directory `/home/testuser' ...
info: Copying files from `/etc/skel' ...
info: Adding new user `testuser' to supplemental / extra groups `users' ...
info: Adding user `testuser' to group `users' ...

$ echo 'testuser:TestPass@123' | chpasswd
$ passwd -S testuser
testuser P 2026-09-03 0 99999 7 -1
```

`P` = a usable password is set. Compare with the `L` from both `useradd` runs.

### The required test user, verified

```console
$ grep testuser /etc/passwd
testuser:x:1003:1003:Test User,101,555-0100,555-0101,DevOps Homework:/home/testuser:/bin/bash

$ id testuser
uid=1003(testuser) gid=1003(testuser) groups=1003(testuser),100(users)

$ ls -la /home/testuser
total 20
drwxr-x--- 2 testuser testuser 4096 Sep  3 04:26 .
drwxr-xr-x 1 root     root     4096 Sep  3 04:26 ..
-rw-r--r-- 1 testuser testuser  220 Sep  3 04:26 .bash_logout
-rw-r--r-- 1 testuser testuser 3771 Sep  3 04:26 .bashrc
-rw-r--r-- 1 testuser testuser  807 Sep  3 04:26 .profile

$ ls -la /etc/skel
total 24
drwxr-xr-x 2 root root 4096 Aug 10 14:49 .
drwxr-xr-x 1 root root 4096 Sep  3 04:26 ..
-rw-r--r-- 1 root root  220 Mar 31  2024 .bash_logout
-rw-r--r-- 1 root root 3771 Mar 31  2024 .bashrc
-rw-r--r-- 1 root root  807 Mar 31  2024 .profile
```

Those three dotfiles in the home directory came from `/etc/skel` — `adduser` copied them
automatically. And the account genuinely works:

```console
$ su - testuser -c 'whoami; pwd; echo $SHELL; ls -a'
testuser
/home/testuser
/bin/bash
.
..
.bash_logout
.bashrc
.profile
```

### Side by side

```console
$ grep -E 'raw_user|flag_user|testuser' /etc/passwd
raw_user:x:1001:1001::/home/raw_user:/bin/sh
flag_user:x:1002:1002:Manually Configured User:/home/flag_user:/bin/bash
testuser:x:1003:1003:Test User,101,555-0100,555-0101,DevOps Homework:/home/testuser:/bin/bash

format: name:passwd:UID:GID:GECOS/comment:home:shell

$ for u in raw_user flag_user testuser; do printf '%-10s home=%-18s shell=%-10s\n' "$u" "$(getent passwd $u | cut -d: -f6)" "$(getent passwd $u | cut -d: -f7)"; done
raw_user   home=/home/raw_user     shell=/bin/sh   
flag_user  home=/home/flag_user    shell=/bin/bash 
testuser   home=/home/testuser     shell=/bin/bash 
```

The `/etc/passwd` format is
`name : password : UID : GID : GECOS/comment : home : shell`

| | `useradd raw_user` | `useradd -m -s ... flag_user` | `adduser testuser` |
|---|---|---|---|
| Home directory created | ✗ | ✓ | ✓ |
| `/etc/skel` copied | ✗ | ✓ | ✓ |
| Login shell | `/bin/sh` | `/bin/bash` | `/bin/bash` |
| Password set | ✗ (locked) | ✗ (locked) | ✓ |
| GECOS filled | ✗ | partly | ✓ |
| Commands needed | 1 (broken) | 2 (`useradd` + `passwd`) | **1** |

### `adduser` also manages group membership

```console
$ adduser testuser sudo
info: Adding user `testuser' to group `sudo' ...
$ groups testuser
testuser : testuser sudo users
```

## Summary table

| | `adduser` | `useradd` |
|---|---|---|
| Type | Perl wrapper script | compiled binary (`shadow`) |
| Level | high level, policy-aware | low level, does exactly what you say |
| Availability | Debian / Ubuntu | **every** Linux distribution |
| Interactive | yes, prompts | no |
| Home directory | automatic | only with `-m` |
| Password | prompts for one | separate `passwd` command |
| Reads `/etc/adduser.conf` | yes | no (uses `/etc/default/useradd`, `/etc/login.defs`) |
| Best for | humans on Ubuntu | scripts, Dockerfiles, other distros |
| Delete counterpart | `deluser` | `userdel` |

## Cleaning up

```console
$ deluser --remove-home raw_user
info: Looking for files to backup/remove ...
warn: `/usr/bin/crontab' not executed. Skipping crontab removal. Package `cron' required.
info: Removing user `raw_user' ...

$ userdel -r flag_user
userdel: flag_user mail spool (/var/mail/flag_user) not found

$ grep -E 'raw_user|flag_user' /etc/passwd || echo 'both removed'
both removed
```

> **Gotcha found while running this lab:** `deluser --remove-home` initially failed with
> `you need to install the 'perl' package` on a minimal Ubuntu image — the `perl-base` that
> ships by default is not the full Perl that `adduser`/`deluser` need for file handling.
> `userdel -r` works regardless, which is another reason scripts prefer the low-level tools.

## Related commands

```bash
adduser testuser sudo          # add an existing user to a group
deluser --remove-home testuser # delete user + home
userdel -r testuser            # low-level equivalent
passwd testuser                # set/change password
usermod -aG docker testuser    # append to a group (-a is essential, or you REPLACE groups)
chage -l testuser              # password ageing info
getent passwd testuser         # query via NSS rather than grepping the file
```

<details>
<summary><b>Full Task 2 transcript</b> (click to expand — all 8 steps)</summary>

```console
###############################################
# STEP 0: What ARE these two commands?
###############################################
$ cat /etc/os-release | head -3
PRETTY_NAME="Ubuntu 24.04.4 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"

$ which adduser useradd
/usr/sbin/adduser
/usr/sbin/useradd

$ file /usr/sbin/adduser
/usr/sbin/adduser: Perl script text executable

$ file /usr/sbin/useradd
/usr/sbin/useradd: ELF 64-bit LSB pie executable, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-aarch64.so.1, BuildID[sha1]=483f79642f7a936acdeb2cb2fd1c4e70c2f0ef9d, for GNU/Linux 3.7.0, stripped

--- adduser is a friendly Perl WRAPPER; useradd is the low-level C binary ---
$ head -20 /usr/sbin/adduser
#! /usr/bin/perl

# Copyright (C) 2000-2004 Roland Bauerschmidt <rb@debian.org>
#               2005-2023 Marc Haber <mh+debian-packages@zugschlus.de>
#               2022 Benjamin Drung <benjamin.drung@canonical.com>
#               2023 Guillem Jover <guillem@debian.org>
#               2021-2022 Jason Franklin <jason@oneway.dev>
#               2022 Matt Barry <matt@hazelmollusk.org>
#               2016-2017 Afif Elghraoui <afif@debian.org>
#               2016 Dr. Helge Kreutzmann <debian@helgefjell.de>
#               2005-2009 Joerg Hoh <joerg@joerghoh.de>
#               2006-2011 Stephen Gran <sgran@debian.org>
#
# Original adduser:
# Copyright (C) 1997-1999 Guy Maor <maor@debian.org>
#
# Copyright (C) 1995 Ted Hajek <tedhajek@boombox.micro.umn.edu>
#                    Ian A. Murdock <imurdock@gnu.ai.mit.edu>
#
# The general scheme of this program was adapted from the original

###############################################
# STEP 1: The LOW-LEVEL way -- useradd (bare minimum)
###############################################
$ useradd raw_user

$ grep raw_user /etc/passwd
raw_user:x:1001:1001::/home/raw_user:/bin/sh

$ grep raw_user /etc/shadow
raw_user:!:20699:0:99999:7:::

$ grep raw_user /etc/group
raw_user:x:1001:

--- Notice: NO home directory was created ---
$ ls -la /home
total 12
drwxr-xr-x 1 root   root   4096 Sep  3 04:25 .
drwxr-xr-x 1 root   root   4096 Sep  3 04:26 ..
drwxr-x--- 2 ubuntu ubuntu 4096 Aug 10 14:55 ubuntu

$ test -d /home/raw_user && echo 'home exists' || echo 'NO HOME DIRECTORY for raw_user'
NO HOME DIRECTORY for raw_user

--- Notice: login shell is /bin/sh (no shell set), and the account is LOCKED (! in shadow) ---
$ passwd -S raw_user
raw_user L 2026-09-03 0 99999 7 -1

###############################################
# STEP 2: Making useradd behave requires MANY flags
###############################################
$ useradd -m -s /bin/bash -c 'Manually Configured User' -G sudo flag_user

$ grep flag_user /etc/passwd
flag_user:x:1002:1002:Manually Configured User:/home/flag_user:/bin/bash

$ ls -la /home/flag_user
total 20
drwxr-x--- 2 flag_user flag_user 4096 Sep  3 04:26 .
drwxr-xr-x 1 root      root      4096 Sep  3 04:26 ..
-rw-r--r-- 1 flag_user flag_user  220 Mar 31  2024 .bash_logout
-rw-r--r-- 1 flag_user flag_user 3771 Mar 31  2024 .bashrc
-rw-r--r-- 1 flag_user flag_user  807 Mar 31  2024 .profile

$ groups flag_user
flag_user : flag_user sudo

$ passwd -S flag_user
flag_user L 2026-09-03 0 99999 7 -1

###############################################
# STEP 3: The RECOMMENDED way on Ubuntu/Debian -- adduser
###############################################
--- Interactively you would simply type:  sudo adduser testuser
    and answer its prompts:
    Adding user `testuser' ...
    Adding new group `testuser' (1001) ...
    Adding new user `testuser' (1001) with group `testuser' ...
    Creating home directory `/home/testuser' ...
    Copying files from `/etc/skel' ...
    New password:
    Retype new password:
    Full Name []: Test User
    Room Number []: 101
    Work Phone []: 555-0100
    Home Phone []: 555-0101
    Other []: DevOps Homework
    Is the information correct? [Y/n] Y

--- Same thing, run non-interactively (scriptable form): ---
$ adduser --gecos 'Test User,101,555-0100,555-0101,DevOps Homework' --disabled-password testuser
info: Adding user `testuser' ...
info: Selecting UID/GID from range 1000 to 59999 ...
info: Adding new group `testuser' (1003) ...
info: Adding new user `testuser' (1003) with group `testuser (1003)' ...
info: Creating home directory `/home/testuser' ...
info: Copying files from `/etc/skel' ...
info: Adding new user `testuser' to supplemental / extra groups `users' ...
info: Adding user `testuser' to group `users' ...

$ echo 'testuser:TestPass@123' | chpasswd

$ passwd -S testuser
testuser P 2026-09-03 0 99999 7 -1


$ grep testuser /etc/passwd
testuser:x:1003:1003:Test User,101,555-0100,555-0101,DevOps Homework:/home/testuser:/bin/bash

$ grep testuser /etc/group
users:x:100:testuser
testuser:x:1003:

$ passwd -S testuser
testuser P 2026-09-03 0 99999 7 -1

--- adduser DID create and populate the home directory automatically: ---
$ ls -la /home/testuser
total 20
drwxr-x--- 2 testuser testuser 4096 Sep  3 04:26 .
drwxr-xr-x 1 root     root     4096 Sep  3 04:26 ..
-rw-r--r-- 1 testuser testuser  220 Sep  3 04:26 .bash_logout
-rw-r--r-- 1 testuser testuser 3771 Sep  3 04:26 .bashrc
-rw-r--r-- 1 testuser testuser  807 Sep  3 04:26 .profile

--- ...by copying the skeleton directory /etc/skel: ---
$ ls -la /etc/skel
total 24
drwxr-xr-x 2 root root 4096 Aug 10 14:49 .
drwxr-xr-x 1 root root 4096 Sep  3 04:26 ..
-rw-r--r-- 1 root root  220 Mar 31  2024 .bash_logout
-rw-r--r-- 1 root root 3771 Mar 31  2024 .bashrc
-rw-r--r-- 1 root root  807 Mar 31  2024 .profile

--- ...and it created a matching USER PRIVATE GROUP: ---
$ id testuser
uid=1003(testuser) gid=1003(testuser) groups=1003(testuser),100(users)

###############################################
# STEP 4: Side-by-side comparison of the 3 accounts
###############################################
$ grep -E 'raw_user|flag_user|testuser' /etc/passwd
raw_user:x:1001:1001::/home/raw_user:/bin/sh
flag_user:x:1002:1002:Manually Configured User:/home/flag_user:/bin/bash
testuser:x:1003:1003:Test User,101,555-0100,555-0101,DevOps Homework:/home/testuser:/bin/bash

format: name:passwd:UID:GID:GECOS/comment:home:shell

$ for u in raw_user flag_user testuser; do printf '%-10s home=%-18s shell=%-10s\n' "$u" "$(getent passwd $u | cut -d: -f6)" "$(getent passwd $u | cut -d: -f7)"; done
raw_user   home=/home/raw_user     shell=/bin/sh   
flag_user  home=/home/flag_user    shell=/bin/bash 
testuser   home=/home/testuser     shell=/bin/bash 

###############################################
# STEP 5: Prove the recommended user actually works
###############################################
$ su - testuser -c 'whoami; pwd; echo $SHELL; ls -a'
testuser
/home/testuser
/bin/bash
.
..
.bash_logout
.bashrc
.profile

###############################################
# STEP 6: adduser also manages groups & sudo access
###############################################
$ adduser testuser sudo
info: Adding user `testuser' to group `sudo' ...

$ groups testuser
testuser : testuser sudo users

###############################################
# STEP 7: Config file that adduser reads (useradd ignores it)
###############################################
$ grep -vE '^#|^$' /etc/adduser.conf

###############################################
# STEP 8: Deleting users
###############################################
$ deluser --remove-home raw_user
info: Looking for files to backup/remove ...
warn: `/usr/bin/crontab' not executed. Skipping crontab removal. Package `cron' required.
info: Removing user `raw_user' ...

$ userdel -r flag_user
userdel: flag_user mail spool (/var/mail/flag_user) not found

$ grep -E 'raw_user|flag_user' /etc/passwd || echo 'both removed'
both removed

--- keeping testuser as the required deliverable ---
$ getent passwd testuser
testuser:x:1003:1003:Test User,101,555-0100,555-0101,DevOps Homework:/home/testuser:/bin/bash
```

</details>

---

# Task 3 — `journalctl`

## What it is used for

`systemd-journald` collects log messages from the kernel, from early boot, from every service
`systemd` starts (their stdout/stderr), and from applications that call `syslog()`. It stores
them in an **indexed binary format** with structured metadata attached to each entry.

`journalctl` is the tool you use to **query** that database. You cannot `cat` the journal —
it is not plain text — which is exactly what makes it fast to filter by service, time,
priority or boot.

```console
$ systemctl status systemd-journald --no-pager | head -12
● systemd-journald.service - Journal Service
     Loaded: loaded (/usr/lib/systemd/system/systemd-journald.service; static)
    Drop-In: /usr/lib/systemd/system/systemd-journald.service.d
             └─nice.conf
     Active: active (running) since Thu 2026-09-03 04:19:48 UTC; 6min ago
TriggeredBy: ○ systemd-journald-audit.socket
             ● systemd-journald.socket
             ● systemd-journald-dev-log.socket
       Docs: man:systemd-journald.service(8)
             man:journald.conf(5)
   Main PID: 23 (systemd-journal)
     Status: "Processing requests..."

$ ls -la /var/log/journal/ 2>/dev/null || ls -la /run/log/journal/
total 20
drwxr-sr-x+ 1 root systemd-journal 4096 Sep  3 04:19 .
drwxr-xr-x  1 root root            4096 Sep  3 04:19 ..
drwxr-sr-x+ 2 root systemd-journal 4096 Sep  3 04:19 34c36af29c1e4f109f8240a2fdc99503
```

**Persistent vs volatile:** logs in `/var/log/journal/` survive reboots; logs in
`/run/log/journal/` are in tmpfs and vanish. Persistence is enabled with
`Storage=persistent` in `/etc/systemd/journald.conf`.

## The commands that matter

### Viewing

| Command | What it does |
|---|---|
| `journalctl` | everything, oldest first, in a pager |
| `journalctl -n 20` | last 20 entries |
| `journalctl -r` | reverse — newest first |
| `journalctl -e` | jump straight to the end |
| `journalctl -f` | **follow live**, like `tail -f` |
| `journalctl -x` | add explanatory help text to messages |
| `journalctl --no-pager` | plain output, for scripts and pipes |

```console
$ journalctl -n 10 --no-pager
Sep 03 04:26:06 ff4c4be986b8 deluser[1013]: `/usr/bin/crontab' not executed. Skipping crontab removal. Package `cron' required.
Sep 03 04:26:06 ff4c4be986b8 deluser[1013]: Removing user `raw_user' ...
Sep 03 04:26:06 ff4c4be986b8 userdel[1017]: delete user 'raw_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1017]: removed group 'raw_user' owned by 'raw_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1017]: removed shadow group 'raw_user' owned by 'raw_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: delete user 'flag_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: delete 'flag_user' from group 'sudo'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: removed group 'flag_user' owned by 'flag_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: removed shadow group 'flag_user' owned by 'flag_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: delete 'flag_user' from shadow group 'sudo'

$ journalctl -r -n 5 --no-pager
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: delete 'flag_user' from shadow group 'sudo'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: removed shadow group 'flag_user' owned by 'flag_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: removed group 'flag_user' owned by 'flag_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: delete 'flag_user' from group 'sudo'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: delete user 'flag_user'
```

### Filtering by service — the one you will use daily

```console
$ systemctl status nginx --no-pager | head -12
● nginx.service - A high performance web server and a reverse proxy server
     Loaded: loaded (/usr/lib/systemd/system/nginx.service; enabled; preset: enabled)
     Active: active (running) since Thu 2026-09-03 04:19:48 UTC; 6min ago
       Docs: man:nginx(8)
    Process: 73 ExecStartPre=/usr/sbin/nginx -t -q -g daemon on; master_process on; (code=exited, status=0/SUCCESS)
    Process: 78 ExecStart=/usr/sbin/nginx -g daemon on; master_process on; (code=exited, status=0/SUCCESS)
   Main PID: 81 (nginx)
      Tasks: 9 (limit: 4742)
     Memory: 5.4M (peak: 6.2M)
        CPU: 22ms
     CGroup: /docker/ff4c4be986b899c0c185ef292b8cb93cf30c8f3c0686698330d96955b1b68228/system.slice/nginx.service
             ├─81 "nginx: master process /usr/sbin/nginx -g daemon on; master_process on;"

$ journalctl -u nginx --no-pager
Sep 03 04:19:48 ff4c4be986b8 systemd[1]: Starting nginx.service - A high performance web server and a reverse proxy server...
Sep 03 04:19:48 ff4c4be986b8 systemd[1]: Started nginx.service - A high performance web server and a reverse proxy server.
```

After a `systemctl restart nginx`, the stop/start pair appears — this is how you confirm a
service actually restarted, and exactly when:

```console
$ journalctl -u nginx --no-pager -n 15
Sep 03 04:19:48 ff4c4be986b8 systemd[1]: Starting nginx.service - A high performance web server and a reverse proxy server...
Sep 03 04:19:48 ff4c4be986b8 systemd[1]: Started nginx.service - A high performance web server and a reverse proxy server.
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Stopping nginx.service - A high performance web server and a reverse proxy server...
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: nginx.service: Deactivated successfully.
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Stopped nginx.service - A high performance web server and a reverse proxy server.
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Starting nginx.service - A high performance web server and a reverse proxy server...
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Started nginx.service - A high performance web server and a reverse proxy server.
```

| Command | What it does |
|---|---|
| `journalctl -u nginx` | all logs for one unit |
| `journalctl -u nginx -f` | follow one service live |
| `journalctl -u nginx -n 50` | last 50 lines for that service |
| `journalctl -u nginx -u ssh` | two services at once |
| `journalctl -u nginx --since today` | combine filters |

### Filtering by time

```bash
journalctl --since "10 minutes ago"
journalctl --since today
journalctl --since yesterday --until "03:00"
journalctl --since "2026-09-03 04:00:00" --until "2026-09-03 05:00:00"
```

```console
$ journalctl --since today --no-pager | wc -l
826

$ journalctl --since '2026-01-01' --until 'now' --no-pager | wc -l
826
```

### Filtering by priority
```
0 emerg   1 alert   2 crit   3 err   4 warning   5 notice   6 info   7 debug
```

```bash
journalctl -p err              # errors and MORE severe (0-3)
journalctl -p warning..err     # a range
journalctl -p 3 -xb            # errors since this boot, with explanations
```

### Filtering by boot

```console
$ journalctl --list-boots --no-pager
IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY
  0 3403a99c68564371b9fb72c149337f7a Thu 2026-09-03 04:19:48 UTC Thu 2026-09-03 04:26:38 UTC
```

`journalctl -b` = this boot. `journalctl -b -1` = the **previous** boot — the single most useful
flag when a machine crashed and you need to know why. (This container has only ever booted once,
hence the single entry.)

### Structured field filters

Because the journal is structured, you can filter on metadata rather than grepping text:

```console
$ journalctl _PID=1 --no-pager -n 5
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Stopping nginx.service - A high performance web server and a reverse proxy server...
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: nginx.service: Deactivated successfully.
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Stopped nginx.service - A high performance web server and a reverse proxy server.
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Starting nginx.service - A high performance web server and a reverse proxy server...
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Started nginx.service - A high performance web server and a reverse proxy server.

$ journalctl /usr/sbin/nginx --no-pager -n 5

$ journalctl -k --no-pager -n 5
Sep 03 04:19:48 ff4c4be986b8 kernel: eth0: renamed from vetha74d1df
Sep 03 04:19:48 ff4c4be986b8 kernel: docker0: port 1(veth5f80646) entered blocking state
Sep 03 04:19:48 ff4c4be986b8 kernel: docker0: port 1(veth5f80646) entered forwarding state
Sep 03 04:19:48 ff4c4be986b8 systemd-journald[23]: Collecting audit messages is disabled.
Sep 03 04:19:48 ff4c4be986b8 systemd-journald[23]: Received client request to flush runtime journal.
```

| Filter | Meaning |
|---|---|
| `_PID=1` | by process ID |
| `_UID=1000` | by user ID |
| `/usr/sbin/nginx` | by executable path |
| `-t tag` | by syslog identifier |
| `-k` | kernel messages only (equivalent to `dmesg`) |

Writing your own entry and reading it straight back:

```console
$ logger -t devops-homework -p user.notice 'Hello from the DevOps homework, written via logger'
$ journalctl -t devops-homework --no-pager
Sep 03 04:26:38 ff4c4be986b8 devops-homework[1090]: Hello from the DevOps homework, written via logger
```

### Output formats

```console
$ journalctl -u nginx -o cat --no-pager -n 3
Stopped nginx.service - A high performance web server and a reverse proxy server.
Starting nginx.service - A high performance web server and a reverse proxy server...
Started nginx.service - A high performance web server and a reverse proxy server.

$ journalctl -u nginx -o verbose --no-pager -n 1
Thu 2026-09-03 04:26:38.076258 UTC [s=2e741be98f9c405d9b6160539dfc87ed;i=596;b=3403a99c68564371b9fb72c149337f7a;m=56ea58ca1d;t=65a8c8ece6584;x=e899bfa4c1e147b6]
    PRIORITY=6
    _BOOT_ID=3403a99c68564371b9fb72c149337f7a
    _MACHINE_ID=34c36af29c1e4f109f8240a2fdc99503
    _HOSTNAME=ff4c4be986b8
    _RUNTIME_SCOPE=system
    _UID=0
    _GID=0
    SYSLOG_FACILITY=3
    _TRANSPORT=journal
    TID=1
    CODE_FILE=src/core/job.c
    SYSLOG_IDENTIFIER=systemd
    JOB_TYPE=start
    _PID=1
    _COMM=systemd
    _EXE=/usr/lib/systemd/systemd
    _CMDLINE=/sbin/init
    _CAP_EFFECTIVE=1ffffffffff
    _SYSTEMD_CGROUP=/init.scope
    _SYSTEMD_UNIT=init.scope
    _SYSTEMD_SLICE=-.slice
    CODE_LINE=796
    CODE_FUNC=job_emit_done_message
    JOB_RESULT=done
    MESSAGE_ID=39f53479d3a045ac8e11786248231fbf
    UNIT=nginx.service
    MESSAGE=Started nginx.service - A high performance web server and a reverse proxy server.
    JOB_ID=150
    INVOCATION_ID=90e7407c7a3e4c22b2096ab51fcf2bd8
    _SOURCE_REALTIME_TIMESTAMP=1788409598076258
```

The `verbose` format shows every structured field attached to the entry — which is what makes
the field filters above possible.

| Format | Use |
|---|---|
| `-o short` | default, syslog-like |
| `-o cat` | message text only — good for piping |
| `-o verbose` | every structured field |
| `-o json` / `-o json-pretty` | machine-readable, for log shipping |

### Disk usage and cleanup

```console
$ journalctl --disk-usage
Archived and active journals take up 8.0M in the file system.

$ journalctl --verify 2>&1 | tail -3
PASS: /var/log/journal/34c36af29c1e4f109f8240a2fdc99503/system.journal

--- cleanup commands (destructive, shown here for reference): ---
    journalctl --vacuum-size=100M    # keep at most 100 MB
    journalctl --vacuum-time=7d      # keep only the last 7 days
    journalctl --rotate              # force rotation right now

$ journalctl --vacuum-time=2d
Vacuuming done, freed 0B of archived journals from /run/log/journal.
Vacuuming done, freed 0B of archived journals from /var/log/journal/34c36af29c1e4f109f8240a2fdc99503.
Vacuuming done, freed 0B of archived journals from /var/log/journal.
```

| Command | Effect |
|---|---|
| `journalctl --disk-usage` | how much space the journal uses |
| `journalctl --vacuum-size=100M` | keep at most 100 MB |
| `journalctl --vacuum-time=7d` | keep only the last 7 days |
| `journalctl --rotate` | force rotation now |
| `journalctl --verify` | check the files for corruption |

Long-term limits belong in `/etc/systemd/journald.conf` (`SystemMaxUse=`, `MaxRetentionSec=`).

## Practical recipes

```bash
# Why did my service fail?
journalctl -u myapp.service -n 50 --no-pager -p err

# Watch a deployment live
journalctl -u myapp.service -f

# What broke during last night's crash?
journalctl -b -1 -p err

# Everything the kernel said about disks this boot
journalctl -kb | grep -i sda

# Feed logs into another tool
journalctl -u myapp -o json --since "1 hour ago" | jq .
```

<details>
<summary><b>Full Task 3 transcript</b> (click to expand — all 9 steps)</summary>

```console
###############################################
# STEP 0: What is journalctl?
###############################################
$ systemctl --version | head -1
systemd 255 (255.4-1ubuntu8.17)

$ systemctl status systemd-journald --no-pager | head -12
● systemd-journald.service - Journal Service
     Loaded: loaded (/usr/lib/systemd/system/systemd-journald.service; static)
    Drop-In: /usr/lib/systemd/system/systemd-journald.service.d
             └─nice.conf
     Active: active (running) since Thu 2026-09-03 04:19:48 UTC; 6min ago
TriggeredBy: ○ systemd-journald-audit.socket
             ● systemd-journald.socket
             ● systemd-journald-dev-log.socket
       Docs: man:systemd-journald.service(8)
             man:journald.conf(5)
   Main PID: 23 (systemd-journal)
     Status: "Processing requests..."

--- The journal is a BINARY log database written by systemd-journald. ---
--- journalctl is the tool used to QUERY it.  Files live here: ---
$ ls -la /var/log/journal/ 2>/dev/null || ls -la /run/log/journal/
total 20
drwxr-sr-x+ 1 root systemd-journal 4096 Sep  3 04:19 .
drwxr-xr-x  1 root root            4096 Sep  3 04:19 ..
drwxr-sr-x+ 2 root systemd-journal 4096 Sep  3 04:19 34c36af29c1e4f109f8240a2fdc99503

###############################################
# STEP 1: View ALL logs (newest at the bottom)
###############################################
$ journalctl --no-pager | head -20
Sep 03 04:19:48 ff4c4be986b8 kernel: Booting Linux on physical CPU 0x0000000000 [0x610f0000]
Sep 03 04:19:48 ff4c4be986b8 kernel: Linux version 7.0.12-linuxkit (root@buildkitsandbox) (gcc (Alpine 15.2.0) 15.2.0, GNU ld (GNU Binutils) 2.45.1) #1 SMP PREEMPT Wed Aug 12 20:18:49 UTC 2026 ()
Sep 03 04:19:48 ff4c4be986b8 kernel: OF: reserved mem: Reserved memory: No reserved-memory node in the DT
Sep 03 04:19:48 ff4c4be986b8 kernel: psci: probing for conduit method from DT.
Sep 03 04:19:48 ff4c4be986b8 kernel: psci: PSCIv1.1 detected in firmware.
Sep 03 04:19:48 ff4c4be986b8 kernel: psci: Using standard PSCI v0.2 function IDs
Sep 03 04:19:48 ff4c4be986b8 kernel: psci: Trusted OS migration not required
Sep 03 04:19:48 ff4c4be986b8 kernel: psci: SMC Calling Convention v1.1
Sep 03 04:19:48 ff4c4be986b8 kernel: Zone ranges:
Sep 03 04:19:48 ff4c4be986b8 kernel:   DMA      [mem 0x0000000070000000-0x00000000ffffffff]
Sep 03 04:19:48 ff4c4be986b8 kernel:   DMA32    empty
Sep 03 04:19:48 ff4c4be986b8 kernel:   Normal   [mem 0x0000000100000000-0x000000016fffffff]
Sep 03 04:19:48 ff4c4be986b8 kernel: Movable zone start for each node
Sep 03 04:19:48 ff4c4be986b8 kernel: Early memory node ranges
Sep 03 04:19:48 ff4c4be986b8 kernel:   node   0: [mem 0x0000000070000000-0x000000016fffffff]
Sep 03 04:19:48 ff4c4be986b8 kernel: Initmem setup node 0 [mem 0x0000000070000000-0x000000016fffffff]
Sep 03 04:19:48 ff4c4be986b8 kernel: percpu: Embedded 32 pages/cpu s90648 r8192 d32232 u131072
Sep 03 04:19:48 ff4c4be986b8 kernel: pcpu-alloc: s90648 r8192 d32232 u131072 alloc=32*4096
Sep 03 04:19:48 ff4c4be986b8 kernel: pcpu-alloc: [0] 0 [0] 1 [0] 2 [0] 3 [0] 4 [0] 5 [0] 6 [0] 7 
Sep 03 04:19:48 ff4c4be986b8 kernel: Detected PIPT I-cache on CPU0

###############################################
# STEP 2: Most useful flags
###############################################
--- -n N : last N lines ---
$ journalctl -n 10 --no-pager
Sep 03 04:26:06 ff4c4be986b8 deluser[1013]: `/usr/bin/crontab' not executed. Skipping crontab removal. Package `cron' required.
Sep 03 04:26:06 ff4c4be986b8 deluser[1013]: Removing user `raw_user' ...
Sep 03 04:26:06 ff4c4be986b8 userdel[1017]: delete user 'raw_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1017]: removed group 'raw_user' owned by 'raw_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1017]: removed shadow group 'raw_user' owned by 'raw_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: delete user 'flag_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: delete 'flag_user' from group 'sudo'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: removed group 'flag_user' owned by 'flag_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: removed shadow group 'flag_user' owned by 'flag_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: delete 'flag_user' from shadow group 'sudo'

--- -r : reverse (newest first) ---
$ journalctl -r -n 5 --no-pager
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: delete 'flag_user' from shadow group 'sudo'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: removed shadow group 'flag_user' owned by 'flag_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: removed group 'flag_user' owned by 'flag_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: delete 'flag_user' from group 'sudo'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: delete user 'flag_user'

--- -e : jump to the end   |   -f : follow live (like tail -f) ---
--- -x : add explanatory help text to messages ---
$ journalctl -xn 5 --no-pager
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: delete user 'flag_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: delete 'flag_user' from group 'sudo'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: removed group 'flag_user' owned by 'flag_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: removed shadow group 'flag_user' owned by 'flag_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: delete 'flag_user' from shadow group 'sudo'

###############################################
# STEP 3: Logs for a SPECIFIC SERVICE  (-u)
###############################################
$ systemctl start nginx

$ systemctl status nginx --no-pager | head -12
● nginx.service - A high performance web server and a reverse proxy server
     Loaded: loaded (/usr/lib/systemd/system/nginx.service; enabled; preset: enabled)
     Active: active (running) since Thu 2026-09-03 04:19:48 UTC; 6min ago
       Docs: man:nginx(8)
    Process: 73 ExecStartPre=/usr/sbin/nginx -t -q -g daemon on; master_process on; (code=exited, status=0/SUCCESS)
    Process: 78 ExecStart=/usr/sbin/nginx -g daemon on; master_process on; (code=exited, status=0/SUCCESS)
   Main PID: 81 (nginx)
      Tasks: 9 (limit: 4742)
     Memory: 5.4M (peak: 6.2M)
        CPU: 22ms
     CGroup: /docker/ff4c4be986b899c0c185ef292b8cb93cf30c8f3c0686698330d96955b1b68228/system.slice/nginx.service
             ├─81 "nginx: master process /usr/sbin/nginx -g daemon on; master_process on;"

--- THE key command: journalctl -u <service> ---
$ journalctl -u nginx --no-pager
Sep 03 04:19:48 ff4c4be986b8 systemd[1]: Starting nginx.service - A high performance web server and a reverse proxy server...
Sep 03 04:19:48 ff4c4be986b8 systemd[1]: Started nginx.service - A high performance web server and a reverse proxy server.

--- restart the service and watch new entries appear ---
$ systemctl restart nginx

$ journalctl -u nginx --no-pager -n 15
Sep 03 04:19:48 ff4c4be986b8 systemd[1]: Starting nginx.service - A high performance web server and a reverse proxy server...
Sep 03 04:19:48 ff4c4be986b8 systemd[1]: Started nginx.service - A high performance web server and a reverse proxy server.
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Stopping nginx.service - A high performance web server and a reverse proxy server...
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: nginx.service: Deactivated successfully.
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Stopped nginx.service - A high performance web server and a reverse proxy server.
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Starting nginx.service - A high performance web server and a reverse proxy server...
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Started nginx.service - A high performance web server and a reverse proxy server.

###############################################
# STEP 4: Filter by TIME
###############################################
$ journalctl --since '10 minutes ago' --no-pager | tail -8
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: removed group 'flag_user' owned by 'flag_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: removed shadow group 'flag_user' owned by 'flag_user'
Sep 03 04:26:06 ff4c4be986b8 userdel[1025]: delete 'flag_user' from shadow group 'sudo'
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Stopping nginx.service - A high performance web server and a reverse proxy server...
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: nginx.service: Deactivated successfully.
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Stopped nginx.service - A high performance web server and a reverse proxy server.
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Starting nginx.service - A high performance web server and a reverse proxy server...
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Started nginx.service - A high performance web server and a reverse proxy server.

$ journalctl --since today --no-pager | wc -l
826

$ journalctl --since '2026-01-01' --until 'now' --no-pager | wc -l
826

--- also accepts: yesterday, '1 hour ago', '2026-09-03 04:00:00' ---
###############################################
# STEP 5: Filter by PRIORITY  (-p)
###############################################
levels: 0 emerg  1 alert  2 crit  3 err  4 warning  5 notice  6 info  7 debug
$ journalctl -p err --no-pager -n 10
Sep 03 04:20:59 ff4c4be986b8 deluser[282]: In order to use the --remove-home, --remove-all-files, and --backup features, you need to install the `perl' package. To accomplish that, run apt-get install perl.
Sep 03 04:21:26 ff4c4be986b8 deluser[300]: In order to use the --remove-home, --remove-all-files, and --backup features, you need to install the `perl' package. To accomplish that, run apt-get install perl.
Sep 03 04:21:26 ff4c4be986b8 adduser[309]: The user `testuser' already exists.
Sep 03 04:21:33 ff4c4be986b8 deluser[327]: In order to use the --remove-home, --remove-all-files, and --backup features, you need to install the `perl' package. To accomplish that, run apt-get install perl.
Sep 03 04:25:50 ff4c4be986b8 adduser[805]: Caught a SIG%s.
Sep 03 04:25:50 ff4c4be986b8 adduser[805]: `groupdel testuser' returned error code 6. Exiting.

$ journalctl -p warning..err --no-pager -n 10
Sep 03 04:19:48 ff4c4be986b8 kernel: pci-host-generic 40000000.pci: Memory resource size exceeds max for 32 bits
Sep 03 04:19:48 ff4c4be986b8 kernel: PFKEY is deprecated and scheduled to be removed in 2027, please contact the netdev mailing list
Sep 03 04:19:48 ff4c4be986b8 kernel: netlink: 'initd': attribute type 4 has an invalid length.
Sep 03 04:19:48 ff4c4be986b8 kernel: fakeowner: loading out-of-tree module taints kernel.
Sep 03 04:19:48 ff4c4be986b8 kernel: NOTICE: Automounting of tracing to debugfs is deprecated and will be removed in 2030
Sep 03 04:19:48 ff4c4be986b8 kernel: hrtimer: interrupt took 5203209 ns
Sep 03 04:19:48 ff4c4be986b8 systemd-sysctl[31]: Couldn't write '1' to 'kernel/yama/ptrace_scope', ignoring: No such file or directory
Sep 03 04:23:13 ff4c4be986b8 deluser[705]: `/usr/bin/crontab' not executed. Skipping crontab removal. Package `cron' required.
Sep 03 04:25:50 ff4c4be986b8 adduser[805]: Caught a SIG%s.
Sep 03 04:26:06 ff4c4be986b8 deluser[1013]: `/usr/bin/crontab' not executed. Skipping crontab removal. Package `cron' required.

###############################################
# STEP 6: Filter by BOOT, by PID, by USER, by EXECUTABLE
###############################################
$ journalctl --list-boots --no-pager
IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY
  0 3403a99c68564371b9fb72c149337f7a Thu 2026-09-03 04:19:48 UTC Thu 2026-09-03 04:26:38 UTC

$ journalctl -b --no-pager | head -5
Sep 03 04:19:48 ff4c4be986b8 kernel: Booting Linux on physical CPU 0x0000000000 [0x610f0000]
Sep 03 04:19:48 ff4c4be986b8 kernel: Linux version 7.0.12-linuxkit (root@buildkitsandbox) (gcc (Alpine 15.2.0) 15.2.0, GNU ld (GNU Binutils) 2.45.1) #1 SMP PREEMPT Wed Aug 12 20:18:49 UTC 2026 ()
Sep 03 04:19:48 ff4c4be986b8 kernel: OF: reserved mem: Reserved memory: No reserved-memory node in the DT
Sep 03 04:19:48 ff4c4be986b8 kernel: psci: probing for conduit method from DT.
Sep 03 04:19:48 ff4c4be986b8 kernel: psci: PSCIv1.1 detected in firmware.

--- -b -1 would show the PREVIOUS boot ---
$ journalctl _PID=1 --no-pager -n 5
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Stopping nginx.service - A high performance web server and a reverse proxy server...
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: nginx.service: Deactivated successfully.
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Stopped nginx.service - A high performance web server and a reverse proxy server.
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Starting nginx.service - A high performance web server and a reverse proxy server...
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Started nginx.service - A high performance web server and a reverse proxy server.

$ journalctl /usr/sbin/nginx --no-pager -n 5
-- No entries --

$ journalctl -u nginx -o json-pretty --no-pager -n 1
{
	"JOB_RESULT" : "done",
	"_BOOT_ID" : "3403a99c68564371b9fb72c149337f7a",
	"TID" : "1",
	"_SYSTEMD_CGROUP" : "/init.scope",
	"CODE_FUNC" : "job_emit_done_message",
	"UNIT" : "nginx.service",
	"_UID" : "0",
	"_GID" : "0",
	"_RUNTIME_SCOPE" : "system",
	"CODE_FILE" : "src/core/job.c",
	"_PID" : "1",
	"_SOURCE_REALTIME_TIMESTAMP" : "1788409598076258",
	"__SEQNUM" : "1430",
	"__CURSOR" : "s=2e741be98f9c405d9b6160539dfc87ed;i=596;b=3403a99c68564371b9fb72c149337f7a;m=56ea58ca1d;t=65a8c8ece6584;x=e899bfa4c1e147b6",
	"_CAP_EFFECTIVE" : "1ffffffffff",
	"__SEQNUM_ID" : "2e741be98f9c405d9b6160539dfc87ed",
	"MESSAGE" : "Started nginx.service - A high performance web server and a reverse proxy server.",
	"SYSLOG_IDENTIFIER" : "systemd",
	"_COMM" : "systemd",
	"_SYSTEMD_SLICE" : "-.slice",
	"_TRANSPORT" : "journal",
	"_MACHINE_ID" : "34c36af29c1e4f109f8240a2fdc99503",
	"PRIORITY" : "6",
	"MESSAGE_ID" : "39f53479d3a045ac8e11786248231fbf",
	"_SYSTEMD_UNIT" : "init.scope",
	"CODE_LINE" : "796",
	"__REALTIME_TIMESTAMP" : "1788409598076292",
	"SYSLOG_FACILITY" : "3",
	"_CMDLINE" : "/sbin/init",
	"INVOCATION_ID" : "90e7407c7a3e4c22b2096ab51fcf2bd8",
	"__MONOTONIC_TIMESTAMP" : "373298874909",
	"_HOSTNAME" : "ff4c4be986b8",
	"JOB_ID" : "150",
	"_EXE" : "/usr/lib/systemd/systemd",
	"JOB_TYPE" : "start"
}

###############################################
# STEP 7: Output formats  (-o)
###############################################
$ journalctl -u nginx -o short --no-pager -n 2
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Starting nginx.service - A high performance web server and a reverse proxy server...
Sep 03 04:26:38 ff4c4be986b8 systemd[1]: Started nginx.service - A high performance web server and a reverse proxy server.

$ journalctl -u nginx -o cat --no-pager -n 3
Stopped nginx.service - A high performance web server and a reverse proxy server.
Starting nginx.service - A high performance web server and a reverse proxy server...
Started nginx.service - A high performance web server and a reverse proxy server.

$ journalctl -u nginx -o verbose --no-pager -n 1
Thu 2026-09-03 04:26:38.076258 UTC [s=2e741be98f9c405d9b6160539dfc87ed;i=596;b=3403a99c68564371b9fb72c149337f7a;m=56ea58ca1d;t=65a8c8ece6584;x=e899bfa4c1e147b6]
    PRIORITY=6
    _BOOT_ID=3403a99c68564371b9fb72c149337f7a
    _MACHINE_ID=34c36af29c1e4f109f8240a2fdc99503
    _HOSTNAME=ff4c4be986b8
    _RUNTIME_SCOPE=system
    _UID=0
    _GID=0
    SYSLOG_FACILITY=3
    _TRANSPORT=journal
    TID=1
    CODE_FILE=src/core/job.c
    SYSLOG_IDENTIFIER=systemd
    JOB_TYPE=start
    _PID=1
    _COMM=systemd
    _EXE=/usr/lib/systemd/systemd
    _CMDLINE=/sbin/init
    _CAP_EFFECTIVE=1ffffffffff
    _SYSTEMD_CGROUP=/init.scope
    _SYSTEMD_UNIT=init.scope
    _SYSTEMD_SLICE=-.slice
    CODE_LINE=796
    CODE_FUNC=job_emit_done_message
    JOB_RESULT=done
    MESSAGE_ID=39f53479d3a045ac8e11786248231fbf
    UNIT=nginx.service
    MESSAGE=Started nginx.service - A high performance web server and a reverse proxy server.
    JOB_ID=150
    INVOCATION_ID=90e7407c7a3e4c22b2096ab51fcf2bd8
    _SOURCE_REALTIME_TIMESTAMP=1788409598076258

###############################################
# STEP 8: Kernel messages, and writing your own entry
###############################################
$ journalctl -k --no-pager -n 5
Sep 03 04:19:48 ff4c4be986b8 kernel: eth0: renamed from vetha74d1df
Sep 03 04:19:48 ff4c4be986b8 kernel: docker0: port 1(veth5f80646) entered blocking state
Sep 03 04:19:48 ff4c4be986b8 kernel: docker0: port 1(veth5f80646) entered forwarding state
Sep 03 04:19:48 ff4c4be986b8 systemd-journald[23]: Collecting audit messages is disabled.
Sep 03 04:19:48 ff4c4be986b8 systemd-journald[23]: Received client request to flush runtime journal.

$ logger -t devops-homework -p user.notice 'Hello from the DevOps homework, written via logger'

$ journalctl -t devops-homework --no-pager
Sep 03 04:26:38 ff4c4be986b8 devops-homework[1090]: Hello from the DevOps homework, written via logger

###############################################
# STEP 9: Disk usage and log rotation / cleanup
###############################################
$ journalctl --disk-usage
Archived and active journals take up 8.0M in the file system.

$ journalctl --verify 2>&1 | tail -3
PASS: /var/log/journal/34c36af29c1e4f109f8240a2fdc99503/system.journal

--- cleanup commands (destructive, shown here for reference): ---
    journalctl --vacuum-size=100M    # keep at most 100 MB
    journalctl --vacuum-time=7d      # keep only the last 7 days
    journalctl --rotate              # force rotation right now
$ journalctl --vacuum-time=2d
Vacuuming done, freed 0B of archived journals from /run/log/journal.
Vacuuming done, freed 0B of archived journals from /var/log/journal/34c36af29c1e4f109f8240a2fdc99503.
Vacuuming done, freed 0B of archived journals from /var/log/journal.
```

</details>

---

# Task 4 — Linux Command Cheat Sheet

All 16 categories below were executed live; the complete transcript is in
[`outputs/task4-command-cheatsheet.txt`](outputs/task4-command-cheatsheet.txt) and the script
that produced it is [`scripts/cheatsheet-lab.sh`](scripts/cheatsheet-lab.sh).

### 1. Orientation — where and who am I

| Command | Purpose |
|---|---|
| `pwd` | print working directory |
| `whoami` | current username |
| `id` | UID, GID and all group memberships |
| `hostname` / `hostnamectl` | machine name and OS details |
| `uname -a` | kernel name, version, architecture |
| `uptime` | how long the machine has been up + load average |
| `date` | current date and time |

```console
$ id
uid=0(root) gid=0(root) groups=0(root)

$ uname -a
Linux ff4c4be986b8 7.0.12-linuxkit #1 SMP PREEMPT Wed Aug 12 20:18:49 UTC 2026 aarch64 aarch64 aarch64 GNU/Linux

$ uptime
 04:33:17 up 4 days,  7:48,  0 user,  load average: 0.07, 0.08, 0.09
```

### 2. Navigation

| Command | Purpose |
|---|---|
| `cd dir` / `cd ..` / `cd ~` / `cd -` | move around; `-` returns to the previous directory |
| `ls` | list |
| `ls -l` | long format: permissions, owner, size, mtime |
| `ls -la` | include hidden dotfiles |
| `ls -lh` | human-readable sizes (K/M/G) |
| `ls -lt` | sort by modification time |
| `ls -R` | recurse into subdirectories |
| `tree dir` | draw the directory tree |

```console
$ tree project
project
|-- docs
|-- src
`-- tests

4 directories, 0 files

$ cd project/src && pwd && cd - && pwd
/root/cheat/project/src
/root/cheat
/root/cheat
```

### 3. Creating, copying, moving, deleting

| Command | Purpose |
|---|---|
| `touch file` | create an empty file / update its timestamp |
| `mkdir dir` | make a directory |
| `mkdir -p a/b/c` | make the whole path, no error if it exists |
| `cp src dst` | copy a file |
| `cp -r srcdir dstdir` | copy a directory recursively |
| `mv src dst` | move **or rename** |
| `rm file` | delete a file |
| `rm -rf dir` | delete a directory tree, no prompts — **irreversible** |
| `rmdir dir` | delete an *empty* directory |

`mv` renames in place — note `utils.py` becomes `helpers.py`:

```console
$ mv project/src/utils.py project/src/helpers.py
$ ls -l project/src
total 0
-rw-r--r-- 1 root root 0 Sep  3 04:33 app.py
-rw-r--r-- 1 root root 0 Sep  3 04:33 app.py.bak
-rw-r--r-- 1 root root 0 Sep  3 04:33 helpers.py
```

### 4. Viewing file content

| Command | Purpose |
|---|---|
| `cat file` | dump the whole file |
| `cat -n file` | with line numbers |
| `less file` | scrollable pager (`q` quits, `/` searches) |
| `head -n 20 file` | first 20 lines |
| `tail -n 20 file` | last 20 lines |
| `tail -f file` | **follow** a file as it grows — the log-watching command |
| `wc -l file` | count lines (`-w` words, `-c` bytes) |

```console
$ head -3 numbers.txt
line1
line2
line3

$ tail -3 numbers.txt
line8
line9
line10

$ wc numbers.txt
10 10 61 numbers.txt
```

`wc` prints lines, words, bytes in that order.

### 5. Searching

| Command | Purpose |
|---|---|
| `grep pattern file` | find matching lines |
| `grep -n` | show line numbers |
| `grep -i` | case-insensitive |
| `grep -v` | **invert** — lines that do *not* match |
| `grep -c` | count matches |
| `grep -r pattern dir/` | search recursively |
| `find . -name '*.py'` | find by name |
| `find . -type d` | only directories (`-type f` = files) |
| `find . -size +100M` | by size |
| `find . -mtime -7` | modified in the last 7 days |
| `find . -name '*.log' -delete` | find and act |
| `which cmd` | path of the executable that would run |
| `type cmd` | is it a builtin, alias, function or file? |

```console
$ grep -n 'line' numbers.txt | head -4
1:line1
2:line2
3:line3
4:line4

$ grep -c 'line' numbers.txt
10

$ find . -name '*.py'
./project/src/helpers.py
./project/src/app.py
./backup_project/src/utils.py
./backup_project/src/app.py

$ which bash grep
/usr/bin/bash
/usr/bin/grep

$ type cd
cd is a shell builtin
```

### 6. Text processing

| Command | Purpose |
|---|---|
| `cut -d, -f1 file` | slice out a delimited column |
| `sort file` | sort lines (`-n` numeric, `-r` reverse, `-u` unique) |
| `uniq -c` | collapse duplicates and count (input must be sorted) |
| `awk -F, '{print $1}'` | field-aware processing |
| `sed 's/old/new/g' file` | stream editing / substitution |
| `tr 'a-z' 'A-Z'` | translate characters |
| `paste`, `join`, `column -t` | combine and align columns |

```console
$ cat fruit.csv
banana,3
apple,5
cherry,1
apple,5

$ cut -d, -f1 fruit.csv
banana
apple
cherry
apple

$ sort -u fruit.csv
apple,5
banana,3
cherry,1

$ awk -F, '{print $1 " costs " $2}' fruit.csv
banana costs 3
apple costs 5
cherry costs 1
apple costs 5

$ sed 's/apple/AVOCADO/g' fruit.csv
banana,3
AVOCADO,5
cherry,1
AVOCADO,5

$ head -3 /etc/passwd | cut -d: -f1,7
root:/bin/bash
daemon:/usr/sbin/nologin
bin:/usr/sbin/nologin
```

### 7. Permissions and ownership
```
   rwx  rwx  rwx        r=4  w=2  x=1
   |    |    |
 owner group other      755 = rwxr-xr-x     644 = rw-r--r--
```

| Command | Purpose |
|---|---|
| `chmod +x script.sh` | make executable (symbolic form) |
| `chmod 755 file` | numeric form |
| `chmod -R 755 dir/` | recursive |
| `chown user:group file` | change owner and group |
| `umask` | default permission mask for new files |
| `stat -c '%A %a %U %G %n' file` | print permissions and ownership compactly |

A newly created file, then each change and its effect:

```console
$ ls -l script.sh
-rw-r--r-- 1 root root 0 Sep  3 04:33 script.sh

$ chmod +x script.sh
$ ls -l script.sh
-rwxr-xr-x 1 root root 0 Sep  3 04:33 script.sh

$ chmod 644 script.sh
$ ls -l script.sh
-rw-r--r-- 1 root root 0 Sep  3 04:33 script.sh

$ chmod 755 script.sh
$ ls -l script.sh
-rwxr-xr-x 1 root root 0 Sep  3 04:33 script.sh

$ chown testuser:testuser script.sh
$ ls -l script.sh
-rwxr-xr-x 1 testuser testuser 0 Sep  3 04:33 script.sh

$ umask
0022

$ stat -c '%A %a %U %G %n' script.sh
-rwxr-xr-x 755 testuser testuser script.sh
```

Watch the mode string change `-rw-r--r--` → `-rwxr-xr-x` → `-rw-r--r--` → `-rwxr-xr-x`, then
the owner change from `root root` to `testuser testuser`.

### 8. Processes

| Command | Purpose |
|---|---|
| `ps` | processes in this shell |
| `ps aux` | every process, BSD syntax |
| `ps -ef` | every process, System V syntax |
| `ps -eo pid,ppid,%cpu,%mem,comm --sort=-%cpu` | custom columns, sorted by CPU |
| `pgrep -a nginx` | find PIDs by name |
| `pstree -p` | the process tree |
| `top` / `htop` | live interactive monitor |
| `cmd &` | run in the background |
| `jobs` | list this shell's background jobs |
| `kill PID` | polite stop (SIGTERM 15) |
| `kill -9 PID` | force kill (SIGKILL 9) |
| `pkill -f pattern` | kill by command-line pattern |

```console
$ ps -eo pid,ppid,user,%cpu,%mem,comm --sort=-%cpu | head -8
    PID    PPID USER     %CPU %MEM COMMAND
   1661       0 root     22.2  0.0 bash
      1       0 root      0.0  0.2 systemd
     23       1 root      0.0  0.2 systemd-journal
     71       1 message+  0.0  0.0 dbus-daemon
     74       1 root      0.0  0.1 systemd-logind
     77       1 root      0.0  0.0 agetty
   1061       1 root      0.0  0.0 nginx

$ pgrep -a nginx
1061 nginx: master process /usr/sbin/nginx -g daemon on; master_process on;
1062 nginx: worker process
1063 nginx: worker process
1064 nginx: worker process
1065 nginx: worker process
1067 nginx: worker process
1068 nginx: worker process
1069 nginx: worker process
1070 nginx: worker process

$ pstree -p 2>/dev/null | head -10 || echo 'pstree not installed'
systemd(1)-+-agetty(77)
           |-dbus-daemon(71)
           |-nginx(1061)-+-nginx(1062)
           |             |-nginx(1063)
           |             |-nginx(1064)
           |             |-nginx(1065)
           |             |-nginx(1067)
           |             |-nginx(1068)
           |             |-nginx(1069)
           |             `-nginx(1070)
```

Background jobs:

```console
$ jobs
[1]+  Running                 sleep 300 > /dev/null 2>&1 &
```

> **Gotcha hit while writing this lab:** the first version of this script ran `sleep 300 &`
> inside a pipeline and **hung for five minutes**. A background job inherits the pipeline's
> stdout, so `head` never sees EOF and the whole command blocks. The fix is to redirect it —
> `sleep 300 >/dev/null 2>&1 &` — and capture `$!` so you can kill it by PID.

### 9. Disk and memory

| Command | Purpose |
|---|---|
| `df -h` | free space per mounted filesystem |
| `df -hT` | include the filesystem type |
| `du -sh dir` | total size of a directory |
| `du -h --max-depth=1` | size of each immediate subdirectory |
| `free -h` | RAM and swap usage |

```console
$ df -h
Filesystem      Size  Used Avail Use% Mounted on
overlay         224G  2.6G  210G   2% /
tmpfs            64M     0   64M   0% /dev
shm              64M     0   64M   0% /dev/shm
tmpfs           2.0G   36K  2.0G   1% /run
tmpfs           2.0G     0  2.0G   0% /run/lock
/dev/vda1       224G  2.6G  210G   2% /etc/hosts

$ du -sh /root/cheat
44K	/root/cheat

$ free -h
               total        used        free      shared  buff/cache   available
Mem:           3.8Gi       765Mi       1.2Gi        37Mi       2.1Gi       3.1Gi
Swap:          1.0Gi          0B       1.0Gi
```

### 10. Archives and compression

| Command | Purpose |
|---|---|
| `tar -czvf out.tar.gz dir/` | **c**reate, g**z**ip, **v**erbose, **f**ile |
| `tar -xzvf out.tar.gz` | e**x**tract |
| `tar -xzf out.tar.gz -C /dest` | extract somewhere specific |
| `tar -tzf out.tar.gz` | lis**t** contents without extracting |
| `gzip file` / `gunzip file.gz` | compress a single file |
| `zip -r out.zip dir/` / `unzip out.zip` | zip format |

```console
$ tar -czvf project.tar.gz project
project/
project/tests/
project/src/
project/src/helpers.py
project/src/app.py
project/docs/
$ ls -lh project.tar.gz
-rw-r--r-- 1 root root 207 Sep  3 04:33 project.tar.gz

$ tar -tzf project.tar.gz
project/
project/tests/
project/src/
project/src/helpers.py
project/src/app.py
project/docs/

$ mkdir extracted && tar -xzf project.tar.gz -C extracted && find extracted
extracted
extracted/project
extracted/project/tests
extracted/project/src
extracted/project/src/helpers.py
extracted/project/src/app.py
extracted/project/docs
```

### 11. Redirection and pipes

| Syntax | Meaning |
|---|---|
| `cmd > file` | stdout to file, **overwrite** |
| `cmd >> file` | stdout to file, **append** |
| `cmd 2> file` | stderr to file |
| `cmd > file 2>&1` | both streams to one file |
| `cmd &> file` | same thing, bash shorthand |
| `cmd < file` | read stdin from a file |
| `cmd1 \| cmd2` | pipe stdout of one into stdin of the next |
| `cmd \| tee file` | print **and** save |
| `cmd > /dev/null` | discard output |

```console
$ echo 'appended with >>' >> out.txt && cat out.txt
written with >
appended with >>

$ ls /nonexistent 2> err.txt; cat err.txt
ls: cannot access '/nonexistent': No such file or directory

$ ls /nonexistent > all.txt 2>&1; cat all.txt
ls: cannot access '/nonexistent': No such file or directory

$ cat /etc/passwd | grep root | cut -d: -f1
root

$ echo 'to stdout and to file' | tee tee.txt
to stdout and to file
```

Note the difference between the two error examples: `2>` captured only stderr, while
`> file 2>&1` sent both streams to the same place.

### 12. Networking

| Command | Purpose |
|---|---|
| `ip addr show` | interfaces and IP addresses |
| `ip route` | routing table |
| `hostname -I` | just this machine's IPs |
| `ss -tuln` | listening TCP/UDP sockets |
| `ping -c 4 host` | reachability |
| `curl -I url` | HTTP headers only |
| `dig name +short` | DNS lookup |

```console
$ ip route
default via 172.17.0.1 dev eth0 
172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.2 

$ ss -tuln | head -8
Netid State  Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
tcp   LISTEN 0      511          0.0.0.0:80        0.0.0.0:*          
tcp   LISTEN 0      511             [::]:80           [::]:*          

$ ping -c 3 127.0.0.1
PING 127.0.0.1 (127.0.0.1) 56(84) bytes of data.
64 bytes from 127.0.0.1: icmp_seq=1 ttl=64 time=0.047 ms
64 bytes from 127.0.0.1: icmp_seq=2 ttl=64 time=0.146 ms
64 bytes from 127.0.0.1: icmp_seq=3 ttl=64 time=0.128 ms

--- 127.0.0.1 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2064ms
rtt min/avg/max/mdev = 0.047/0.107/0.146/0.043 ms
```

Covered in depth in [Homework 3 — Networking](../03-networking).

### 13. Users and groups

| Command | Purpose |
|---|---|
| `id user` | UID/GID/groups |
| `groups user` | group memberships |
| `getent passwd` | list accounts via NSS |
| `su - user` | switch user with a login shell |
| `sudo cmd` | run one command as root |
| `last` | recent logins |

```console
$ id testuser
uid=1003(testuser) gid=1003(testuser) groups=1003(testuser),27(sudo),100(users)

$ groups testuser
testuser : testuser sudo users

$ getent passwd | tail -3
systemd-network:x:998:998:systemd Network Management:/:/usr/sbin/nologin
messagebus:x:100:101::/nonexistent:/usr/sbin/nologin
testuser:x:1003:1003:Test User,101,555-0100,555-0101,DevOps Homework:/home/testuser:/bin/bash
```

### 14. Services (systemd)

| Command | Purpose |
|---|---|
| `systemctl status nginx` | current state + recent log lines |
| `systemctl start\|stop\|restart\|reload nginx` | control it |
| `systemctl enable\|disable nginx` | start at boot or not |
| `systemctl is-active nginx` | scriptable state check |
| `systemctl list-units --type=service --state=running` | what is running |
| `systemctl daemon-reload` | reload unit files after editing |

```console
$ systemctl is-active nginx
active

$ systemctl is-enabled nginx
enabled

$ systemctl list-units --type=service --state=running --no-pager | head -10
  UNIT                     LOAD   ACTIVE SUB     DESCRIPTION
  dbus.service             loaded active running D-Bus System Message Bus
  getty@tty1.service       loaded active running Getty on tty1
  nginx.service            loaded active running A high performance web server and a reverse proxy server
  systemd-journald.service loaded active running Journal Service
  systemd-logind.service   loaded active running User Login Management

Legend: LOAD   → Reflects whether the unit definition was properly loaded.
        ACTIVE → The high-level unit activation state, i.e. generalization of SUB.
        SUB    → The low-level unit activation state, values depend on unit type.
```

### 15. Package management (apt)

| Command | Purpose |
|---|---|
| `apt update` | refresh the package index |
| `apt upgrade` | install available updates |
| `apt install pkg` | install |
| `apt remove pkg` / `apt purge pkg` | remove / remove with config |
| `apt search term` | search |
| `apt-cache policy pkg` | installed vs candidate version |
| `dpkg -l` | list installed packages |
| `dpkg -L pkg` | which files a package installed |

```console
$ apt-cache policy nginx | head -5
nginx:
  Installed: 1.24.0-2ubuntu7.17
  Candidate: 1.24.0-2ubuntu7.17
  Version table:
 *** 1.24.0-2ubuntu7.17 500
```

### 16. Environment, history, help

| Command | Purpose |
|---|---|
| `echo $HOME $USER $SHELL` | read variables |
| `env` | all environment variables |
| `export VAR=value` | set one for child processes |
| `alias ll='ls -la'` | make a shortcut |
| `history` | previous commands (`!42` re-runs #42, `Ctrl-R` searches) |
| `man cmd` | manual page |
| `cmd --help` | quick usage |

```console
$ echo $HOME $USER $SHELL
/root /bin/bash

$ export MY_VAR='devops' && echo $MY_VAR
devops

$ alias ll='ls -la' && alias | head -3
alias ll='ls -la'

$ ls --help | head -5
Usage: ls [OPTION]... [FILE]...
List information about the FILEs (the current directory by default).
Sort entries alphabetically if none of -cftuvSUX nor --sort is specified.

Mandatory arguments to long options are mandatory for short options too.
```

> On a minimal Ubuntu container the `man` pages are stripped out — running `man ls` prints a
> notice telling you to run `unminimize` to restore them. `cmd --help` still works, which is
> why it appears above instead.

<details>
<summary><b>Full Task 4 transcript</b> (click to expand — all 16 categories)</summary>

```console

===================================================
  1. WHERE AM I / WHO AM I  (orientation)
===================================================
$ pwd
/root/cheat

$ whoami
root

$ id
uid=0(root) gid=0(root) groups=0(root)

$ hostname
ff4c4be986b8

$ hostnamectl --no-pager
hostnamectl: unrecognized option '--no-pager'

$ uname -a
Linux ff4c4be986b8 7.0.12-linuxkit #1 SMP PREEMPT Wed Aug 12 20:18:49 UTC 2026 aarch64 aarch64 aarch64 GNU/Linux

$ uptime
 04:33:17 up 4 days,  7:48,  0 user,  load average: 0.07, 0.08, 0.09

$ date
Thu Sep  3 04:33:17 UTC 2026

$ cal 2>/dev/null || date '+%B %Y'
   September 2026     
Su Mo Tu We Th Fr Sa  
       1  2  3  4  5  
 6  7  8  9 10 11 12  
13 14 15 16 17 18 19  
20 21 22 23 24 25 26  
27 28 29 30           
                      


===================================================
  2. NAVIGATION  (cd, ls, tree)
===================================================
$ mkdir -p project/{src,docs,tests}

$ ls
project

$ ls -l
total 4
drwxr-xr-x 5 root root 4096 Sep  3 04:33 project

$ ls -la
total 12
drwxr-xr-x 3 root root 4096 Sep  3 04:33 .
drwx------ 1 root root 4096 Sep  3 04:33 ..
drwxr-xr-x 5 root root 4096 Sep  3 04:33 project

$ ls -lh
total 4.0K
drwxr-xr-x 5 root root 4.0K Sep  3 04:33 project

$ ls -lt
total 4
drwxr-xr-x 5 root root 4096 Sep  3 04:33 project

$ ls -R
.:
project

./project:
docs
src
tests

./project/docs:

./project/src:

./project/tests:

$ tree project
project
|-- docs
|-- src
`-- tests

4 directories, 0 files

$ cd project/src && pwd && cd - && pwd
/root/cheat/project/src
/root/cheat
/root/cheat


===================================================
  3. CREATING FILES & DIRECTORIES  (touch, mkdir, cp, mv, rm)
===================================================
$ touch project/src/app.py project/src/utils.py

$ mkdir -p deep/nested/path

$ ls -l project/src
total 0
-rw-r--r-- 1 root root 0 Sep  3 04:33 app.py
-rw-r--r-- 1 root root 0 Sep  3 04:33 utils.py

$ cp project/src/app.py project/src/app.py.bak

$ cp -r project backup_project

$ mv project/src/utils.py project/src/helpers.py

$ ls -l project/src
total 0
-rw-r--r-- 1 root root 0 Sep  3 04:33 app.py
-rw-r--r-- 1 root root 0 Sep  3 04:33 app.py.bak
-rw-r--r-- 1 root root 0 Sep  3 04:33 helpers.py

$ rm project/src/app.py.bak

$ rm -rf deep

$ ls
backup_project
project


===================================================
  4. VIEWING FILE CONTENT  (cat, less, head, tail, wc)
===================================================
$ printf 'line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\n' > numbers.txt

$ cat numbers.txt
line1
line2
line3
line4
line5
line6
line7
line8
line9
line10

$ cat -n numbers.txt
     1	line1
     2	line2
     3	line3
     4	line4
     5	line5
     6	line6
     7	line7
     8	line8
     9	line9
    10	line10

$ head -3 numbers.txt
line1
line2
line3

$ tail -3 numbers.txt
line8
line9
line10

$ wc -l numbers.txt
10 numbers.txt

$ wc numbers.txt
10 10 61 numbers.txt

-- less / more open an interactive pager (q to quit) --
-- tail -f follows a file live, e.g. tail -f /var/log/syslog --

===================================================
  5. SEARCHING  (grep, find, locate, which)
===================================================
$ grep 'line5' numbers.txt
line5

$ grep -n 'line' numbers.txt | head -4
1:line1
2:line2
3:line3
4:line4

$ grep -c 'line' numbers.txt
10

$ grep -i 'LINE1' numbers.txt
line1
line10

$ grep -v 'line1' numbers.txt | head -3
line2
line3
line4

$ grep -r 'line5' .
./numbers.txt:line5

$ find . -name '*.py'
./project/src/helpers.py
./project/src/app.py
./backup_project/src/utils.py
./backup_project/src/app.py

$ find . -type d
.
./project
./project/tests
./project/src
./project/docs
./backup_project
./backup_project/tests
./backup_project/src
./backup_project/docs

$ find . -type f -size +0c | head -5
./numbers.txt

$ find /etc -name 'passwd' 2>/dev/null
/etc/passwd
/etc/pam.d/passwd

$ which bash grep
/usr/bin/bash
/usr/bin/grep

$ type cd
cd is a shell builtin


===================================================
  6. TEXT PROCESSING  (cut, sort, uniq, awk, sed, tr)
===================================================
$ printf 'banana,3\napple,5\ncherry,1\napple,5\n' > fruit.csv

$ cat fruit.csv
banana,3
apple,5
cherry,1
apple,5

$ cut -d, -f1 fruit.csv
banana
apple
cherry
apple

$ sort fruit.csv
apple,5
apple,5
banana,3
cherry,1

$ sort -u fruit.csv
apple,5
banana,3
cherry,1

$ uniq -c fruit.csv
      1 banana,3
      1 apple,5
      1 cherry,1
      1 apple,5

$ awk -F, '{print $1 " costs " $2}' fruit.csv
banana costs 3
apple costs 5
cherry costs 1
apple costs 5

$ sed 's/apple/AVOCADO/g' fruit.csv
banana,3
AVOCADO,5
cherry,1
AVOCADO,5

$ cat numbers.txt | tr 'a-z' 'A-Z' | head -3
LINE1
LINE2
LINE3

$ head -3 /etc/passwd | cut -d: -f1,7
root:/bin/bash
daemon:/usr/sbin/nologin
bin:/usr/sbin/nologin


===================================================
  7. PERMISSIONS & OWNERSHIP  (chmod, chown, umask)
===================================================
$ touch script.sh

$ ls -l script.sh
-rw-r--r-- 1 root root 0 Sep  3 04:33 script.sh

$ chmod +x script.sh

$ ls -l script.sh
-rwxr-xr-x 1 root root 0 Sep  3 04:33 script.sh

$ chmod 644 script.sh

$ ls -l script.sh
-rw-r--r-- 1 root root 0 Sep  3 04:33 script.sh

$ chmod 755 script.sh

$ ls -l script.sh
-rwxr-xr-x 1 root root 0 Sep  3 04:33 script.sh

-- rwx = 4+2+1 ; 755 = rwxr-xr-x (owner all, group+other read/execute) --
$ chown testuser:testuser script.sh

$ ls -l script.sh
-rwxr-xr-x 1 testuser testuser 0 Sep  3 04:33 script.sh

$ umask
0022

$ stat -c '%A %a %U %G %n' script.sh
-rwxr-xr-x 755 testuser testuser script.sh


===================================================
  8. PROCESSES  (ps, top, kill, jobs)
===================================================
$ ps
    PID TTY          TIME CMD
      1 ?        00:00:00 systemd
     23 ?        00:00:00 systemd-journal
     74 ?        00:00:00 systemd-logind
   1061 ?        00:00:00 nginx
   1661 ?        00:00:00 bash
   1876 ?        00:00:00 bash
   1877 ?        00:00:00 ps
   1878 ?        00:00:00 head

$ ps aux | head -8
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  0.0  0.2  20968 11660 ?        Ss   04:19   0:00 /sbin/init
root          23  0.0  0.2  33636 11420 ?        S<s  04:19   0:00 /usr/lib/systemd/systemd-journald
message+      71  0.0  0.0   8404  3972 ?        Ss   04:19   0:00 @dbus-daemon --system --address=systemd: --nofork --nopidfile --systemd-activation --syslog-only
root          74  0.0  0.1  17204  7168 ?        Ss   04:19   0:00 /usr/lib/systemd/systemd-logind
root          77  0.0  0.0   2700  1716 tty1     Ss+  04:19   0:00 /sbin/agetty -o -p -- \u --noclear - linux
root        1061  0.0  0.0  10380  1548 ?        Ss   04:26   0:00 nginx: master process /usr/sbin/nginx -g daemon on; master_process on;
www-data    1062  0.0  0.0  10752  3360 ?        S    04:26   0:00 nginx: worker process

$ ps -ef | head -6
UID          PID    PPID  C STIME TTY          TIME CMD
root           1       0  0 04:19 ?        00:00:00 /sbin/init
root          23       1  0 04:19 ?        00:00:00 /usr/lib/systemd/systemd-journald
message+      71       1  0 04:19 ?        00:00:00 @dbus-daemon --system --address=systemd: --nofork --nopidfile --systemd-activation --syslog-only
root          74       1  0 04:19 ?        00:00:00 /usr/lib/systemd/systemd-logind
root          77       1  0 04:19 tty1     00:00:00 /sbin/agetty -o -p -- \u --noclear - linux

$ ps -eo pid,ppid,user,%cpu,%mem,comm --sort=-%cpu | head -8
    PID    PPID USER     %CPU %MEM COMMAND
   1661       0 root     22.2  0.0 bash
      1       0 root      0.0  0.2 systemd
     23       1 root      0.0  0.2 systemd-journal
     71       1 message+  0.0  0.0 dbus-daemon
     74       1 root      0.0  0.1 systemd-logind
     77       1 root      0.0  0.0 agetty
   1061       1 root      0.0  0.0 nginx

$ pgrep -a nginx
1061 nginx: master process /usr/sbin/nginx -g daemon on; master_process on;
1062 nginx: worker process
1063 nginx: worker process
1064 nginx: worker process
1065 nginx: worker process
1067 nginx: worker process
1068 nginx: worker process
1069 nginx: worker process
1070 nginx: worker process

$ pstree -p 2>/dev/null | head -10 || echo 'pstree not installed'
systemd(1)-+-agetty(77)
           |-dbus-daemon(71)
           |-nginx(1061)-+-nginx(1062)
           |             |-nginx(1063)
           |             |-nginx(1064)
           |             |-nginx(1065)
           |             |-nginx(1067)
           |             |-nginx(1068)
           |             |-nginx(1069)
           |             `-nginx(1070)

-- top / htop are the interactive live process monitors --
$ sleep 300 &   # start a background job
[1] 1898

$ jobs
[1]+  Running                 sleep 300 > /dev/null 2>&1 &

$ ps -p 1898 -o pid,stat,comm
    PID STAT COMMAND
   1898 S    sleep

$ kill 1898
background job 1898 terminated

-- kill <PID> sends SIGTERM(15); kill -9 <PID> sends SIGKILL --

===================================================
  9. DISK & MEMORY  (df, du, free)
===================================================
$ df -h
Filesystem      Size  Used Avail Use% Mounted on
overlay         224G  2.6G  210G   2% /
tmpfs            64M     0   64M   0% /dev
shm              64M     0   64M   0% /dev/shm
tmpfs           2.0G   36K  2.0G   1% /run
tmpfs           2.0G     0  2.0G   0% /run/lock
/dev/vda1       224G  2.6G  210G   2% /etc/hosts

$ df -hT | head -5
Filesystem     Type     Size  Used Avail Use% Mounted on
overlay        overlay  224G  2.6G  210G   2% /
tmpfs          tmpfs     64M     0   64M   0% /dev
shm            tmpfs     64M     0   64M   0% /dev/shm
tmpfs          tmpfs    2.0G   36K  2.0G   1% /run

$ du -sh /root/cheat
44K	/root/cheat

$ du -h --max-depth=1 /root/cheat
16K	/root/cheat/project
16K	/root/cheat/backup_project
44K	/root/cheat

$ free -h
               total        used        free      shared  buff/cache   available
Mem:           3.8Gi       765Mi       1.2Gi        37Mi       2.1Gi       3.1Gi
Swap:          1.0Gi          0B       1.0Gi

$ free -m
               total        used        free      shared  buff/cache   available
Mem:            3916         765        1197          37        2172        3150
Swap:           1023           0        1023


===================================================
  10. ARCHIVES & COMPRESSION  (tar, gzip, zip)
===================================================
$ tar -czvf project.tar.gz project
project/
project/tests/
project/src/
project/src/helpers.py
project/src/app.py
project/docs/

$ ls -lh project.tar.gz
-rw-r--r-- 1 root root 207 Sep  3 04:33 project.tar.gz

$ tar -tzf project.tar.gz
project/
project/tests/
project/src/
project/src/helpers.py
project/src/app.py
project/docs/

$ mkdir extracted && tar -xzf project.tar.gz -C extracted && find extracted
extracted
extracted/project
extracted/project/tests
extracted/project/src
extracted/project/src/helpers.py
extracted/project/src/app.py
extracted/project/docs

$ gzip -k numbers.txt && ls -l numbers.txt*
-rw-r--r-- 1 root root 61 Sep  3 04:33 numbers.txt
-rw-r--r-- 1 root root 64 Sep  3 04:33 numbers.txt.gz

$ gunzip numbers.txt.gz && ls -l numbers.txt
gzip: numbers.txt already exists;	not overwritten


===================================================
  11. I/O REDIRECTION & PIPES
===================================================
$ echo 'written with >' > out.txt && cat out.txt
written with >

$ echo 'appended with >>' >> out.txt && cat out.txt
written with >
appended with >>

$ ls /nonexistent 2> err.txt; cat err.txt
ls: cannot access '/nonexistent': No such file or directory

$ ls /nonexistent > all.txt 2>&1; cat all.txt
ls: cannot access '/nonexistent': No such file or directory

$ ls /etc | wc -l
112

$ cat /etc/passwd | grep root | cut -d: -f1
root

$ echo 'to stdout and to file' | tee tee.txt
to stdout and to file

$ cat tee.txt
to stdout and to file


===================================================
  12. NETWORKING BASICS
===================================================
$ ip addr show | head -12
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: tunl0@NONE: <NOARP> mtu 1480 qdisc noop state DOWN group default qlen 1000
    link/ipip 0.0.0.0 brd 0.0.0.0
3: gre0@NONE: <NOARP> mtu 1476 qdisc noop state DOWN group default qlen 1000
    link/gre 0.0.0.0 brd 0.0.0.0
4: gretap0@NONE: <BROADCAST,MULTICAST> mtu 1462 qdisc noop state DOWN group default qlen 1000
    link/ether 00:00:00:00:00:00 brd ff:ff:ff:ff:ff:ff

$ ip route
default via 172.17.0.1 dev eth0 
172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.2 

$ hostname -I
172.17.0.2 

$ ss -tuln | head -8
Netid State  Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
tcp   LISTEN 0      511          0.0.0.0:80        0.0.0.0:*          
tcp   LISTEN 0      511             [::]:80           [::]:*          

$ ping -c 3 127.0.0.1
PING 127.0.0.1 (127.0.0.1) 56(84) bytes of data.
64 bytes from 127.0.0.1: icmp_seq=1 ttl=64 time=0.047 ms
64 bytes from 127.0.0.1: icmp_seq=2 ttl=64 time=0.146 ms
64 bytes from 127.0.0.1: icmp_seq=3 ttl=64 time=0.128 ms

--- 127.0.0.1 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2064ms
rtt min/avg/max/mdev = 0.047/0.107/0.146/0.043 ms

$ curl -sI http://localhost | head -5
HTTP/1.1 200 OK
Server: nginx/1.24.0 (Ubuntu)
Date: Thu, 03 Sep 2026 04:33:19 GMT
Content-Type: text/html
Content-Length: 615


===================================================
  13. USERS, GROUPS, SUDO
===================================================
$ id testuser
uid=1003(testuser) gid=1003(testuser) groups=1003(testuser),27(sudo),100(users)

$ groups testuser
testuser : testuser sudo users

$ getent passwd | tail -3
systemd-network:x:998:998:systemd Network Management:/:/usr/sbin/nologin
messagebus:x:100:101::/nonexistent:/usr/sbin/nologin
testuser:x:1003:1003:Test User,101,555-0100,555-0101,DevOps Homework:/home/testuser:/bin/bash

$ cat /etc/group | tail -5
ubuntu:x:1000:
systemd-journal:x:999:
systemd-network:x:998:
messagebus:x:101:
testuser:x:1003:

$ last 2>/dev/null | head -3 || echo 'no wtmp in container'
reboot   system boot  7.0.12-linuxkit  Thu Sep  3 04:19   still running

wtmp begins Thu Sep  3 04:19:48 2026


===================================================
  14. SERVICES  (systemctl)
===================================================
$ systemctl status nginx --no-pager | head -6
● nginx.service - A high performance web server and a reverse proxy server
     Loaded: loaded (/usr/lib/systemd/system/nginx.service; enabled; preset: enabled)
     Active: active (running) since Thu 2026-09-03 04:26:38 UTC; 6min ago
       Docs: man:nginx(8)
   Main PID: 1061 (nginx)
      Tasks: 9 (limit: 4742)

$ systemctl is-active nginx
active

$ systemctl is-enabled nginx
enabled

$ systemctl list-units --type=service --state=running --no-pager | head -10
  UNIT                     LOAD   ACTIVE SUB     DESCRIPTION
  dbus.service             loaded active running D-Bus System Message Bus
  getty@tty1.service       loaded active running Getty on tty1
  nginx.service            loaded active running A high performance web server and a reverse proxy server
  systemd-journald.service loaded active running Journal Service
  systemd-logind.service   loaded active running User Login Management

Legend: LOAD   → Reflects whether the unit definition was properly loaded.
        ACTIVE → The high-level unit activation state, i.e. generalization of SUB.
        SUB    → The low-level unit activation state, values depend on unit type.


===================================================
  15. PACKAGE MANAGEMENT  (apt)
===================================================
$ apt list --installed 2>/dev/null | head -6
Listing...
adduser/noble,now 3.137ubuntu1 all [installed]
apt/noble-updates,now 2.8.3 arm64 [installed]
base-files/noble-updates,now 13ubuntu10.4 arm64 [installed]
base-passwd/noble,now 3.6.3build1 arm64 [installed]
bash/noble,now 5.2.21-2ubuntu4 arm64 [installed]

$ dpkg -l | head -8
Desired=Unknown/Install/Remove/Purge/Hold
| Status=Not/Inst/Conf-files/Unpacked/halF-conf/Half-inst/trig-aWait/Trig-pend
|/ Err?=(none)/Reinst-required (Status,Err: uppercase=bad)
||/ Name                        Version                           Architecture Description
+++-===========================-=================================-============-================================================================================
ii  adduser                     3.137ubuntu1                      all          add and remove users and groups
ii  apt                         2.8.3                             arm64        commandline package manager
ii  base-files                  13ubuntu10.4                      arm64        Debian base system miscellaneous files

$ apt-cache policy nginx | head -5
nginx:
  Installed: 1.24.0-2ubuntu7.17
  Candidate: 1.24.0-2ubuntu7.17
  Version table:
 *** 1.24.0-2ubuntu7.17 500

-- apt update / apt install <pkg> / apt remove <pkg> / apt search <pkg> --

===================================================
  16. HISTORY, ALIASES, ENV, HELP
===================================================
$ echo $HOME $USER $SHELL
/root /bin/bash

$ env | sort | head -8
DEBIAN_FRONTEND=noninteractive
HOME=/root
HOSTNAME=ff4c4be986b8
OLDPWD=/
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
PWD=/root/cheat
SHLVL=1
_=/usr/bin/env

$ export MY_VAR='devops' && echo $MY_VAR
devops

$ alias ll='ls -la' && alias | head -3
alias ll='ls -la'

$ man ls 2>/dev/null | col -b | head -8
This system has been minimized by removing packages and content that are
not required on a system that users do not log into.

To restore this content, including manpages, you can run the 'unminimize'
command. You will still need to ensure the 'man-db' package is installed.

$ ls --help | head -5
Usage: ls [OPTION]... [FILE]...
List information about the FILEs (the current directory by default).
Sort entries alphabetically if none of -cftuvSUX nor --sort is specified.

Mandatory arguments to long options are mandatory for short options too.

$ history 2>/dev/null | tail -3 || echo 'history is interactive-shell only'
```

</details>

---

## Files in this folder

| Path | What it is |
|---|---|
| `Dockerfile.lab` | Ubuntu 24.04 + systemd image used for every Linux task |
| `scripts/links-lab.sh` | Task 1 — reproduces the soft/hard link transcript |
| `scripts/user-lab.sh` | Task 2 — reproduces the adduser/useradd transcript |
| `scripts/journal-lab.sh` | Task 3 — reproduces the journalctl transcript |
| `scripts/cheatsheet-lab.sh` | Task 4 — reproduces the cheat sheet transcript |
| `outputs/*.txt` | the raw captured output of each script |

### Reproducing everything

```bash
docker build -t linux-lab:24.04 -f Dockerfile.lab .
docker run -d --name linux-lab --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw --tmpfs /run --tmpfs /run/lock linux-lab:24.04

for s in links user journal cheatsheet; do
  docker cp scripts/$s-lab.sh linux-lab:/root/
  docker exec linux-lab bash /root/$s-lab.sh
done
```

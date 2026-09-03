#!/bin/bash
# Task 2: adduser vs useradd -- live transcript
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }

echo "###############################################"
echo "# STEP 0: What ARE these two commands?"
echo "###############################################"
run "cat /etc/os-release | head -3"
run "which adduser useradd"
run "file /usr/sbin/adduser"
run "file /usr/sbin/useradd"
echo "--- adduser is a friendly Perl WRAPPER; useradd is the low-level C binary ---"
run "head -20 /usr/sbin/adduser"

echo "###############################################"
echo "# STEP 1: The LOW-LEVEL way -- useradd (bare minimum)"
echo "###############################################"
run "useradd raw_user"
run "grep raw_user /etc/passwd"
run "grep raw_user /etc/shadow"
run "grep raw_user /etc/group"
echo "--- Notice: NO home directory was created ---"
run "ls -la /home"
run "test -d /home/raw_user && echo 'home exists' || echo 'NO HOME DIRECTORY for raw_user'"
echo "--- Notice: login shell is /bin/sh (no shell set), and the account is LOCKED (! in shadow) ---"
run "passwd -S raw_user"

echo "###############################################"
echo "# STEP 2: Making useradd behave requires MANY flags"
echo "###############################################"
run "useradd -m -s /bin/bash -c 'Manually Configured User' -G sudo flag_user"
run "grep flag_user /etc/passwd"
run "ls -la /home/flag_user"
run "groups flag_user"
run "passwd -S flag_user"

echo "###############################################"
echo "# STEP 3: The RECOMMENDED way on Ubuntu/Debian -- adduser"
echo "###############################################"
echo "--- Interactively you would simply type:  sudo adduser testuser"
echo "    and answer its prompts:"
cat <<'PROMPTS'
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
PROMPTS
echo
echo "--- Same thing, run non-interactively (scriptable form): ---"
run "adduser --gecos 'Test User,101,555-0100,555-0101,DevOps Homework' --disabled-password testuser"
run "echo 'testuser:TestPass@123' | chpasswd"
run "passwd -S testuser"
echo

run "grep testuser /etc/passwd"
run "grep testuser /etc/group"
run "passwd -S testuser"
echo "--- adduser DID create and populate the home directory automatically: ---"
run "ls -la /home/testuser"
echo "--- ...by copying the skeleton directory /etc/skel: ---"
run "ls -la /etc/skel"
echo "--- ...and it created a matching USER PRIVATE GROUP: ---"
run "id testuser"

echo "###############################################"
echo "# STEP 4: Side-by-side comparison of the 3 accounts"
echo "###############################################"
run "grep -E 'raw_user|flag_user|testuser' /etc/passwd"
echo "format: name:passwd:UID:GID:GECOS/comment:home:shell"
echo
run "for u in raw_user flag_user testuser; do printf '%-10s home=%-18s shell=%-10s\n' \"\$u\" \"\$(getent passwd \$u | cut -d: -f6)\" \"\$(getent passwd \$u | cut -d: -f7)\"; done"

echo "###############################################"
echo "# STEP 5: Prove the recommended user actually works"
echo "###############################################"
run "su - testuser -c 'whoami; pwd; echo \$SHELL; ls -a'"

echo "###############################################"
echo "# STEP 6: adduser also manages groups & sudo access"
echo "###############################################"
run "adduser testuser sudo"
run "groups testuser"

echo "###############################################"
echo "# STEP 7: Config file that adduser reads (useradd ignores it)"
echo "###############################################"
run "grep -vE '^#|^$' /etc/adduser.conf"

echo "###############################################"
echo "# STEP 8: Deleting users"
echo "###############################################"
run "deluser --remove-home raw_user"
run "userdel -r flag_user"
run "grep -E 'raw_user|flag_user' /etc/passwd || echo 'both removed'"
echo "--- keeping testuser as the required deliverable ---"
run "getent passwd testuser"

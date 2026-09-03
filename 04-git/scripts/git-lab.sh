#!/bin/bash
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
sec() { echo; echo "==================================================="; echo "  $*"; echo "==================================================="; }

export GIT_PAGER=cat
rm -rf /tmp/git-lab && mkdir -p /tmp/git-lab && cd /tmp/git-lab

sec "SETUP: create a fresh repository"
run "git init -b main"
run "git config user.name 'BinaryBhakti'"
run "git config user.email 'ashmitknayak@gmail.com'"

echo "###################################################################"
echo "#  TASK 1:  git commit -m   vs   git commit -a -m"
echo "###################################################################"

sec "1a. First commit -- a brand new file MUST be staged with git add"
run "echo 'v1: initial content' > file1.txt"
run "git status --short"
echo "-- '??' means UNTRACKED. git commit -a will NOT pick this up: --"
run "git commit -a -m 'try to commit an untracked file with -a'"
echo "-- Nothing was committed. Untracked files are invisible to -a. --"
run "git add file1.txt"
run "git status --short"
echo "-- 'A' means staged/Added. Now it can be committed: --"
run "git commit -m 'C1: add file1.txt'"
run "git log --oneline"

sec "1b. Modify a TRACKED file -- now compare the two commands"
run "echo 'v2: modified content' >> file1.txt"
run "cat file1.txt"
run "git status --short"
echo "-- ' M' (space then M) = modified in WORKING DIRECTORY but NOT staged --"
echo
echo "-- Try plain 'git commit -m' with nothing staged: --"
run "git commit -m 'C2: plain commit with nothing staged'"
echo "-- It REFUSED: 'no changes added to commit'. --"
echo
echo "-- Now the same situation with -a, which auto-stages tracked files: --"
run "git commit -a -m 'C2: modify file1.txt using commit -a -m'"
run "git log --oneline"
run "git status --short"
echo "-- Working tree is clean. -a did 'git add' for us on TRACKED files. --"

sec "1c. Side-by-side proof with a tracked file AND an untracked file"
run "echo 'v3: third change' >> file1.txt"
run "echo 'brand new, never tracked' > file2_untracked.txt"
run "git status --short"
echo "-- ' M file1.txt'  = tracked + modified  -> -a WILL commit it"
echo "-- '?? file2_untracked.txt' = untracked  -> -a will IGNORE it"
echo
run "git commit -a -m 'C3: -a picks up file1 but ignores the untracked file'"
run "git show --stat --oneline HEAD"
run "git status --short"
echo "-- Confirmed: file2_untracked.txt is STILL untracked after commit -a. --"
run "git add file2_untracked.txt && git commit -m 'C4: explicitly add and commit file2'"
run "git status --short"
run "git log --oneline"

sec "1d. What about a DELETED tracked file?"
run "echo 'delete me later' > file3.txt && git add file3.txt && git commit -m 'C5: add file3.txt'"
run "rm file3.txt"
run "git status --short"
echo "-- ' D' = deleted in working tree, deletion not staged --"
run "git commit -a -m 'C6: -a also stages DELETIONS of tracked files'"
run "git status --short"
run "git log --oneline"

sec "1e. SUMMARY TABLE"
cat <<'TABLE'
 +------------------------+---------------------+------------------------+
 | Change type            | git commit -m       | git commit -a -m       |
 +------------------------+---------------------+------------------------+
 | New / untracked file   | needs git add first | IGNORED (needs add)    |
 | Modified tracked file  | needs git add first | auto-staged  [OK]      |
 | Deleted tracked file   | needs git add/rm    | auto-staged  [OK]      |
 | Staged changes         | commits them        | commits them           |
 +------------------------+---------------------+------------------------+
   -a  ==  "git add -u"  (update tracked files)  +  "git commit"
TABLE

echo
echo "###################################################################"
echo "#  TASK 2:  git cherry-pick"
echo "###################################################################"

sec "2a. Build up 4 commits on main"
run "rm -rf /tmp/git-lab2 && mkdir -p /tmp/git-lab2"
cd /tmp/git-lab2
run "git init -b main"
run "git config user.name 'BinaryBhakti'"
run "git config user.email 'ashmitknayak@gmail.com'"
run "echo '# My Project' > README.md && git add . && git commit -m 'M1: initial commit with README'"
run "echo 'body { margin: 0; }' > style.css && git add . && git commit -m 'M2: add stylesheet'"
run "echo 'console.log(\"app\");' > app.js && git add . && git commit -m 'M3: add app.js'"
run "echo 'node_modules/' > .gitignore && git add . && git commit -m 'M4: add gitignore'"

sec "2b. View the commits on main with git log"
run "git log --oneline"
run "git log --oneline --graph --decorate"
run "git log --pretty=format:'%h | %an | %ar | %s' && echo"

sec "2c. Create a new branch and add 3 commits to it"
run "git checkout -b feature-branch"
run "git branch"
run "echo 'function login() {}' > auth.js && git add . && git commit -m 'F1: add authentication module'"
run "echo 'CRITICAL BUGFIX: fixed null pointer' > bugfix.txt && git add . && git commit -m 'F2: HOTFIX - fix null pointer crash'"
run "echo '<h1>New Dashboard</h1>' > dashboard.html && git add . && git commit -m 'F3: add dashboard page (not ready for main)'"

sec "2d. Use git log to identify the SPECIFIC commit we want"
run "git log --oneline"
echo "-- We want ONLY 'F2: HOTFIX' on main. We do NOT want F1 or F3. --"
run "git log --oneline --grep='HOTFIX'"
HOTFIX_SHA=$(git log --format=%H --grep='HOTFIX')
echo "Full SHA of the commit to cherry-pick: $HOTFIX_SHA"
echo "Short SHA: ${HOTFIX_SHA:0:7}"
echo
run "git show --stat $HOTFIX_SHA"

sec "2e. Compare the two branches BEFORE the cherry-pick"
run "git checkout main"
run "ls -1"
echo "-- main does NOT have auth.js, bugfix.txt or dashboard.html --"
run "git log --oneline --all --graph --decorate"

sec "2f. THE CHERRY-PICK  --  bring just that one commit into main"
run "git cherry-pick $HOTFIX_SHA"

sec "2g. VERIFY the change is now on main"
run "git log --oneline"
echo "-- Note: F2 appears on main with a NEW hash (it is a copy, not a move) --"
run "ls -1"
run "cat bugfix.txt"
echo "-- bugfix.txt is present on main. --"
echo
echo "-- And F1 / F3 did NOT come along: --"
run "test -f auth.js && echo 'auth.js present (WRONG)' || echo 'auth.js absent (CORRECT)'"
run "test -f dashboard.html && echo 'dashboard.html present (WRONG)' || echo 'dashboard.html absent (CORRECT)'"

sec "2h. The full picture"
run "git log --oneline --all --graph --decorate"
run "git branch -v"
echo "-- Same content, different SHAs (cherry-pick REPLAYS the diff): --"
run "git log --format='%h %s' -1 main"
run "git log --format='%h %s' --grep='HOTFIX' feature-branch"
run "git show --stat HEAD"

sec "2i. Useful cherry-pick variants (reference)"
cat <<'REF'
  git cherry-pick <sha>              # apply one commit
  git cherry-pick <sha1> <sha2>      # apply several commits
  git cherry-pick <sha1>..<sha2>     # apply a RANGE (exclusive of sha1)
  git cherry-pick <sha1>^..<sha2>    # apply a RANGE (inclusive of sha1)
  git cherry-pick -n <sha>           # apply but do NOT commit (stage only)
  git cherry-pick -x <sha>           # add "(cherry picked from ...)" to message
  git cherry-pick --continue         # after resolving a conflict
  git cherry-pick --abort            # cancel and go back
  git cherry-pick --skip             # skip the current commit
REF
echo
run "git cherry-pick -n \$(git log --format=%H --grep='F1' feature-branch)"
run "git status --short"
run "git cherry-pick --abort 2>/dev/null || git reset --hard HEAD"
run "git status --short"
run "git log --oneline"

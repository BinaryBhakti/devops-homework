# Homework 4 — Git

**Task 1:** practise `git commit -a -m` and understand how it differs from `git commit -m`.
**Task 2:** create commits on `main` and on a branch, then cherry-pick one specific commit
across.

Everything below was executed in throwaway repositories. **All output blocks are extracted
verbatim** from [`outputs/git-commands.txt`](outputs/git-commands.txt); the script that
produced them is [`scripts/git-lab.sh`](scripts/git-lab.sh).

---

# Task 1 — `git commit -m` vs `git commit -a -m`

## The short answer
```
git commit -a -m "msg"   ==   git add -u  +  git commit -m "msg"
```

`-a` automatically stages **modifications and deletions of files git already tracks**.
It does **not** stage **new (untracked) files** — those always need an explicit `git add`.

## The three-area model
```
   Working directory  ──git add──▶  Staging area (index)  ──git commit──▶  Repository
        (your edits)                   (what will go in)                    (history)

   git commit -m      : commits ONLY what is already staged
   git commit -a -m   : first stages every TRACKED file that changed, then commits
                        (untracked files are still skipped)
```

## Setup and the first commit

A brand-new file is **untracked**, and `-a` cannot see it:

```console
$ git status --short
?? file1.txt
```

`??` means untracked. Try to commit it with `-a`:

```console
$ git commit -a -m 'try to commit an untracked file with -a'
On branch main

Initial commit

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	file1.txt

nothing added to commit but untracked files present (use "git add" to track)
```

Nothing was committed. Untracked files are invisible to `-a`. Stage it explicitly:

```console
$ git add file1.txt
$ git status --short
A  file1.txt

$ git commit -m 'C1: add file1.txt'
[main (root-commit) f424497] C1: add file1.txt
 1 file changed, 1 insertion(+)
 create mode 100644 file1.txt
```

`A` in the first column means staged/added.

## Modify a tracked file — now the difference shows

```console
$ echo 'v2: modified content' >> file1.txt
$ git status --short
 M file1.txt
```

`' M'` (a **space** then `M`) means modified in the working directory but **not staged**.
The position of the letter matters: first column = staged, second column = unstaged.

Plain `git commit -m` refuses, because nothing is staged:

```console
$ git commit -m 'C2: plain commit with nothing staged'
On branch main
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   file1.txt

no changes added to commit (use "git add" and/or "git commit -a")
```

Note git's own hint at the end: *"use `git add` and/or `git commit -a`"*. With `-a` it just
works:

```console
$ git commit -a -m 'C2: modify file1.txt using commit -a -m'
[main 35b40f7] C2: modify file1.txt using commit -a -m
 1 file changed, 1 insertion(+)
$ git status --short
```

The working tree is clean — `-a` did the `git add` for us, but only on the **tracked** file.

## The decisive test: one tracked change + one untracked file

```console
$ git status --short
 M file1.txt
?? file2_untracked.txt
```

- `' M file1.txt'` — tracked and modified → `-a` **will** commit it
- `'?? file2_untracked.txt'` — untracked → `-a` will **ignore** it

```console
$ git commit -a -m 'C3: -a picks up file1 but ignores the untracked file'
[main cee8e3f] C3: -a picks up file1 but ignores the untracked file
 1 file changed, 1 insertion(+)

$ git show --stat --oneline HEAD
cee8e3f C3: -a picks up file1 but ignores the untracked file
 file1.txt | 1 +
 1 file changed, 1 insertion(+)

$ git status --short
?? file2_untracked.txt
```

The commit contained **only** `file1.txt` — one file changed — and `file2_untracked.txt` is
still sitting there untracked afterwards. It needs the explicit two-step:

```console
$ git add file2_untracked.txt && git commit -m 'C4: explicitly add and commit file2'
[main cd85ff7] C4: explicitly add and commit file2
 1 file changed, 1 insertion(+)
 create mode 100644 file2_untracked.txt
$ git status --short
```

## What about a deleted file?

```console
$ rm file3.txt
$ git status --short
 D file3.txt
```

`' D'` = deleted in the working tree, deletion not staged. `-a` handles this too:

```console
$ git commit -a -m 'C6: -a also stages DELETIONS of tracked files'
[main b0fc8b5] C6: -a also stages DELETIONS of tracked files
 1 file changed, 1 deletion(-)
 delete mode 100644 file3.txt
$ git status --short
```

That is the part people forget: **`-a` stages deletions as well as modifications**, because
both are changes to files git already tracks.

## The six commits produced

```console
$ git log --oneline
b0fc8b5 C6: -a also stages DELETIONS of tracked files
4004748 C5: add file3.txt
cd85ff7 C4: explicitly add and commit file2
cee8e3f C3: -a picks up file1 but ignores the untracked file
35b40f7 C2: modify file1.txt using commit -a -m
f424497 C1: add file1.txt
```

## Summary

| Change type | `git commit -m` | `git commit -a -m` |
|---|---|---|
| New / untracked file | needs `git add` first | **ignored** — still needs `git add` |
| Modified tracked file | needs `git add` first | auto-staged ✓ |
| Deleted tracked file | needs `git add`/`git rm` | auto-staged ✓ |
| Already-staged changes | commits them | commits them |

**When to use which**

- `git commit -a -m "msg"` — quick commit of edits to existing files. Convenient, but it
  commits *everything* tracked that you changed, including edits you may not have meant to
  include.
- `git add <specific files>` then `git commit -m "msg"` — deliberate, reviewable commits.
  This is the better habit for real work, and the only option when adding new files.
- `git commit` with no `-m` opens your editor, which is how you write a proper multi-line
  commit message (subject line, blank line, body).

> **Common interview trap:** "Does `git commit -a` commit everything?" — No. It commits every
> **tracked** change. A brand-new file is untracked and will be silently left out.

<details>
<summary><b>Full Task 1 transcript</b> (click to expand)</summary>

```console

===================================================
  SETUP: create a fresh repository
===================================================
$ git init -b main
Initialized empty Git repository in /private/tmp/git-lab/.git/

$ git config user.name 'BinaryBhakti'

$ git config user.email 'ashmitknayak@gmail.com'

###################################################################
#  TASK 1:  git commit -m   vs   git commit -a -m
###################################################################

===================================================
  1a. First commit -- a brand new file MUST be staged with git add
===================================================
$ echo 'v1: initial content' > file1.txt

$ git status --short
?? file1.txt

-- '??' means UNTRACKED. git commit -a will NOT pick this up: --
$ git commit -a -m 'try to commit an untracked file with -a'
On branch main

Initial commit

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	file1.txt

nothing added to commit but untracked files present (use "git add" to track)

-- Nothing was committed. Untracked files are invisible to -a. --
$ git add file1.txt

$ git status --short
A  file1.txt

-- 'A' means staged/Added. Now it can be committed: --
$ git commit -m 'C1: add file1.txt'
[main (root-commit) f424497] C1: add file1.txt
 1 file changed, 1 insertion(+)
 create mode 100644 file1.txt

$ git log --oneline
f424497 C1: add file1.txt


===================================================
  1b. Modify a TRACKED file -- now compare the two commands
===================================================
$ echo 'v2: modified content' >> file1.txt

$ cat file1.txt
v1: initial content
v2: modified content

$ git status --short
 M file1.txt

-- ' M' (space then M) = modified in WORKING DIRECTORY but NOT staged --

-- Try plain 'git commit -m' with nothing staged: --
$ git commit -m 'C2: plain commit with nothing staged'
On branch main
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   file1.txt

no changes added to commit (use "git add" and/or "git commit -a")

-- It REFUSED: 'no changes added to commit'. --

-- Now the same situation with -a, which auto-stages tracked files: --
$ git commit -a -m 'C2: modify file1.txt using commit -a -m'
[main 35b40f7] C2: modify file1.txt using commit -a -m
 1 file changed, 1 insertion(+)

$ git log --oneline
35b40f7 C2: modify file1.txt using commit -a -m
f424497 C1: add file1.txt

$ git status --short

-- Working tree is clean. -a did 'git add' for us on TRACKED files. --

===================================================
  1c. Side-by-side proof with a tracked file AND an untracked file
===================================================
$ echo 'v3: third change' >> file1.txt

$ echo 'brand new, never tracked' > file2_untracked.txt

$ git status --short
 M file1.txt
?? file2_untracked.txt

-- ' M file1.txt'  = tracked + modified  -> -a WILL commit it
-- '?? file2_untracked.txt' = untracked  -> -a will IGNORE it

$ git commit -a -m 'C3: -a picks up file1 but ignores the untracked file'
[main cee8e3f] C3: -a picks up file1 but ignores the untracked file
 1 file changed, 1 insertion(+)

$ git show --stat --oneline HEAD
cee8e3f C3: -a picks up file1 but ignores the untracked file
 file1.txt | 1 +
 1 file changed, 1 insertion(+)

$ git status --short
?? file2_untracked.txt

-- Confirmed: file2_untracked.txt is STILL untracked after commit -a. --
$ git add file2_untracked.txt && git commit -m 'C4: explicitly add and commit file2'
[main cd85ff7] C4: explicitly add and commit file2
 1 file changed, 1 insertion(+)
 create mode 100644 file2_untracked.txt

$ git status --short

$ git log --oneline
cd85ff7 C4: explicitly add and commit file2
cee8e3f C3: -a picks up file1 but ignores the untracked file
35b40f7 C2: modify file1.txt using commit -a -m
f424497 C1: add file1.txt


===================================================
  1d. What about a DELETED tracked file?
===================================================
$ echo 'delete me later' > file3.txt && git add file3.txt && git commit -m 'C5: add file3.txt'
[main 4004748] C5: add file3.txt
 1 file changed, 1 insertion(+)
 create mode 100644 file3.txt

$ rm file3.txt

$ git status --short
 D file3.txt

-- ' D' = deleted in working tree, deletion not staged --
$ git commit -a -m 'C6: -a also stages DELETIONS of tracked files'
[main b0fc8b5] C6: -a also stages DELETIONS of tracked files
 1 file changed, 1 deletion(-)
 delete mode 100644 file3.txt

$ git status --short

$ git log --oneline
b0fc8b5 C6: -a also stages DELETIONS of tracked files
4004748 C5: add file3.txt
cd85ff7 C4: explicitly add and commit file2
cee8e3f C3: -a picks up file1 but ignores the untracked file
35b40f7 C2: modify file1.txt using commit -a -m
f424497 C1: add file1.txt


===================================================
  1e. SUMMARY TABLE
===================================================
 +------------------------+---------------------+------------------------+
 | Change type            | git commit -m       | git commit -a -m       |
 +------------------------+---------------------+------------------------+
 | New / untracked file   | needs git add first | IGNORED (needs add)    |
 | Modified tracked file  | needs git add first | auto-staged  [OK]      |
 | Deleted tracked file   | needs git add/rm    | auto-staged  [OK]      |
 | Staged changes         | commits them        | commits them           |
 +------------------------+---------------------+------------------------+
   -a  ==  "git add -u"  (update tracked files)  +  "git commit"

###################################################################
#  TASK 2:  git cherry-pick
###################################################################

===================================================
  2a. Build up 4 commits on main
===================================================
$ rm -rf /tmp/git-lab2 && mkdir -p /tmp/git-lab2

$ git init -b main
Initialized empty Git repository in /private/tmp/git-lab2/.git/

$ git config user.name 'BinaryBhakti'

$ git config user.email 'ashmitknayak@gmail.com'

$ echo '# My Project' > README.md && git add . && git commit -m 'M1: initial commit with README'
[main (root-commit) 3987539] M1: initial commit with README
 1 file changed, 1 insertion(+)
 create mode 100644 README.md

$ echo 'body { margin: 0; }' > style.css && git add . && git commit -m 'M2: add stylesheet'
[main fe03ebd] M2: add stylesheet
 1 file changed, 1 insertion(+)
 create mode 100644 style.css

$ echo 'console.log("app");' > app.js && git add . && git commit -m 'M3: add app.js'
[main 3305b2a] M3: add app.js
 1 file changed, 1 insertion(+)
 create mode 100644 app.js

$ echo 'node_modules/' > .gitignore && git add . && git commit -m 'M4: add gitignore'
[main fc62b41] M4: add gitignore
 1 file changed, 1 insertion(+)
 create mode 100644 .gitignore


===================================================
  2b. View the commits on main with git log
===================================================
$ git log --oneline
fc62b41 M4: add gitignore
3305b2a M3: add app.js
fe03ebd M2: add stylesheet
3987539 M1: initial commit with README

$ git log --oneline --graph --decorate
* fc62b41 (HEAD -> main) M4: add gitignore
* 3305b2a M3: add app.js
* fe03ebd M2: add stylesheet
* 3987539 M1: initial commit with README

$ git log --pretty=format:'%h | %an | %ar | %s' && echo
fc62b41 | BinaryBhakti | 0 seconds ago | M4: add gitignore
3305b2a | BinaryBhakti | 0 seconds ago | M3: add app.js
fe03ebd | BinaryBhakti | 0 seconds ago | M2: add stylesheet
3987539 | BinaryBhakti | 0 seconds ago | M1: initial commit with README


===================================================
  2c. Create a new branch and add 3 commits to it
===================================================
$ git checkout -b feature-branch
Switched to a new branch 'feature-branch'

$ git branch
* feature-branch
  main

$ echo 'function login() {}' > auth.js && git add . && git commit -m 'F1: add authentication module'
[feature-branch 70844d3] F1: add authentication module
 1 file changed, 1 insertion(+)
 create mode 100644 auth.js

$ echo 'CRITICAL BUGFIX: fixed null pointer' > bugfix.txt && git add . && git commit -m 'F2: HOTFIX - fix null pointer crash'
[feature-branch fa73f70] F2: HOTFIX - fix null pointer crash
 1 file changed, 1 insertion(+)
 create mode 100644 bugfix.txt

$ echo '<h1>New Dashboard</h1>' > dashboard.html && git add . && git commit -m 'F3: add dashboard page (not ready for main)'
[feature-branch 07c2511] F3: add dashboard page (not ready for main)
 1 file changed, 1 insertion(+)
 create mode 100644 dashboard.html


===================================================
  2d. Use git log to identify the SPECIFIC commit we want
===================================================
$ git log --oneline
07c2511 F3: add dashboard page (not ready for main)
fa73f70 F2: HOTFIX - fix null pointer crash
70844d3 F1: add authentication module
fc62b41 M4: add gitignore
3305b2a M3: add app.js
fe03ebd M2: add stylesheet
3987539 M1: initial commit with README

-- We want ONLY 'F2: HOTFIX' on main. We do NOT want F1 or F3. --
$ git log --oneline --grep='HOTFIX'
fa73f70 F2: HOTFIX - fix null pointer crash

Full SHA of the commit to cherry-pick: fa73f70feb445e32c2b669f1d4d258ccc1f506be
Short SHA: fa73f70

$ git show --stat fa73f70feb445e32c2b669f1d4d258ccc1f506be
commit fa73f70feb445e32c2b669f1d4d258ccc1f506be
Author: BinaryBhakti <ashmitknayak@gmail.com>
Date:   Thu Sep 3 10:06:24 2026 +0530

    F2: HOTFIX - fix null pointer crash

 bugfix.txt | 1 +
 1 file changed, 1 insertion(+)


===================================================
  2e. Compare the two branches BEFORE the cherry-pick
===================================================
$ git checkout main
Switched to branch 'main'

$ ls -1
README.md
app.js
style.css

-- main does NOT have auth.js, bugfix.txt or dashboard.html --
$ git log --oneline --all --graph --decorate
* 07c2511 (feature-branch) F3: add dashboard page (not ready for main)
* fa73f70 F2: HOTFIX - fix null pointer crash
* 70844d3 F1: add authentication module
* fc62b41 (HEAD -> main) M4: add gitignore
* 3305b2a M3: add app.js
* fe03ebd M2: add stylesheet
* 3987539 M1: initial commit with README


===================================================
  2f. THE CHERRY-PICK  --  bring just that one commit into main
===================================================
$ git cherry-pick fa73f70feb445e32c2b669f1d4d258ccc1f506be
[main b6ce554] F2: HOTFIX - fix null pointer crash
 Date: Thu Sep 3 10:06:24 2026 +0530
 1 file changed, 1 insertion(+)
 create mode 100644 bugfix.txt


===================================================
  2g. VERIFY the change is now on main
===================================================
$ git log --oneline
b6ce554 F2: HOTFIX - fix null pointer crash
fc62b41 M4: add gitignore
3305b2a M3: add app.js
fe03ebd M2: add stylesheet
3987539 M1: initial commit with README

-- Note: F2 appears on main with a NEW hash (it is a copy, not a move) --
$ ls -1
README.md
app.js
bugfix.txt
style.css

$ cat bugfix.txt
CRITICAL BUGFIX: fixed null pointer

-- bugfix.txt is present on main. --

-- And F1 / F3 did NOT come along: --
$ test -f auth.js && echo 'auth.js present (WRONG)' || echo 'auth.js absent (CORRECT)'
auth.js absent (CORRECT)

$ test -f dashboard.html && echo 'dashboard.html present (WRONG)' || echo 'dashboard.html absent (CORRECT)'
dashboard.html absent (CORRECT)


===================================================
  2h. The full picture
===================================================
$ git log --oneline --all --graph --decorate
* 07c2511 (feature-branch) F3: add dashboard page (not ready for main)
* fa73f70 F2: HOTFIX - fix null pointer crash
* 70844d3 F1: add authentication module
| * b6ce554 (HEAD -> main) F2: HOTFIX - fix null pointer crash
|/  
* fc62b41 M4: add gitignore
* 3305b2a M3: add app.js
* fe03ebd M2: add stylesheet
* 3987539 M1: initial commit with README

$ git branch -v
  feature-branch 07c2511 F3: add dashboard page (not ready for main)
* main           b6ce554 F2: HOTFIX - fix null pointer crash

-- Same content, different SHAs (cherry-pick REPLAYS the diff): --
$ git log --format='%h %s' -1 main
b6ce554 F2: HOTFIX - fix null pointer crash

$ git log --format='%h %s' --grep='HOTFIX' feature-branch
fa73f70 F2: HOTFIX - fix null pointer crash

$ git show --stat HEAD
commit b6ce554af2fb604aa9395f887f0ed27526cd955f
Author: BinaryBhakti <ashmitknayak@gmail.com>
Date:   Thu Sep 3 10:06:24 2026 +0530

    F2: HOTFIX - fix null pointer crash

 bugfix.txt | 1 +
 1 file changed, 1 insertion(+)


===================================================
  2i. Useful cherry-pick variants (reference)
===================================================
  git cherry-pick <sha>              # apply one commit
  git cherry-pick <sha1> <sha2>      # apply several commits
  git cherry-pick <sha1>..<sha2>     # apply a RANGE (exclusive of sha1)
  git cherry-pick <sha1>^..<sha2>    # apply a RANGE (inclusive of sha1)
  git cherry-pick -n <sha>           # apply but do NOT commit (stage only)
  git cherry-pick -x <sha>           # add "(cherry picked from ...)" to message
  git cherry-pick --continue         # after resolving a conflict
  git cherry-pick --abort            # cancel and go back
  git cherry-pick --skip             # skip the current commit

$ git cherry-pick -n $(git log --format=%H --grep='F1' feature-branch)

$ git status --short
A  auth.js

$ git cherry-pick --abort 2>/dev/null || git reset --hard HEAD
HEAD is now at b6ce554 F2: HOTFIX - fix null pointer crash

$ git status --short

$ git log --oneline
b6ce554 F2: HOTFIX - fix null pointer crash
fc62b41 M4: add gitignore
3305b2a M3: add app.js
fe03ebd M2: add stylesheet
3987539 M1: initial commit with README
```

</details>

---

# Task 2 — `git cherry-pick`

## What cherry-pick does

`git cherry-pick <sha>` takes the **diff introduced by one commit** and replays it on top of
your current branch, creating a **new commit with a new SHA**. It is a copy, not a move: the
original commit stays exactly where it was.

Use it when you need *one* change from a branch — typically an urgent hotfix — without merging
everything else that branch contains.
```
   before                              after cherry-picking F2 onto main

   feature ● F1                        feature ● F1
           ● F2  (want this)                   ● F2
           ● F3                                ● F3
          /                                   /
   main  ● M4                          main  ● M4
         ● M3                                ● M3   ● F2'  <- NEW sha, same change
```

## Build 4 commits on `main`

```console
$ git init -b main
Initialized empty Git repository in /private/tmp/git-lab2/.git/
$ echo '# My Project' > README.md && git add . && git commit -m 'M1: initial commit with README'
[main (root-commit) 3987539] M1: initial commit with README
 1 file changed, 1 insertion(+)
 create mode 100644 README.md

$ echo 'body { margin: 0; }' > style.css && git add . && git commit -m 'M2: add stylesheet'
[main fe03ebd] M2: add stylesheet
 1 file changed, 1 insertion(+)
 create mode 100644 style.css

$ echo 'console.log("app");' > app.js && git add . && git commit -m 'M3: add app.js'
[main 3305b2a] M3: add app.js
 1 file changed, 1 insertion(+)
 create mode 100644 app.js

$ echo 'node_modules/' > .gitignore && git add . && git commit -m 'M4: add gitignore'
[main fc62b41] M4: add gitignore
 1 file changed, 1 insertion(+)
 create mode 100644 .gitignore
```

## View them with `git log`

```console
$ git log --oneline
fc62b41 M4: add gitignore
3305b2a M3: add app.js
fe03ebd M2: add stylesheet
3987539 M1: initial commit with README

$ git log --pretty=format:'%h | %an | %ar | %s' && echo
fc62b41 | BinaryBhakti | 0 seconds ago | M4: add gitignore
3305b2a | BinaryBhakti | 0 seconds ago | M3: add app.js
fe03ebd | BinaryBhakti | 0 seconds ago | M2: add stylesheet
3987539 | BinaryBhakti | 0 seconds ago | M1: initial commit with README
```

| `git log` option | What it shows |
|---|---|
| `--oneline` | one compact line per commit |
| `--graph` | ASCII branch/merge graph |
| `--decorate` | branch and tag names |
| `--all` | every branch, not just the current one |
| `-n 5` | limit to 5 commits |
| `--grep='text'` | only commits whose message matches |
| `--pretty=format:'%h %an %ar %s'` | custom output (hash, author, relative date, subject) |
| `-p` | show the full patch for each commit |
| `--stat` | show which files changed and by how much |

## Create a branch and add 3 commits

```console
$ git checkout -b feature-branch
Switched to a new branch 'feature-branch'
$ git branch
* feature-branch
  main

$ echo 'function login() {}' > auth.js && git add . && git commit -m 'F1: add authentication module'
[feature-branch 70844d3] F1: add authentication module
 1 file changed, 1 insertion(+)
 create mode 100644 auth.js

$ echo 'CRITICAL BUGFIX: fixed null pointer' > bugfix.txt && git add . && git commit -m 'F2: HOTFIX - fix null pointer crash'
[feature-branch fa73f70] F2: HOTFIX - fix null pointer crash
 1 file changed, 1 insertion(+)
 create mode 100644 bugfix.txt

$ echo '<h1>New Dashboard</h1>' > dashboard.html && git add . && git commit -m 'F3: add dashboard page (not ready for main)'
[feature-branch 07c2511] F3: add dashboard page (not ready for main)
 1 file changed, 1 insertion(+)
 create mode 100644 dashboard.html
```

## Use `git log` to identify the specific commit

```console
$ git log --oneline
07c2511 F3: add dashboard page (not ready for main)
fa73f70 F2: HOTFIX - fix null pointer crash
70844d3 F1: add authentication module
fc62b41 M4: add gitignore
3305b2a M3: add app.js
fe03ebd M2: add stylesheet
3987539 M1: initial commit with README
```

We want **only** `F2: HOTFIX` on main. `F1` and `F3` must stay behind. Find it by message:

```console
$ git log --oneline --grep='HOTFIX'
fa73f70 F2: HOTFIX - fix null pointer crash

Full SHA of the commit to cherry-pick: fa73f70feb445e32c2b669f1d4d258ccc1f506be
Short SHA: fa73f70
```

Getting the full SHA into a variable, which is what the script did:

```bash
HOTFIX_SHA=$(git log --format=%H --grep='HOTFIX')
# -> fa73f70feb445e32c2b669f1d4d258ccc1f506be   (short: fa73f70)
```

And inspecting what that commit actually changes before picking it:

```console
$ git show --stat fa73f70feb445e32c2b669f1d4d258ccc1f506be
commit fa73f70feb445e32c2b669f1d4d258ccc1f506be
Author: BinaryBhakti <ashmitknayak@gmail.com>
Date:   Thu Sep 3 10:06:24 2026 +0530

    F2: HOTFIX - fix null pointer crash

 bugfix.txt | 1 +
 1 file changed, 1 insertion(+)
```

## The state of `main` before the cherry-pick

```console
$ git checkout main
Switched to branch 'main'
$ ls -1
README.md
app.js
style.css
```

`main` has none of the branch's files. The graph shows the two lines of development:

```console
$ git log --oneline --all --graph --decorate
* 07c2511 (feature-branch) F3: add dashboard page (not ready for main)
* fa73f70 F2: HOTFIX - fix null pointer crash
* 70844d3 F1: add authentication module
* fc62b41 (HEAD -> main) M4: add gitignore
* 3305b2a M3: add app.js
* fe03ebd M2: add stylesheet
* 3987539 M1: initial commit with README
```

## The cherry-pick

```console
$ git cherry-pick fa73f70feb445e32c2b669f1d4d258ccc1f506be
[main b6ce554] F2: HOTFIX - fix null pointer crash
 Date: Thu Sep 3 10:06:24 2026 +0530
 1 file changed, 1 insertion(+)
 create mode 100644 bugfix.txt
```

## Verify the change is now on `main`

```console
$ git log --oneline
b6ce554 F2: HOTFIX - fix null pointer crash
fc62b41 M4: add gitignore
3305b2a M3: add app.js
fe03ebd M2: add stylesheet
3987539 M1: initial commit with README
```

`F2` is on `main` — but look closely at the hash. On the branch it was `fa73f70`; on `main` it
is `b6ce554`. **Cherry-pick creates a new commit** with the same message and the same change,
but a different SHA, because the parent commit is different.

The file is really there:

```console
$ ls -1
README.md
app.js
bugfix.txt
style.css

$ cat bugfix.txt
CRITICAL BUGFIX: fixed null pointer
```

And crucially, `F1` and `F3` did **not** come along:

```console
$ test -f auth.js && echo 'auth.js present (WRONG)' || echo 'auth.js absent (CORRECT)'
auth.js absent (CORRECT)

$ test -f dashboard.html && echo 'dashboard.html present (WRONG)' || echo 'dashboard.html absent (CORRECT)'
dashboard.html absent (CORRECT)
```

## The full picture

```console
$ git log --oneline --all --graph --decorate
* 07c2511 (feature-branch) F3: add dashboard page (not ready for main)
* fa73f70 F2: HOTFIX - fix null pointer crash
* 70844d3 F1: add authentication module
| * b6ce554 (HEAD -> main) F2: HOTFIX - fix null pointer crash
|/  
* fc62b41 M4: add gitignore
* 3305b2a M3: add app.js
* fe03ebd M2: add stylesheet
* 3987539 M1: initial commit with README

$ git branch -v
  feature-branch 07c2511 F3: add dashboard page (not ready for main)
* main           b6ce554 F2: HOTFIX - fix null pointer crash
```

The graph says it all: `feature-branch` still holds `F1 → F2 → F3`, while `main` gained a
single new commit carrying only the `F2` change.

## Cherry-pick variants

| Command | Effect |
|---|---|
| `git cherry-pick <sha>` | apply one commit |
| `git cherry-pick <sha1> <sha2>` | apply several commits |
| `git cherry-pick <sha1>..<sha2>` | apply a range, **excluding** `sha1` |
| `git cherry-pick <sha1>^..<sha2>` | apply a range, **including** `sha1` |
| `git cherry-pick -n <sha>` | apply but do **not** commit (stage only) |
| `git cherry-pick -x <sha>` | append `(cherry picked from commit ...)` to the message |
| `git cherry-pick --continue` | carry on after resolving a conflict |
| `git cherry-pick --abort` | cancel and return to the previous state |
| `git cherry-pick --skip` | skip the current commit in a multi-commit pick |

`-n` demonstrated — the change is staged but not committed, then abandoned:

```console
$ git cherry-pick -n $(git log --format=%H --grep='F1' feature-branch)
$ git status --short
A  auth.js

$ git cherry-pick --abort 2>/dev/null || git reset --hard HEAD
HEAD is now at b6ce554 F2: HOTFIX - fix null pointer crash
$ git status --short

$ git log --oneline
b6ce554 F2: HOTFIX - fix null pointer crash
fc62b41 M4: add gitignore
3305b2a M3: add app.js
fe03ebd M2: add stylesheet
3987539 M1: initial commit with README
```

Back to exactly where we were — `auth.js` is gone again and `main` still has its five commits.

## Notes and cautions

- **Cherry-pick duplicates commits.** If you cherry-pick from a branch and later merge that
  same branch, git usually notices the identical change, but you can end up with the same work
  recorded twice in the history.
- **Conflicts happen** when the target branch has diverged. Git stops, you fix the files,
  `git add` them, then `git cherry-pick --continue`.
- **`-x` is good manners** on shared branches: it records where the commit came from.
- **Prefer merge or rebase** for whole branches. Cherry-pick is for the one-off case — a hotfix
  that must ship now, or rescuing a commit made on the wrong branch.

<details>
<summary><b>Full Task 2 transcript</b> (click to expand)</summary>

```console
```

</details>

---

## Reproducing this

```bash
bash scripts/git-lab.sh
```

It creates `/tmp/git-lab` (Task 1) and `/tmp/git-lab2` (Task 2) from scratch, so it is safe to
re-run and touches nothing else.

# Security Policy

## What this repository is

A Godot 4.7 game demo. It is **public**, and it deliberately ships a runnable
Windows binary so that partners can play without installing an engine.

That second fact is the whole risk model, so it is worth stating plainly:

* The repository contains **executable code** — GDScript that Godot runs the
  moment the project is opened.
* The repository contains **a distributable artifact** — `release/RTSDemo-win64.zip`
  is what other people download and run.

Anyone on the internet can open a pull request against a public repository.
They **cannot** push to `main` directly. The single point where untrusted code
can enter this project is the moment a pull request is merged — which is a
decision you make, and the reason the tooling below exists.

## Rules for this repository

1. **Only the owner merges.** No one else has write access.
2. **Never run an unmerged pull request locally.** Godot executes GDScript on
   project open. A pull request that edits `project.godot` (autoloads, main
   scene) or adds a `.gd` file runs code on your machine the moment you press
   F5. Read the diff first; if you must try it, use a throwaway copy outside
   this repository.
3. **Treat `release/*.zip` as critical.** A pull request that replaces the
   archive replaces what every partner downloads. Extract and run it somewhere
   disposable before you tell anyone to download it.
4. **Never merge without reviewing.** Use the helper:

   ```powershell
   powershell -File tools/check_pr.ps1 -Base origin/main -Head <pr-branch>
   ```

   It classifies every changed file by risk, flags the executable and
   distributable ones, and verifies the published SHA-256 checksum.
5. **Do not use `git add -A -f` here.** It overrides `.gitignore` and will
   sweep `.godot/` and `build/` into a commit.
6. **No secrets in this repository.** There are none today, and there should
   never be any. Use environment variables or GitHub Actions secrets if that
   ever changes.

## Verifying a download

The published archive ships with its own checksum:

```
release/RTSDemo-win64.zip.sha256
```

```powershell
Get-FileHash release\RTSDemo-win64.zip -Algorithm SHA256
```

If you downloaded the archive from GitHub and the hash matches the file in the
repository at the same commit, the bytes are the ones that were built.

## Reporting a problem

Open an issue for ordinary bugs. For anything that looks like an attempt to
smuggle code or a tampered binary into the repository, contact the owner
privately instead of opening a public issue.

## Hardening the repository (owner only)

These are the settings that actually enforce the rules above. They live in the
GitHub UI, under **Settings**:

| Where | What | Why |
|---|---|---|
| Branches → `main` → *Add rule* | Require a pull request before merging | Nobody, including a compromised collaborator, can push straight to `main` |
| same rule | Require approvals: 1, and **do not allow bypassing** | Forces the review even when you are both author and reviewer |
| same rule | Require status checks / require branches to be up to date | A stale branch cannot slip through |
| General → Features | Untick *Allow edits and invitations for all public forks* | Stops outsiders editing your repository after forking |
| Collaborators | Keep the list to yourself | Every added collaborator is another person who can push |
| Security → 2FA | Enable two-factor authentication | The single biggest lever on your account |
| Settings → Notifications | Email me for pushes and pull requests | You find out about a push the moment it happens |
| Developer settings | Audit personal access tokens and SSH keys | Revoke anything you do not recognise |

The most important one is **2FA on your GitHub account**. A leaked personal
access token can bypass every repository rule above.

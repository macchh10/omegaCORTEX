# Environment setup

One-time setup. Roughly 45 minutes total. Do Part A on the Mac mini first, since everything else depends on it.

The model: **the Mac mini is the only place work happens.** Every other device reaches it. Nothing is duplicated, so nothing can drift out of sync.

```
GitHub repo  ──  docs, scripts, workflow JSON        follows you everywhere
Mac mini     ──  n8n, database, LaunchAgents         the only running instance
Tailscale    ──  private network                     reach the mini from anywhere
```

---

# Part A — Mac mini (do this first)

## A1. Stop it from sleeping

A sleeping mini means the 5:20 and 6:00 AM runs are silently skipped. n8n does **not** catch up missed schedule triggers.

```bash
sudo pmset -a sleep 0
sudo pmset -a disksleep 0
sudo pmset repeat wakeorpoweron MTWRFSU 05:00:00
```

Verify:

```bash
pmset -g sched
pmset -g custom | grep -E " sleep|disksleep"
```

Expect `wakepoweron at 5:00AM every day` and `sleep 0`. The display can still sleep, that's fine and doesn't affect anything.

## A2. Turn on Remote Login

System Settings → General → Sharing → **Remote Login** on.

Note the username shown. Then confirm from Terminal:

```bash
sudo systemsetup -getremotelogin
```

Expect `Remote Login: On`.

## A3. Install Tailscale

Download from [tailscale.com/download](https://tailscale.com/download), install, sign in. Free for personal use.

```bash
tailscale status
tailscale ip -4
```

Note the machine name it reports. That name is how every other device reaches this box, from anywhere, without exposing anything to the public internet.

Optional but recommended, so you never chase a changing name:

```bash
sudo tailscale set --hostname=macmini
```

## A4. Put the repo in place

```bash
cd ~/Documents
tar -xzf ~/Downloads/omegacortex-agent.tar.gz
cd omegacortex-agent
chmod +x scripts/*.sh scripts/*.py
./scripts/health-check.sh
```

## A5. Push to GitHub, private

```bash
./scripts/scan-secrets.sh
gh auth status || gh auth login
gh repo create omegacortex-agent --private --source=. --push
```

**Private is mandatory.** These docs expose your SAM.gov query structure, agency targeting, and scoring model.

## A6. Make the secret scanner a hard gate

```bash
cat > .git/hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
exec "$(git rev-parse --show-toplevel)/scripts/scan-secrets.sh"
EOF
chmod +x .git/hooks/pre-commit
```

Git hooks are not committed, so install this on every machine where you commit.

## A7. Nightly automated backup

**Do this only after Phase 0.2 removes and rotates the SAM.gov API key.** Committing workflow JSON before then writes the key into git history, where deleting it later does not remove it.

```bash
cp scripts/com.omegacortex.backup.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/501 ~/Library/LaunchAgents/com.omegacortex.backup.plist
```

Test it immediately rather than waiting until 11:30 PM:

```bash
launchctl kickstart -k gui/501/com.omegacortex.backup
sleep 30
tail -30 ~/Library/Logs/omegacortex-backup.log
```

It exports, decodes any BLOB corruption, verifies, scans for secrets, and commits and pushes only when something actually changed.

---

# Part B — MacBook Pro

## B1. Tailscale

Install and sign in with the **same account** as the mini.

```bash
tailscale status
```

You should see the mini listed.

## B2. SSH shortcut

```bash
cat >> ~/.ssh/config <<'EOF'

Host macmini
  HostName macmini
  User luislozada
  ServerAliveInterval 60
EOF
```

Replace `HostName` with whatever `tailscale status` shows if you didn't set the hostname in A3.

Test:

```bash
ssh macmini
```

First connection asks you to accept the host key. After that it's instant.

For passwordless login:

```bash
ssh-keygen -t ed25519          # skip if you already have a key
ssh-copy-id macmini
```

## B3. Clone the repo

For reading docs, editing scoring logic, drafting proposals. Anything that doesn't touch the running n8n.

```bash
cd ~/Documents
gh repo clone omegacortex-agent
cd omegacortex-agent
cat > .git/hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
exec "$(git rev-parse --show-toplevel)/scripts/scan-secrets.sh"
EOF
chmod +x .git/hooks/pre-commit
```

---

# Part C — Quality of life

Add to `~/.zshrc` on **both** machines:

```bash
# OMEGACORTEX
export OMEGA=~/Documents/omegacortex-agent
alias omega='cd $OMEGA'
alias omega-status='cd $OMEGA && git pull -q && head -40 docs/SESSION-LOG.md'
alias omega-health='cd $OMEGA && ./scripts/health-check.sh'
alias omega-mini='ssh macmini -t "cd ~/Documents/omegacortex-agent && exec \$SHELL -l"'
alias omega-ui='open http://macmini:5678'
```

Then `source ~/.zshrc`.

On the MacBook, `omega-mini` drops you straight into the repo on the mini in one command.

---

# Part D — Daily rhythm

**Starting anywhere:**

```bash
omega-status        # pull and read the last handoff
omega-health        # what is actually true right now
```

Trust the health check over the log. The log says what someone believed. The health check says what is running.

**Working on the pipeline** (must be on the mini):

```bash
omega-mini          # from the MacBook, or just omega on the mini
claude
```

**Ending, every time:**

```bash
./scripts/health-check.sh
./scripts/scan-secrets.sh
# update docs/STATUS.md
# append an entry to docs/SESSION-LOG.md
git add -A && git commit && git push
```

Full rules in [`HANDOFF-PROTOCOL.md`](HANDOFF-PROTOCOL.md).

---

# What goes where

| Task | Where | Why |
|---|---|---|
| Fix a workflow, run n8n CLI, check executions | Mac mini, directly or over SSH | n8n only exists there |
| Read docs, check status, review a handoff | Any device | It's in the repo |
| Write Phase 3 scoring logic, edit scripts | Any device, run on the mini | Pure code, portable |
| Draft proposals, research solicitations | Any device, including a cloud session | No n8n dependency |
| Emergency triage | SSH to the mini from anywhere | Needs the live instance |

A Claude Code **cloud** environment cannot reach `localhost:5678`, cannot run `n8n export:workflow`, and cannot touch the LaunchAgent. Use it only for work with no n8n dependency.

---

# Verify the whole thing

From the MacBook, off your home network if you can, phone hotspot is fine:

```bash
ssh macmini
cd ~/Documents/omegacortex-agent
./scripts/health-check.sh
```

If that returns UP with the wake schedule confirmed, the setup works. You can now fix the pipeline from anywhere.

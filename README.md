# Make Me an Admin (Jamf Self Service)

Time-boxed local admin rights for macOS users, with automatic demotion and an audit log. Built for Jamf Pro Self Service.

> Forked from [rthannigan/MakeMeAnAdmin](https://github.com/rthannigan/MakeMeAnAdmin) and rewritten: strict mode (`set -euo pipefail`), reliable console-user detection, centralized config, and a self-cleaning LaunchDaemon.

## What it does

1. Detects the logged-in console user (`stat -f%Su /dev/console`, so it doesn't rely on parsing `who`).
2. Adds that user to the `admin` group and shows a confirmation dialog.
3. Installs a LaunchDaemon that fires after 30 minutes of uptime, so the timer survives logouts and reboots.
4. When it fires, the removal script:
   - removes the user from `admin`
   - collects the last 30 minutes of unified logs (`log collect`) for auditing
   - deletes the LaunchDaemon and itself

## Why

It replaces standing admin rights with just-in-time elevation: users can install what they need, IT keeps least privilege, and security gets a log of what happened during the window.

## Configuration

All settings live in the variables block at the top of `MakeMeAnAdmin.sh`:

| Variable | Default | Purpose |
|---|---|---|
| `ADMIN_DURATION_SECONDS` | `1800` | How long admin rights last |
| `LABEL` | `com.company.removeAdmin` | LaunchDaemon label; change to your org's reverse-DNS |
| `USER_STATE_DIR` | `/private/var/userToRemove` | Where the user record and `.logarchive` are saved |

The `--last 30m` value in the removal script sets the log window; keep it in step with `ADMIN_DURATION_SECONDS`.

## Deploying in Jamf Pro

1. **Settings → Scripts → New**, then paste `MakeMeAnAdmin.sh`.
2. Create a policy that runs the script, scoped to the right computers or users.
3. Enable it in **Self Service**.
4. Set **Execution Frequency** to *Once every day* to limit abuse.
5. Optionally, collect `/private/var/userToRemove/*.logarchive` with a follow-up policy or EDR for review.

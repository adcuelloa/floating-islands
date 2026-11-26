# Recovery

Read this before activating. Every command below works without the
graphical shell. The default rollback needs only bash, jq and coreutils.

## The one command

```bash
<repo>/scripts/rollback.sh
```

It does four things:

1. Saves the current `shell.json` as `shell.json.rollback-<timestamp>`.
2. Deselects this bar. It uses `omarchy bar reset` when the CLI is available,
   and otherwise edits `~/.config/omarchy/shell.json` with `jq`.
3. Removes the trial marker.
4. Tells a running shell to reload.

All other configuration is kept: layout, plugins, idle settings and
`bar.islands`. If another third-party bar is selected, it refuses to touch
it unless you pass `--any-bar`.

## From a TTY

1. Press **Ctrl+Alt+F3** and log in.
2. Run `<checkout>/scripts/rollback.sh`, from wherever the repository is checked
   out. Keep a note of that path somewhere you can reach from a TTY.
3. Return with **Ctrl+Alt+F1** (or F2, depending on the session). If the shell
   is running, the stock bar is already back. If it is not, it loads the stock
   bar when it starts. Inside the graphical session, `omarchy restart shell`
   starts it.

From a TTY, `rollback.sh` cannot restart the shell. Once back in the
session, run `omarchy restart shell`. It is not needed for safety, but
panel hotkeys and summons need it.

## Why rollback restarts the shell

Omarchy 4.5.0rc2 hot-swaps back to the stock bar but leaves the shell
without a reference to it (`docs/upstream/shell-bar-null-after-plugin-bar.md`).
The bar draws and takes clicks, but these fail:

- panel hotkeys (`togglePanelAt`);
- `omarchy-shell shell summon <widget>`;
- toast placement.

So whenever the shell is reachable, `rollback.sh` deselects the bar and then
runs `omarchy restart shell`, Omarchy's own controlled restart. That restart:

1. waits for the old instance to exit;
2. relaunches the shell through Hyprland, with the session environment;
3. re-secures the lock screen if the session was locked;
4. waits for the notification service.

The cost: open popups and toasts close, and the bar is briefly absent.
`--no-restart` keeps the hot swap. From a TTY the shell is not reachable, so
the script prints the command to run once back in the session.

## By situation

| Situation | What happens | What to do |
|---|---|---|
| Invalid QML (bad import or syntax) | The shell logs "bar option … failed to load, falling back" and shows the stock bar. `bar.id` still names this bar | `scripts/rollback.sh` to clear it. `tests/imports.sh` and `tests/lint.sh` catch this before activation |
| Loaded but invisible, or misplaced | The shell keeps it. `activate.sh` notices within 5 s (no IPC answer, or no surfaces) and rolls back by itself | Otherwise `scripts/rollback.sh` |
| Hosted widgets inactive after switching bars | Omarchy hot-reload after switching bar identity (from `omarchy.bar` or legacy `islands.bar` to `floating-islands`) can leave hosted status-island widgets inactive. `activate.sh` prints a concise advisory and does not force an automatic restart | Run `omarchy restart shell` explicitly if hosted widgets do not appear or respond |
| The shell died, or loops on start | No bar, no notifications | From a TTY: `scripts/rollback.sh`, then log in again. Without the repository: `jq 'del(.bar.id)' ~/.config/omarchy/shell.json > /tmp/s && mv /tmp/s ~/.config/omarchy/shell.json` |
| After a reboot or re-login during a trial | The bar deselects itself; the stock bar returns | Nothing |
| You want the exact previous configuration | — | `scripts/rollback.sh --restore ~/.config/omarchy/shell.json.pre-floating-islands` (the snapshot `activate.sh` took; legacy pre-migration snapshots used `shell.json.pre-islands.bar`) |
| Remove everything | — | `scripts/uninstall.sh` (deselects first) |

## Testing a build over the persistent bar

When this bar is already the daily bar, a development build is tested with
`scripts/branch-test.sh`, not with a trial. The local-first development loop is:

**Implement → protected preview → owner feedback → correct → validate → explicit acceptance**

```bash
scripts/branch-test.sh --arm 45   # snapshot the installed plugin and shell.json
scripts/install.sh                # install the build under test
omarchy restart shell             # the bar's own QML loads only on a restart
...                               # supervised checks, feedback, corrections, validation
scripts/branch-test.sh --restore  # revert to the previous snapshot and restart the shell
# OR, once satisfied with the validated preview:
scripts/branch-test.sh --accept   # retain this build in place, stop rollback, preserve backup
```

Three different ends:

- **Restore (`--restore`, or the timer at the deadline).** Puts back the
  previous Floating Islands installation and the exact `shell.json`, checked
  against its checksum, then restarts the shell. The bar stays selected.
- **Explicit acceptance (`--accept`).** Retains the currently installed plugin
  and current `~/.config/omarchy/shell.json` byte-for-byte without reinstalling
  or restarting `omarchy-shell`. Acceptance is always an explicit manual
  decision — it never runs automatically on passing tests. Accepting a local
  installation only promotes the already-installed local desktop preview; it is
  separate from committing, pushing, merging, or publishing changes in git.
- **Emergency fallback (`scripts/rollback.sh`).** Returns the *stock* Omarchy
  bar. Use it when the shell will not come back; it needs nothing from the
  snapshot and works from a TTY. Restore the daily bar afterwards on purpose.

### What `--accept` retains and preserves

Before accepting, `scripts/branch-test.sh --accept` verifies that:

1. the armed snapshot directory (`~/.local/state/islands-branch-test`) is a
   real, owner-owned, mode `700` directory with a complete, checksum-valid
   snapshot;
2. no restoration has started or completed (`restoring` marker or active lock);
3. `~/.config/omarchy/shell.json` is valid version-1 JSON selecting the
   expected plugin ID, and the installed plugin passes manifest/entry-point
   validation (`omarchy-plugin-validate` when available).

Once verified, `--accept`:

- **Retains** the currently installed plugin under
  `~/.config/omarchy/plugins/<id>` and the current `~/.config/omarchy/shell.json`
  (including any settings adjustments made during the preview) unchanged, with
  no reinstall and no shell restart.
- **Preserves** the original armed snapshot (plugin tree, `shell.json`,
  checksums, `id`, and script copy) in a private (mode `700`), uniquely named
  directory under `~/.local/state/islands-branch-test-backups/<id>-<timestamp>.<random>`.
  Existing recovery backups are never overwritten or automatically pruned.
- **Commits** a terminal `accepted` marker before stopping the transient
  deadline timer and removing `islands-branch-restore-boot.service`, so an
  already-dispatched timer or login restore cannot revert an accepted
  installation. If timer or login-unit cleanup fails, `--accept` exits non-zero
  and keeps the `accepted` marker so the accepted bar remains protected until
  you re-run `scripts/branch-test.sh --accept` to finish cleanup.

### Restoring a preserved backup after acceptance

To roll back to a previously accepted snapshot preserved under
`~/.local/state/islands-branch-test-backups/`:

1. Confirm no branch-test session is currently armed (`scripts/branch-test.sh --status`).
2. Copy the chosen backup directory into `~/.local/state/islands-branch-test`
   (copying keeps the original backup directory untouched):

   ```bash
   cp -a ~/.local/state/islands-branch-test-backups/<backup-name> ~/.local/state/islands-branch-test
   chmod 700 ~/.local/state/islands-branch-test
   scripts/branch-test.sh --restore
   ```

`--restore` verifies the snapshot checksums, atomically swaps the previous
plugin and `shell.json` back into place, verifies the restored files, restarts
the shell, and removes `~/.local/state/islands-branch-test` while leaving the
preserved copy in `~/.local/state/islands-branch-test-backups/` intact.

The restore has two temporary triggers, both removed once the restored files
verify:

- **At the deadline:** a wall-clock (`OnCalendar`) transient user timer, the
  same kind as the trial watchdog. It fires on resume when the deadline
  passed during a suspend; a monotonic (`OnActiveSec`) timer would pause
  while the machine sleeps.
- **After a reboot:** transient timers do not survive one, so `--arm` also
  enables a user unit, `~/.config/systemd/user/islands-branch-restore-boot.service`,
  that restores at the next login, ordered before the graphical session so
  the shell starts from the restored files. A reboot therefore ends the test
  at the next login, even before the deadline. **Not yet verified on a real
  reboot**: the sandbox covers the restore it runs, and the unit file passes
  `systemd-analyze --user verify` and was enabled live, but no machine has
  been rebooted with it armed.

The login unit cannot outlive a successful restore: every verified restore
(the timer, a manual `--restore` or the unit itself) disables and deletes it,
and while the snapshot is gone its `ConditionPathExists` makes it a no-op. A
restore that fails verification keeps it on purpose, so the next login tries
again. To remove a stale one by hand:
`systemctl --user disable islands-branch-restore-boot.service` and delete the
file.

The snapshot (the plugin, `shell.json`, their checksums and a copy of the
script) is in `~/.local/state/islands-branch-test`, created with mode 700 and
checked before every use (a real directory, owned by you, mode 700); a
symlink or a readable directory is refused. It does not depend on the
terminal, the session that armed it or the repository's branch.

- `--arm` writes a `complete` marker last; a snapshot without it (an
  interrupted arm) is refused by both `--arm` and `--restore`.
- `--restore` holds a lock, so the timer and a manual restore never run at
  once. It swaps the plugin in as a complete copy and moves `shell.json`
  back, then checks every plugin file and `shell.json` against the
  snapshot's checksums. Only then are the timer and the login unit removed.
  A mismatch keeps the snapshot and both triggers. An interrupted restore
  can simply be run again.
- If the shell refuses to restart (a locked screen), the files stay
  restored and only the restart is retried every 5 minutes, at most 24 times.
  With no desktop session (the login case) no restart is needed.
- `--status` shows the snapshot, the login unit and the deadline.

## Options

```
rollback.sh --dry-run        show what would change
rollback.sh --restore FILE   restore a saved shell.json (checked to be version 1 first)
rollback.sh --uninstall      also remove ~/.config/omarchy/plugins/<id>
rollback.sh --any-bar        deselect any third-party bar
rollback.sh --no-restart     deselect only; do not restart the shell
```

## What has been verified

`tests/scripts/sandbox.test.sh` runs every path above against a synthetic
configuration in a throwaway HOME under `/tmp`. The `omarchy` CLI and the
file layout are real; `omarchy-shell` and `hyprctl` are stubs. Covered:

- the TTY environment, with no session variables;
- a running shell and a dead one;
- no `omarchy` CLI at all;
- dry run, restore, refusing a foreign bar or a non-config file;
- an unreadable `shell.json`, which is reported and left untouched;
- uninstall.

`branch-test.sh` is covered there too (arm, restore, accept, backup preservation
and recovery, verification, refusals, shared locking, cleanup-failure recovery,
the login path, the locked-screen retry). Live, on 2026-10-31, its
wall-clock timer fired on its own, restored the installed plugin (every file
checksum) and `shell.json` (byte-identical), restarted the shell and removed
the timer, the login unit and the snapshot. A real reboot has not been tested.

Observed live ([docs/TESTING.md](TESTING.md)):

- the watchdog rollback, unattended;
- `rollback.sh` under text-console conditions (empty environment, PATH of
  bash, jq and coreutils only), with the running shell picking up the change
  by itself;
- `shell.json` identical to the pre-activation snapshot each time.

The shell's fallback on a load error has still not been observed live, and
`--restart` is never run in the tests.

# jg-mech-ingame

An in-game editor for the JG Mechanic config. Open it with a command, change shops and settings in a React UI, and save the result straight back to JG Mechanic's `config.lua`.

## What it does

- Edits every setting in `config.lua`, plus all shops (locations, car lifts, stashes, item stores, services, tuning, blips, jobs and management ranks).
- Shows shops on a map and lets you place locations by aiming in the world.
- Saves named copies of the config to your database.
- **Save to file** rewrites only what you changed, keeps a backup, and restarts JG Mechanic.

## Requirements

- `ox_lib`
- `oxmysql`
- JG Mechanic (and its own dependencies, such as `jg-vehiclemileage`)

## Install

1. Put the folder in your resources and add `ensure jg-mech-ingame` to `server.cfg`.
2. Allow the script to write to JG Mechanic's folder. Add this to `server.cfg` or `permissions.cfg`, then restart the server:

   ```
   add_filesystem_permission jg-mech-ingame write jg-mechanic
   ```

   Use your JG Mechanic folder name if it differs.
3. Make sure admins are in `group.admin` (they get the `admin` permission).

The database table is created automatically.

## Use

Run `/mechconfig` in game.

| Page | What it does |
| --- | --- |
| All Shops / Owned / Self-Service | List, search, create, edit, duplicate, delete and import shops |
| Settings | Every other `Config.*` setting, grouped |
| Saved Configs | Save and load named copies in the database |

Top right: **Pull from file** reloads the current file. **Save to file** applies your changes and restarts JG Mechanic.

In the Locations, Car lifts and Stashes forms, **Place with raycast** hides the menu. Aim in the world, scroll to change the zone size, press Enter or click to place, and Backspace to cancel. Q and E rotate car lifts.

## Config

Edit `config.lua`:

| Option | Default | Meaning |
| --- | --- | --- |
| `command` | `mechconfig` | Command that opens the editor |
| `ace` | `admin` | Permission required |
| `backupBeforeWrite` | `true` | Save a `.bak-<time>` copy before writing |

## Troubleshooting

- **"Could not write ..."**: the filesystem permission line above is missing, or the server wasn't restarted after adding it.
- **Saved but JG Mechanic didn't restart**: it failed to start again. Check the server console for a missing dependency.
- **Couldn't load the config**: the resource must be named `jg-mechanic`, with its config at `config/config.lua`.

# Due

A macOS menu bar assignment tracker. Lives in the menu bar only (no Dock icon, no
windows), shows how many things are due today, and lets you add and manage
assignments from a small popover. Nothing leaves your Mac; there is no network layer
at all.

## Quick add

Type a line like this and press Enter:

```
pset 4 fri 5pm #CS225 ~1h30m
```

That parses to: title "pset 4", due next Friday at 5:00 PM, course CS225, estimate 1
hour 30 minutes. Anything you don't type is left out; a bare title with no date falls
back to the day you're adding it.

**Dates**

| You type | Means |
|---|---|
| `today`, `tonight`, `tod`, `eod` | today |
| `tomorrow`, `tmr`, `tmrw`, `tmw` | tomorrow |
| `mon` … `sunday` | the next occurrence of that weekday |
| `next fri` | that weekday, but in the following week |
| `in 3 days`, `in 2 weeks` | relative offset |
| `eow` | end of this week (Saturday) |
| `dec 8`, `december 8th` | that date, next occurrence (rolls to next year if passed) |
| `12/8` | month/day, same rollover rule |

**Times**

| You type | Means |
|---|---|
| `5pm`, `5:30pm`, `17:00, at 1230, 830am` | that clock time |
| `at 5`, `@ 5` | 5 reads as PM if 1 to 6, AM if 7 to 11 |
| `noon` | 12:00 PM |
| `midnight` | 11:59 PM (end of that day) |

No time given = 11:59 PM on the due date.

**Other tokens**

| You type | Means |
|---|---|
| `#CS225` | course tag |
| `~1h30m`, `~45m`, `~2h`, `~1.5 hours` | estimated time |

## Color legend

Course colors are cosmetic and assigned automatically; urgency colors are fixed and
mean the same thing everywhere in the app:

| Color | Bucket |
|---|---|
| Red | Overdue |
| Orange | Due today |
| Yellow | Soon (inside your "soon" threshold) |
| Blue | This week (inside your "this week" threshold) |
| Gray | Later |

Both thresholds are adjustable in Settings.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| Enter | Add the quick-add line |
| Cmd+N | Focus the quick-add field |
| Esc | Close the popover |
| Cmd+Q | Quit Due |

## Where data lives

Everything is a single JSON file at:

```
~/Library/Application Support/Due/assignments.json
```

Settings > Data has a "Show in Finder" button that jumps straight to it. There is no
sync, no account, and no telemetry; back up that one file if you want a backup.

## Building

```
./build.sh
```

Builds a release binary, assembles `~/Applications/Due.app`, code-signs it, and
relaunches it if it's already running. Flags:

- `--test` runs `swift test` first and stops if anything fails.
- `--no-launch` skips opening the app after building.

Requires macOS 14 or later.

## Launch at login

Settings > General > "Launch at login". This only works once Due is running from
`~/Applications/Due.app` (built via `./build.sh`); it can't register a login item when
run straight out of `.build/debug`.

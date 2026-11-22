# Configurable Button

A Plasma 6 panel button with a configurable list of states. Each state
has a name, an icon, and a script. The button shows the current state's
icon, clicking it cycles through the states and
runs their scripts, and an optional status script keeps the shown state
in sync with whatever the button controls or monitors.

A freshly added button that has not been configured yet shows a
configure gear icon instead of a state; clicking it opens the
settings.

## Installation

Install from the plasmoid directory:

```
kpackagetool6 --type Plasma/Applet --install .
```

Use `--upgrade` instead of `--install` to update an existing
installation.

## How it works

### States

The button's states are a list, edited in the settings. Each state has:

- **Name** — the state's name. The status script can select a state by
  printing its name.
- **Script** — the command run when the button cycles to this state:
  a full path to a script or a shell snippet.
- **Exit code** — optional. A status script run that ends with this
  exit code selects this state.
- **Icon** — the icon shown in the panel while this state is active.
- **Run when clicked** — when unchecked, clicking skips this state and
  its script never runs from a click. Only the status script can select
  it, which is meant for display-only states (a fault condition, for
  example).
- **Default** — exactly one state is the default. It is shown at
  startup, selected when a status run matches nothing, and restored
  when a state's script fails.

### Clicking

Clicking the button (or pressing its assigned keyboard shortcut)
advances to the next "Run when clicked" state and runs that state's
script. While a script runs, the button shows a busy indicator. If the
script exits with a non-zero code, the button falls back to the
default state when the script finishes.

### Status script

The status script reports the real-world state of what the button
controls, so the icon stays truthful even when the state changes
behind the button's back. It can run once on startup, periodically at
a configurable interval, or both. Status checks pause while a button
script runs, and the periodic timer restarts when it finishes.

Each status run selects the state to show, resolved in this order:

1. The state whose **name** it prints on stdout.
2. The state at the **index** it prints on stdout (counting from 0).
3. The state whose **exit code** matches the run's exit code.
4. The **default** state, when nothing above matches.

## Configuration

The settings page has:

- **States** — the state list described above, with buttons to add and
  remove states.
- **Status script** — the script, whether it runs periodically, the
  interval, and whether it runs on startup.

## Examples

### Monitor a connection or a service

Add two states, On and Off, make Off the default, and give On the exit
code 0. Uncheck "Run when clicked" for both if the button should only
display, never act. Set the status script to something like
`ping -c 2 -q example.com` or `systemctl is-active docker`, run on
startup and periodically: exit code 0 shows On, any other exit code
shows Off.

### Start and stop a service

Two states with scripts, for example On running
`systemctl start docker` and Off running `systemctl stop docker`
(assuming those can run without a password prompt). Add the status
script from the previous example so the icon follows the service even
when it is started or stopped elsewhere.

### Cycle through more than two settings

Add one state per setting, for example three fan speeds or power
profiles, each with the command that applies it. Clicking steps
through them in order and wraps around. A status script that prints
the current setting's name keeps the display in sync.

## Existing configurations

Configurations from the two-state version of this applet keep working
unchanged. The on and off scripts, icons, and their enable switches
become the initial two states, with On answering to exit code 0 and
Off as the default, so a status script that only sets its exit code
behaves exactly as before: 0 shows On, anything else shows Off.

## Credits

Originally by Piotr Markiewicz.

- https://github.com/neicker/on-off-switch
- https://github.com/MakG10/plasma-applet-server-status

You might also like:
https://github.com/Intika-Linux-Plasmoid/plasmoid-on-off-switch-commands

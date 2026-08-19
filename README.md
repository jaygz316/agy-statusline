# agy-statusline

Real-time, responsive status line plugin for the **Antigravity CLI** (`agy`) — displays the active model, session context usage, host / SSH machine name, smart directory/git status, background task/subagent telemetry, relative quota countdowns, and critical usage alerts.

## What it shows

```
Claude Sonnet 4.6 (Thinking) │ ✍️  27% │ 🖥️  proxmox-01 [SSH] │ ~/projects/my-project (master*) │ 🤖 2 subagents ⚙️  1 task │ Google AI Pro

claude 5h ●●○○○○○○○○  21% ⟳ in 2h 15m (20:40)
claude 7d ●○○○○○○○○○  16% ⟳ in 4d 3h (jul 4, 20:57)
```

| Field | Description |
|---|---|
| **Model** | Active model for the current session |
| **`✍️ %`** | Context window usage (color-coded with `🚨` critical warning above 90%) |
| **`🖥️ Host [SSH]`** | Machine hostname & SSH indicator (automatically active on SSH sessions, or set to always show) |
| **Directory (branch*)** | Smartly truncated directory path + git branch (`*` = uncommitted changes) |
| **`🤖 ⚙️ Tasks`** | Active background tasks and running subagents counter |
| **Plan** | Account tier (Google AI Pro, etc., hidden automatically on narrow screens) |
| **`claude/gemini 5h`** | 5-hour rolling quota gauge + relative reset countdown (`in 2h 15m`) |
| **`claude/gemini 7d`** | Weekly quota gauge + relative reset countdown (`in 4d 3h`) |

> **Auto Pool Detection**: The quota pool shown (`claude` or `gemini`) is automatically selected based on the active model ID.

---

## Features

- 🖥️ **Computer Name & SSH Session Awareness**: Automatically identifies the current computer name (`proxmox-01`, `unraid`, `racknerd`, `fedora`, etc.) and attaches a vivid `[SSH]` badge during remote SSH sessions so you never mix up host machines. Supports both short (`proxmox-01`) and full (`user@proxmox-01`) formats.
- ⏱️ **Relative Reset Timer**: Displays real-time countdowns (`in 2h 15m`, `in 4d 3h`) alongside local reset times.
- 🚨 **Critical State Alerts**: Bold visual alerts (`🚨` / `[!]` / `󰀦`) when context usage reaches $\ge 90\%$ or quota is critically low.
- 🤖 **Task & Subagent Telemetry**: Real-time counter of active background tasks and running subagents (`🤖 2 subagents ⚙️ 1 task`).
- 📐 **Responsive Terminal Width Adaptation**:
  - **Wide ($\ge 100$ cols)**: Full path, complete task labels, host badge, complete quota gauges, relative + clock reset times.
  - **Standard ($70\text{--}99$ cols)**: Compact task badges, clean multi-line layout with relative reset times.
  - **Compact ($48\text{--}69$ cols)**: Plan tier omitted, 6-segment bars, 2-line condensed view.
  - **Ultra-Compact ($< 48$ cols)**: Single-line streamlined status.
- 📂 **Smart Path Truncation**: Intelligently renders `~/projects/repo`, `…/parent/child`, or `base` according to available terminal width.
- 🎨 **Configurable Themes**: Built-in support for `emoji`, `nerd` (Nerd Fonts), `ascii`, and `powerline`.

---

## Requirements

- [`jq`](https://jqlang.github.io/jq/) — for JSON parsing
- `git` — for branch info
- GNU `date` & coreutils (`awk`, `tr`)
- `agy` (Antigravity CLI) installed and configured

---

## Installation

```bash
git clone https://github.com/your-username/agy-statusline
cd agy-statusline
bash bin/install.sh
```

Restart `agy` to see your status line.

---

## Configuration & Theming

Configuration is managed in `~/.gemini/statusline.conf` (created automatically on install from [`statusline.conf.example`](file:///home/jay/projects/agy-statusline/statusline.conf.example)), or overridden via environment variables.

### Themes

Set `THEME="emoji"` (or export `STATUSLINE_THEME="..."`):

* **`emoji`** (Default):
  ```
  Claude Sonnet 4.6 (Thinking) │ ✍️  27% │ 🖥️  box [SSH] │ my-app (master*) │ 🤖 2 subagents │ Google AI Pro
  claude 5h ●●○○○○○○○○  21% ⟳ in 2h 15m
  ```
* **`nerd`** (Requires a [Nerd Font](https://www.nerdfonts.com/)):
  ```
  Claude Sonnet 4.6 (Thinking) │ 󱐌 27% │ 󰒋 box [󰣀 SSH] │ my-app ( master*) │ 󰚩 2 subagents │ 󰍛 Google AI Pro
  claude 5h ██░░░░░░░░  21% 󰑐 in 2h 15m
  ```
* **`powerline`**:
  ```
  Claude Sonnet 4.6 (Thinking)  ✍ 27%  💻 box [SSH]  my-app ( master*)  🤖 2 subagents  ◆ Google AI Pro
  claude 5h ■■□□□□□□□□  21% ⟳ in 2h 15m
  ```
* **`ascii`** (Zero unicode dependencies):
  ```
  Claude Sonnet 4.6 (Thinking) | ctx: 27% | @box [SSH] | my-app (master*) | agents: 2 | Google AI Pro
  claude 5h [##--------]  21% reset: in 2h 15m
  ```

### Available Configuration Options

| Option in `statusline.conf` | Env Variable Override | Default | Values |
|---|---|---|---|
| `THEME` | `STATUSLINE_THEME` | `"emoji"` | `"emoji"`, `"nerd"`, `"ascii"`, `"powerline"` |
| `SHOW_HOSTNAME` | `STATUSLINE_SHOW_HOSTNAME` | `"auto"` | `"auto"` (shows on SSH), `"always"`, `"never"` |
| `HOSTNAME_FORMAT` | `STATUSLINE_HOSTNAME_FORMAT` | `"short"` | `"short"` (`server`), `"full"` (`user@server`) |
| `SHOW_SSH_INDICATOR` | `STATUSLINE_SHOW_SSH_INDICATOR` | `true` | `true`, `false` |
| `SSH_INDICATOR_TEXT` | `STATUSLINE_SSH_INDICATOR_TEXT` | `"SSH"` | String (e.g. `"SSH"`, `"ssh"`, `"REMOTE"`) |
| `LAYOUT` | `STATUSLINE_LAYOUT` | `"auto"` | `"auto"`, `"full"`, `"compact"`, `"single"` |
| `BAR_WIDTH` | `STATUSLINE_BAR_WIDTH` | `10` | Integer (e.g. `8`, `10`, `12`) |
| `RELATIVE_TIME` | `STATUSLINE_RELATIVE_TIME` | `true` | `true`, `false` |
| `CRITICAL_ALERTS` | `STATUSLINE_CRITICAL_ALERTS` | `true` | `true`, `false` |
| `SHOW_TASKS` | `STATUSLINE_SHOW_TASKS` | `true` | `true`, `false` |
| `SHOW_PLAN` | `STATUSLINE_SHOW_PLAN` | `true` | `true`, `false` |

---

## Uninstall

```bash
bash bin/uninstall.sh
```

This restores your previous statusline (if any) and removes the `statusLine` entry from `settings.json`.

---

## Project Structure

```
agy-statusline/
├── bin/
│   ├── statusline.sh          # Main script (installed to ~/.gemini/statusline.sh)
│   ├── install.sh             # Installer script
│   └── uninstall.sh           # Uninstaller script
├── statusline.conf.example    # Template configuration file
├── README.md                  # User documentation
└── AGENTS.md                  # Developer & Agent guidelines
```

---

## How It Works

`agy` runs the command configured under `statusLine` in `settings.json`, passing the current session state as JSON via stdin. The script parses it in a single ultra-fast `jq` pass and emits ANSI-colored text for the terminal.

The installer configures the following in `~/.gemini/antigravity-cli/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "bash \"$HOME/.gemini/statusline.sh\"",
  "enabled": true
}
```

You can toggle the status line at any time from within `agy` using `/statusline`.

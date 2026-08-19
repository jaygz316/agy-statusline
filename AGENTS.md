# AGENTS.md

Developer and AI agent operational guide for `agy-statusline`.

---

## 1. Overview & Architecture

`agy-statusline` is a high-performance, real-time, responsive statusline plugin for the **Antigravity CLI** (`agy`).

### How It Works
1. **Execution**: `agy` invokes the configured statusline script as a subprocess on prompt interactions or state changes.
2. **Configuration**: The script loads user preferences from `~/.gemini/statusline.conf` (with fallback to `STATUSLINE_*` environment variables).
3. **Input Stream**: Session state is passed into the script via standard input (`stdin`) as a JSON payload.
4. **Processing**:
   - Single-pass parsing via `jq` using ASCII record separator (`\x1e`) to guarantee zero subshell overhead and sub-50ms execution.
   - Background tasks and subagents recursive count parsing.
   - Machine hostname detection with automatic SSH session awareness.
   - Local git branch and dirty status detection using `git --no-optional-locks`.
   - Relative epoch countdown calculations for quota reset windows.
   - Dynamic path shortening and responsive layout adaptation based on `terminal_width`.
5. **Output Stream**: Formatted, ANSI-colored string is emitted to standard output (`stdout`), which `agy` renders in the terminal interface.

```
┌──────────────┐   JSON via stdin    ┌───────────────────┐   ANSI stdout   ┌──────────────┐
│  agy CLI     │ ──────────────────> │ bin/statusline.sh │ ──────────────> │ CLI Terminal │
└──────────────┘                     └───────────────────┘                 └──────────────┘
                                              ▲
                                              │ reads
                                     ┌──────────────────┐
                                     │ statusline.conf  │
                                     └──────────────────┘
```

---

## 2. Project Structure

```
agy-statusline/
├── bin/
│   ├── statusline.sh          # Main statusline rendering script (installed to ~/.gemini/statusline.sh)
│   ├── install.sh             # Installer: verifies deps, configures statusline.sh, config, and settings.json
│   └── uninstall.sh           # Uninstaller: restores backups, cleans settings.json
├── statusline.conf.example    # Template configuration file (installed to ~/.gemini/statusline.conf)
├── README.md                  # End-user documentation
└── AGENTS.md                  # Agent and developer guidelines (this file)
```

---

## 3. Dependencies & Requirements

- **Runtime Shell**: `bash` (4.0+)
- **JSON Processor**: `jq` (required for parsing stdin)
- **VCS**: `git` (for branch and dirty status detection)
- **Coreutils**: GNU `date` (supports ISO-8601 parsing via `-d`), `awk`, `tr`, `basename`, `dirname`, `pwd`
- **Host Application**: Antigravity CLI (`agy`) with configuration at `~/.gemini/antigravity-cli/`

---

## 4. Input JSON Schema

The `agy` CLI provides session state through `stdin`. Below is the documented schema and field mappings:

### Sample Input Payload

```json
{
  "model": {
    "display_name": "Claude Sonnet 4.6 (Thinking)",
    "id": "claude-3-7-sonnet"
  },
  "cwd": "/home/user/projects/my-repo",
  "context_window": {
    "used_percentage": 27.4
  },
  "agent_state": "idle",
  "plan_tier": "Google AI Pro",
  "terminal_width": 120,
  "tasks": [
    { "id": "task-1", "status": "running" }
  ],
  "subagents": [
    { "id": "sub-1", "state": "running" },
    { "id": "sub-2", "state": "running" }
  ],
  "quota": {
    "3p-5h": {
      "remaining_fraction": 0.79,
      "reset_time": "2026-08-19T02:40:00Z"
    },
    "3p-weekly": {
      "remaining_fraction": 0.84,
      "reset_time": "2026-08-25T20:57:00Z"
    },
    "gemini-5h": {
      "remaining_fraction": 0.95,
      "reset_time": "2026-08-19T02:40:00Z"
    },
    "gemini-weekly": {
      "remaining_fraction": 0.60,
      "reset_time": "2026-08-25T20:57:00Z"
    }
  }
}
```

### Field Definitions

| JSON Field | Type | Description | Script Handling |
| :--- | :--- | :--- | :--- |
| `model.display_name` | string | Human-readable model label | Displays in blue (fallback: `"agy"`) |
| `model.id` | string | Model identifier | Evaluated for `claude`, `anthropic`, or `3p` to switch quota pool (`3p` vs `gemini`) |
| `cwd` | string | Current working directory | Formatted via `format_path` with smart truncation |
| `context_window.used_percentage` | number | Context window utilization (%) | Color-graded; triggers `🚨` critical badge when $\ge 90\%$ |
| `agent_state` | string | Current lifecycle state (`"working"`, `"running"`, `"idle"`) | Shows active icon (`⚡`, `󱐋`, `*`) when active |
| `tasks` / `active_tasks` | number / array / object | Active background tasks | Counted and formatted into task badge (`⚙️ 1`) |
| `subagents` / `active_subagents` | number / array / object | Running subagent instances | Counted and formatted into subagent badge (`🤖 2`) |
| `plan_tier` | string | Account tier (e.g., `"Google AI Pro"`) | Appended to Line 1; hidden when width $< 75$ |
| `terminal_width` | number | Terminal column width | Used for responsive layout switching and path budget |
| `quota.<pool-5h>.remaining_fraction` | float | Fraction remaining (0.0 to 1.0) | Converted to consumed %: `(1 - remaining_fraction) * 100` |
| `quota.<pool-5h>.reset_time` | string | ISO-8601 timestamp | Formatted as relative countdown (`in 2h 15m`) + local time |
| `quota.<pool-weekly>.remaining_fraction` | float | Fraction remaining (0.0 to 1.0) | Converted to consumed %: `(1 - remaining_fraction) * 100` |
| `quota.<pool-weekly>.reset_time` | string | ISO-8601 timestamp | Formatted as relative countdown (`in 4d 3h`) + local date |

---

## 5. Output Formatting, Theming & Visual Rules

### Output Layout Modes

#### 1. Full Layout (`width >= 70` or `LAYOUT="full"`)
```
<Model> │ ✍️  <Ctx>% │ 🖥️ <Host> [SSH] │ <Path> (<Branch><Dirty>) │ 🤖 <Subagents> ⚙️ <Tasks> │ <PlanTier>

<pool> 5h <Bar> <Consumed>% ⟳ in <RelTime> (<ResetTime>)
<pool> 7d <Bar> <Consumed>% ⟳ in <RelDate> (<ResetDate>)
```

#### 2. Compact Layout (`48 <= width < 70` or `LAYOUT="compact"`)
```
<Model> │ ✍️  <Ctx>% │ 🖥️ <Host> [SSH] │ <Path> (<Branch><Dirty>) │ 🤖 <Subagents>
<pool> 5h <Bar6> <Consumed>% ⟳ in <RelTime> │ <pool> 7d <Bar6> <Consumed>% ⟳ in <RelDate>
```

#### 3. Single-Line Layout (`width < 48` or `LAYOUT="single"`)
```
<Model> │ ✍️  <Ctx>% │ 🖥️ <Host> [SSH] │ <Path> │ 🤖 <Subagents> │ 5h:<Consumed>%
```

---

### Built-in Themes

| Theme | Separator | Context Icon | Active State | Quota Reset | Host Icon | SSH Icon | Branch Icon | Plan Icon | Subagent / Task Icons | Bar Glyphs |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`emoji`** (default) | ` │ ` | `✍️  ` | `⚡ ` | `⟳ ` | `🖥️  ` | `🌐 ` | ` ` | ` ` | `🤖 ` / `⚙️  ` | `●` / `○` |
| **`nerd`** | ` │ ` | `󱐌 ` | `󱐋 ` | `󰑐 ` | `󰒋 ` | `󰣀 ` | ` ` | `󰍛 ` | `󰚩 ` / `󰑮 ` | `█` / `░` |
| **`ascii`** | ` \| ` | `ctx: ` | `* ` | `reset: ` | `@` | ` ` | ` ` | ` ` | `agents: ` / `tasks: ` | `[#-]` |
| **`powerline`** | `  ` | `✍ ` | `⚡ ` | `⟳ ` | `💻 ` | `⚡ ` | ` ` | `◆ ` | `🤖 ` / `⚙ ` | `■` / `□` |

---

## 6. Development & Testing Workflows

### Syntax Verification
```bash
bash -n bin/*.sh
```

### Manual Testing with Mock Payloads

#### Test Hostname on SSH (Emoji Theme)
```bash
cat << 'EOF' | SSH_CLIENT="192.168.1.50 54321 22" bash bin/statusline.sh
{
  "model": { "display_name": "Claude Sonnet 4.6 (Thinking)", "id": "claude-3-7-sonnet" },
  "cwd": "/home/jay/projects/agy-statusline",
  "context_window": { "used_percentage": 27 },
  "agent_state": "idle",
  "tasks": 1,
  "subagents": 2,
  "plan_tier": "Google AI Pro",
  "terminal_width": 120,
  "quota": {
    "3p-5h": { "remaining_fraction": 0.79, "reset_time": "2026-08-19T02:40:00Z" },
    "3p-weekly": { "remaining_fraction": 0.84, "reset_time": "2026-08-25T20:57:00Z" }
  }
}
EOF
```

#### Test Nerd Font Theme with Hostname & Tasks
```bash
cat << 'EOF' | STATUSLINE_THEME=nerd STATUSLINE_SHOW_HOSTNAME=always bash bin/statusline.sh
{
  "model": { "display_name": "Gemini 2.5 Flash", "id": "gemini-2.5-flash" },
  "cwd": "/home/jay/projects/agy-statusline",
  "context_window": { "used_percentage": 30 },
  "agent_state": "idle",
  "tasks": [{ "id": "1", "status": "running" }],
  "subagents": [{ "id": "sub1" }],
  "plan_tier": "Google AI Studio",
  "terminal_width": 100,
  "quota": {
    "gemini-5h": { "remaining_fraction": 0.15, "reset_time": "2026-08-19T02:40:00Z" },
    "gemini-weekly": { "remaining_fraction": 0.40, "reset_time": "2026-08-25T20:57:00Z" }
  }
}
EOF
```

---

## 7. Configuration Lifecycle

- **Configuration File**: `~/.gemini/statusline.conf`
- **Installation**: [`bin/install.sh`](file:///home/jay/projects/agy-statusline/bin/install.sh) copies [`statusline.conf.example`](file:///home/jay/projects/agy-statusline/statusline.conf.example) to `~/.gemini/statusline.conf` if not already present.
- **Uninstallation**: [`bin/uninstall.sh`](file:///home/jay/projects/agy-statusline/bin/uninstall.sh) preserves `statusline.conf` to protect user settings while removing script registration from `settings.json`.

---

## 8. Agent Contribution Guidelines

1. **Ultra-Low Latency (< 50ms)**:
   - Extract all JSON fields and task structures in a **single `jq` pass** using `\u001e` record delimiters.
   - Never invoke `jq` or `awk` inside loops or multiple times per execution.
   - Always use `git --no-optional-locks` for git commands.

2. **Fault Tolerance & Safety**:
   - The script must never exit with a non-zero exit code due to unexpected, empty, or missing JSON keys.
   - Handle polymorphic types (e.g., tasks as integers, objects, or arrays) gracefully without failing.

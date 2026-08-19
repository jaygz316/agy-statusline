#!/bin/bash
set -f

input=$(cat)

if [ -z "$input" ]; then
    printf "agy"
    exit 0
fi

# ── Load Configuration ──────────────────────────────────
CONFIG_FILE="${STATUSLINE_CONFIG:-$HOME/.gemini/statusline.conf}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE" 2>/dev/null
fi

THEME="${STATUSLINE_THEME:-${THEME:-emoji}}"
LAYOUT="${STATUSLINE_LAYOUT:-${LAYOUT:-auto}}"
BAR_WIDTH="${STATUSLINE_BAR_WIDTH:-${BAR_WIDTH:-10}}"
RELATIVE_TIME="${STATUSLINE_RELATIVE_TIME:-${RELATIVE_TIME:-true}}"
CRITICAL_ALERTS="${STATUSLINE_CRITICAL_ALERTS:-${CRITICAL_ALERTS:-true}}"
SHOW_HOSTNAME="${STATUSLINE_SHOW_HOSTNAME:-${SHOW_HOSTNAME:-auto}}"
HOSTNAME_FORMAT="${STATUSLINE_HOSTNAME_FORMAT:-${HOSTNAME_FORMAT:-short}}"
SHOW_SSH_INDICATOR="${STATUSLINE_SHOW_SSH_INDICATOR:-${SHOW_SSH_INDICATOR:-true}}"
SSH_INDICATOR_TEXT="${STATUSLINE_SSH_INDICATOR_TEXT:-${SSH_INDICATOR_TEXT:-SSH}}"
SHOW_PLAN="${STATUSLINE_SHOW_PLAN:-${SHOW_PLAN:-true}}"
SHOW_TASKS="${STATUSLINE_SHOW_TASKS:-${SHOW_TASKS:-true}}"

# ── Colors ──────────────────────────────────────────────
blue='\033[38;2;0;153;255m'
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;175;80m'
cyan='\033[38;2;86;182;194m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
gold='\033[38;2;240;190;90m'
white='\033[38;2;220;220;220m'
magenta='\033[38;2;180;140;255m'
bold_red='\033[1;38;2;255;85;85m'
dim='\033[2m'
reset='\033[0m'

# ── Theme Definitions ───────────────────────────────────
case "$THEME" in
    nerd)
        icon_sep=" │ "
        icon_ctx="󱐌 "
        icon_state="󱐋 "
        icon_quota="󰑐 "
        icon_branch=" "
        icon_host="󰒋 "
        icon_ssh="󰣀 "
        icon_plan="󰍛 "
        icon_crit="󰀦 "
        icon_task="󰑮 "
        icon_subagent="󰚩 "
        bar_fill="█"
        bar_empty="░"
        ;;
    ascii)
        icon_sep=" | "
        icon_ctx="ctx: "
        icon_state="* "
        icon_quota="reset: "
        icon_branch=""
        icon_host="@"
        icon_ssh=""
        icon_plan=""
        icon_crit="[!] "
        icon_task="tasks: "
        icon_subagent="agents: "
        bar_fill="#"
        bar_empty="-"
        ;;
    powerline)
        icon_sep="  "
        icon_ctx="✍ "
        icon_state="⚡ "
        icon_quota="⟳ "
        icon_branch=" "
        icon_host="💻 "
        icon_ssh="⚡ "
        icon_plan="◆ "
        icon_crit="⚡! "
        icon_task="⚙ "
        icon_subagent="🤖 "
        bar_fill="■"
        bar_empty="□"
        ;;
    emoji|*)
        icon_sep=" │ "
        icon_ctx="✍️  "
        icon_state="⚡ "
        icon_quota="⟳ "
        icon_branch=""
        icon_host="🖥️  "
        icon_ssh="🌐 "
        icon_plan=""
        icon_crit="🚨 "
        icon_task="⚙️  "
        icon_subagent="🤖 "
        bar_fill="●"
        bar_empty="○"
        ;;
esac

sep="${dim}${icon_sep}${reset}"

# ── Extract JSON data in single jq pass ──────────────────
IFS=$'\x1e' read -r model_name model_id cwd ctx_pct agent_state plan_tier terminal_width \
  task_cnt subagent_cnt \
  q3p_5h_frac q3p_5h_reset q3p_5h_sec q3p_wk_frac q3p_wk_reset q3p_wk_sec \
  qgem_5h_frac qgem_5h_reset qgem_5h_sec qgem_wk_frac qgem_wk_reset qgem_wk_sec < <(
  echo "$input" | jq -r '
    def is_active_status(s):
      if s == null or s == "" then true
      else
        (s | tostring | ascii_downcase) as $st
        | if ($st == "done" or $st == "completed" or $st == "finished" or $st == "killed" or $st == "cancelled" or $st == "canceled" or $st == "failed" or $st == "dead" or $st == "exited" or $st == "stopped" or $st == "errored" or $st == "error") then false
          else true
          end
      end;

    def count_val:
      if . == null then 0
      elif type == "number" then .
      elif type == "string" then (try tonumber catch 1)
      elif type == "boolean" then (if . then 1 else 0 end)
      elif type == "array" then
        ([ .[] | count_val ] | add // 0)
      elif type == "object" then
        if (has("running") or has("active") or has("in_progress")) then
          ((.running // 0) + (.active // 0) + (.in_progress // 0))
        elif (has("status") or has("state") or has("lifecycle")) then
          (if is_active_status(.status // .state // .lifecycle) then 1 else 0 end)
        elif has("count") then (.count // 0)
        elif (has("total") and (length == 1)) then (.total // 0)
        else
          # Count individual object as 1 active item
          1
        end
      else 0
      end;

    def get_task_count:
      (
        ((.tasks // null) | count_val) +
        ((.active_tasks // null) | count_val) +
        ((.running_tasks // null) | count_val) +
        ((.background_tasks // null) | count_val) +
        ((.task_count // null) | count_val)
      );

    def get_subagent_count:
      (
        ((.subagents // null) | count_val) +
        ((.active_subagents // null) | count_val) +
        ((.subagent_count // null) | count_val) +
        ((.agents // null) | count_val) +
        ((.active_agents // null) | count_val) +
        ((.sub_agents // null) | count_val)
      );

    [
      (.model.display_name // "agy"),
      (.model.id // ""),
      (.cwd // ""),
      ((.context_window.used_percentage // 0) | round | tostring),
      (.agent_state // ""),
      (.plan_tier // ""),
      ((.terminal_width // 80) | tostring),
      (get_task_count | tostring),
      (get_subagent_count | tostring),
      ((.quota["3p-5h"].remaining_fraction // "") | tostring),
      (.quota["3p-5h"].reset_time // ""),
      ((.quota["3p-5h"].reset_in_seconds // "") | tostring),
      ((.quota["3p-weekly"].remaining_fraction // "") | tostring),
      (.quota["3p-weekly"].reset_time // ""),
      ((.quota["3p-weekly"].reset_in_seconds // "") | tostring),
      ((.quota["gemini-5h"].remaining_fraction // "") | tostring),
      (.quota["gemini-5h"].reset_time // ""),
      ((.quota["gemini-5h"].reset_in_seconds // "") | tostring),
      ((.quota["gemini-weekly"].remaining_fraction // "") | tostring),
      (.quota["gemini-weekly"].reset_time // ""),
      ((.quota["gemini-weekly"].reset_in_seconds // "") | tostring)
    ] | join("\u001e")'
)

[ -z "$cwd" ] && cwd=$(pwd)
[ -z "$terminal_width" ] || [ "$terminal_width" -le 0 ] 2>/dev/null && terminal_width=80
[ -z "$ctx_pct" ] 2>/dev/null && ctx_pct=0
[ -z "$task_cnt" ] 2>/dev/null && task_cnt=0
[ -z "$subagent_cnt" ] 2>/dev/null && subagent_cnt=0

# ── Helpers ─────────────────────────────────────────────
color_for_pct() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then
        if [ "$CRITICAL_ALERTS" = "true" ]; then
            printf "$bold_red"
        else
            printf "$red"
        fi
    elif [ "$pct" -ge 70 ]; then printf "$yellow"
    elif [ "$pct" -ge 50 ]; then printf "$orange"
    else printf "$green"
    fi
}

build_bar() {
    local pct=$1
    local width=$2
    [ -z "$width" ] || [ "$width" -le 0 ] && width=10
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar_color
    bar_color=$(color_for_pct "$pct")

    local filled_str="" empty_str=""
    for ((i=0; i<filled; i++)); do filled_str+="$bar_fill"; done
    for ((i=0; i<empty; i++)); do empty_str+="$bar_empty"; done

    if [ "$THEME" = "ascii" ]; then
        printf "[${bar_color}${filled_str}${dim}${empty_str}${reset}]"
    else
        printf "${bar_color}${filled_str}${dim}${empty_str}${reset}"
    fi
}

format_seconds_diff() {
    local diff=$1
    if [ "$diff" -le 0 ]; then
        printf "now"
        return
    fi

    local days=$(( diff / 86400 ))
    local hours=$(( (diff % 86400) / 3600 ))
    local mins=$(( (diff % 3600) / 60 ))

    if [ "$days" -gt 0 ]; then
        if [ "$hours" -gt 0 ]; then
            printf "in %dd %dh" "$days" "$hours"
        else
            printf "in %dd" "$days"
        fi
    elif [ "$hours" -gt 0 ]; then
        if [ "$mins" -gt 0 ]; then
            printf "in %dh %dm" "$hours" "$mins"
        else
            printf "in %dh" "$hours"
        fi
    else
        if [ "$mins" -gt 0 ]; then
            printf "in %dm" "$mins"
        else
            printf "in <1m"
        fi
    fi
}

format_relative_time() {
    local reset_iso=$1
    local reset_sec=$2

    if [ -n "$reset_sec" ] && [ "$reset_sec" != "null" ] && [ "$reset_sec" -ge 0 ] 2>/dev/null; then
        format_seconds_diff "$reset_sec"
        return
    fi

    [ -z "$reset_iso" ] || [ "$reset_iso" = "null" ] && return

    local epoch
    epoch=$(date -d "$reset_iso" +%s 2>/dev/null)
    [ -z "$epoch" ] && return

    local now
    now=$(date +%s)
    local diff=$(( epoch - now ))
    format_seconds_diff "$diff"
}

format_reset_time() {
    local reset_iso=$1
    local reset_sec=$2
    local style=$3  # "time" for 5h, "datetime" for 7d
    local term_w=$4
    [ -z "$reset_iso" ] || [ "$reset_iso" = "null" ] && return

    local epoch
    epoch=$(date -d "$reset_iso" +%s 2>/dev/null)
    [ -z "$epoch" ] && return

    local abs_time=""
    if [ "$style" = "time" ]; then
        abs_time=$(date -d "@$epoch" +"%H:%M" 2>/dev/null)
    else
        abs_time=$(date -d "@$epoch" +"%b %-d, %H:%M" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    fi

    if [ "$RELATIVE_TIME" = "true" ]; then
        local rel_time
        rel_time=$(format_relative_time "$reset_iso" "$reset_sec")
        if [ -n "$rel_time" ]; then
            if [ -n "$term_w" ] && [ "$term_w" -ge 100 ]; then
                printf "%s (%s)" "$rel_time" "$abs_time"
            else
                printf "%s" "$rel_time"
            fi
            return
        fi
    fi

    printf "%s" "$abs_time"
}

format_path() {
    local full_path=$1
    local max_len=$2
    [ -z "$full_path" ] && full_path=$(pwd)
    [ -z "$max_len" ] || [ "$max_len" -le 0 ] && max_len=25

    # Replace $HOME with ~
    local display_path="${full_path/#$HOME/\~}"

    if [ ${#display_path} -le "$max_len" ]; then
        printf "%s" "$display_path"
        return
    fi

    local base
    base=$(basename "$full_path")

    if [ ${#base} -gt "$max_len" ]; then
        if [ "$max_len" -gt 3 ]; then
            printf "…%s" "${base: -((max_len - 1))}"
        else
            printf "%s" "$base"
        fi
        return
    fi

    local parent_dir
    parent_dir=$(dirname "$full_path")
    local parent_base
    parent_base=$(basename "$parent_dir")

    local shortened="…/${parent_base}/${base}"
    if [ ${#shortened} -le "$max_len" ]; then
        printf "%s" "$shortened"
    else
        printf "%s" "$base"
    fi
}

format_tasks() {
    local t_cnt=$1
    local s_cnt=$2
    local term_w=$3
    local is_short=$4

    local parts=()
    if [ "$s_cnt" -gt 0 ]; then
        if [ "$THEME" = "ascii" ]; then
            parts+=("${icon_subagent}${s_cnt}")
        elif [ "$term_w" -ge 100 ] && [ "$is_short" != "true" ]; then
            local label="subagents"
            [ "$s_cnt" -eq 1 ] && label="subagent"
            parts+=("${icon_subagent}${s_cnt} ${label}")
        else
            parts+=("${icon_subagent}${s_cnt}")
        fi
    fi

    if [ "$t_cnt" -gt 0 ]; then
        if [ "$THEME" = "ascii" ]; then
            parts+=("${icon_task}${t_cnt}")
        elif [ "$term_w" -ge 100 ] && [ "$is_short" != "true" ]; then
            local label="tasks"
            [ "$t_cnt" -eq 1 ] && label="task"
            parts+=("${icon_task}${t_cnt} ${label}")
        else
            parts+=("${icon_task}${t_cnt}")
        fi
    fi

    if [ ${#parts[@]} -eq 0 ]; then
        return
    fi

    local out=""
    for p in "${parts[@]}"; do
        [ -n "$out" ] && out+=" "
        out+="$p"
    done
    printf "%s" "$out"
}

format_host() {
    local show_setting=$1
    local host_fmt=$2
    local show_ssh_ind=$3

    local is_ssh=false
    if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ] || [ -n "$SSH_CONNECTION" ]; then
        is_ssh=true
    elif [ -r "/proc/$PPID/cmdline" ] && grep -qiE 'sshd|mosh-server' "/proc/$PPID/cmdline" 2>/dev/null; then
        is_ssh=true
    fi

    local should_show=false
    case "$show_setting" in
        always|true) should_show=true ;;
        never|false) should_show=false ;;
        auto|*)
            if [ "$is_ssh" = "true" ]; then
                should_show=true
            fi
            ;;
    esac

    if [ "$should_show" != "true" ]; then
        return
    fi

    local raw_host="${STATUSLINE_HOSTNAME:-${HOSTNAME:-}}"
    if [ -z "$raw_host" ]; then
        raw_host=$(hostname -s 2>/dev/null || cat /etc/hostname 2>/dev/null || uname -n 2>/dev/null)
    fi
    raw_host="${raw_host%%.*}"
    [ -z "$raw_host" ] && raw_host="unknown-host"

    local host_str="$raw_host"
    if [ "$host_fmt" = "full" ] && [ -n "$USER" ]; then
        host_str="${USER}@${raw_host}"
    fi

    local ssh_badge=""
    if [ "$is_ssh" = "true" ] && [ "$show_ssh_ind" = "true" ]; then
        if [ "$THEME" = "nerd" ]; then
            ssh_badge=" ${cyan}[${icon_ssh}${SSH_INDICATOR_TEXT}]${reset}"
        elif [ "$THEME" = "ascii" ]; then
            ssh_badge=" [${SSH_INDICATOR_TEXT}]"
        else
            ssh_badge=" ${cyan}[${SSH_INDICATOR_TEXT}]${reset}"
        fi
    fi

    printf "${gold}%s%s${reset}%b" "$icon_host" "$host_str" "$ssh_badge"
}

# ── Path formatting based on terminal width ──────────────
if [ "$terminal_width" -ge 100 ]; then
    display_dir=$(format_path "$cwd" 35)
elif [ "$terminal_width" -ge 70 ]; then
    display_dir=$(format_path "$cwd" 20)
else
    display_dir=$(format_path "$cwd" 12)
fi

# ── Git info ─────────────────────────────────────────────
git_branch=""
git_dirty=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
    if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
        git_dirty="*"
    fi
fi

# ── Agent state icon ─────────────────────────────────────
state_icon=""
case "$agent_state" in
    working|running) state_icon="$icon_state" ;;
    idle|*)          state_icon="" ;;
esac

# ── Context Warning / Critical State ─────────────────────
ctx_color=$(color_for_pct "$ctx_pct")
ctx_crit_badge=""
if [ "$CRITICAL_ALERTS" = "true" ] && [ "$ctx_pct" -ge 90 ]; then
    ctx_crit_badge="${bold_red}${icon_crit}${reset}"
fi

# ── Host / Machine Badge ─────────────────────────────────
host_badge=$(format_host "$SHOW_HOSTNAME" "$HOSTNAME_FORMAT" "$SHOW_SSH_INDICATOR")

# ── Task / Subagent Badge ────────────────────────────────
task_badge=""
task_badge_short=""
if [ "$SHOW_TASKS" = "true" ] && { [ "$task_cnt" -gt 0 ] || [ "$subagent_cnt" -gt 0 ]; }; then
    task_badge=$(format_tasks "$task_cnt" "$subagent_cnt" "$terminal_width" "false")
    task_badge_short=$(format_tasks "$task_cnt" "$subagent_cnt" "$terminal_width" "true")
fi

# ── LINE 1: Model │ Context % │ Host │ Directory (branch) │ Tasks │ Plan ──
line1="${blue}${model_name}${reset}"
line1+="${sep}"
line1+="${ctx_crit_badge}${icon_ctx}${ctx_color}${ctx_pct}%${reset}"

if [ -n "$host_badge" ]; then
    line1+="${sep}${host_badge}"
fi

line1+="${sep}"
line1+="${state_icon}${cyan}${display_dir}${reset}"

if [ -n "$git_branch" ]; then
    line1+=" ${green}(${icon_branch}${git_branch}${red}${git_dirty}${green})${reset}"
fi

if [ -n "$task_badge" ]; then
    line1+="${sep}${magenta}${task_badge}${reset}"
fi

if [ "$SHOW_PLAN" = "true" ] && [ -n "$plan_tier" ] && [ "$plan_tier" != "null" ] && [ "$terminal_width" -ge 75 ]; then
    line1+="${sep}${dim}${icon_plan}${plan_tier}${reset}"
fi

# ── Detect model pool (3p = Claude/Anthropic, gemini = Google) ──
model_id_lower=$(echo "$model_id" | tr '[:upper:]' '[:lower:]')
if echo "$model_id_lower" | grep -qiE 'claude|anthropic|3p'; then
    pool_label="claude"
    q5h_frac="$q3p_5h_frac"
    q5h_reset_iso="$q3p_5h_reset"
    q5h_reset_sec="$q3p_5h_sec"
    qwk_frac="$q3p_wk_frac"
    qwk_reset_iso="$q3p_wk_reset"
    qwk_reset_sec="$q3p_wk_sec"
else
    pool_label="gemini"
    q5h_frac="$qgem_5h_frac"
    q5h_reset_iso="$qgem_5h_reset"
    q5h_reset_sec="$qgem_5h_sec"
    qwk_frac="$qgem_wk_frac"
    qwk_reset_iso="$qgem_wk_reset"
    qwk_reset_sec="$qgem_wk_sec"
fi

effective_bar_width=$BAR_WIDTH
if [ "$terminal_width" -lt 65 ]; then
    effective_bar_width=6
fi

# 5h quota
q5h_line=""
if [ -n "$q5h_frac" ]; then
    q5h_pct=$(awk -v f="$q5h_frac" 'BEGIN {printf "%.0f", (1 - f) * 100}')
    q5h_bar=$(build_bar "$q5h_pct" "$effective_bar_width")
    q5h_color=$(color_for_pct "$q5h_pct")
    q5h_pct_fmt=$(printf "%3d" "$q5h_pct")
    q5h_reset_fmt=$(format_reset_time "$q5h_reset_iso" "$q5h_reset_sec" "time" "$terminal_width")

    q5h_line="${white}${pool_label} 5h${reset} ${q5h_bar} ${q5h_color}${q5h_pct_fmt}%${reset}"
    [ -n "$q5h_reset_fmt" ] && q5h_line+=" ${dim}${icon_quota}${reset}${white}${q5h_reset_fmt}${reset}"
fi

# weekly quota
qwk_line=""
if [ -n "$qwk_frac" ]; then
    qwk_pct=$(awk -v f="$qwk_frac" 'BEGIN {printf "%.0f", (1 - f) * 100}')
    qwk_bar=$(build_bar "$qwk_pct" "$effective_bar_width")
    qwk_color=$(color_for_pct "$qwk_pct")
    qwk_pct_fmt=$(printf "%3d" "$qwk_pct")
    qwk_reset_fmt=$(format_reset_time "$qwk_reset_iso" "$qwk_reset_sec" "datetime" "$terminal_width")

    qwk_line="${white}${pool_label} 7d${reset} ${qwk_bar} ${qwk_color}${qwk_pct_fmt}%${reset}"
    [ -n "$qwk_reset_fmt" ] && qwk_line+=" ${dim}${icon_quota}${reset}${white}${qwk_reset_fmt}${reset}"
fi

# ── Determine Layout ─────────────────────────────────────
active_layout="$LAYOUT"
if [ "$active_layout" = "auto" ]; then
    if [ "$terminal_width" -lt 48 ]; then
        active_layout="single"
    elif [ "$terminal_width" -lt 70 ]; then
        active_layout="compact"
    else
        active_layout="full"
    fi
fi

# ── Render Output ────────────────────────────────────────
case "$active_layout" in
    single)
        out="${blue}${model_name}${reset}${sep}${ctx_crit_badge}${icon_ctx}${ctx_color}${ctx_pct}%${reset}"
        if [ -n "$host_badge" ]; then
            out+="${sep}${host_badge}"
        fi
        out+="${sep}${cyan}${display_dir}${reset}"
        if [ -n "$task_badge_short" ]; then
            out+="${sep}${magenta}${task_badge_short}${reset}"
        fi
        if [ -n "$q5h_pct" ]; then
            out+="${sep}${white}5h:${reset}${q5h_color}${q5h_pct}%${reset}"
        fi
        printf "%b" "$out"
        ;;
    compact)
        printf "%b\n" "$line1"
        quota_compact=""
        [ -n "$q5h_line" ] && quota_compact+="$q5h_line"
        if [ -n "$qwk_line" ]; then
            [ -n "$quota_compact" ] && quota_compact+="${sep}"
            quota_compact+="$qwk_line"
        fi
        [ -n "$quota_compact" ] && printf "%b" "$quota_compact"
        ;;
    full|*)
        printf "%b" "$line1"
        quota_lines=""
        [ -n "$q5h_line" ] && quota_lines+="$q5h_line"
        if [ -n "$qwk_line" ]; then
            [ -n "$quota_lines" ] && quota_lines+="\n"
            quota_lines+="$qwk_line"
        fi
        [ -n "$quota_lines" ] && printf "\n\n%b" "$quota_lines"
        ;;
esac

exit 0

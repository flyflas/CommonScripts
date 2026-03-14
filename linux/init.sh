#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

# ============================
# Global configuration
# ============================
readonly SCRIPT_NAME="init.sh"
readonly UI_TITLE="Debian Base Installer"
readonly LOG_FILE="${LOG_FILE:-/tmp/install.log}"
readonly UI_LOG_FILE="${UI_LOG_FILE:-/tmp/install.ui.log}"
readonly SELECTION_FILE="${SELECTION_FILE:-/tmp/init.selection}"
readonly SCRIPT_MARK="# === AUTO CONFIGURED BY INIT.SH ==="

PKG_UPDATED=0
LIVE_OUTPUT=0


# ============================
# Common helpers
# ============================
init_log() {
  mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$UI_LOG_FILE")"
  : >"$UI_LOG_FILE"
  touch "$LOG_FILE"
}

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"
}

run_cmd() {
  log "RUN: $*"
  if [[ "${LIVE_OUTPUT:-0}" -eq 1 ]]; then
    printf '>>> %s\n' "$*"
    "$@" 2>&1 | tee -a "$LOG_FILE"
    return "${PIPESTATUS[0]}"
  else
    "$@" >>"$LOG_FILE" 2>&1
  fi
}

run_bash() {
  log "RUN: $*"
  if [[ "${LIVE_OUTPUT:-0}" -eq 1 ]]; then
    printf '>>> %s\n' "$*"
    bash -lc "$*" 2>&1 | tee -a "$LOG_FILE"
    return "${PIPESTATUS[0]}"
  else
    bash -lc "$*" >>"$LOG_FILE" 2>&1
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log "ERROR: root privileges required"
    printf 'ERROR: this action requires root.\n' >&2
    return 1
  fi
}

ensure_line_in_file() {
  local file="$1"
  local line="$2"
  grep -Fqx "$line" "$file" >>"$LOG_FILE" 2>&1 || printf '%s\n' "$line" >>"$file"
}

backup_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  run_cmd cp "$file" "${file}.bak.$(date +%Y%m%d%H%M%S)"
}


# ============================
# Debian package management
# ============================
require_debian() {
  if [[ ! -r /etc/os-release ]]; then
    log "ERROR: /etc/os-release not found"
    return 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  local id="${ID:-}"
  local like="${ID_LIKE:-}"

  if [[ "$id" == "debian" || "$id" == "ubuntu" || "$like" == *debian* ]]; then
    return 0
  fi

  log "ERROR: unsupported distro id=$id like=$like"
  printf 'ERROR: this script currently supports Debian-family systems only.\n' >&2
  return 1
}

pkg_update_once() {
  if [[ "$PKG_UPDATED" -eq 1 ]]; then
    return 0
  fi

  run_cmd apt-get -qq update
  PKG_UPDATED=1
}

install_packages() {
  require_debian || return 1
  require_root || return 1
  pkg_update_once || return 1
  if [[ "${LIVE_OUTPUT:-0}" -eq 1 ]]; then
    DEBIAN_FRONTEND=noninteractive run_cmd apt-get install -y --no-install-recommends "$@"
  else
    DEBIAN_FRONTEND=noninteractive run_cmd apt-get -qq install -y --no-install-recommends "$@"
  fi
}

install_dependencies() {
  install_packages curl wget git ca-certificates dialog tar gzip xz-utils unzip
}


# ============================
# dialog (TUI)
# ============================
dialog_cmd() {
  stty sane >/dev/null 2>&1 || true
  env -u DIALOGOPTS dialog "$@"
}

ensure_dialog_installed() {
  if command_exists dialog; then
    return 0
  fi
  install_packages dialog
}

ensure_terminal_size() {
  local rows cols
  rows="$(tput lines 2>/dev/null || echo 0)"
  cols="$(tput cols 2>/dev/null || echo 0)"

  if [[ "$rows" -lt 22 || "$cols" -lt 82 ]]; then
    dialog_cmd \
      --backtitle "$UI_TITLE" \
      --title "Terminal Too Small" \
      --msgbox "Current terminal: ${rows}x${cols}\nMinimum required: 22x82\n\nPlease enlarge the terminal and retry." 10 70
    return 1
  fi
}

map_selection_token() {
  local token="$1"
  case "$token" in
    SSHD|setup_sshd) echo "setup_sshd" ;;
    BBR|enable_bbr) echo "enable_bbr" ;;
    Swap|config_swap) echo "config_swap=1G" ;;
    1Panel|install_1panel) echo "install_1panel" ;;
    Btop|install_btop) echo "install_btop" ;;
    Docker|install_docker) echo "install_docker" ;;
    Ncdu|install_ncdu) echo "install_ncdu" ;;
    Neovim|install_neovim) echo "install_neovim" ;;
    NextTrace|install_nexttrace) echo "install_nexttrace" ;;
    Singbox|install_singbox) echo "install_singbox" ;;
    SpeedTest|install_speedtest) echo "install_speedtest" ;;
    Zsh|install_zsh) echo "install_zsh" ;;
    Debian12|dd_debian12) echo "dd_debian12" ;;
    *) echo "$token" ;;
  esac
}

collect_checklist() {
  local title="$1"
  local text="$2"
  shift 2

  local output status token
  local -a raw=()
  CHECKLIST_SELECTIONS=()

  status=0
  output="$(dialog_cmd \
    --stdout \
    --separate-output \
    --backtitle "$UI_TITLE" \
    --title "$title" \
    --ok-label "Confirm" \
    --cancel-label "Back" \
    --checklist "$text" 20 80 10 \
    "$@")" || status=$?

  if [[ "$status" -ne 0 ]]; then
    return 1
  fi

  mapfile -t raw <<<"$output"
  for token in "${raw[@]}"; do
    token="$(map_selection_token "$token")"
    [[ -n "$token" ]] && CHECKLIST_SELECTIONS+=("$token")
  done
}

menu_system_settings() {
  local choice status

  while true; do
    status=0
    choice="$(dialog_cmd \
      --stdout \
      --backtitle "$UI_TITLE" \
      --title "System Settings" \
      --ok-label "Confirm" \
      --cancel-label "Back" \
      --menu "Select one item to configure:" 16 70 5 \
      SSHD "Configure SSH key login" \
      BBR "Enable BBR congestion control" \
      Swap "Configure swap space" \
      Shell "Configure shell profile")" || status=$?

    if [[ "$status" -ne 0 || -z "$choice" ]]; then
      break
    fi

    # Execute directly with simple interactive UI
    case "$choice" in
      SSHD)
        dialog_cmd --infobox "Configuring SSH server...\nPlease wait." 5 40
        clear
        setup_sshd
        ;;
      BBR)
        if check_bbr_enabled; then
          dialog_cmd \
            --backtitle "$UI_TITLE" \
            --title "BBR Status" \
            --ok-label "Cancel" \
            --msgbox "Current BBR status: Already Enabled\n\nNo further configuration is required." 8 45
        else
          if dialog_cmd \
            --backtitle "$UI_TITLE" \
            --title "Enable BBR" \
            --yes-label "Confirm" \
            --no-label "Cancel" \
            --yesno "Current BBR status: Not Enabled\n\nDo you want to enable the BBR congestion control algorithm now?" 8 60; then
            
            dialog_cmd --infobox "Enabling BBR...\nPlease wait." 5 40
            clear
            enable_bbr
          fi
        fi
        ;;
      Swap)
        local mem_total_kb mem_total_gb recommend_gb val status_swap
        mem_total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
        
        # Round up/down to nearest GB: (KB + 512MB) / 1GB
        if [[ -n "$mem_total_kb" && "$mem_total_kb" -gt 0 ]]; then
          mem_total_gb=$(( (mem_total_kb + 524288) / 1048576 ))
          [[ "$mem_total_gb" -eq 0 ]] && mem_total_gb=1
        else
          # Fallback if meminfo is unreadable
          mem_total_gb=1
        fi
        
        if [[ "$mem_total_gb" -lt 2 ]]; then
          recommend_gb=$(( mem_total_gb > 0 ? mem_total_gb * 2 : 1 ))
        elif [[ "$mem_total_gb" -le 8 ]]; then
          recommend_gb="$mem_total_gb"
        else
          recommend_gb=4
        fi
        
        status_swap=0
        val="$(dialog_cmd \
          --stdout \
          --backtitle "$UI_TITLE" \
          --title "Configure Swap Space" \
          --ok-label "Confirm" \
          --cancel-label "Back" \
          --inputbox "Current physical memory: ${mem_total_gb}G\nRecommended swap size: ${recommend_gb}G\n\nEnter desired swap size (e.g. 512M, 1G, 4G):" 12 60 "${recommend_gb}G")" || status_swap=$?

        if [[ "$status_swap" -eq 0 && -n "$val" ]]; then
          dialog_cmd --infobox "Configuring Swap (${val})...\nPlease wait." 5 40
          clear
          config_swap "$val"
        fi
        ;;
      Shell)
        dialog_cmd --infobox "Configuring shell profile...\nPlease wait." 5 40
        clear
        config_shell
        ;;
    esac
  done
}

menu_tool_installation() {
  local d_1panel
  local d_btop
  local d_docker
  local d_ncdu
  local d_neovim
  local d_nexttrace
  local d_singbox
  local d_speedtest
  local d_zsh

  d_1panel=$(printf "%-25s" "Server control panel")
  d_btop=$(printf "%-25s" "Resource monitor")
  d_docker=$(printf "%-25s" "Container engine")
  d_ncdu=$(printf "%-25s" "Disk usage analyzer")
  d_neovim=$(printf "%-25s" "Text editor (LazyVim)")
  d_nexttrace=$(printf "%-25s" "Visual route tracker")
  d_singbox=$(printf "%-25s" "Universal proxy platform")
  d_speedtest=$(printf "%-25s" "Network bandwidth tester")
  d_zsh=$(printf "%-25s" "Shell env (oh-my-zsh)")

  # Probe installed status and append [OK] or equivalent padding for uniform highlighting
  if systemctl is-active 1panel.service >/dev/null 2>&1; then d_1panel+=" [OK]"; else d_1panel+="     "; fi
  if command_exists btop; then d_btop+=" [OK]"; else d_btop+="     "; fi
  if command_exists docker; then d_docker+=" [OK]"; else d_docker+="     "; fi
  if command_exists ncdu; then d_ncdu+=" [OK]"; else d_ncdu+="     "; fi
  if command_exists nvim; then d_neovim+=" [OK]"; else d_neovim+="     "; fi
  if command_exists nexttrace; then d_nexttrace+=" [OK]"; else d_nexttrace+="     "; fi
  if systemctl is-active sing-box.service >/dev/null 2>&1; then d_singbox+=" [OK]"; else d_singbox+="     "; fi
  if command_exists speedtest; then d_speedtest+=" [OK]"; else d_speedtest+="     "; fi
  if command_exists zsh; then d_zsh+=" [OK]"; else d_zsh+="     "; fi

  if collect_checklist \
    "Tool Installation" \
    "Select one or more tools to install/update:" \
    1Panel "$d_1panel" OFF \
    Btop "$d_btop" OFF \
    Docker "$d_docker" OFF \
    Ncdu "$d_ncdu" OFF \
    Neovim "$d_neovim" OFF \
    NextTrace "$d_nexttrace" OFF \
    Singbox "$d_singbox" OFF \
    SpeedTest "$d_speedtest" OFF \
    Zsh "$d_zsh" OFF; then
    clear
    run_selected_tasks_with_progress "${CHECKLIST_SELECTIONS[@]}"
  fi
}

menu_system_reinstall() {
  local choice status

  status=0
  choice="$(dialog_cmd \
    --stdout \
    --backtitle "$UI_TITLE" \
    --title "System Reinstall" \
    --ok-label "Confirm" \
    --cancel-label "Back" \
    --menu "Select one target:" 18 80 6 \
    Debian12 "Reinstall Debian 12" \
    Debian13 "Reinstall Debian 13" \
    Alpine "Reinstall Alpine")" || status=$?

  if [[ "$status" -ne 0 || -z "$choice" ]]; then
    return 0
  fi

  # Create a temporary DIALOGRC for a high-contrast danger theme
  local temp_rc="/tmp/dialog_danger.rc"
  cat <<EOF > "$temp_rc"
screen_color = (CYAN,BLUE,ON)
dialog_color = (WHITE,RED,ON)
title_color = (YELLOW,RED,ON)
border_color = (WHITE,RED,ON)
border2_color = (WHITE,RED,ON)
button_active_color = (RED,WHITE,ON)
button_inactive_color = (WHITE,RED,ON)
button_key_active_color = (RED,WHITE,ON)
button_key_inactive_color = (WHITE,RED,ON)
button_label_active_color = (RED,WHITE,ON)
button_label_inactive_color = (WHITE,RED,ON)
shadow_color = (BLACK,BLACK,ON)
EOF

  local danger_ok=0
  export DIALOGRC="$temp_rc"
  dialog_cmd \
    --backtitle "$UI_TITLE" \
    --title "Danger Zone" \
    --yes-label "I understand" \
    --no-label "Cancel" \
    --yesno "You selected: $choice\n\nThis operation will overwrite your system in real implementations.\n\nContinue?" 10 60 || danger_ok=1
  unset DIALOGRC
  rm -f "$temp_rc"

  if [[ "$danger_ok" -eq 0 ]]; then
    
    local pwd pwd2 status_pwd status_pwd2
    while true; do
      status_pwd=0
      pwd="$(dialog_cmd \
        --stdout \
        --insecure \
        --backtitle "$UI_TITLE" \
        --title "Root Password" \
        --passwordbox "Set a root password for the new system:" 10 50)" || status_pwd=$?

      if [[ "$status_pwd" -ne 0 || -z "$pwd" ]]; then
        return 0
      fi

      status_pwd2=0
      pwd2="$(dialog_cmd \
        --stdout \
        --insecure \
        --backtitle "$UI_TITLE" \
        --title "Confirm Root Password" \
        --passwordbox "Please enter the password again to confirm:" 10 50)" || status_pwd2=$?

      if [[ "$status_pwd2" -ne 0 ]]; then
        return 0
      fi

      if [[ "$pwd" == "$pwd2" ]]; then
        break
      else
        dialog_cmd \
          --backtitle "$UI_TITLE" \
          --title "Password Mismatch" \
          --msgbox "The two passwords do not match.\nPlease try again." 8 40
      fi
    done
    
    local task_name
    [[ "$choice" == "Debian12" ]] && task_name="dd_debian12"
    [[ "$choice" == "Debian13" ]] && task_name="dd_debian13"
    [[ "$choice" == "Alpine" ]] && task_name="dd_alpine"
    
    clear
    run_selected_tasks_with_progress "${task_name}=${pwd}"
  fi
}

tui_main_menu() {
  local choice status

  ensure_dialog_installed || {
    printf 'ERROR: failed to install dialog. See log: %s\n' "$LOG_FILE" >&2
    return 1
  }
  ensure_terminal_size || return 1

  while true; do
    status=0
    choice="$(dialog_cmd \
      --stdout \
      --backtitle "$UI_TITLE" \
      --title "Main Menu" \
      --ok-label "Confirm" \
      --cancel-label "Exit" \
      --menu "Use UP/DOWN to select:" 20 80 8 \
      1 "System Settings" \
      2 "System Reinstall" \
      3 "Tool Installation")" || status=$?

    if [[ "$status" -ne 0 ]]; then
      break
    fi

    case "$choice" in
      1) menu_system_settings ;;
      2) menu_system_reinstall ;;
      3) menu_tool_installation ;;
    esac
  done

  clear
}


# ============================
# Task execution framework
# ============================
split_task_item() {
  local item="$1"
  TASK_NAME="${item%%=*}"
  TASK_ARG=""
  [[ "$item" == *"="* ]] && TASK_ARG="${item#*=}"
}

load_selected_tasks() {
  SELECTED_TASKS=()

  if [[ "$#" -gt 0 ]]; then
    SELECTED_TASKS=("$@")
    return 0
  fi

  if [[ -f "$SELECTION_FILE" ]]; then
    mapfile -t SELECTED_TASKS <"$SELECTION_FILE"
  fi
}

save_selected_tasks() {
  local -a items=("$@")
  : >"$SELECTION_FILE"
  [[ "${#items[@]}" -gt 0 ]] && printf '%s\n' "${items[@]}" >"$SELECTION_FILE"
}

run_one_selected_task() {
  local item="$1"
  split_task_item "$item"

  if ! declare -F "$TASK_NAME" >/dev/null 2>&1; then
    log "ERROR: unknown task function: $TASK_NAME"
    return 127
  fi

  log "===== START TASK: $item ====="
  if [[ -n "$TASK_ARG" ]]; then
    "$TASK_NAME" "$TASK_ARG"
  else
    "$TASK_NAME"
  fi
  local rc=$?
  log "===== END TASK: $item (rc=$rc) ====="
  return "$rc"
}

task_title() {
  local item="$1"
  case "$item" in
    setup_sshd*) echo "Configure SSH" ;;
    enable_bbr*) echo "Enable BBR" ;;
    config_swap*) echo "Configure Swap" ;;
    install_1panel*) echo "Install 1Panel" ;;
    install_btop*) echo "Install btop" ;;
    install_docker*) echo "Install Docker" ;;
    install_ncdu*) echo "Install ncdu" ;;
    install_neovim*) echo "Install Neovim" ;;
    install_nexttrace*) echo "Install NextTrace" ;;
    install_singbox*) echo "Install Sing-box" ;;
    install_speedtest*) echo "Install SpeedTest" ;;
    install_zsh*) echo "Install zsh" ;;
    install_base*) echo "Install Base Bundle" ;;
    dd_debian12*) echo "Reinstall Debian 12" ;;
    dd_debian13*) echo "Reinstall Debian 13" ;;
    dd_alpine*) echo "Reinstall Alpine" ;;
    *) echo "$item" ;;
  esac
}

# ============================
# TUI Progress Display
# ============================

# Status constants for dialog --mixedgauge
readonly STATUS_SUCCEEDED=0
readonly STATUS_FAILED=1
readonly STATUS_IN_PROGRESS=7
readonly STATUS_PENDING=8

show_mixedgauge() {
  local text="$1" percent="$2"
  shift 2
  dialog_cmd \
    --backtitle "$UI_TITLE" \
    --title "Installation Progress" \
    --mixedgauge "$text" 20 76 "$percent" "$@"
}

build_gauge_args() {
  local -n _out="$1"
  local -n _tasks="$2"
  local -n _statuses="$3"
  local i count
  count=${#_tasks[@]}
  _out=()
  for ((i = 0; i < count; i++)); do
    _out+=("$(task_title "${_tasks[$i]}")" "${_statuses[$i]}")
  done
}

run_selected_tasks_with_progress() {
  init_log
  load_selected_tasks "$@"

  if [[ "${#SELECTED_TASKS[@]}" -eq 0 ]]; then
    printf 'No selected tasks. Use TUI first: ./%s tui\n' "$SCRIPT_NAME"
    return 1
  fi

  save_selected_tasks "${SELECTED_TASKS[@]}"

  local total idx item rc title percent
  local success=0 failed=0
  local failed_list=""
  local rc_file="/tmp/task_rc.$$"

  total="${#SELECTED_TASKS[@]}"

  # Initialise per-task status array (all pending)
  local -a task_statuses=()
  for ((idx = 0; idx < total; idx++)); do
    task_statuses["$idx"]=$STATUS_PENDING
  done

  # Pre-run apt-get update so subshells don't need to repeat it
  if require_root 2>/dev/null && require_debian 2>/dev/null; then
    local -a g=()
    build_gauge_args g SELECTED_TASKS task_statuses
    show_mixedgauge "\nPreparing package manager ..." 0 "${g[@]}"
    pkg_update_once 2>/dev/null || true
  fi

  idx=0
  for item in "${SELECTED_TASKS[@]}"; do
    idx=$((idx + 1))
    title="$(task_title "$item")"
    percent=$(( (idx - 1) * 100 / total ))

    # --- Phase 1: show overall progress via --mixedgauge ---
    task_statuses[$((idx - 1))]=$STATUS_IN_PROGRESS
    local -a g=()
    build_gauge_args g SELECTED_TASKS task_statuses
    show_mixedgauge "\nCurrently installing: $title" "$percent" "${g[@]}"
    sleep 1.5

    # --- Phase 2: run task with live output via --progressbox ---
    : >"$UI_LOG_FILE"
    : >"$rc_file"

    (
      # Disable exit-on-error so that failures don't kill the
      # subshell (and thereby the pipeline / parent via pipefail).
      # Task exit codes are communicated through $rc_file instead.
      set +eo pipefail

      # Enable live output inside this subshell
      LIVE_OUTPUT=1

      printf '=== [%d/%d] %s ===\n\n' "$idx" "$total" "$title"

      split_task_item "$item"

      if ! declare -F "$TASK_NAME" >/dev/null 2>&1; then
        printf 'ERROR: unknown task function: %s\n' "$TASK_NAME"
        echo 127 >"$rc_file"
        exit 127
      fi

      if [[ -n "$TASK_ARG" ]]; then
        "$TASK_NAME" "$TASK_ARG"
      else
        "$TASK_NAME"
      fi
      local_rc=$?

      echo "" # blank line before result
      if [[ "$local_rc" -eq 0 ]]; then
        printf '[OK] %s completed successfully\n' "$title"
      else
        printf '[FAILED] %s  (exit code: %d)\n' "$title" "$local_rc"
      fi

      echo "$local_rc" >"$rc_file"
      sleep 1
    ) 2>&1 | dialog_cmd \
      --backtitle "$UI_TITLE" \
      --title "[$idx/$total] $title" \
      --progressbox 20 76 || true

    rc=$(cat "$rc_file" 2>/dev/null || echo 1)

    if [[ "$rc" -eq 0 ]]; then
      success=$((success + 1))
      task_statuses[$((idx - 1))]=$STATUS_SUCCEEDED
    else
      failed=$((failed + 1))
      failed_list+=" ${item}(rc=${rc})"
      task_statuses[$((idx - 1))]=$STATUS_FAILED
      log "STOP: task failed, abort remaining tasks"
      break
    fi
  done

  # --- Phase 3: final summary ---
  [[ "$failed" -eq 0 ]] && percent=100 || percent=$(( (idx - 1) * 100 / total ))

  local -a g=()
  build_gauge_args g SELECTED_TASKS task_statuses
  local summary_text
  if [[ "$failed" -eq 0 ]]; then
    summary_text="\nAll tasks completed successfully!"
  else
    summary_text="\nInstallation stopped due to failure."
  fi
  show_mixedgauge "$summary_text" "$percent" "${g[@]}"
  sleep 2

  # Build human-readable summary box
  local msg=""
  msg+="Total tasks : $total\n"
  msg+="Succeeded   : $success\n"
  msg+="Failed      : $failed\n\n"
  [[ "$failed" -gt 0 ]] && msg+="Failed tasks:$failed_list\n\n"
  msg+="Log file: $LOG_FILE"

  if dialog_cmd \
    --backtitle "$UI_TITLE" \
    --title "Installation Complete" \
    --yes-label "View Log" \
    --no-label "Return" \
    --yesno "$msg" 14 60; then
    dialog_cmd \
      --backtitle "$UI_TITLE" \
      --title "Full Installation Log" \
      --textbox "$LOG_FILE" 22 78
  fi

  rm -f "$rc_file"
  [[ "$failed" -eq 0 ]]
}


# ============================
# Installation / configuration tasks
# ============================
install_speedtest() {
  require_root || return 1
  run_bash "curl -fsSL https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash" || return 1
  install_packages speedtest || install_packages speedtest-cli || return 1
  command_exists speedtest || command_exists speedtest-cli
}

install_btop() {
  require_root || return 1
  install_packages btop
  command_exists btop
}

install_lazyvim() {
  local home_dir="${HOME:-/root}"
  local ts
  ts="$(date +%s)"

  run_cmd mv "$home_dir/.config/nvim" "$home_dir/.config/nvim.bak.$ts" 2>/dev/null || true
  run_cmd mv "$home_dir/.local/share/nvim" "$home_dir/.local/share/nvim.bak.$ts" 2>/dev/null || true
  run_cmd mv "$home_dir/.local/state/nvim" "$home_dir/.local/state/nvim.bak.$ts" 2>/dev/null || true
  run_cmd mv "$home_dir/.cache/nvim" "$home_dir/.cache/nvim.bak.$ts" 2>/dev/null || true

  run_cmd git clone https://github.com/LazyVim/starter "$home_dir/.config/nvim" || return 1
  run_cmd rm -rf "$home_dir/.config/nvim/.git"
}

install_neovim() {
  require_root || return 1
  install_packages curl tar gzip xz-utils git unzip xclip || return 1

  local arch url extract_dir
  local tmp_tar="/tmp/nvim-linux.tar.gz"
  local tmp_dir="/tmp/nvim-extract"

  arch="$(uname -m)"
  case "$arch" in
    x86_64)
      url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"
      extract_dir="nvim-linux-x86_64"
      ;;
    aarch64|arm64)
      url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-arm64.tar.gz"
      extract_dir="nvim-linux-arm64"
      ;;
    *)
      log "ERROR: unsupported architecture for neovim: $arch"
      return 1
      ;;
  esac

  run_cmd rm -rf "$tmp_dir" /opt/nvim "$tmp_tar" || return 1
  run_cmd mkdir -p "$tmp_dir" || return 1
  run_cmd curl -fL "$url" -o "$tmp_tar" || return 1
  run_cmd tar -xzf "$tmp_tar" -C "$tmp_dir" || return 1

  [[ -d "$tmp_dir/$extract_dir" ]] || {
    log "ERROR: extracted directory not found: $tmp_dir/$extract_dir"
    return 1
  }

  run_cmd mv "$tmp_dir/$extract_dir" /opt/nvim || return 1
  run_cmd ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim || return 1
  command_exists nvim || return 1

  install_lazyvim
}

install_nexttrace() {
  require_root || return 1
  install_packages curl || return 1
  run_bash "curl -sSL nxtrace.org/nt | bash" || return 1
  command_exists nexttrace
}

config_shell() {
  local home_dir="${HOME:-/root}"
  local shell_path="${SHELL:-}"
  local rc_file=""

  run_cmd timedatectl set-timezone Asia/Shanghai || true

  if [[ "$shell_path" == *zsh* ]]; then
    rc_file="$home_dir/.zshrc"
  elif [[ "$shell_path" == *bash* ]]; then
    rc_file="$home_dir/.bashrc"
  elif [[ -f "$home_dir/.bashrc" ]]; then
    rc_file="$home_dir/.bashrc"
  elif [[ -f "$home_dir/.zshrc" ]]; then
    rc_file="$home_dir/.zshrc"
  else
    log "ERROR: unable to determine shell rc file"
    return 1
  fi

  [[ -f "$rc_file" ]] || run_cmd touch "$rc_file" || return 1

  if grep -Fq "$SCRIPT_MARK" "$rc_file" >>"$LOG_FILE" 2>&1; then
    log "config_shell: marker exists, skip"
    return 0
  fi

  backup_file "$rc_file" || return 1

  {
    printf '\n%s\n' "$SCRIPT_MARK"
    printf 'export HISTTIMEFORMAT="%%F %%T  "\n'
    printf 'export HISTSIZE=10000\n'
    printf 'export HISTIGNORE="pwd:ls:exit"\n'
    printf 'export EDITOR="nvim"\n'
    printf 'alias ll="ls -lh --color=auto"\n'
    printf 'alias la="ls -lha --color=auto"\n'
    printf 'alias cls="clear"\n'
    printf 'alias grep="grep --color=auto"\n'
    printf 'alias ..="cd .."\n'
    printf 'alias df="df -h"\n'
    printf 'alias du="du -h"\n'
    if command_exists nvim; then
      printf 'alias vim="nvim"\n'
    fi
  } >>"$rc_file"

  log "config_shell done: $rc_file"
  if [[ "${LIVE_OUTPUT:-0}" -eq 0 ]]; then
    dialog_cmd --backtitle "$UI_TITLE" --title "Shell Configured" --msgbox "Shell profile has been successfully configured in $rc_file." 8 60
  fi
}

install_zsh() {
  require_root || return 1
  install_packages zsh git curl fonts-powerline || install_packages zsh git curl || return 1

  local home_dir="${HOME:-/root}"
  local zshrc="$home_dir/.zshrc"
  local zsh_bin

  zsh_bin="$(command -v zsh || true)"
  [[ -n "$zsh_bin" ]] || {
    log "ERROR: zsh not found after install"
    return 1
  }

  grep -Fqx "$zsh_bin" /etc/shells >>"$LOG_FILE" 2>&1 || printf '%s\n' "$zsh_bin" >>/etc/shells

  [[ -f "$zshrc" ]] && backup_file "$zshrc"

  run_bash "RUNZSH=no CHSH=no KEEP_ZSHRC=yes bash <(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || return 1

  run_cmd git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$home_dir/.oh-my-zsh/custom/themes/powerlevel10k" || true
  run_cmd git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "$home_dir/.oh-my-zsh/custom/plugins/zsh-autosuggestions" || true
  run_cmd git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$home_dir/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" || true

  [[ -f "$zshrc" ]] || run_cmd cp "$home_dir/.oh-my-zsh/templates/zshrc.zsh-template" "$zshrc" || return 1
  run_cmd sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$zshrc" || return 1
  run_cmd sed -i 's|^plugins=.*|plugins=(git zsh-autosuggestions zsh-syntax-highlighting)|' "$zshrc" || true

  if ! grep -Fq '# === AUTO GENERATED SETTINGS ===' "$zshrc" >>"$LOG_FILE" 2>&1; then
    {
      printf '\n# === AUTO GENERATED SETTINGS ===\n'
      printf 'export HISTSIZE=100000\n'
      printf 'export HISTFILESIZE=100000\n'
      printf 'export SAVEHIST=100000\n'
      printf 'DISABLE_AUTO_UPDATE="true"\n'
      printf '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh\n'
    } >>"$zshrc"
  fi

  if [[ -n "${SUDO_USER:-}" ]]; then
    run_cmd chsh -s "$zsh_bin" "$SUDO_USER" || true
  else
    run_cmd chsh -s "$zsh_bin" "$(id -un)" || true
  fi

  log "install_zsh done"
}

config_swap() {
  require_root || return 1
  local swap_size="${1:-1G}"
  local swap_file="/swapfile"

  if ! [[ "$swap_size" =~ ^[0-9]+[GM]$ ]]; then
    log "ERROR: invalid swap size format: $swap_size"
    return 1
  fi

  if swapon --show=NAME --noheadings | grep -q '^/swapfile$' >>"$LOG_FILE" 2>&1; then
    run_cmd swapoff /swapfile || return 1
  fi

  run_cmd rm -f "$swap_file" || return 1
  run_cmd fallocate -l "$swap_size" "$swap_file" || {
    if [[ "$swap_size" == *G ]]; then
      run_cmd dd if=/dev/zero of="$swap_file" bs=1M count="$(( ${swap_size%G} * 1024 ))" status=none || return 1
    else
      run_cmd dd if=/dev/zero of="$swap_file" bs=1M count="${swap_size%M}" status=none || return 1
    fi
  }

  run_cmd chmod 600 "$swap_file" || return 1
  run_cmd mkswap "$swap_file" || return 1
  run_cmd swapon "$swap_file" || return 1
  ensure_line_in_file /etc/fstab '/swapfile none swap sw 0 0'

  log "config_swap done: $swap_size"
  if [[ "${LIVE_OUTPUT:-0}" -eq 0 ]]; then
    dialog_cmd --backtitle "$UI_TITLE" --title "Swap Configured" --msgbox "Swap space has been successfully configured to ${swap_size}." 8 40
  fi
}

setup_sshd() {
  require_root || return 1
  install_packages openssh-server || install_packages openssh || true

  local sshd_config="/etc/ssh/sshd_config"
  local ssh_dir="${HOME:-/root}/.ssh"
  local key_path="$ssh_dir/id_ed25519"
  local backup_path port

  [[ -f "$sshd_config" ]] || {
    log "ERROR: sshd_config not found"
    return 1
  }

  port="$(shuf -i 60000-65535 -n 1)"
  backup_path="${sshd_config}.bak.$(date +%s)"
  run_cmd cp "$sshd_config" "$backup_path" || return 1

  run_cmd sed -ri "s|^#?Port .*|Port ${port}|" "$sshd_config" || return 1
  run_cmd sed -ri 's|^#?PermitRootLogin .*|PermitRootLogin prohibit-password|' "$sshd_config" || true
  run_cmd sed -ri 's|^#?PasswordAuthentication .*|PasswordAuthentication no|' "$sshd_config" || true
  run_cmd sed -ri 's|^#?PubkeyAuthentication .*|PubkeyAuthentication yes|' "$sshd_config" || true
  ensure_line_in_file "$sshd_config" 'AllowUsers root'

  run_cmd mkdir -p "$ssh_dir" || return 1
  run_cmd chmod 700 "$ssh_dir" || return 1

  if [[ ! -f "$key_path" ]]; then
    run_cmd ssh-keygen -t ed25519 -f "$key_path" -N "" || return 1
  fi

  run_cmd touch "$ssh_dir/authorized_keys" || return 1
  run_cmd chmod 600 "$ssh_dir/authorized_keys" || return 1
  grep -Fqx "$(<"$key_path.pub")" "$ssh_dir/authorized_keys" >>"$LOG_FILE" 2>&1 || {
    cat "$key_path.pub" >>"$ssh_dir/authorized_keys"
    printf '\n' >>"$ssh_dir/authorized_keys"
  }

  run_cmd sshd -t || {
    run_cmd cp "$backup_path" "$sshd_config"
    return 1
  }

  run_cmd systemctl restart sshd || run_cmd systemctl restart ssh || return 1
  run_cmd systemctl is-active sshd || run_cmd systemctl is-active ssh || true
  log "setup_sshd done; port=$port; key=$key_path"
  
  if [[ "${LIVE_OUTPUT:-0}" -eq 0 ]]; then
    dialog_cmd \
      --backtitle "$UI_TITLE" \
      --title "SSH Configuration Successful" \
      --msgbox "SSH service has been configured successfully.\n\nImportant Information:\nSSH Port: ${port}\nPrivate Key: ${key_path}\n\nPlease save your private key securely before disconnecting!" 12 60
  fi
}

check_bbr_enabled() {
  local c q
  c="$(sysctl -n net.ipv4.tcp_congestion_control 2>>"$LOG_FILE" || true)"
  q="$(sysctl -n net.core.default_qdisc 2>>"$LOG_FILE" || true)"
  [[ "$c" == "bbr" && "$q" == "fq" ]]
}

enable_bbr() {
  require_root || return 1
  if check_bbr_enabled; then
    log "enable_bbr: already enabled"
    return 0
  fi

  backup_file /etc/sysctl.conf || true
  ensure_line_in_file /etc/sysctl.conf 'net.core.default_qdisc=fq'
  ensure_line_in_file /etc/sysctl.conf 'net.ipv4.tcp_congestion_control=bbr'

  run_cmd sysctl -p || return 1
  if check_bbr_enabled; then
    if [[ "${LIVE_OUTPUT:-0}" -eq 0 ]]; then
      dialog_cmd --backtitle "$UI_TITLE" --title "BBR Enabled" --msgbox "BBR congestion control has been successfully enabled." 8 50
    fi
    return 0
  fi
}

install_ncdu() {
  require_root || return 1
  install_packages ncdu
  command_exists ncdu
}

install_singbox() {
  require_root || return 1
  install_packages curl || return 1

  log "install_singbox: running install.sh script"
  run_bash "curl -fsSL https://sing-box.app/install.sh | sh" || return 1

  run_cmd systemctl enable sing-box.service
  run_cmd systemctl start sing-box.service

  # Configure daily restart at 3:00 AM
  local cron_file="/etc/cron.d/singbox-restart"
  echo "0 3 * * * root systemctl restart sing-box.service" > "$cron_file"
  chmod 644 "$cron_file"

  log "install_singbox done"
}

install_docker() {
  require_root || return 1
  install_packages curl || return 1

  log "install_docker: running get.docker.com script"
  run_bash "curl -fsSL https://get.docker.com | bash" || return 1
  
  run_cmd systemctl enable docker
  run_cmd systemctl start docker

  command_exists docker || return 1
  log "install_docker done: $(docker --version)"
}

install_1panel() {
  require_root || return 1
  install_packages curl || return 1

  log "install_1panel: running quick_start.sh"
  local log_output="/tmp/1panel_install.log"
  run_bash "curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh | bash" > "$log_output" 2>&1
  local script_rc=$?

  cat "$log_output" >> "$LOG_FILE"
  
  if [[ "$script_rc" -ne 0 ]]; then
    log "ERROR: 1panel installation failed"
    return 1
  fi

  local panel_url panel_user panel_pass
  panel_url=$(grep -oP 'http://[a-zA-Z0-9.\-]+:\d+/[a-zA-Z0-9]+' "$log_output" | head -n 1)
  panel_user=$(grep -oP '(?<=username: ).*' "$log_output" | head -n 1)
  panel_pass=$(grep -oP '(?<=password: ).*' "$log_output" | head -n 1)

  log "install_1panel done: url=$panel_url user=$panel_user"

  if [[ "${LIVE_OUTPUT:-0}" -eq 0 && -n "$panel_url" ]]; then
    dialog_cmd \
      --backtitle "$UI_TITLE" \
      --title "1Panel Installation Successful" \
      --msgbox "1Panel has been successfully installed.\n\nPanel URL: ${panel_url}\nUsername: ${panel_user}\nPassword: ${panel_pass}\n\nPlease save these credentials securely!" 12 70
  fi
}

dd_debian12() {
  local pwd="${1:-}"
  if [[ -z "$pwd" ]]; then
    log "ERROR: dd_debian12 requires a password argument"
    printf 'ERROR: Password cannot be empty.\n' >&2
    return 1
  fi

  local script_url="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
  log "dd_debian12: preparing to install Debian 12"
  run_bash "bash <(curl -sL $script_url || wget -qO- $script_url) debian 12 --password '$pwd'" || return 1
}

dd_debian13() {
  local pwd="${1:-}"
  if [[ -z "$pwd" ]]; then
    log "ERROR: dd_debian13 requires a password argument"
    printf 'ERROR: Password cannot be empty.\n' >&2
    return 1
  fi

  local script_url="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
  log "dd_debian13: preparing to install Debian 13"
  run_bash "bash <(curl -sL $script_url || wget -qO- $script_url) debian 13 --password '$pwd'" || return 1
}

dd_alpine() {
  local pwd="${1:-}"
  if [[ -z "$pwd" ]]; then
    log "ERROR: dd_alpine requires a password argument"
    printf 'ERROR: Password cannot be empty.\n' >&2
    return 1
  fi

  local script_url="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
  log "dd_alpine: preparing to install Alpine"
  run_bash "bash <(curl -sL $script_url || wget -qO- $script_url) alpine 3.21 --password '$pwd'" || return 1
}

install_base() {
  install_speedtest || return 1
  install_btop || return 1
  install_neovim || return 1
  install_nexttrace || return 1
  config_swap "1G" || return 1
  install_zsh || return 1
  config_shell || return 1
  setup_sshd || return 1
  enable_bbr || return 1
}


# ============================
# CLI
# ============================
show_help() {
  cat <<'EOF'
Usage:
  ./init.sh [options]

If no option is provided, the script starts the TUI menu.

System settings:
  sshd                 Configure SSH key login
  bbr                  Enable BBR
  swap                 Configure 1G swap
  swap=4G              Configure custom swap size (supports M/G)

System reinstall:
  debian12=<pwd>       Reinstall Debian 12 with specified root password
  debian13=<pwd>       Reinstall Debian 13 with specified root password
  alpine=<pwd>         Reinstall Alpine with specified root password

Tool installation:
  speedtest            Install speedtest
  btop                 Install btop
  neovim               Install neovim + LazyVim
  nexttrace            Install nexttrace
  shell                Configure current shell rc
  zsh                  Install and configure zsh

Bundle and execution:
  base                 Install base bundle in sequence
  tui                  Launch dialog TUI
  run-selected         Run tasks from selection file or args

Environment:
  LOG_FILE=/tmp/install.log
  UI_LOG_FILE=/tmp/install.ui.log
  SELECTION_FILE=/tmp/init.selection
EOF
}

main() {
  init_log
  require_debian || return 1

  if [[ "$#" -eq 0 ]]; then
    tui_main_menu
    return 0
  fi

  case "${1:-}" in
    -h|--help)
      show_help
      return 0
      ;;
  esac

  install_dependencies || log "WARN: dependency install failed, continue"

  local arg size pwd
  while [[ "$#" -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      tui)
        tui_main_menu
        ;;
      run-selected)
        shift
        run_selected_tasks_with_progress "$@"
        return $?
        ;;
      base)
        install_base
        ;;
      sshd)
        setup_sshd
        ;;
      bbr)
        enable_bbr
        ;;
      swap)
        config_swap "1G"
        ;;
      swap=*)
        size="${arg#swap=}"
        config_swap "${size^^}"
        ;;
      speedtest)
        install_speedtest
        ;;
      btop)
        install_btop
        ;;
      neovim)
        install_neovim
        ;;
      nexttrace)
        install_nexttrace
        ;;
      shell)
        config_shell
        ;;
      zsh)
        install_zsh
        ;;
      debian12=*)
        pwd="${arg#debian12=}"
        dd_debian12 "$pwd"
        ;;
      debian13=*)
        pwd="${arg#debian13=}"
        dd_debian13 "$pwd"
        ;;
      alpine=*)
        pwd="${arg#alpine=}"
        dd_alpine "$pwd"
        ;;
      -h|--help)
        show_help
        ;;
      *)
        log "ERROR: unknown option: $arg"
        printf 'ERROR: unknown option: %s\n\n' "$arg" >&2
        show_help
        return 1
        ;;
    esac
    shift
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

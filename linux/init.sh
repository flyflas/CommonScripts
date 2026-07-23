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
readonly SSH_LOGIN_INFO_MARK="# === SSH LOGIN INFO BY INIT.SH ==="
readonly LSD_ALIAS_MARK="# === LSD ALIASES BY INIT.SH ==="
readonly LSD_CONFIG_DATE_LINE='date: "+%Y/%m/%d %H:%M:%S"'
readonly TARGET_TIMEZONE="Asia/Shanghai"

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

shell_quote() {
  printf '%q' "$1"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

bat_command_exists() {
  command_exists bat || command_exists batcat
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

select_shell_rc_file() {
  local home_dir="$1"
  local shell_path="${2:-}"
  local candidate

  case "$shell_path" in
  *zsh*)
    printf '%s/.zshrc' "$home_dir"
    return 0
    ;;
  *bash*)
    printf '%s/.bashrc' "$home_dir"
    return 0
    ;;
  *fish*)
    printf '%s/.config/fish/config.fish' "$home_dir"
    return 0
    ;;
  esac

  for candidate in "$home_dir/.zshrc" "$home_dir/.bashrc" "$home_dir/.profile"; do
    if [[ -f "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  printf '%s/.profile' "$home_dir"
}

resolve_lsd_target_context() {
  local target_user="${SUDO_USER:-}"
  local passwd_entry
  local target_home="${HOME:-/root}"
  local target_shell="${SHELL:-}"
  local target_uid target_gid

  if [[ -z "$target_user" || "$target_user" == "root" ]]; then
    if [[ -n "${USER:-}" && "${USER:-}" != "root" ]]; then
      target_user="$USER"
    else
      target_user="root"
    fi
  fi

  target_uid="$(id -u "$target_user" 2>/dev/null || id -u)"
  target_gid="$(id -g "$target_user" 2>/dev/null || id -g)"

  if passwd_entry="$(getent passwd "$target_user" 2>/dev/null)"; then
    target_home="$(printf '%s' "$passwd_entry" | awk -F: '{print $6}')"
    target_shell="$(printf '%s' "$passwd_entry" | awk -F: '{print $7}')"
    target_uid="$(printf '%s' "$passwd_entry" | awk -F: '{print $3}')"
    target_gid="$(printf '%s' "$passwd_entry" | awk -F: '{print $4}')"
  fi

  [[ -n "$target_home" ]] || target_home="${HOME:-/root}"
  [[ -n "$target_shell" ]] || target_shell="${SHELL:-}"

  printf '%s\t%s\t%s\t%s\t%s\n' "$target_user" "$target_home" "$target_shell" "$target_uid" "$target_gid"
}

chown_lsd_target_path() {
  local target_uid="$1"
  local target_gid="$2"
  local path="$3"

  [[ "$target_uid" == "0" && "$target_gid" == "0" ]] && return 0
  [[ -e "$path" || -L "$path" ]] || return 0
  run_cmd chown "$target_uid:$target_gid" "$path"
}

configure_lsd_aliases() {
  local home_dir="$1"
  local shell_path="${2:-}"
  local target_uid="${3:-0}"
  local target_gid="${4:-0}"
  local rc_file
  local alias_style="shell"
  local rc_dir

  rc_file="$(select_shell_rc_file "$home_dir" "$shell_path")" || return 1
  rc_dir="$(dirname "$rc_file")"

  case "$rc_file" in
  */config.fish)
    alias_style="fish"
    ;;
  esac

  [[ -d "$rc_dir" ]] || run_cmd mkdir -p "$rc_dir" || return 1
  [[ -f "$rc_file" ]] || run_cmd touch "$rc_file" || return 1

  if grep -Fq "$LSD_ALIAS_MARK" "$rc_file" >>"$LOG_FILE" 2>&1; then
    chown_lsd_target_path "$target_uid" "$target_gid" "$rc_file" || return 1
    if [[ "$rc_dir" == "$home_dir/.config/"* ]]; then
      chown_lsd_target_path "$target_uid" "$target_gid" "$home_dir/.config" || true
      chown_lsd_target_path "$target_uid" "$target_gid" "$rc_dir" || true
    fi
    log "configure_lsd_aliases: marker exists, skip"
    return 0
  fi

  backup_file "$rc_file" || return 1

  {
    printf '\n%s\n' "$LSD_ALIAS_MARK"
    if [[ "$alias_style" == "fish" ]]; then
      printf "alias ls 'lsd'\n"
      printf "alias ll 'lsd -lh'\n"
      printf "alias la 'lsd -lah'\n"
      printf "alias l 'lsd -lAh'\n"
    else
      printf 'alias ls="lsd"\n'
      printf 'alias ll="lsd -lh"\n'
      printf 'alias la="lsd -lah"\n'
      printf 'alias l="lsd -lAh"\n'
    fi
  } >>"$rc_file"

  chown_lsd_target_path "$target_uid" "$target_gid" "$rc_file" || return 1
  if [[ "$rc_dir" == "$home_dir/.config/"* ]]; then
    chown_lsd_target_path "$target_uid" "$target_gid" "$home_dir/.config" || true
    chown_lsd_target_path "$target_uid" "$target_gid" "$rc_dir" || true
  fi

  log "configure_lsd_aliases done: $rc_file"
}

configure_lsd_config() {
  local home_dir="$1"
  local target_uid="${2:-0}"
  local target_gid="${3:-0}"
  local config_dir="$home_dir/.config/lsd"
  local config_file="$config_dir/config.yaml"
  local tmp_file

  [[ -d "$config_dir" ]] || run_cmd mkdir -p "$config_dir" || return 1

  tmp_file="$(mktemp "${config_file}.XXXXXX")" || return 1
  if [[ -f "$config_file" ]]; then
    backup_file "$config_file" || {
      run_cmd rm -f "$tmp_file" || true
      return 1
    }
    awk -v date_line="$LSD_CONFIG_DATE_LINE" '
      BEGIN { seen = 0 }
      /^date:[[:space:]]*/ {
        if (!seen) {
          print date_line
          seen = 1
        }
        next
      }
      { print }
      END {
        if (!seen) {
          print date_line
        }
      }
    ' "$config_file" >"$tmp_file" || {
      run_cmd rm -f "$tmp_file" || true
      return 1
    }
  else
    printf '%s\n' "$LSD_CONFIG_DATE_LINE" >"$tmp_file" || {
      run_cmd rm -f "$tmp_file" || true
      return 1
    }
  fi

  if [[ -L "$config_file" ]]; then
    run_cmd cp "$tmp_file" "$config_file" || {
      run_cmd rm -f "$tmp_file" || true
      return 1
    }
    run_cmd rm -f "$tmp_file" || true
  else
    run_cmd mv "$tmp_file" "$config_file" || {
      run_cmd rm -f "$tmp_file" || true
      return 1
    }
  fi

  chown_lsd_target_path "$target_uid" "$target_gid" "$home_dir/.config" || true
  chown_lsd_target_path "$target_uid" "$target_gid" "$config_dir" || return 1
  chown_lsd_target_path "$target_uid" "$target_gid" "$config_file" || return 1
  log "configure_lsd_config done: $config_file"
}

configure_lsd_post_install() {
  local target_user target_home target_shell target_uid target_gid

  IFS=$'\t' read -r target_user target_home target_shell target_uid target_gid < <(resolve_lsd_target_context) || return 1
  configure_lsd_aliases "$target_home" "$target_shell" "$target_uid" "$target_gid" || return 1
  configure_lsd_config "$target_home" "$target_uid" "$target_gid" || return 1
}

resolve_fastfetch_target_context() {
  resolve_lsd_target_context
}

chown_fastfetch_target_path() {
  chown_lsd_target_path "$@"
}

write_fastfetch_config_template() {
  local output_file="$1"

  cat >"$output_file" <<'EOF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "padding": {
            "top": 2
        }
    },
    "display": {
        "separator": " -> "
    },
    "modules": [
        "title",
        "separator",
        {
            "type": "os",
            "key": " OS",
            "keyColor": "yellow",
            "format": "{2}"
        },
        {
            "type": "os",
            "key": "├─{icon}",
            "keyColor": "yellow",
            "format": "{pretty-name} {arch}"
        },
        {
            "type": "kernel",
            "key": "├─",
            "keyColor": "yellow"
        },

        {
            "type": "packages",
            "key": "├─󰏖",
            "keyColor": "yellow"
        },
        {
            "type": "uptime",
            "key": "╰─󰅐",
            "keyColor": "yellow"
        },
        "break",

        {
            "type": "shell",
            "key": " SHELL",
            "keyColor": "blue"
        },
        {
            "type": "terminal",
            "key": "├─",
            "keyColor": "blue"
        },
        {
            "type": "terminalfont",
            "key": "├─",
            "keyColor": "blue"
        },
        {
            "type": "lm",
            "key": "╰─󰧨",
            "keyColor": "blue"
        },
        "break",

        {
            "type": "host",
            "key": "󰌢 PC",
            "keyColor": "green"
        },
        {
            "type": "cpu",
            "key": "├─󰻠",
            "keyColor": "green",
            "format": "{name} ({cores-physical}C/{cores-logical}T)"
        },
        {
            "type": "gpu",
            "key": "├─󰍛",
            "keyColor": "green"
        },
        {
            "type": "memory",
            "key": "├─󰑭",
            "keyColor": "green"
        },
        {
            "type": "disk",
            "key": "├─",
            "keyColor": "green"
        },
        {
            "type": "swap",
            "key": "╰─󰓡",
            "keyColor": "green"
        },

        "break",
        "colors"
    ]
}
EOF
}

configure_fastfetch_config() {
  local home_dir="$1"
  local target_uid="${2:-0}"
  local target_gid="${3:-0}"
  local config_dir="$home_dir/.config/fastfetch"
  local config_file="$config_dir/config.jsonc"
  local tmp_file

  [[ -d "$config_dir" ]] || run_cmd mkdir -p "$config_dir" || return 1

  tmp_file="$(mktemp "${config_file}.XXXXXX")" || return 1
  write_fastfetch_config_template "$tmp_file" || {
    run_cmd rm -f "$tmp_file" || true
    return 1
  }

  if [[ -f "$config_file" ]]; then
    backup_file "$config_file" || {
      run_cmd rm -f "$tmp_file" || true
      return 1
    }
  fi

  if [[ -L "$config_file" ]]; then
    run_cmd cp "$tmp_file" "$config_file" || {
      run_cmd rm -f "$tmp_file" || true
      return 1
    }
    run_cmd rm -f "$tmp_file" || true
  else
    run_cmd mv "$tmp_file" "$config_file" || {
      run_cmd rm -f "$tmp_file" || true
      return 1
    }
  fi

  chown_fastfetch_target_path "$target_uid" "$target_gid" "$home_dir/.config" || true
  chown_fastfetch_target_path "$target_uid" "$target_gid" "$config_dir" || return 1
  chown_fastfetch_target_path "$target_uid" "$target_gid" "$config_file" || return 1
  log "configure_fastfetch_config done: $config_file"
}

configure_fastfetch_post_install() {
  local target_user target_home target_shell target_uid target_gid

  IFS=$'\t' read -r target_user target_home target_shell target_uid target_gid < <(resolve_fastfetch_target_context) || return 1
  configure_fastfetch_config "$target_home" "$target_uid" "$target_gid" || return 1
}

# ============================
# Locale helpers
# ============================
normalize_locale_name() {
  local value="${1:-}"
  value="${value%%@*}"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
  *.utf8) value="${value%.utf8}.utf-8" ;;
  esac
  printf '%s' "$value"
}

is_zh_cn_utf8_locale() {
  local value
  value="$(normalize_locale_name "${1:-}")"
  [[ "$value" == "zh_cn.utf-8" ]]
}

current_locale_effective_value() {
  if [[ -n "${LC_ALL:-}" ]]; then
    printf '%s' "$LC_ALL"
  elif [[ -n "${LC_CTYPE:-}" ]]; then
    printf '%s' "$LC_CTYPE"
  else
    printf '%s' "${LANG:-}"
  fi
}

current_locale_charmap() {
  locale charmap 2>/dev/null || true
}

current_timezone_value() {
  command_exists timedatectl || return 1
  timedatectl show -p Timezone --value 2>/dev/null
}

is_current_terminal_zh_cn_utf8() {
  local effective charmap
  effective="$(current_locale_effective_value)"
  charmap="$(current_locale_charmap)"
  charmap="$(printf '%s' "$charmap" | tr '[:lower:]' '[:upper:]')"

  is_zh_cn_utf8_locale "$effective" && [[ "$charmap" == "UTF-8" ]]
}

locale_status_text() {
  local effective charmap
  effective="$(current_locale_effective_value)"
  charmap="$(current_locale_charmap)"

  printf 'Current effective locale: %s\n' "${effective:-unset}"
  printf 'Current locale charmap : %s\n' "${charmap:-unknown}"
  printf 'LC_ALL                 : %s\n' "${LC_ALL:-unset}"
  printf 'LC_CTYPE               : %s\n' "${LC_CTYPE:-unset}"
  printf 'LANG                   : %s\n' "${LANG:-unset}"
}

locale_status_dialog_text() {
  local effective charmap
  effective="$(current_locale_effective_value)"
  charmap="$(current_locale_charmap)"

  printf 'Current effective locale: %s\\n' "${effective:-unset}"
  printf 'Current locale charmap : %s\\n' "${charmap:-unknown}"
  printf 'LC_ALL                 : %s\\n' "${LC_ALL:-unset}"
  printf 'LC_CTYPE               : %s\\n' "${LC_CTYPE:-unset}"
  printf 'LANG                   : %s' "${LANG:-unset}"
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

ensure_reinstall_download_tools() {
  if command_exists curl && command_exists wget; then
    return 0
  fi

  log "System reinstall requires curl and wget; installing missing download tools"
  install_packages curl wget || return 1

  command_exists curl && command_exists wget
}

prepare_reinstall_certificates() {
  log "System reinstall: refreshing apt metadata and reinstalling ca-certificates"
  run_cmd apt update || return 1
  run_cmd env DEBIAN_FRONTEND=noninteractive apt install -y --reinstall ca-certificates || return 1
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
      --ok-label "OK" \
      --msgbox "Current terminal: ${rows}x${cols}\nMinimum required: 22x82\n\nPlease enlarge the terminal and retry." 10 70
    return 1
  fi
}

map_selection_token() {
  local token="$1"
  case "$token" in
  SSHD | setup_sshd) echo "setup_sshd" ;;
  BBR | enable_bbr) echo "enable_bbr" ;;
  Swap | config_swap) echo "config_swap=1G" ;;
  TimeZone | ShanghaiTimezone | config_timezone_asia_shanghai) echo "config_timezone_asia_shanghai" ;;
  1Panel | install_1panel) echo "install_1panel" ;;
  Btop | install_btop) echo "install_btop" ;;
  Bat | install_bat) echo "install_bat" ;;
  Docker | install_docker) echo "install_docker" ;;
  Fastfetch | install_fastfetch) echo "install_fastfetch" ;;
  Lsd | install_lsd) echo "install_lsd" ;;
  Lazygit | install_lazygit) echo "install_lazygit" ;;
  Ncdu | install_ncdu) echo "install_ncdu" ;;
  Neovim | install_neovim) echo "install_neovim" ;;
  NextTrace | install_nexttrace) echo "install_nexttrace" ;;
  Singbox | install_singbox) echo "install_singbox" ;;
  SpeedTest | install_speedtest) echo "install_speedtest" ;;
  Yazi | install_yazi) echo "install_yazi" ;;
  Zsh | install_zsh) echo "install_zsh" ;;
  Debian12 | dd_debian12) echo "dd_debian12" ;;
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
      --menu "Select one item to configure:" 17 70 7 \
      SSHD "Configure SSH key login" \
      BBR "Enable BBR congestion control" \
      Swap "Configure swap space" \
      TimeZone "Set timezone to Asia/Shanghai" \
      LANG "Set LANG=zh_CN.UTF-8" \
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
          --ok-label "OK" \
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
        mem_total_gb=$(((mem_total_kb + 524288) / 1048576))
        [[ "$mem_total_gb" -eq 0 ]] && mem_total_gb=1
      else
        # Fallback if meminfo is unreadable
        mem_total_gb=1
      fi

      if [[ "$mem_total_gb" -lt 2 ]]; then
        recommend_gb=$((mem_total_gb > 0 ? mem_total_gb * 2 : 1))
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
    TimeZone)
      local timezone_current timezone_prompt
      if timezone_current="$(current_timezone_value)"; then
        timezone_prompt="Current timezone: ${timezone_current:-unknown}\nTarget timezone : $TARGET_TIMEZONE\n\nDo you want to set the system timezone to $TARGET_TIMEZONE?"
      else
        timezone_prompt="Current timezone: unavailable (timedatectl not found or not usable)\nTarget timezone : $TARGET_TIMEZONE\n\nDo you want to set the system timezone to $TARGET_TIMEZONE?"
      fi

      if dialog_cmd \
        --backtitle "$UI_TITLE" \
        --title "Set System Timezone" \
        --yes-label "Confirm" \
        --no-label "Cancel" \
        --yesno "$timezone_prompt" 9 70; then
        dialog_cmd --infobox "Configuring system timezone...\nPlease wait." 5 45
        clear
        if config_timezone_asia_shanghai; then
          dialog_cmd \
            --backtitle "$UI_TITLE" \
            --title "Timezone Configured" \
            --ok-label "OK" \
            --msgbox "System timezone has been set to $TARGET_TIMEZONE." 7 58
        else
          dialog_cmd \
            --backtitle "$UI_TITLE" \
            --title "Timezone Configuration Failed" \
            --ok-label "OK" \
            --msgbox "Failed to set system timezone to $TARGET_TIMEZONE.\n\nSee log: $LOG_FILE" 8 64
        fi
      fi
      ;;
    LANG)
      local locale_msg lang_prompt
      locale_msg="$(locale_status_dialog_text)"
      if is_current_terminal_zh_cn_utf8; then
        lang_prompt="Current terminal is already using zh_CN.UTF-8.\n\n${locale_msg}\n\nThis will ensure the system default LANG is set to zh_CN.UTF-8.\n\nDo you want to continue?"
      else
        lang_prompt="Current terminal is not using zh_CN.UTF-8.\n\n${locale_msg}\n\nThis will set the system default LANG=zh_CN.UTF-8.\nIt will not change LC_ALL or LC_CTYPE in the current terminal.\nYou may need to reconnect or log in again for the new default to apply.\n\nDo you want to continue?"
      fi

      if dialog_cmd \
        --backtitle "$UI_TITLE" \
        --title "Set System Language" \
        --yes-label "Confirm" \
        --no-label "Cancel" \
        --yesno "$lang_prompt" 18 76; then
        dialog_cmd --infobox "Configuring system language...\nPlease wait." 5 40
        clear
        if config_lang_zh_utf8; then
          dialog_cmd \
            --backtitle "$UI_TITLE" \
            --title "Language Configured" \
            --ok-label "OK" \
            --msgbox "System LANG has been set to zh_CN.UTF-8.\n\nIf LC_ALL or LC_CTYPE is set in your shell, SSH client, terminal profile, or service environment, it may still override LANG until removed or changed.\n\nReconnect or log in again for the new default to apply." 12 72
        else
          dialog_cmd \
            --backtitle "$UI_TITLE" \
            --title "Language Configuration Failed" \
            --ok-label "OK" \
            --msgbox "Failed to configure LANG=zh_CN.UTF-8.\n\nSee log: $LOG_FILE" 8 64
        fi
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
  local d_bat
  local d_docker
  local d_fastfetch
  local d_lsd
  local d_lazygit
  local d_ncdu
  local d_neovim
  local d_nexttrace
  local d_singbox
  local d_speedtest
  local d_yazi
  local d_zsh

  d_1panel=$(printf "%-25s" "Server control panel")
  d_btop=$(printf "%-25s" "Resource monitor")
  d_bat=$(printf "%-25s" "Terminal cat viewer")
  d_docker=$(printf "%-25s" "Container engine")
  d_fastfetch=$(printf "%-25s" "System information tool")
  d_lsd=$(printf "%-25s" "Modern ls replacement")
  d_lazygit=$(printf "%-25s" "Terminal git interface")
  d_ncdu=$(printf "%-25s" "Disk usage analyzer")
  d_neovim=$(printf "%-25s" "Text editor (LazyVim)")
  d_nexttrace=$(printf "%-25s" "Visual route tracker")
  d_singbox=$(printf "%-25s" "Universal proxy platform")
  d_speedtest=$(printf "%-25s" "Network bandwidth tester")
  d_yazi=$(printf "%-25s" "Terminal file manager")
  d_zsh=$(printf "%-25s" "Shell env (oh-my-zsh)")

  # Probe installed status and append [OK] or equivalent padding for uniform highlighting
  if systemctl is-active 1panel.service >/dev/null 2>&1; then d_1panel+=" [OK]"; else d_1panel+="     "; fi
  if command_exists btop; then d_btop+=" [OK]"; else d_btop+="     "; fi
  if bat_command_exists; then d_bat+=" [OK]"; else d_bat+="     "; fi
  if command_exists docker; then d_docker+=" [OK]"; else d_docker+="     "; fi
  if command_exists fastfetch; then d_fastfetch+=" [OK]"; else d_fastfetch+="     "; fi
  if command_exists lsd; then d_lsd+=" [OK]"; else d_lsd+="     "; fi
  if command_exists lazygit; then d_lazygit+=" [OK]"; else d_lazygit+="     "; fi
  if command_exists ncdu; then d_ncdu+=" [OK]"; else d_ncdu+="     "; fi
  if command_exists nvim; then d_neovim+=" [OK]"; else d_neovim+="     "; fi
  if command_exists nexttrace; then d_nexttrace+=" [OK]"; else d_nexttrace+="     "; fi
  if systemctl is-active sing-box.service >/dev/null 2>&1; then d_singbox+=" [OK]"; else d_singbox+="     "; fi
  if command_exists speedtest; then d_speedtest+=" [OK]"; else d_speedtest+="     "; fi
  if command_exists yazi; then d_yazi+=" [OK]"; else d_yazi+="     "; fi
  if command_exists zsh; then d_zsh+=" [OK]"; else d_zsh+="     "; fi

  if collect_checklist \
    "Tool Installation" \
    "Select one or more tools to install/update:" \
    1Panel "$d_1panel" OFF \
    Btop "$d_btop" OFF \
    Bat "$d_bat" OFF \
    Docker "$d_docker" OFF \
    Fastfetch "$d_fastfetch" OFF \
    Lsd "$d_lsd" OFF \
    Lazygit "$d_lazygit" OFF \
    Ncdu "$d_ncdu" OFF \
    Neovim "$d_neovim" OFF \
    NextTrace "$d_nexttrace" OFF \
    Singbox "$d_singbox" OFF \
    SpeedTest "$d_speedtest" OFF \
    Yazi "$d_yazi" OFF \
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
  cat <<EOF >"$temp_rc"
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
    if ! ensure_reinstall_download_tools; then
      dialog_cmd \
        --backtitle "$UI_TITLE" \
        --title "Dependency Installation Failed" \
        --ok-label "OK" \
        --msgbox "Failed to install required download tools: curl and wget.\n\nSystem reinstall cannot continue.\n\nSee log: $LOG_FILE" 10 68
      return 1
    fi

    local pwd pwd2 username status_pwd status_pwd2 status_username
    status_username=0
    username="$(dialog_cmd \
      --stdout \
      --backtitle "$UI_TITLE" \
      --title "Username" \
      --ok-label "Confirm" \
      --cancel-label "Back" \
      --inputbox "Set username for the new system. Leave empty to use root:" 10 60)" || status_username=$?

    if [[ "$status_username" -ne 0 ]]; then
      return 0
    fi
    [[ -n "$username" ]] || username="root"

    while true; do
      status_pwd=0
      pwd="$(dialog_cmd \
        --stdout \
        --insecure \
        --backtitle "$UI_TITLE" \
        --title "User Password" \
        --ok-label "Confirm" \
        --cancel-label "Back" \
        --passwordbox "Set a password for the selected user:" 10 50)" || status_pwd=$?

      if [[ "$status_pwd" -ne 0 || -z "$pwd" ]]; then
        return 0
      fi

      status_pwd2=0
      pwd2="$(dialog_cmd \
        --stdout \
        --insecure \
        --backtitle "$UI_TITLE" \
        --title "Confirm User Password" \
        --ok-label "Confirm" \
        --cancel-label "Back" \
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
          --ok-label "OK" \
          --msgbox "The two passwords do not match.\nPlease try again." 8 40
      fi
    done

    local task_name
    [[ "$choice" == "Debian12" ]] && task_name="dd_debian12"
    [[ "$choice" == "Debian13" ]] && task_name="dd_debian13"
    [[ "$choice" == "Alpine" ]] && task_name="dd_alpine"

    local task_item="${task_name}=${pwd}"$'\t'"${username}"

    clear
    run_selected_tasks_with_progress --completion-reboot "$task_item"
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
  TASK_ARG2=""
  [[ "$item" == *"="* ]] && TASK_ARG="${item#*=}"
  if [[ "$TASK_ARG" == *$'\t'* ]]; then
    TASK_ARG2="${TASK_ARG#*$'\t'}"
    TASK_ARG="${TASK_ARG%%$'\t'*}"
  fi
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

apply_reinstall_username_to_tasks() {
  local username="${1:-}"
  [[ -n "$username" ]] || return 0

  local idx item
  for idx in "${!SELECTED_TASKS[@]}"; do
    item="${SELECTED_TASKS[$idx]}"
    case "$item" in
    dd_debian12=* | dd_debian13=* | dd_alpine=*)
      [[ "$item" == *$'\t'* ]] || SELECTED_TASKS[$idx]="${item}"$'\t'"${username}"
      ;;
    esac
  done
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
  if [[ -n "$TASK_ARG2" ]]; then
    "$TASK_NAME" "$TASK_ARG" "$TASK_ARG2"
  elif [[ -n "$TASK_ARG" ]]; then
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
  config_timezone_asia_shanghai*) echo "Set Timezone Asia/Shanghai" ;;
  config_lang_zh_utf8*) echo "Configure LANG zh_CN.UTF-8" ;;
  install_1panel*) echo "Install 1Panel" ;;
  install_btop*) echo "Install btop" ;;
  install_bat*) echo "Install bat" ;;
  install_docker*) echo "Install Docker" ;;
  install_fastfetch*) echo "Install fastfetch" ;;
  install_lsd*) echo "Install lsd" ;;
  install_lazygit*) echo "Install lazygit" ;;
  install_ncdu*) echo "Install ncdu" ;;
  install_neovim*) echo "Install Neovim" ;;
  install_nexttrace*) echo "Install NextTrace" ;;
  install_singbox*) echo "Install Sing-box" ;;
  install_speedtest*) echo "Install SpeedTest" ;;
  install_yazi*) echo "Install Yazi" ;;
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

confirm_and_reboot() {
  if dialog_cmd \
    --backtitle "$UI_TITLE" \
    --title "Confirm Reboot" \
    --yes-label "Reboot" \
    --no-label "Cancel" \
    --yesno "Reboot the system now?" 7 44; then
    if run_cmd systemctl reboot; then
      return 0
    fi
    if run_cmd reboot; then
      return 0
    fi
    dialog_cmd \
      --backtitle "$UI_TITLE" \
      --title "Reboot Failed" \
      --ok-label "OK" \
      --msgbox "Failed to reboot the system.\n\nTried: systemctl reboot\nThen: reboot\n\nSee log: $LOG_FILE" 10 64
  fi
}

run_selected_tasks_with_progress() {
  init_log
  local show_reboot=0
  if [[ "${1:-}" == "--completion-reboot" ]]; then
    show_reboot=1
    shift
  fi

  load_selected_tasks "$@"
  apply_reinstall_username_to_tasks "${REINSTALL_USERNAME:-}"

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
    percent=$(((idx - 1) * 100 / total))

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

      if [[ -n "$TASK_ARG2" ]]; then
        "$TASK_NAME" "$TASK_ARG" "$TASK_ARG2"
      elif [[ -n "$TASK_ARG" ]]; then
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
  [[ "$failed" -eq 0 ]] && percent=100 || percent=$(((idx - 1) * 100 / total))

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

  while true; do
    local action=0
    if [[ "$show_reboot" -eq 1 ]]; then
      dialog_cmd \
        --backtitle "$UI_TITLE" \
        --title "Installation Complete" \
        --yes-label "View Log" \
        --no-label "Reboot" \
        --extra-button \
        --extra-label "Return" \
        --yesno "$msg" 14 60 || action=$?
    else
      dialog_cmd \
        --backtitle "$UI_TITLE" \
        --title "Installation Complete" \
        --yes-label "View Log" \
        --no-label "Return" \
        --yesno "$msg" 14 60 || action=$?
    fi

    case "$action" in
    0)
      dialog_cmd \
        --backtitle "$UI_TITLE" \
        --title "Full Installation Log" \
        --exit-label "Return" \
        --textbox "$LOG_FILE" 22 78
      ;;
    1)
      if [[ "$show_reboot" -eq 1 ]]; then
        confirm_and_reboot
      else
        break
      fi
      ;;
    3 | 255)
      break
      ;;
    *)
      break
      ;;
    esac
  done

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

install_bat() {
  require_root || return 1
  install_packages bat || return 1

  if ! command_exists bat && [[ -x /usr/bin/batcat ]]; then
    run_cmd mkdir -p /usr/local/bin || return 1
    if [[ -e /usr/local/bin/bat || -L /usr/local/bin/bat ]]; then
      if [[ "$(readlink /usr/local/bin/bat 2>/dev/null || true)" != "/usr/bin/batcat" ]]; then
        log "ERROR: /usr/local/bin/bat exists and does not point to /usr/bin/batcat"
        return 1
      fi
    else
      run_cmd ln -s /usr/bin/batcat /usr/local/bin/bat || return 1
    fi
  fi

  bat_command_exists
}

install_fastfetch() {
  require_root || return 1
  install_packages curl ca-certificates || return 1

  local arch release_arch api_url release_json deb_url tmp_deb

  arch="$(uname -m)"
  case "$arch" in
  x86_64)
    release_arch="amd64"
    ;;
  aarch64 | arm64)
    release_arch="aarch64"
    ;;
  *)
    log "ERROR: unsupported architecture for fastfetch: $arch"
    return 1
    ;;
  esac

  api_url="https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest"
  release_json="$(mktemp "/tmp/fastfetch-release-${release_arch}.XXXXXX.json")" || return 1
  run_cmd curl -fL --retry 3 --connect-timeout 10 "$api_url" -o "$release_json" || {
    run_cmd rm -f "$release_json" || true
    return 1
  }
  deb_url="$(sed -nE "s|.*\"browser_download_url\": \"([^\"]*/fastfetch-linux-${release_arch}\.deb)\".*|\1|p" "$release_json" | head -n 1)"
  run_cmd rm -f "$release_json" || true

  if [[ -z "$deb_url" ]]; then
    log "ERROR: unable to find fastfetch ${release_arch} .deb asset from latest release"
    return 1
  fi

  tmp_deb="$(mktemp "/tmp/fastfetch-${release_arch}.XXXXXX.deb")" || return 1
  run_cmd curl -fL --retry 3 --connect-timeout 10 "$deb_url" -o "$tmp_deb" || {
    run_cmd rm -f "$tmp_deb" || true
    return 1
  }
  run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp_deb" || {
    run_cmd rm -f "$tmp_deb" || true
    return 1
  }
  run_cmd rm -f "$tmp_deb" || true

  command_exists fastfetch || return 1
  configure_fastfetch_post_install || return 1
  log "install_fastfetch done"
}

install_lsd() {
  require_root || return 1
  install_packages curl ca-certificates || return 1

  local arch deb_arch api_url release_json deb_url tmp_deb

  arch="$(uname -m)"
  case "$arch" in
  x86_64)
    deb_arch="amd64"
    ;;
  aarch64 | arm64)
    deb_arch="arm64"
    ;;
  *)
    log "ERROR: unsupported architecture for lsd: $arch"
    return 1
    ;;
  esac

  api_url="https://api.github.com/repos/lsd-rs/lsd/releases/latest"
  release_json="$(mktemp "/tmp/lsd-release-${deb_arch}.XXXXXX.json")" || return 1
  run_cmd curl -fL --retry 3 --connect-timeout 10 "$api_url" -o "$release_json" || {
    run_cmd rm -f "$release_json" || true
    return 1
  }
  deb_url="$(sed -nE "s|.*\"browser_download_url\": \"([^\"]+_${deb_arch}\.deb)\".*|\1|p" "$release_json" | head -n 1)"
  run_cmd rm -f "$release_json" || true

  if [[ -z "$deb_url" ]]; then
    log "ERROR: unable to find lsd ${deb_arch} .deb asset from latest release"
    return 1
  fi

  tmp_deb="$(mktemp "/tmp/lsd-${deb_arch}.XXXXXX.deb")" || return 1
  run_cmd curl -fL --retry 3 --connect-timeout 10 "$deb_url" -o "$tmp_deb" || {
    run_cmd rm -f "$tmp_deb" || true
    return 1
  }
  run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp_deb" || {
    run_cmd rm -f "$tmp_deb" || true
    return 1
  }
  run_cmd rm -f "$tmp_deb" || true

  command_exists lsd || return 1
  configure_lsd_post_install || return 1
  log "install_lsd done"
}

install_lazygit() {
  require_root || return 1
  install_packages curl ca-certificates tar gzip git || return 1

  local arch release_arch api_url release_json asset_url tmp_tar tmp_dir

  arch="$(uname -m)"
  case "$arch" in
  x86_64)
    release_arch="x86_64"
    ;;
  aarch64 | arm64)
    release_arch="arm64"
    ;;
  *)
    log "ERROR: unsupported architecture for lazygit: $arch"
    return 1
    ;;
  esac

  (
    set -Eeuo pipefail
    api_url="https://api.github.com/repos/jesseduffield/lazygit/releases/latest"
    release_json="$(mktemp "/tmp/lazygit-release-${release_arch}.XXXXXX.json")"
    tmp_tar=""
    tmp_dir=""
    trap 'rm -rf "$release_json" "$tmp_tar" "$tmp_dir" >/dev/null 2>&1 || true' EXIT

    tmp_tar="$(mktemp "/tmp/lazygit-${release_arch}.XXXXXX.tar.gz")"
    tmp_dir="$(mktemp -d "/tmp/lazygit-extract-${release_arch}.XXXXXX")"

    run_cmd curl -fL --retry 3 --connect-timeout 10 "$api_url" -o "$release_json"
    asset_url="$(sed -nE "s|.*\"browser_download_url\": \"([^\"]*/lazygit_[^\"]*_linux_${release_arch}\.tar\.gz)\".*|\1|p" "$release_json" | head -n 1)"

    if [[ -z "$asset_url" ]]; then
      log "ERROR: unable to find lazygit ${release_arch} tar.gz asset from latest release"
      exit 1
    fi

    run_cmd curl -fL --retry 3 --connect-timeout 10 "$asset_url" -o "$tmp_tar"
    run_cmd tar -xzf "$tmp_tar" -C "$tmp_dir"

    [[ -f "$tmp_dir/lazygit" ]] || {
      log "ERROR: extracted lazygit binary not found in $tmp_dir"
      exit 1
    }

    run_cmd mkdir -p /usr/local/bin
    run_cmd install -m 0755 "$tmp_dir/lazygit" /usr/local/bin/lazygit
    command_exists lazygit
    run_cmd /usr/local/bin/lazygit --version
    log "install_lazygit done"
  )
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
  aarch64 | arm64)
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

config_timezone_asia_shanghai() {
  local actual

  require_root || return 1

  if ! command_exists timedatectl; then
    log "ERROR: timedatectl not found; cannot set timezone to $TARGET_TIMEZONE"
    printf 'ERROR: timedatectl not found; cannot set timezone to %s.\n' "$TARGET_TIMEZONE" >&2
    return 1
  fi

  log "config_timezone_asia_shanghai: setting timezone to $TARGET_TIMEZONE"
  if ! run_cmd timedatectl set-timezone "$TARGET_TIMEZONE"; then
    log "ERROR: timedatectl set-timezone $TARGET_TIMEZONE failed"
    printf 'ERROR: failed to set timezone to %s.\n' "$TARGET_TIMEZONE" >&2
    return 1
  fi

  actual="$(timedatectl show -p Timezone --value 2>>"$LOG_FILE" || true)"
  if [[ "$actual" != "$TARGET_TIMEZONE" ]]; then
    log "ERROR: timezone verification failed; expected=$TARGET_TIMEZONE actual=${actual:-unset}"
    printf 'ERROR: timezone verification failed; expected %s, got %s.\n' "$TARGET_TIMEZONE" "${actual:-unset}" >&2
    return 1
  fi

  log "config_timezone_asia_shanghai done: timezone=$actual"
  printf 'Timezone set to %s.\n' "$actual"
}

config_shell() {
  local target_user
  local home_dir
  local shell_path
  local target_uid
  local target_gid
  local rc_file=""

  IFS=$'\t' read -r target_user home_dir shell_path target_uid target_gid < <(resolve_lsd_target_context) || return 1

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
  else
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

    chown_lsd_target_path "$target_uid" "$target_gid" "$rc_file" || return 1
    log "config_shell user rc done: $rc_file"
  fi

  [[ -f "$home_dir/.hushlogin" ]] || run_cmd touch "$home_dir/.hushlogin" || return 1
  chown_lsd_target_path "$target_uid" "$target_gid" "$home_dir/.hushlogin" || return 1

  configure_ssh_login_info_global_rc || return 1

  log "config_shell done: $rc_file; hushlogin=$home_dir/.hushlogin"
  if [[ "${LIVE_OUTPUT:-0}" -eq 0 ]]; then
    dialog_cmd --backtitle "$UI_TITLE" --title "Shell Configured" --ok-label "OK" --msgbox "Shell profile has been successfully configured in $rc_file." 8 60
  fi
}

configure_ssh_login_info_global_rc() {
  local rc_file
  local found=0

  for rc_file in /etc/bash.bashrc /etc/zsh/zshrc; do
    [[ -f "$rc_file" ]] && found=1
  done

  if [[ "$found" -eq 0 ]]; then
    log "configure_ssh_login_info_global_rc: no supported global rc files found"
    return 0
  fi

  require_root || return 1

  for rc_file in /etc/bash.bashrc /etc/zsh/zshrc; do
    [[ -f "$rc_file" ]] || continue

    if grep -Fq "$SSH_LOGIN_INFO_MARK" "$rc_file" >>"$LOG_FILE" 2>&1; then
      log "configure_ssh_login_info_global_rc: marker exists, skip $rc_file"
      continue
    fi

    backup_file "$rc_file" || return 1
    {
      printf '\n%s\n' "$SSH_LOGIN_INFO_MARK"
      printf 'if [[ -o interactive && -n "$SSH_CONNECTION" && -t 1 ]]; then\n'
      printf '    clear\n'
      printf '    command -v fastfetch >/dev/null 2>&1 && fastfetch\n'
      printf '\n'
      printf '    uname -r\n'
      printf '    uname -v\n'
      printf 'fi\n'
    } >>"$rc_file"

    log "configure_ssh_login_info_global_rc done: $rc_file"
  done
}

config_lang_zh_utf8() {
  require_debian || return 1
  require_root || return 1
  install_packages locales || return 1

  local locale_gen="/etc/locale.gen"
  local default_locale="/etc/default/locale"
  local locale_line="zh_CN.UTF-8 UTF-8"
  local lang_line="LANG=zh_CN.UTF-8"

  [[ -f "$locale_gen" ]] && backup_file "$locale_gen" || true
  [[ -f "$default_locale" ]] && backup_file "$default_locale" || true

  if grep -Eq '^[[:space:]]*#?[[:space:]]*zh_CN\.UTF-8[[:space:]]+UTF-8[[:space:]]*$' "$locale_gen" >>"$LOG_FILE" 2>&1; then
    run_cmd sed -i -E 's|^[[:space:]]*#?[[:space:]]*(zh_CN\.UTF-8[[:space:]]+UTF-8)[[:space:]]*$|\1|' "$locale_gen" || return 1
  else
    ensure_line_in_file "$locale_gen" "$locale_line"
  fi

  run_cmd locale-gen zh_CN.UTF-8 || return 1
  run_cmd update-locale LANG=zh_CN.UTF-8 || return 1

  if [[ ! -f "$default_locale" ]]; then
    log "ERROR: $default_locale was not created"
    return 1
  fi

  if ! grep -Fxq "$lang_line" "$default_locale" >>"$LOG_FILE" 2>&1; then
    log "ERROR: $default_locale does not contain $lang_line"
    return 1
  fi

  log "locale status after config:"
  locale_status_text | while IFS= read -r line; do
    log "$line"
  done
  log "config_lang_zh_utf8 done"
}

confirm_cli_lang_change() {
  [[ -t 0 && -t 1 ]] || return 0

  printf '%s\n\n' "$(locale_status_text)"

  if is_current_terminal_zh_cn_utf8; then
    printf 'Current terminal is already using zh_CN.UTF-8.\n'
    printf 'Apply system LANG=zh_CN.UTF-8 anyway? [y/N] '
  else
    printf 'Current terminal is not using zh_CN.UTF-8.\n'
    printf 'This will set the system default LANG=zh_CN.UTF-8, but will not override current LC_ALL/LC_CTYPE.\n'
    printf 'Reconnect or log in again for the new default to apply.\n'
    printf 'Continue? [y/N] '
  fi

  local answer
  read -r answer
  [[ "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" || "$answer" == "YES" ]]
}

cli_config_lang_zh_utf8() {
  confirm_cli_lang_change || return 1
  config_lang_zh_utf8 || return 1

  if ! is_current_terminal_zh_cn_utf8; then
    printf 'System LANG has been set to zh_CN.UTF-8. Current terminal is still not using zh_CN.UTF-8; reconnect or log in again for the new default to apply.\n'
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
      run_cmd dd if=/dev/zero of="$swap_file" bs=1M count="$((${swap_size%G} * 1024))" status=none || return 1
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
    dialog_cmd --backtitle "$UI_TITLE" --title "Swap Configured" --ok-label "OK" --msgbox "Swap space has been successfully configured to ${swap_size}." 8 40
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
      --ok-label "OK" \
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
      dialog_cmd --backtitle "$UI_TITLE" --title "BBR Enabled" --ok-label "OK" --msgbox "BBR congestion control has been successfully enabled." 8 50
    fi
    return 0
  fi
}

install_ncdu() {
  require_root || return 1
  install_packages ncdu
  command_exists ncdu
}

install_yazi() {
  require_root || return 1
  install_packages curl ca-certificates || return 1

  local arch yazi_arch deb_url tmp_deb dep
  local -a optional_deps=(ffmpeg 7zip jq poppler-utils fd-find ripgrep fzf zoxide imagemagick)

  arch="$(uname -m)"
  case "$arch" in
  x86_64)
    yazi_arch="x86_64"
    ;;
  aarch64 | arm64)
    yazi_arch="aarch64"
    ;;
  *)
    log "ERROR: unsupported architecture for yazi: $arch"
    return 1
    ;;
  esac

  for dep in "${optional_deps[@]}"; do
    install_packages "$dep" || log "WARN: failed to install optional yazi dependency: $dep"
  done

  deb_url="https://github.com/sxyazi/yazi/releases/latest/download/yazi-${yazi_arch}-unknown-linux-gnu.deb"
  tmp_deb="$(mktemp "/tmp/yazi-${yazi_arch}.XXXXXX.deb")" || return 1

  run_cmd curl -fL --retry 3 --connect-timeout 10 "$deb_url" -o "$tmp_deb" || {
    run_cmd rm -f "$tmp_deb" || true
    return 1
  }
  run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp_deb" || {
    run_cmd rm -f "$tmp_deb" || true
    return 1
  }
  run_cmd rm -f "$tmp_deb" || true

  command_exists yazi || return 1
  if ! command_exists ya; then
    log "WARN: yazi installed but ya command not found"
  fi
  log "install_yazi done"
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
  echo "0 3 * * * root systemctl restart sing-box.service" >"$cron_file"
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
  run_bash "curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh | bash" >"$log_output" 2>&1
  local script_rc=$?

  cat "$log_output" >>"$LOG_FILE"

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
      --ok-label "OK" \
      --msgbox "1Panel has been successfully installed.\n\nPanel URL: ${panel_url}\nUsername: ${panel_user}\nPassword: ${panel_pass}\n\nPlease save these credentials securely!" 12 70
  fi
}

dd_debian12() {
  local pwd="${1:-}"
  local username="${2:-root}"
  if [[ -z "$pwd" ]]; then
    log "ERROR: dd_debian12 requires a password argument"
    printf 'ERROR: Password cannot be empty.\n' >&2
    return 1
  fi

  local script_url="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
  local cmd="bash <(curl -sL $script_url || wget -qO- $script_url) debian 12 --password $(shell_quote "$pwd") --username $(shell_quote "$username")"

  log "dd_debian12: preparing to install Debian 12"
  prepare_reinstall_certificates || return 1
  run_bash "$cmd" || return 1
}

dd_debian13() {
  local pwd="${1:-}"
  local username="${2:-root}"
  if [[ -z "$pwd" ]]; then
    log "ERROR: dd_debian13 requires a password argument"
    printf 'ERROR: Password cannot be empty.\n' >&2
    return 1
  fi

  local script_url="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
  local cmd="bash <(curl -sL $script_url || wget -qO- $script_url) debian 13 --password $(shell_quote "$pwd") --username $(shell_quote "$username")"

  log "dd_debian13: preparing to install Debian 13"
  prepare_reinstall_certificates || return 1
  run_bash "$cmd" || return 1
}

dd_alpine() {
  local pwd="${1:-}"
  local username="${2:-root}"
  if [[ -z "$pwd" ]]; then
    log "ERROR: dd_alpine requires a password argument"
    printf 'ERROR: Password cannot be empty.\n' >&2
    return 1
  fi

  local script_url="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
  local cmd="bash <(curl -sL $script_url || wget -qO- $script_url) alpine 3.24 --password $(shell_quote "$pwd") --username $(shell_quote "$username")"

  log "dd_alpine: preparing to install Alpine"
  prepare_reinstall_certificates || return 1
  run_bash "$cmd" || return 1
}

install_base() {
  install_speedtest || return 1
  install_btop || return 1
  install_neovim || return 1
  install_nexttrace || return 1
  config_swap "1G" || return 1
  install_zsh || return 1
  config_timezone_asia_shanghai || log "WARN: failed to configure timezone, continue base installation"
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
  --shanghai-timezone  Set timezone to Asia/Shanghai
  lang                 Configure LANG=zh_CN.UTF-8 and show current locale status

System reinstall:
  debian12=<pwd>       Reinstall Debian 12 with specified root password
  debian13=<pwd>       Reinstall Debian 13 with specified root password
  alpine=<pwd>         Reinstall Alpine with specified root password
  --username=<name>    Optional reinstall username; empty/default uses root only

Tool installation:
  speedtest            Install speedtest
  btop                 Install btop
  bat                  Install bat
  fastfetch            Install fastfetch
  lsd                  Install lsd
  lazygit              Install lazygit
  neovim               Install neovim + LazyVim
  nexttrace            Install nexttrace
  yazi                 Install Yazi
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
  -h | --help)
    show_help
    return 0
    ;;
  esac

  install_dependencies || log "WARN: dependency install failed, continue"

  local arg scan_arg size pwd username=""
  for scan_arg in "$@"; do
    case "$scan_arg" in
    --username=*) username="${scan_arg#--username=}" ;;
    esac
  done

  while [[ "$#" -gt 0 ]]; do
    arg="$1"
    case "$arg" in
    tui)
      tui_main_menu
      ;;
    run-selected)
      shift
      local -a run_args=()
      while [[ "$#" -gt 0 ]]; do
        case "${1:-}" in
        --username=*) ;;
        *) run_args+=("$1") ;;
        esac
        shift
      done
      REINSTALL_USERNAME="$username"
      run_selected_tasks_with_progress "${run_args[@]}"
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
    --shanghai-timezone)
      config_timezone_asia_shanghai
      ;;
    --username=*)
      ;;
    lang)
      cli_config_lang_zh_utf8
      ;;
    speedtest)
      install_speedtest
      ;;
    btop)
      install_btop
      ;;
    bat)
      install_bat
      ;;
    fastfetch)
      install_fastfetch
      ;;
    lsd)
      install_lsd
      ;;
    lazygit)
      install_lazygit
      ;;
    neovim)
      install_neovim
      ;;
    nexttrace)
      install_nexttrace
      ;;
    yazi)
      install_yazi
      ;;
    shell)
      config_shell
      ;;
    zsh)
      install_zsh
      ;;
    debian12=*)
      pwd="${arg#debian12=}"
      dd_debian12 "$pwd" "$username"
      ;;
    debian13=*)
      pwd="${arg#debian13=}"
      dd_debian13 "$pwd" "$username"
      ;;
    alpine=*)
      pwd="${arg#alpine=}"
      dd_alpine "$pwd" "$username"
      ;;
    -h | --help)
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

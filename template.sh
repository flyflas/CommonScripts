#!/usr/bin/env bash

# Template Script by XiaoBai
# Initial August 2023; Last update August 2023

# Purpose:    The purpose of this script is to quickly init linux setting.
#             Thereby avoiding cumbersome manual settings.

alias echo="echo -e"

set -Eeuxo pipefail
# set -Eeo pipefail

trap 'echo  "xxx do someting"' EXIT

END_COLOR="\033[0m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"

error() {
	echo -e "${RED}$*${END_COLOR}"
}

info() {
    echo -e "${GREEN}$*${END_COLOR}"
}

remind() {
    echo -e "${BLUE}$*${END_COLOR}"
}

warning() {
    echo -e "${YELLOW}$*${END_COLOR}"
}



#! /usr/bin/env bash

#--------------------------------------------------------
#                   .ssh 备份脚本
# 功能： 将 mac 中的 .ssh 文件夹中的内容定时备份到 onedrive 中
# @author xiaobai
# @date 2023年 3月15日 星期三 13时13分41秒 CST
# @version 2.0
#-------------------------------------------------------

set -Eeuo pipefail

echo -e "[$(date +"%F %T")] 正在备份.ssh"

ORIGIN_DIR="$HOME/.ssh"
TARGET_DIR="$HOME/OneDrive/附件/ssh_backup/.ssh"
declare -A ORIGIN_FILE_DICT
declare -A TARGET_FILE_DICT

OLD_IFS="$IFS"
IFS=$'\n'
mapfile -t ORIGIN_FILE_SET < <(ls "${ORIGIN_DIR}")
mapfile -t TARGET_FILE_SET < <(ls "${TARGET_DIR}")

IFS="$OLD_IFS"

[[ ! (-d "${ORIGIN_DIR}") ]] && echo -e ".ssh 文件夹不存在！！！" && exit 1

for i in "${ORIGIN_FILE_SET[@]}"; do
    ORIGIN_FILE_DICT["$i"]="$(sha1sum "${ORIGIN_DIR}/$i" | awk '{print $1}')"
done

for i in "${TARGET_FILE_SET[@]}"; do
    TARGET_FILE_DICT["$i"]="$(sha1sum "${TARGET_DIR}/$i" | awk '{print $1}')"

    if [[ ! "${ORIGIN_FILE_DICT["$i"]}" ]]; then
        # 如果 .ssh 目录中没有该文件，则将改文件拷贝到 .ssh 目录中
        cp "${TARGET_DIR}/${i}" "${ORIGIN_DIR}/"
        echo -e "[$(date +"%F %T")]" "${TARGET_DIR}/${i}" " --> " "${ORIGIN_DIR}/${i}"
    fi

    if [[ "${TARGET_FILE_DICT["$i"]}" != "${ORIGIN_FILE_DICT["$i"]}" ]]; then
        ORIGIN_FILE_TIME="stat -r "${ORIGIN_DIR}/$i" | awk '{print $10}'"
        TARGET_FILE_TIME="stat -r "${TARGET_DIR}/$i" | awk '{print $10}}'"

        if [[ ${ORIGIN_FILE_TIME} -gt ${TARGET_FILE_TIME} ]]; then
            # .ssh 文件夹中的文件是最新修改的。
            # 将 .ssh 文件夹中的文件拷贝到 OneDrive 中
            cp "${ORIGIN_DIR}/${i}" "${TARGET_DIR}/"
            echo -e "[$(date +"%F %T")]" "${ORIGIN_DIR}/${i}" " --> " "${TARGET_DIR}/${i}"

        else
            # OneDrive 中的文件是最新修改的。
            # 将 OneDrive 文件夹中的文件拷贝到 .ssh 中
            cp "${TARGET_DIR}/${i}" "${ORIGIN_DIR}/"
            echo -e "[$(date +"%F %T")]" "${TARGET_DIR}/${i}" " --> " "${ORIGIN_DIR}/${i}"

        fi
    fi
done

for i in "${ORIGIN_FILE_SET[@]}"; do
    if [[ ! "${TARGET_FILE_DICT["$i"]}" ]]; then
        cp "${ORIGIN_DIR}/${i}" "${TARGET_DIR}/"
        echo -e "[$(date +"%F %T")]" "${ORIGIN_DIR}/${i}" " --> " "${TARGET_DIR}/${i}"
    fi
done

echo -e "[$(date +"%F %T")] 备份已经完成。"

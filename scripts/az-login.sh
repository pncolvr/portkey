#!/usr/bin/env bash
utils=$(echo "${BASH_SOURCE[0]:-0}" | xargs realpath | xargs dirname)/_common.sh
source "$utils"

login
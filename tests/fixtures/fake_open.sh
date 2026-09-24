#!/bin/zsh

set -u

[[ -n "${YU_OPEN_CALLED_FILE:-}" ]] && print -r -- "$1" > "$YU_OPEN_CALLED_FILE"
exit 0


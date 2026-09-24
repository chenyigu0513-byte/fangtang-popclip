#!/bin/zsh

set -u

output_file=""
request_file=""
body="${YU_CURL_BODY:-}"
[[ -n "$body" ]] || body='{}'

while IFS= read -r _config_line; do
  :
done

for (( index = 1; index <= $#; index++ )); do
  argument="${@[index]}"
  if [[ "$argument" == "--output" ]]; then
    next_index=$(( index + 1 ))
    output_file="${@[next_index]}"
  elif [[ "$argument" == --data-binary ]]; then
    next_index=$(( index + 1 ))
    data_argument="${@[next_index]}"
    request_file="${data_argument#@}"
  fi
done

[[ -n "${YU_CURL_CALLED_FILE:-}" ]] && print -r -- "called" > "$YU_CURL_CALLED_FILE"
if [[ -n "${YU_REQUEST_CAPTURE_FILE:-}" && -n "$request_file" ]]; then
  /bin/cp "$request_file" "$YU_REQUEST_CAPTURE_FILE"
fi

case "${YU_CURL_SCENARIO:-success}" in
  success)
    print -rn -- "$body" > "$output_file"
    print -rn -- "200"
    exit 0
    ;;
  auth)
    print -rn -- "$body" > "$output_file"
    print -rn -- "401"
    exit 0
    ;;
  server)
    print -rn -- "$body" > "$output_file"
    print -rn -- "503"
    exit 0
    ;;
  timeout)
    print -u2 -r -- "simulated timeout"
    print -rn -- "000"
    exit 28
    ;;
  *)
    print -u2 -r -- "unknown fake curl scenario"
    exit 2
    ;;
esac

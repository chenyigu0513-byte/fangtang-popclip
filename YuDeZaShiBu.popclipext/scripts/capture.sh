#!/bin/zsh

set -u

readonly PLUTIL_BIN="${YU_PLUTIL_BIN:-/usr/bin/plutil}"
readonly CURL_BIN="${YU_CURL_BIN:-/usr/bin/curl}"
readonly OPEN_BIN="${YU_OPEN_BIN:-/usr/bin/open}"
readonly PERL_BIN="${YU_PERL_BIN:-/usr/bin/perl}"
readonly MKTEMP_BIN="${YU_MKTEMP_BIN:-/usr/bin/mktemp}"
readonly DATE_BIN="${YU_DATE_BIN:-/bin/date}"
readonly SLEEP_BIN="${YU_SLEEP_BIN:-/bin/sleep}"
readonly STATE_DIR="${YU_STATE_DIR:-${HOME}/Library/Application Support/YuDeZaShiBu}"
readonly USAGE_FILE="${STATE_DIR}/usage.json"
readonly CAPTURE_FILE="${STATE_DIR}/capture.json"
readonly API_URL="https://api.deepseek.com/chat/completions"
readonly ALLOWED_TAGS="SOP 技巧 案例 观点 灵感 待整理"
readonly HEADING_SETTLE_DELAY="${YU_HEADING_SETTLE_DELAY:-0.35}"

CAPTURE_TAG="${CAPTURE_TAG:-}"
SELECTED_TEXT="${POPCLIP_TEXT:-}"
API_KEY="${POPCLIP_OPTION_APIKEY:-}"
VAULT_NAME="${POPCLIP_OPTION_VAULTNAME:-}"
FILE_NAME="${POPCLIP_OPTION_FILENAME:-}"
INCLUDE_SOURCE="${POPCLIP_OPTION_INCLUDESOURCE:-1}"
MONTHLY_LIMIT="${POPCLIP_OPTION_MONTHLYTOKENLIMIT:-100000}"
WARNING_PERCENTAGE="${POPCLIP_OPTION_WARNINGPERCENTAGE:-80}"
BROWSER_URL="${POPCLIP_BROWSER_URL:-}"
BROWSER_TITLE="${POPCLIP_BROWSER_TITLE:-}"
APP_NAME="${POPCLIP_APP_NAME:-}"

REQUEST_FILE=""
RESPONSE_FILE=""
CURL_ERROR_FILE=""
CAPTURE_DATE=""
CAPTURE_HEADING=""
CAPTURE_TARGET_HEADING=""
CAPTURE_DATETIME_FALLBACK=0

cleanup() {
  [[ -n "$REQUEST_FILE" && -f "$REQUEST_FILE" ]] && /bin/rm -f "$REQUEST_FILE"
  [[ -n "$RESPONSE_FILE" && -f "$RESPONSE_FILE" ]] && /bin/rm -f "$RESPONSE_FILE"
  [[ -n "$CURL_ERROR_FILE" && -f "$CURL_ERROR_FILE" ]] && /bin/rm -f "$CURL_ERROR_FILE"
}
trap cleanup EXIT INT TERM

is_positive_integer() {
  [[ "$1" =~ '^[0-9]+$' ]] && (( $1 > 0 ))
}

normalize_settings() {
  is_positive_integer "$MONTHLY_LIMIT" || MONTHLY_LIMIT=100000
  if ! is_positive_integer "$WARNING_PERCENTAGE" || (( WARNING_PERCENTAGE >= 100 )); then
    WARNING_PERCENTAGE=80
  fi
}

is_allowed_tag() {
  local candidate="$1"
  local allowed
  for allowed in ${(z)ALLOWED_TAGS}; do
    [[ "$candidate" == "$allowed" ]] && return 0
  done
  return 1
}

url_encode() {
  YU_URL_VALUE="$1" "$PERL_BIN" -MURI::Escape -e 'print uri_escape($ENV{"YU_URL_VALUE"})'
}

markdown_escape_title() {
  printf '%s' "$1" | "$PERL_BIN" -0pe 's/([\\\[\]])/\\$1/g; s/[\r\n]+/ /g'
}

read_capture_date() {
  "$PLUTIL_BIN" -extract lastCaptureDate raw "$CAPTURE_FILE" 2>/dev/null
}

write_capture_date() {
  local capture_date="$1" temp_file
  temp_file="$($MKTEMP_BIN "${STATE_DIR}/.capture.XXXXXX")" || return 1
  "$PLUTIL_BIN" -create xml1 "$temp_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert lastCaptureDate -string "$capture_date" "$temp_file" >/dev/null || return 1
  "$PLUTIL_BIN" -convert json "$temp_file" >/dev/null || return 1
  /bin/chmod 600 "$temp_file"
  /bin/mv -f "$temp_file" "$CAPTURE_FILE"
}

weekday_name() {
  case "$1" in
    0) print -r -- "星期日" ;;
    1) print -r -- "星期一" ;;
    2) print -r -- "星期二" ;;
    3) print -r -- "星期三" ;;
    4) print -r -- "星期四" ;;
    5) print -r -- "星期五" ;;
    6) print -r -- "星期六" ;;
    *) return 1 ;;
  esac
}

prepare_capture_date() {
  local previous_date weekday_number year month day weekday
  CAPTURE_DATE=""
  CAPTURE_HEADING=""
  CAPTURE_TARGET_HEADING=""
  CAPTURE_DATETIME_FALLBACK=0

  year="$($DATE_BIN '+%Y')" || { CAPTURE_DATETIME_FALLBACK=1; return; }
  month="$($DATE_BIN '+%m')" || { CAPTURE_DATETIME_FALLBACK=1; return; }
  day="$($DATE_BIN '+%d')" || { CAPTURE_DATETIME_FALLBACK=1; return; }
  weekday_number="$($DATE_BIN '+%w')" || { CAPTURE_DATETIME_FALLBACK=1; return; }
  weekday="$(weekday_name "$weekday_number")" || { CAPTURE_DATETIME_FALLBACK=1; return; }
  CAPTURE_DATE="${year}-${month}-${day}"

  /bin/mkdir -p "$STATE_DIR" >/dev/null 2>&1 || { CAPTURE_DATETIME_FALLBACK=1; return; }
  /bin/chmod 700 "$STATE_DIR" 2>/dev/null || true

  if [[ -e "$CAPTURE_FILE" ]]; then
    previous_date="$(read_capture_date)" || { CAPTURE_DATETIME_FALLBACK=1; return; }
  else
    previous_date=""
  fi

  if [[ "$previous_date" != "$CAPTURE_DATE" ]]; then
    CAPTURE_HEADING="## ${year}年${month#0}月${day#0}日 · ${weekday}"
  else
    CAPTURE_TARGET_HEADING="${year}年${month#0}月${day#0}日 · ${weekday}"
  fi
}

format_markdown() {
  local tag="$1"
  local timestamp quoted source title entry_prefix
  timestamp="$($DATE_BIN '+%H:%M')"
  quoted="$(printf '%s' "$SELECTED_TEXT" | /usr/bin/sed 's/^/  > /')"
  source=""

  if (( CAPTURE_DATETIME_FALLBACK == 1 )); then
    entry_prefix="- $($DATE_BIN '+%Y-%m-%d %H:%M')"
  else
    entry_prefix="- ${timestamp}"
  fi

  if [[ "$INCLUDE_SOURCE" == "1" || "$INCLUDE_SOURCE" == "true" ]]; then
    if [[ -n "$BROWSER_URL" ]]; then
      title="${BROWSER_TITLE:-来源}"
      title="$(markdown_escape_title "$title")"
      source=$'\n'"  [来源：${title}](<${BROWSER_URL}>)"
    elif [[ -n "$APP_NAME" ]]; then
      title="$(markdown_escape_title "$APP_NAME")"
      source=$'\n'"  来源：${title}"
    fi
  fi

  if [[ -n "$CAPTURE_HEADING" ]]; then
    printf '%s\n\n%s #%s\n%s%s' "$CAPTURE_HEADING" "$entry_prefix" "$tag" "$quoted" "$source"
  else
    printf '%s #%s\n%s%s' "$entry_prefix" "$tag" "$quoted" "$source"
  fi
}

append_to_obsidian() {
  local tag="$1"
  local markdown vault_encoded file_encoded data_encoded uri heading_encoded write_mode
  prepare_capture_date
  markdown="$(format_markdown "$tag")"
  vault_encoded="$(url_encode "$VAULT_NAME")" || return 1
  file_encoded="$(url_encode "$FILE_NAME")" || return 1
  data_encoded="$(url_encode $'\n'"$markdown"$'\n\n')" || return 1
  # Advanced URI resolves headings from Obsidian's metadata cache. After a
  # first write, that cache can lag behind the file by a short moment; give it
  # time to settle before asking for a same-day heading insertion.
  if [[ -n "$CAPTURE_TARGET_HEADING" && "$HEADING_SETTLE_DELAY" != "0" ]]; then
    "$SLEEP_BIN" "$HEADING_SETTLE_DELAY"
  fi

  # filepath is the unambiguous Advanced URI file identifier. filename relies
  # on linkpath resolution and can point at a different file when aliases or
  # duplicate names exist in a vault.
  # Dates are newest-first at the top of the note. Within one date group,
  # records are chronological: the first capture stays at the top and later
  # captures are appended below it.
  write_mode="prepend"
  [[ -n "$CAPTURE_TARGET_HEADING" ]] && write_mode="append"
  uri="obsidian://advanced-uri?vault=${vault_encoded}&filepath=${file_encoded}&data=${data_encoded}&mode=${write_mode}"
  if [[ -n "$CAPTURE_TARGET_HEADING" ]]; then
    heading_encoded="$(url_encode "$CAPTURE_TARGET_HEADING")" || return 1
    uri="${uri}&heading=${heading_encoded}"
  fi

  if [[ -n "${YU_CAPTURE_OUTPUT_FILE:-}" ]]; then
    printf '%s\n' "$markdown" > "$YU_CAPTURE_OUTPUT_FILE"
    printf '%s\n' "$uri" > "${YU_CAPTURE_OUTPUT_FILE}.uri"
  fi

  "$OPEN_BIN" "$uri" >/dev/null 2>&1 || return 1

  if [[ -n "$CAPTURE_HEADING" ]]; then
    write_capture_date "$CAPTURE_DATE" >/dev/null 2>&1 || true
  fi
}

write_state() {
  local period="$1" settled="$2" pending="$3" limit="$4" threshold="$5"
  local temp_file
  temp_file="$($MKTEMP_BIN "${STATE_DIR}/.usage.XXXXXX")" || return 1
  "$PLUTIL_BIN" -create xml1 "$temp_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert period -string "$period" "$temp_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert settledTokens -integer "$settled" "$temp_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert pendingTokens -integer "$pending" "$temp_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert warningThreshold -integer "$threshold" "$temp_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert limit -integer "$limit" "$temp_file" >/dev/null || return 1
  "$PLUTIL_BIN" -convert json "$temp_file" >/dev/null || return 1
  /bin/chmod 600 "$temp_file"
  /bin/mv -f "$temp_file" "$USAGE_FILE"
}

read_state_value() {
  "$PLUTIL_BIN" -extract "$1" raw "$USAGE_FILE" 2>/dev/null
}

load_or_create_state() {
  local current_period="$1" limit="$2" threshold="$3"
  local period settled pending

  /bin/mkdir -p "$STATE_DIR" || return 1
  /bin/chmod 700 "$STATE_DIR" 2>/dev/null || true

  if [[ ! -e "$USAGE_FILE" ]]; then
    write_state "$current_period" 0 0 "$limit" "$threshold" || return 1
  fi

  period="$(read_state_value period)" || return 2
  settled="$(read_state_value settledTokens)" || return 2
  pending="$(read_state_value pendingTokens)" || return 2
  is_positive_integer "$settled" || [[ "$settled" == "0" ]] || return 2
  is_positive_integer "$pending" || [[ "$pending" == "0" ]] || return 2

  if [[ "$period" != "$current_period" ]]; then
    write_state "$current_period" 0 0 "$limit" "$threshold" || return 1
  else
    write_state "$period" "$settled" "$pending" "$limit" "$threshold" || return 1
  fi
  return 0
}

build_request() {
  local request_file="$1"
  local system_prompt
  system_prompt='你是摘录分类器。只返回一个标签，不要解释：SOP、技巧、案例、观点、灵感、待整理。SOP=流程或步骤；技巧=可直接复用的方法；案例=具体做法或产品/商业实例；观点=判断或洞察；灵感=启发性想法；无法确定=待整理。'

  "$PLUTIL_BIN" -create xml1 "$request_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert model -string deepseek-flash "$request_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert max_tokens -integer 16 "$request_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert temperature -float 0 "$request_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert stream -bool false "$request_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert reasoning_effort -string none "$request_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert thinking -dictionary "$request_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert thinking.type -string disabled "$request_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert messages -array "$request_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert messages.0 -dictionary "$request_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert messages.0.role -string system "$request_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert messages.0.content -string "$system_prompt" "$request_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert messages.1 -dictionary "$request_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert messages.1.role -string user "$request_file" >/dev/null || return 1
  "$PLUTIL_BIN" -insert messages.1.content -string "$SELECTED_TEXT" "$request_file" >/dev/null || return 1
  "$PLUTIL_BIN" -convert json "$request_file" >/dev/null || return 1
}

release_reservation() {
  local period="$1" settled="$2" pending="$3" reservation="$4" limit="$5" threshold="$6"
  local next_pending=$(( pending - reservation ))
  (( next_pending < 0 )) && next_pending=0
  write_state "$period" "$settled" "$next_pending" "$limit" "$threshold"
}

settle_reservation() {
  local period="$1" settled="$2" pending="$3" reservation="$4" actual="$5" limit="$6" threshold="$7"
  local next_pending=$(( pending - reservation ))
  (( next_pending < 0 )) && next_pending=0
  write_state "$period" $(( settled + actual )) "$next_pending" "$limit" "$threshold"
}

classify_with_ai() {
  local current_period threshold load_status settled pending used char_count reservation
  local http_code curl_status raw_tag tag actual_tokens message

  if [[ -z "$API_KEY" ]]; then
    AI_TAG="待整理"
    AI_MESSAGE="未配置 DeepSeek API Key，已保存 #待整理"
    return
  fi

  char_count="$(printf '%s' "$SELECTED_TEXT" | LC_ALL=en_US.UTF-8 /usr/bin/wc -m | /usr/bin/tr -d ' ')"
  if ! is_positive_integer "$char_count" && [[ "$char_count" != "0" ]]; then
    char_count="$(printf '%s' "$SELECTED_TEXT" | /usr/bin/wc -c | /usr/bin/tr -d ' ')"
  fi
  if (( char_count > 4000 )); then
    AI_TAG="待整理"
    AI_MESSAGE="选中内容超过 4,000 字符，已保存 #待整理"
    return
  fi

  current_period="$($DATE_BIN '+%Y-%m')"
  threshold=$(( MONTHLY_LIMIT * WARNING_PERCENTAGE / 100 ))
  load_or_create_state "$current_period" "$MONTHLY_LIMIT" "$threshold"
  load_status=$?
  if (( load_status == 2 )); then
    AI_TAG="待整理"
    AI_MESSAGE="token 用量记录损坏，已保存 #待整理"
    return
  elif (( load_status != 0 )); then
    AI_TAG="待整理"
    AI_MESSAGE="无法写入 token 用量记录，已保存 #待整理"
    return
  fi

  settled="$(read_state_value settledTokens)"
  pending="$(read_state_value pendingTokens)"
  used=$(( settled + pending ))
  reservation=$(( char_count * 4 + 528 ))

  if (( used >= MONTHLY_LIMIT || used + reservation > MONTHLY_LIMIT )); then
    AI_TAG="待整理"
    AI_MESSAGE="本月 AI 额度已用完，已保存 #待整理"
    return
  fi

  pending=$(( pending + reservation ))
  if ! write_state "$current_period" "$settled" "$pending" "$MONTHLY_LIMIT" "$threshold"; then
    AI_TAG="待整理"
    AI_MESSAGE="无法预留 token 额度，已保存 #待整理"
    return
  fi

  REQUEST_FILE="$($MKTEMP_BIN "${STATE_DIR}/.request.XXXXXX")" || {
    AI_TAG="待整理"; AI_MESSAGE="无法创建请求，已保存 #待整理"; return;
  }
  RESPONSE_FILE="$($MKTEMP_BIN "${STATE_DIR}/.response.XXXXXX")" || {
    AI_TAG="待整理"; AI_MESSAGE="无法创建响应文件，已保存 #待整理"; return;
  }
  CURL_ERROR_FILE="$($MKTEMP_BIN "${STATE_DIR}/.curl-error.XXXXXX")" || {
    AI_TAG="待整理"; AI_MESSAGE="无法创建错误文件，已保存 #待整理"; return;
  }
  /bin/chmod 600 "$REQUEST_FILE" "$RESPONSE_FILE" "$CURL_ERROR_FILE"

  if ! build_request "$REQUEST_FILE"; then
    AI_TAG="待整理"
    AI_MESSAGE="无法组装 DeepSeek 请求，已保存 #待整理"
    return
  fi

  http_code="$({
    printf 'header = "Authorization: Bearer %s"\n' "$API_KEY"
  } | "$CURL_BIN" --config - --silent --show-error --connect-timeout 5 --max-time 15 \
      --header 'Content-Type: application/json' --data-binary "@${REQUEST_FILE}" \
      --output "$RESPONSE_FILE" --write-out '%{http_code}' "$API_URL" 2>"$CURL_ERROR_FILE")"
  curl_status=$?

  if (( curl_status != 0 )); then
    AI_TAG="待整理"
    AI_MESSAGE="DeepSeek 连接失败，已保存 #待整理"
    return
  fi

  if [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
    release_reservation "$current_period" "$settled" "$pending" "$reservation" "$MONTHLY_LIMIT" "$threshold" >/dev/null 2>&1 || true
    AI_TAG="待整理"
    AI_MESSAGE="DeepSeek API Key 无效或权限不足，已保存 #待整理"
    return
  fi

  if [[ ! "$http_code" =~ '^2[0-9][0-9]$' ]]; then
    AI_TAG="待整理"
    AI_MESSAGE="DeepSeek 服务暂时不可用（HTTP ${http_code}），已保存 #待整理"
    return
  fi

  raw_tag="$($PLUTIL_BIN -extract choices.0.message.content raw "$RESPONSE_FILE" 2>/dev/null)" || {
    AI_TAG="待整理"; AI_MESSAGE="DeepSeek 响应缺少标签，已保存 #待整理"; return;
  }
  actual_tokens="$($PLUTIL_BIN -extract usage.total_tokens raw "$RESPONSE_FILE" 2>/dev/null)" || {
    AI_TAG="待整理"; AI_MESSAGE="DeepSeek 响应缺少 token 用量，已保存 #待整理"; return;
  }
  if ! is_positive_integer "$actual_tokens"; then
    AI_TAG="待整理"
    AI_MESSAGE="DeepSeek token 用量无效，已保存 #待整理"
    return
  fi

  tag="$(printf '%s' "$raw_tag" | "$PERL_BIN" -0pe 's/^\s+|\s+$//g; s/^["'"'"']|["'"'"']$//g')"
  if ! settle_reservation "$current_period" "$settled" "$pending" "$reservation" "$actual_tokens" "$MONTHLY_LIMIT" "$threshold"; then
    AI_TAG="待整理"
    AI_MESSAGE="无法结算 token 用量，已保存 #待整理"
    return
  fi

  settled=$(( settled + actual_tokens ))
  pending=$(( pending - reservation ))
  (( pending < 0 )) && pending=0
  used=$(( settled + pending ))

  if is_allowed_tag "$tag"; then
    AI_TAG="$tag"
    if (( used >= threshold )); then
      AI_MESSAGE="AI → #${tag}｜本月 ${used} / ${MONTHLY_LIMIT} tokens，剩余 $(( MONTHLY_LIMIT - used ))"
    else
      AI_MESSAGE="AI → #${tag}｜本月 ${used} / ${MONTHLY_LIMIT} tokens"
    fi
  else
    AI_TAG="待整理"
    AI_MESSAGE="AI 分类结果无效，已保存 #待整理｜本月 ${used} / ${MONTHLY_LIMIT} tokens"
  fi
}

normalize_settings

if [[ -z "$SELECTED_TEXT" ]]; then
  print -r -- "没有可保存的文字"
  exit 1
fi

if [[ -z "$VAULT_NAME" || -z "$FILE_NAME" ]]; then
  print -r -- "请先在方糖设置中填写 Obsidian 知识库名和目标笔记名"
  exit 1
fi

if [[ "$CAPTURE_TAG" == "AI" ]]; then
  AI_TAG="待整理"
  AI_MESSAGE=""
  classify_with_ai
  if append_to_obsidian "$AI_TAG"; then
    print -r -- "$AI_MESSAGE"
    exit 0
  fi
  print -r -- "无法打开 Obsidian，请检查知识库和笔记名"
  exit 1
fi

if ! is_allowed_tag "$CAPTURE_TAG"; then
  print -r -- "未知标签：${CAPTURE_TAG}"
  exit 1
fi

if append_to_obsidian "$CAPTURE_TAG"; then
  print -r -- "已保存 #${CAPTURE_TAG}"
  exit 0
fi

print -r -- "无法打开 Obsidian，请检查知识库和笔记名"
exit 1

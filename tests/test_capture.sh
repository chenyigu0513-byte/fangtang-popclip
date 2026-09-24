#!/bin/zsh

set -u

readonly PROJECT_DIR="${0:A:h:h}"
readonly CAPTURE_SCRIPT="${PROJECT_DIR}/YuDeZaShiBu.popclipext/scripts/capture.sh"
readonly PLUTIL_BIN="/usr/bin/plutil"

TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/yu-capture-tests.XXXXXX")" || exit 1
trap '/bin/rm -rf "$TEST_ROOT"' EXIT INT TERM

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  print -r -- "PASS: $1"
  PASS_COUNT=$(( PASS_COUNT + 1 ))
}

fail() {
  print -u2 -r -- "FAIL: $1"
  FAIL_COUNT=$(( FAIL_COUNT + 1 ))
}

assert_contains() {
  local file="$1" expected="$2" label="$3"
  if /usr/bin/grep -Fq -- "$expected" "$file"; then
    pass "$label"
  else
    fail "$label（缺少：$expected）"
  fi
}

assert_not_contains() {
  local file="$1" unexpected="$2" label="$3"
  if ! /usr/bin/grep -Fq -- "$unexpected" "$file"; then
    pass "$label"
  else
    fail "$label（意外出现：$unexpected）"
  fi
}

assert_equals() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label（实际：$actual；期望：$expected）"
  fi
}

make_fake_tools() {
  local bin_dir="$1"
  /bin/mkdir -p "$bin_dir"

  /bin/cp "${PROJECT_DIR}/tests/fixtures/fake_curl.sh" "$bin_dir/curl"
  /bin/cp "${PROJECT_DIR}/tests/fixtures/fake_date.sh" "$bin_dir/date"
  /bin/cp "${PROJECT_DIR}/tests/fixtures/fake_open.sh" "$bin_dir/open"
  /bin/cp "${PROJECT_DIR}/tests/fixtures/fake_sleep.sh" "$bin_dir/sleep"
  /bin/chmod 700 "$bin_dir/curl" "$bin_dir/date" "$bin_dir/open" "$bin_dir/sleep"
}

run_capture() {
  local case_dir="$1" tag="$2" text="$3" result_file="$4"
  shift 4

  /usr/bin/env \
    CAPTURE_TAG="$tag" \
    POPCLIP_TEXT="$text" \
    POPCLIP_OPTION_APIKEY="test-key-never-sent" \
    POPCLIP_OPTION_VAULTNAME="鲸鱼" \
    POPCLIP_OPTION_FILENAME="鱼的杂事簿" \
    POPCLIP_OPTION_INCLUDESOURCE="1" \
    POPCLIP_OPTION_MONTHLYTOKENLIMIT="100000" \
    POPCLIP_OPTION_WARNINGPERCENTAGE="80" \
    YU_STATE_DIR="$case_dir/state" \
    YU_CAPTURE_OUTPUT_FILE="$case_dir/captured.md" \
    YU_CURL_BIN="$case_dir/bin/curl" \
    YU_OPEN_BIN="$case_dir/bin/open" \
    YU_DATE_BIN="$case_dir/bin/date" \
    YU_SLEEP_BIN="$case_dir/bin/sleep" \
    YU_HEADING_SETTLE_DELAY="0" \
    YU_TEST_DATE="2026-09-20" \
    YU_TEST_TIME="10:51" \
    YU_CURL_CALLED_FILE="$case_dir/curl-called" \
    YU_REQUEST_CAPTURE_FILE="$case_dir/request.json" \
    YU_OPEN_CALLED_FILE="$case_dir/open-uri" \
    "$@" \
    /bin/zsh "$CAPTURE_SCRIPT" >"$result_file" 2>&1
}

create_state() {
  local state_dir="$1" period="$2" settled="$3" pending="$4"
  local file="$state_dir/usage.json"
  /bin/mkdir -p "$state_dir"
  "$PLUTIL_BIN" -create xml1 "$file" >/dev/null
  "$PLUTIL_BIN" -insert period -string "$period" "$file" >/dev/null
  "$PLUTIL_BIN" -insert settledTokens -integer "$settled" "$file" >/dev/null
  "$PLUTIL_BIN" -insert pendingTokens -integer "$pending" "$file" >/dev/null
  "$PLUTIL_BIN" -insert warningThreshold -integer 80000 "$file" >/dev/null
  "$PLUTIL_BIN" -insert limit -integer 100000 "$file" >/dev/null
  "$PLUTIL_BIN" -convert json "$file" >/dev/null
}

state_value() {
  local state_file="$1" key="$2"
  "$PLUTIL_BIN" -extract "$key" raw "$state_file"
}

new_case() {
  local name="$1"
  local case_dir="$TEST_ROOT/$name"
  /bin/mkdir -p "$case_dir"
  make_fake_tools "$case_dir/bin"
  print -r -- "$case_dir"
}

test_manual_browser_capture() {
  local case_dir result
  case_dir="$(new_case manual-browser)"
  result="$case_dir/result.txt"

  run_capture "$case_dir" "技巧" $'第一行\n第二行' "$result" \
    POPCLIP_BROWSER_URL="https://example.com/a?b=1&c=2" \
    POPCLIP_BROWSER_TITLE="示例 [页面]"

  assert_contains "$case_dir/captured.md" "#技巧" "手动动作写入正确标签"
  assert_contains "$case_dir/captured.md" "  > 第一行" "多行摘录第一行使用引用格式"
  assert_contains "$case_dir/captured.md" "  > 第二行" "多行摘录第二行使用引用格式"
  assert_contains "$case_dir/captured.md" '[来源：示例 \[页面\]](<https://example.com/a?b=1&c=2>)' "网页来源被保留并转义标题"
  [[ ! -e "$case_dir/curl-called" ]] && pass "手动动作不调用 DeepSeek" || fail "手动动作不应调用 DeepSeek"
  [[ ! -e "$case_dir/state/usage.json" ]] && pass "手动动作不创建 AI 用量文件" || fail "手动动作不应创建 AI 用量文件"
  assert_contains "$result" "已保存 #技巧" "手动动作返回成功提示"
}

test_manual_app_capture() {
  local case_dir result
  case_dir="$(new_case manual-app)"
  result="$case_dir/result.txt"

  run_capture "$case_dir" "SOP" "执行这三步" "$result" POPCLIP_APP_NAME="飞书"

  assert_contains "$case_dir/captured.md" "来源：飞书" "非网页内容记录来源应用"
  assert_contains "$case_dir/captured.md" "#SOP" "SOP 标签可用"
}

test_daily_heading_groups_captures() {
  local case_dir first_result second_result next_day_result
  case_dir="$(new_case daily-heading)"
  first_result="$case_dir/first-result.txt"
  second_result="$case_dir/second-result.txt"
  next_day_result="$case_dir/next-day-result.txt"

  run_capture "$case_dir" "案例" "当天第一条" "$first_result"
  assert_contains "$case_dir/captured.md" "## 2026年9月20日 · 星期日" "当天首条写入日期标题"
  assert_contains "$case_dir/captured.md" "- 10:51 #案例" "当天首条保留时间"
  assert_contains "$case_dir/captured.md.uri" "mode=prepend" "新日期插入笔记顶部"
  assert_not_contains "$case_dir/captured.md.uri" "&heading=" "新日期整体插入而非定位旧标题"
  assert_equals "$(state_value "$case_dir/state/capture.json" lastCaptureDate)" "2026-09-20" "首条记录保存当天日期标记"

  run_capture "$case_dir" "技巧" "当天第二条" "$second_result" YU_TEST_TIME="14:30"
  assert_not_contains "$case_dir/captured.md" "## 2026年9月20日" "同一天后续内容不重复日期标题"
  assert_contains "$case_dir/captured.md" "- 14:30 #技巧" "同一天后续内容只显示时间"
  assert_contains "$case_dir/captured.md.uri" "mode=append" "同一天新记录追加到当日分组末尾"
  local decoded_uri
  decoded_uri="$(/usr/bin/perl -MURI::Escape -0777 -ne 'print uri_unescape($_)' "$case_dir/captured.md.uri")"
  assert_equals "${decoded_uri##*&heading=}" "2026年9月20日 · 星期日" "同日新记录定位到日期标题内部"

  run_capture "$case_dir" "灵感" "明天第一条" "$next_day_result" YU_TEST_DATE="2026-09-21" YU_TEST_TIME="09:05"
  assert_contains "$case_dir/captured.md" "## 2026年9月21日 · 星期一" "跨天首条新增日期标题"
  assert_contains "$case_dir/captured.md" "- 09:05 #灵感" "跨天首条保留当天时间"
  assert_not_contains "$case_dir/captured.md.uri" "&heading=" "跨天新日期不插进昨日分组"
}

test_corrupt_capture_date_falls_back_to_full_datetime() {
  local case_dir result
  case_dir="$(new_case corrupt-capture-date)"
  result="$case_dir/result.txt"
  /bin/mkdir -p "$case_dir/state"
  print -r -- "not-json" > "$case_dir/state/capture.json"

  run_capture "$case_dir" "待整理" "内容" "$result"

  assert_contains "$case_dir/captured.md" "- 2026-09-20 10:51 #待整理" "日期记录损坏时回退完整日期时间"
  assert_not_contains "$case_dir/captured.md" "## 2026年" "日期记录损坏时不写入不可靠标题"
}

test_ai_success() {
  local case_dir result state_file settled pending request_text request_model request_thinking
  case_dir="$(new_case ai-success)"
  result="$case_dir/result.txt"

  run_capture "$case_dir" "AI" "这是一条判断与洞察" "$result" \
    POPCLIP_BROWSER_URL="https://private.example/secret" \
    POPCLIP_BROWSER_TITLE="私人页面" \
    YU_CURL_SCENARIO="success" \
    YU_CURL_BODY='{"choices":[{"message":{"content":"观点"}}],"usage":{"total_tokens":123}}'

  state_file="$case_dir/state/usage.json"
  settled="$(state_value "$state_file" settledTokens)"
  pending="$(state_value "$state_file" pendingTokens)"
  request_text="$(state_value "$case_dir/request.json" messages.1.content)"
  request_model="$(state_value "$case_dir/request.json" model)"
  request_thinking="$(state_value "$case_dir/request.json" thinking.type)"

  assert_contains "$case_dir/captured.md" "#观点" "AI 成功分类为白名单标签"
  assert_equals "$settled" "123" "AI 成功后记录真实 token 数"
  assert_equals "$pending" "0" "AI 成功后清除预留 token"
  assert_equals "$request_text" "这是一条判断与洞察" "只把选中文字作为用户内容发送"
  assert_equals "$request_model" "deepseek-flash" "使用指定 DeepSeek 模型"
  assert_equals "$request_thinking" "disabled" "关闭思考模式以控制消耗"
  assert_not_contains "$case_dir/request.json" "private.example" "请求不包含来源 URL"
  assert_not_contains "$case_dir/request.json" "私人页面" "请求不包含网页标题"
  assert_not_contains "$case_dir/request.json" "鱼的杂事簿" "请求不包含 Obsidian 笔记名"
  assert_contains "$result" "AI → #观点" "AI 成功提示包含分类"
}

test_ai_invalid_tag() {
  local case_dir result settled pending
  case_dir="$(new_case ai-invalid-tag)"
  result="$case_dir/result.txt"

  run_capture "$case_dir" "AI" "内容" "$result" \
    YU_CURL_SCENARIO="success" \
    YU_CURL_BODY='{"choices":[{"message":{"content":"新闻"}}],"usage":{"total_tokens":9}}'

  settled="$(state_value "$case_dir/state/usage.json" settledTokens)"
  pending="$(state_value "$case_dir/state/usage.json" pendingTokens)"
  assert_contains "$case_dir/captured.md" "#待整理" "非白名单 AI 标签安全回退"
  assert_equals "$settled" "9" "无效标签仍结算已消耗 token"
  assert_equals "$pending" "0" "无效标签响应后清除预留 token"
}

test_ai_auth_failure_releases_reservation() {
  local case_dir result settled pending
  case_dir="$(new_case ai-auth-failure)"
  result="$case_dir/result.txt"

  run_capture "$case_dir" "AI" "内容" "$result" \
    YU_CURL_SCENARIO="auth" \
    YU_CURL_BODY='{"error":{"message":"unauthorized"}}'

  settled="$(state_value "$case_dir/state/usage.json" settledTokens)"
  pending="$(state_value "$case_dir/state/usage.json" pendingTokens)"
  assert_contains "$case_dir/captured.md" "#待整理" "鉴权失败仍保存原文"
  assert_equals "$settled" "0" "鉴权失败不计入已结算 token"
  assert_equals "$pending" "0" "鉴权失败释放预留 token"
  assert_contains "$result" "API Key 无效" "鉴权失败给出明确提示"
}

test_ai_uncertain_failure_keeps_reservation() {
  local case_dir result settled pending
  case_dir="$(new_case ai-timeout)"
  result="$case_dir/result.txt"

  run_capture "$case_dir" "AI" "内容" "$result" YU_CURL_SCENARIO="timeout"

  settled="$(state_value "$case_dir/state/usage.json" settledTokens)"
  pending="$(state_value "$case_dir/state/usage.json" pendingTokens)"
  assert_contains "$case_dir/captured.md" "#待整理" "网络结果不确定时仍保存原文"
  assert_equals "$settled" "0" "网络结果不确定时不伪造真实用量"
  (( pending > 0 )) && pass "网络结果不确定时保留预留 token" || fail "网络结果不确定时应保留预留 token"
  assert_contains "$result" "连接失败" "网络失败返回明确提示"
}

test_ai_quota_blocks_request() {
  local case_dir result period
  case_dir="$(new_case ai-quota)"
  result="$case_dir/result.txt"
  period="$(/bin/date '+%Y-%m')"
  create_state "$case_dir/state" "$period" 99990 0

  run_capture "$case_dir" "AI" "内容" "$result"

  [[ ! -e "$case_dir/curl-called" ]] && pass "额度不足时不发起网络请求" || fail "额度不足时不应发起网络请求"
  assert_contains "$case_dir/captured.md" "#待整理" "额度不足仍保存原文"
  assert_contains "$result" "额度已用完" "额度不足显示提醒"
}

test_ai_too_long_blocks_request() {
  local case_dir result long_text
  case_dir="$(new_case ai-too-long)"
  result="$case_dir/result.txt"
  long_text="$(/usr/bin/perl -CS -e 'print "字" x 4001')"

  run_capture "$case_dir" "AI" "$long_text" "$result"

  [[ ! -e "$case_dir/curl-called" ]] && pass "超过 4,000 字符时不发起网络请求" || fail "超长内容不应发起网络请求"
  [[ ! -e "$case_dir/state/usage.json" ]] && pass "超长内容不创建用量记录" || fail "超长内容不应创建用量记录"
  assert_contains "$case_dir/captured.md" "#待整理" "超长内容仍保存原文"
  assert_contains "$result" "超过 4,000 字符" "超长内容显示明确提醒"
}

test_corrupt_state_blocks_request() {
  local case_dir result
  case_dir="$(new_case corrupt-state)"
  result="$case_dir/result.txt"
  /bin/mkdir -p "$case_dir/state"
  print -r -- "not-json" > "$case_dir/state/usage.json"

  run_capture "$case_dir" "AI" "内容" "$result"

  [[ ! -e "$case_dir/curl-called" ]] && pass "用量文件损坏时不发起网络请求" || fail "用量文件损坏时不应发起网络请求"
  assert_contains "$case_dir/captured.md" "#待整理" "用量文件损坏仍保存原文"
  assert_contains "$result" "用量记录损坏" "用量文件损坏显示明确提醒"
}

test_month_rollover_resets_usage() {
  local case_dir result period settled pending
  case_dir="$(new_case month-rollover)"
  result="$case_dir/result.txt"
  period="$(/bin/date '+%Y-%m')"
  create_state "$case_dir/state" "1999-12" 99999 100

  run_capture "$case_dir" "AI" "新的一个月" "$result" \
    YU_CURL_SCENARIO="success" \
    YU_CURL_BODY='{"choices":[{"message":{"content":"灵感"}}],"usage":{"total_tokens":12}}'

  assert_equals "$(state_value "$case_dir/state/usage.json" period)" "$period" "跨月后更新计费月份"
  settled="$(state_value "$case_dir/state/usage.json" settledTokens)"
  pending="$(state_value "$case_dir/state/usage.json" pendingTokens)"
  assert_equals "$settled" "12" "跨月后从零开始累计真实用量"
  assert_equals "$pending" "0" "跨月成功请求后无待结算用量"
}

test_manual_browser_capture
test_manual_app_capture
test_daily_heading_groups_captures
test_corrupt_capture_date_falls_back_to_full_datetime
test_ai_success
test_ai_invalid_tag
test_ai_auth_failure_releases_reservation
test_ai_uncertain_failure_keeps_reservation
test_ai_quota_blocks_request
test_ai_too_long_blocks_request
test_corrupt_state_blocks_request
test_month_rollover_resets_usage

print -r -- ""
print -r -- "结果：${PASS_COUNT} 通过，${FAIL_COUNT} 失败"
(( FAIL_COUNT == 0 ))

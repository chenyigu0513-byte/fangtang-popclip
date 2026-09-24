#!/bin/zsh

set -u

test_date="${YU_TEST_DATE:-2026-09-20}"
test_time="${YU_TEST_TIME:-10:51}"

case "${1:-}" in
  +%Y) print -r -- "${test_date[1,4]}" ;;
  +%m) print -r -- "${test_date[6,7]}" ;;
  +%d) print -r -- "${test_date[9,10]}" ;;
  +%Y-%m) print -r -- "${test_date[1,7]}" ;;
  +%Y-%m-%d) print -r -- "$test_date" ;;
  +%H:%M) print -r -- "$test_time" ;;
  '+%Y-%m-%d %H:%M') print -r -- "$test_date $test_time" ;;
  +%w)
    case "$test_date" in
      2026-09-20) print -r -- 0 ;;
      2026-09-21) print -r -- 1 ;;
      *) /bin/date "$@" ;;
    esac
    ;;
  *) /bin/date "$@" ;;
esac


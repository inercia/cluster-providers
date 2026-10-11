#!/usr/bin/env bash

printf '%s\n' "$*" >> "$TEST_CURL_LOG"
printf 'mock_install\n'
# Emit a partial script even on failure to ensure it is never executed.
[ "${TEST_CURL_FAIL:-0}" = 0 ] || exit 22

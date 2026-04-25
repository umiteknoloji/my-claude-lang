#!/bin/bash
# Test: normal prompts produce valid JSON output.

echo "--- test-json-validity ---"

_jv_dir="$(setup_test_dir)"

_out="$(run_activate_hook "$_jv_dir" "Create a simple login page")"
assert_json_valid "English prompt → valid JSON" "$_out"

_out="$(run_activate_hook "$_jv_dir" "Bana basit bir login sayfası yap")"
assert_json_valid "Turkish prompt → valid JSON" "$_out"

cleanup_test_dir "$_jv_dir"

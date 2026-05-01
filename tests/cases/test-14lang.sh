#!/bin/bash
# Test: Turkish prompt produces valid JSON output.

echo "--- test-14lang ---"

_14l_dir="$(setup_test_dir)"

_out="$(run_activate_hook "$_14l_dir" "Bana basit bir login sayfası yap")"
assert_json_valid "Turkish prompt → valid JSON" "$_out"

cleanup_test_dir "$_14l_dir"

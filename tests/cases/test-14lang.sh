#!/bin/bash
# Test: all 14 supported language prompts produce valid JSON output.

echo "--- test-14lang ---"

_14l_dir="$(setup_test_dir)"

while IFS= read -r _prompt || [ -n "$_prompt" ]; do
  [ -z "$_prompt" ] && continue
  [[ "$_prompt" == \#* ]] && continue
  _out="$(run_activate_hook "$_14l_dir" "$_prompt")"
  assert_json_valid "14lang prompt → valid JSON: ${_prompt:0:30}" "$_out"
done < "$REPO_ROOT/tests/fixtures/prompts-14lang.txt"

cleanup_test_dir "$_14l_dir"

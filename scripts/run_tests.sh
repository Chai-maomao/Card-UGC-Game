#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${1:-${GODOT_BIN:-godot}}"
suite="${2:-logic}"
case "$suite" in logic|visual) ;; *) echo "Suite must be logic or visual"; exit 2 ;; esac
godot_project_path="$repo_root"
if [[ "$godot_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  godot_project_path="$(wslpath -w "$repo_root")"
fi
log_dir="$repo_root/.godot/test-logs/$suite"
mkdir -p "$log_dir"

failed=0
count=0
for scene_path in "$repo_root"/Test*.tscn; do
  scene_name="$(basename "$scene_path")"
  if [[ "$suite" == logic && "$scene_name" == *Visual.tscn ]]; then continue; fi
  if [[ "$suite" == visual && "$scene_name" != *Visual.tscn ]]; then continue; fi
  log_path="$log_dir/${scene_name%.tscn}.log"
  count=$((count + 1))

  render_args=(--headless)
  if [[ "$suite" == visual ]]; then render_args=(--rendering-method gl_compatibility --rendering-driver opengl3); fi
  timeout "${TEST_TIMEOUT_SECONDS:-90}s" "$godot_bin" "${render_args[@]}" --path "$godot_project_path" \
    --scene "res://$scene_name" >"$log_path" 2>&1
  exit_code=$?
  marker="$(grep -E 'TEST_[A-Z0-9_]+_OK' "$log_path" | tail -n 1 || true)"

  if [ "$exit_code" -ne 0 ] \
    || grep -Eq 'SCRIPT ERROR|Parse Error|ERROR:|TEST_[A-Z0-9_]+_FAILED' "$log_path" \
    || [ -z "$marker" ]; then
    printf 'FAIL  %s (exit=%s)\n' "$scene_name" "$exit_code"
    sed -n '1,220p' "$log_path"
    failed=$((failed + 1))
  else
    printf 'PASS  %s  %s\n' "$scene_name" "$marker"
  fi
done

printf 'Ran %s test scenes; failures: %s\n' "$count" "$failed"
if [ "$count" -eq 0 ]; then exit 1; fi
exit "$failed"

#!/usr/bin/env bash
# MCL Dev Server lifecycle helpers (8.12.0).
#
# Public API (when sourced from a hook):
#   mcl_devserver_is_headless       — print "true"/"false"
#   mcl_devserver_detect <project>  — JSON via mcl-dev-server-detect.py
#   mcl_devserver_start <project>   — spawn + state set + audit
#   mcl_devserver_stop              — kill PID + state clear + audit
#   mcl_devserver_status            — "active"/"inactive"/"stale"
#
# State writes go through mcl_state_set which requires authorized caller
# (mcl-stop.sh / mcl-activate.sh / etc.). Direct CLI use limited.

if [ -n "${_MCL_DEVSERVER_LIB_LOADED:-}" ]; then
  return 0 2>/dev/null || true
fi
_MCL_DEVSERVER_LIB_LOADED=1

mcl_devserver_is_headless() {
  if [ -n "${MCL_HEADLESS:-}" ]; then printf 'true\n'; return; fi
  if [ -n "${CI:-}" ]; then printf 'true\n'; return; fi
  # Linux SSH heuristic: no DISPLAY and no Wayland.
  if [ "$(uname 2>/dev/null)" = "Linux" ] \
     && [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    printf 'true\n'; return
  fi
  printf 'false\n'
}

mcl_devserver_detect() {
  local proj="$1"
  local lib_dir; lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  python3 "$lib_dir/mcl-dev-server-detect.py" "$proj" 2>/dev/null || echo '{"stack":null}'
}

_mcl_devserver_port_free() {
  # Returns 0 if port is free, 1 if busy.
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    ! lsof -i ":$port" >/dev/null 2>&1
  elif command -v nc >/dev/null 2>&1; then
    ! nc -z 127.0.0.1 "$port" 2>/dev/null
  else
    # No tool available — assume free.
    return 0
  fi
}

mcl_devserver_start() {
  local proj="$1"
  local detection; detection="$(mcl_devserver_detect "$proj")"
  local stack default_port start_cmd args_json
  stack="$(printf '%s' "$detection" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("stack") or "")' 2>/dev/null)"
  if [ -z "$stack" ] || [ "$stack" = "None" ]; then
    return 1
  fi
  default_port="$(printf '%s' "$detection" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("default_port") or 0)' 2>/dev/null)"
  start_cmd="$(printf '%s' "$detection" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("start_cmd") or "")' 2>/dev/null)"
  args_json="$(printf '%s' "$detection" | python3 -c 'import json,sys; print(json.dumps(json.loads(sys.stdin.read()).get("args") or []))' 2>/dev/null)"

  # Port allocation (try default + 4 fallbacks).
  local port="$default_port"
  local tries=0
  while [ "$tries" -lt 5 ] && ! _mcl_devserver_port_free "$port"; do
    port=$((port + 1))
    tries=$((tries + 1))
  done
  if [ "$tries" -gt 0 ]; then
    mcl_audit_log "dev-server-port-fallback" "$(basename "${0:-mcl-stop.sh}")" \
      "requested=${default_port} assigned=${port}"
  fi
  if ! _mcl_devserver_port_free "$port"; then
    mcl_audit_log "dev-server-port-exhausted" "$(basename "${0:-mcl-stop.sh}")" \
      "tried=${default_port}-${port}"
    return 1
  fi

  local log_path="${MCL_STATE_DIR:?}/dev-server.log"
  local pid_file="${MCL_STATE_DIR}/dev-server.pid"
  : > "$log_path" 2>/dev/null

  # Build argv array
  local argv
  argv="$(printf '%s' "$args_json" | python3 -c '
import json, sys, shlex
print(" ".join(shlex.quote(x) for x in json.loads(sys.stdin.read())))
' 2>/dev/null)"

  # Spawn detached.
  (
    cd "$proj" || exit 1
    # PORT env hint for stacks that read it.
    PORT="$port" eval "nohup \"$start_cmd\" $argv > \"$log_path\" 2>&1 &"
    echo $! > "$pid_file"
  )
  local pid
  pid="$(cat "$pid_file" 2>/dev/null)"
  if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    mcl_audit_log "dev-server-spawn-failed" "$(basename "${0:-mcl-stop.sh}")" \
      "stack=${stack} port=${port}"
    return 1
  fi

  local url="http://localhost:${port}"
  [ "$stack" = "expo" ] && url="exp://localhost:${port}"
  local started_at; started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local payload
  payload="$(python3 -c '
import json, sys
print(json.dumps({
    "active": True,
    "stack": sys.argv[1],
    "port": int(sys.argv[2]),
    "url": sys.argv[3],
    "pid": int(sys.argv[4]),
    "started_at": sys.argv[5],
    "log_path": sys.argv[6],
}))
' "$stack" "$port" "$url" "$pid" "$started_at" "$log_path" 2>/dev/null)"
  if [ -n "$payload" ]; then
    mcl_state_set dev_server "$payload" >/dev/null 2>&1 || true
  fi
  mcl_audit_log "dev-server-started" "$(basename "${0:-mcl-stop.sh}")" \
    "stack=${stack} port=${port} pid=${pid} url=${url}"
  command -v mcl_trace_append >/dev/null 2>&1 && \
    mcl_trace_append dev_server_started "$stack:$port"
  return 0
}

mcl_devserver_status() {
  local pid_file="${MCL_STATE_DIR:?}/dev-server.pid"
  local active
  active="$(python3 -c '
import json, os, sys
sf = os.environ.get("MCL_STATE_FILE") or os.path.join(
    os.environ.get("MCL_STATE_DIR") or os.path.join(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd(), ".mcl"),
    "state.json")
try:
    with open(sf) as f:
        d = json.load(f)
    print("true" if (d.get("dev_server") or {}).get("active") else "false")
except Exception:
    print("false")
' 2>/dev/null)"
  if [ "$active" != "true" ]; then
    printf 'inactive\n'; return
  fi
  local pid; pid="$(cat "$pid_file" 2>/dev/null)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    printf 'active\n'
  else
    printf 'stale\n'
  fi
}

mcl_devserver_stop() {
  local pid_file="${MCL_STATE_DIR:?}/dev-server.pid"
  local pid; pid="$(cat "$pid_file" 2>/dev/null)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    sleep 1
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
  fi
  rm -f "$pid_file" 2>/dev/null
  mcl_state_set dev_server '{"active": false}' >/dev/null 2>&1 || true
  mcl_audit_log "dev-server-stopped" "$(basename "${0:-mcl-activate.sh}")" \
    "pid=${pid:-none}"
  command -v mcl_trace_append >/dev/null 2>&1 && \
    mcl_trace_append dev_server_stopped ""
}

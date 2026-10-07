#!/usr/bin/env bash

set -euo pipefail

native_repo_root() {
  local current
  current="$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")" && pwd)"
  while [[ "${current}" != "/" ]]; do
    if [[ -d "${current}/scripts" && -d "${current}/.github/skills" ]]; then
      printf '%s\n' "${current}"
      return 0
    fi
    current="$(dirname -- "${current}")"
  done
  printf 'ERROR: repository root not found.\n' >&2
  return 2
}

native_python() {
  if command -v python3 >/dev/null 2>&1; then
    command -v python3
  elif command -v python >/dev/null 2>&1; then
    command -v python
  else
    printf 'ERROR: python3 or python is required.\n' >&2
    return 127
  fi
}

native_abspath() {
  local _repo_root="$1"
  local _path="$2"
  if [[ "${_path}" = /* || "${_path}" =~ ^[A-Za-z]:[\\/] ]]; then
    printf '%s\n' "${_path}"
  else
    printf '%s/%s\n' "${_repo_root}" "${_path}"
  fi
}

native_collect_inputs() {
  local _repo_root="$1"
  local _manifest="$2"
  local files_name="$3"
  local paths_name="$4"
  local output_name="$5"
  local exclude_default_extensions="${6:-true}"
  local -n files_ref="${files_name}"
  local -n paths_ref="${paths_name}"
  local -n output_ref="${output_name}"
  local _python_bin
  _python_bin="$(native_python)"
  output_ref=()

  if [[ -n "${_manifest}" ]]; then
    local manifest_path
    manifest_path="$(native_abspath "${_repo_root}" "${_manifest}")"
    mapfile -t output_ref < <("${_python_bin}" - "${manifest_path}" <<'PY'
import csv
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
if path.suffix.lower() == ".csv":
    with path.open(newline="", encoding="utf-8-sig") as stream:
        rows = list(csv.DictReader(stream))
else:
    rows = json.loads(path.read_text(encoding="utf-8-sig"))
    if isinstance(rows, dict):
        rows = rows.get("files", rows.get("entries", [rows]))
for row in rows:
    value = row.get("path") if isinstance(row, dict) else row
    if value:
        print(value)
PY
    )
  else
    local candidate pattern match
    for candidate in "${files_ref[@]}"; do
      candidate="$(native_abspath "${_repo_root}" "${candidate}")"
      if [[ -d "${candidate}" ]]; then
        while IFS= read -r -d '' match; do output_ref+=("${match}"); done \
          < <(find "${candidate}" -type f -print0)
      else
        output_ref+=("${candidate}")
      fi
    done
    for pattern in "${paths_ref[@]}"; do
      pattern="$(native_abspath "${_repo_root}" "${pattern}")"
      if [[ -d "${pattern}" ]]; then
        while IFS= read -r -d '' match; do
          if [[ "${exclude_default_extensions}" == true ]]; then
            case "${match,,}" in *.cob|*.inp|*.itt) continue ;; esac
          fi
          output_ref+=("${match}")
        done \
          < <(find "${pattern}" -type f -print0)
      else
        while IFS= read -r match; do
          [[ -n "${match}" ]] || continue
          if [[ "${exclude_default_extensions}" == true ]]; then
            case "${match,,}" in *.cob|*.inp|*.itt) continue ;; esac
          fi
          output_ref+=("${match}")
        done < <(compgen -G "${pattern}" || true)
      fi
    done
  fi

  local -A seen=()
  local -a filtered=()
  for candidate in "${output_ref[@]}"; do
    candidate="$(native_abspath "${_repo_root}" "${candidate}")"
    if [[ -z "${seen[${candidate}]+x}" ]]; then
      seen["${candidate}"]=1
      filtered+=("${candidate}")
    fi
  done
  if ((${#filtered[@]} == 0)); then
    printf 'ERROR: no input files matched.\n' >&2
    return 2
  fi
  mapfile -t output_ref < <(printf '%s\n' "${filtered[@]}" | LC_ALL=C sort)
}

native_write_results_xml() {
  local results_path="$1"
  local rows_dir="$2"
  local _python_bin
  _python_bin="$(native_python)"
  mkdir -p -- "$(dirname -- "${results_path}")"
  "${_python_bin}" - "${rows_dir}" "${results_path}" <<'PY'
import json
import pathlib
import sys
import xml.etree.ElementTree as ET

rows_dir = pathlib.Path(sys.argv[1])
root = ET.Element("results")
for row_path in sorted(rows_dir.glob("*.json")):
    row = json.loads(row_path.read_text(encoding="utf-8"))
    item = ET.SubElement(root, "result")
    for key in ("path", "exit", "stdout", "stderr"):
        child = ET.SubElement(item, key)
        child.text = str(row.get(key, ""))
ET.indent(root)
ET.ElementTree(root).write(sys.argv[2], encoding="utf-8", xml_declaration=True)
PY
}

native_run_python_batch() {
  local throttle="$1"
  local results_path="$2"
  local worker="$3"
  local inputs_name="$4"
  local -n inputs_ref="${inputs_name}"
  local rows_dir
  rows_dir="$(mktemp -d)"
  trap 'rm -rf -- "${rows_dir}"' RETURN

  local index=0 running=0 failed=0 child_exit
  for input in "${inputs_ref[@]}"; do
    (
      local out_file err_file exit_code
      out_file="${rows_dir}/${index}.out"
      err_file="${rows_dir}/${index}.err"
      set +e
      "${worker}" "${input}" >"${out_file}" 2>"${err_file}"
      exit_code=$?
      set -e
      "$(native_python)" - "${rows_dir}/${index}.json" "${input}" "${exit_code}" "${out_file}" "${err_file}" <<'PY'
import json
import pathlib
import sys

path, source, exit_code, stdout_path, stderr_path = sys.argv[1:]
payload = {
    "path": source,
    "exit": int(exit_code),
    "stdout": pathlib.Path(stdout_path).read_text(encoding="utf-8", errors="replace"),
    "stderr": pathlib.Path(stderr_path).read_text(encoding="utf-8", errors="replace"),
}
pathlib.Path(path).write_text(json.dumps(payload, ensure_ascii=True), encoding="utf-8")
PY
      exit "${exit_code}"
    ) &
    index=$((index + 1))
    running=$((running + 1))
    if ((running >= throttle)); then
      if wait -n; then :; else
        child_exit=$?
        if ((child_exit == 4)); then failed=4; elif ((failed == 0)); then failed=1; fi
      fi
      running=$((running - 1))
    fi
  done
  while ((running > 0)); do
    if wait -n; then :; else
      child_exit=$?
      if ((child_exit == 4)); then failed=4; elif ((failed == 0)); then failed=1; fi
    fi
    running=$((running - 1))
  done
  native_write_results_xml "${results_path}" "${rows_dir}"
  return "${failed}"
}

native_normalize_option() {
  local option="${1#-}"
  option="${option#-}"
  printf '%s\n' "${option}" | tr '[:upper:]' '[:lower:]'
}
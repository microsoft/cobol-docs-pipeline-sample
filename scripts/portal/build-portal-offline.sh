#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/../lib/native-common.sh"
readonly repo_root="$(native_repo_root)"
readonly python_bin="$(native_python)"
args=()
while (($#)); do
	option="$(native_normalize_option "$1")"; shift
	case "${option}" in
		sourceroot) args+=(--source-root "$1"); shift ;;
		skipbuild) args+=(--skip-build) ;;
		site) args+=(--site "$1"); shift ;;
		out) args+=(--out "$1"); shift ;;
		open) open_after=true ;;
		*) args+=("--${option}" "$1"); shift ;;
	esac
done
(cd -- "${repo_root}" && "${python_bin}" "${script_dir}/build-portal-offline.py" "${args[@]}")
if [[ "${open_after:-false}" == true ]]; then
	output="${repo_root}/docs/_portal/site-offline/index.html"
	if command -v xdg-open >/dev/null 2>&1; then
		xdg-open "${output}" >/dev/null 2>&1 &
	elif command -v open >/dev/null 2>&1; then
		open "${output}" >/dev/null 2>&1 &
	elif command -v cmd.exe >/dev/null 2>&1; then
		cmd.exe /c start "" "$(wslpath -w "${output}")" >/dev/null 2>&1 &
	else
		printf 'WARNING: no browser opener found; open %s manually.\n' "${output}" >&2
	fi
fi

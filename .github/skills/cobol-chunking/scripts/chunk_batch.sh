#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/../../../../scripts/lib/native-common.sh"
readonly repo_root="$(native_repo_root)"
readonly python_bin="$(native_python)"

files=(); paths=(); manifest=""; source_root=""; kind_hint=""; platform_hint=""; encoding_hint=""
throttle="$(nproc 2>/dev/null || echo 1)"
results_xml="temp/chunk_results.xml"
while (($#)); do
	option="$(native_normalize_option "$1")"; shift
	case "${option}" in
		files) while (($#)) && [[ "$1" != -* ]]; do files+=("$1"); shift; done ;;
		paths) while (($#)) && [[ "$1" != -* ]]; do paths+=("$1"); shift; done ;;
		manifest) manifest="$1"; shift ;;
		sourceroot) source_root="$1"; shift ;;
		kindhint) kind_hint="$1"; shift ;;
		platformhint) platform_hint="$1"; shift ;;
		encodinghint) encoding_hint="$1"; shift ;;
		throttle) throttle="$1"; shift ;;
		resultsxml) results_xml="$1"; shift ;;
		*) printf 'ERROR: unknown option -%s\n' "${option}" >&2; exit 2 ;;
	esac
done
inputs=(); native_collect_inputs "${repo_root}" "${manifest}" files paths inputs
results_xml="$(native_abspath "${repo_root}" "${results_xml}")"

run_chunk() {
	args=("${script_dir}/chunk.py" --source "$1")
	[[ -n "${kind_hint}" ]] && args+=(--kind-hint "${kind_hint}")
	[[ -n "${platform_hint}" ]] && args+=(--platform-hint "${platform_hint}")
	[[ -n "${encoding_hint}" ]] && args+=(--encoding-hint "${encoding_hint}")
	[[ -n "${source_root}" ]] && args+=(--source-root "${source_root}")
	"${python_bin}" "${args[@]}"
}
export script_dir python_bin source_root kind_hint platform_hint encoding_hint
export -f run_chunk
printf 'Chunking %d file(s) with throttle=%s\n' "${#inputs[@]}" "${throttle}"
native_run_python_batch "${throttle}" "${results_xml}" run_chunk inputs

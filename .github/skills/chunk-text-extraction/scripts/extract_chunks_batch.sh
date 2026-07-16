#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/../../../../scripts/lib/native-common.sh"
readonly repo_root="$(native_repo_root)"
readonly python_bin="$(native_python)"

files=(); paths=(); manifest=""; source_root=""; output_dir=""; prune=false
throttle="$(nproc 2>/dev/null || echo 1)"; results_xml="temp/chunk_text_results.xml"
while (($#)); do
	option="$(native_normalize_option "$1")"; shift
	case "${option}" in
		files) while (($#)) && [[ "$1" != -* ]]; do files+=("$1"); shift; done ;;
		paths) while (($#)) && [[ "$1" != -* ]]; do paths+=("$1"); shift; done ;;
		manifest) manifest="$1"; shift ;;
		sourceroot) source_root="$1"; shift ;;
		outputdir) output_dir="$1"; shift ;;
		prune) prune=true ;;
		throttle) throttle="$1"; shift ;;
		resultsxml) results_xml="$1"; shift ;;
		*) printf 'ERROR: unknown option -%s\n' "${option}" >&2; exit 2 ;;
	esac
done
inputs=(); native_collect_inputs "${repo_root}" "${manifest}" files paths inputs
results_xml="$(native_abspath "${repo_root}" "${results_xml}")"

run_chunks() {
	args=("${script_dir}/extract-chunks.py" --source "$1")
	[[ -n "${source_root}" ]] && args+=(--source-root "${source_root}")
	[[ -n "${output_dir}" ]] && args+=(--output-dir "${output_dir}")
	${prune} && args+=(--prune)
	"${python_bin}" "${args[@]}"
}
export script_dir python_bin source_root output_dir prune
export -f run_chunks
printf 'Extracting chunks for %d file(s) with throttle=%s\n' "${#inputs[@]}" "${throttle}"
native_run_python_batch "${throttle}" "${results_xml}" run_chunks inputs

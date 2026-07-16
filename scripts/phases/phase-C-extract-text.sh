#!/usr/bin/env bash
set -euo pipefail
readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
results_dir="temp"; args=()
while (($#)); do
	if [[ "${1,,}" == "-resultsdir" || "${1,,}" == "--resultsdir" ]]; then
		results_dir="$2"; shift 2
	else args+=("$1"); shift
	fi
done
exec "${script_dir}/../../.github/skills/chunk-text-extraction/scripts/extract_chunks_batch.sh" \
	"${args[@]}" -ResultsXml "${results_dir}/chunk_text_results.xml"

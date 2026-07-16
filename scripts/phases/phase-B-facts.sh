#!/usr/bin/env bash
set -euo pipefail
readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
results_dir="temp"; skip_xref=false; args=()
while (($#)); do
	case "${1,,}" in
		-resultsdir|--resultsdir) results_dir="$2"; shift 2 ;;
		-skipxrefpass|--skipxrefpass) skip_xref=true; shift ;;
		*) args+=("$1"); shift ;;
	esac
done
batch="${script_dir}/../../.github/skills/cobol-facts-extraction/scripts/extract_facts_batch.sh"
"${batch}" "${args[@]}" -ResultsXml "${results_dir}/facts_results.xml"
${skip_xref} || "${batch}" -XrefPass

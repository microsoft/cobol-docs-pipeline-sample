#!/usr/bin/env bash
set -euo pipefail

readonly native_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${native_dir}/native-common.sh"

pandoc_path="pandoc"; results_xml="temp/docx_results.xml"; force=false; markdown_paths=()
while (($#)); do
  option="$(native_normalize_option "$1")"; shift
  case "${option}" in
    pandocpath) pandoc_path="$1"; shift ;;
    resultsxml) results_xml="$1"; shift ;;
    force) force=true ;;
    markdownpaths|files) while (($#)) && [[ "$1" != -* ]]; do markdown_paths+=("$1"); shift; done ;;
    *) printf 'ERROR: unknown native DOCX option: -%s\n' "${option}" >&2; exit 2 ;;
  esac
done

if ! command -v "${pandoc_path}" >/dev/null 2>&1 && [[ ! -x "${pandoc_path}" ]]; then
  printf 'WARNING: pandoc not found (%s); skipping DOCX conversion.\n' "${pandoc_path}" >&2
  exit 0
fi
if ((${#markdown_paths[@]} == 0)); then
  printf 'No Markdown outputs found to convert to DOCX.\n'
  exit 0
fi

run_docx() {
  local markdown_path="$1" docx_path
  docx_path="${markdown_path%.md}.docx"
  if ! ${force} && [[ -f "${docx_path}" && "${docx_path}" -nt "${markdown_path}" ]]; then
    printf 'Up to date: %s\n' "${docx_path}"
    return 0
  fi
  "${pandoc_path}" "${markdown_path}" --from gfm --to docx --output "${docx_path}"
}
export pandoc_path force
export -f run_docx
native_run_python_batch 1 "${results_xml}" run_docx markdown_paths
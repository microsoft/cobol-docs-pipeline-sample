#!/usr/bin/env bash
set -euo pipefail

readonly native_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${native_dir}/native-common.sh"
readonly repo_root="$(native_repo_root)"
if (($# < 1)); then printf 'Usage: %s <D-N> [options]\n' "$0" >&2; exit 2; fi
phase="${1^^}"; shift

files=(); paths=(); input_manifest=""; source_root=""; results_dir="temp"; throttle="$(nproc 2>/dev/null || echo 1)"
languages="en"; profile_name=""; agent=""; section_throttle=6; finalizer_throttle=4
dispatch_throttle=4; grouping_manifest="config/grouping.yaml"; pandoc_path="pandoc"
dry_run=false; force=false; prune=false; skip_docx=false
portal_skip=false; portal_site=""; portal_out=""; portal_open=false
portal_languages=""
while (($#)); do
  option="$(native_normalize_option "$1")"; shift
  case "${option}" in
    files) while (($#)) && [[ "$1" != -* ]]; do files+=("$1"); shift; done ;;
    paths) while (($#)) && [[ "$1" != -* ]]; do paths+=("$1"); shift; done ;;
    manifest) input_manifest="$1"; shift ;;
    groupingmanifest) grouping_manifest="$1"; shift ;;
    sourceroot) source_root="$1"; shift ;;
    resultsdir) results_dir="$1"; shift ;;
    throttle) throttle="$1"; shift ;;
    languages|grouplanguages) languages="$1"; portal_languages="$1"; shift ;;
    profilename|profile) profile_name="$1"; shift ;;
    agent) agent="$1"; shift ;;
    docsthrottle|diagramsthrottle) dispatch_throttle="$1"; shift ;;
    sectionthrottle) section_throttle="$1"; shift ;;
    finalizerthrottle) finalizer_throttle="$1"; shift ;;
    dryrun|groupdryrun) dry_run=true ;;
    force|groupforce) force=true ;;
    prune|groupprune) prune=true ;;
    skipdocx|technicalanalysisskipdocx) skip_docx=true ;;
    trackusage|skipxrefpass) ;;
    oteldir|premiummultiplier) shift ;;
    pandocpath) pandoc_path="$1"; shift ;;
    skipbuild|portalskipbuild) portal_skip=true ;;
    site|portalsite) portal_site="$1"; shift ;;
    out|portalout) portal_out="$1"; shift ;;
    open|portalopen) portal_open=true ;;
    *) printf 'ERROR: unknown phase %s option -%s.\n' "${phase}" "${option}" >&2; exit 2 ;;
  esac
done
mkdir -p -- "${results_dir}"
selectors=()
((${#files[@]})) && selectors+=(-Files "${files[@]}")
((${#paths[@]})) && selectors+=(-Paths "${paths[@]}")
[[ -n "${input_manifest}" ]] && selectors+=(-Manifest "${input_manifest}")
[[ -n "${source_root}" ]] && selectors+=(-SourceRoot "${source_root}")
flags=(); ${force} && flags+=(-Force); ${prune} && flags+=(-Prune)
dispatch_flags=(); ${dry_run} && dispatch_flags+=(-DryRun); ${force} && dispatch_flags+=(-Force)
profile_flags=(); [[ -n "${profile_name}" ]] && profile_flags+=(-ProfileName "${profile_name}")
docx_flags=(); ${force} && docx_flags+=(-Force)

skill() { "${repo_root}/$1" "${@:2}"; }
dispatch() { "${repo_root}/$1" "${@:2}"; }

source_docx() {
  local document_name="$1" results_name="$2" input basename language
  ${dry_run} && return 0
  ${skip_docx} && return 0
  local -a source_inputs=() markdown_paths=()
  native_collect_inputs "${repo_root}" "${input_manifest}" files paths source_inputs
  read -r -a language_list <<<"${languages//,/ }"
  for input in "${source_inputs[@]}"; do
    basename="$(basename -- "${input}")"
    for language in "${language_list[@]}"; do
      target="${repo_root}/docs/${language}/${basename}/${document_name}"
      [[ -f "${target}" ]] && markdown_paths+=("${target}")
    done
  done
  "${repo_root}/scripts/lib/native-docx.sh" -MarkdownPaths "${markdown_paths[@]}" \
    -PandocPath "${pandoc_path}" -ResultsXml "${results_dir}/${results_name}" "${docx_flags[@]}"
}

group_docx() {
  local document_name="$1" results_name="$2" group_id language target
  ${dry_run} && return 0
  ${skip_docx} && return 0
  local -a markdown_paths=()
  read -r -a language_list <<<"${languages//,/ }"
  mapfile -t group_ids < <(
    "$(native_python)" "${repo_root}/scripts/lib/read_groups.py" "${grouping_manifest}" |
      "$(native_python)" -c '
import json, sys
groups = json.load(sys.stdin)
sys.stdout.write("\n".join(str(group["id"]).strip() for group in groups if str(group.get("id", "")).strip()))
'
  )
  for group_id in "${group_ids[@]}"; do
    for language in "${language_list[@]}"; do
      target="${repo_root}/docs/${language}/_groups/${group_id}/${document_name}"
      [[ -f "${target}" ]] && markdown_paths+=("${target}")
    done
  done
  "${repo_root}/scripts/lib/native-docx.sh" -MarkdownPaths "${markdown_paths[@]}" \
    -PandocPath "${pandoc_path}" -ResultsXml "${results_dir}/${results_name}" "${docx_flags[@]}"
}

case "${phase}" in
  D)
    dispatch scripts/dispatchers/run-docs-copilot-batch.sh "${selectors[@]}" -EnsureBundles \
      -Languages "${languages}" \
      -Agent "${agent:-section-doc-writer}" -Throttle "${dispatch_throttle}" \
      -ResultsXml "${results_dir}/copilot_doc_results.xml" "${dispatch_flags[@]}"
    ;;
  E)
    skill .github/skills/section-doc-finalizer/scripts/finalize_stage_batch.sh "${selectors[@]}" \
      -Languages "${languages}" -Throttle "${throttle}" -ResultsXml "${results_dir}/finalize_stage_results.xml"
    dispatch scripts/dispatchers/run-docs-finalize-batch.sh "${selectors[@]}" -Languages "${languages}" \
      -Agent "${agent:-section-doc-finalizer}" -Throttle "${finalizer_throttle}" \
      -ResultsXml "${results_dir}/copilot_finalize_results.xml" "${dispatch_flags[@]}"
    ${dry_run} || skill .github/skills/section-doc-finalizer/scripts/assemble_complete_batch.sh \
      "${selectors[@]}" -Languages "${languages}" -Throttle "${throttle}" \
      -ResultsXml "${results_dir}/complete_assemble_results.xml" "${flags[@]}"
    source_docx complete.md complete_docx_results.xml
    ;;
  F)
    skill .github/skills/requirements-writer/scripts/req_stage_batch.sh \
      "${selectors[@]}" -Languages "${languages}" \
      -Throttle "${throttle}" -ResultsXml "${results_dir}/req_stage_results.xml" "${profile_flags[@]}" "${flags[@]}"
    dispatch scripts/dispatchers/run-docs-req-section-batch.sh "${selectors[@]}" -Languages "${languages}" \
      -Agent "${agent:-requirements-writer}" -Throttle "${section_throttle}" \
      -ResultsXml "${results_dir}/copilot_req_section_results.xml" "${dispatch_flags[@]}"
    skill .github/skills/requirements-finalizer/scripts/req_finalize_stage_batch.sh \
      "${selectors[@]}" -Languages "${languages}" \
      -Throttle "${throttle}" -ResultsXml "${results_dir}/req_finalize_stage_results.xml" "${profile_flags[@]}"
    dispatch scripts/dispatchers/run-docs-req-finalize-batch.sh "${selectors[@]}" -Languages "${languages}" \
      -Agent "${agent:-requirements-writer}" -Throttle "${finalizer_throttle}" \
      -ResultsXml "${results_dir}/copilot_req_finalize_results.xml" "${dispatch_flags[@]}"
    source_docx requirements.md req_docx_results.xml
    ;;
  G)
    skill .github/skills/functional-analysis-writer/scripts/fa_stage_batch.sh \
      "${selectors[@]}" -Languages "${languages}" \
      -Throttle "${throttle}" -ResultsXml "${results_dir}/fa_stage_results.xml" "${profile_flags[@]}" "${flags[@]}"
    dispatch scripts/dispatchers/run-docs-fa-section-batch.sh "${selectors[@]}" -Languages "${languages}" \
      -Agent "${agent:-functional-analysis-writer}" -Throttle "${section_throttle}" \
      -ResultsXml "${results_dir}/copilot_fa_section_results.xml" "${dispatch_flags[@]}"
    skill .github/skills/functional-analysis-finalizer/scripts/fa_finalize_stage_batch.sh \
      "${selectors[@]}" -Languages "${languages}" \
      -Throttle "${throttle}" -ResultsXml "${results_dir}/fa_finalize_stage_results.xml" "${profile_flags[@]}"
    dispatch scripts/dispatchers/run-docs-fa-finalize-batch.sh "${selectors[@]}" -Languages "${languages}" \
      -Agent "${agent:-functional-analysis-writer}" -Throttle "${finalizer_throttle}" \
      -ResultsXml "${results_dir}/copilot_fa_finalize_results.xml" "${dispatch_flags[@]}"
    source_docx functional-analysis.md fa_docx_results.xml
    ;;
  H)
    skill .github/skills/diagram-renderer/scripts/diagrams_stage_batch.sh "${selectors[@]}" -Throttle "${throttle}" \
      -ResultsXml "${results_dir}/diagrams_stage_results.xml"
    dispatch scripts/dispatchers/run-docs-diagrams-batch.sh "${selectors[@]}" -Agent "${agent:-diagram-renderer}" \
      -Throttle "${dispatch_throttle}" -ResultsXml "${results_dir}/diagrams_results.xml" "${dispatch_flags[@]}"
    ;;
  I|J|K|M)
    case "${phase}" in
      I)
        stage=".github/skills/group-doc-finalizer/scripts/group_doc_stage_batch.sh"
        dispatcher="scripts/dispatchers/run-docs-group-doc-finalize-batch.sh"
        ;;
      J)
        stage=".github/skills/requirements-group-writer/scripts/req_group_stage_batch.sh"
        dispatcher="scripts/dispatchers/run-docs-req-group-finalize-batch.sh"
        ;;
      K)
        stage=".github/skills/functional-analysis-group-writer/scripts/fa_group_stage_batch.sh"
        dispatcher="scripts/dispatchers/run-docs-fa-group-finalize-batch.sh"
        ;;
      M)
        stage=".github/skills/technical-analysis-writer/scripts/ta_group_stage_batch.sh"
        dispatcher="scripts/dispatchers/run-docs-ta-group-finalize-batch.sh"
        ;;
    esac
    skill "${stage}" -Manifest "${grouping_manifest}" -Languages "${languages}" -Throttle "${throttle}" \
      -ResultsXml "${results_dir}/group_${phase}_stage_results.xml" "${profile_flags[@]}" "${flags[@]}"
    if [[ "${phase}" == J ]]; then
      dispatch scripts/dispatchers/run-docs-req-group-section-batch.sh \
        -Manifest "${grouping_manifest}" \
        -Languages "${languages}" -Agent "${agent:-requirements-group-writer}" -Throttle "${section_throttle}" \
        -ResultsXml "${results_dir}/copilot_req_group_section_results.xml" "${dispatch_flags[@]}"
    elif [[ "${phase}" == K ]]; then
      dispatch scripts/dispatchers/run-docs-fa-group-section-batch.sh \
        -Manifest "${grouping_manifest}" \
        -Languages "${languages}" -Agent "${agent:-functional-analysis-group-writer}" -Throttle "${section_throttle}" \
        -ResultsXml "${results_dir}/copilot_fa_group_section_results.xml" "${dispatch_flags[@]}"
    fi
    dispatch "${dispatcher}" -Manifest "${grouping_manifest}" -Languages "${languages}" \
      -Throttle "${finalizer_throttle}" \
      -ResultsXml "${results_dir}/group_${phase}_results.xml" "${dispatch_flags[@]}"
    case "${phase}" in
      I) group_docx complete.md group_complete_docx_results.xml ;;
      J) group_docx requirements.md req_group_docx_results.xml ;;
      K) group_docx functional-analysis.md fa_group_docx_results.xml ;;
      M) group_docx technical-analysis.md ta_group_docx_results.xml ;;
    esac
    ;;
  L)
    skill .github/skills/technical-analysis-writer/scripts/ta_stage_batch.sh \
      "${selectors[@]}" -Languages "${languages}" \
      -Throttle "${throttle}" -ResultsXml "${results_dir}/ta_stage_results.xml" "${profile_flags[@]}"
    dispatch scripts/dispatchers/run-docs-ta-finalize-batch.sh "${selectors[@]}" -Languages "${languages}" \
      -Throttle "${finalizer_throttle}" -ResultsXml "${results_dir}/ta_finalize_results.xml" "${dispatch_flags[@]}"
    source_docx technical-analysis.md ta_docx_results.xml
    ;;
  N)
    portal_args=(); [[ -n "${source_root}" ]] && portal_args+=(--source-root "${source_root}")
    [[ -n "${portal_languages}" ]] && portal_args+=(--languages "${portal_languages}")
    ${portal_skip} && portal_args+=(--skip-build)
    [[ -n "${portal_site}" ]] && portal_args+=(--site "${portal_site}")
    [[ -n "${portal_out}" ]] && portal_args+=(--out "${portal_out}")
    ${portal_open} && portal_args+=(--open)
    "${repo_root}/scripts/portal/build-portal-offline.sh" "${portal_args[@]}"
    ;;
  *) printf 'ERROR: native phase must be D through N.\n' >&2; exit 2 ;;
esac
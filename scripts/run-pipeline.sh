#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/lib/native-common.sh"
readonly phase_order=(A B C D E F G H I J K L M N)

files=(); paths=(); selected_requested=(); skipped=()
manifest=""; source_root=""; throttle="$(nproc 2>/dev/null || echo 1)"; results_dir="temp"
max_phase_retries=3; from_phase="A"; to_phase="N"
run_workspace_xref=true; run_copilot_docs=true; run_section_finalizer=true
run_functional_analysis=true; run_diagrams=true; run_group_docs=true
run_group_requirements=true; run_group_functional_analysis=true
run_technical_analysis=true; run_group_technical_analysis=true; run_portal=true
copilot_docs_dry_run=false; copilot_docs_agent="section-doc-writer"; copilot_docs_throttle=15
copilot_docs_track_usage=true; copilot_docs_otel_dir=""; copilot_docs_premium_multiplier=1
section_languages="en"; section_agent="section-doc-finalizer"; section_throttle=4
section_dry_run=false; section_force=false
requirements_languages="en"; requirements_profile=""; requirements_prune=false; requirements_force=false
functional_languages="en"; functional_profile=""; functional_prune=false; functional_force=false
diagrams_agent="diagram-renderer"; diagrams_throttle=4; diagrams_dry_run=false; diagrams_force=false
skip_docx=false; pandoc_path="pandoc"
technical_languages="en"; technical_profile=""; technical_skip_docx=false
technical_dry_run=false; technical_force=false
grouping_manifest="config/grouping.yaml"; group_languages="en"
group_requirements_profile=""; group_functional_profile=""; group_technical_profile=""
group_prune=false; group_dry_run=false; group_force=false
portal_skip_build=false; portal_site=""; portal_out=""; portal_open=false

parse_bool() {
  case "${1,,}" in
    true|1|yes|on|'') printf 'true\n' ;;
    false|0|no|off) printf 'false\n' ;;
    *) printf 'ERROR: invalid Boolean value: %s\n' "$1" >&2; return 2 ;;
  esac
}

while (($#)); do
  raw_option="$1"; shift
  inline_value=""
  if [[ "${raw_option}" == *:* ]]; then
    inline_value="${raw_option#*:}"
    raw_option="${raw_option%%:*}"
  fi
  option="$(native_normalize_option "${raw_option}")"
  case "${option}" in
    files) while (($#)) && [[ "$1" != -* ]]; do files+=("$1"); shift; done ;;
    paths) while (($#)) && [[ "$1" != -* ]]; do paths+=("$1"); shift; done ;;
    manifest) manifest="$1"; shift ;;
    sourceroot) source_root="$1"; shift ;;
    throttle) throttle="$1"; shift ;;
    resultsdir) results_dir="$1"; shift ;;
    maxphaseretries) max_phase_retries="$1"; shift ;;
    phases)
      while (($#)) && [[ "$1" != -* ]]; do
        IFS=',' read -r -a values <<<"$1"
        selected_requested+=("${values[@]}")
        shift
      done
      ;;
    from) from_phase="${1^^}"; shift ;;
    to) to_phase="${1^^}"; shift ;;
    skip)
      while (($#)) && [[ "$1" != -* ]]; do
        IFS=',' read -r -a values <<<"$1"
        skipped+=("${values[@]}")
        shift
      done
      ;;
    runworkspacexrefpass) run_workspace_xref="$(parse_bool "${inline_value:-true}")" ;;
    runcopilotdocs) run_copilot_docs="$(parse_bool "${inline_value:-true}")" ;;
    runsectionfinalizer) run_section_finalizer="$(parse_bool "${inline_value:-true}")" ;;
    runfunctionalanalysis) run_functional_analysis="$(parse_bool "${inline_value:-true}")" ;;
    rundiagrams) run_diagrams="$(parse_bool "${inline_value:-true}")" ;;
    rungroupdocs) run_group_docs="$(parse_bool "${inline_value:-true}")" ;;
    rungrouprequirements) run_group_requirements="$(parse_bool "${inline_value:-true}")" ;;
    rungroupfunctionalanalysis) run_group_functional_analysis="$(parse_bool "${inline_value:-true}")" ;;
    runtechnicalanalysis) run_technical_analysis="$(parse_bool "${inline_value:-true}")" ;;
    rungrouptechnicalanalysis) run_group_technical_analysis="$(parse_bool "${inline_value:-true}")" ;;
    runportal) run_portal="$(parse_bool "${inline_value:-true}")" ;;
    copilotdocsdryrun) copilot_docs_dry_run=true ;;
    copilotdocsagent) copilot_docs_agent="$1"; shift ;;
    copilotdocsthrottle) copilot_docs_throttle="$1"; shift ;;
    copilotdocstrackusage) copilot_docs_track_usage="$(parse_bool "${inline_value:-true}")" ;;
    copilotdocsoteldir) copilot_docs_otel_dir="$1"; shift ;;
    copilotdocspremiummultiplier) copilot_docs_premium_multiplier="$1"; shift ;;
    sectionfinalizerlanguages) section_languages="$1"; shift ;;
    sectionfinalizeragent) section_agent="$1"; shift ;;
    sectionfinalizerthrottle) section_throttle="$1"; shift ;;
    sectionfinalizerdryrun) section_dry_run=true ;;
    sectionfinalizerforce) section_force=true ;;
    requirementslanguages) requirements_languages="$1"; shift ;;
    requirementsprofile) requirements_profile="$1"; shift ;;
    requirementsprune) requirements_prune=true ;;
    requirementsforce) requirements_force=true ;;
    functionalanalysislanguages) functional_languages="$1"; shift ;;
    functionalanalysisprofile) functional_profile="$1"; shift ;;
    functionalanalysisprune) functional_prune=true ;;
    functionalanalysisforce) functional_force=true ;;
    diagramsagent) diagrams_agent="$1"; shift ;;
    diagramsthrottle) diagrams_throttle="$1"; shift ;;
    diagramsdryrun) diagrams_dry_run=true ;;
    diagramsforce) diagrams_force=true ;;
    skipdocx) skip_docx=true ;;
    technicalanalysislanguages) technical_languages="$1"; shift ;;
    technicalanalysisprofile) technical_profile="$1"; shift ;;
    pandocpath) pandoc_path="$1"; shift ;;
    technicalanalysisskipdocx) technical_skip_docx=true ;;
    technicalanalysisdryrun) technical_dry_run=true ;;
    technicalanalysisforce) technical_force=true ;;
    groupingmanifest) grouping_manifest="$1"; shift ;;
    grouplanguages) group_languages="$1"; shift ;;
    grouprequirementsprofile) group_requirements_profile="$1"; shift ;;
    groupfunctionalanalysisprofile) group_functional_profile="$1"; shift ;;
    grouptechnicalanalysisprofile) group_technical_profile="$1"; shift ;;
    groupprune) group_prune=true ;;
    groupdryrun) group_dry_run=true ;;
    groupforce) group_force=true ;;
    portalskipbuild) portal_skip_build=true ;;
    portalsite) portal_site="$1"; shift ;;
    portalout) portal_out="$1"; shift ;;
    portalopen) portal_open=true ;;
    *) printf 'ERROR: unsupported pipeline option: %s\n' "${raw_option}" >&2; exit 2 ;;
  esac
done

if ((${#files[@]} == 0 && ${#paths[@]} == 0)) && [[ -z "${manifest}" ]]; then
  printf 'ERROR: provide -Files, -Paths, or -Manifest.\n' >&2; exit 2
fi
[[ "${throttle}" =~ ^[1-9][0-9]*$ ]] || { printf 'ERROR: -Throttle must be at least 1.\n' >&2; exit 2; }
[[ "${max_phase_retries}" =~ ^[0-9]+$ ]] || {
  printf 'ERROR: -MaxPhaseRetries must be non-negative.\n' >&2
  exit 2
}

phase_index() {
  local needle="${1^^}" index
  for index in "${!phase_order[@]}"; do
    [[ "${phase_order[index]}" == "${needle}" ]] && {
      printf '%s\n' "${index}"
      return 0
    }
  done
  return 1
}

selected=()
if ((${#selected_requested[@]})); then
  for phase in "${phase_order[@]}"; do
    for requested in "${selected_requested[@]}"; do
      [[ "${phase}" == "${requested^^}" ]] && selected+=("${phase}")
    done
  done
else
  start="$(phase_index "${from_phase}")" || { printf 'ERROR: invalid -From phase: %s\n' "${from_phase}" >&2; exit 2; }
  end="$(phase_index "${to_phase}")" || { printf 'ERROR: invalid -To phase: %s\n' "${to_phase}" >&2; exit 2; }
  ((start <= end)) || { printf 'ERROR: -From %s is after -To %s.\n' "${from_phase}" "${to_phase}" >&2; exit 2; }
  selected=("${phase_order[@]:start:end-start+1}")
fi

phase_enabled() {
  case "$1" in
    D) ${run_copilot_docs} ;;
    E) ${run_section_finalizer} ;;
    G) ${run_functional_analysis} ;;
    H) ${run_diagrams} ;;
    I) ${run_group_docs} ;; J) ${run_group_requirements} ;; K) ${run_group_functional_analysis} ;;
    L) ${run_technical_analysis} ;; M) ${run_group_technical_analysis} ;; N) ${run_portal} ;; *) return 0 ;;
  esac
}
is_skipped() {
  local candidate
  for candidate in "${skipped[@]}"; do
    [[ "$1" == "${candidate^^}" ]] && return 0
  done
  return 1
}
filtered=()
for phase in "${selected[@]}"; do
  phase_enabled "${phase}" && ! is_skipped "${phase}" && filtered+=("${phase}")
done
selected=("${filtered[@]}")
if ((${#selected[@]} == 0)); then printf 'No phases selected. Nothing to do.\n'; exit 0; fi

selector_args=()
((${#files[@]})) && selector_args+=(-Files "${files[@]}")
((${#paths[@]})) && selector_args+=(-Paths "${paths[@]}")
[[ -n "${manifest}" ]] && selector_args+=(-Manifest "${manifest}")
[[ -n "${source_root}" ]] && selector_args+=(-SourceRoot "${source_root}")
mkdir -p -- "${results_dir}"

phase_script() {
  case "$1" in
    A) echo "${script_dir}/phases/phase-A-chunk.sh" ;;
    B) echo "${script_dir}/phases/phase-B-facts.sh" ;;
    C) echo "${script_dir}/phases/phase-C-extract-text.sh" ;;
    D) echo "${script_dir}/phases/phase-D-section-docs.sh" ;;
    E) echo "${script_dir}/phases/phase-E-finalize.sh" ;;
    F) echo "${script_dir}/phases/phase-F-requirements.sh" ;;
    G) echo "${script_dir}/phases/phase-G-functional-analysis.sh" ;;
    H) echo "${script_dir}/phases/phase-H-diagrams.sh" ;;
    I) echo "${script_dir}/phases/phase-I-group-docs.sh" ;;
    J) echo "${script_dir}/phases/phase-J-group-requirements.sh" ;;
    K) echo "${script_dir}/phases/phase-K-group-functional-analysis.sh" ;;
    L) echo "${script_dir}/phases/phase-L-technical-analysis.sh" ;;
    M) echo "${script_dir}/phases/phase-M-group-technical-analysis.sh" ;;
    N) echo "${script_dir}/phases/phase-N-portal.sh" ;;
  esac
}

build_phase_args() {
  local phase="$1" output_name="$2"; local -n output_ref="${output_name}"; output_ref=()
  case "${phase}" in
    A|B|C|D|E|F|G|H|L)
      output_ref+=("${selector_args[@]}" -Throttle "${throttle}" -ResultsDir "${results_dir}")
      ;;
    I|J|K|M) output_ref+=(-ResultsDir "${results_dir}") ;;
  esac
  case "${phase}" in
    B) ! ${run_workspace_xref} && output_ref+=(-SkipXrefPass) ;;
    D)
      output_ref+=(-Agent "${copilot_docs_agent}" -DocsThrottle "${copilot_docs_throttle}")
      ${copilot_docs_dry_run} && output_ref+=(-DryRun)
      ${copilot_docs_track_usage} && output_ref+=(-TrackUsage)
      [[ -n "${copilot_docs_otel_dir}" ]] && output_ref+=(-OtelDir "${copilot_docs_otel_dir}")
      [[ "${copilot_docs_premium_multiplier}" != 1 ]] &&
        output_ref+=(-PremiumMultiplier "${copilot_docs_premium_multiplier}")
      ;;
    E)
      output_ref+=(
        -Languages "${section_languages}" -Agent "${section_agent}"
        -FinalizerThrottle "${section_throttle}" -PandocPath "${pandoc_path}"
      )
      ${section_dry_run} && output_ref+=(-DryRun)
      ${section_force} && output_ref+=(-Force)
      ${skip_docx} && output_ref+=(-SkipDocx)
      ;;
    F|G)
      if [[ "${phase}" == F ]]; then
        languages="${requirements_languages}"; profile="${requirements_profile}"
        prune="${requirements_prune}"; force="${requirements_force}"
      else
        languages="${functional_languages}"; profile="${functional_profile}"
        prune="${functional_prune}"; force="${functional_force}"
      fi
      output_ref+=(-Languages "${languages}" -PandocPath "${pandoc_path}")
      [[ -n "${profile}" ]] && output_ref+=(-ProfileName "${profile}")
      ${prune} && output_ref+=(-Prune)
      ${force} && output_ref+=(-Force)
      ${skip_docx} && output_ref+=(-SkipDocx)
      ;;
    H)
      output_ref+=(-Agent "${diagrams_agent}" -DiagramsThrottle "${diagrams_throttle}")
      ${diagrams_dry_run} && output_ref+=(-DryRun)
      ${diagrams_force} && output_ref+=(-Force)
      ;;
    I|J|K|M)
      output_ref+=(
        -GroupingManifest "${grouping_manifest}" -Languages "${group_languages}"
        -PandocPath "${pandoc_path}"
      )
      [[ "${phase}" == J && -n "${group_requirements_profile}" ]] &&
        output_ref+=(-ProfileName "${group_requirements_profile}")
      [[ "${phase}" == K && -n "${group_functional_profile}" ]] &&
        output_ref+=(-ProfileName "${group_functional_profile}")
      [[ "${phase}" == M && -n "${group_technical_profile}" ]] &&
        output_ref+=(-ProfileName "${group_technical_profile}")
      ${group_prune} && output_ref+=(-Prune)
      ${group_dry_run} && output_ref+=(-DryRun)
      ${group_force} && output_ref+=(-Force)
      ${skip_docx} && output_ref+=(-SkipDocx)
      [[ "${phase}" == M ]] && ${technical_skip_docx} && output_ref+=(-SkipDocx)
      ;;
    L)
      output_ref+=(-Languages "${technical_languages}" -PandocPath "${pandoc_path}")
      [[ -n "${technical_profile}" ]] && output_ref+=(-ProfileName "${technical_profile}")
      ${technical_skip_docx} && output_ref+=(-SkipDocx)
      ${technical_dry_run} && output_ref+=(-DryRun)
      ${technical_force} && output_ref+=(-Force)
      ;;
    N)
      [[ -n "${source_root}" ]] && output_ref+=(-SourceRoot "${source_root}")
      ${portal_skip_build} && output_ref+=(-SkipBuild)
      [[ -n "${portal_site}" ]] && output_ref+=(-Site "${portal_site}")
      [[ -n "${portal_out}" ]] && output_ref+=(-Out "${portal_out}")
      ${portal_open} && output_ref+=(-Open)
      ;;
  esac
  return 0
}

printf '=== Native Bash pipeline start: %s (max phase retries: %s) ===\n' \
  "$(IFS=' -> '; echo "${selected[*]}")" "${max_phase_retries}"
for phase in "${selected[@]}"; do
  script="$(phase_script "${phase}")"
  [[ -f "${script}" ]] || {
    printf 'ERROR: native phase script not found: %s\n' "${script}" >&2
    exit 2
  }
  build_phase_args "${phase}" phase_args
  attempt=0
  while true; do
    set +e
    bash "${script}" "${phase_args[@]}"
    exit_code=$?
    set -e
    ((exit_code == 0)) && break
    ((attempt >= max_phase_retries)) && {
      printf '=== Pipeline aborted at phase %s (exit=%s) ===\n' "${phase}" "${exit_code}"
      exit "${exit_code}"
    }
    attempt=$((attempt + 1))
    printf 'Phase %s failed; retry %d/%d.\n' \
      "${phase}" "${attempt}" "${max_phase_retries}" >&2
  done
done
printf '=== Native Bash pipeline completed successfully (%s) ===\n' "$(IFS=' -> '; echo "${selected[*]}")"
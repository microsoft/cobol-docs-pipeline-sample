#!/usr/bin/env bash
set -euo pipefail

readonly native_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${native_dir}/native-common.sh"
readonly repo_root="$(native_repo_root)"

if (($# < 1)); then printf 'Usage: %s <mode> [options]\n' "$0" >&2; exit 2; fi
mode="$1"; shift
files=(); paths=(); manifest=""; source_root=""; languages="en"; agent=""
copilot_cli="copilot"; copilot_subcommand=""; agent_switch="--agent"; prompt_switch="--prompt"
additional_args=(); throttle=12; results_xml="temp/${mode}_results.xml"; dry_run=false
ensure_bundles=false; ensure_facts=true; force=false; max_retries=2; timeout_sec=1800
state_path=""; plan_path=""

while (($#)); do
  option="$(native_normalize_option "$1")"; shift
  case "${option}" in
    files) while (($#)) && [[ "$1" != -* ]]; do files+=("$1"); shift; done ;;
    paths) while (($#)) && [[ "$1" != -* ]]; do paths+=("$1"); shift; done ;;
    manifest) manifest="$1"; shift ;;
    sourceroot) source_root="$1"; shift ;;
    languages) languages="$1"; shift ;;
    agent) agent="$1"; shift ;;
    copilotcli) copilot_cli="$1"; shift ;;
    copilotsubcommand) copilot_subcommand="$1"; shift ;;
    agentswitch) agent_switch="$1"; shift ;;
    promptswitch) prompt_switch="$1"; shift ;;
    additionalcopilotargs) while (($#)) && [[ "$1" != -* ]]; do additional_args+=("$1"); shift; done ;;
    throttle|docsthrottle|finalizerthrottle|sectionthrottle|diagramsthrottle) throttle="$1"; shift ;;
    resultsxml) results_xml="$1"; shift ;;
    dryrun) dry_run=true ;;
    ensurebundles) ensure_bundles=true ;;
    ensurefactsslices) ensure_facts=true ;;
    force|restart) force=true ;;
    maxretries) max_retries="$1"; shift ;;
    pertasktimeoutsec) timeout_sec="$1"; shift ;;
    statepath) state_path="$1"; shift ;;
    planpath) plan_path="$1"; shift ;;
    resume|noninteractive|tasklogging|allowlowerthrottle|trackusage|status) ;;
    logsdir|tasklogpath|oteldir|usagelogpath|prompttemplate) shift ;;
    tasklogpreviewcount|premiummultiplier) shift ;;
    excludeextensions) while (($#)) && [[ "$1" != -* ]]; do shift; done ;;
    *) printf 'ERROR: unknown option -%s for dispatcher %s.\n' "${option}" "${mode}" >&2; exit 2 ;;
  esac
done

case "${mode}" in
  section) agent="${agent:-section-doc-writer}"; bundle_kind="_bundles"; bundle_glob="*.bundle.json" ;;
  diagrams) agent="${agent:-diagram-renderer}"; bundle_kind=""; bundle_glob="_diagrams.bundle.json" ;;
  finalize) agent="${agent:-section-doc-finalizer}"; bundle_kind=""; bundle_glob="_finalize.bundle.json" ;;
  req-section) agent="${agent:-requirements-writer}"; bundle_kind="_req-bundles"; bundle_glob="*.bundle.json" ;;
  req-finalize) agent="${agent:-requirements-writer}"; bundle_kind="_req-bundles"; bundle_glob="_finalize.bundle.json" ;;
  fa-section) agent="${agent:-functional-analysis-writer}"; bundle_kind="_fa-bundles"; bundle_glob="*.bundle.json" ;;
  fa-finalize) agent="${agent:-functional-analysis-writer}"; bundle_kind="_fa-bundles"; bundle_glob="_finalize.bundle.json" ;;
  ta-finalize) agent="${agent:-technical-analysis-writer}"; bundle_kind="_ta-bundles"; bundle_glob="_finalize.bundle.json" ;;
  group-doc-finalize) agent="${agent:-group-doc-finalizer}"; group_kind="_doc-bundles"; bundle_glob="_finalize.bundle.json" ;;
  req-group-section) agent="${agent:-requirements-group-writer}"; group_kind="_req-group-bundles"; bundle_glob="*.bundle.json" ;;
  req-group-finalize) agent="${agent:-requirements-group-writer}"; group_kind="_req-group-bundles"; bundle_glob="_finalize.bundle.json" ;;
  fa-group-section) agent="${agent:-functional-analysis-group-writer}"; group_kind="_fa-group-bundles"; bundle_glob="*.bundle.json" ;;
  fa-group-finalize) agent="${agent:-functional-analysis-group-writer}"; group_kind="_fa-group-bundles"; bundle_glob="_finalize.bundle.json" ;;
  ta-group-finalize) agent="${agent:-technical-analysis-writer}"; group_kind="_ta-group-bundles"; bundle_glob="_finalize.bundle.json" ;;
  *) printf 'ERROR: unknown dispatcher mode: %s\n' "${mode}" >&2; exit 2 ;;
esac

results_xml="$(native_abspath "${repo_root}" "${results_xml}")"
state_path="$(native_abspath "${repo_root}" "${state_path:-logs/${mode}_state.jsonl}")"
plan_path="$(native_abspath "${repo_root}" "${plan_path:-logs/${mode}_plan.json}")"
mkdir -p -- "$(dirname -- "${results_xml}")" "$(dirname -- "${state_path}")"

bundles=()
if [[ -n "${group_kind:-}" ]]; then
  [[ -n "${manifest}" ]] || manifest="config/grouping.yaml"
  manifest="$(native_abspath "${repo_root}" "${manifest}")"
  mapfile -t group_ids < <("$(native_python)" "${repo_root}/scripts/lib/read_groups.py" "${manifest}" | \
    "$(native_python)" -c 'import json,sys; sys.stdout.write("\n".join(str(x["id"]).strip() for x in json.load(sys.stdin) if str(x.get("id", "")).strip()))')
  if ((${#group_ids[@]} == 0)); then
    mkdir -p -- "$(dirname -- "${results_xml}")"
    printf '<?xml version="1.0" encoding="utf-8"?>\n<results />\n' >"${results_xml}"
    printf '%s: no groups declared; no-op.\n' "${mode}"
    exit 0
  fi
  for group_id in "${group_ids[@]}"; do
    while IFS= read -r match; do [[ -n "${match}" ]] && bundles+=("${match}"); done \
      < <(compgen -G "${repo_root}/docs/_shared/_groups/${group_id}/${group_kind}/${bundle_glob}" || true)
  done
else
  inputs=(); native_collect_inputs "${repo_root}" "${manifest}" files paths inputs
  if [[ "${mode}" == section && "${ensure_facts}" == true ]]; then
    "${repo_root}/.github/skills/facts-slicing/scripts/slice_facts_batch.sh" \
      -Files "${inputs[@]}" ${source_root:+-SourceRoot "${source_root}"} -Throttle "${throttle}" \
      -ResultsXml "$(dirname -- "${results_xml}")/slice_results.xml"
  fi
  if [[ "${mode}" == section && "${ensure_bundles}" == true ]]; then
    stage_args=(-Files "${inputs[@]}" -Languages "${languages}" -Throttle "${throttle}"
      -ResultsXml "$(dirname -- "${results_xml}")/stage_results.xml")
    [[ -n "${source_root}" ]] && stage_args+=(-SourceRoot "${source_root}")
    "${repo_root}/.github/skills/section-doc-writer/scripts/write_sections_batch.sh" "${stage_args[@]}"
  fi
  for input in "${inputs[@]}"; do
    basename="$(basename -- "${input}")"
    if [[ -n "${bundle_kind}" ]]; then
      pattern="${repo_root}/docs/_shared/${basename}/${bundle_kind}/${bundle_glob}"
    else
      pattern="${repo_root}/docs/_shared/${basename}/${bundle_glob}"
    fi
    while IFS= read -r match; do
      [[ -n "${match}" ]] || continue
      [[ "${bundle_glob}" == "*.bundle.json" && "$(basename -- "${match}")" == "_finalize.bundle.json" ]] && continue
      bundles+=("${match}")
    done < <(compgen -G "${pattern}" || true)
  done
fi
mapfile -t bundles < <(printf '%s\n' "${bundles[@]}" | sed '/^$/d' | LC_ALL=C sort -u)
if ((${#bundles[@]} == 0)); then
  printf 'ERROR: no %s bundles found. Run the corresponding staging script first.\n' "${mode}" >&2
  exit 4
fi

"$(native_python)" - "${plan_path}" "${mode}" "${agent}" "${bundles[@]}" <<'PY'
import json
import pathlib
import sys
path, mode, agent, *bundles = sys.argv[1:]
pathlib.Path(path).write_text(json.dumps({"mode": mode, "agent": agent, "bundles": bundles}, indent=2), encoding="utf-8")
PY

run_copilot_bundle() {
  local bundle="$1" bundle_view prompt attempt exit_code output
  bundle_view="${bundle%.json}.md"
  [[ -f "${bundle_view}" ]] || bundle_view="${bundle}"
  prompt="Read ${bundle_view} as the authoritative prepared input and write every output requested by its metadata. Follow the referenced template and active profile exactly."
  if ${dry_run}; then
    printf 'DRY-RUN: %q %q %q %q %q\n' "${copilot_cli}" "${copilot_subcommand}" "${agent_switch}" "${agent}" "${prompt}"
    return 0
  fi
  command -v "${copilot_cli}" >/dev/null 2>&1 || { printf 'ERROR: Copilot CLI not found: %s\n' "${copilot_cli}" >&2; return 127; }
  args=()
  [[ -n "${copilot_subcommand}" ]] && args+=("${copilot_subcommand}")
  args+=("${agent_switch}" "${agent}" "${prompt_switch}" "${prompt}" "${additional_args[@]}")
  attempt=0
  while true; do
    set +e
    if command -v timeout >/dev/null 2>&1; then
      timeout "${timeout_sec}" "${copilot_cli}" "${args[@]}"
    else
      "${copilot_cli}" "${args[@]}"
    fi
    exit_code=$?
    set -e
    ((exit_code == 0)) && break
    ((attempt >= max_retries)) && return "${exit_code}"
    attempt=$((attempt + 1))
    printf 'Retrying %s (%d/%d).\n' "${bundle}" "${attempt}" "${max_retries}" >&2
  done
  "$(native_python)" - "${state_path}" "${bundle}" <<'PY'
import datetime
import json
import pathlib
import sys
with pathlib.Path(sys.argv[1]).open("a", encoding="utf-8") as stream:
    stream.write(json.dumps({"bundle_path": sys.argv[2], "status": "ok", "completed_utc": datetime.datetime.now(datetime.timezone.utc).isoformat()}) + "\n")
PY
}
export dry_run copilot_cli copilot_subcommand agent_switch agent prompt_switch timeout_sec max_retries state_path
export -a additional_args 2>/dev/null || true
export -f run_copilot_bundle
printf 'Dispatching %d %s bundle(s) with agent=%s throttle=%s dry_run=%s\n' \
  "${#bundles[@]}" "${mode}" "${agent}" "${throttle}" "${dry_run}"
native_run_python_batch "${throttle}" "${results_xml}" run_copilot_bundle bundles
#!/usr/bin/env bash
set -euo pipefail

readonly native_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${native_dir}/native-common.sh"
readonly repo_root="$(native_repo_root)"
readonly python_bin="$(native_python)"

if (($# < 1)); then
  printf 'Usage: %s <mode> [options]\n' "$0" >&2
  exit 2
fi
mode="$1"; shift
files=(); paths=(); manifest=""; source_root=""; output_dir=""; bundles_dir=""
languages="en"; profile_name=""; bundle_path=""; throttle="$(nproc 2>/dev/null || echo 1)"
results_xml="temp/${mode}_results.xml"; prune=false; force=false

while (($#)); do
  option="$(native_normalize_option "$1")"; shift
  case "${option}" in
    files) while (($#)) && [[ "$1" != -* ]]; do files+=("$1"); shift; done ;;
    paths) while (($#)) && [[ "$1" != -* ]]; do paths+=("$1"); shift; done ;;
    manifest) manifest="$1"; shift ;;
    sourceroot) source_root="$1"; shift ;;
    outputdir) output_dir="$1"; shift ;;
    bundlesdir) bundles_dir="$1"; shift ;;
    languages) languages="$1"; shift ;;
    profilename|profile) profile_name="$1"; shift ;;
    bundlepath) bundle_path="$1"; shift ;;
    throttle) throttle="$1"; shift ;;
    resultsxml) results_xml="$1"; shift ;;
    prune) prune=true ;;
    force) force=true ;;
    excludeextensions) while (($#)) && [[ "$1" != -* ]]; do shift; done ;;
    *) printf 'ERROR: unknown option -%s for %s.\n' "${option}" "${mode}" >&2; exit 2 ;;
  esac
done
results_xml="$(native_abspath "${repo_root}" "${results_xml}")"

case "${mode}" in
  req_group_stage|fa_group_stage|group_doc_stage|ta_group_stage)
    [[ -n "${manifest}" ]] || manifest="config/grouping.yaml"
    manifest="$(native_abspath "${repo_root}" "${manifest}")"
    mapfile -t inputs < <("${python_bin}" "${repo_root}/scripts/lib/read_groups.py" "${manifest}" | \
      "${python_bin}" -c 'import json,sys; sys.stdout.write("\n".join(str(x["id"]).strip() for x in json.load(sys.stdin) if str(x.get("id", "")).strip()))')
    if ((${#inputs[@]} == 0)); then
      mkdir -p -- "$(dirname -- "${results_xml}")"
      printf '<?xml version="1.0" encoding="utf-8"?>\n<results />\n' >"${results_xml}"
      printf '%s: no groups declared; no-op.\n' "${mode}"
      exit 0
    fi
    ;;
  *)
    inputs=()
    native_collect_inputs "${repo_root}" "${manifest}" files paths inputs
    ;;
esac

case "${mode}" in
  slice_facts) py_script="${repo_root}/.github/skills/facts-slicing/scripts/slice-facts.py" ;;
  write_sections) py_script="${repo_root}/.github/skills/section-doc-writer/scripts/stage-bundles.py" ;;
  finalize_stage) py_script="${repo_root}/.github/skills/section-doc-finalizer/scripts/assemble-inputs.py" ;;
  assemble_complete) py_script="${repo_root}/.github/skills/section-doc-finalizer/scripts/assemble-complete.py" ;;
  diagrams_stage) py_script="${repo_root}/.github/skills/diagram-renderer/scripts/assemble-inputs.py" ;;
  req_stage) py_script="${repo_root}/.github/skills/requirements-writer/scripts/stage-bundles.py" ;;
  req_finalize_stage) py_script="${repo_root}/.github/skills/requirements-finalizer/scripts/assemble-inputs.py" ;;
  fa_stage) py_script="${repo_root}/.github/skills/functional-analysis-writer/scripts/stage-bundles.py" ;;
  fa_finalize_stage) py_script="${repo_root}/.github/skills/functional-analysis-finalizer/scripts/assemble-inputs.py" ;;
  ta_stage) py_script="${repo_root}/.github/skills/technical-analysis-writer/scripts/assemble-inputs.py" ;;
  req_group_stage) py_script="${repo_root}/.github/skills/requirements-group-writer/scripts/assemble-inputs.py" ;;
  fa_group_stage) py_script="${repo_root}/.github/skills/functional-analysis-group-writer/scripts/assemble-inputs.py" ;;
  group_doc_stage) py_script="${repo_root}/.github/skills/group-doc-finalizer/scripts/assemble-inputs.py" ;;
  ta_group_stage) py_script="${repo_root}/.github/skills/technical-analysis-writer/scripts/assemble-group-inputs.py" ;;
  *) printf 'ERROR: unknown native skill mode: %s\n' "${mode}" >&2; exit 2 ;;
esac
[[ -f "${py_script}" ]] || { printf 'ERROR: Python implementation not found: %s\n' "${py_script}" >&2; exit 2; }

run_skill() {
  local input="$1" basename out
  basename="$(basename -- "${input}")"
  args=("${py_script}")
  case "${mode}" in
    slice_facts)
      args+=(--source "${input}")
      [[ -n "${source_root}" ]] && args+=(--source-root "${source_root}")
      [[ -n "${output_dir}" ]] && args+=(--output-dir "${output_dir}")
      ${prune} && args+=(--prune)
      ;;
    write_sections|req_stage|fa_stage)
      args+=(--source "${input}" --languages "${languages}")
      [[ -n "${source_root}" ]] && args+=(--source-root "${source_root}")
      [[ -n "${bundles_dir}" ]] && args+=(--bundles-dir "${bundles_dir}")
      [[ "${mode}" != write_sections && -n "${profile_name}" ]] && args+=(--profile-name "${profile_name}")
      ${prune} && args+=(--prune)
      ${force} && args+=(--force)
      ;;
    finalize_stage)
      out="${bundle_path:-docs/_shared/${basename}/_finalize.bundle.json}"
      args+=(--source "${input}" --languages "${languages}" --out "${out}")
      [[ -n "${source_root}" ]] && args+=(--source-root "${source_root}")
      [[ -n "${profile_name}" ]] && args+=(--profile "${profile_name}")
      ;;
    diagrams_stage)
      out="${bundle_path:-docs/_shared/${basename}/_diagrams.bundle.json}"
      args+=(--source "${input}" --out "${out}")
      [[ -n "${source_root}" ]] && args+=(--source-root "${source_root}")
      [[ -n "${profile_name}" ]] && args+=(--profile "${profile_name}")
      ;;
    req_finalize_stage|fa_finalize_stage|ta_stage)
      args+=(--source "${input}" --languages "${languages}")
      [[ -n "${source_root}" ]] && args+=(--source-root "${source_root}")
      [[ -n "${profile_name}" ]] && args+=(--profile-name "${profile_name}")
      ;;
    assemble_complete)
      out="${repo_root}/docs/_shared/${basename}/_finalize.bundle.json"
      args+=(--bundle "${out}" --languages "${languages}")
      ${force} && args+=(--force)
      ;;
    req_group_stage|fa_group_stage|group_doc_stage|ta_group_stage)
      case "${mode}" in
        req_group_stage) out="docs/_shared/_groups/${input}/_req-group-bundles/_finalize.bundle.json" ;;
        fa_group_stage) out="docs/_shared/_groups/${input}/_fa-group-bundles/_finalize.bundle.json" ;;
        group_doc_stage) out="docs/_shared/_groups/${input}/_doc-bundles/_finalize.bundle.json" ;;
        ta_group_stage) out="docs/_shared/_groups/${input}/_ta-group-bundles/_finalize.bundle.json" ;;
      esac
      args+=(--group-id "${input}" --languages "${languages}" --manifest "${manifest}" --out "${out}")
      [[ -n "${profile_name}" ]] && args+=(--profile-name "${profile_name}")
      ;;
  esac
  (cd -- "${repo_root}" && "${python_bin}" "${args[@]}")
}
export repo_root python_bin py_script mode source_root output_dir bundles_dir languages profile_name bundle_path manifest prune force
export -f run_skill
printf 'Running native %s for %d item(s) with throttle=%s\n' "${mode}" "${#inputs[@]}" "${throttle}"
native_run_python_batch "${throttle}" "${results_xml}" run_skill inputs
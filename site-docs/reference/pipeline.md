# Phases, artifacts, agents, and skills

## Executable phases

| Phase | Engine | Scope | Primary result |
|-------|--------|-------|----------------|
| A | Python | per file | `chunk-manifest.json` |
| B | Python | per file + workspace | `facts.json`, incoming xrefs |
| C | Python | per file | chunk text and fact slices |
| D | Copilot + QA | per section | section Markdown and diagrams |
| E | Copilot + Python | per file | `index.md`, `complete.md`, DOCX |
| F | Copilot + Python | per requirements section | `requirements.md`, DOCX |
| G | Copilot + Python | per FA section | `functional-analysis.md`, DOCX |
| H | Copilot | per file | overview Mermaid diagrams |
| I | Copilot + Python | per group | group index and complete docs |
| J | Copilot + Python | per group | group requirements |
| K | Copilot + Python | per group | group functional analysis |
| L | Copilot + Pandoc | per file | technical analysis and DOCX |
| M | Copilot + Pandoc | per group | group technical analysis and DOCX |
| N | Python | workspace | generated-documentation web/offline portal |

## Phase prerequisites and checkpoints

| Phase | Requires | Check before continuing |
|-------|----------|-------------------------|
| A | Source file and source configuration | Platform, kind, encoding, chunks, and empty `errors[]` |
| B | Phase-A manifest | Program ID, facts collections, source hashes, incoming xrefs after fan-in |
| C | Manifest and facts | Chunk index, raw text, and chunk-scoped fact slices |
| D | A-C artifacts | Bundles, section Markdown, Mermaid, and QA findings |
| E | Complete phase-D section set | Per-file index, complete doc, call tables, and optional DOCX |
| F-G | Per-file facts and documentation | Requirements/FA drafts, final document, and optional DOCX |
| H | File-level facts bundle | One overview diagram per non-empty supported collection |
| I-K | Declared groups and member outputs | Group bundles and consolidated documents |
| L-M | Complete per-file or group narrative | Technical-analysis Markdown and optional DOCX |
| N | Generated Markdown outputs | Web and offline execution portals |

The prerequisites above describe required artifacts. Only YAML output selection
automatically adds producing phases; explicit `-Phases` or `-From`/`-To` selections
must provide them or reuse existing artifacts. In `config/pipeline.yaml`,
`output.generate` selects file and group deliverables together; technical analysis
does not require requirements or functional analysis. See the
[selection contract](../guides/configuration.md#select-generated-deliverables)
for exact phase sets and final `Run*`/`-Skip` filtering.

Run [artifact inspection](../guides/artifacts.md) after A-C and before submitting model-backed
work. Missing upstream artifacts produce exit code 4 rather than partial downstream output.

## Artifact tree

```text
docs/
|-- _shared/<file>/
|   |-- chunk-manifest.json
|   |-- facts.json
|   |-- chunks/
|   |-- facts-slices/
|   |-- _bundles/
|   `-- diagrams/
|-- _reviews/
|-- en/<file>/
|-- it/<file>/
`-- _portal/
```

`docs/_shared` is machine-oriented. `docs/<lang>` contains human deliverables. `docs/_portal` is
an execution result and is unrelated to the tracked `site-docs` user guide.

### Representative per-file output

```text
docs/
|-- _shared/ORDR100.CBL/
|   |-- chunk-manifest.json
|   |-- facts.json
|   |-- chunks/index.json
|   |-- facts-slices/
|   |-- _bundles/
|   `-- diagrams/
|-- _reviews/section-doc/
|-- en/ORDR100.CBL/
|   |-- sections/
|   |-- index.md
|   |-- complete.md
|   |-- requirements.md
|   |-- functional-analysis.md
|   `-- technical-analysis.md
`-- it/ORDR100.CBL/
```

Markdown is the canonical human deliverable. DOCX siblings are conversion products and may be
omitted with skip switches. Language-neutral extraction, bundles, reviews, and diagrams are not
duplicated under each language.

## Core agents

| Agent | Responsibility |
|-------|----------------|
| `section-agent` | Runs the writer/reviewer loop for one chunk |
| `section-doc-writer` | Authors one section from one prepared bundle |
| `section-doc-finalizer` | Authors the per-file landing page |
| `requirements-writer` | Authors and finalizes technical requirements |
| `functional-analysis-writer` | Authors and finalizes functional analysis |
| `diagram-renderer` | Authors file-level Mermaid overviews |
| `group-doc-finalizer` | Consolidates member documentation by group |
| `technical-analysis-writer` | Authors per-file and per-group technical analysis |

## Core skills

| Skill | Pipeline use |
|-------|--------------|
| `cobol-chunking` | Deterministic phase-A outline |
| `cobol-facts-extraction` | Deterministic phase-B knowledge graph |
| `chunk-text-extraction` | Raw source slices |
| `facts-slicing` | Chunk-scoped facts |
| `section-doc-writer` | Section authoring contract |
| `qa-reviewer` | Mechanical documentation checks |
| `section-doc-finalizer` | Per-file index and complete docs |
| `requirements-writer` | Requirements section authoring |
| `functional-analysis-writer` | Functional-analysis authoring |
| `diagram-renderer` | Overview diagram authoring |
| `technical-analysis-writer` | Technical-analysis finalization |

## Diagram outputs

Phase H emits a file only when the corresponding facts collection is non-empty.

| Diagram | Evidence |
|---------|----------|
| `call-graph.mmd` | Internal `PERFORM` relationships |
| `inter-program-call-graph.mmd` | Outbound calls and workspace `incoming_xref` |
| `control-flow.mmd` | `GO TO` and perform targets |
| `jcl-steps.mmd` | Mainframe JCL steps |
| `cl-command-flow.mmd` | IBM i CL command sequence and targets |
| `cics-calls.mmd` | CICS command interactions |
| `cursor-lifecycle.mmd` | SQL cursor declarations and operations |
| `er-fragment.mmd` | Level-01 data records and fields |

## Exit and failure behavior

Deterministic scripts use non-zero exit codes for invalid usage, schema failures, missing
prerequisites, and stale inputs. Phase wrappers preserve those failures, write phase events, and
apply the configured retry budget. The orchestrator stops when a phase remains unsuccessful after
its retries.

`-MaxPhaseRetries 3` means one initial attempt followed by at most three retries. Phase-level
retries do not discard dispatcher state, so already completed authored tasks can resume when the
dispatcher supports it.

# sample1_clean

## Overview
sample1_clean is a fully original COBOL/JCL batch sample for omni-channel order settlement.
It models a realistic production flow with multi-step controls, reference data, and rejection handling.

Pipeline steps:
1. ORDR100 - syntactic/domain validation and first-level reject stream
2. ORDR150 - customer/product enrichment and master-data checks
3. ORDR200 - pricing (discount, tax, fx) and policy exceptions
4. ORDR300 - detail statement generation, channel summaries, control records
5. ORDR400 - reconciliation of actual controls vs expected controls with tolerance and audit verdict
6. ORDR450 - incident routing (severity-based) and checkpoint emission for restart governance
7. ORDR460 - recovery orchestration: chooses restart entry stage and emits ops escalation decisions
8. ORDR470 - trend anomaly detection using historical controls and configurable thresholds
9. ORDR480 - remediation action recommendation engine with policy-based prioritization
10. ORDR490 - executive run report consolidating controls, risks, restart and actions
11. ORDR500 - closed-loop action execution simulation with status tracking
12. ORDR510 - SLA breach detection and escalation for pending actions
13. ORDR520 - governance KPI rollup for operational dashboard consumption
14. ORDR530 - KPI trend drift detection against historical KPI baseline
15. ORDR540 - automated run disposition (GREEN/AMBER/RED)
16. ORDR550 - publish-ready governance narrative output
17. ORDR560 - control-room handoff bundle manifest
18. ORDR570 - deterministic runbook action matrix
19. ORDR580 - incident-bridge timeline feed
20. ORDR590 - shift-close certification package
21. ORDR600 - audit-evidence export index

## Folder Layout
- COBOL/: program sources
- COBOL/COPY/: shared layouts (input, working, output, masters, references)
- JCL/: job/proc plus sample data files

## Data Dependencies
- Order input: JCL/ORDER_INP.DAT
- Customer master: JCL/CUSTOMER_MST.DAT
- Product master: JCL/PRODUCT_MST.DAT
- Tax reference: JCL/TAX_REF.DAT
- FX reference: JCL/FX_RATE.DAT
- Expected controls: JCL/EXPECTED_CTL.DAT
- Runtime policy: JCL/RUN_CFG.DAT
- Historical controls baseline: JCL/HIST_CTL.DAT
- Remediation policy rules: JCL/REMED_RULE.DAT
- Historical KPI baseline: JCL/KPI_HIST.DAT

## Processing Characteristics
- Record sizes:
	- Input: 160 bytes
	- Working: 240 bytes
	- Statement output: 240 bytes
- Rejection streams:
	- Stage 100 rejects invalid input payloads
	- Stage 150 rejects unknown/inactive customer or product
	- Stage 200 rejects missing tax or fx rules
- Business rules:
	- Discount by customer segment and order volume
	- Optional promo uplift (capped)
	- Tax by channel + region + tax-group
	- Currency normalization to EUR
- Reconciliation:
	- Global totals in output summary lines
	- Channel-level totals and control output dataset
	- Independent stage-level control reconciliation with pass/fail evidence output
	- Count controls are exact; amount controls use tolerance policy

## Operational Control Pattern
- Stage 300 emits structured controls (`ORDRCTL1`) for key metrics:
	- orders processed
	- statement rows
	- total EUR (global + channel)
- Stage 400 compares actual controls with expected controls and writes audit evidence.
- Suggested operation mode:
	- Keep expected controls in a governed reference dataset
	- Archive each run audit output for compliance reviews
	- Alert when Stage 400 return code is non-zero

## Run Modes And Policies
- Runtime policy file drives reconciliation strictness and tolerance.
- Example mode values:
	- EOD: standard daily tolerance and warning-level mismatches
	- EOM: tighter tolerance and strict fail mode for month-end closure
- Stage 400 reads policy and sets return code based on strictness.

## Incident And Restart Governance
- Stage 450 scans reject streams and audit failures to emit incident records with:
	- severity (1 or 2)
	- route code (for operations ownership)
	- source stage and message payload
- Stage 450 also writes checkpoint records per stage (`CKPSTAT1`) with status and counters.
- Checkpoint outputs can be used by operations to choose restart points on rerun.

## Recovery Orchestration
- Stage 460 reads checkpoints and incidents and outputs:
	- restart plan (`RSTRPLN1`) with selected restart stage
	- operations alert stream for escalation handling
- Escalation is threshold-driven using runtime policy:
	- sev2 threshold for operations escalation
	- sev1 threshold for control-room escalation
	- strict mode to enforce immediate halt workflow

## Predictive Risk Layer
- Stage 470 compares current structured controls with historical averages per metric/channel.
- Anomaly detection supports both count and amount metrics with percentage delta threshold.
- Risk alert output includes:
	- current vs average values
	- computed delta percentage
	- severity and route (RUNCTRL or DATAOPS)
- Threshold is controlled by runtime policy (`RUN-CFG-ANOMALY-PCT`).

## Remediation Recommendation Layer
- Stage 480 merges three inputs:
	- risk alerts from Stage 470
	- restart decision from Stage 460
	- remediation policy rules (`REMRULE1`)
- Output is a ranked action stream with:
	- priority
	- auto/manual execution flag
	- target restart stage
	- reason composed from anomaly + policy context
- Typical generated actions:
	- execute restart
	- refresh reference data
	- quarantine batch
	- manual control-room review

## Executive Run Summary Layer
- Stage 490 consolidates key run indicators into a single report stream.
- Inputs:
	- structured controls (`ORDRCTL1`)
	- risk alerts (`RISKALR1`)
	- restart plan (`RSTRPLN1`)
	- recommended actions (`RECACT01`)
- Output:
	- executive report records (`EXECRPT1`) with:
		- run snapshot counts
		- financial aggregate totals
		- restart and severity posture
		- high-priority action density for control-room triage

## Closed-Loop Action Execution Layer
- Stage 500 consumes the recommended action stream and runtime policy.
- Execution model:
	- automatic + high-priority actions are marked as executed
	- lower-priority auto actions are scheduled
	- manual actions are routed to approval unless strict mode escalates scheduling
- Output status stream (`ACTSTAT1`) includes:
	- execution status (`EXECUTED`, `SCHEDULED`, `PENDING-APR`)
	- owning operations queue (`RUNCTRL`, `DATAOPS`, `OPS`)
	- synthetic tracking ticket id
	- closure reason combining policy decision and original recommendation context

## SLA Escalation Layer
- Stage 510 evaluates action statuses against policy thresholds from runtime config.
- Detection patterns:
	- high-priority pending approvals
	- strict-mode pending violations
	- run-level pending volume beyond configured threshold
- Output SLA alert stream (`SLALRT1`) includes:
	- item-level and summary-level breach lines
	- severity and breach code
	- owning queue, ticket, and target stage
	- escalation message for control-room follow-up

## Governance KPI Layer
- Stage 520 consolidates operational outcomes into dashboard-ready KPI records.
- Inputs:
	- executive run report (`EXECRPT1`)
	- action execution statuses (`ACTSTAT1`)
	- SLA alerts (`SLALRT1`)
- Output KPI stream (`KPIRPT1`) provides:
	- execution completion rate
	- pending backlog indicators
	- SLA alert density
	- total settled financial volume
- Designed as a final reporting layer for control-room daily governance packs.

## KPI Trend Drift Layer
- Stage 530 compares current KPI values with historical baselines.
- Drift logic uses runtime policy anomaly threshold (`RUN-CFG-ANOMALY-PCT`).
- Output trend alert stream (`KPITRD1`) includes:
	- current vs baseline KPI values
	- computed delta percentage
	- severity classification by drift magnitude
	- governance message for follow-up analysis

## Automated Disposition Layer
- Stage 540 consolidates KPI drift, SLA posture, and restart pressure into final run status.
- Inputs:
	- KPI trend alerts (`KPITRD1`)
	- SLA alerts (`SLALRT1`)
	- restart plan (`RSTRPLN1`)
- Output disposition stream (`RUNDSP1`) provides:
	- status (`GREEN`, `AMBER`, `RED`)
	- aggregated red/amber signal counters
	- critical vs warning split by KPI/SLA source
	- restart stage context and governance message

## Governance Narrative Publishing Layer
- Stage 550 generates leadership-ready narrative records for each batch run.
- Inputs:
	- run disposition (`RUNDSP1`)
	- KPI rollup (`KPIRPT1`)
	- SLA alerts (`SLALRT1`)
	- restart plan (`RSTRPLN1`)
- Output narrative stream (`GOVRPT1`) includes:
	- executive header with overall status
	- risk posture summary
	- operational execution posture
	- restart/runbook context for publication workflows

## Control-Room Handoff Bundle Layer
- Stage 560 builds a single manifest that references all governance artifacts from Stage 400 onward.
- Bundle manifest output (`BNDLMF1`) includes per-artifact:
	- stage owner
	- readiness status (`READY`, `MISSING`, `EMPTY`)
	- processing priority
	- short operational summary
- Intended as the operational handoff index for shift change and incident bridge calls.

## Runbook Action Matrix Layer
- Stage 570 transforms the handoff bundle into execution-ready control-room actions.
- Inputs:
	- handoff manifest (`BNDLMF1`)
	- final run disposition (`RUNDSP1`)
- Output matrix (`RUNMAT1`) provides deterministic fields for:
	- owning team (`RUNCTRL`, `DATAOPS`, `OPS`)
	- prescribed action (`REGENERATE-ARTIFACT`, `VERIFY-ZERO-STATE`, `PUBLISH-AND-ACK`)
	- urgency (`RED`, `AMBER`, `GREEN`) derived from disposition and artifact status
	- operational note carrying artifact status and summary context

## Incident-Bridge Timeline Layer
- Stage 580 composes a single chronological bridge feed across execution sources.
- Inputs:
	- runbook matrix (`RUNMAT1`)
	- action statuses (`ACTSTAT1`)
	- SLA alerts (`SLALRT1`)
	- governance narrative lines (`GOVRPT1`)
- Output timeline (`TIMELN1`) emits deterministic sequence records with:
	- source stream and owner
	- stage, urgency, and status
	- ticket/event anchors
	- normalized timeline message for operator handoff

## Shift-Close Certification Layer
- Stage 590 assembles a deterministic sign-off package for end-of-shift governance control.
- Inputs:
	- timeline feed (`TIMELN1`)
	- runbook matrix (`RUNMAT1`)
	- governance narrative (`GOVRPT1`)
- Output certification (`SHFCLS1`) includes:
	- event and urgency totals (including RED/AMBER counts)
	- total vs pending runbook actions
	- overall status (`STABLE`, `DEGRADED`, `CRITICAL`)
	- certification flag (`Y`/`N`) and summary message for control-room signoff

## Audit-Evidence Export Index Layer
- Stage 600 produces a publish index for compliance export and long-term retention routing.
- Inputs:
	- handoff bundle (`BNDLMF1`)
	- runbook matrix (`RUNMAT1`)
	- timeline feed (`TIMELN1`)
	- shift-close certification (`SHFCLS1`)
	- governance narrative (`GOVRPT1`)
- Output index (`AUDIDX1`) provides deterministic metadata per artifact:
	- export class (`EXPORT`, `REVIEW`, `REBUILD`)
	- retention days (365 / 1095 / 2555)
	- handoff queue (`AUDIT`, `RUNCTRL`, `OPS`)
	- package id and summary context for archive and evidence transfer

## Notes
- This sample is for demo/training and architecture workshops.
- Dataset names in JCL are placeholders and should be mapped to your environment.

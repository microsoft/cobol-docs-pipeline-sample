       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR540.
      *---------------------------------------------------------------*
      * Automated governance disposition.
      * Inputs:
      * - KPI trend alerts (ORDR530)
      * - SLA alerts (ORDR510)
      * - restart plan (ORDR460)
      * Output:
      * - final run disposition (GREEN/AMBER/RED)
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-KTR ASSIGN TO ORDRKTR
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-SLA ASSIGN TO ORDRSLA
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-PLN ASSIGN TO ORDRPLN
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-DSP ASSIGN TO ORDRDSP
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-KTR
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY KPITRD1.

       FD  IN-SLA
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY SLALRT1.

       FD  IN-PLN
           RECORD CONTAINS 160 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RSTRPLN1.

       FD  OUT-DSP
           RECORD CONTAINS 200 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RUNDSP1.

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-END-KTR                 PIC X VALUE 'N'.
              88 END-OF-KTR              VALUE 'Y'.
           05 WS-END-SLA                 PIC X VALUE 'N'.
              88 END-OF-SLA              VALUE 'Y'.

       01  WS-RUN.
           05 WS-RUN-ID                  PIC X(8) VALUE 'ORDR540 '.
           05 WS-RESTART-STAGE           PIC X(8) VALUE 'NONE    '.

       01  WS-SIGNALS.
           05 WS-KPI-CRIT                PIC 9(5) VALUE ZERO.
           05 WS-SLA-CRIT                PIC 9(5) VALUE ZERO.
           05 WS-KPI-WARN                PIC 9(5) VALUE ZERO.
           05 WS-SLA-WARN                PIC 9(5) VALUE ZERO.
           05 WS-RED-SIGNALS             PIC 9(5) VALUE ZERO.
           05 WS-AMBER-SIGNALS           PIC 9(5) VALUE ZERO.

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR540 RUNNING ***'
           OPEN INPUT IN-KTR IN-SLA IN-PLN
                OUTPUT OUT-DSP

           PERFORM LOAD-PLAN
           PERFORM SCAN-KPI-TREND
           PERFORM SCAN-SLA
           PERFORM DECIDE-DISPOSITION

           CLOSE IN-KTR IN-SLA IN-PLN OUT-DSP

           DISPLAY 'ORDR540 KPI CRIT    : ' WS-KPI-CRIT
           DISPLAY 'ORDR540 SLA CRIT    : ' WS-SLA-CRIT
           DISPLAY 'ORDR540 KPI WARN    : ' WS-KPI-WARN
           DISPLAY 'ORDR540 SLA WARN    : ' WS-SLA-WARN

           GOBACK.

       LOAD-PLAN.
           READ IN-PLN
               AT END
                   CONTINUE
               NOT AT END
                   MOVE RST-PLAN-RUN-ID TO WS-RUN-ID
                   MOVE RST-PLAN-NEXT-STAGE TO WS-RESTART-STAGE
           END-READ.

       SCAN-KPI-TREND.
           PERFORM UNTIL END-OF-KTR
               READ IN-KTR
                   AT END
                       SET END-OF-KTR TO TRUE
                   NOT AT END
                       IF KPI-TRD-SEVERITY = '1'
                           ADD 1 TO WS-KPI-CRIT
                       END-IF
                       IF KPI-TRD-SEVERITY = '2'
                           ADD 1 TO WS-KPI-WARN
                       END-IF
               END-READ
           END-PERFORM.

       SCAN-SLA.
           PERFORM UNTIL END-OF-SLA
               READ IN-SLA
                   AT END
                       SET END-OF-SLA TO TRUE
                   NOT AT END
                       IF SLA-SEVERITY = '1'
                           ADD 1 TO WS-SLA-CRIT
                       END-IF
                       IF SLA-SEVERITY = '2'
                           ADD 1 TO WS-SLA-WARN
                       END-IF
               END-READ
           END-PERFORM.

       DECIDE-DISPOSITION.
           ADD WS-KPI-CRIT WS-SLA-CRIT GIVING WS-RED-SIGNALS
           ADD WS-KPI-WARN WS-SLA-WARN GIVING WS-AMBER-SIGNALS

           IF WS-RESTART-STAGE NOT = 'NONE    '
               ADD 1 TO WS-AMBER-SIGNALS
           END-IF

           MOVE SPACES TO RUN-DSP-REC
           MOVE WS-RUN-ID TO RUN-DSP-RUN-ID
           MOVE WS-RESTART-STAGE TO RUN-DSP-RESTART-STAGE
           MOVE WS-RED-SIGNALS TO RUN-DSP-RED-SIGNALS
           MOVE WS-AMBER-SIGNALS TO RUN-DSP-AMBER-SIGNALS
           MOVE WS-KPI-CRIT TO RUN-DSP-KPI-CRIT
           MOVE WS-SLA-CRIT TO RUN-DSP-SLA-CRIT
           MOVE WS-KPI-WARN TO RUN-DSP-KPI-WARN
           MOVE WS-SLA-WARN TO RUN-DSP-SLA-WARN

           IF WS-RED-SIGNALS > 0
               MOVE 'RED   ' TO RUN-DSP-STATUS
               MOVE '1' TO RUN-DSP-SEVERITY
               MOVE 'CRITICAL GOVERNANCE SIGNALS DETECTED; EXECUTIVE ESCALATION REQUIRED'
                 TO RUN-DSP-MESSAGE
           ELSE
               IF WS-AMBER-SIGNALS > 0
                   MOVE 'AMBER ' TO RUN-DSP-STATUS
                   MOVE '2' TO RUN-DSP-SEVERITY
                   MOVE 'WARNING SIGNALS DETECTED; CONTROL-ROOM FOLLOW-UP REQUIRED'
                     TO RUN-DSP-MESSAGE
               ELSE
                   MOVE 'GREEN ' TO RUN-DSP-STATUS
                   MOVE '0' TO RUN-DSP-SEVERITY
                   MOVE 'ALL GOVERNANCE SIGNALS WITHIN EXPECTED OPERATING RANGE'
                     TO RUN-DSP-MESSAGE
               END-IF
           END-IF

           WRITE RUN-DSP-REC.

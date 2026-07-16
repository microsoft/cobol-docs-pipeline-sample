       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR560.
      *---------------------------------------------------------------*
      * Control-room handoff manifest publisher.
      * Inputs: key outputs from stages 400-550.
      * Output: normalized bundle manifest for operational handoff.
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-AUD ASSIGN TO ORDRAUD
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-PLN ASSIGN TO ORDRPLN
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-RSK ASSIGN TO ORDRRSK
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-ACT ASSIGN TO ORDRACT
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-XEC ASSIGN TO ORDRXEC
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-STS ASSIGN TO ORDRSTS
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-SLA ASSIGN TO ORDRSLA
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-KPI ASSIGN TO ORDRKPI
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-KTR ASSIGN TO ORDRKTR
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-DSP ASSIGN TO ORDRDSP
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-GOV ASSIGN TO ORDRGOV
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-BND ASSIGN TO ORDRBND
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-AUD
           RECORD CONTAINS 180 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       01  IN-AUD-REC                    PIC X(180).

       FD  IN-PLN
           RECORD CONTAINS 160 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RSTRPLN1.

       FD  IN-RSK
           RECORD CONTAINS 220 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RISKALR1.

       FD  IN-ACT
           RECORD CONTAINS 220 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RECACT01.

       FD  IN-XEC
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY EXECRPT1.

       FD  IN-STS
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY ACTSTAT1.

       FD  IN-SLA
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY SLALRT1.

       FD  IN-KPI
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY KPIRPT1.

       FD  IN-KTR
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY KPITRD1.

       FD  IN-DSP
           RECORD CONTAINS 200 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RUNDSP1.

       FD  IN-GOV
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY GOVRPT1.

       FD  OUT-BND
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY BNDLMF1.

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-EOF-AUD                 PIC X VALUE 'N'.
           05 WS-EOF-PLN                 PIC X VALUE 'N'.
           05 WS-EOF-RSK                 PIC X VALUE 'N'.
           05 WS-EOF-ACT                 PIC X VALUE 'N'.
           05 WS-EOF-XEC                 PIC X VALUE 'N'.
           05 WS-EOF-STS                 PIC X VALUE 'N'.
           05 WS-EOF-SLA                 PIC X VALUE 'N'.
           05 WS-EOF-KPI                 PIC X VALUE 'N'.
           05 WS-EOF-KTR                 PIC X VALUE 'N'.
           05 WS-EOF-DSP                 PIC X VALUE 'N'.
           05 WS-EOF-GOV                 PIC X VALUE 'N'.

       01  WS-RUN-ID                     PIC X(8) VALUE 'ORDR560 '.
       01  WS-DSP-STATUS                 PIC X(6) VALUE 'UNKNWN'.

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR560 RUNNING ***'
           OPEN INPUT IN-AUD IN-PLN IN-RSK IN-ACT IN-XEC IN-STS
                      IN-SLA IN-KPI IN-KTR IN-DSP IN-GOV
                OUTPUT OUT-BND

           PERFORM PRIME-FILES
           PERFORM LOAD-RUN-CONTEXT
           PERFORM WRITE-MANIFEST

           CLOSE IN-AUD IN-PLN IN-RSK IN-ACT IN-XEC IN-STS
                 IN-SLA IN-KPI IN-KTR IN-DSP IN-GOV OUT-BND

           DISPLAY 'ORDR560 BUNDLE WRITTEN: 11'
           GOBACK.

       PRIME-FILES.
           READ IN-AUD
               AT END MOVE 'Y' TO WS-EOF-AUD
           END-READ
           READ IN-PLN
               AT END MOVE 'Y' TO WS-EOF-PLN
           END-READ
           READ IN-RSK
               AT END MOVE 'Y' TO WS-EOF-RSK
           END-READ
           READ IN-ACT
               AT END MOVE 'Y' TO WS-EOF-ACT
           END-READ
           READ IN-XEC
               AT END MOVE 'Y' TO WS-EOF-XEC
           END-READ
           READ IN-STS
               AT END MOVE 'Y' TO WS-EOF-STS
           END-READ
           READ IN-SLA
               AT END MOVE 'Y' TO WS-EOF-SLA
           END-READ
           READ IN-KPI
               AT END MOVE 'Y' TO WS-EOF-KPI
           END-READ
           READ IN-KTR
               AT END MOVE 'Y' TO WS-EOF-KTR
           END-READ
           READ IN-DSP
               AT END MOVE 'Y' TO WS-EOF-DSP
           END-READ
           READ IN-GOV
               AT END MOVE 'Y' TO WS-EOF-GOV
           END-READ.

       LOAD-RUN-CONTEXT.
           IF WS-EOF-PLN = 'N'
               MOVE RST-PLAN-RUN-ID TO WS-RUN-ID
           END-IF
           IF WS-EOF-DSP = 'N'
               MOVE RUN-DSP-STATUS TO WS-DSP-STATUS
           END-IF.

       WRITE-MANIFEST.
           PERFORM WRITE-AUD-LINE
           PERFORM WRITE-PLN-LINE
           PERFORM WRITE-RSK-LINE
           PERFORM WRITE-ACT-LINE
           PERFORM WRITE-XEC-LINE
           PERFORM WRITE-STS-LINE
           PERFORM WRITE-SLA-LINE
           PERFORM WRITE-KPI-LINE
           PERFORM WRITE-KTR-LINE
           PERFORM WRITE-DSP-LINE
           PERFORM WRITE-GOV-LINE.

       WRITE-AUD-LINE.
           MOVE SPACES TO BNDL-MF-REC
           MOVE WS-RUN-ID TO BNDL-MF-RUN-ID
           MOVE 'AUDIT-EVIDENCE      ' TO BNDL-MF-ARTIFACT
           MOVE 'ORDR400 ' TO BNDL-MF-STAGE
           MOVE 1 TO BNDL-MF-PRIORITY
           IF WS-EOF-AUD = 'Y'
               MOVE 'MISSING   ' TO BNDL-MF-STATUS
               MOVE 'AUDIT OUTPUT EMPTY OR UNAVAILABLE' TO BNDL-MF-SUMMARY
           ELSE
               MOVE 'READY     ' TO BNDL-MF-STATUS
               MOVE 'AUDIT EVIDENCE AVAILABLE FOR RECONCILIATION TRACEABILITY'
                 TO BNDL-MF-SUMMARY
           END-IF
           WRITE BNDL-MF-REC.

       WRITE-PLN-LINE.
           MOVE SPACES TO BNDL-MF-REC
           MOVE WS-RUN-ID TO BNDL-MF-RUN-ID
           MOVE 'RESTART-PLAN        ' TO BNDL-MF-ARTIFACT
           MOVE 'ORDR460 ' TO BNDL-MF-STAGE
           MOVE 1 TO BNDL-MF-PRIORITY
           IF WS-EOF-PLN = 'Y'
               MOVE 'MISSING   ' TO BNDL-MF-STATUS
               MOVE 'RESTART PLAN NOT GENERATED' TO BNDL-MF-SUMMARY
           ELSE
               MOVE 'READY     ' TO BNDL-MF-STATUS
               STRING
                   'NEXT STAGE=' DELIMITED BY SIZE
                   RST-PLAN-NEXT-STAGE DELIMITED BY SIZE
                   ' ACTION=' DELIMITED BY SIZE
                   RST-PLAN-ACTION DELIMITED BY SIZE
                   INTO BNDL-MF-SUMMARY
               END-STRING
           END-IF
           WRITE BNDL-MF-REC.

       WRITE-RSK-LINE.
           MOVE SPACES TO BNDL-MF-REC
           MOVE WS-RUN-ID TO BNDL-MF-RUN-ID
           MOVE 'RISK-ALERTS         ' TO BNDL-MF-ARTIFACT
           MOVE 'ORDR470 ' TO BNDL-MF-STAGE
           MOVE 2 TO BNDL-MF-PRIORITY
           IF WS-EOF-RSK = 'Y'
               MOVE 'EMPTY     ' TO BNDL-MF-STATUS
               MOVE 'NO RISK ALERTS PRODUCED' TO BNDL-MF-SUMMARY
           ELSE
               MOVE 'READY     ' TO BNDL-MF-STATUS
               MOVE 'RISK ALERT PAYLOAD AVAILABLE FOR GOVERNANCE REVIEW'
                 TO BNDL-MF-SUMMARY
           END-IF
           WRITE BNDL-MF-REC.

       WRITE-ACT-LINE.
           MOVE SPACES TO BNDL-MF-REC
           MOVE WS-RUN-ID TO BNDL-MF-RUN-ID
           MOVE 'RECOMMENDED-ACTIONS ' TO BNDL-MF-ARTIFACT
           MOVE 'ORDR480 ' TO BNDL-MF-STAGE
           MOVE 2 TO BNDL-MF-PRIORITY
           IF WS-EOF-ACT = 'Y'
               MOVE 'MISSING   ' TO BNDL-MF-STATUS
               MOVE 'ACTION RECOMMENDATIONS NOT AVAILABLE' TO BNDL-MF-SUMMARY
           ELSE
               MOVE 'READY     ' TO BNDL-MF-STATUS
               MOVE 'REMEDIATION ACTIONS AVAILABLE FOR EXECUTION PIPELINE'
                 TO BNDL-MF-SUMMARY
           END-IF
           WRITE BNDL-MF-REC.

       WRITE-XEC-LINE.
           MOVE SPACES TO BNDL-MF-REC
           MOVE WS-RUN-ID TO BNDL-MF-RUN-ID
           MOVE 'EXEC-SUMMARY         ' TO BNDL-MF-ARTIFACT
           MOVE 'ORDR490 ' TO BNDL-MF-STAGE
           MOVE 2 TO BNDL-MF-PRIORITY
           IF WS-EOF-XEC = 'Y'
               MOVE 'MISSING   ' TO BNDL-MF-STATUS
               MOVE 'EXECUTIVE SUMMARY NOT AVAILABLE' TO BNDL-MF-SUMMARY
           ELSE
               MOVE 'READY     ' TO BNDL-MF-STATUS
               MOVE 'EXECUTIVE SNAPSHOT READY FOR CONTROL-ROOM OVERVIEW'
                 TO BNDL-MF-SUMMARY
           END-IF
           WRITE BNDL-MF-REC.

       WRITE-STS-LINE.
           MOVE SPACES TO BNDL-MF-REC
           MOVE WS-RUN-ID TO BNDL-MF-RUN-ID
           MOVE 'ACTION-STATUS        ' TO BNDL-MF-ARTIFACT
           MOVE 'ORDR500 ' TO BNDL-MF-STAGE
           MOVE 3 TO BNDL-MF-PRIORITY
           IF WS-EOF-STS = 'Y'
               MOVE 'MISSING   ' TO BNDL-MF-STATUS
               MOVE 'ACTION STATUS STREAM NOT AVAILABLE' TO BNDL-MF-SUMMARY
           ELSE
               MOVE 'READY     ' TO BNDL-MF-STATUS
               MOVE 'CLOSED-LOOP STATUS AVAILABLE FOR OPS EXECUTION TRACKING'
                 TO BNDL-MF-SUMMARY
           END-IF
           WRITE BNDL-MF-REC.

       WRITE-SLA-LINE.
           MOVE SPACES TO BNDL-MF-REC
           MOVE WS-RUN-ID TO BNDL-MF-RUN-ID
           MOVE 'SLA-ALERTS          ' TO BNDL-MF-ARTIFACT
           MOVE 'ORDR510 ' TO BNDL-MF-STAGE
           MOVE 3 TO BNDL-MF-PRIORITY
           IF WS-EOF-SLA = 'Y'
               MOVE 'EMPTY     ' TO BNDL-MF-STATUS
               MOVE 'NO SLA BREACHES DETECTED' TO BNDL-MF-SUMMARY
           ELSE
               MOVE 'READY     ' TO BNDL-MF-STATUS
               MOVE 'SLA BREACH EVIDENCE AVAILABLE FOR RISK ESCALATION'
                 TO BNDL-MF-SUMMARY
           END-IF
           WRITE BNDL-MF-REC.

       WRITE-KPI-LINE.
           MOVE SPACES TO BNDL-MF-REC
           MOVE WS-RUN-ID TO BNDL-MF-RUN-ID
           MOVE 'KPI-ROLLUP          ' TO BNDL-MF-ARTIFACT
           MOVE 'ORDR520 ' TO BNDL-MF-STAGE
           MOVE 3 TO BNDL-MF-PRIORITY
           IF WS-EOF-KPI = 'Y'
               MOVE 'MISSING   ' TO BNDL-MF-STATUS
               MOVE 'KPI ROLLUP NOT AVAILABLE' TO BNDL-MF-SUMMARY
           ELSE
               MOVE 'READY     ' TO BNDL-MF-STATUS
               MOVE 'KPI ROLLUP READY FOR DASHBOARD AND TREND INPUT'
                 TO BNDL-MF-SUMMARY
           END-IF
           WRITE BNDL-MF-REC.

       WRITE-KTR-LINE.
           MOVE SPACES TO BNDL-MF-REC
           MOVE WS-RUN-ID TO BNDL-MF-RUN-ID
           MOVE 'KPI-TREND           ' TO BNDL-MF-ARTIFACT
           MOVE 'ORDR530 ' TO BNDL-MF-STAGE
           MOVE 4 TO BNDL-MF-PRIORITY
           IF WS-EOF-KTR = 'Y'
               MOVE 'EMPTY     ' TO BNDL-MF-STATUS
               MOVE 'NO KPI DRIFT ALERTS GENERATED' TO BNDL-MF-SUMMARY
           ELSE
               MOVE 'READY     ' TO BNDL-MF-STATUS
               MOVE 'TREND DRIFT SIGNALS AVAILABLE FOR GOVERNANCE REVIEW'
                 TO BNDL-MF-SUMMARY
           END-IF
           WRITE BNDL-MF-REC.

       WRITE-DSP-LINE.
           MOVE SPACES TO BNDL-MF-REC
           MOVE WS-RUN-ID TO BNDL-MF-RUN-ID
           MOVE 'DISPOSITION         ' TO BNDL-MF-ARTIFACT
           MOVE 'ORDR540 ' TO BNDL-MF-STAGE
           MOVE 4 TO BNDL-MF-PRIORITY
           IF WS-EOF-DSP = 'Y'
               MOVE 'MISSING   ' TO BNDL-MF-STATUS
               MOVE 'RUN DISPOSITION NOT AVAILABLE' TO BNDL-MF-SUMMARY
           ELSE
               MOVE 'READY     ' TO BNDL-MF-STATUS
               STRING
                   'FINAL STATUS=' DELIMITED BY SIZE
                   WS-DSP-STATUS DELIMITED BY SIZE
                   INTO BNDL-MF-SUMMARY
               END-STRING
           END-IF
           WRITE BNDL-MF-REC.

       WRITE-GOV-LINE.
           MOVE SPACES TO BNDL-MF-REC
           MOVE WS-RUN-ID TO BNDL-MF-RUN-ID
           MOVE 'GOV-NARRATIVE       ' TO BNDL-MF-ARTIFACT
           MOVE 'ORDR550 ' TO BNDL-MF-STAGE
           MOVE 5 TO BNDL-MF-PRIORITY
           IF WS-EOF-GOV = 'Y'
               MOVE 'MISSING   ' TO BNDL-MF-STATUS
               MOVE 'GOVERNANCE NARRATIVE OUTPUT NOT AVAILABLE'
                 TO BNDL-MF-SUMMARY
           ELSE
               MOVE 'READY     ' TO BNDL-MF-STATUS
               MOVE 'PUBLISH-READY GOVERNANCE NARRATIVE AVAILABLE'
                 TO BNDL-MF-SUMMARY
           END-IF
           WRITE BNDL-MF-REC.

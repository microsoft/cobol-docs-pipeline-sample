       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR550.
      *---------------------------------------------------------------*
      * Governance narrative publisher.
      * Inputs:
      * - run disposition (ORDR540)
      * - KPI feed (ORDR520)
      * - SLA alerts (ORDR510)
      * - restart plan (ORDR460)
      * Output:
      * - publish-ready governance narrative records
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-DSP ASSIGN TO ORDRDSP
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-KPI ASSIGN TO ORDRKPI
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-SLA ASSIGN TO ORDRSLA
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-PLN ASSIGN TO ORDRPLN
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-GOV ASSIGN TO ORDRGOV
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-DSP
           RECORD CONTAINS 200 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RUNDSP1.

       FD  IN-KPI
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY KPIRPT1.

       FD  IN-SLA
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY SLALRT1.

       FD  IN-PLN
           RECORD CONTAINS 160 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RSTRPLN1.

       FD  OUT-GOV
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY GOVRPT1.

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-END-KPI                 PIC X VALUE 'N'.
              88 END-OF-KPI              VALUE 'Y'.
           05 WS-END-SLA                 PIC X VALUE 'N'.
              88 END-OF-SLA              VALUE 'Y'.

       01  WS-RUN.
           05 WS-RUN-ID                  PIC X(8) VALUE 'ORDR550 '.
           05 WS-DSP-STATUS              PIC X(6) VALUE 'GREEN '.
           05 WS-DSP-SEVERITY            PIC X VALUE '0'.
           05 WS-PLAN-STAGE              PIC X(8) VALUE 'NONE    '.
           05 WS-PLAN-ACTION             PIC X(20) VALUE SPACES.

       01  WS-TOTALS.
           05 WS-KPI-ROWS                PIC 9(9) VALUE ZERO.
           05 WS-SLA-ROWS                PIC 9(9) VALUE ZERO.
           05 WS-KPI-SEV1                PIC 9(9) VALUE ZERO.
           05 WS-KPI-SEV2                PIC 9(9) VALUE ZERO.
           05 WS-SLA-SEV1                PIC 9(9) VALUE ZERO.
           05 WS-SLA-SEV2                PIC 9(9) VALUE ZERO.
           05 WS-EXEC-RATE               PIC 9(3)V99 VALUE ZERO.
           05 WS-PENDING-BACKLOG         PIC 9(9) VALUE ZERO.

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR550 RUNNING ***'
           OPEN INPUT IN-DSP IN-KPI IN-SLA IN-PLN
                OUTPUT OUT-GOV

           PERFORM LOAD-DISPOSITION
           PERFORM LOAD-PLAN
           PERFORM SCAN-KPI
           PERFORM SCAN-SLA
           PERFORM WRITE-HEADER
           PERFORM WRITE-RISK-POSTURE
           PERFORM WRITE-EXECUTION-POSTURE
           PERFORM WRITE-RESTART-POSTURE

           CLOSE IN-DSP IN-KPI IN-SLA IN-PLN OUT-GOV

           DISPLAY 'ORDR550 KPI ROWS : ' WS-KPI-ROWS
           DISPLAY 'ORDR550 SLA ROWS : ' WS-SLA-ROWS

           GOBACK.

       LOAD-DISPOSITION.
           READ IN-DSP
               AT END
                   CONTINUE
               NOT AT END
                   MOVE RUN-DSP-RUN-ID TO WS-RUN-ID
                   MOVE RUN-DSP-STATUS TO WS-DSP-STATUS
                   MOVE RUN-DSP-SEVERITY TO WS-DSP-SEVERITY
           END-READ.

       LOAD-PLAN.
           READ IN-PLN
               AT END
                   CONTINUE
               NOT AT END
                   MOVE RST-PLAN-NEXT-STAGE TO WS-PLAN-STAGE
                   MOVE RST-PLAN-ACTION TO WS-PLAN-ACTION
           END-READ.

       SCAN-KPI.
           PERFORM UNTIL END-OF-KPI
               READ IN-KPI
                   AT END
                       SET END-OF-KPI TO TRUE
                   NOT AT END
                       ADD 1 TO WS-KPI-ROWS
                       IF KPI-RPT-SEVERITY = '1'
                           ADD 1 TO WS-KPI-SEV1
                       END-IF
                       IF KPI-RPT-SEVERITY = '2'
                           ADD 1 TO WS-KPI-SEV2
                       END-IF
                       IF KPI-RPT-METRIC = 'EXECUTION-RATE      '
                           MOVE KPI-RPT-RATE TO WS-EXEC-RATE
                       END-IF
                       IF KPI-RPT-METRIC = 'PENDING-BACKLOG      '
                           MOVE KPI-RPT-COUNT TO WS-PENDING-BACKLOG
                       END-IF
               END-READ
           END-PERFORM.

       SCAN-SLA.
           PERFORM UNTIL END-OF-SLA
               READ IN-SLA
                   AT END
                       SET END-OF-SLA TO TRUE
                   NOT AT END
                       ADD 1 TO WS-SLA-ROWS
                       IF SLA-SEVERITY = '1'
                           ADD 1 TO WS-SLA-SEV1
                       END-IF
                       IF SLA-SEVERITY = '2'
                           ADD 1 TO WS-SLA-SEV2
                       END-IF
               END-READ
           END-PERFORM.

       WRITE-HEADER.
           MOVE SPACES TO GOV-RPT-REC
           MOVE WS-RUN-ID TO GOV-RPT-RUN-ID
           MOVE 'EXEC-HEADER  ' TO GOV-RPT-LINE-TYPE
           MOVE WS-DSP-STATUS TO GOV-RPT-STATUS
           MOVE WS-DSP-SEVERITY TO GOV-RPT-SEVERITY
           MOVE 'RUN-DISPOSITION      ' TO GOV-RPT-KEY
           MOVE WS-KPI-ROWS TO GOV-RPT-COUNT
           MOVE WS-EXEC-RATE TO GOV-RPT-RATE
           STRING
               'RUN GOVERNANCE STATUS=' DELIMITED BY SIZE
               WS-DSP-STATUS DELIMITED BY SIZE
               ' KPI-ROWS=' DELIMITED BY SIZE
               WS-KPI-ROWS DELIMITED BY SIZE
               ' SLA-ROWS=' DELIMITED BY SIZE
               WS-SLA-ROWS DELIMITED BY SIZE
               INTO GOV-RPT-MESSAGE
           END-STRING
           WRITE GOV-RPT-REC.

       WRITE-RISK-POSTURE.
           MOVE SPACES TO GOV-RPT-REC
           MOVE WS-RUN-ID TO GOV-RPT-RUN-ID
           MOVE 'RISK-SUMMARY ' TO GOV-RPT-LINE-TYPE
           MOVE WS-DSP-STATUS TO GOV-RPT-STATUS
           MOVE WS-DSP-SEVERITY TO GOV-RPT-SEVERITY
           MOVE 'SLA-POSTURE          ' TO GOV-RPT-KEY
           MOVE WS-SLA-ROWS TO GOV-RPT-COUNT
           MOVE WS-SLA-SEV1 TO GOV-RPT-AMOUNT
           MOVE ZERO TO GOV-RPT-RATE
           STRING
               'SLA CRITICAL=' DELIMITED BY SIZE
               WS-SLA-SEV1 DELIMITED BY SIZE
               ' WARNING=' DELIMITED BY SIZE
               WS-SLA-SEV2 DELIMITED BY SIZE
               INTO GOV-RPT-MESSAGE
           END-STRING
           WRITE GOV-RPT-REC.

       WRITE-EXECUTION-POSTURE.
           MOVE SPACES TO GOV-RPT-REC
           MOVE WS-RUN-ID TO GOV-RPT-RUN-ID
           MOVE 'OPS-SUMMARY  ' TO GOV-RPT-LINE-TYPE
           MOVE WS-DSP-STATUS TO GOV-RPT-STATUS
           MOVE WS-DSP-SEVERITY TO GOV-RPT-SEVERITY
           MOVE 'EXEC-POSTURE         ' TO GOV-RPT-KEY
           MOVE WS-PENDING-BACKLOG TO GOV-RPT-COUNT
           MOVE WS-KPI-SEV1 TO GOV-RPT-AMOUNT
           MOVE WS-EXEC-RATE TO GOV-RPT-RATE
           STRING
               'EXECUTION-RATE=' DELIMITED BY SIZE
               WS-EXEC-RATE DELIMITED BY SIZE
               ' PENDING=' DELIMITED BY SIZE
               WS-PENDING-BACKLOG DELIMITED BY SIZE
               INTO GOV-RPT-MESSAGE
           END-STRING
           WRITE GOV-RPT-REC.

       WRITE-RESTART-POSTURE.
           MOVE SPACES TO GOV-RPT-REC
           MOVE WS-RUN-ID TO GOV-RPT-RUN-ID
           MOVE 'RUNBOOK      ' TO GOV-RPT-LINE-TYPE
           MOVE WS-DSP-STATUS TO GOV-RPT-STATUS
           MOVE WS-DSP-SEVERITY TO GOV-RPT-SEVERITY
           MOVE 'RESTART-PLAN         ' TO GOV-RPT-KEY
           MOVE ZERO TO GOV-RPT-COUNT
           MOVE ZERO TO GOV-RPT-AMOUNT
           MOVE ZERO TO GOV-RPT-RATE
           STRING
               'NEXT-STAGE=' DELIMITED BY SIZE
               WS-PLAN-STAGE DELIMITED BY SIZE
               ' ACTION=' DELIMITED BY SIZE
               WS-PLAN-ACTION DELIMITED BY SIZE
               INTO GOV-RPT-MESSAGE
           END-STRING
           WRITE GOV-RPT-REC.

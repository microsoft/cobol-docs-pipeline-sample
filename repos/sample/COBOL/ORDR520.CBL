       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR520.
      *---------------------------------------------------------------*
      * Governance KPI rollup.
      * Inputs:
      * - executive report (ORDR490)
      * - action status stream (ORDR500)
      * - SLA alerts (ORDR510)
      * Output:
      * - KPI dashboard feed for control-room governance
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-XEC ASSIGN TO ORDRXEC
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-STS ASSIGN TO ORDRSTS
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-SLA ASSIGN TO ORDRSLA
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-KPI ASSIGN TO ORDRKPI
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
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

       FD  OUT-KPI
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY KPIRPT1.

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-END-XEC                 PIC X VALUE 'N'.
              88 END-OF-XEC              VALUE 'Y'.
           05 WS-END-STS                 PIC X VALUE 'N'.
              88 END-OF-STS              VALUE 'Y'.
           05 WS-END-SLA                 PIC X VALUE 'N'.
              88 END-OF-SLA              VALUE 'Y'.

       01  WS-RUN.
           05 WS-RUN-ID                  PIC X(8) VALUE 'ORDR520 '.

       01  WS-TOTALS.
           05 WS-TOTAL-ACTION            PIC 9(9) VALUE ZERO.
           05 WS-HIGH-PRIO-TOTAL         PIC 9(9) VALUE ZERO.
           05 WS-FIN-AMOUNT              PIC 9(13)V99 VALUE ZERO.

           05 WS-STS-READ                PIC 9(9) VALUE ZERO.
           05 WS-EXECUTED-COUNT          PIC 9(9) VALUE ZERO.
           05 WS-SCHEDULED-COUNT         PIC 9(9) VALUE ZERO.
           05 WS-PENDING-COUNT           PIC 9(9) VALUE ZERO.

           05 WS-SLA-READ                PIC 9(9) VALUE ZERO.
           05 WS-SLA-SEV1                PIC 9(9) VALUE ZERO.
           05 WS-SLA-SEV2                PIC 9(9) VALUE ZERO.

       01  WS-RATES.
           05 WS-EXEC-RATE               PIC 9(3)V99 VALUE ZERO.
           05 WS-SLA-RATE                PIC 9(3)V99 VALUE ZERO.

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR520 RUNNING ***'
           OPEN INPUT IN-XEC IN-STS IN-SLA
                OUTPUT OUT-KPI

           PERFORM SCAN-EXECUTIVE
           PERFORM SCAN-STATUS
           PERFORM SCAN-SLA
           PERFORM COMPUTE-RATES
           PERFORM WRITE-KPI-LINES

           CLOSE IN-XEC IN-STS IN-SLA OUT-KPI

           DISPLAY 'ORDR520 STATUS READ : ' WS-STS-READ
           DISPLAY 'ORDR520 SLA READ    : ' WS-SLA-READ
           DISPLAY 'ORDR520 KPI WRITTEN : 4'

           GOBACK.

       SCAN-EXECUTIVE.
           PERFORM UNTIL END-OF-XEC
               READ IN-XEC
                   AT END
                       SET END-OF-XEC TO TRUE
                   NOT AT END
                       MOVE EXEC-RPT-RUN-ID TO WS-RUN-ID
                       IF EXEC-RPT-LINE-TYPE = 'RUN-HEADER'
                           MOVE EXEC-RPT-ACTION-COUNT TO WS-TOTAL-ACTION
                           MOVE EXEC-RPT-HIGH-PRIORITY TO WS-HIGH-PRIO-TOTAL
                       END-IF
                       IF EXEC-RPT-LINE-TYPE = 'FIN-SUMMARY'
                           MOVE EXEC-RPT-AMOUNT TO WS-FIN-AMOUNT
                       END-IF
               END-READ
           END-PERFORM.

       SCAN-STATUS.
           PERFORM UNTIL END-OF-STS
               READ IN-STS
                   AT END
                       SET END-OF-STS TO TRUE
                   NOT AT END
                       ADD 1 TO WS-STS-READ
                       IF ACT-STAT-STATUS = 'EXECUTED    '
                           ADD 1 TO WS-EXECUTED-COUNT
                       END-IF
                       IF ACT-STAT-STATUS = 'SCHEDULED   '
                           ADD 1 TO WS-SCHEDULED-COUNT
                       END-IF
                       IF ACT-STAT-STATUS = 'PENDING-APR '
                           ADD 1 TO WS-PENDING-COUNT
                       END-IF
               END-READ
           END-PERFORM.

       SCAN-SLA.
           PERFORM UNTIL END-OF-SLA
               READ IN-SLA
                   AT END
                       SET END-OF-SLA TO TRUE
                   NOT AT END
                       ADD 1 TO WS-SLA-READ
                       IF SLA-SEVERITY = '1'
                           ADD 1 TO WS-SLA-SEV1
                       END-IF
                       IF SLA-SEVERITY = '2'
                           ADD 1 TO WS-SLA-SEV2
                       END-IF
               END-READ
           END-PERFORM.

       COMPUTE-RATES.
           IF WS-STS-READ > 0
               COMPUTE WS-EXEC-RATE =
                   (WS-EXECUTED-COUNT * 100) / WS-STS-READ
           END-IF

           IF WS-TOTAL-ACTION > 0
               COMPUTE WS-SLA-RATE =
                   (WS-SLA-READ * 100) / WS-TOTAL-ACTION
           END-IF.

       WRITE-KPI-LINES.
           PERFORM WRITE-KPI-EXECUTION
           PERFORM WRITE-KPI-BACKLOG
           PERFORM WRITE-KPI-SLA
           PERFORM WRITE-KPI-FINANCE.

       WRITE-KPI-EXECUTION.
           MOVE SPACES TO KPI-RPT-REC
           MOVE WS-RUN-ID TO KPI-RPT-RUN-ID
           MOVE 'OPERATIONS' TO KPI-RPT-CATEGORY
           MOVE 'EXECUTION-RATE      ' TO KPI-RPT-METRIC
           MOVE WS-EXECUTED-COUNT TO KPI-RPT-COUNT
           MOVE WS-EXEC-RATE TO KPI-RPT-RATE
           IF WS-EXEC-RATE < 80
               MOVE '2' TO KPI-RPT-SEVERITY
           ELSE
               MOVE '0' TO KPI-RPT-SEVERITY
           END-IF
           MOVE 'EXECUTION COMPLETION RATE FOR CLOSED-LOOP ACTIONS'
             TO KPI-RPT-MESSAGE
           WRITE KPI-RPT-REC.

       WRITE-KPI-BACKLOG.
           MOVE SPACES TO KPI-RPT-REC
           MOVE WS-RUN-ID TO KPI-RPT-RUN-ID
           MOVE 'OPERATIONS' TO KPI-RPT-CATEGORY
           MOVE 'PENDING-BACKLOG      ' TO KPI-RPT-METRIC
           MOVE WS-PENDING-COUNT TO KPI-RPT-COUNT
           MOVE WS-HIGH-PRIO-TOTAL TO KPI-RPT-AMOUNT
           MOVE ZERO TO KPI-RPT-RATE
           IF WS-PENDING-COUNT > 0
               MOVE '1' TO KPI-RPT-SEVERITY
           ELSE
               MOVE '0' TO KPI-RPT-SEVERITY
           END-IF
           MOVE 'PENDING APPROVAL BACKLOG WITH HIGH-PRIORITY REFERENCE'
             TO KPI-RPT-MESSAGE
           WRITE KPI-RPT-REC.

       WRITE-KPI-SLA.
           MOVE SPACES TO KPI-RPT-REC
           MOVE WS-RUN-ID TO KPI-RPT-RUN-ID
           MOVE 'RISK      ' TO KPI-RPT-CATEGORY
           MOVE 'SLA-ALERT-DENSITY    ' TO KPI-RPT-METRIC
           MOVE WS-SLA-READ TO KPI-RPT-COUNT
           MOVE WS-SLA-SEV2 TO KPI-RPT-AMOUNT
           MOVE WS-SLA-RATE TO KPI-RPT-RATE
           IF WS-SLA-SEV2 > 0
               MOVE '2' TO KPI-RPT-SEVERITY
           ELSE
               MOVE '0' TO KPI-RPT-SEVERITY
           END-IF
           MOVE 'SLA BREACH DENSITY RELATIVE TO RECOMMENDED ACTION VOLUME'
             TO KPI-RPT-MESSAGE
           WRITE KPI-RPT-REC.

       WRITE-KPI-FINANCE.
           MOVE SPACES TO KPI-RPT-REC
           MOVE WS-RUN-ID TO KPI-RPT-RUN-ID
           MOVE 'FINANCE   ' TO KPI-RPT-CATEGORY
           MOVE 'TOTAL-EUR-SETTLED    ' TO KPI-RPT-METRIC
           MOVE WS-TOTAL-ACTION TO KPI-RPT-COUNT
           MOVE WS-FIN-AMOUNT TO KPI-RPT-AMOUNT
           MOVE ZERO TO KPI-RPT-RATE
           MOVE '0' TO KPI-RPT-SEVERITY
           MOVE 'FINANCIAL VOLUME FROM EXECUTIVE SUMMARY FOR DAILY DASHBOARD'
             TO KPI-RPT-MESSAGE
           WRITE KPI-RPT-REC.

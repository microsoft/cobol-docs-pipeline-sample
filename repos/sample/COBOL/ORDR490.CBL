       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR490.
      *---------------------------------------------------------------*
      * Executive run summary and governance report.
      * Inputs:
      * - structured controls (ORDR300)
      * - risk alerts (ORDR470)
      * - restart plan (ORDR460)
      * - recommended actions (ORDR480)
      * Output:
      * - executive report lines for operations and audit consumers
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-CTL ASSIGN TO ORDRCTL
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-RISK ASSIGN TO ORDRRSK
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-PLAN ASSIGN TO ORDRPLN
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-ACTION ASSIGN TO ORDRACT
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-REPORT ASSIGN TO ORDRXEC
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-CTL
           RECORD CONTAINS 120 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY ORDRCTL1.

       FD  IN-RISK
           RECORD CONTAINS 220 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RISKALR1.

       FD  IN-PLAN
           RECORD CONTAINS 160 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RSTRPLN1.

       FD  IN-ACTION
           RECORD CONTAINS 220 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RECACT01.

       FD  OUT-REPORT
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY EXECRPT1.

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-END-CTL                 PIC X VALUE 'N'.
              88 END-OF-CTL              VALUE 'Y'.
           05 WS-END-RISK                PIC X VALUE 'N'.
              88 END-OF-RISK             VALUE 'Y'.
           05 WS-END-ACTION              PIC X VALUE 'N'.
              88 END-OF-ACTION           VALUE 'Y'.

       01  WS-RUN.
           05 WS-RUN-ID                  PIC X(8) VALUE 'ORDR490 '.
           05 WS-PLAN-STAGE              PIC X(8) VALUE 'NONE    '.
           05 WS-PLAN-ACTION             PIC X(20) VALUE SPACES.

       01  WS-TOTALS.
           05 WS-CTL-ROWS                PIC 9(9) VALUE ZERO.
           05 WS-RISK-ROWS               PIC 9(9) VALUE ZERO.
           05 WS-ACTION-ROWS             PIC 9(9) VALUE ZERO.
           05 WS-SEV1-COUNT              PIC 9(9) VALUE ZERO.
           05 WS-SEV2-COUNT              PIC 9(9) VALUE ZERO.
           05 WS-HIGH-PRIO-COUNT         PIC 9(9) VALUE ZERO.
           05 WS-TOTAL-COUNT             PIC 9(9) VALUE ZERO.
           05 WS-TOTAL-AMOUNT            PIC 9(15)V99 VALUE ZERO.

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR490 RUNNING ***'
           OPEN INPUT IN-CTL IN-RISK IN-PLAN IN-ACTION
                OUTPUT OUT-REPORT

           PERFORM LOAD-PLAN
           PERFORM SUMMARIZE-CONTROLS
           PERFORM SUMMARIZE-RISK
           PERFORM SUMMARIZE-ACTIONS
           PERFORM WRITE-REPORT-HEADER
           PERFORM WRITE-REPORT-SUMMARY
           PERFORM WRITE-REPORT-RESTART

           CLOSE IN-CTL IN-RISK IN-PLAN IN-ACTION OUT-REPORT

           DISPLAY 'ORDR490 CTL ROWS     : ' WS-CTL-ROWS
           DISPLAY 'ORDR490 RISK ROWS    : ' WS-RISK-ROWS
           DISPLAY 'ORDR490 ACTION ROWS  : ' WS-ACTION-ROWS
           DISPLAY 'ORDR490 HIGH PRIORITY: ' WS-HIGH-PRIO-COUNT

           GOBACK.

       LOAD-PLAN.
           READ IN-PLAN
               AT END
                   CONTINUE
               NOT AT END
                   MOVE RST-PLAN-RUN-ID TO WS-RUN-ID
                   MOVE RST-PLAN-NEXT-STAGE TO WS-PLAN-STAGE
                   MOVE RST-PLAN-ACTION TO WS-PLAN-ACTION
                   MOVE RST-PLAN-SEV1-COUNT TO WS-SEV1-COUNT
                   MOVE RST-PLAN-SEV2-COUNT TO WS-SEV2-COUNT
           END-READ.

       SUMMARIZE-CONTROLS.
           PERFORM UNTIL END-OF-CTL
               READ IN-CTL
                   AT END
                       SET END-OF-CTL TO TRUE
                   NOT AT END
                       ADD 1 TO WS-CTL-ROWS
                       IF ORDR-CTL-METRIC = 'ORDERS-PROCESSED    '
                           ADD ORDR-CTL-COUNT-VALUE TO WS-TOTAL-COUNT
                       END-IF
                       IF ORDR-CTL-METRIC = 'TOTAL-EUR           '
                           ADD ORDR-CTL-AMOUNT-VALUE TO WS-TOTAL-AMOUNT
                       END-IF
               END-READ
           END-PERFORM.

       SUMMARIZE-RISK.
           PERFORM UNTIL END-OF-RISK
               READ IN-RISK
                   AT END
                       SET END-OF-RISK TO TRUE
                   NOT AT END
                       ADD 1 TO WS-RISK-ROWS
               END-READ
           END-PERFORM.

       SUMMARIZE-ACTIONS.
           PERFORM UNTIL END-OF-ACTION
               READ IN-ACTION
                   AT END
                       SET END-OF-ACTION TO TRUE
                   NOT AT END
                       ADD 1 TO WS-ACTION-ROWS
                       IF REC-ACT-PRIORITY <= 10
                           ADD 1 TO WS-HIGH-PRIO-COUNT
                       END-IF
               END-READ
           END-PERFORM.

       WRITE-REPORT-HEADER.
           MOVE SPACES TO EXEC-RPT-REC
           MOVE WS-RUN-ID TO EXEC-RPT-RUN-ID
           MOVE 'RUN-HEADER' TO EXEC-RPT-LINE-TYPE
           MOVE WS-CTL-ROWS TO EXEC-RPT-COUNT
           MOVE WS-TOTAL-AMOUNT TO EXEC-RPT-AMOUNT
           MOVE WS-SEV1-COUNT TO EXEC-RPT-SEV1
           MOVE WS-SEV2-COUNT TO EXEC-RPT-SEV2
           MOVE WS-ACTION-ROWS TO EXEC-RPT-ACTION-COUNT
           MOVE WS-HIGH-PRIO-COUNT TO EXEC-RPT-HIGH-PRIORITY
           MOVE WS-PLAN-STAGE TO EXEC-RPT-RESTART-STAGE
           STRING
               'EXECUTIVE RUN SNAPSHOT: CTL=' DELIMITED BY SIZE
               WS-CTL-ROWS DELIMITED BY SIZE
               ' RISK=' DELIMITED BY SIZE
               WS-RISK-ROWS DELIMITED BY SIZE
               ' ACTION=' DELIMITED BY SIZE
               WS-ACTION-ROWS DELIMITED BY SIZE
               INTO EXEC-RPT-MESSAGE
           END-STRING
           WRITE EXEC-RPT-REC.

       WRITE-REPORT-SUMMARY.
           MOVE SPACES TO EXEC-RPT-REC
           MOVE WS-RUN-ID TO EXEC-RPT-RUN-ID
           MOVE 'FIN-SUMMARY' TO EXEC-RPT-LINE-TYPE
           MOVE 'ORDERS-PROCESSED    ' TO EXEC-RPT-METRIC
           MOVE 'ALL       ' TO EXEC-RPT-CHANNEL
           MOVE WS-TOTAL-COUNT TO EXEC-RPT-COUNT
           MOVE WS-TOTAL-AMOUNT TO EXEC-RPT-AMOUNT
           MOVE WS-ACTION-ROWS TO EXEC-RPT-ACTION-COUNT
           MOVE WS-HIGH-PRIO-COUNT TO EXEC-RPT-HIGH-PRIORITY
           MOVE WS-PLAN-STAGE TO EXEC-RPT-RESTART-STAGE
           MOVE 'FINANCIAL AGGREGATE FROM STRUCTURED CONTROLS'
             TO EXEC-RPT-MESSAGE
           WRITE EXEC-RPT-REC.

       WRITE-REPORT-RESTART.
           MOVE SPACES TO EXEC-RPT-REC
           MOVE WS-RUN-ID TO EXEC-RPT-RUN-ID
           MOVE 'RESTART   ' TO EXEC-RPT-LINE-TYPE
           MOVE WS-SEV1-COUNT TO EXEC-RPT-SEV1
           MOVE WS-SEV2-COUNT TO EXEC-RPT-SEV2
           MOVE WS-ACTION-ROWS TO EXEC-RPT-ACTION-COUNT
           MOVE WS-HIGH-PRIO-COUNT TO EXEC-RPT-HIGH-PRIORITY
           MOVE WS-PLAN-STAGE TO EXEC-RPT-RESTART-STAGE
           STRING
               'RESTART ACTION=' DELIMITED BY SIZE
               WS-PLAN-ACTION DELIMITED BY SIZE
               ' NEXT-STAGE=' DELIMITED BY SIZE
               WS-PLAN-STAGE DELIMITED BY SIZE
               INTO EXEC-RPT-MESSAGE
           END-STRING
           WRITE EXEC-RPT-REC.

       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR510.
      *---------------------------------------------------------------*
      * SLA breach detection on action execution statuses.
      * Inputs:
      * - action status stream (ORDR500)
      * - runtime policy
      * Output:
      * - SLA alerts for overdue/high-priority pending actions
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-STATUS ASSIGN TO ORDRSTS
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-CFG ASSIGN TO RUNCFG
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-SLA ASSIGN TO ORDRSLA
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-STATUS
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY ACTSTAT1.

       FD  IN-CFG
           RECORD CONTAINS 80 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RUNCFG01.

       FD  OUT-SLA
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY SLALRT1.

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-END-STATUS              PIC X VALUE 'N'.
              88 END-OF-STATUS           VALUE 'Y'.

       01  WS-CFG.
           05 WS-RUN-MODE                PIC X(3) VALUE 'EOD'.
           05 WS-STRICT-FLAG             PIC X VALUE 'N'.
           05 WS-PENDING-LIMIT           PIC 9(5) VALUE ZERO.
           05 WS-HIGH-PRIO-LIMIT         PIC 9(5) VALUE ZERO.

       01  WS-TOTALS.
           05 WS-STATUS-READ             PIC 9(9) VALUE ZERO.
           05 WS-PENDING-COUNT           PIC 9(9) VALUE ZERO.
           05 WS-SCHEDULED-COUNT         PIC 9(9) VALUE ZERO.
           05 WS-HIGH-PRIO-PENDING       PIC 9(9) VALUE ZERO.
           05 WS-ALERT-WRITTEN           PIC 9(9) VALUE ZERO.

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR510 RUNNING ***'
           OPEN INPUT IN-STATUS IN-CFG
                OUTPUT OUT-SLA

           PERFORM LOAD-CONFIG
           PERFORM SCAN-STATUSES
           PERFORM WRITE-SUMMARY-ALERT

           CLOSE IN-STATUS IN-CFG OUT-SLA

           DISPLAY 'ORDR510 STATUS READ   : ' WS-STATUS-READ
           DISPLAY 'ORDR510 PENDING COUNT : ' WS-PENDING-COUNT
           DISPLAY 'ORDR510 HIGH PENDING  : ' WS-HIGH-PRIO-PENDING
           DISPLAY 'ORDR510 ALERT WRITTEN : ' WS-ALERT-WRITTEN

           GOBACK.

       LOAD-CONFIG.
           READ IN-CFG
               AT END
                   CONTINUE
               NOT AT END
                   MOVE RUN-CFG-RUN-MODE TO WS-RUN-MODE
                   MOVE RUN-CFG-STRICT-FLAG TO WS-STRICT-FLAG
                   MOVE RUN-CFG-MIN-SEV2-FAIL TO WS-PENDING-LIMIT
                   MOVE RUN-CFG-MIN-SEV1-FAIL TO WS-HIGH-PRIO-LIMIT
           END-READ.

       SCAN-STATUSES.
           PERFORM UNTIL END-OF-STATUS
               READ IN-STATUS
                   AT END
                       SET END-OF-STATUS TO TRUE
                   NOT AT END
                       ADD 1 TO WS-STATUS-READ
                       PERFORM ACCUMULATE-COUNTERS
                       PERFORM EVALUATE-ONE-STATUS
               END-READ
           END-PERFORM.

       ACCUMULATE-COUNTERS.
           IF ACT-STAT-STATUS = 'PENDING-APR '
               ADD 1 TO WS-PENDING-COUNT
               IF ACT-STAT-PRIORITY <= 10
                   ADD 1 TO WS-HIGH-PRIO-PENDING
               END-IF
           END-IF

           IF ACT-STAT-STATUS = 'SCHEDULED   '
               ADD 1 TO WS-SCHEDULED-COUNT
           END-IF.

       EVALUATE-ONE-STATUS.
           IF ACT-STAT-STATUS = 'PENDING-APR '
              AND ACT-STAT-PRIORITY <= 10
               PERFORM WRITE-ITEM-ALERT
           END-IF

           IF WS-STRICT-FLAG = 'Y'
              AND ACT-STAT-STATUS = 'PENDING-APR '
              AND ACT-STAT-PRIORITY <= 20
               PERFORM WRITE-STRICT-ALERT
           END-IF.

       WRITE-ITEM-ALERT.
           MOVE SPACES TO SLA-ALERT-REC
           MOVE ACT-STAT-RUN-ID TO SLA-RUN-ID
           MOVE 'ITEM-BREACH' TO SLA-LINE-TYPE
           MOVE ACT-STAT-TICKET TO SLA-TICKET
           MOVE ACT-STAT-OWNER TO SLA-OWNER
           MOVE '1' TO SLA-SEVERITY
           MOVE 'PENDING-HI  ' TO SLA-BREACH-CODE
           MOVE ACT-STAT-PRIORITY TO SLA-PRIORITY
           MOVE ACT-STAT-TARGET-STAGE TO SLA-TARGET-STAGE
           MOVE ACT-STAT-STATUS TO SLA-STATUS
           STRING
               'HIGH PRIORITY ACTION STILL PENDING APPROVAL' DELIMITED BY SIZE
               ' | MODE=' DELIMITED BY SIZE
               WS-RUN-MODE DELIMITED BY SIZE
               INTO SLA-MESSAGE
           END-STRING
           WRITE SLA-ALERT-REC
           ADD 1 TO WS-ALERT-WRITTEN.

       WRITE-STRICT-ALERT.
           MOVE SPACES TO SLA-ALERT-REC
           MOVE ACT-STAT-RUN-ID TO SLA-RUN-ID
           MOVE 'STRICT-BRCH' TO SLA-LINE-TYPE
           MOVE ACT-STAT-TICKET TO SLA-TICKET
           MOVE ACT-STAT-OWNER TO SLA-OWNER
           MOVE '2' TO SLA-SEVERITY
           MOVE 'STRICT-PEND ' TO SLA-BREACH-CODE
           MOVE ACT-STAT-PRIORITY TO SLA-PRIORITY
           MOVE ACT-STAT-TARGET-STAGE TO SLA-TARGET-STAGE
           MOVE ACT-STAT-STATUS TO SLA-STATUS
           MOVE 'STRICT MODE DOES NOT ALLOW EXTENDED MANUAL PENDING'
             TO SLA-MESSAGE
           WRITE SLA-ALERT-REC
           ADD 1 TO WS-ALERT-WRITTEN.

       WRITE-SUMMARY-ALERT.
           IF WS-PENDING-COUNT > WS-PENDING-LIMIT
               MOVE SPACES TO SLA-ALERT-REC
               MOVE 'ORDR510 ' TO SLA-RUN-ID
               MOVE 'RUN-SUMM  ' TO SLA-LINE-TYPE
               MOVE 'SLA-SUMMARY ' TO SLA-TICKET
               MOVE 'RUNCTRL ' TO SLA-OWNER
               MOVE '2' TO SLA-SEVERITY
               MOVE 'PEND-LIMIT ' TO SLA-BREACH-CODE
               MOVE 99 TO SLA-PRIORITY
               MOVE 'ALL     ' TO SLA-TARGET-STAGE
               MOVE 'SUMMARY     ' TO SLA-STATUS
               STRING
                   'PENDING ACTIONS=' DELIMITED BY SIZE
                   WS-PENDING-COUNT DELIMITED BY SIZE
                   ' LIMIT=' DELIMITED BY SIZE
                   WS-PENDING-LIMIT DELIMITED BY SIZE
                   ' HIGH-PENDING=' DELIMITED BY SIZE
                   WS-HIGH-PRIO-PENDING DELIMITED BY SIZE
                   INTO SLA-MESSAGE
               END-STRING
               WRITE SLA-ALERT-REC
               ADD 1 TO WS-ALERT-WRITTEN
           END-IF.

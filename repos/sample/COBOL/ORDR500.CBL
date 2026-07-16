       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR500.
      *---------------------------------------------------------------*
      * Action execution simulator and closed-loop tracker.
      * Inputs:
      * - recommended actions (ORDR480)
      * - runtime policy (RUNCFG)
      * Output:
      * - action execution status stream
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-ACTION ASSIGN TO ORDRACT
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-CFG ASSIGN TO RUNCFG
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-STATUS ASSIGN TO ORDRSTS
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-ACTION
           RECORD CONTAINS 220 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RECACT01.

       FD  IN-CFG
           RECORD CONTAINS 80 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RUNCFG01.

       FD  OUT-STATUS
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY ACTSTAT1.

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-END-ACTION              PIC X VALUE 'N'.
              88 END-OF-ACTION           VALUE 'Y'.

       01  WS-CFG.
           05 WS-STRICT-FLAG             PIC X VALUE 'N'.
           05 WS-RUN-MODE                PIC X(3) VALUE 'EOD'.

       01  WS-TICKET.
           05 WS-TICKET-NUM              PIC 9(6) VALUE ZERO.

       01  WS-COUNTERS.
           05 WS-ACTION-READ             PIC 9(9) VALUE ZERO.
           05 WS-EXECUTED-COUNT          PIC 9(9) VALUE ZERO.
           05 WS-SCHEDULED-COUNT         PIC 9(9) VALUE ZERO.
           05 WS-PENDING-COUNT           PIC 9(9) VALUE ZERO.

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR500 RUNNING ***'
           OPEN INPUT IN-ACTION IN-CFG
                OUTPUT OUT-STATUS

           PERFORM LOAD-CONFIG
           PERFORM PROCESS-ACTIONS

           CLOSE IN-ACTION IN-CFG OUT-STATUS

           DISPLAY 'ORDR500 ACTION READ    : ' WS-ACTION-READ
           DISPLAY 'ORDR500 EXECUTED COUNT : ' WS-EXECUTED-COUNT
           DISPLAY 'ORDR500 SCHEDULED COUNT: ' WS-SCHEDULED-COUNT
           DISPLAY 'ORDR500 PENDING COUNT  : ' WS-PENDING-COUNT

           GOBACK.

       LOAD-CONFIG.
           READ IN-CFG
               AT END
                   CONTINUE
               NOT AT END
                   MOVE RUN-CFG-RUN-MODE TO WS-RUN-MODE
                   MOVE RUN-CFG-STRICT-FLAG TO WS-STRICT-FLAG
           END-READ.

       PROCESS-ACTIONS.
           PERFORM UNTIL END-OF-ACTION
               READ IN-ACTION
                   AT END
                       SET END-OF-ACTION TO TRUE
                   NOT AT END
                       ADD 1 TO WS-ACTION-READ
                       PERFORM WRITE-STATUS
               END-READ
           END-PERFORM.

       WRITE-STATUS.
           MOVE SPACES TO ACT-STAT-REC
           MOVE REC-ACT-RUN-ID TO ACT-STAT-RUN-ID
           MOVE REC-ACT-SOURCE TO ACT-STAT-SOURCE
           MOVE REC-ACT-ACTION TO ACT-STAT-ACTION
           MOVE REC-ACT-TARGET-STAGE TO ACT-STAT-TARGET-STAGE
           MOVE REC-ACT-PRIORITY TO ACT-STAT-PRIORITY
           MOVE REC-ACT-AUTO-FLAG TO ACT-STAT-AUTO-FLAG

           EVALUATE REC-ACT-ROUTE
               WHEN 'RUNCTRL '
                   MOVE 'RUNCTRL ' TO ACT-STAT-OWNER
               WHEN 'DATAOPS '
                   MOVE 'DATAOPS ' TO ACT-STAT-OWNER
               WHEN OTHER
                   MOVE 'OPS     ' TO ACT-STAT-OWNER
           END-EVALUATE

           IF REC-ACT-AUTO-FLAG = 'Y'
               IF REC-ACT-PRIORITY <= 10
                   MOVE 'EXECUTED    ' TO ACT-STAT-STATUS
                   ADD 1 TO WS-EXECUTED-COUNT
               ELSE
                   MOVE 'SCHEDULED   ' TO ACT-STAT-STATUS
                   ADD 1 TO WS-SCHEDULED-COUNT
               END-IF
           ELSE
               IF WS-STRICT-FLAG = 'Y'
                  AND REC-ACT-SEVERITY = '1'
                   MOVE 'SCHEDULED   ' TO ACT-STAT-STATUS
                   ADD 1 TO WS-SCHEDULED-COUNT
               ELSE
                   MOVE 'PENDING-APR ' TO ACT-STAT-STATUS
                   ADD 1 TO WS-PENDING-COUNT
               END-IF
           END-IF

           ADD 1 TO WS-TICKET-NUM
           STRING
               'TKT' DELIMITED BY SIZE
               WS-RUN-MODE DELIMITED BY SIZE
               WS-TICKET-NUM DELIMITED BY SIZE
               INTO ACT-STAT-TICKET
           END-STRING

           STRING
               'STATUS=' DELIMITED BY SIZE
               ACT-STAT-STATUS DELIMITED BY SIZE
               ' OWNER=' DELIMITED BY SIZE
               ACT-STAT-OWNER DELIMITED BY SIZE
               ' | ' DELIMITED BY SIZE
               REC-ACT-REASON DELIMITED BY SIZE
               INTO ACT-STAT-REASON
           END-STRING

           WRITE ACT-STAT-REC.

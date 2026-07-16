       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR480.
      *---------------------------------------------------------------*
      * Remediation recommendation engine.
      * Inputs:
      * - risk alerts (ORDR470)
      * - restart plan (ORDR460)
      * - remediation policy rules
      * Outputs:
      * - ranked recommended actions for operations
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-RISK ASSIGN TO ORDRRSK
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-PLAN ASSIGN TO ORDRPLN
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-RULE ASSIGN TO REMRULE
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-ACTION ASSIGN TO ORDRACT
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-RISK
           RECORD CONTAINS 220 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RISKALR1.

       FD  IN-PLAN
           RECORD CONTAINS 160 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RSTRPLN1.

       FD  IN-RULE
           RECORD CONTAINS 120 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY REMRULE1.

       FD  OUT-ACTION
           RECORD CONTAINS 220 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RECACT01.

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-END-RISK                PIC X VALUE 'N'.
              88 END-OF-RISK             VALUE 'Y'.
           05 WS-END-RULE                PIC X VALUE 'N'.
              88 END-OF-RULE             VALUE 'Y'.

       01  WS-RUN.
           05 WS-RUN-ID                  PIC X(8) VALUE 'ORDR480 '.
           05 WS-PLAN-STAGE              PIC X(8) VALUE 'NONE    '.
           05 WS-PLAN-ACTION             PIC X(20) VALUE SPACES.

       01  WS-COUNTERS.
           05 WS-RISK-READ               PIC 9(9) VALUE ZERO.
           05 WS-RULE-READ               PIC 9(9) VALUE ZERO.
           05 WS-ACTIONS-WRITTEN         PIC 9(9) VALUE ZERO.

       01  WS-RULE-TABLE.
           05 WS-RULE-ENTRY OCCURS 30 TIMES
              INDEXED BY RULE-IDX.
               10 WS-RULE-SEVERITY       PIC X(1).
               10 WS-RULE-ROUTE          PIC X(8).
               10 WS-RULE-ACTION         PIC X(20).
               10 WS-RULE-AUTO           PIC X(1).
               10 WS-RULE-PRIORITY       PIC 9(2).
               10 WS-RULE-MESSAGE        PIC X(60).

       01  WS-RULE-LOADED                PIC 9(3) VALUE ZERO.
       01  WS-MATCH-FOUND                PIC X VALUE 'N'.

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR480 RUNNING ***'
           OPEN INPUT IN-RISK IN-PLAN IN-RULE
                OUTPUT OUT-ACTION

           PERFORM LOAD-PLAN
           PERFORM LOAD-RULES
           PERFORM BUILD-ACTIONS
           PERFORM WRITE-PLAN-ACTION

           CLOSE IN-RISK IN-PLAN IN-RULE OUT-ACTION

           DISPLAY 'ORDR480 RISK READ      : ' WS-RISK-READ
           DISPLAY 'ORDR480 RULE READ      : ' WS-RULE-READ
           DISPLAY 'ORDR480 ACTION WRITTEN : ' WS-ACTIONS-WRITTEN

           GOBACK.

       LOAD-PLAN.
           READ IN-PLAN
               AT END
                   CONTINUE
               NOT AT END
                   MOVE RST-PLAN-RUN-ID TO WS-RUN-ID
                   MOVE RST-PLAN-NEXT-STAGE TO WS-PLAN-STAGE
                   MOVE RST-PLAN-ACTION TO WS-PLAN-ACTION
           END-READ.

       LOAD-RULES.
           PERFORM UNTIL END-OF-RULE
               READ IN-RULE
                   AT END
                       SET END-OF-RULE TO TRUE
                   NOT AT END
                       ADD 1 TO WS-RULE-READ
                       ADD 1 TO WS-RULE-LOADED
                       MOVE REM-RULE-SEVERITY
                         TO WS-RULE-SEVERITY (WS-RULE-LOADED)
                       MOVE REM-RULE-ROUTE
                         TO WS-RULE-ROUTE (WS-RULE-LOADED)
                       MOVE REM-RULE-ACTION
                         TO WS-RULE-ACTION (WS-RULE-LOADED)
                       MOVE REM-RULE-AUTO-FLAG
                         TO WS-RULE-AUTO (WS-RULE-LOADED)
                       MOVE REM-RULE-PRIORITY
                         TO WS-RULE-PRIORITY (WS-RULE-LOADED)
                       MOVE REM-RULE-MESSAGE
                         TO WS-RULE-MESSAGE (WS-RULE-LOADED)
               END-READ
           END-PERFORM.

       BUILD-ACTIONS.
           PERFORM UNTIL END-OF-RISK
               READ IN-RISK
                   AT END
                       SET END-OF-RISK TO TRUE
                   NOT AT END
                       ADD 1 TO WS-RISK-READ
                       PERFORM MAP-RISK-TO-ACTION
               END-READ
           END-PERFORM.

       MAP-RISK-TO-ACTION.
           MOVE 'N' TO WS-MATCH-FOUND

           PERFORM VARYING RULE-IDX FROM 1 BY 1
             UNTIL RULE-IDX > WS-RULE-LOADED OR WS-MATCH-FOUND = 'Y'
               IF RISK-SEVERITY = WS-RULE-SEVERITY (RULE-IDX)
                  AND RISK-ROUTE = WS-RULE-ROUTE (RULE-IDX)
                   MOVE 'Y' TO WS-MATCH-FOUND
               END-IF
           END-PERFORM

           MOVE SPACES TO REC-ACT-REC
           MOVE WS-RUN-ID TO REC-ACT-RUN-ID
           MOVE 'RISK      ' TO REC-ACT-SOURCE
           MOVE RISK-SEVERITY TO REC-ACT-SEVERITY
           MOVE RISK-ROUTE TO REC-ACT-ROUTE
           MOVE WS-PLAN-STAGE TO REC-ACT-TARGET-STAGE

           IF WS-MATCH-FOUND = 'Y'
               MOVE WS-RULE-PRIORITY (RULE-IDX) TO REC-ACT-PRIORITY
               MOVE WS-RULE-ACTION (RULE-IDX) TO REC-ACT-ACTION
               MOVE WS-RULE-AUTO (RULE-IDX) TO REC-ACT-AUTO-FLAG
               STRING
                   RISK-MESSAGE DELIMITED BY SIZE
                   ' | POLICY=' DELIMITED BY SIZE
                   WS-RULE-MESSAGE (RULE-IDX) DELIMITED BY SIZE
                   INTO REC-ACT-REASON
               END-STRING
           ELSE
               MOVE 99 TO REC-ACT-PRIORITY
               MOVE 'MANUAL-TRIAGE        ' TO REC-ACT-ACTION
               MOVE 'N' TO REC-ACT-AUTO-FLAG
               MOVE 'NO POLICY MATCH - MANUAL TRIAGE REQUIRED'
                 TO REC-ACT-REASON
           END-IF

           WRITE REC-ACT-REC
           ADD 1 TO WS-ACTIONS-WRITTEN.

       WRITE-PLAN-ACTION.
           MOVE SPACES TO REC-ACT-REC
           MOVE WS-RUN-ID TO REC-ACT-RUN-ID
           MOVE 'PLAN      ' TO REC-ACT-SOURCE
           MOVE '1' TO REC-ACT-SEVERITY
           MOVE 'RUNCTRL ' TO REC-ACT-ROUTE
           MOVE 1 TO REC-ACT-PRIORITY
           MOVE 'EXECUTE-RESTART      ' TO REC-ACT-ACTION
           MOVE 'N' TO REC-ACT-AUTO-FLAG
           MOVE WS-PLAN-STAGE TO REC-ACT-TARGET-STAGE
           STRING
               'RESTART DECISION: ' DELIMITED BY SIZE
               WS-PLAN-ACTION DELIMITED BY SIZE
               ' | STAGE=' DELIMITED BY SIZE
               WS-PLAN-STAGE DELIMITED BY SIZE
               INTO REC-ACT-REASON
           END-STRING

           WRITE REC-ACT-REC
           ADD 1 TO WS-ACTIONS-WRITTEN.

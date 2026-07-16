       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR400.
      *---------------------------------------------------------------*
      * Reconcile actual controls (ORDR300) against expected controls.
      * - count metrics: exact match
      * - amount metrics: tolerance-based match
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-ACTUAL ASSIGN TO ORDRCTL
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-EXPECT ASSIGN TO ORDRXCT
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-CONFIG ASSIGN TO RUNCFG
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-AUDIT ASSIGN TO ORDRAUD
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-ACTUAL
           RECORD CONTAINS 120 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       01  ACT-CTL-REC.
           05 ACT-CTL-RUN-ID            PIC X(8).
           05 ACT-CTL-METRIC            PIC X(20).
           05 ACT-CTL-CHANNEL           PIC X(10).
           05 ACT-CTL-MEASURE-TYPE      PIC X(1).
           05 ACT-CTL-COUNT-VALUE       PIC 9(9).
           05 ACT-CTL-AMOUNT-VALUE      PIC 9(13)V99.
           05 ACT-CTL-FILLER            PIC X(57).

       FD  IN-EXPECT
           RECORD CONTAINS 120 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       01  EXP-CTL-REC.
           05 EXP-CTL-RUN-ID            PIC X(8).
           05 EXP-CTL-METRIC            PIC X(20).
           05 EXP-CTL-CHANNEL           PIC X(10).
           05 EXP-CTL-MEASURE-TYPE      PIC X(1).
           05 EXP-CTL-COUNT-VALUE       PIC 9(9).
           05 EXP-CTL-AMOUNT-VALUE      PIC 9(13)V99.
           05 EXP-CTL-FILLER            PIC X(57).

       FD  IN-CONFIG
           RECORD CONTAINS 80 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RUNCFG01.

       FD  OUT-AUDIT
           RECORD CONTAINS 220 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       01  OUT-AUDIT-REC                  PIC X(220).

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-END-ACT                 PIC X VALUE 'N'.
              88 END-OF-ACT              VALUE 'Y'.
           05 WS-END-EXP                 PIC X VALUE 'N'.
              88 END-OF-EXP              VALUE 'Y'.

       01  WS-COUNTERS.
           05 WS-ACT-READ                PIC 9(9) VALUE ZERO.
           05 WS-EXP-READ                PIC 9(9) VALUE ZERO.
           05 WS-PASS                    PIC 9(9) VALUE ZERO.
           05 WS-FAIL                    PIC 9(9) VALUE ZERO.
           05 WS-MISS                    PIC 9(9) VALUE ZERO.

       01  WS-LIMITS.
           05 WS-AMOUNT-TOLERANCE        PIC 9(7)V99 VALUE 500.00.
           05 WS-RUN-MODE                PIC X(3) VALUE 'EOD'.
           05 WS-STRICT-FLAG             PIC X VALUE 'N'.

       01  WS-EXPECTED-TABLE.
           05 WS-EXP-ENTRY OCCURS 100 TIMES
              INDEXED BY EXP-IDX.
               10 WS-EXP-METRIC          PIC X(20).
               10 WS-EXP-CHANNEL         PIC X(10).
               10 WS-EXP-TYPE            PIC X(1).
               10 WS-EXP-COUNT           PIC 9(9).
               10 WS-EXP-AMOUNT          PIC 9(13)V99.
               10 WS-EXP-MATCHED         PIC X(1).

       01  WS-EXP-LOADED                 PIC 9(4) VALUE ZERO.
       01  WS-MATCH-FOUND                PIC X VALUE 'N'.
       01  WS-DELTA-AMOUNT               PIC S9(13)V99 VALUE ZERO.
       01  WS-ABS-DELTA                  PIC 9(13)V99 VALUE ZERO.
       01  WS-MESSAGE                    PIC X(220).

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR400 RUNNING ***'
           OPEN INPUT IN-ACTUAL IN-EXPECT IN-CONFIG
                OUTPUT OUT-AUDIT

           PERFORM LOAD-RUN-CONFIG

           PERFORM LOAD-EXPECTED
           PERFORM RECONCILE-ACTUAL
           PERFORM CHECK-MISSING-EXPECTED
           PERFORM WRITE-SUMMARY

           CLOSE IN-ACTUAL IN-EXPECT IN-CONFIG OUT-AUDIT

           DISPLAY 'ORDR400 ACTUAL READ   : ' WS-ACT-READ
           DISPLAY 'ORDR400 EXPECTED READ : ' WS-EXP-READ
           DISPLAY 'ORDR400 PASS          : ' WS-PASS
           DISPLAY 'ORDR400 FAIL          : ' WS-FAIL
           DISPLAY 'ORDR400 MISSING       : ' WS-MISS
           DISPLAY 'ORDR400 MODE          : ' WS-RUN-MODE
           DISPLAY 'ORDR400 TOLERANCE     : ' WS-AMOUNT-TOLERANCE

           IF WS-FAIL > ZERO OR WS-MISS > ZERO
               IF WS-STRICT-FLAG = 'Y'
                   MOVE 12 TO RETURN-CODE
               ELSE
                   MOVE 8 TO RETURN-CODE
               END-IF
           END-IF

           GOBACK.

       LOAD-RUN-CONFIG.
           READ IN-CONFIG
               AT END
                   CONTINUE
               NOT AT END
                   MOVE RUN-CFG-RUN-MODE TO WS-RUN-MODE
                   MOVE RUN-CFG-AMOUNT-TOL TO WS-AMOUNT-TOLERANCE
                   MOVE RUN-CFG-STRICT-FLAG TO WS-STRICT-FLAG
           END-READ.

       LOAD-EXPECTED.
           PERFORM UNTIL END-OF-EXP
               READ IN-EXPECT
                   AT END
                       SET END-OF-EXP TO TRUE
                   NOT AT END
                       ADD 1 TO WS-EXP-READ
                       ADD 1 TO WS-EXP-LOADED
                       MOVE EXP-CTL-METRIC TO WS-EXP-METRIC (WS-EXP-LOADED)
                       MOVE EXP-CTL-CHANNEL TO WS-EXP-CHANNEL (WS-EXP-LOADED)
                       MOVE EXP-CTL-MEASURE-TYPE TO WS-EXP-TYPE (WS-EXP-LOADED)
                       MOVE EXP-CTL-COUNT-VALUE TO WS-EXP-COUNT (WS-EXP-LOADED)
                       MOVE EXP-CTL-AMOUNT-VALUE TO WS-EXP-AMOUNT (WS-EXP-LOADED)
                       MOVE 'N' TO WS-EXP-MATCHED (WS-EXP-LOADED)
               END-READ
           END-PERFORM.

       RECONCILE-ACTUAL.
           PERFORM UNTIL END-OF-ACT
               READ IN-ACTUAL
                   AT END
                       SET END-OF-ACT TO TRUE
                   NOT AT END
                       ADD 1 TO WS-ACT-READ
                       PERFORM RECONCILE-ONE
               END-READ
           END-PERFORM.

       RECONCILE-ONE.
           MOVE 'N' TO WS-MATCH-FOUND

           PERFORM VARYING EXP-IDX FROM 1 BY 1
             UNTIL EXP-IDX > WS-EXP-LOADED OR WS-MATCH-FOUND = 'Y'
                    IF ACT-CTL-METRIC = WS-EXP-METRIC (EXP-IDX)
                        AND ACT-CTL-CHANNEL = WS-EXP-CHANNEL (EXP-IDX)
                        AND ACT-CTL-MEASURE-TYPE = WS-EXP-TYPE (EXP-IDX)
                   MOVE 'Y' TO WS-MATCH-FOUND
                   MOVE 'Y' TO WS-EXP-MATCHED (EXP-IDX)
               END-IF
           END-PERFORM

           IF WS-MATCH-FOUND NOT = 'Y'
               ADD 1 TO WS-FAIL
               MOVE SPACES TO OUT-AUDIT-REC
               STRING
                   'FAIL | UNEXPECTED METRIC | '
                   ACT-CTL-METRIC ' | '
                   ACT-CTL-CHANNEL
                   DELIMITED BY SIZE INTO OUT-AUDIT-REC
               END-STRING
               WRITE OUT-AUDIT-REC
           ELSE
               IF ACT-CTL-MEASURE-TYPE = 'C'
                   IF ACT-CTL-COUNT-VALUE = WS-EXP-COUNT (EXP-IDX)
                       ADD 1 TO WS-PASS
                       MOVE SPACES TO OUT-AUDIT-REC
                       STRING
                           'PASS | COUNT | '
                           ACT-CTL-METRIC ' | '
                           ACT-CTL-CHANNEL
                           DELIMITED BY SIZE INTO OUT-AUDIT-REC
                       END-STRING
                       WRITE OUT-AUDIT-REC
                   ELSE
                       ADD 1 TO WS-FAIL
                       MOVE SPACES TO OUT-AUDIT-REC
                       STRING
                           'FAIL | COUNT MISMATCH | '
                           ACT-CTL-METRIC ' | '
                           ACT-CTL-CHANNEL
                           DELIMITED BY SIZE INTO OUT-AUDIT-REC
                       END-STRING
                       WRITE OUT-AUDIT-REC
                   END-IF
               ELSE
                   COMPUTE WS-DELTA-AMOUNT =
                     ACT-CTL-AMOUNT-VALUE - WS-EXP-AMOUNT (EXP-IDX)
                   IF WS-DELTA-AMOUNT < ZERO
                       COMPUTE WS-ABS-DELTA = WS-DELTA-AMOUNT * -1
                   ELSE
                       MOVE WS-DELTA-AMOUNT TO WS-ABS-DELTA
                   END-IF

                   IF WS-ABS-DELTA <= WS-AMOUNT-TOLERANCE
                       ADD 1 TO WS-PASS
                       MOVE SPACES TO OUT-AUDIT-REC
                       STRING
                           'PASS | AMOUNT | '
                           ACT-CTL-METRIC ' | '
                           ACT-CTL-CHANNEL
                           DELIMITED BY SIZE INTO OUT-AUDIT-REC
                       END-STRING
                       WRITE OUT-AUDIT-REC
                   ELSE
                       ADD 1 TO WS-FAIL
                       MOVE SPACES TO OUT-AUDIT-REC
                       STRING
                           'FAIL | AMOUNT DELTA > TOLERANCE | '
                           ACT-CTL-METRIC ' | '
                           ACT-CTL-CHANNEL
                           DELIMITED BY SIZE INTO OUT-AUDIT-REC
                       END-STRING
                       WRITE OUT-AUDIT-REC
                   END-IF
               END-IF
           END-IF.

       CHECK-MISSING-EXPECTED.
           PERFORM VARYING EXP-IDX FROM 1 BY 1
             UNTIL EXP-IDX > WS-EXP-LOADED
               IF WS-EXP-MATCHED (EXP-IDX) NOT = 'Y'
                   ADD 1 TO WS-MISS
                   MOVE SPACES TO OUT-AUDIT-REC
                   STRING
                       'FAIL | MISSING ACTUAL METRIC | '
                       WS-EXP-METRIC (EXP-IDX) ' | '
                       WS-EXP-CHANNEL (EXP-IDX)
                       DELIMITED BY SIZE INTO OUT-AUDIT-REC
                   END-STRING
                   WRITE OUT-AUDIT-REC
               END-IF
           END-PERFORM.

       WRITE-SUMMARY.
           MOVE SPACES TO OUT-AUDIT-REC
           STRING
               'SUMMARY | PASS=' WS-PASS
               ' FAIL=' WS-FAIL
               ' MISSING=' WS-MISS
               DELIMITED BY SIZE INTO OUT-AUDIT-REC
           END-STRING
           WRITE OUT-AUDIT-REC.

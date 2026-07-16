       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR530.
      *---------------------------------------------------------------*
      * KPI trend drift detector.
      * Inputs:
      * - current KPI feed (ORDR520)
      * - historical KPI baselines
      * - runtime policy (anomaly percentage threshold)
      * Output:
      * - KPI trend alerts for governance drift
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-KPI ASSIGN TO ORDRKPI
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-HST ASSIGN TO KPIHST
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-CFG ASSIGN TO RUNCFG
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-TRD ASSIGN TO ORDRKTR
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-KPI
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY KPIRPT1.

       FD  IN-HST
           RECORD CONTAINS 120 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY KPIHST1.

       FD  IN-CFG
           RECORD CONTAINS 80 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RUNCFG01.

       FD  OUT-TRD
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY KPITRD1.

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-END-KPI                 PIC X VALUE 'N'.
              88 END-OF-KPI              VALUE 'Y'.
           05 WS-END-HST                 PIC X VALUE 'N'.
              88 END-OF-HST              VALUE 'Y'.

       01  WS-CFG.
           05 WS-DELTA-THRESHOLD         PIC 9(3)V99 VALUE 20.00.

       01  WS-HIST-TABLE.
           05 WS-HIST-ENTRY OCCURS 50 TIMES
              INDEXED BY HST-IDX.
               10 WS-HIST-METRIC         PIC X(20).
               10 WS-HIST-AVG-COUNT      PIC 9(9).
               10 WS-HIST-AVG-AMOUNT     PIC 9(13)V99.
               10 WS-HIST-AVG-RATE       PIC 9(3)V99.

           01  WS-HIST-ROWS                  PIC 9(3) VALUE ZERO.
       01  WS-HIT                        PIC X VALUE 'N'.
       01  WS-CALC.
           05 WS-DELTA-BASE              PIC 9(13)V99 VALUE ZERO.
           05 WS-DELTA-VALUE             PIC 9(13)V99 VALUE ZERO.
           05 WS-DELTA-PCT               PIC 9(3)V99 VALUE ZERO.

       01  WS-RUN.
           05 WS-RUN-ID                  PIC X(8) VALUE 'ORDR530 '.

       01  WS-COUNTERS.
           05 WS-KPI-READ                PIC 9(9) VALUE ZERO.
           05 WS-ALERT-WRITTEN           PIC 9(9) VALUE ZERO.

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR530 RUNNING ***'
           OPEN INPUT IN-KPI IN-HST IN-CFG
                OUTPUT OUT-TRD

           PERFORM LOAD-CONFIG
           PERFORM LOAD-HISTORY
           PERFORM EVALUATE-KPI

           CLOSE IN-KPI IN-HST IN-CFG OUT-TRD

           DISPLAY 'ORDR530 KPI READ      : ' WS-KPI-READ
           DISPLAY 'ORDR530 ALERT WRITTEN : ' WS-ALERT-WRITTEN

           GOBACK.

       LOAD-CONFIG.
           READ IN-CFG
               AT END
                   CONTINUE
               NOT AT END
                   MOVE RUN-CFG-ANOMALY-PCT TO WS-DELTA-THRESHOLD
           END-READ.

       LOAD-HISTORY.
           PERFORM UNTIL END-OF-HST
               READ IN-HST
                   AT END
                       SET END-OF-HST TO TRUE
                   NOT AT END
                       ADD 1 TO WS-HIST-ROWS
                       MOVE KPI-HST-METRIC TO WS-HIST-METRIC (WS-HIST-ROWS)
                       MOVE KPI-HST-AVG-COUNT TO WS-HIST-AVG-COUNT (WS-HIST-ROWS)
                       MOVE KPI-HST-AVG-AMOUNT TO WS-HIST-AVG-AMOUNT (WS-HIST-ROWS)
                       MOVE KPI-HST-AVG-RATE TO WS-HIST-AVG-RATE (WS-HIST-ROWS)
               END-READ
           END-PERFORM.

       EVALUATE-KPI.
           PERFORM UNTIL END-OF-KPI
               READ IN-KPI
                   AT END
                       SET END-OF-KPI TO TRUE
                   NOT AT END
                       ADD 1 TO WS-KPI-READ
                       MOVE KPI-RPT-RUN-ID TO WS-RUN-ID
                       PERFORM FIND-HISTORY
                       IF WS-HIT = 'Y'
                           PERFORM CHECK-ONE-METRIC
                       END-IF
               END-READ
           END-PERFORM.

       FIND-HISTORY.
           MOVE 'N' TO WS-HIT
           PERFORM VARYING HST-IDX FROM 1 BY 1
                         UNTIL HST-IDX > WS-HIST-ROWS OR WS-HIT = 'Y'
               IF KPI-RPT-METRIC = WS-HIST-METRIC (HST-IDX)
                   MOVE 'Y' TO WS-HIT
               END-IF
           END-PERFORM.

       CHECK-ONE-METRIC.
           MOVE ZERO TO WS-DELTA-PCT

           IF KPI-RPT-RATE > 0 AND WS-HIST-AVG-RATE (HST-IDX) > 0
               MOVE WS-HIST-AVG-RATE (HST-IDX) TO WS-DELTA-BASE
               COMPUTE WS-DELTA-VALUE =
                   FUNCTION ABS(KPI-RPT-RATE - WS-HIST-AVG-RATE (HST-IDX))
               COMPUTE WS-DELTA-PCT =
                   (WS-DELTA-VALUE * 100) / WS-DELTA-BASE
           ELSE
               IF KPI-RPT-COUNT > 0 AND WS-HIST-AVG-COUNT (HST-IDX) > 0
                   MOVE WS-HIST-AVG-COUNT (HST-IDX) TO WS-DELTA-BASE
                   COMPUTE WS-DELTA-VALUE =
                       FUNCTION ABS(KPI-RPT-COUNT - WS-HIST-AVG-COUNT (HST-IDX))
                   COMPUTE WS-DELTA-PCT =
                       (WS-DELTA-VALUE * 100) / WS-DELTA-BASE
               END-IF
           END-IF

           IF WS-DELTA-PCT > WS-DELTA-THRESHOLD
               PERFORM WRITE-ALERT
           END-IF.

       WRITE-ALERT.
           MOVE SPACES TO KPI-TRD-REC
           MOVE WS-RUN-ID TO KPI-TRD-RUN-ID
           MOVE KPI-RPT-METRIC TO KPI-TRD-METRIC
           MOVE KPI-RPT-CATEGORY TO KPI-TRD-CATEGORY
           MOVE KPI-RPT-COUNT TO KPI-TRD-CURR-COUNT
           MOVE WS-HIST-AVG-COUNT (HST-IDX) TO KPI-TRD-BASE-COUNT
           MOVE KPI-RPT-AMOUNT TO KPI-TRD-CURR-AMOUNT
           MOVE WS-HIST-AVG-AMOUNT (HST-IDX) TO KPI-TRD-BASE-AMOUNT
           MOVE KPI-RPT-RATE TO KPI-TRD-CURR-RATE
           MOVE WS-HIST-AVG-RATE (HST-IDX) TO KPI-TRD-BASE-RATE
           MOVE WS-DELTA-PCT TO KPI-TRD-DELTA-PCT

           IF WS-DELTA-PCT > WS-DELTA-THRESHOLD * 2
               MOVE '1' TO KPI-TRD-SEVERITY
           ELSE
               MOVE '2' TO KPI-TRD-SEVERITY
           END-IF

           STRING
               'KPI DRIFT DETECTED. DELTA=' DELIMITED BY SIZE
               WS-DELTA-PCT DELIMITED BY SIZE
               ' THRESHOLD=' DELIMITED BY SIZE
               WS-DELTA-THRESHOLD DELIMITED BY SIZE
               INTO KPI-TRD-MESSAGE
           END-STRING

           WRITE KPI-TRD-REC
           ADD 1 TO WS-ALERT-WRITTEN.

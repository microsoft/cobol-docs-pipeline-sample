       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR470.
      *---------------------------------------------------------------*
      * Trend and anomaly detection on control metrics.
      * - compares current controls with historical averages
      * - emits risk alerts when delta percentage is above threshold
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-CURRENT ASSIGN TO ORDRCTL
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-HISTORY ASSIGN TO HISTCTL
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-CONFIG ASSIGN TO RUNCFG
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-RISK ASSIGN TO ORDRRSK
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-CURRENT
           RECORD CONTAINS 120 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY ORDRCTL1.

       FD  IN-HISTORY
           RECORD CONTAINS 120 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       01  HIST-CTL-REC.
           05 HIST-CTL-RUN-ID            PIC X(8).
           05 HIST-CTL-METRIC            PIC X(20).
           05 HIST-CTL-CHANNEL           PIC X(10).
           05 HIST-CTL-MEASURE-TYPE      PIC X(1).
           05 HIST-CTL-COUNT-VALUE       PIC 9(9).
           05 HIST-CTL-AMOUNT-VALUE      PIC 9(13)V99.
           05 HIST-CTL-FILLER            PIC X(57).

       FD  IN-CONFIG
           RECORD CONTAINS 80 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RUNCFG01.

       FD  OUT-RISK
           RECORD CONTAINS 220 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RISKALR1.

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-END-CUR                 PIC X VALUE 'N'.
              88 END-OF-CUR              VALUE 'Y'.
           05 WS-END-HIS                 PIC X VALUE 'N'.
              88 END-OF-HIS              VALUE 'Y'.

       01  WS-RUN.
           05 WS-RUN-ID                  PIC X(8) VALUE 'ORDR470 '.
           05 WS-ANOMALY-PCT             PIC 9(3)V99 VALUE 15.00.

       01  WS-COUNTERS.
           05 WS-CUR-READ                PIC 9(9) VALUE ZERO.
           05 WS-HIS-READ                PIC 9(9) VALUE ZERO.
           05 WS-RISK-WRITTEN            PIC 9(9) VALUE ZERO.

       01  WS-HIST-TABLE.
           05 WS-HIST-ENTRY OCCURS 300 TIMES
              INDEXED BY HIS-IDX.
               10 WS-HIST-METRIC         PIC X(20).
               10 WS-HIST-CHANNEL        PIC X(10).
               10 WS-HIST-TYPE           PIC X(1).
               10 WS-HIST-OBS            PIC 9(5).
               10 WS-HIST-CNT-SUM        PIC 9(11).
               10 WS-HIST-AMT-SUM        PIC 9(15)V99.

       01  WS-HIST-KEYS                  PIC 9(4) VALUE ZERO.
       01  WS-MATCH-FOUND                PIC X VALUE 'N'.
       01  WS-AVG-COUNT                  PIC 9(9) VALUE ZERO.
       01  WS-AVG-AMOUNT                 PIC 9(13)V99 VALUE ZERO.
       01  WS-DELTA-PCT                  PIC 9(3)V99 VALUE ZERO.
       01  WS-DELTA-AMT                  PIC S9(13)V99 VALUE ZERO.
       01  WS-ABS-AMT                    PIC 9(13)V99 VALUE ZERO.
       01  WS-DELTA-CNT                  PIC S9(9) VALUE ZERO.
       01  WS-ABS-CNT                    PIC 9(9) VALUE ZERO.

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR470 RUNNING ***'
           OPEN INPUT IN-CURRENT IN-HISTORY IN-CONFIG
                OUTPUT OUT-RISK

           PERFORM LOAD-CONFIG
           PERFORM LOAD-HISTORY
           PERFORM ANALYZE-CURRENT

           CLOSE IN-CURRENT IN-HISTORY IN-CONFIG OUT-RISK

           DISPLAY 'ORDR470 CURRENT READ : ' WS-CUR-READ
           DISPLAY 'ORDR470 HISTORY READ : ' WS-HIS-READ
           DISPLAY 'ORDR470 RISK WRITTEN : ' WS-RISK-WRITTEN

           GOBACK.

       LOAD-CONFIG.
           READ IN-CONFIG
               AT END
                   CONTINUE
               NOT AT END
                   MOVE RUN-CFG-ANOMALY-PCT TO WS-ANOMALY-PCT
           END-READ.

       LOAD-HISTORY.
           PERFORM UNTIL END-OF-HIS
               READ IN-HISTORY
                   AT END
                       SET END-OF-HIS TO TRUE
                   NOT AT END
                       ADD 1 TO WS-HIS-READ
                       PERFORM ACCUMULATE-HISTORY
               END-READ
           END-PERFORM.

       ACCUMULATE-HISTORY.
           MOVE 'N' TO WS-MATCH-FOUND

           PERFORM VARYING HIS-IDX FROM 1 BY 1
             UNTIL HIS-IDX > WS-HIST-KEYS OR WS-MATCH-FOUND = 'Y'
               IF HIST-CTL-METRIC = WS-HIST-METRIC (HIS-IDX)
                  AND HIST-CTL-CHANNEL = WS-HIST-CHANNEL (HIS-IDX)
                  AND HIST-CTL-MEASURE-TYPE = WS-HIST-TYPE (HIS-IDX)
                   MOVE 'Y' TO WS-MATCH-FOUND
               END-IF
           END-PERFORM

           IF WS-MATCH-FOUND = 'Y'
               ADD 1 TO WS-HIST-OBS (HIS-IDX)
               ADD HIST-CTL-COUNT-VALUE TO WS-HIST-CNT-SUM (HIS-IDX)
               ADD HIST-CTL-AMOUNT-VALUE TO WS-HIST-AMT-SUM (HIS-IDX)
           ELSE
               ADD 1 TO WS-HIST-KEYS
               MOVE HIST-CTL-METRIC TO WS-HIST-METRIC (WS-HIST-KEYS)
               MOVE HIST-CTL-CHANNEL TO WS-HIST-CHANNEL (WS-HIST-KEYS)
               MOVE HIST-CTL-MEASURE-TYPE TO WS-HIST-TYPE (WS-HIST-KEYS)
               MOVE 1 TO WS-HIST-OBS (WS-HIST-KEYS)
               MOVE HIST-CTL-COUNT-VALUE TO WS-HIST-CNT-SUM (WS-HIST-KEYS)
               MOVE HIST-CTL-AMOUNT-VALUE TO WS-HIST-AMT-SUM (WS-HIST-KEYS)
           END-IF.

       ANALYZE-CURRENT.
           PERFORM UNTIL END-OF-CUR
               READ IN-CURRENT
                   AT END
                       SET END-OF-CUR TO TRUE
                   NOT AT END
                       ADD 1 TO WS-CUR-READ
                       PERFORM EVALUATE-CURRENT-ROW
               END-READ
           END-PERFORM.

       EVALUATE-CURRENT-ROW.
           MOVE 'N' TO WS-MATCH-FOUND
           MOVE ZERO TO WS-AVG-COUNT WS-AVG-AMOUNT WS-DELTA-PCT

           PERFORM VARYING HIS-IDX FROM 1 BY 1
             UNTIL HIS-IDX > WS-HIST-KEYS OR WS-MATCH-FOUND = 'Y'
               IF ORDR-CTL-METRIC = WS-HIST-METRIC (HIS-IDX)
                  AND ORDR-CTL-CHANNEL = WS-HIST-CHANNEL (HIS-IDX)
                  AND ORDR-CTL-MEASURE-TYPE = WS-HIST-TYPE (HIS-IDX)
                   MOVE 'Y' TO WS-MATCH-FOUND
               END-IF
           END-PERFORM

           IF WS-MATCH-FOUND = 'Y'
               IF ORDR-CTL-MEASURE-TYPE = 'C'
                   COMPUTE WS-AVG-COUNT =
                     WS-HIST-CNT-SUM (HIS-IDX) / WS-HIST-OBS (HIS-IDX)
                   IF WS-AVG-COUNT > ZERO
                       COMPUTE WS-DELTA-CNT =
                         ORDR-CTL-COUNT-VALUE - WS-AVG-COUNT
                       IF WS-DELTA-CNT < ZERO
                           COMPUTE WS-ABS-CNT = WS-DELTA-CNT * -1
                       ELSE
                           MOVE WS-DELTA-CNT TO WS-ABS-CNT
                       END-IF
                       COMPUTE WS-DELTA-PCT =
                         (WS-ABS-CNT * 100) / WS-AVG-COUNT
                   END-IF
               ELSE
                   COMPUTE WS-AVG-AMOUNT =
                     WS-HIST-AMT-SUM (HIS-IDX) / WS-HIST-OBS (HIS-IDX)
                   IF WS-AVG-AMOUNT > ZERO
                       COMPUTE WS-DELTA-AMT =
                         ORDR-CTL-AMOUNT-VALUE - WS-AVG-AMOUNT
                       IF WS-DELTA-AMT < ZERO
                           COMPUTE WS-ABS-AMT = WS-DELTA-AMT * -1
                       ELSE
                           MOVE WS-DELTA-AMT TO WS-ABS-AMT
                       END-IF
                       COMPUTE WS-DELTA-PCT =
                         (WS-ABS-AMT * 100) / WS-AVG-AMOUNT
                   END-IF
               END-IF

               IF WS-DELTA-PCT >= WS-ANOMALY-PCT
                   PERFORM WRITE-RISK-ALERT
               END-IF
           END-IF.

       WRITE-RISK-ALERT.
           MOVE SPACES TO RISK-ALERT-REC
           MOVE WS-RUN-ID TO RISK-RUN-ID
           MOVE ORDR-CTL-METRIC TO RISK-METRIC
           MOVE ORDR-CTL-CHANNEL TO RISK-CHANNEL
           MOVE ORDR-CTL-MEASURE-TYPE TO RISK-MEASURE-TYPE
           MOVE ORDR-CTL-COUNT-VALUE TO RISK-CURRENT-COUNT
           MOVE WS-AVG-COUNT TO RISK-AVG-COUNT
           MOVE ORDR-CTL-AMOUNT-VALUE TO RISK-CURRENT-AMOUNT
           MOVE WS-AVG-AMOUNT TO RISK-AVG-AMOUNT
           MOVE WS-DELTA-PCT TO RISK-DELTA-PCT

           IF WS-DELTA-PCT >= 40.00
               MOVE '1' TO RISK-SEVERITY
               MOVE 'RUNCTRL ' TO RISK-ROUTE
               MOVE 'EXTREME TREND VARIATION DETECTED' TO RISK-MESSAGE
           ELSE
               MOVE '2' TO RISK-SEVERITY
               MOVE 'DATAOPS ' TO RISK-ROUTE
               MOVE 'ANOMALY ABOVE CONFIGURED THRESHOLD' TO RISK-MESSAGE
           END-IF

           WRITE RISK-ALERT-REC
           ADD 1 TO WS-RISK-WRITTEN.

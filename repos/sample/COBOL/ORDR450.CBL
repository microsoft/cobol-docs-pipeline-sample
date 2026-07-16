       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR450.
      *---------------------------------------------------------------*
      * Post-run incident classification and checkpoint emission.
      * - scans reject streams + audit stream
      * - routes incidents by severity and category
      * - writes checkpoints for restart governance
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-RJ1 ASSIGN TO ORDRRJ1
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-RJ2 ASSIGN TO ORDRRJ2
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-RJ3 ASSIGN TO ORDRRJ3
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-AUD ASSIGN TO ORDRAUD
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-CONFIG ASSIGN TO RUNCFG
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-INC ASSIGN TO ORDRINC
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-CKP ASSIGN TO ORDRCKP
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-RJ1
           RECORD CONTAINS 220 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       01  RJ1-REC                        PIC X(220).

       FD  IN-RJ2
           RECORD CONTAINS 220 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       01  RJ2-REC                        PIC X(220).

       FD  IN-RJ3
           RECORD CONTAINS 300 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       01  RJ3-REC                        PIC X(300).

       FD  IN-AUD
           RECORD CONTAINS 220 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       01  AUD-REC                        PIC X(220).

       FD  IN-CONFIG
           RECORD CONTAINS 80 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RUNCFG01.

       FD  OUT-INC
           RECORD CONTAINS 220 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY INCDNT01.

       FD  OUT-CKP
           RECORD CONTAINS 120 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY CKPSTAT1.

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-END-RJ1                 PIC X VALUE 'N'.
              88 END-OF-RJ1              VALUE 'Y'.
           05 WS-END-RJ2                 PIC X VALUE 'N'.
              88 END-OF-RJ2              VALUE 'Y'.
           05 WS-END-RJ3                 PIC X VALUE 'N'.
              88 END-OF-RJ3              VALUE 'Y'.
           05 WS-END-AUD                 PIC X VALUE 'N'.
              88 END-OF-AUD              VALUE 'Y'.

       01  WS-RUNTIME.
           05 WS-RUN-MODE                PIC X(3) VALUE 'EOD'.
           05 WS-RUN-ID                  PIC X(8) VALUE 'ORDR450 '.

       01  WS-COUNTERS.
           05 WS-RJ1-CNT                 PIC 9(9) VALUE ZERO.
           05 WS-RJ2-CNT                 PIC 9(9) VALUE ZERO.
           05 WS-RJ3-CNT                 PIC 9(9) VALUE ZERO.
           05 WS-AUD-FAIL                PIC 9(9) VALUE ZERO.
           05 WS-INC-WRITTEN             PIC 9(9) VALUE ZERO.

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR450 RUNNING ***'
           OPEN INPUT IN-RJ1 IN-RJ2 IN-RJ3 IN-AUD IN-CONFIG
                OUTPUT OUT-INC OUT-CKP

           PERFORM LOAD-CONFIG
           PERFORM SCAN-RJ1
           PERFORM SCAN-RJ2
           PERFORM SCAN-RJ3
           PERFORM SCAN-AUD
           PERFORM WRITE-CHECKPOINTS

           CLOSE IN-RJ1 IN-RJ2 IN-RJ3 IN-AUD IN-CONFIG OUT-INC OUT-CKP

           DISPLAY 'ORDR450 RJ1 : ' WS-RJ1-CNT
           DISPLAY 'ORDR450 RJ2 : ' WS-RJ2-CNT
           DISPLAY 'ORDR450 RJ3 : ' WS-RJ3-CNT
           DISPLAY 'ORDR450 AUD-FAIL : ' WS-AUD-FAIL
           DISPLAY 'ORDR450 INCIDENTS : ' WS-INC-WRITTEN

           GOBACK.

       LOAD-CONFIG.
           READ IN-CONFIG
               AT END
                   CONTINUE
               NOT AT END
                   MOVE RUN-CFG-RUN-MODE TO WS-RUN-MODE
           END-READ.

       SCAN-RJ1.
           PERFORM UNTIL END-OF-RJ1
               READ IN-RJ1
                   AT END
                       SET END-OF-RJ1 TO TRUE
                   NOT AT END
                       ADD 1 TO WS-RJ1-CNT
                       PERFORM WRITE-INCIDENT
               END-READ
           END-PERFORM.

       SCAN-RJ2.
           PERFORM UNTIL END-OF-RJ2
               READ IN-RJ2
                   AT END
                       SET END-OF-RJ2 TO TRUE
                   NOT AT END
                       ADD 1 TO WS-RJ2-CNT
                       PERFORM WRITE-INCIDENT
               END-READ
           END-PERFORM.

       SCAN-RJ3.
           PERFORM UNTIL END-OF-RJ3
               READ IN-RJ3
                   AT END
                       SET END-OF-RJ3 TO TRUE
                   NOT AT END
                       ADD 1 TO WS-RJ3-CNT
                       PERFORM WRITE-INCIDENT
               END-READ
           END-PERFORM.

       SCAN-AUD.
           PERFORM UNTIL END-OF-AUD
               READ IN-AUD
                   AT END
                       SET END-OF-AUD TO TRUE
                   NOT AT END
                       IF AUD-REC(1:4) = 'FAIL'
                           ADD 1 TO WS-AUD-FAIL
                           PERFORM WRITE-AUDIT-INCIDENT
                       END-IF
               END-READ
           END-PERFORM.

       WRITE-INCIDENT.
           MOVE SPACES TO INC-REC
           MOVE WS-RUN-ID TO INC-RUN-ID
           MOVE 'REJECTS ' TO INC-SOURCE
           MOVE 'SEV2' TO INC-KEY
           MOVE '2' TO INC-SEVERITY
           MOVE 'DATAOPS ' TO INC-ROUTE-CODE
           MOVE 'RJ-STAGE' TO INC-STAGE
           MOVE 'REJECTED RECORD IN PIPELINE STAGE' TO INC-MESSAGE
           WRITE INC-REC
           ADD 1 TO WS-INC-WRITTEN.

       WRITE-AUDIT-INCIDENT.
           MOVE SPACES TO INC-REC
           MOVE WS-RUN-ID TO INC-RUN-ID
           MOVE 'AUDIT   ' TO INC-SOURCE
           MOVE 'SEV1' TO INC-KEY
           MOVE '1' TO INC-SEVERITY
           MOVE 'RUNCTRL ' TO INC-ROUTE-CODE
           MOVE 'AUDIT   ' TO INC-STAGE
           MOVE AUD-REC(1:120) TO INC-MESSAGE
           WRITE INC-REC
           ADD 1 TO WS-INC-WRITTEN.

       WRITE-CHECKPOINTS.
           MOVE SPACES TO CKP-REC
           MOVE WS-RUN-ID TO CKP-RUN-ID
           MOVE WS-RUN-MODE TO CKP-RUN-MODE
           MOVE '20260623090000' TO CKP-TS

           MOVE 'STG100  ' TO CKP-STAGE
           MOVE 'C' TO CKP-STATUS
           MOVE ZERO TO CKP-PROCESSED
           MOVE WS-RJ1-CNT TO CKP-REJECTED
           MOVE ZERO TO CKP-FAILED
           WRITE CKP-REC

           MOVE 'STG150  ' TO CKP-STAGE
           MOVE 'C' TO CKP-STATUS
           MOVE ZERO TO CKP-PROCESSED
           MOVE WS-RJ2-CNT TO CKP-REJECTED
           MOVE ZERO TO CKP-FAILED
           WRITE CKP-REC

           MOVE 'STG200  ' TO CKP-STAGE
           MOVE 'C' TO CKP-STATUS
           MOVE ZERO TO CKP-PROCESSED
           MOVE WS-RJ3-CNT TO CKP-REJECTED
           MOVE ZERO TO CKP-FAILED
           WRITE CKP-REC

           MOVE 'STG400  ' TO CKP-STAGE
           IF WS-AUD-FAIL > ZERO
               MOVE 'F' TO CKP-STATUS
           ELSE
               MOVE 'C' TO CKP-STATUS
           END-IF
           MOVE ZERO TO CKP-PROCESSED
           MOVE ZERO TO CKP-REJECTED
           MOVE WS-AUD-FAIL TO CKP-FAILED
           WRITE CKP-REC

           MOVE 'STG450  ' TO CKP-STAGE
           MOVE 'C' TO CKP-STATUS
           MOVE WS-INC-WRITTEN TO CKP-PROCESSED
           MOVE ZERO TO CKP-REJECTED
           MOVE ZERO TO CKP-FAILED
           WRITE CKP-REC.

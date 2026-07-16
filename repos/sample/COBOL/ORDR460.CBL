       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR460.
      *---------------------------------------------------------------*
      * Recovery orchestrator:
      * - reads checkpoints and incidents
      * - identifies earliest failed stage
      * - emits restart plan and escalation decisions
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-CKP ASSIGN TO ORDRCKP
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-INC ASSIGN TO ORDRINC
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-CONFIG ASSIGN TO RUNCFG
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-PLAN ASSIGN TO ORDRPLN
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-OPS ASSIGN TO ORDROPS
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-CKP
           RECORD CONTAINS 120 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY CKPSTAT1.

       FD  IN-INC
           RECORD CONTAINS 220 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY INCDNT01.

       FD  IN-CONFIG
           RECORD CONTAINS 80 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RUNCFG01.

       FD  OUT-PLAN
           RECORD CONTAINS 160 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RSTRPLN1.

       FD  OUT-OPS
           RECORD CONTAINS 220 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       01  OUT-OPS-REC                    PIC X(220).

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-END-CKP                 PIC X VALUE 'N'.
              88 END-OF-CKP              VALUE 'Y'.
           05 WS-END-INC                 PIC X VALUE 'N'.
              88 END-OF-INC              VALUE 'Y'.

       01  WS-RUNTIME.
           05 WS-RUN-ID                  PIC X(8) VALUE 'ORDR460 '.
           05 WS-RUN-MODE                PIC X(3) VALUE 'EOD'.
           05 WS-STRICT                  PIC X VALUE 'N'.
           05 WS-MIN-SEV2                PIC 9(5) VALUE 2.
           05 WS-MIN-SEV1                PIC 9(5) VALUE 10.

       01  WS-COUNTERS.
           05 WS-CKP-READ                PIC 9(9) VALUE ZERO.
           05 WS-INC-READ                PIC 9(9) VALUE ZERO.
           05 WS-PLAN-WRITTEN            PIC 9(9) VALUE ZERO.
           05 WS-OPS-WRITTEN             PIC 9(9) VALUE ZERO.
           05 WS-SEV1                    PIC 9(9) VALUE ZERO.
           05 WS-SEV2                    PIC 9(9) VALUE ZERO.

       01  WS-FAILURE.
           05 WS-FAIL-FOUND              PIC X VALUE 'N'.
           05 WS-FAIL-STAGE              PIC X(8) VALUE SPACES.
           05 WS-FAIL-SEQ                PIC 9(4) VALUE 9999.

       01  WS-STAGE-SEQ                  PIC 9(4) VALUE ZERO.
       01  WS-MESSAGE                    PIC X(84).

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR460 RUNNING ***'
           OPEN INPUT IN-CKP IN-INC IN-CONFIG
                OUTPUT OUT-PLAN OUT-OPS

           PERFORM LOAD-CONFIG
           PERFORM SCAN-CHECKPOINTS
           PERFORM SCAN-INCIDENTS
           PERFORM EMIT-PLAN
           PERFORM EMIT-OPERATIONS

           CLOSE IN-CKP IN-INC IN-CONFIG OUT-PLAN OUT-OPS

           DISPLAY 'ORDR460 CKP READ   : ' WS-CKP-READ
           DISPLAY 'ORDR460 INC READ   : ' WS-INC-READ
           DISPLAY 'ORDR460 PLAN WRITT : ' WS-PLAN-WRITTEN
           DISPLAY 'ORDR460 OPS WRITT  : ' WS-OPS-WRITTEN
           DISPLAY 'ORDR460 SEV1/SEV2  : ' WS-SEV1 ' / ' WS-SEV2

           GOBACK.

       LOAD-CONFIG.
           READ IN-CONFIG
               AT END
                   CONTINUE
               NOT AT END
                   MOVE RUN-CFG-RUN-MODE TO WS-RUN-MODE
                   MOVE RUN-CFG-STRICT-FLAG TO WS-STRICT
                   MOVE RUN-CFG-MIN-SEV2-FAIL TO WS-MIN-SEV2
                   MOVE RUN-CFG-MIN-SEV1-FAIL TO WS-MIN-SEV1
           END-READ.

       SCAN-CHECKPOINTS.
           PERFORM UNTIL END-OF-CKP
               READ IN-CKP
                   AT END
                       SET END-OF-CKP TO TRUE
                   NOT AT END
                       ADD 1 TO WS-CKP-READ
                       PERFORM EVALUATE-CHECKPOINT
               END-READ
           END-PERFORM.

       EVALUATE-CHECKPOINT.
           IF CKP-STATUS = 'F'
               PERFORM DETERMINE-STAGE-SEQUENCE
               IF WS-STAGE-SEQ < WS-FAIL-SEQ
                   MOVE 'Y' TO WS-FAIL-FOUND
                   MOVE CKP-STAGE TO WS-FAIL-STAGE
                   MOVE WS-STAGE-SEQ TO WS-FAIL-SEQ
               END-IF
           END-IF.

       DETERMINE-STAGE-SEQUENCE.
           MOVE 9999 TO WS-STAGE-SEQ
           EVALUATE CKP-STAGE
               WHEN 'STG100  '
                   MOVE 100 TO WS-STAGE-SEQ
               WHEN 'STG150  '
                   MOVE 150 TO WS-STAGE-SEQ
               WHEN 'STG200  '
                   MOVE 200 TO WS-STAGE-SEQ
               WHEN 'STG300  '
                   MOVE 300 TO WS-STAGE-SEQ
               WHEN 'STG400  '
                   MOVE 400 TO WS-STAGE-SEQ
               WHEN 'STG450  '
                   MOVE 450 TO WS-STAGE-SEQ
               WHEN OTHER
                   MOVE 9999 TO WS-STAGE-SEQ
           END-EVALUATE.

       SCAN-INCIDENTS.
           PERFORM UNTIL END-OF-INC
               READ IN-INC
                   AT END
                       SET END-OF-INC TO TRUE
                   NOT AT END
                       ADD 1 TO WS-INC-READ
                       IF INC-SEVERITY = '1'
                           ADD 1 TO WS-SEV1
                       END-IF
                       IF INC-SEVERITY = '2'
                           ADD 1 TO WS-SEV2
                       END-IF
               END-READ
           END-PERFORM.

       EMIT-PLAN.
           MOVE SPACES TO RST-PLAN-REC
           MOVE WS-RUN-ID TO RST-PLAN-RUN-ID
           MOVE WS-RUN-MODE TO RST-PLAN-MODE
           MOVE WS-SEV1 TO RST-PLAN-SEV1-COUNT
           MOVE WS-SEV2 TO RST-PLAN-SEV2-COUNT

           IF WS-FAIL-FOUND = 'Y'
               MOVE 'RESTART-REQUIRED    ' TO RST-PLAN-ACTION
               MOVE WS-FAIL-STAGE TO RST-PLAN-NEXT-STAGE
               MOVE '1' TO RST-PLAN-SEVERITY
               MOVE 'RUNCTRL ' TO RST-PLAN-ROUTE
               MOVE 'EARLIEST FAILED STAGE SELECTED FOR RESTART' TO
                 RST-PLAN-MESSAGE
           ELSE
               MOVE 'NO-RESTART          ' TO RST-PLAN-ACTION
               MOVE 'NONE    ' TO RST-PLAN-NEXT-STAGE
               MOVE '3' TO RST-PLAN-SEVERITY
               MOVE 'DATAOPS ' TO RST-PLAN-ROUTE
               MOVE 'ALL STAGES COMPLETED - PROCESS CLOSED' TO
                 RST-PLAN-MESSAGE
           END-IF

           WRITE RST-PLAN-REC
           ADD 1 TO WS-PLAN-WRITTEN.

       EMIT-OPERATIONS.
           IF WS-SEV2 >= WS-MIN-SEV2
               MOVE SPACES TO OUT-OPS-REC
               STRING
                   'ESCALATE|SEV2|THRESHOLD EXCEEDED|COUNT='
                   WS-SEV2
                   DELIMITED BY SIZE INTO OUT-OPS-REC
               END-STRING
               WRITE OUT-OPS-REC
               ADD 1 TO WS-OPS-WRITTEN
           END-IF

           IF WS-SEV1 >= WS-MIN-SEV1
               MOVE SPACES TO OUT-OPS-REC
               STRING
                   'ESCALATE|SEV1|CRITICAL FAILURES EXCEEDED|COUNT='
                   WS-SEV1
                   DELIMITED BY SIZE INTO OUT-OPS-REC
               END-STRING
               WRITE OUT-OPS-REC
               ADD 1 TO WS-OPS-WRITTEN
           END-IF

           IF WS-STRICT = 'Y' AND WS-FAIL-FOUND = 'Y'
               MOVE SPACES TO OUT-OPS-REC
               STRING
                   'STRICT-MODE|IMMEDIATE HALT AND CONTROL-ROOM TICKET'
                   DELIMITED BY SIZE INTO OUT-OPS-REC
               END-STRING
               WRITE OUT-OPS-REC
               ADD 1 TO WS-OPS-WRITTEN
           END-IF.

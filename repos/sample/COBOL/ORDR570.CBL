       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR570.
      *---------------------------------------------------------------*
      * Deterministic runbook action matrix generator.
      * Inputs:
      * - handoff bundle manifest (ORDR560)
      * - final run disposition (ORDR540)
      * Output:
      * - ordered action matrix for control-room execution
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-BND ASSIGN TO ORDRBND
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-DSP ASSIGN TO ORDRDSP
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-MAT ASSIGN TO ORDRMAT
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-BND
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY BNDLMF1.

       FD  IN-DSP
           RECORD CONTAINS 200 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RUNDSP1.

       FD  OUT-MAT
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RUNMAT1.

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-END-BND                 PIC X VALUE 'N'.
              88 END-OF-BND              VALUE 'Y'.

       01  WS-RUN.
           05 WS-RUN-ID                  PIC X(8) VALUE 'ORDR570 '.
           05 WS-DISPOSITION             PIC X(6) VALUE 'GREEN '.

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR570 RUNNING ***'
           OPEN INPUT IN-BND IN-DSP
                OUTPUT OUT-MAT

           PERFORM LOAD-DISPOSITION
           PERFORM BUILD-MATRIX

           CLOSE IN-BND IN-DSP OUT-MAT

           DISPLAY 'ORDR570 MATRIX WRITTEN'
           GOBACK.

       LOAD-DISPOSITION.
           READ IN-DSP
               AT END
                   CONTINUE
               NOT AT END
                   MOVE RUN-DSP-RUN-ID TO WS-RUN-ID
                   MOVE RUN-DSP-STATUS TO WS-DISPOSITION
           END-READ.

       BUILD-MATRIX.
           PERFORM UNTIL END-OF-BND
               READ IN-BND
                   AT END
                       SET END-OF-BND TO TRUE
                   NOT AT END
                       PERFORM WRITE-MATRIX-LINE
               END-READ
           END-PERFORM.

       WRITE-MATRIX-LINE.
           MOVE SPACES TO RUN-MAT-REC
           MOVE WS-RUN-ID TO RUN-MAT-RUN-ID
           MOVE BNDL-MF-STAGE TO RUN-MAT-STEP
           MOVE BNDL-MF-ARTIFACT TO RUN-MAT-ARTIFACT
           MOVE BNDL-MF-PRIORITY TO RUN-MAT-PRIORITY
           MOVE WS-DISPOSITION TO RUN-MAT-DISPOSITION

           EVALUATE TRUE
               WHEN BNDL-MF-ARTIFACT = 'AUDIT-EVIDENCE      '
                   MOVE 'RUNCTRL ' TO RUN-MAT-OWNER
               WHEN BNDL-MF-ARTIFACT = 'RESTART-PLAN        '
                   MOVE 'RUNCTRL ' TO RUN-MAT-OWNER
               WHEN BNDL-MF-ARTIFACT = 'RISK-ALERTS         '
                   MOVE 'DATAOPS ' TO RUN-MAT-OWNER
               WHEN BNDL-MF-ARTIFACT = 'SLA-ALERTS          '
                   MOVE 'DATAOPS ' TO RUN-MAT-OWNER
               WHEN BNDL-MF-ARTIFACT = 'KPI-ROLLUP          '
                   MOVE 'RUNCTRL ' TO RUN-MAT-OWNER
               WHEN OTHER
                   MOVE 'OPS     ' TO RUN-MAT-OWNER
           END-EVALUATE

           IF BNDL-MF-STATUS = 'MISSING   '
               MOVE 'REGENERATE-ARTIFACT     ' TO RUN-MAT-ACTION
               MOVE 'RED   ' TO RUN-MAT-URGENCY
           ELSE
               IF BNDL-MF-STATUS = 'EMPTY     '
                   MOVE 'VERIFY-ZERO-STATE      ' TO RUN-MAT-ACTION
                   IF WS-DISPOSITION = 'RED   '
                      OR WS-DISPOSITION = 'AMBER '
                       MOVE 'AMBER ' TO RUN-MAT-URGENCY
                   ELSE
                       MOVE 'GREEN ' TO RUN-MAT-URGENCY
                   END-IF
               ELSE
                   MOVE 'PUBLISH-AND-ACK        ' TO RUN-MAT-ACTION
                   IF WS-DISPOSITION = 'RED   '
                       MOVE 'RED   ' TO RUN-MAT-URGENCY
                   ELSE
                       IF WS-DISPOSITION = 'AMBER '
                           MOVE 'AMBER ' TO RUN-MAT-URGENCY
                       ELSE
                           MOVE 'GREEN ' TO RUN-MAT-URGENCY
                       END-IF
                   END-IF
               END-IF
           END-IF

           STRING
               'STATUS=' DELIMITED BY SIZE
               BNDL-MF-STATUS DELIMITED BY SIZE
               ' SUMMARY=' DELIMITED BY SIZE
               BNDL-MF-SUMMARY DELIMITED BY SIZE
               INTO RUN-MAT-NOTE
           END-STRING

           WRITE RUN-MAT-REC.

       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR590.
      *---------------------------------------------------------------*
      * Shift-close certification package generator.
      * Inputs: TIMELINE, RUNMATRIX, GOVRPT
      * Output: certification records for end-of-shift signoff
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-TLN ASSIGN TO ORDRTLN
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-MAT ASSIGN TO ORDRMAT
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-GOV ASSIGN TO ORDRGOV
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-CLS ASSIGN TO ORDRCLS
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-TLN
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY TIMELN1.

       FD  IN-MAT
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RUNMAT1.

       FD  IN-GOV
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY GOVRPT1.

       FD  OUT-CLS
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY SHFCLS1.

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-END-TLN                 PIC X VALUE 'N'.
              88 END-OF-TLN              VALUE 'Y'.
           05 WS-END-MAT                 PIC X VALUE 'N'.
              88 END-OF-MAT              VALUE 'Y'.
           05 WS-END-GOV                 PIC X VALUE 'N'.
              88 END-OF-GOV              VALUE 'Y'.

       01  WS-COUNTS.
           05 WS-TOTAL-EVENTS            PIC 9(7) VALUE ZERO.
           05 WS-RED-EVENTS              PIC 9(7) VALUE ZERO.
           05 WS-AMBER-EVENTS            PIC 9(7) VALUE ZERO.
           05 WS-ACTIONS-TOTAL           PIC 9(7) VALUE ZERO.
           05 WS-ACTIONS-PENDING         PIC 9(7) VALUE ZERO.

       01  WS-RUN.
           05 WS-RUN-ID                  PIC X(8) VALUE 'ORDR590 '.
           05 WS-OVERALL-STATUS          PIC X(12) VALUE 'STABLE      '.
           05 WS-CERT-FLAG               PIC X VALUE 'Y'.

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR590 RUNNING ***'
           OPEN INPUT IN-TLN IN-MAT IN-GOV
                OUTPUT OUT-CLS

           PERFORM SCAN-TIMELINE
           PERFORM SCAN-MATRIX
           PERFORM SCAN-GOV
           PERFORM DERIVE-CERTIFICATION
           PERFORM WRITE-SUMMARY

           CLOSE IN-TLN IN-MAT IN-GOV OUT-CLS

           DISPLAY 'ORDR590 SHIFT CLOSE WRITTEN'
           GOBACK.

       SCAN-TIMELINE.
           PERFORM UNTIL END-OF-TLN
               READ IN-TLN
                   AT END
                       SET END-OF-TLN TO TRUE
                   NOT AT END
                       MOVE TIMELN-RUN-ID TO WS-RUN-ID
                       ADD 1 TO WS-TOTAL-EVENTS
                       IF TIMELN-URGENCY = 'RED   '
                           ADD 1 TO WS-RED-EVENTS
                       ELSE
                           IF TIMELN-URGENCY = 'AMBER '
                               ADD 1 TO WS-AMBER-EVENTS
                           END-IF
                       END-IF
               END-READ
           END-PERFORM.

       SCAN-MATRIX.
           PERFORM UNTIL END-OF-MAT
               READ IN-MAT
                   AT END
                       SET END-OF-MAT TO TRUE
                   NOT AT END
                       MOVE RUN-MAT-RUN-ID TO WS-RUN-ID
                       ADD 1 TO WS-ACTIONS-TOTAL
                       IF RUN-MAT-ACTION = 'REGENERATE-ARTIFACT     '
                           ADD 1 TO WS-ACTIONS-PENDING
                       END-IF
               END-READ
           END-PERFORM.

       SCAN-GOV.
           PERFORM UNTIL END-OF-GOV
               READ IN-GOV
                   AT END
                       SET END-OF-GOV TO TRUE
                   NOT AT END
                       MOVE GOV-RPT-RUN-ID TO WS-RUN-ID
                       IF GOV-RPT-SEVERITY = 'R'
                           MOVE 'CRITICAL    ' TO WS-OVERALL-STATUS
                       ELSE
                           IF GOV-RPT-SEVERITY = 'A'
                               IF WS-OVERALL-STATUS NOT = 'CRITICAL    '
                                   MOVE 'DEGRADED    ' TO WS-OVERALL-STATUS
                               END-IF
                           END-IF
                       END-IF
               END-READ
           END-PERFORM.

       DERIVE-CERTIFICATION.
           IF WS-RED-EVENTS > 0
               MOVE 'N' TO WS-CERT-FLAG
           ELSE
               IF WS-ACTIONS-PENDING > 0
                   MOVE 'N' TO WS-CERT-FLAG
               ELSE
                   IF WS-OVERALL-STATUS = 'CRITICAL    '
                       MOVE 'N' TO WS-CERT-FLAG
                   ELSE
                       MOVE 'Y' TO WS-CERT-FLAG
                   END-IF
               END-IF
           END-IF.

       WRITE-SUMMARY.
           MOVE SPACES TO SHF-CLS-REC
           MOVE WS-RUN-ID TO SHF-CLS-RUN-ID
           MOVE 'SUMMARY   ' TO SHF-CLS-LINE-TYPE
           MOVE WS-OVERALL-STATUS TO SHF-CLS-STATUS
           MOVE 'RUNCTRL ' TO SHF-CLS-OWNER
           MOVE WS-TOTAL-EVENTS TO SHF-CLS-TOTAL-EVENTS
           MOVE WS-RED-EVENTS TO SHF-CLS-RED-EVENTS
           MOVE WS-AMBER-EVENTS TO SHF-CLS-AMBER-EVENTS
           MOVE WS-ACTIONS-TOTAL TO SHF-CLS-ACTIONS-TOTAL
           MOVE WS-ACTIONS-PENDING TO SHF-CLS-ACTIONS-PENDING
           MOVE WS-CERT-FLAG TO SHF-CLS-CERT-FLAG

           STRING
               'SHIFT-CLOSE CERT=' DELIMITED BY SIZE
               WS-CERT-FLAG DELIMITED BY SIZE
               ' STATUS=' DELIMITED BY SIZE
               WS-OVERALL-STATUS DELIMITED BY SIZE
               ' RED=' DELIMITED BY SIZE
               WS-RED-EVENTS DELIMITED BY SIZE
               ' PENDING=' DELIMITED BY SIZE
               WS-ACTIONS-PENDING DELIMITED BY SIZE
               INTO SHF-CLS-MESSAGE
           END-STRING

           WRITE SHF-CLS-REC.

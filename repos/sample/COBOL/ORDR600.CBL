       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR600.
      *---------------------------------------------------------------*
      * Audit-evidence export index publisher.
      * Inputs: handoff bundle + downstream governance artifacts.
      * Output: export index with retention and handoff metadata.
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-BND ASSIGN TO ORDRBND
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-MAT ASSIGN TO ORDRMAT
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-TLN ASSIGN TO ORDRTLN
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-CLS ASSIGN TO ORDRCLS
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-GOV ASSIGN TO ORDRGOV
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-IDX ASSIGN TO ORDAIDX
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-BND
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY BNDLMF1.

       FD  IN-MAT
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RUNMAT1.

       FD  IN-TLN
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY TIMELN1.

       FD  IN-CLS
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY SHFCLS1.

       FD  IN-GOV
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY GOVRPT1.

       FD  OUT-IDX
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY AUDIDX1.

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-END-BND                 PIC X VALUE 'N'.
              88 END-OF-BND              VALUE 'Y'.
           05 WS-END-MAT                 PIC X VALUE 'N'.
              88 END-OF-MAT              VALUE 'Y'.
           05 WS-END-TLN                 PIC X VALUE 'N'.
              88 END-OF-TLN              VALUE 'Y'.
           05 WS-END-GOV                 PIC X VALUE 'N'.
              88 END-OF-GOV              VALUE 'Y'.

       01  WS-RUN.
           05 WS-RUN-ID                  PIC X(8) VALUE 'ORDR600 '.
           05 WS-CERT-FLAG               PIC X VALUE 'N'.

       01  WS-STATS.
           05 WS-MAT-ROWS                PIC 9(7) VALUE ZERO.
           05 WS-TLN-ROWS                PIC 9(7) VALUE ZERO.
           05 WS-GOV-ROWS                PIC 9(7) VALUE ZERO.

       01  WS-BUILD.
           05 WS-PACKAGE-ID              PIC X(16).

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR600 RUNNING ***'
           OPEN INPUT IN-BND IN-MAT IN-TLN IN-CLS IN-GOV
                OUTPUT OUT-IDX

           PERFORM LOAD-CERTIFICATION
           PERFORM COUNT-MATRIX
           PERFORM COUNT-TIMELINE
           PERFORM COUNT-GOV
           PERFORM WRITE-BUNDLE-INDEX
           PERFORM WRITE-DERIVED-INDEX

           CLOSE IN-BND IN-MAT IN-TLN IN-CLS IN-GOV OUT-IDX

           DISPLAY 'ORDR600 AUDIT INDEX WRITTEN'
           GOBACK.

       LOAD-CERTIFICATION.
           READ IN-CLS
               AT END
                   CONTINUE
               NOT AT END
                   MOVE SHF-CLS-RUN-ID TO WS-RUN-ID
                   MOVE SHF-CLS-CERT-FLAG TO WS-CERT-FLAG
           END-READ.

       COUNT-MATRIX.
           PERFORM UNTIL END-OF-MAT
               READ IN-MAT
                   AT END
                       SET END-OF-MAT TO TRUE
                   NOT AT END
                       MOVE RUN-MAT-RUN-ID TO WS-RUN-ID
                       ADD 1 TO WS-MAT-ROWS
               END-READ
           END-PERFORM.

       COUNT-TIMELINE.
           PERFORM UNTIL END-OF-TLN
               READ IN-TLN
                   AT END
                       SET END-OF-TLN TO TRUE
                   NOT AT END
                       MOVE TIMELN-RUN-ID TO WS-RUN-ID
                       ADD 1 TO WS-TLN-ROWS
               END-READ
           END-PERFORM.

       COUNT-GOV.
           PERFORM UNTIL END-OF-GOV
               READ IN-GOV
                   AT END
                       SET END-OF-GOV TO TRUE
                   NOT AT END
                       MOVE GOV-RPT-RUN-ID TO WS-RUN-ID
                       ADD 1 TO WS-GOV-ROWS
               END-READ
           END-PERFORM.

       WRITE-BUNDLE-INDEX.
           PERFORM UNTIL END-OF-BND
               READ IN-BND
                   AT END
                       SET END-OF-BND TO TRUE
                   NOT AT END
                       PERFORM PREPARE-INDEX-LINE
                       MOVE BNDL-MF-ARTIFACT TO AUD-IDX-ARTIFACT
                       MOVE BNDL-MF-STAGE TO AUD-IDX-STAGE
                       MOVE BNDL-MF-STATUS TO AUD-IDX-STATUS
                       IF BNDL-MF-STATUS = 'MISSING   '
                           MOVE 'REBUILD ' TO AUD-IDX-EXPORT-CLASS
                       ELSE
                           IF BNDL-MF-STATUS = 'EMPTY     '
                               MOVE 'REVIEW  ' TO AUD-IDX-EXPORT-CLASS
                           ELSE
                               MOVE 'EXPORT  ' TO AUD-IDX-EXPORT-CLASS
                           END-IF
                       END-IF
                       IF BNDL-MF-PRIORITY >= 90
                           MOVE 2555 TO AUD-IDX-RETENTION-DAYS
                       ELSE
                           IF BNDL-MF-PRIORITY >= 70
                               MOVE 1095 TO AUD-IDX-RETENTION-DAYS
                           ELSE
                               MOVE 0365 TO AUD-IDX-RETENTION-DAYS
                           END-IF
                       END-IF
                       IF BNDL-MF-STAGE = 'STAGE400'
                           MOVE 'AUDIT     ' TO AUD-IDX-HANDOFF
                       ELSE
                           IF BNDL-MF-STAGE = 'STAGE540'
                               MOVE 'RUNCTRL   ' TO AUD-IDX-HANDOFF
                           ELSE
                               MOVE 'OPS       ' TO AUD-IDX-HANDOFF
                           END-IF
                       END-IF
                       STRING
                           'CERT=' DELIMITED BY SIZE
                           WS-CERT-FLAG DELIMITED BY SIZE
                           ' MAT=' DELIMITED BY SIZE
                           WS-MAT-ROWS DELIMITED BY SIZE
                           ' TLN=' DELIMITED BY SIZE
                           WS-TLN-ROWS DELIMITED BY SIZE
                           ' GOV=' DELIMITED BY SIZE
                           WS-GOV-ROWS DELIMITED BY SIZE
                           ' NOTE=' DELIMITED BY SIZE
                           BNDL-MF-SUMMARY DELIMITED BY SIZE
                           INTO AUD-IDX-SUMMARY
                       END-STRING
                       WRITE AUD-IDX-REC
               END-READ
           END-PERFORM.

       WRITE-DERIVED-INDEX.
           PERFORM PREPARE-INDEX-LINE
           MOVE 'RUN-MATRIX          ' TO AUD-IDX-ARTIFACT
           MOVE 'STAGE570' TO AUD-IDX-STAGE
           MOVE 'READY     ' TO AUD-IDX-STATUS
           MOVE 1095 TO AUD-IDX-RETENTION-DAYS
           MOVE 'RUNCTRL   ' TO AUD-IDX-HANDOFF
           MOVE 'EXPORT  ' TO AUD-IDX-EXPORT-CLASS
           STRING
               'ROW-COUNT=' DELIMITED BY SIZE
               WS-MAT-ROWS DELIMITED BY SIZE
               INTO AUD-IDX-SUMMARY
           END-STRING
           WRITE AUD-IDX-REC

           PERFORM PREPARE-INDEX-LINE
           MOVE 'TIMELINE-FEED       ' TO AUD-IDX-ARTIFACT
           MOVE 'STAGE580' TO AUD-IDX-STAGE
           MOVE 'READY     ' TO AUD-IDX-STATUS
           MOVE 1095 TO AUD-IDX-RETENTION-DAYS
           MOVE 'OPS       ' TO AUD-IDX-HANDOFF
           MOVE 'EXPORT  ' TO AUD-IDX-EXPORT-CLASS
           STRING
               'ROW-COUNT=' DELIMITED BY SIZE
               WS-TLN-ROWS DELIMITED BY SIZE
               INTO AUD-IDX-SUMMARY
           END-STRING
           WRITE AUD-IDX-REC

           PERFORM PREPARE-INDEX-LINE
           MOVE 'SHIFT-CLOSE         ' TO AUD-IDX-ARTIFACT
           MOVE 'STAGE590' TO AUD-IDX-STAGE
           MOVE 'READY     ' TO AUD-IDX-STATUS
           MOVE 2555 TO AUD-IDX-RETENTION-DAYS
           MOVE 'AUDIT     ' TO AUD-IDX-HANDOFF
           MOVE 'EXPORT  ' TO AUD-IDX-EXPORT-CLASS
           STRING
               'CERTIFICATION=' DELIMITED BY SIZE
               WS-CERT-FLAG DELIMITED BY SIZE
               INTO AUD-IDX-SUMMARY
           END-STRING
           WRITE AUD-IDX-REC.

       PREPARE-INDEX-LINE.
           MOVE SPACES TO AUD-IDX-REC
           MOVE WS-RUN-ID TO AUD-IDX-RUN-ID
           STRING
               'PKG' DELIMITED BY SIZE
               WS-RUN-ID DELIMITED BY SIZE
               INTO WS-PACKAGE-ID
           END-STRING
           MOVE WS-PACKAGE-ID TO AUD-IDX-PACKAGE-ID.

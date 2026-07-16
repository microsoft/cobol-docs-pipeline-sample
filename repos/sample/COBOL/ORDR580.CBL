       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR580.
      *---------------------------------------------------------------*
      * Incident-bridge timeline synthesizer.
      * Inputs: RUNMATRIX, ACTSTATUS, SLAALERT, GOVRPT
      * Output: deterministic timeline feed for shift handoff and bridge
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-MAT ASSIGN TO ORDRMAT
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-STS ASSIGN TO ORDRSTS
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-SLA ASSIGN TO ORDRSLA
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-GOV ASSIGN TO ORDRGOV
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-TLN ASSIGN TO ORDRTLN
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-MAT
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY RUNMAT1.

       FD  IN-STS
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY ACTSTAT1.

       FD  IN-SLA
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY SLALRT1.

       FD  IN-GOV
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY GOVRPT1.

       FD  OUT-TLN
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY TIMELN1.

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-END-MAT                 PIC X VALUE 'N'.
              88 END-OF-MAT              VALUE 'Y'.
           05 WS-END-STS                 PIC X VALUE 'N'.
              88 END-OF-STS              VALUE 'Y'.
           05 WS-END-SLA                 PIC X VALUE 'N'.
              88 END-OF-SLA              VALUE 'Y'.
           05 WS-END-GOV                 PIC X VALUE 'N'.
              88 END-OF-GOV              VALUE 'Y'.

       01  WS-CONTROL.
           05 WS-SEQ                     PIC 9(6) VALUE ZERO.
           05 WS-RUN-ID                  PIC X(8) VALUE 'ORDR580 '.

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR580 RUNNING ***'
           OPEN INPUT IN-MAT IN-STS IN-SLA IN-GOV
                OUTPUT OUT-TLN

           PERFORM FROM-MATRIX
           PERFORM FROM-STATUS
           PERFORM FROM-SLA
           PERFORM FROM-GOV

           CLOSE IN-MAT IN-STS IN-SLA IN-GOV OUT-TLN

           DISPLAY 'ORDR580 TIMELINE WRITTEN'
           GOBACK.

       FROM-MATRIX.
           PERFORM UNTIL END-OF-MAT
               READ IN-MAT
                   AT END
                       SET END-OF-MAT TO TRUE
                   NOT AT END
                       MOVE RUN-MAT-RUN-ID TO WS-RUN-ID
                       PERFORM INIT-LINE
                       MOVE 'RUNMATRIX  ' TO TIMELN-SOURCE
                       MOVE RUN-MAT-OWNER TO TIMELN-OWNER
                       MOVE RUN-MAT-STEP TO TIMELN-STAGE
                       MOVE RUN-MAT-URGENCY TO TIMELN-URGENCY
                       MOVE RUN-MAT-DISPOSITION TO TIMELN-STATUS
                       MOVE SPACES TO TIMELN-TICKET
                       MOVE RUN-MAT-ACTION TO TIMELN-EVENT
                       MOVE RUN-MAT-NOTE TO TIMELN-MESSAGE
                       WRITE TIMELN-REC
               END-READ
           END-PERFORM.

       FROM-STATUS.
           PERFORM UNTIL END-OF-STS
               READ IN-STS
                   AT END
                       SET END-OF-STS TO TRUE
                   NOT AT END
                       MOVE ACT-STAT-RUN-ID TO WS-RUN-ID
                       PERFORM INIT-LINE
                       MOVE 'ACTSTATUS  ' TO TIMELN-SOURCE
                       MOVE ACT-STAT-OWNER TO TIMELN-OWNER
                       MOVE ACT-STAT-TARGET-STAGE TO TIMELN-STAGE
                       IF ACT-STAT-PRIORITY >= 90
                           MOVE 'RED   ' TO TIMELN-URGENCY
                       ELSE
                           IF ACT-STAT-PRIORITY >= 70
                               MOVE 'AMBER ' TO TIMELN-URGENCY
                           ELSE
                               MOVE 'GREEN ' TO TIMELN-URGENCY
                           END-IF
                       END-IF
                       MOVE ACT-STAT-STATUS TO TIMELN-STATUS
                       MOVE ACT-STAT-TICKET TO TIMELN-TICKET
                       MOVE ACT-STAT-ACTION TO TIMELN-EVENT
                       MOVE ACT-STAT-REASON TO TIMELN-MESSAGE
                       WRITE TIMELN-REC
               END-READ
           END-PERFORM.

       FROM-SLA.
           PERFORM UNTIL END-OF-SLA
               READ IN-SLA
                   AT END
                       SET END-OF-SLA TO TRUE
                   NOT AT END
                       MOVE SLA-RUN-ID TO WS-RUN-ID
                       PERFORM INIT-LINE
                       MOVE 'SLAALERT  ' TO TIMELN-SOURCE
                       MOVE SLA-OWNER TO TIMELN-OWNER
                       MOVE SLA-TARGET-STAGE TO TIMELN-STAGE
                       EVALUATE SLA-SEVERITY
                           WHEN 'C'
                               MOVE 'RED   ' TO TIMELN-URGENCY
                           WHEN 'H'
                               MOVE 'AMBER ' TO TIMELN-URGENCY
                           WHEN OTHER
                               MOVE 'GREEN ' TO TIMELN-URGENCY
                       END-EVALUATE
                       MOVE SLA-STATUS TO TIMELN-STATUS
                       MOVE SLA-TICKET TO TIMELN-TICKET
                       MOVE SLA-BREACH-CODE TO TIMELN-EVENT
                       MOVE SLA-MESSAGE TO TIMELN-MESSAGE
                       WRITE TIMELN-REC
               END-READ
           END-PERFORM.

       FROM-GOV.
           PERFORM UNTIL END-OF-GOV
               READ IN-GOV
                   AT END
                       SET END-OF-GOV TO TRUE
                   NOT AT END
                       MOVE GOV-RPT-RUN-ID TO WS-RUN-ID
                       PERFORM INIT-LINE
                       MOVE 'GOVRPT    ' TO TIMELN-SOURCE
                       MOVE 'RUNCTRL ' TO TIMELN-OWNER
                       MOVE 'STAGE550' TO TIMELN-STAGE
                       IF GOV-RPT-SEVERITY = 'R'
                           MOVE 'RED   ' TO TIMELN-URGENCY
                       ELSE
                           IF GOV-RPT-SEVERITY = 'A'
                               MOVE 'AMBER ' TO TIMELN-URGENCY
                           ELSE
                               MOVE 'GREEN ' TO TIMELN-URGENCY
                           END-IF
                       END-IF
                       MOVE GOV-RPT-STATUS TO TIMELN-STATUS
                       MOVE SPACES TO TIMELN-TICKET
                       MOVE GOV-RPT-LINE-TYPE TO TIMELN-EVENT
                       MOVE GOV-RPT-MESSAGE TO TIMELN-MESSAGE
                       WRITE TIMELN-REC
               END-READ
           END-PERFORM.

       INIT-LINE.
           MOVE SPACES TO TIMELN-REC
           ADD 1 TO WS-SEQ
           MOVE WS-SEQ TO TIMELN-SEQ
           MOVE WS-RUN-ID TO TIMELN-RUN-ID.

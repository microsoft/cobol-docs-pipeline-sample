       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR100.
      *---------------------------------------------------------------*
      * Validate and normalize raw orders.
      * Additional controls:
      * - mandatory field checks
      * - domain checks (channel/currency/region)
      * - simple duplicate detection (consecutive order id)
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-ORDERS ASSIGN TO ORDRIN
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-VALID ASSIGN TO ORDRWK0
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-REJECT ASSIGN TO ORDRRJ1
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-ORDERS
           RECORD CONTAINS 160 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY ORDRIN01.

       FD  OUT-VALID
           RECORD CONTAINS 160 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       01  OUT-VALID-REC                 PIC X(160).

       FD  OUT-REJECT
           RECORD CONTAINS 220 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       01  OUT-REJECT-REC.
           05 RJ-REASON                  PIC X(60).
           05 RJ-RAW                     PIC X(160).

       WORKING-STORAGE SECTION.
       01  WS-END                        PIC X VALUE 'N'.
           88 END-OF-FILE                VALUE 'Y'.
       01  WS-COUNTERS.
           05 WS-READ                    PIC 9(9) VALUE ZERO.
           05 WS-VALID                   PIC 9(9) VALUE ZERO.
           05 WS-REJECT                  PIC 9(9) VALUE ZERO.
           05 WS-DUPLICATE               PIC 9(9) VALUE ZERO.

       01  WS-VALIDATION.
           05 WS-REASON                  PIC X(60).
           05 WS-LAST-ORDER-ID           PIC X(12) VALUE SPACES.

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR100 RUNNING ***'
           OPEN INPUT IN-ORDERS
                OUTPUT OUT-VALID OUT-REJECT

           PERFORM UNTIL END-OF-FILE
               READ IN-ORDERS
                   AT END
                       SET END-OF-FILE TO TRUE
                   NOT AT END
                       ADD 1 TO WS-READ
                       PERFORM VALIDATE-RECORD
               END-READ
           END-PERFORM

           CLOSE IN-ORDERS OUT-VALID OUT-REJECT

           DISPLAY 'ORDR100 READ      : ' WS-READ
           DISPLAY 'ORDR100 VALID     : ' WS-VALID
           DISPLAY 'ORDR100 REJECT    : ' WS-REJECT
           DISPLAY 'ORDR100 DUPLICATE : ' WS-DUPLICATE

           GOBACK.

       VALIDATE-RECORD.
           MOVE SPACES TO WS-REASON

           IF ORDR-IN-ORDER-ID = SPACES
               MOVE 'MISSING ORDER-ID' TO WS-REASON
           END-IF

           IF WS-REASON = SPACES AND ORDR-IN-CUSTOMER-ID = SPACES
               MOVE 'MISSING CUSTOMER-ID' TO WS-REASON
           END-IF

           IF WS-REASON = SPACES AND ORDR-IN-PRODUCT-CODE = SPACES
               MOVE 'MISSING PRODUCT-CODE' TO WS-REASON
           END-IF

           IF WS-REASON = SPACES AND ORDR-IN-QUANTITY = ZERO
               MOVE 'QUANTITY MUST BE GREATER THAN 0' TO WS-REASON
           END-IF

           IF WS-REASON = SPACES AND ORDR-IN-UNIT-PRICE = ZERO
               MOVE 'UNIT PRICE MUST BE GREATER THAN 0' TO WS-REASON
           END-IF

           IF WS-REASON = SPACES
              AND ORDR-IN-CHANNEL NOT = 'ONLINE    '
              AND ORDR-IN-CHANNEL NOT = 'RETAIL    '
              AND ORDR-IN-CHANNEL NOT = 'PARTNER   '
               MOVE 'INVALID CHANNEL' TO WS-REASON
           END-IF

           IF WS-REASON = SPACES
              AND ORDR-IN-CURRENCY NOT = 'EUR'
              AND ORDR-IN-CURRENCY NOT = 'USD'
              AND ORDR-IN-CURRENCY NOT = 'GBP'
               MOVE 'INVALID CURRENCY' TO WS-REASON
           END-IF

           IF WS-REASON = SPACES
              AND ORDR-IN-REGION NOT = 'EU '
              AND ORDR-IN-REGION NOT = 'NAM'
              AND ORDR-IN-REGION NOT = 'APC'
               MOVE 'INVALID REGION' TO WS-REASON
           END-IF

           IF WS-REASON = SPACES AND ORDR-IN-ORDER-ID = WS-LAST-ORDER-ID
               MOVE 'DUPLICATE ORDER-ID (CONSECUTIVE)' TO WS-REASON
               ADD 1 TO WS-DUPLICATE
           END-IF

           MOVE ORDR-IN-ORDER-ID TO WS-LAST-ORDER-ID

           IF WS-REASON = SPACES
               MOVE ORDR-IN-REC TO OUT-VALID-REC
               WRITE OUT-VALID-REC
               ADD 1 TO WS-VALID
           ELSE
               MOVE WS-REASON TO RJ-REASON
               MOVE ORDR-IN-REC TO RJ-RAW
               WRITE OUT-REJECT-REC
               ADD 1 TO WS-REJECT
           END-IF.

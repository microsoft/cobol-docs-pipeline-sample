       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR150.
      *---------------------------------------------------------------*
      * Enrich validated orders with customer and product master data.
      * Rejects records with missing/inactive references.
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-VALID ASSIGN TO ORDRWK0
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-CUST ASSIGN TO CUSTMST
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-PROD ASSIGN TO PRODMST
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-ENRICH ASSIGN TO ORDRWK1
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-REJECT ASSIGN TO ORDRRJ2
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-VALID
           RECORD CONTAINS 160 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY ORDRIN01.

       FD  IN-CUST
           RECORD CONTAINS 80 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY CUSTMST1.

       FD  IN-PROD
           RECORD CONTAINS 70 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY PRODMST1.

       FD  OUT-ENRICH
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY ORDRWK01.

       FD  OUT-REJECT
           RECORD CONTAINS 220 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       01  OUT-REJECT-REC.
           05 RJ-REASON                  PIC X(60).
           05 RJ-RAW                     PIC X(160).

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-END-IN                  PIC X VALUE 'N'.
              88 END-OF-IN               VALUE 'Y'.
           05 WS-END-CUST                PIC X VALUE 'N'.
              88 END-OF-CUST             VALUE 'Y'.
           05 WS-END-PROD                PIC X VALUE 'N'.
              88 END-OF-PROD             VALUE 'Y'.

       01  WS-COUNTERS.
           05 WS-READ                    PIC 9(9) VALUE ZERO.
           05 WS-WRITTEN                 PIC 9(9) VALUE ZERO.
           05 WS-REJECT                  PIC 9(9) VALUE ZERO.
           05 WS-CUST-LOADED             PIC 9(4) VALUE ZERO.
           05 WS-PROD-LOADED             PIC 9(4) VALUE ZERO.

       01  WS-CUST-TABLE.
           05 WS-CUST-ENTRY OCCURS 500 TIMES
              INDEXED BY CUST-IDX.
               10 WS-CUST-ID             PIC X(10).
               10 WS-CUST-NAME           PIC X(30).
               10 WS-CUST-SEGMENT        PIC X(10).
               10 WS-CUST-STATUS         PIC X(1).

       01  WS-PROD-TABLE.
           05 WS-PROD-ENTRY OCCURS 500 TIMES
              INDEXED BY PROD-IDX.
               10 WS-PROD-CODE           PIC X(12).
               10 WS-PROD-CATEGORY       PIC X(10).
               10 WS-PROD-TAX-GROUP      PIC X(4).
               10 WS-PROD-DISCOUNT       PIC 9V999.
               10 WS-PROD-ACTIVE         PIC X(1).

       01  WS-FLAGS.
           05 WS-CUST-FOUND              PIC X VALUE 'N'.
           05 WS-PROD-FOUND              PIC X VALUE 'N'.

       01  WS-REASON                     PIC X(60).

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR150 RUNNING ***'
           OPEN INPUT IN-CUST IN-PROD IN-VALID
                OUTPUT OUT-ENRICH OUT-REJECT

           PERFORM LOAD-CUSTOMERS
           PERFORM LOAD-PRODUCTS

           PERFORM UNTIL END-OF-IN
               READ IN-VALID
                   AT END
                       SET END-OF-IN TO TRUE
                   NOT AT END
                       ADD 1 TO WS-READ
                       PERFORM ENRICH-RECORD
               END-READ
           END-PERFORM

           CLOSE IN-CUST IN-PROD IN-VALID OUT-ENRICH OUT-REJECT

           DISPLAY 'ORDR150 CUST-LOADED : ' WS-CUST-LOADED
           DISPLAY 'ORDR150 PROD-LOADED : ' WS-PROD-LOADED
           DISPLAY 'ORDR150 READ        : ' WS-READ
           DISPLAY 'ORDR150 WRITTEN     : ' WS-WRITTEN
           DISPLAY 'ORDR150 REJECT      : ' WS-REJECT

           GOBACK.

       LOAD-CUSTOMERS.
           PERFORM UNTIL END-OF-CUST
               READ IN-CUST
                   AT END
                       SET END-OF-CUST TO TRUE
                   NOT AT END
                       ADD 1 TO WS-CUST-LOADED
                       MOVE CUST-MST-ID
                         TO WS-CUST-ID (WS-CUST-LOADED)
                       MOVE CUST-MST-NAME
                         TO WS-CUST-NAME (WS-CUST-LOADED)
                       MOVE CUST-MST-SEGMENT
                         TO WS-CUST-SEGMENT (WS-CUST-LOADED)
                       MOVE CUST-MST-STATUS
                         TO WS-CUST-STATUS (WS-CUST-LOADED)
               END-READ
           END-PERFORM.

       LOAD-PRODUCTS.
           PERFORM UNTIL END-OF-PROD
               READ IN-PROD
                   AT END
                       SET END-OF-PROD TO TRUE
                   NOT AT END
                       ADD 1 TO WS-PROD-LOADED
                       MOVE PROD-MST-CODE
                         TO WS-PROD-CODE (WS-PROD-LOADED)
                       MOVE PROD-MST-CATEGORY
                         TO WS-PROD-CATEGORY (WS-PROD-LOADED)
                       MOVE PROD-MST-TAX-GROUP
                         TO WS-PROD-TAX-GROUP (WS-PROD-LOADED)
                       MOVE PROD-MST-BASE-DISCOUNT
                         TO WS-PROD-DISCOUNT (WS-PROD-LOADED)
                       MOVE PROD-MST-ACTIVE
                         TO WS-PROD-ACTIVE (WS-PROD-LOADED)
               END-READ
           END-PERFORM.

       ENRICH-RECORD.
           MOVE SPACES TO WS-REASON
           MOVE 'N' TO WS-CUST-FOUND WS-PROD-FOUND

           PERFORM VARYING CUST-IDX FROM 1 BY 1
             UNTIL CUST-IDX > WS-CUST-LOADED OR WS-CUST-FOUND = 'Y'
               IF ORDR-IN-CUSTOMER-ID = WS-CUST-ID (CUST-IDX)
                   MOVE 'Y' TO WS-CUST-FOUND
               END-IF
           END-PERFORM

           IF WS-CUST-FOUND NOT = 'Y'
               MOVE 'CUSTOMER NOT FOUND IN MASTER' TO WS-REASON
           END-IF

           IF WS-REASON = SPACES
              AND WS-CUST-STATUS (CUST-IDX) NOT = 'A'
               MOVE 'CUSTOMER IS NOT ACTIVE' TO WS-REASON
           END-IF

           PERFORM VARYING PROD-IDX FROM 1 BY 1
             UNTIL PROD-IDX > WS-PROD-LOADED OR WS-PROD-FOUND = 'Y'
               IF ORDR-IN-PRODUCT-CODE = WS-PROD-CODE (PROD-IDX)
                   MOVE 'Y' TO WS-PROD-FOUND
               END-IF
           END-PERFORM

           IF WS-REASON = SPACES AND WS-PROD-FOUND NOT = 'Y'
               MOVE 'PRODUCT NOT FOUND IN MASTER' TO WS-REASON
           END-IF

           IF WS-REASON = SPACES
              AND WS-PROD-ACTIVE (PROD-IDX) NOT = 'Y'
               MOVE 'PRODUCT IS NOT ACTIVE' TO WS-REASON
           END-IF

           IF WS-REASON = SPACES
               MOVE SPACES TO ORDR-WK-REC
               MOVE ORDR-IN-ORDER-ID TO ORDR-WK-ORDER-ID
               MOVE ORDR-IN-CUSTOMER-ID TO ORDR-WK-CUSTOMER-ID
               MOVE ORDR-IN-CUSTOMER-NAME TO ORDR-WK-CUSTOMER-NAME
               MOVE ORDR-IN-PRODUCT-CODE TO ORDR-WK-PRODUCT-CODE
               MOVE ORDR-IN-QUANTITY TO ORDR-WK-QUANTITY
               MOVE ORDR-IN-UNIT-PRICE TO ORDR-WK-UNIT-PRICE
               MOVE ORDR-IN-ORDER-DATE TO ORDR-WK-ORDER-DATE
               MOVE ORDR-IN-CHANNEL TO ORDR-WK-CHANNEL
               MOVE ORDR-IN-CURRENCY TO ORDR-WK-CURRENCY
               MOVE ORDR-IN-REGION TO ORDR-WK-REGION
               MOVE ORDR-IN-SHIP-MODE TO ORDR-WK-SHIP-MODE
               MOVE ORDR-IN-PROMO-CODE TO ORDR-WK-PROMO-CODE
               MOVE ORDR-IN-SALES-REP TO ORDR-WK-SALES-REP

               MOVE WS-CUST-SEGMENT (CUST-IDX) TO ORDR-WK-CUSTOMER-SEGMENT
               MOVE WS-CUST-STATUS (CUST-IDX) TO ORDR-WK-CUST-STATUS
               MOVE WS-PROD-CATEGORY (PROD-IDX) TO ORDR-WK-PRODUCT-CATEGORY
               MOVE WS-PROD-TAX-GROUP (PROD-IDX) TO ORDR-WK-TAX-GROUP
               MOVE WS-PROD-ACTIVE (PROD-IDX) TO ORDR-WK-PRODUCT-ACTIVE
               MOVE 'E' TO ORDR-WK-STATUS

               WRITE ORDR-WK-REC
               ADD 1 TO WS-WRITTEN
           ELSE
               MOVE WS-REASON TO RJ-REASON
               MOVE ORDR-IN-REC TO RJ-RAW
               WRITE OUT-REJECT-REC
               ADD 1 TO WS-REJECT
           END-IF.

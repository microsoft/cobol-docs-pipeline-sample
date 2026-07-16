       IDENTIFICATION DIVISION.
       PROGRAM-ID. ORDR200.
      *---------------------------------------------------------------*
      * Compute commercial and fiscal amounts.
      * Uses:
      * - tax reference by channel/region/tax-group
      * - fx rates by currency
      * - dynamic discount policy (segment + promo + quantity)
      *---------------------------------------------------------------*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-ENRICH ASSIGN TO ORDRWK1
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-TAX ASSIGN TO TAXREF
               ORGANIZATION IS SEQUENTIAL.
           SELECT IN-FX ASSIGN TO FXRATE
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-CALC ASSIGN TO ORDRWK2
               ORGANIZATION IS SEQUENTIAL.
           SELECT OUT-REJECT ASSIGN TO ORDRRJ3
               ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD  IN-ENRICH
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY ORDRWK01.

       FD  IN-TAX
           RECORD CONTAINS 30 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY TAXREF01.

       FD  IN-FX
           RECORD CONTAINS 20 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       COPY FXRATE01.

       FD  OUT-CALC
           RECORD CONTAINS 240 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       01  OUT-CALC-REC                  PIC X(240).

       FD  OUT-REJECT
           RECORD CONTAINS 300 CHARACTERS
           BLOCK CONTAINS 0 RECORDS.
       01  OUT-REJECT-REC.
           05 RJ-REASON                  PIC X(60).
           05 RJ-RAW                     PIC X(240).

       WORKING-STORAGE SECTION.
       01  WS-END.
           05 WS-END-IN                  PIC X VALUE 'N'.
              88 END-OF-IN               VALUE 'Y'.
           05 WS-END-TAX                 PIC X VALUE 'N'.
              88 END-OF-TAX              VALUE 'Y'.
           05 WS-END-FX                  PIC X VALUE 'N'.
              88 END-OF-FX               VALUE 'Y'.

       01  WS-COUNTERS.
           05 WS-READ                    PIC 9(9) VALUE ZERO.
           05 WS-WRITTEN                 PIC 9(9) VALUE ZERO.
           05 WS-REJECT                  PIC 9(9) VALUE ZERO.
           05 WS-TAX-LOADED              PIC 9(4) VALUE ZERO.
           05 WS-FX-LOADED               PIC 9(4) VALUE ZERO.

       01  WS-TAX-TABLE.
           05 WS-TAX-ENTRY OCCURS 200 TIMES
              INDEXED BY TAX-IDX.
               10 WS-TAX-CHANNEL         PIC X(10).
               10 WS-TAX-REGION          PIC X(3).
               10 WS-TAX-GROUP           PIC X(4).
               10 WS-TAX-RATE-TAB        PIC 9V999.

       01  WS-FX-TABLE.
           05 WS-FX-ENTRY OCCURS 50 TIMES
              INDEXED BY FX-IDX.
               10 WS-FX-CURRENCY         PIC X(3).
               10 WS-FX-RATE             PIC 9(3)V9(6).

       01  WS-FLAGS.
           05 WS-TAX-FOUND               PIC X VALUE 'N'.
           05 WS-FX-FOUND                PIC X VALUE 'N'.

       01  WS-CALC.
           05 WS-REASON                  PIC X(60).
           05 WS-DISCOUNT-RATE           PIC 9V999 VALUE ZERO.
           05 WS-SUBTOTAL                PIC 9(11)V99 VALUE ZERO.
           05 WS-DISCOUNT-AMOUNT         PIC 9(11)V99 VALUE ZERO.
           05 WS-NET-AMOUNT              PIC 9(11)V99 VALUE ZERO.
           05 WS-TAX-RATE                PIC 9V999 VALUE ZERO.
           05 WS-TAX-AMOUNT              PIC 9(11)V99 VALUE ZERO.
           05 WS-TOTAL-AMOUNT            PIC 9(11)V99 VALUE ZERO.
           05 WS-TOTAL-EUR               PIC 9(11)V99 VALUE ZERO.
           05 WS-FX-RATE                 PIC 9(3)V9(6) VALUE ZERO.

       PROCEDURE DIVISION.
       MAIN-SECTION.
           DISPLAY '*** PHASE ORDR200 RUNNING ***'
           OPEN INPUT IN-ENRICH IN-TAX IN-FX
                OUTPUT OUT-CALC OUT-REJECT

           PERFORM LOAD-TAX
           PERFORM LOAD-FX

           PERFORM UNTIL END-OF-IN
               READ IN-ENRICH
                   AT END
                       SET END-OF-IN TO TRUE
                   NOT AT END
                       ADD 1 TO WS-READ
                       PERFORM PRICE-RECORD
               END-READ
           END-PERFORM

           CLOSE IN-ENRICH IN-TAX IN-FX OUT-CALC OUT-REJECT

           DISPLAY 'ORDR200 TAX-LOADED : ' WS-TAX-LOADED
           DISPLAY 'ORDR200 FX-LOADED  : ' WS-FX-LOADED
           DISPLAY 'ORDR200 READ       : ' WS-READ
           DISPLAY 'ORDR200 WRITTEN    : ' WS-WRITTEN
           DISPLAY 'ORDR200 REJECT     : ' WS-REJECT

           GOBACK.

       LOAD-TAX.
           PERFORM UNTIL END-OF-TAX
               READ IN-TAX
                   AT END
                       SET END-OF-TAX TO TRUE
                   NOT AT END
                       ADD 1 TO WS-TAX-LOADED
                       MOVE TAX-REF-CHANNEL
                         TO WS-TAX-CHANNEL (WS-TAX-LOADED)
                       MOVE TAX-REF-REGION
                         TO WS-TAX-REGION (WS-TAX-LOADED)
                       MOVE TAX-REF-TAX-GROUP
                         TO WS-TAX-GROUP (WS-TAX-LOADED)
                       MOVE TAX-REF-RATE
                         TO WS-TAX-RATE-TAB (WS-TAX-LOADED)
               END-READ
           END-PERFORM.

       LOAD-FX.
           PERFORM UNTIL END-OF-FX
               READ IN-FX
                   AT END
                       SET END-OF-FX TO TRUE
                   NOT AT END
                       ADD 1 TO WS-FX-LOADED
                       MOVE FX-RATE-CURRENCY
                         TO WS-FX-CURRENCY (WS-FX-LOADED)
                       MOVE FX-RATE-TO-EUR
                         TO WS-FX-RATE (WS-FX-LOADED)
               END-READ
           END-PERFORM.

       PRICE-RECORD.
           MOVE SPACES TO WS-REASON
           MOVE 'N' TO WS-TAX-FOUND WS-FX-FOUND

           COMPUTE WS-SUBTOTAL = ORDR-WK-QUANTITY * ORDR-WK-UNIT-PRICE

           MOVE 0 TO WS-DISCOUNT-RATE
           IF ORDR-WK-CUSTOMER-SEGMENT = 'GOLD      '
               MOVE 0.030 TO WS-DISCOUNT-RATE
           END-IF
           IF ORDR-WK-CUSTOMER-SEGMENT = 'PLATINUM  '
               MOVE 0.050 TO WS-DISCOUNT-RATE
           END-IF
           IF ORDR-WK-QUANTITY >= 100
               ADD 0.020 TO WS-DISCOUNT-RATE
           END-IF
           IF ORDR-WK-PROMO-CODE = 'SPRING10  '
               ADD 0.010 TO WS-DISCOUNT-RATE
           END-IF
           IF WS-DISCOUNT-RATE > 0.150
               MOVE 0.150 TO WS-DISCOUNT-RATE
           END-IF

           COMPUTE WS-DISCOUNT-AMOUNT = WS-SUBTOTAL * WS-DISCOUNT-RATE
           COMPUTE WS-NET-AMOUNT = WS-SUBTOTAL - WS-DISCOUNT-AMOUNT

           PERFORM VARYING TAX-IDX FROM 1 BY 1
             UNTIL TAX-IDX > WS-TAX-LOADED OR WS-TAX-FOUND = 'Y'
               IF ORDR-WK-CHANNEL = WS-TAX-CHANNEL (TAX-IDX)
                  AND ORDR-WK-REGION = WS-TAX-REGION (TAX-IDX)
                  AND ORDR-WK-TAX-GROUP = WS-TAX-GROUP (TAX-IDX)
                   MOVE WS-TAX-RATE-TAB (TAX-IDX) TO WS-TAX-RATE
                   MOVE 'Y' TO WS-TAX-FOUND
               END-IF
           END-PERFORM

           IF WS-TAX-FOUND NOT = 'Y'
               MOVE 'NO TAX RULE FOR CHANNEL/REGION/TAX-GROUP' TO WS-REASON
           END-IF

           PERFORM VARYING FX-IDX FROM 1 BY 1
             UNTIL FX-IDX > WS-FX-LOADED OR WS-FX-FOUND = 'Y'
               IF ORDR-WK-CURRENCY = WS-FX-CURRENCY (FX-IDX)
                   MOVE WS-FX-RATE (FX-IDX) TO WS-FX-RATE
                   MOVE 'Y' TO WS-FX-FOUND
               END-IF
           END-PERFORM

           IF WS-REASON = SPACES AND WS-FX-FOUND NOT = 'Y'
               MOVE 'NO FX RATE FOR CURRENCY' TO WS-REASON
           END-IF

           IF WS-REASON = SPACES
               COMPUTE WS-TAX-AMOUNT = WS-NET-AMOUNT * WS-TAX-RATE
               COMPUTE WS-TOTAL-AMOUNT = WS-NET-AMOUNT + WS-TAX-AMOUNT
               COMPUTE WS-TOTAL-EUR = WS-TOTAL-AMOUNT * WS-FX-RATE

               MOVE WS-SUBTOTAL TO ORDR-WK-SUBTOTAL
               MOVE WS-DISCOUNT-RATE TO ORDR-WK-DISCOUNT-RATE
               MOVE WS-DISCOUNT-AMOUNT TO ORDR-WK-DISCOUNT-AMOUNT
               MOVE WS-NET-AMOUNT TO ORDR-WK-NET-AMOUNT
               MOVE WS-TAX-RATE TO ORDR-WK-TAX-RATE
               MOVE WS-TAX-AMOUNT TO ORDR-WK-TAX-AMOUNT
               MOVE WS-TOTAL-AMOUNT TO ORDR-WK-TOTAL-AMOUNT
               MOVE WS-TOTAL-EUR TO ORDR-WK-TOTAL-EUR
               MOVE WS-FX-RATE TO ORDR-WK-FX-RATE
               MOVE 'P' TO ORDR-WK-STATUS

               MOVE ORDR-WK-REC TO OUT-CALC-REC
               WRITE OUT-CALC-REC
               ADD 1 TO WS-WRITTEN
           ELSE
               MOVE WS-REASON TO RJ-REASON
               MOVE ORDR-WK-REC TO RJ-RAW
               WRITE OUT-REJECT-REC
               ADD 1 TO WS-REJECT
           END-IF.

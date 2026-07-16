      *****************************************************************
      * ORDRWK01 - Enriched/Calculated Working Record (240 bytes)
      *****************************************************************
       01  ORDR-WK-REC.
           05 ORDR-WK-ORDER-ID           PIC X(12).
           05 ORDR-WK-CUSTOMER-ID        PIC X(10).
           05 ORDR-WK-CUSTOMER-NAME      PIC X(30).
           05 ORDR-WK-PRODUCT-CODE       PIC X(12).
           05 ORDR-WK-QUANTITY            PIC 9(5).
           05 ORDR-WK-UNIT-PRICE          PIC 9(7)V99.
           05 ORDR-WK-SUBTOTAL            PIC 9(11)V99.
           05 ORDR-WK-DISCOUNT-RATE       PIC 9V999.
           05 ORDR-WK-DISCOUNT-AMOUNT     PIC 9(11)V99.
           05 ORDR-WK-NET-AMOUNT          PIC 9(11)V99.
           05 ORDR-WK-TAX-RATE            PIC 9V999.
           05 ORDR-WK-TAX-AMOUNT          PIC 9(11)V99.
           05 ORDR-WK-TOTAL-AMOUNT        PIC 9(11)V99.
           05 ORDR-WK-TOTAL-EUR           PIC 9(11)V99.
           05 ORDR-WK-FX-RATE             PIC 9(3)V9(6).
           05 ORDR-WK-ORDER-DATE          PIC 9(8).
           05 ORDR-WK-CHANNEL             PIC X(10).
           05 ORDR-WK-CURRENCY            PIC X(3).
           05 ORDR-WK-REGION              PIC X(3).
           05 ORDR-WK-SHIP-MODE           PIC X(8).
           05 ORDR-WK-PROMO-CODE          PIC X(10).
           05 ORDR-WK-SALES-REP           PIC X(10).
           05 ORDR-WK-CUSTOMER-SEGMENT    PIC X(10).
           05 ORDR-WK-CUST-STATUS         PIC X(1).
           05 ORDR-WK-PRODUCT-CATEGORY    PIC X(10).
           05 ORDR-WK-TAX-GROUP           PIC X(4).
           05 ORDR-WK-PRODUCT-ACTIVE      PIC X(1).
           05 ORDR-WK-STATUS              PIC X(1).
           05 ORDR-WK-FILLER              PIC X(14).

      *****************************************************************
      * ORDRIN01 - Input Order Record (160 bytes)
      *****************************************************************
       01  ORDR-IN-REC.
           05 ORDR-IN-ORDER-ID           PIC X(12).
           05 ORDR-IN-CUSTOMER-ID        PIC X(10).
           05 ORDR-IN-CUSTOMER-NAME      PIC X(30).
           05 ORDR-IN-PRODUCT-CODE       PIC X(12).
           05 ORDR-IN-QUANTITY            PIC 9(5).
           05 ORDR-IN-UNIT-PRICE          PIC 9(7)V99.
           05 ORDR-IN-ORDER-DATE          PIC 9(8).
           05 ORDR-IN-CHANNEL             PIC X(10).
           05 ORDR-IN-CURRENCY            PIC X(3).
           05 ORDR-IN-REGION              PIC X(3).
           05 ORDR-IN-SHIP-MODE           PIC X(8).
           05 ORDR-IN-PROMO-CODE          PIC X(10).
           05 ORDR-IN-SALES-REP           PIC X(10).
           05 ORDR-IN-FILLER              PIC X(39).

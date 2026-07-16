      *****************************************************************
      * ORDROUT1 - Final Statement / Summary Record (240 bytes)
      *****************************************************************
       01  ORDR-OUT-REC.
           05 ORDR-OUT-TYPE              PIC X(1).
           05 ORDR-OUT-ORDER-ID          PIC X(12).
           05 ORDR-OUT-CUSTOMER-ID       PIC X(10).
           05 ORDR-OUT-CUSTOMER-NAME     PIC X(30).
           05 ORDR-OUT-PRODUCT-CODE      PIC X(12).
           05 ORDR-OUT-CATEGORY          PIC X(10).
           05 ORDR-OUT-SEGMENT           PIC X(10).
           05 ORDR-OUT-QUANTITY           PIC Z(5).
           05 ORDR-OUT-UNIT-PRICE         PIC Z(7).99.
           05 ORDR-OUT-SUBTOTAL           PIC Z(11).99.
           05 ORDR-OUT-DISCOUNT           PIC Z(11).99.
           05 ORDR-OUT-NET                PIC Z(11).99.
           05 ORDR-OUT-TAX-AMOUNT         PIC Z(11).99.
           05 ORDR-OUT-TOTAL-AMOUNT       PIC Z(11).99.
           05 ORDR-OUT-TOTAL-EUR          PIC Z(11).99.
           05 ORDR-OUT-ORDER-DATE         PIC 9(8).
           05 ORDR-OUT-CHANNEL            PIC X(10).
           05 ORDR-OUT-CURRENCY           PIC X(3).
           05 ORDR-OUT-REGION             PIC X(3).
           05 ORDR-OUT-SHIP-MODE          PIC X(8).
           05 ORDR-OUT-PROMO-CODE         PIC X(10).
           05 ORDR-OUT-FILLER             PIC X(2).

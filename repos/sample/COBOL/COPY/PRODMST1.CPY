      *****************************************************************
    * PRODMST1 - Product Master Record (70 bytes)
      *****************************************************************
       01  PROD-MST-REC.
           05 PROD-MST-CODE              PIC X(12).
           05 PROD-MST-DESCRIPTION       PIC X(24).
           05 PROD-MST-CATEGORY          PIC X(10).
           05 PROD-MST-TAX-GROUP         PIC X(4).
           05 PROD-MST-BASE-DISCOUNT     PIC 9V999.
           05 PROD-MST-ACTIVE            PIC X(1).
           05 PROD-MST-FILLER            PIC X(15).

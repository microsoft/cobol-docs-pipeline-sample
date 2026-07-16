      *****************************************************************
      * CUSTMST1 - Customer Master Record (80 bytes)
      *****************************************************************
       01  CUST-MST-REC.
           05 CUST-MST-ID                PIC X(10).
           05 CUST-MST-NAME              PIC X(30).
           05 CUST-MST-SEGMENT           PIC X(10).
           05 CUST-MST-STATUS            PIC X(1).
           05 CUST-MST-RISK-COUNTRY      PIC X(3).
           05 CUST-MST-CREDIT-LIMIT      PIC 9(9)V99.
           05 CUST-MST-PAYMENT-TERMS     PIC X(4).
           05 CUST-MST-FILLER            PIC X(11).

      *****************************************************************
      * TAXREF01 - Tax rule by channel/region/tax-group (30 bytes)
      *****************************************************************
       01  TAX-REF-REC.
           05 TAX-REF-CHANNEL            PIC X(10).
           05 TAX-REF-REGION             PIC X(3).
           05 TAX-REF-TAX-GROUP          PIC X(4).
           05 TAX-REF-RATE               PIC 9V999.
           05 TAX-REF-FILLER             PIC X(9).

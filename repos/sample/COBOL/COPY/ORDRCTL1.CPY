      *****************************************************************
      * ORDRCTL1 - Structured Control Record (120 bytes)
      *****************************************************************
       01  ORDR-CTL-REC.
           05 ORDR-CTL-RUN-ID            PIC X(8).
           05 ORDR-CTL-METRIC            PIC X(20).
           05 ORDR-CTL-CHANNEL           PIC X(10).
           05 ORDR-CTL-MEASURE-TYPE      PIC X(1).
           05 ORDR-CTL-COUNT-VALUE       PIC 9(9).
           05 ORDR-CTL-AMOUNT-VALUE      PIC 9(13)V99.
           05 ORDR-CTL-FILLER            PIC X(57).

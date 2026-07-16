      *****************************************************************
      * RISKALR1 - Risk anomaly alert record (220 bytes)
      *****************************************************************
       01  RISK-ALERT-REC.
           05 RISK-RUN-ID                PIC X(8).
           05 RISK-METRIC                PIC X(20).
           05 RISK-CHANNEL               PIC X(10).
           05 RISK-MEASURE-TYPE          PIC X(1).
           05 RISK-CURRENT-COUNT         PIC 9(9).
           05 RISK-AVG-COUNT             PIC 9(9).
           05 RISK-CURRENT-AMOUNT        PIC 9(13)V99.
           05 RISK-AVG-AMOUNT            PIC 9(13)V99.
           05 RISK-DELTA-PCT             PIC 9(3)V99.
           05 RISK-SEVERITY              PIC X(1).
           05 RISK-ROUTE                 PIC X(8).
           05 RISK-MESSAGE               PIC X(85).
           05 RISK-FILLER                PIC X(19).

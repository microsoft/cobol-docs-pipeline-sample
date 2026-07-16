      *****************************************************************
      * KPITRD1 - KPI trend deviation alert record (240 bytes)
      *****************************************************************
       01  KPI-TRD-REC.
           05 KPI-TRD-RUN-ID             PIC X(8).
           05 KPI-TRD-METRIC             PIC X(20).
           05 KPI-TRD-CATEGORY           PIC X(10).
           05 KPI-TRD-CURR-COUNT         PIC 9(9).
           05 KPI-TRD-BASE-COUNT         PIC 9(9).
           05 KPI-TRD-CURR-AMOUNT        PIC 9(13)V99.
           05 KPI-TRD-BASE-AMOUNT        PIC 9(13)V99.
           05 KPI-TRD-CURR-RATE          PIC 9(3)V99.
           05 KPI-TRD-BASE-RATE          PIC 9(3)V99.
           05 KPI-TRD-DELTA-PCT          PIC 9(3)V99.
           05 KPI-TRD-SEVERITY           PIC X(1).
           05 KPI-TRD-MESSAGE            PIC X(126).
           05 KPI-TRD-FILLER             PIC X(11).
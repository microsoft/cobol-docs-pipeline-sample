      *****************************************************************
      * KPIRPT1 - Governance KPI report record (240 bytes)
      *****************************************************************
       01  KPI-RPT-REC.
           05 KPI-RPT-RUN-ID             PIC X(8).
           05 KPI-RPT-CATEGORY           PIC X(10).
           05 KPI-RPT-METRIC             PIC X(20).
           05 KPI-RPT-COUNT              PIC 9(9).
           05 KPI-RPT-AMOUNT             PIC 9(13)V99.
           05 KPI-RPT-RATE               PIC 9(3)V99.
           05 KPI-RPT-SEVERITY           PIC X(1).
           05 KPI-RPT-MESSAGE            PIC X(150).
           05 KPI-RPT-FILLER             PIC X(20).
      *****************************************************************
      * KPIHST1 - Historical KPI baseline record (120 bytes)
      *****************************************************************
       01  KPI-HST-REC.
           05 KPI-HST-METRIC             PIC X(20).
           05 KPI-HST-AVG-COUNT          PIC 9(9).
           05 KPI-HST-AVG-AMOUNT         PIC 9(13)V99.
           05 KPI-HST-AVG-RATE           PIC 9(3)V99.
           05 KPI-HST-FILLER             PIC X(70).
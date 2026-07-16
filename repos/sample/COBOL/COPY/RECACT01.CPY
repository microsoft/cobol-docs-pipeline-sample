      *****************************************************************
      * RECACT01 - Recommended recovery action (220 bytes)
      *****************************************************************
       01  REC-ACT-REC.
           05 REC-ACT-RUN-ID             PIC X(8).
           05 REC-ACT-SOURCE             PIC X(10).
           05 REC-ACT-SEVERITY           PIC X(1).
           05 REC-ACT-ROUTE              PIC X(8).
           05 REC-ACT-PRIORITY           PIC 9(2).
           05 REC-ACT-ACTION             PIC X(20).
           05 REC-ACT-AUTO-FLAG          PIC X(1).
           05 REC-ACT-TARGET-STAGE       PIC X(8).
           05 REC-ACT-REASON             PIC X(120).
           05 REC-ACT-FILLER             PIC X(42).

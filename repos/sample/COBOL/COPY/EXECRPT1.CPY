      *****************************************************************
      * EXECRPT1 - Executive run report record (240 bytes)
      *****************************************************************
       01  EXEC-RPT-REC.
           05 EXEC-RPT-RUN-ID            PIC X(8).
           05 EXEC-RPT-LINE-TYPE         PIC X(10).
           05 EXEC-RPT-METRIC            PIC X(20).
           05 EXEC-RPT-CHANNEL           PIC X(10).
           05 EXEC-RPT-COUNT             PIC 9(9).
           05 EXEC-RPT-AMOUNT            PIC 9(13)V99.
           05 EXEC-RPT-SEV1              PIC 9(9).
           05 EXEC-RPT-SEV2              PIC 9(9).
           05 EXEC-RPT-ACTION-COUNT      PIC 9(9).
           05 EXEC-RPT-HIGH-PRIORITY     PIC 9(9).
           05 EXEC-RPT-RESTART-STAGE     PIC X(8).
           05 EXEC-RPT-MESSAGE           PIC X(120).
           05 EXEC-RPT-FILLER            PIC X(15).
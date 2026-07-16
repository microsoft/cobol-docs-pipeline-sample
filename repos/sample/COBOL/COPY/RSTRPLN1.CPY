      *****************************************************************
      * RSTRPLN1 - Restart and operations plan record (160 bytes)
      *****************************************************************
       01  RST-PLAN-REC.
           05 RST-PLAN-RUN-ID            PIC X(8).
           05 RST-PLAN-MODE              PIC X(3).
           05 RST-PLAN-ACTION            PIC X(20).
           05 RST-PLAN-NEXT-STAGE        PIC X(8).
           05 RST-PLAN-SEVERITY          PIC X(1).
           05 RST-PLAN-ROUTE             PIC X(8).
           05 RST-PLAN-SEV1-COUNT        PIC 9(9).
           05 RST-PLAN-SEV2-COUNT        PIC 9(9).
           05 RST-PLAN-MESSAGE           PIC X(84).
           05 RST-PLAN-FILLER            PIC X(10).

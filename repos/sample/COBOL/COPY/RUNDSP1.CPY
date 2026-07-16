      *****************************************************************
      * RUNDSP1 - Run disposition record (200 bytes)
      *****************************************************************
       01  RUN-DSP-REC.
           05 RUN-DSP-RUN-ID             PIC X(8).
           05 RUN-DSP-STATUS             PIC X(6).
           05 RUN-DSP-SEVERITY           PIC X(1).
           05 RUN-DSP-RESTART-STAGE      PIC X(8).
           05 RUN-DSP-RED-SIGNALS        PIC 9(5).
           05 RUN-DSP-AMBER-SIGNALS      PIC 9(5).
           05 RUN-DSP-KPI-CRIT           PIC 9(5).
           05 RUN-DSP-SLA-CRIT           PIC 9(5).
           05 RUN-DSP-KPI-WARN           PIC 9(5).
           05 RUN-DSP-SLA-WARN           PIC 9(5).
           05 RUN-DSP-MESSAGE            PIC X(147).
           05 RUN-DSP-FILLER             PIC X(10).
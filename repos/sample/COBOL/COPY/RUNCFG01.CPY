      *****************************************************************
      * RUNCFG01 - Runtime policy configuration (80 bytes)
      *****************************************************************
       01  RUN-CFG-REC.
           05 RUN-CFG-RUN-MODE           PIC X(3).
           05 RUN-CFG-AMOUNT-TOL         PIC 9(7)V99.
           05 RUN-CFG-STRICT-FLAG        PIC X(1).
           05 RUN-CFG-MIN-SEV2-FAIL      PIC 9(5).
           05 RUN-CFG-MIN-SEV1-FAIL      PIC 9(5).
           05 RUN-CFG-ANOMALY-PCT        PIC 9(3)V99.
           05 RUN-CFG-FILLER             PIC X(52).

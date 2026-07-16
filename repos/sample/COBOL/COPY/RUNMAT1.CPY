      *****************************************************************
      * RUNMAT1 - Deterministic runbook action matrix (240 bytes)
      *****************************************************************
       01  RUN-MAT-REC.
           05 RUN-MAT-RUN-ID             PIC X(8).
           05 RUN-MAT-STEP               PIC X(8).
           05 RUN-MAT-ARTIFACT           PIC X(20).
           05 RUN-MAT-OWNER              PIC X(8).
           05 RUN-MAT-ACTION             PIC X(24).
           05 RUN-MAT-URGENCY            PIC X(6).
           05 RUN-MAT-PRIORITY           PIC 9(2).
           05 RUN-MAT-DISPOSITION        PIC X(6).
           05 RUN-MAT-NOTE               PIC X(154).
           05 RUN-MAT-FILLER             PIC X(11).
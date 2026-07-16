      *****************************************************************
      * ACTSTAT1 - Action execution status record (240 bytes)
      *****************************************************************
       01  ACT-STAT-REC.
           05 ACT-STAT-RUN-ID            PIC X(8).
           05 ACT-STAT-SOURCE            PIC X(10).
           05 ACT-STAT-ACTION            PIC X(20).
           05 ACT-STAT-TARGET-STAGE      PIC X(8).
           05 ACT-STAT-PRIORITY          PIC 9(2).
           05 ACT-STAT-AUTO-FLAG         PIC X(1).
           05 ACT-STAT-STATUS            PIC X(12).
           05 ACT-STAT-OWNER             PIC X(8).
           05 ACT-STAT-TICKET            PIC X(12).
           05 ACT-STAT-REASON            PIC X(120).
           05 ACT-STAT-FILLER            PIC X(39).
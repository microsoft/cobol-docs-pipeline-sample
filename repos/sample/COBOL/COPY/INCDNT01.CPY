      *****************************************************************
      * INCDNT01 - Incident event record (220 bytes)
      *****************************************************************
       01  INC-REC.
           05 INC-RUN-ID                 PIC X(8).
           05 INC-STAGE                  PIC X(8).
           05 INC-SOURCE                 PIC X(10).
           05 INC-SEVERITY               PIC X(1).
           05 INC-ROUTE-CODE             PIC X(8).
           05 INC-KEY                    PIC X(20).
           05 INC-MESSAGE                PIC X(120).
           05 INC-FILLER                 PIC X(45).

      *****************************************************************
      * CKPSTAT1 - Checkpoint status record (120 bytes)
      *****************************************************************
       01  CKP-REC.
           05 CKP-RUN-ID                 PIC X(8).
           05 CKP-STAGE                  PIC X(8).
           05 CKP-STATUS                 PIC X(1).
           05 CKP-RUN-MODE               PIC X(3).
           05 CKP-TS                     PIC X(14).
           05 CKP-PROCESSED              PIC 9(9).
           05 CKP-REJECTED               PIC 9(9).
           05 CKP-FAILED                 PIC 9(9).
           05 CKP-FILLER                 PIC X(59).

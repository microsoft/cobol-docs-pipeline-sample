      *****************************************************************
      * AUDIDX1 - Audit evidence export index record (240 bytes)
      *****************************************************************
       01  AUD-IDX-REC.
           05 AUD-IDX-RUN-ID             PIC X(8).
           05 AUD-IDX-ARTIFACT           PIC X(20).
           05 AUD-IDX-STAGE              PIC X(8).
           05 AUD-IDX-STATUS             PIC X(10).
           05 AUD-IDX-RETENTION-DAYS     PIC 9(4).
           05 AUD-IDX-HANDOFF            PIC X(10).
           05 AUD-IDX-EXPORT-CLASS       PIC X(8).
           05 AUD-IDX-PACKAGE-ID         PIC X(16).
           05 AUD-IDX-SUMMARY            PIC X(150).
           05 AUD-IDX-FILLER             PIC X(6).
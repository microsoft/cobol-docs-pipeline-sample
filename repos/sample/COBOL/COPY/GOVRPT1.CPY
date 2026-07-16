      *****************************************************************
      * GOVRPT1 - Governance narrative report record (240 bytes)
      *****************************************************************
       01  GOV-RPT-REC.
           05 GOV-RPT-RUN-ID             PIC X(8).
           05 GOV-RPT-LINE-TYPE          PIC X(12).
           05 GOV-RPT-STATUS             PIC X(6).
           05 GOV-RPT-SEVERITY           PIC X(1).
           05 GOV-RPT-KEY                PIC X(20).
           05 GOV-RPT-COUNT              PIC 9(9).
           05 GOV-RPT-AMOUNT             PIC 9(13)V99.
           05 GOV-RPT-RATE               PIC 9(3)V99.
           05 GOV-RPT-MESSAGE            PIC X(158).
           05 GOV-RPT-FILLER             PIC X(10).
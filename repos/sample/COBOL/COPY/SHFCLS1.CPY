      *****************************************************************
      * SHFCLS1 - Shift-close certification package (240 bytes)
      *****************************************************************
       01  SHF-CLS-REC.
           05 SHF-CLS-RUN-ID             PIC X(8).
           05 SHF-CLS-LINE-TYPE          PIC X(10).
           05 SHF-CLS-STATUS             PIC X(12).
           05 SHF-CLS-OWNER              PIC X(8).
           05 SHF-CLS-TOTAL-EVENTS       PIC 9(7).
           05 SHF-CLS-RED-EVENTS         PIC 9(7).
           05 SHF-CLS-AMBER-EVENTS       PIC 9(7).
           05 SHF-CLS-ACTIONS-TOTAL      PIC 9(7).
           05 SHF-CLS-ACTIONS-PENDING    PIC 9(7).
           05 SHF-CLS-CERT-FLAG          PIC X(1).
           05 SHF-CLS-MESSAGE            PIC X(170).
           05 SHF-CLS-FILLER             PIC X(4).
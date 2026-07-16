      *****************************************************************
      * SLALRT1 - SLA breach alert record (240 bytes)
      *****************************************************************
       01  SLA-ALERT-REC.
           05 SLA-RUN-ID                 PIC X(8).
           05 SLA-LINE-TYPE              PIC X(10).
           05 SLA-TICKET                 PIC X(12).
           05 SLA-OWNER                  PIC X(8).
           05 SLA-SEVERITY               PIC X(1).
           05 SLA-BREACH-CODE            PIC X(12).
           05 SLA-PRIORITY               PIC 9(2).
           05 SLA-TARGET-STAGE           PIC X(8).
           05 SLA-STATUS                 PIC X(12).
           05 SLA-MESSAGE                PIC X(140).
           05 SLA-FILLER                 PIC X(27).
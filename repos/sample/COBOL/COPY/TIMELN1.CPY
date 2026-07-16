      *****************************************************************
      * TIMELN1 - Incident bridge timeline feed (240 bytes)
      *****************************************************************
       01  TIMELN-REC.
           05 TIMELN-RUN-ID              PIC X(8).
           05 TIMELN-SEQ                 PIC 9(6).
           05 TIMELN-SOURCE              PIC X(10).
           05 TIMELN-OWNER               PIC X(8).
           05 TIMELN-STAGE               PIC X(8).
           05 TIMELN-URGENCY             PIC X(6).
           05 TIMELN-STATUS              PIC X(12).
           05 TIMELN-TICKET              PIC X(12).
           05 TIMELN-EVENT               PIC X(24).
           05 TIMELN-MESSAGE             PIC X(140).
           05 TIMELN-FILLER              PIC X(10).
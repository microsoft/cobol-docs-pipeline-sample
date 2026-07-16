       IDENTIFICATION DIVISION.
       PROGRAM-ID. DEMO100.
       AUTHOR. SAMPLE.
      ******************************************************************
      *  Minimal sample used by the cobol-chunking skill tests.        *
      ******************************************************************
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. IBM-390.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT INPUT-FILE ASSIGN TO INFILE.
       DATA DIVISION.
       FILE SECTION.
       FD  INPUT-FILE.
       01  INPUT-RECORD              PIC X(80).
       WORKING-STORAGE SECTION.
       01  WS-COUNTER                PIC 9(05) VALUE ZERO.
       PROCEDURE DIVISION.
       MAIN-PROCESSING SECTION.
       A000-MAIN.
           PERFORM A110-INIT-LOGIT.
           PERFORM B200-CONTROLLO-PARAMETRO.
           STOP RUN.
       A110-INIT-LOGIT SECTION.
           DISPLAY 'INIT'.
       B200-CONTROLLO-PARAMETRO SECTION.
           DISPLAY 'CHECK PARAM'.
           IF WS-COUNTER = ZERO
               DISPLAY 'ZERO'
           END-IF.
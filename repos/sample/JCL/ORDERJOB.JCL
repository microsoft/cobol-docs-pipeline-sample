//ORDERJOB JOB (ACCT),'ORDER BATCH',CLASS=A,MSGCLASS=X,NOTIFY=&SYSUID
//*---------------------------------------------------------------
//* ORDERJOB - Run daily order settlement
//*---------------------------------------------------------------
//RUN      EXEC ORDERP1,HLQ='DEMO.BATCH',RUNDT='20260623'
//

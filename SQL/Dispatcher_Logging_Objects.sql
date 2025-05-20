SET DEFINE OFF;


CREATE SEQUENCE DISPATCHER_FILE_LOG_0
  START WITH 1
  MAXVALUE 9999999999999999999999999999
  MINVALUE 0
  NOCYCLE
  NOCACHE
  NOORDER;


CREATE SEQUENCE DISPATCHER_LOG_APP_0
  START WITH 1
  MAXVALUE 9999999999999999999999999999
  MINVALUE 0
  NOCYCLE
  NOCACHE
  NOORDER;
  
CREATE TABLE DISPATCHER_FILE_LOG
(
  TIME_STAMP       DATE,
  FILE_NAME        VARCHAR2(200 BYTE),
  FILE_PATH        VARCHAR2(50 BYTE),
  REMOTE_FTP       VARCHAR2(100 BYTE),
  START_TIME       DATE,
  END_TIME         DATE,
  DOC_SIZE_BYTES   INTEGER,
  INSTANCE_NAME    VARCHAR2(100 BYTE),
  WORKER_ID        VARCHAR2(50 BYTE),
  TRANSFER_ID      VARCHAR2(50 BYTE),
  PROCESS_ID       VARCHAR2(50 BYTE),
  PK               NUMBER,
  REMOTE_FOLDER    VARCHAR2(100 BYTE),
  TRANSFER_STATUS  INTEGER,
  TRANSFER_INFO    VARCHAR2(50 BYTE)
);


CREATE TABLE DISPATCHER_LOG_APP
(
  TIME_STAMP     DATE,
  FUNCTION_NAME  VARCHAR2(100 BYTE),
  MESSAGE_BODY   VARCHAR2(1000 BYTE),
  INSTANCE_NAME  VARCHAR2(100 BYTE),
  PROCESS_ID     VARCHAR2(50 BYTE),
  PK             NUMBER,
  WORKER_ID      VARCHAR2(50 BYTE),
  REMOTE_FTP     VARCHAR2(100 BYTE)
);


CREATE UNIQUE INDEX DISPATCHER_FILE_LOG_PK ON DISPATCHER_FILE_LOG
(PK);


CREATE UNIQUE INDEX DISPATCHER_LOG_APP_PK ON DISPATCHER_LOG_APP
(PK);


CREATE INDEX IDX_DISPATCHER_APP_PROCESSID ON DISPATCHER_LOG_APP
(PROCESS_ID);


CREATE INDEX IDX_DISPATCHER_APP_TIMESTAMP ON DISPATCHER_LOG_APP
(TIME_STAMP);


CREATE INDEX IDX_DISPATCHER_APP_WORKERID ON DISPATCHER_LOG_APP
(WORKER_ID);


CREATE INDEX IDX_DISPATCHER_FILE_PROCESSID ON DISPATCHER_FILE_LOG
(PROCESS_ID);


CREATE INDEX IDX_DISPATCHER_FILE_TIMESTAMP ON DISPATCHER_FILE_LOG
(TIME_STAMP);


CREATE INDEX IDX_DISPATCHER_FILE_WORKERID ON DISPATCHER_FILE_LOG
(WORKER_ID);


CREATE OR REPLACE TRIGGER DISPATCHER_FILE_LOG_PK_BLD
                    BEFORE INSERT
                    ON DISPATCHER_FILE_LOG
                    REFERENCING NEW AS NEW OLD AS OLD
                    FOR EACH ROW
DECLARE
       last_Sequence   NUMBER;
       last_InsertID   NUMBER;
    BEGIN
       IF (:NEW.PK IS NULL)
       THEN
          SELECT DISPATCHER_FILE_LOG_0.NEXTVAL INTO :NEW.PK FROM DUAL;
       ELSE
          SELECT Last_Number - 1
            INTO last_Sequence
            FROM User_Sequences
           WHERE Sequence_Name = 'DISPATCHER_FILE_LOG_0';

          SELECT :NEW.PK INTO last_InsertID FROM DUAL;

          WHILE (last_InsertID > last_Sequence)
          LOOP
             SELECT DISPATCHER_FILE_LOG_0.NEXTVAL INTO last_Sequence FROM DUAL;
          END LOOP;
       END IF;
    END;
/


CREATE OR REPLACE TRIGGER DISPATCHER_LOG_APP_PK_BLD
                    BEFORE INSERT
                    ON DISPATCHER_LOG_APP
                    REFERENCING NEW AS NEW OLD AS OLD
                    FOR EACH ROW
DECLARE
       last_Sequence   NUMBER;
       last_InsertID   NUMBER;
    BEGIN
       IF (:NEW.PK IS NULL)
       THEN
          SELECT DISPATCHER_LOG_APP_0.NEXTVAL INTO :NEW.PK FROM DUAL;
       ELSE
          SELECT Last_Number - 1
            INTO last_Sequence
            FROM User_Sequences
           WHERE Sequence_Name = 'DISPATCHER_LOG_APP_0';

          SELECT :NEW.PK INTO last_InsertID FROM DUAL;

          WHILE (last_InsertID > last_Sequence)
          LOOP
             SELECT DISPATCHER_LOG_APP_0.NEXTVAL INTO last_Sequence FROM DUAL;
          END LOOP;
       END IF;
    END;
/


ALTER TABLE DISPATCHER_FILE_LOG ADD (
  CONSTRAINT DISPATCHER_FILE_LOG_PK
  PRIMARY KEY
  (PK)
  USING INDEX DISPATCHER_FILE_LOG_PK
  ENABLE VALIDATE);

ALTER TABLE DISPATCHER_LOG_APP ADD (
  CONSTRAINT DISPATCHER_LOG_APP_PK
  PRIMARY KEY
  (PK)
  USING INDEX DISPATCHER_LOG_APP_PK
  ENABLE VALIDATE);
  
  
CREATE OR REPLACE package FTP_DISPATCHER_SERVICE is

  -- Author  : UTULLO
  -- Created : 17/04/2024 10:37:07
  -- Purpose : Domain Service per la gestione del DISPATCHER SERVICE usato in contesto C4C
  

  -- Public function and procedure declarations
  
  -- Elimina i dati delle esecuzioni del Dispatcher più vecchi di logRetentionInDays
  procedure Purge_Logs_Older_Than(logRetentionInDays IN NUMBER, targetServiceName IN VARCHAR2 DEFAULT NULL);

end FTP_DISPATCHER_SERVICE;

/


CREATE OR REPLACE package body FTP_DISPATCHER_SERVICE is


  
  /** Private Functions **/
  
  -- none
  
  
  

  /** Public Methods **/    



  -- Elimina i dati delle esecuzioni del Dispatcher più vecchi di logRetentionInDays
  procedure Purge_Logs_Older_Than(logRetentionInDays IN NUMBER, targetServiceName IN VARCHAR2 DEFAULT NULL) is
     PRAGMA AUTONOMOUS_TRANSACTION;  
  
     thresholdDate DATE;
     
     serviceLogsDeleted     NUMBER;
     ftpLogsDeleted         NUMBER;
     totalRecordDeleted     NUMBER;     
     
  begin
     -- Guard clause
     if (NVL(logRetentionInDays, 0) < 1) then
        RAISE_APPLICATION_ERROR(-20001, 'logRetentionInDays must be NOT NULL and greater than zero');
     end if;
     
     thresholdDate := TRUNC(SYSDATE) - logRetentionInDays;
     
     -- Cancellazione Log connessioni FTP
     DELETE FROM DISPATCHER_FILE_LOG
      WHERE PROCESS_ID IN (
                           SELECT SVC.PROCESS_ID
                              FROM DISPATCHER_LOG_APP SVC
                             WHERE (SVC.TIME_STAMP < thresholdDate)
                               AND ((targetServiceName IS NULL) OR (UPPER(SVC.INSTANCE_NAME) = UPPER(targetServiceName)))
                             GROUP BY SVC.PROCESS_ID
                          );
     ftpLogsDeleted := NVL(SQL%ROWCOUNT, 0);
     
     -- Cancellazione Log esecuzioni Dispatcher
     DELETE FROM DISPATCHER_LOG_APP
      WHERE PROCESS_ID IN (
                           SELECT SVC.PROCESS_ID
                              FROM DISPATCHER_LOG_APP SVC
                             WHERE (SVC.TIME_STAMP < thresholdDate)
                               AND ((targetServiceName IS NULL) OR (UPPER(SVC.INSTANCE_NAME) = UPPER(targetServiceName)))
                             GROUP BY SVC.PROCESS_ID
                          );
     serviceLogsDeleted := NVL(SQL%ROWCOUNT, 0);
     
     -- In caso fosse necessario
     totalRecordDeleted := ftpLogsDeleted + serviceLogsDeleted;
     
     COMMIT;
  
  end Purge_Logs_Older_Than;



end FTP_DISPATCHER_SERVICE;

/




CREATE OR REPLACE FORCE VIEW DYN_DISPATCHERS_DATA_MONITOR
AS
   WITH DATA_SOURCE_SETTINGS
        AS (SELECT SYSDATE CURRENT_TS, 5 TIME_WINDOW_SIZE_IN_DAYS FROM DUAL),
        -- Definizione filtro temporale QUI
        SERVICE_EXECUTION_PKS
        AS (  SELECT SVC.PROCESS_ID, COUNT (*) NUMBER_OF_LOGS
                FROM DISPATCHER_LOG_APP SVC, DATA_SOURCE_SETTINGS DSS
               WHERE (SVC.TIME_STAMP >=
                         (TRUNC (DSS.CURRENT_TS) - DSS.TIME_WINDOW_SIZE_IN_DAYS))
            GROUP BY SVC.PROCESS_ID),
        -- Dati esecuzione SERVIZIO COMPLETO (rilevati dal logger dell'intero servizio)
        -- Un singolo servizio Dispatcher gestisce N thread, ognuno dei quali gestisce una connessione FTP

        -- Sommario dati esecuzione singolo servizio Dispatcher
        SERVICE_EXECUTION_SUMMARY
        AS (  SELECT SVC.PROCESS_ID,
                     SVC.INSTANCE_NAME SERVICE_NAME,
                     MIN (PK) EXECUTION_ID,
                     MIN (SVC.TIME_STAMP) START_TIMESTAMP,
                     MAX (SVC.TIME_STAMP) END_TIMESTAMP,
                     (MAX (SVC.TIME_STAMP) - MIN (SVC.TIME_STAMP)) * 86400
                        SERVICE_DURATION_IN_SECONDS,
                     SUM (
                        DECODE (NVL (UPPER (TRIM (SVC.MESSAGE_BODY)), 'NULL'),
                                'START', 1,
                                0))
                        PROCESS_STARTED,
                     SUM (
                        DECODE (NVL (UPPER (TRIM (SVC.MESSAGE_BODY)), 'NULL'),
                                'END', 1,
                                0))
                        PROCESS_ENDED,
                     SUM (
                        SIGN (
                           NVL (
                              INSTR (UPPER (TRIM (SVC.MESSAGE_BODY)), 'ERROR'),
                              0)))
                        NUMBER_OF_ERRORS
                FROM    DISPATCHER_LOG_APP SVC
                     INNER JOIN
                        SERVICE_EXECUTION_PKS PKS -- Applicazione filtro temporale QUI
                     ON (SVC.PROCESS_ID = PKS.PROCESS_ID)
            GROUP BY SVC.PROCESS_ID, SVC.INSTANCE_NAME),
        -- Sommario dati inviati da tutti i thread FTP gestiti da un singolo servizio Dispatcher
        SERVICE_SEND_SUMMARY
        AS (  SELECT PROCESS_ID,
                     MIN (PK) EXECUTION_ID,
                     COUNT (*) NUMBER_OF_FILES_PROCESSED,
                     MIN (START_TIME) SEND_START_TIME,
                     MAX (END_TIME) SEND_END_TIME,
                     (MAX (END_TIME) - MIN (START_TIME)) * 86400
                        SEND_DURATION_IN_SECONDS
                FROM DISPATCHER_FILE_LOG
            GROUP BY PROCESS_ID),
        -- Errori rilevati durante l'esecuzione di un singolo servizio Dispatcher
        SERVICE_EXECUTION_ERRORS
        AS (SELECT PROCESS_ID,
                   WORKER_ID,
                   REMOTE_FTP,
                   MESSAGE_BODY ERROR_DESCRIPTION
              FROM DISPATCHER_LOG_APP
             WHERE     (UPPER (MESSAGE_BODY) LIKE 'ERROR%')
                   AND (WORKER_ID IS NOT NULL)
                   AND (REMOTE_FTP IS NOT NULL)),
        -- Dati esecuzione SINGOLI THREAD SENDER (rilevati dal logger delle singole trasmissioni)
        -- Un singolo thread di invio gestisce uno specifico endpoint FTP, che a sua volta gestisce il trasferimento dati da N cartelle sorgente a M cartelle destinazione

        -- Sommario dati elaborati da uno specifico worker verso uno specifico endpoint FTP
        SENDER_EXECUTION_SUMMARY
        AS (  SELECT LNK.PROCESS_ID,
                     LNK.WORKER_ID,
                     LNK.REMOTE_FTP,
                     LNK.FILE_PATH SOURCE_FOLDER,
                     LNK.REMOTE_FOLDER REMOTE_FOLDER,
                     MIN (LNK.PK) CONNECTION_ID,
                     COUNT (*) NUMBER_OF_FILES_PROCESSED,
                     SUM (LNK.DOC_SIZE_BYTES) TOTAL_BYTES_TRANSFERRED,
                     MIN (LNK.START_TIME) START_TIME,
                     MAX (LNK.END_TIME) END_TIME,
                     NVL ( (MAX (LNK.END_TIME) - MIN (LNK.START_TIME)) * 86400,
                          0)
                        CONNECTION_DURATION_IN_SECONDS,
                     SUM (
                        DECODE (NVL (LNK.TRANSFER_STATUS, 0),  0, 0,  1, 0,  1))
                        NUMBER_OF_ERRORS
                FROM DISPATCHER_FILE_LOG LNK      --, DATA_SOURCE_SETTINGS DSS
            GROUP BY LNK.PROCESS_ID,
                     LNK.WORKER_ID,
                     LNK.REMOTE_FTP,
                     LNK.FILE_PATH,
                     LNK.REMOTE_FOLDER) --select * from SENDER_EXECUTION_SUMMARY where PROCESS_ID = '3e9c3c54-0096-44d0-91f3-730a4d2b852c'
                                       ,
        -- Sommario dati inviati da una cartella sorgente ad una cartella destinazione utilizzando una specifica connessione FTP
        SINGLE_CONNECTION_SUMMARY
        AS (  SELECT PROCESS_ID                              --, LNK.WORKER_ID
                               ,
                     REMOTE_FTP,
                     SOURCE_FOLDER,
                     REMOTE_FOLDER -- NON espone START_DATE e END_DATE perchè sono relative a thread in potenziale esecuzione simultanea
                                  ,
                     SUM (NUMBER_OF_FILES_PROCESSED) NUMBER_OF_FILES_PROCESSED,
                     SUM (TOTAL_BYTES_TRANSFERRED) TOTAL_BYTES_TRANSFERRED,
                     SUM (CONNECTION_DURATION_IN_SECONDS)
                        CONNECTION_DURATION_IN_SECONDS,
                     SUM (NUMBER_OF_ERRORS) NUMBER_OF_ERRORS
                FROM SENDER_EXECUTION_SUMMARY
            GROUP BY PROCESS_ID,
                     REMOTE_FTP,
                     SOURCE_FOLDER,
                     REMOTE_FOLDER)

   SELECT                 -- Dati relativi all'esecuzione dell'Intero Servizio
         MAIN_SERVICE.EXECUTION_ID SERVICE_EXECUTION_PK,
          MAIN_SERVICE.SERVICE_NAME SERVICE_NAME,
          MAIN_SERVICE.START_TIMESTAMP SERVICE_START_TIMESTAMP,
          MAIN_SERVICE.END_TIMESTAMP SERVICE_END_TIMESTAMP,
          MAIN_SERVICE.SERVICE_DURATION_IN_SECONDS
             SERVICE_DURATION_IN_SECONDS,
          MAIN_SERVICE_CONNECTIONS.NUMBER_OF_FILES_PROCESSED
             FILES_PROCESSED_BY_SERVICE,
          MAIN_SERVICE.NUMBER_OF_ERRORS SERVICE_EXECUTION_ERRORS
		  
     -- Dati relativi ad ogni singola directory gestita da una connessione FTP
          ,
          DIRECTORY_LINK.REMOTE_FTP CONNECTION_ENDPOINT,
          DIRECTORY_LINK.SOURCE_FOLDER SOURCE_FOLDER_NAME,
          DIRECTORY_LINK.REMOTE_FOLDER TARGET_FOLDER_NAME,
          DIRECTORY_LINK.NUMBER_OF_FILES_PROCESSED NUMBER_OF_FILES_DETECTED,
          DIRECTORY_LINK.TOTAL_BYTES_TRANSFERRED TOTAL_BYTES_TRANSFERRED,
          DIRECTORY_LINK.CONNECTION_DURATION_IN_SECONDS
             DIRECTORY_PROCESS_DURATION,
          DIRECTORY_LINK.NUMBER_OF_ERRORS DIRECTORY_PROCESS_ERRORS
     FROM SERVICE_EXECUTION_SUMMARY MAIN_SERVICE
          INNER JOIN SERVICE_SEND_SUMMARY MAIN_SERVICE_CONNECTIONS
             ON (MAIN_SERVICE.PROCESS_ID =
                    MAIN_SERVICE_CONNECTIONS.PROCESS_ID)
          INNER JOIN SINGLE_CONNECTION_SUMMARY DIRECTORY_LINK
             ON (MAIN_SERVICE.PROCESS_ID = DIRECTORY_LINK.PROCESS_ID)
    WHERE (  NVL (MAIN_SERVICE.PROCESS_STARTED, 0)
           * NVL (MAIN_SERVICE.PROCESS_ENDED, 0)) <> 0    -- Service completed
;

/


CREATE OR REPLACE FORCE VIEW DYN_DISPATCHERS_EXECUTION_DATA
AS
   WITH DATA_SOURCE_SETTINGS
        AS (SELECT SYSDATE CURRENT_TS, 90 TIME_WINDOW_SIZE_IN_MINUTES
              FROM DUAL),
        -- Definizione filtro temporale QUI
        LAST_CONNECTIONS_PKS
        AS (  SELECT MAX (DS.SERVICE_EXECUTION_PK) SERVICE_EXECUTION_PK,
                     DS.CONNECTION_ENDPOINT,
                     DS.SOURCE_FOLDER_NAME,
                     MAX (DS.SERVICE_START_TIMESTAMP) SERVICE_START_TIMESTAMP
                FROM DYN_DISPATCHERS_DATA_MONITOR DS, DATA_SOURCE_SETTINGS DSS
               WHERE (DS.SERVICE_START_TIMESTAMP >=
                         (  DSS.CURRENT_TS
                          - (DSS.TIME_WINDOW_SIZE_IN_MINUTES / 1440)))
            GROUP BY DS.CONNECTION_ENDPOINT, DS.SOURCE_FOLDER_NAME),
        LAST_SERVICE_EXECUTION_PKS
        AS (  SELECT SERVICE_EXECUTION_PK,
                     COUNT (*) NUMBER_OF_CONNECTIONS,
                     MAX (SERVICE_START_TIMESTAMP) SERVICE_START_TIMESTAMP
                FROM LAST_CONNECTIONS_PKS
            GROUP BY SERVICE_EXECUTION_PK),
        -- Dati esecuzione SERVIZIO COMPLETO (rilevati dal logger dell'intero servizio)
        -- Un singolo servizio Dispatcher gestisce N thread, ognuno dei quali gestisce una connessione FTP

        -- Sommario dati esecuzione singolo servizio Dispatcher
        SERVICE_EXECUTION_SUMMARY
        AS (  SELECT SVC.SERVICE_EXECUTION_PK,
                     SVC.SERVICE_NAME,
                     MIN (SVC.SERVICE_START_TIMESTAMP) SERVICE_START_TIMESTAMP,
                     MAX (SVC.SERVICE_END_TIMESTAMP) SERVICE_END_TIMESTAMP,
                     MAX (SVC.SERVICE_DURATION_IN_SECONDS)
                        SERVICE_DURATION_IN_SECONDS,
                     MAX (SVC.FILES_PROCESSED_BY_SERVICE)
                        FILES_PROCESSED_BY_SERVICE,
                     MAX (SVC.SERVICE_EXECUTION_ERRORS)
                        SERVICE_EXECUTION_ERRORS --, SUM(SVC.NUMBER_OF_FILES_DETECTED) TOTAL_FILES_PROCESSED
                                                ,
                     SUM (SVC.TOTAL_BYTES_TRANSFERRED) TOTAL_BYTES_TRANSFERRED,
                     SUM (SVC.DIRECTORY_PROCESS_ERRORS)
                        TRANSFER_ERRORS_OCCOURRED
                FROM    DYN_DISPATCHERS_DATA_MONITOR SVC
                     INNER JOIN
                        LAST_SERVICE_EXECUTION_PKS PKS -- Applicazione filtro temporale QUI
                     ON (SVC.SERVICE_EXECUTION_PK = PKS.SERVICE_EXECUTION_PK)
            GROUP BY SVC.SERVICE_EXECUTION_PK, SVC.SERVICE_NAME)
   SELECT SERVICE_EXECUTION_PK,
          SERVICE_NAME,
          SERVICE_START_TIMESTAMP,
          SERVICE_END_TIMESTAMP,
          SERVICE_DURATION_IN_SECONDS,
          FILES_PROCESSED_BY_SERVICE,
          SERVICE_EXECUTION_ERRORS,
          TOTAL_BYTES_TRANSFERRED,
          TRANSFER_ERRORS_OCCOURRED
     FROM SERVICE_EXECUTION_SUMMARY;
	 
/



CREATE OR REPLACE FORCE VIEW DYN_DISPATCHERS_FTP_DATA
AS
   WITH DATA_SOURCE_SETTINGS
        AS (SELECT SYSDATE CURRENT_TS, 90 TIME_WINDOW_SIZE_IN_MINUTES
              FROM DUAL),
        -- Definizione filtro temporale QUI
        LAST_CONNECTIONS_PKS
        AS (  SELECT MAX (DS.SERVICE_EXECUTION_PK) SERVICE_EXECUTION_PK,
                     DS.CONNECTION_ENDPOINT,
                     DS.SOURCE_FOLDER_NAME,
                     MAX (DS.SERVICE_START_TIMESTAMP) SERVICE_START_TIMESTAMP
                FROM DYN_DISPATCHER_MONITOR_DATA_SOURCE DS,
                     DATA_SOURCE_SETTINGS DSS
               WHERE (DS.SERVICE_START_TIMESTAMP >=
                         (  DSS.CURRENT_TS
                          - (DSS.TIME_WINDOW_SIZE_IN_MINUTES / 1440)))
            GROUP BY DS.CONNECTION_ENDPOINT, DS.SOURCE_FOLDER_NAME),
        LAST_SERVICE_EXECUTION_PKS
        AS (  SELECT SERVICE_EXECUTION_PK,
                     COUNT (*) NUMBER_OF_CONNECTIONS,
                     MAX (SERVICE_START_TIMESTAMP) SERVICE_START_TIMESTAMP
                FROM LAST_CONNECTIONS_PKS
            GROUP BY SERVICE_EXECUTION_PK),
        -- Dati esecuzione CONNESSIONI FTP (rilevati dal logger dei trasferimenti file)
        -- Un singolo servizio Dispatcher gestisce N thread, ognuno dei quali gestisce una connessione FTP

        -- Sommario dati esecuzione connessioni FTP
        FTP_CONNESTIONS_SUMMARY
        AS (  SELECT CONNS.SERVICE_EXECUTION_PK,
                     CONNS.SERVICE_NAME,
                     CONNS.CONNECTION_ENDPOINT,
                     CONNS.SOURCE_FOLDER_NAME,
                     CONNS.TARGET_FOLDER_NAME,
                     SUM (CONNS.NUMBER_OF_FILES_DETECTED)
                        NUMBER_OF_FILES_DETECTED,
                     SUM (CONNS.DIRECTORY_PROCESS_DURATION) CONNECTION_DURATION,
                     SUM (CONNS.TOTAL_BYTES_TRANSFERRED) BYTES_TRANSFERRED,
                     SUM (CONNS.DIRECTORY_PROCESS_ERRORS)
                        DIRECTORY_PROCESS_ERRORS
                FROM    DYN_DISPATCHER_MONITOR_DATA_SOURCE CONNS
                     INNER JOIN
                        LAST_SERVICE_EXECUTION_PKS PKS -- Applicazione filtro temporale QUI
                     ON (CONNS.SERVICE_EXECUTION_PK = PKS.SERVICE_EXECUTION_PK)
            GROUP BY CONNS.SERVICE_EXECUTION_PK,
                     CONNS.SERVICE_NAME,
                     CONNS.CONNECTION_ENDPOINT,
                     CONNS.SOURCE_FOLDER_NAME,
                     CONNS.TARGET_FOLDER_NAME)
   SELECT SERVICE_EXECUTION_PK,
          SERVICE_NAME,
          CONNECTION_ENDPOINT,
          SOURCE_FOLDER_NAME,
          TARGET_FOLDER_NAME,
          NUMBER_OF_FILES_DETECTED,
          CONNECTION_DURATION,
          BYTES_TRANSFERRED,
          DIRECTORY_PROCESS_ERRORS
     FROM FTP_CONNESTIONS_SUMMARY;

/
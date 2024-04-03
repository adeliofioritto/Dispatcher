# Dispatcher
## _Trasferimento di cartelle / file da un percorso a Server FTP_

[![Build Status](https://travis-ci.org/joemccann/dillinger.svg?branch=master)](https://travis-ci.org/joemccann/dillinger)

Il dispatcher è un'applicazione che consente di leggere da un percorso di rete / cartella locale e "dispacciarli" (copiarli) all'interno di un Server FTP con scrittura di log applicativi, di trasferimento dei file e di raggiungibilità delle macchine.
L'applicazione è stata pensata per offrire una soluzione di sincronizzazione centralizzata da una fonta verso n-destinazioni.
Originariamente nata per OpenShift, è stata estesa anche per virtual machine standard.

### Ambienti di rilascio:
- OpenShift
- VM

### Struttura e significato delle cartelle
- / : root 
- /start.js : processo principale
- /Dockerfile : file di inizializzazione ambiente per OpenShift
- /package.json : contiene tutte le dipendenze librerie esterne
- /README.md : questo file
    - /OKD : contiene i file di configurazione per l'ambiente OpenShift
        - configmap.yaml : definizione variabili di ambiente per OpenShift
        - secret.yaml : definizioni password di connessione al DataBase
    - /VM : contiene i file di configurazione per virtual machine
        - .env : definizione variabili di ambiente e password per virtual machine
    - /IMG : immagini a corredo per questa guida
    - /SQL : script SQL per Tabelle di logging
        - LogTable.sql : script per la crezione di tabelle di logging

### Struttura e significato del configmap.yaml / .env
Il file presenza le variabili configurative del Dispatcher, nel seguito i possibili valori
| Variabile     | Possibili Valori | Mandatorio | Commento |
| ------------- | ---------------- | -----------| -------- |
| INSTANCE_NAME  | Disp1  |yes|  Il nome del processo che sarà scritto all'interno di log. Questa varibile è utile in caso di multi istanza|
| PVC  | \\YOUR_MNT\FOLDER |yes| Percorso di origine della cartella remota dove andare a leggere cartelle\file da dover trasferire|
|DB_USER| user_db |yes| Nome utente da utilizzare per la connessiona al database per la scrittura del log |
|DB_PASSWORD| password_db |yes| Password del nome utente da utilizzare per la connessiona al database per la scrittura del log. |
| DB_CONNECTION_STRING | csDB |yes| Stringa di connessione al DB |
| FTP_LIST | '{"ftp":[{"host":"first.host.lan", "user":"FTP_username", "password":"FTP_password", "protocol":"ftps", "port":21, "ward":"FOLDER1,FOLDER2", "folder":"currentFolder", "backup":"backupFolder", "entryRoot":"/", "retention":3}]}' |yes| (Maggiormente dettagliato nel seguito) JSON per la configurazione dei Server FTP di destizionazione con le logiche di ribaltamento e mantenimento dei file | 
|CLEAR_FTP_FOLDER| false/true |false| Se impostata a true, svuota la cartella FTP di destinazione (per scopo di test), default a false |
|TRUNC_LOG_TABLE| false/true |false|  Se impostata a true, svuota le tabelle di logging (per scopo di test), default a false |
| SCHEDULING | 60000 | false | Espressa in millisecondi per la pianificazione a intervallo di tempo regolare. Per spegnerarla (processo one-time) impostarla a 0 o rimuoverla dal file di configurazione. Nell'esempio 60000 corrispondono a 1 min |

> [!WARNING]
> Il valore della variabile DB_PASSWORD in caso di OpenShift deve essere codificata in Base64 - per esempio tramite [questo sito](https://www.base64encode.org) - mentre sul file .env viene espressa in chiaro. Esempio:

| Ambiente | Password in Chiaro | File | Valore |
|-|-|-|-|
| OpenShift | test | secret.yaml | dGVzdA== |
| VM | test | .env | test |

Guardiamo nel dettaglio la definizione della variabile FTP_LIST:
```yaml
{
    "ftp": [
        {
            "host": "myfirst.domain.com",
            "user": "usernameFTP",
            "password": "passwordFTP",
            "ward": "Folder1,Folder2",
            "folder": "current",
            "protocol": "ftps",
            "port": 21,
            "backup": "old",
            "retention": 3,
            "entryRoot": "/"
        },
        {
            "host": "mysecond.domain.com",
            "user": "userFTP2",
            "password": "passwordFTP2",
            "ward": "Folder3,Folder1",
            "folder": "current",
            "protocol": "ftps",
            "port": 21,
            "backup": "old",
            "retention": 3,
            "entryRoot": "upload"
        }
    ]
}
```

Il JSON è una collezione di Server FTP che indicano
| Variabile | Valore | Commento |
| - | - | - |
| host | myfirst.domain.com | l'indirizzo IP o il nome host del server FTP |
| user | usernameFTP | lo username dell'utente del Server FTP |
| password | passwordFTP | la password dello username dell'utente del Server FTP |
| ward | Folder1,Folder2 | l'elenco delle cartelle da voler copiare dall'origine alla destinazione, delimitate da virgola |
| folder | current | cartella del Server FTP dove memorizzare le cartelle di origine |
| protocol | ftps | il protocollo di connessione verso il Server FTP. Il dispatcher utilizza la libreria [basic-ftp](https://github.com/patrickjuchli/basic-ftp#readme) quindi i valori accettati dipendono da essa. Testati ftp ed ftps  |
| port | 21 | porta di connessione |
| backup | old | cartella del Server FTP dove memorizzare i file di backup |
| retention | 3 | espresso in numero di giorni, indica quali file bisogna mantenere nella cartella di backup. Il parametro legge la last modification date del file e cancella tutti quelli più vecchi di oggi-retention |
| entryRoot | "/" oppure "upload" | la cartella di ingresso del Server FTP relativamente all'utente FTP che effettua la connessione |

### Logiche di funzionamento
Il Dispatcher si può avviare in singola esecuzione (apertura processo, chiusura, exit) oppure schedulato con una periodicità pari alla variabile espressa in millisecondi SCHEDULING.
Una volta avviato, viene effettuato il controllo che tutte le variabili mandatorie siano censite, in caso contrario interrompe l'esecuzione con il messaggio:
```
Attention! Please check your environment variables
```

Viene quindi costruito il JSON con l'elenco dei Server FTP.
Per ciascun Server FTP, effettua un controllo cancellando gli spazi - per eventuali errori di battitura - presenti nell'elenco definito in "ward" e costruiscce un array con la lista di tutti le cartelle definite. Tale array sarà utilizzato per effettuare il controllo incrociato "quali cartelle sono state inserite rispetto a quelle definite nel percorso di origine" evidenziandone eventualmente delle mancanze (per es. definisco in "ward" la cartella "Folder1", ma "Folder1" non è presente nell'elenco delle cartelle lette nel percorso della PVC).
Viene effettuata la connessione su ciascun Server FTP e quindi nell'ordine:
- Si recupera l'informazione sul Sistema Operativo utilizzato (DB LOG)
- Se la variabile CLEAR_FTP_FOLDER è a true, svuoto la cartella di destinazione
- Effettua il controllo che la cartella "ward" e "backup" siano presenti. In caso contrario, le crea
- Copia ciascuna cartella definita nella "ward" e presente nella PVC all'interno della "backup"
- Copia ciascuna cartella definita nella "ward" e presente nella PVC all'interno della "folder" con la logica di "sovrascrittura" sia della cartella, sia dei file
- Si cancellano tutti i file più vecchi della "retention" presenti nella cartella "backup"

### Gestione dei log
I log vengono scritti a DB su due tabelle di appoggio. La mancata connessione verso il DB non blocca l'esecuzione del trasferimento dei file ai fini del backup.
I loo possono essere di due tipi: applicativi e di trasferimento.
I log applicativi sono presenti nella tabella "DISPATCHER_LOG_APP" e registrano il ciclo di vita del processo tramite il PROCESS_ID e quindi:
- l'avvio
- il recupero delle cartelle definite nel "ward"
- la connessione al server FTP
- il Sistema Operativo
- le azioni di "removeDir"
- l'esecuzione del ribaltamento della singola cartella con il totale dei secondi impiegati
- gli errori di connessione (tipicamente per Timeout)
- la chisura del processo

I log di trasferimento sono presenti nella tabella "DISPATCHER_FILE_LOG" e registrano i trasferimenti dei singoli file, con indicazione del:
- nome file
- cartella di origine
- Server FTP di destinazione
- Data/Ora inizio
- Data/ora fine
- Dimensione del file
- Istance Name: nome del processo indicato nella variabile INSTANCE_NAME
- Worker ID: ID del processo padre
- Transfer ID: ID del singolo trasferimento di file
- Process ID: ID del processo principale

La gerarchia degli ID è la seguente: PROCESS -> 0-n WORKER -> 0-n TRANSFER
- PROCESS: ID univoco del processo principale
- WORKER: ID univoco del processo su singolo Server FTP (generato dal PROCESS)
- TRANSFER: ID univoco del trasferimento del singolo file (generato dal WORKER)

### Elenco dei plugin utilizzati
Nel seguito l'elenco dei plugin utilizzati

| Plugin | README |
| ------ | ------ |
| basic-ftp | https://github.com/patrickjuchli/basic-ftp#readme |
| dotenv | https://github.com/motdotla/dotenv |
| fs | https://github.com/npm/fs |
| node-oracledb | https://github.com/oracle/node-oracledb |
| uuid | https://github.com/uuidjs/uuid |

## Installazione
Seguirà sezione per la guida sull'installazione per:

### OpenShift

### Virtual Machine

## License

MIT

**Free Software, Hell Yeah!**
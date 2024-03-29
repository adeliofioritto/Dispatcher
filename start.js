const ftp = require("basic-ftp")
const fs = require('fs')
const uuid = require('uuid');
const oracledb = require('oracledb');

// --> Variabili interne all'app
var reportAppList = [];
var workerID;
var transferID;
let connection;
let foldersOnMNT;
const svuotaFTP = true; //Varibile di appoggio per svuotare directory e file dell'FTP
const truncTable = true; //Varibile di appoggio per svuotare le tabelle di logging sul DB
var removedElements = []; //Directory della wardList non presenti sulla mountPath
var presentElements = []; //Directory della wardList presenti sulla mountPath
// <-- Variabili interne all'app

// ---> Variabili da istanziare tramite config/secret
var instanceName = '';
var mountPath = '';
var wardList = "";
var ftpList = '';
// <--- Variabili da istanziare tramite config/secret

// --> Bind delle variabili interne rispetto al config properties

let DB_USER = process.env.DB_USER || "";
console.log("DB_USER:"+DB_USER);

let DB_PASSWORD = process.env.DB_PASSWORD || "";
console.log("DB_PASSWORD:"+DB_PASSWORD);

let DB_CONNECTION_STRING = process.env.DB_CONNECTION_STRING || "";
console.log("DB_CONNECTION_STRING:"+DB_CONNECTION_STRING);

instanceName = process.env.INSTANCE_NAME || "";
console.log("instanceName:"+instanceName);

mountPath = process.env.PVC || "";
console.log("mountPath:"+mountPath);

ftpList = process.env.FTP_LIST || "";
console.log("ftpList:"+ftpList);

if (DB_USER === "" || DB_PASSWORD === "" || DB_CONNECTION_STRING === "" || instanceName === "" || mountPath === "" || ftpList === ""){
console.log("Attenzione, verificare le variabili d'ambiente!");
}

// <--- Bind delle variabili interne rispetto al config properties

// --> Definizioni di Classi e Funzioni
class reportFile {
  constructor(timestamp, fileName, directory, remoteFTP, start, end, bytes, instanceName, workerID, transferID) {
    this.timestamp = timestamp;
    this.fileName = fileName;
    this.directory = directory;
    this.remoteFTP = remoteFTP;
    this.start = start;
    this.end = end;
    this.bytes = bytes;
    this.instanceName = instanceName;
    this.workerID = workerID;
    this.transferID = transferID;


  }
  sendToDB() {
    if (connection) {
      console.log(this);
      //console.log("connessione attiva, scrivo a DB");
      var writeLog = scriviLogReportFile(this);
    }
  }
}

class reportApp {
  constructor(funzione, messaggio, instanceName) {
    this.timestamp = getTime();
    this.funzione = funzione;
    this.messaggio = messaggio;
    this.instanceName = instanceName;
    console.log(JSON.stringify(this));
    if (connection) {
      //console.log("connessione attiva, scrivo a DB");
      var writeLog = scriviLogAppDB(this);
    }
  }
}

async function scriviLogAppDB(msg) {
  console.log("scriviLogAppDB");
  console.log(msg);

  result = await connection.execute(
    `INSERT INTO DISPATCHER_LOG_APP VALUES (TO_DATE(:timestamp,'YYYY-MM-DD HH24:MI:SS'), :funzione, :messaggio, :instanceName )`,
    [msg.timestamp, msg.funzione, msg.messaggio, msg.instanceName], { autoCommit: true }
  );
  //console.log("Rows inserted: " + result.rowsAffected);  // 1

}

async function scriviLogReportFile(msg) {
  console.log("scriviLogReportFile");
  console.log(msg);

  result = await connection.execute(
    `INSERT INTO dispatcher_file_log VALUES (TO_DATE(:timestamp,'YYYY-MM-DD HH24:MI:SS'), :file_name, :file_path, :remote_ftp, TO_DATE(:start_time,'YYYY-MM-DD HH24:MI:SS'), TO_DATE(:end_time,'YYYY-MM-DD HH24:MI:SS'), :doc_size_bytes, :instance_name, :worker_id, :transfer_id)`,
    [msg.timestamp, msg.fileName, msg.directory, msg.remoteFTP, msg.start, msg.end, msg.bytes, msg.instanceName, msg.workerID, msg.transferID], { autoCommit: true }
  );
  //console.log("Rows inserted: " + result.rowsAffected);  // 1
}

function getTime() {
  return new Date().toLocaleString('lt-LT');
}

function listToArray(fullString, separator) {
  var fullArray = [];

  if (fullString !== undefined) {
    if (fullString.indexOf(separator) == -1) {
      fullArray.push(fullString);
    } else {
      fullArray = fullString.split(separator);
    }
  }

  return fullArray;
}

function getDirectory(dir, files = []) {
  // Get an array of all files and directories in the passed directory using fs.readdirSync
  const fileList = fs.readdirSync(dir);
  //console.log("Elenco di tutti i file presenti sulla MNT");
  //console.log(fileList);

  // Create the full path of the file/directory by concatenating the passed directory and file/directory name
  for (const file of fileList) {
    const name = `${dir}/${file}`
    // Check if the current file/directory is a directory using fs.statSync
    if (fs.statSync(name).isDirectory()) {
      // If it is a directory, recursively call the getFiles function with the directory path and the files array
      files.push(file)
    }
  }
  return files

}

function createMap(mnt, dir, mappa = []) {

  for (const direct of dir) {
    //console.log(direct);
    const fileList = fs.readdirSync(`${mnt}/${direct}`);
    //console.log(fileList);
    for (const file of fileList) {
      //console.log(file);
      mappa.push(new Array(`${direct}`, `${file}`));
    }
  }
  return mappa;
}

function findMissingPresentDir(foldersOnMNT, arrayWardList) {
  var inCurrent = {};

  for (let x of foldersOnMNT)
    inCurrent[x] = true;
  for (let x of arrayWardList)
    if (!inCurrent[x])
      removedElements.push(x)
    else
      presentElements.push(x)
  //break; // alternatively just break if exactly one missing element
  //console.log(`Configured wards, but not found on MNT: ${removedElements}`)
  //console.log(`Configured wards, founded on MNT: ${presentElements}`)

  reportAppList.push((new reportApp('findMissingPresentDir - configured wards, but not found on MNT', removedElements.toString(), instanceName)));
  reportAppList.push((new reportApp('findMissingPresentDir - configured wards, founded on MNT', presentElements.toString(), instanceName)));

}

// 5 . Funzione che restituisce le directory presenti sull'FTP e nel MOUNT
function findPresentDir(foldersOnMNT, arrayWardList) {
  var removedElementsCicle = [];
  var presentElementsCicle = [];
  var arrayWardList = listToArray(arrayWardList.replace(/\s/g, ''), ',');
  var inCurrent = {};

  for (let x of foldersOnMNT)
    inCurrent[x] = true;
  for (let x of arrayWardList)
    if (!inCurrent[x])
      removedElementsCicle.push(x)
    else
      presentElementsCicle.push(x)
  return presentElementsCicle;
}
// <-- Definizioni di Classi e Funzioni




// Funzione di Connessione all'FTP Client */
async function establishFtpsConnection(server) {
  workerID = uuid.v4();
  var reportFileList = [];
  var globalFolder = null;
  var elementiDaRibaltare = [];
  var dirFTP = [];
  var dirFTPbackup = [];
  var dirFTPcurrent = [];
  const client = new ftp.Client();
  client.ftp.verbose = false;

  try {
    await client.access({
      protocol: server.protocol,
      host: server.host,
      user: server.user,
      password: server.password,
      port: server.port,
      secure: true,
      secureOptions: { "rejectUnauthorized": false },
      connectTimeout: 200000 //Per il connection timeout
    });



    reportAppList.push((new reportApp('establishFtpsConnection - ' + server.host + ' - connected', workerID, instanceName)));

    //Recupero l'informazione sul sistema operativo
    const OS = await client.send("SYST");
    reportAppList.push((new reportApp('establishFtpsConnection - ' + server.host + ' - OS', JSON.stringify(OS), instanceName)));

    //console.log("PWD 1:" + await client.pwd());

    //Svuoto il server FTP se svuotaFTP = true
    var listFile = await client.list(server.entryRoot);
    for (const file of listFile) {
      if (file.type === 2) { //Se è una directory, popolo l'array
        if (svuotaFTP === true) {
          reportAppList.push((new reportApp('establishFtpsConnection - ' + server.host + ' - removeDir ' + `${file.name}` + '', 'Remove all DIR from root path FTP for svuotaFTP', instanceName)));
          var deleteDir = await client.removeDir(`${server.entryRoot}/${file.name}`);
        }
      }
    }

    var currentExist = false;
    var backupExist = false;
    var listFile = await client.list(server.entryRoot);
    for (const file of listFile) {
      if (file.type === 2) { //Se è una directory, popolo l'array
        dirFTP.push(file.name);
        if (file.name === server.folder) { currentExist = true; }
        if (file.name === server.backup) { backupExist = true; }
      }
    }

    //Creo le cartelle di default. Nota: non posso generarla sempre in quanto su Linux genera un'eccezione in caso di esistenza
    await client.cd(server.entryRoot);
    if (currentExist === false) {
      await client.send("MKD " + server.folder); console.log("currentExist dentro:" + currentExist);
    }
    if (backupExist === false) {
      await client.send("MKD " + server.backup); console.log("backupExist dentro:" + backupExist);
    }

    console.log("Directory FTP trovate sul server: " + server.user);
    console.log(dirFTP);

    //console.log("PWD 2:" + await client.pwd());

    client.trackProgress(info => {
      transferID = uuid.v4();
      //console.log("File", info)
      //console.log("server.host:" + server.host);
      timestamp = getTime();
      fileName = info.name;
      directory = globalFolder;
      remoteFTP = server.host;
      bytes = info.bytes;
      if (fileName != "") { //Solo per i file, il trasferimentento delle directory non intendo tracciarlo in questa classe
        if (info.bytes === 0) {
          start = timestamp;
          end = null;
          reportFileList[fileName] = new reportFile(timestamp, fileName, directory, remoteFTP, start, end, bytes, instanceName, workerID, transferID);
        } else {
          start = null;
          end = timestamp;
          reportFileList[fileName]['end'] = timestamp;
          reportFileList[fileName]['bytes'] = bytes;
        }
      }
    })

    elementiDaRibaltare = findPresentDir(foldersOnMNT, server.ward);
    console.log("elementiDaRibaltare");
    //console.log(server.ward);
    console.log(elementiDaRibaltare);
    console.log(reportFileList);

    //1.1 Logica di backup: effettuo la medesima copia sulla cartella di backup
    for (let folder of elementiDaRibaltare) {
      // Faccio l'upload delle directory e file presenti con il controllo incrociato 
      //console.log(`${mountPath}\\${folder}`);
      globalFolder = folder;
      //console.log("START CP:" + new Date(new Date() - 3600 * 1000 * 3).toISOString());
      await client.uploadFromDir(`${mountPath}/${folder}`, `${server.backup}/${folder}`);
      //console.log("END CP:" + new Date(new Date() - 3600 * 1000 * 3).toISOString());
      //break;
    }

    //2.0 Entro nella cartella remota di upload current e cancello tutto il contenuto
    listFile = await client.list(server.folder);
    for (const file of listFile) {
      console.log(file.type);
      console.log(file);
      if (file.type === 1) {
        // pulisco i file nelle directory root 
        //console.log(file);
        //console.log(file.name);
        //await client.remove(`${dirFTPupload}/${file.name}`);
      }
      if (file.type === 2) { //Se è una directory, popolo l'array
        console.log(file);
        dirFTPcurrent.push(file.name);
        reportAppList.push((new reportApp('establishFtpsConnection - ' + server.host + ' - removeDir ' + `${file.name}` + '', 'Remove DIR from root path', instanceName)));
        await client.removeDir(`${server.folder}/${file.name}`);

      }
    }

    console.log("dirFTPcurrent");
    console.log(dirFTPcurrent);


    //2.1 Faccio l'uploade dei file
    for (let folder of elementiDaRibaltare) {
      ///Faccio l'upload delle directory e file presenti con il controllo incrociato
      //console.log(folder);
      //console.log(`${mountPath}\\${folder}`);
      globalFolder = folder;
      var startFolderUpload = new Date(new Date() - 3600 * 1000 * 3);
      console.log("START:" + startFolderUpload.toISOString());
      await client.uploadFromDir(`${mountPath}/${folder}`, `${server.folder}/${folder}`);
      var endFolderUpload = new Date(new Date() - 3600 * 1000 * 3);
      console.log("END:" + endFolderUpload.toISOString());
      var totalElapsed = (endFolderUpload - startFolderUpload) / 1_000;
      console.log("ENDED IN SEC:" + totalElapsed);
      reportAppList.push((new reportApp('establishFtpsConnection - ' + server.host + ' - uploadFromDir ' + `${folder}` + '', 'uploadFromDir in sec ' + totalElapsed, instanceName)));
    }

    console.log("reportFileList: ");
    for (const [key, value] of Object.entries(reportFileList)) {
      //console.log(`${key}: ${value}`);
      console.log(reportFileList[key].sendToDB());
    }
    console.log("fine reportFileList");


    //Cancello i file più vecchi della retention, non c'è bisogno di controllare la current in quanto già cancellata ad ogni loop
    const listFileBackup = await client.list(server.backup);
    //Costruisco l'elenco delle directory della backup
    for (const file of listFileBackup) {
      //console.log(file.type);
      if (file.type === 1) {
        // pulisco i file nelle directory root 
        console.log(file);
        //console.log(file.name);
        //await client.remove(`${dirFTPupload}/${file.name}`);
      }
      if (file.type === 2) { //Se è una directory, popolo l'array
        console.log(file);
        dirFTPbackup.push(file.name);
      }
    }



    //Verifico i file se sono più vecchi della retention, in caso cancellerei
    for (const dir of dirFTPbackup) {
      console.log("dir:" + dir);
      var dirBackup = await client.list(`${server.backup}/${dir}`);
      for (const file of dirBackup) {
        //console.log(file.type);
        if (file.type === 1) {
          // pulisco i file nelle directory root 
          //console.log(file);
          //console.log(file.name);
          //await client.remove(`${dirFTPupload}/${file.name}`);
          var fileTime = await client.send("MDTM " + `${server.backup}/${dir}/` + file.name);
          console.log(fileTime);
          normalizzaData = fileTime.message.replace(fileTime.code + " ", "");
          console.log(normalizzaData);
          var anno = normalizzaData.substring(0, 4);
          var mese = normalizzaData.substring(4, 6)
          var giorno = normalizzaData.substring(6, 8)
          var ora = normalizzaData.substring(8, 10)
          var minuti = normalizzaData.substring(10, 12)
          var secondi = normalizzaData.substring(12, 14)
          console.log(anno + "/" + mese + "/" + giorno + " " + ora + ":" + minuti + ":" + secondi);
          var dataOraFile = new Date(anno + "/" + mese + "/" + giorno + " " + ora + ":" + minuti + ":" + secondi);
          var oraAttuale = new Date();
          console.log(dataOraFile);
          console.log(oraAttuale);
          let Difference_In_Time = oraAttuale.getTime() - dataOraFile.getTime();
          let Difference_In_Days = Math.round(Difference_In_Time / (1000 * 3600 * 24));
          console.log("Difference_In_Days:" + Difference_In_Days);
          if (Difference_In_Days >= server.retention) {
            await client.remove(`${server.backup}/${dir}/` + file.name);
          }
        }
      }
    }

    console.log("dirFTPbackup"); console.log(dirFTPbackup);

  } catch (err) {
    console.log("ERROR")
    console.log(err.toString());
    reportAppList.push((new reportApp('establishFtpsConnection - ' + server.host + ' - ERROR', err.toString(), instanceName)));
  }

  client.close();
}


async function procesMultipleCandidates(data) {
  try {
    connection = await oracledb.getConnection({ user: DB_USER, password: DB_PASSWORD, connectionString: DB_CONNECTION_STRING });
  } catch (err) {
    console.error(err);
  } finally {
    if (connection) {
      console.log("Aperta Connessione DB");
      if (truncTable === true) {
        result = await connection.execute(`TRUNCATE TABLE DISPATCHER_LOG_APP`);
        console.log(" Trunc DISPATCHER_LOG_APP");
        result = await connection.execute(`TRUNCATE TABLE DISPATCHER_FILE_LOG`);
        console.log(" Trunc DISPATCHER_FILE_LOG");
      }
    }
  }
  reportAppList.push((new reportApp('App', 'Start', instanceName)));
  reportAppList.push((new reportApp('App', 'Retrieved all wards in FTP conf', instanceName)));

  var dirFTP = [];

  // 2. Creo l'array della lista dei reparti
  var arrayWardList = listToArray(wardList.replace(/\s/g, ''), ',');
  reportAppList.push((new reportApp('arrayWardList', wardList.toString(), instanceName)));



  // 3. Creo l'elenco delle directory trovate sulla mount
  foldersOnMNT = getDirectory(mountPath);
  reportAppList.push((new reportApp('getDirectory', foldersOnMNT.toString(), instanceName)));

  // 3. Per ciascuna directory, creo l'array bidimensionale per i file presenti in essa
  const mappaDirFile = createMap(mountPath, foldersOnMNT);
  //console.log("Elenco dei file presenti nelle directory");
  //console.log(mappaDirFile);


  // 4. Faccio un raffronto tra le directory presenti sulla MNT rispetto a quelle configurate nel Dispatcher
  findMissingPresentDir(foldersOnMNT, arrayWardList);

  let generatedResponse = []
  for (let elem of data) {
    try {
      //console.log(elem);

      // here candidate data is inserted into  
      let insertResponse = await establishFtpsConnection(elem)
      // and response need to be added into final response array 
      generatedResponse.push(insertResponse)
    } catch (error) {
      console.log('error' + error);
    }
  }
  console.log('complete all') // gets loged first


  if (connection) {
    try {
      reportAppList.push((new reportApp('App', 'End', instanceName)));
      await connection.close();
      console.log("Chiusa Connessione DB");
    } catch (err) {
      console.log("DB Connection Error:");
      console.error(err);
    }
  }

  return generatedResponse // return without waiting for process of 

}



function App() {
  // 1. Cotruisco la sommatoria dei reparti configurati in base al JSON degli FTP
  const objFtpList = JSON.parse(ftpList);
  var contListaFtp = 0;
  objFtpList.ftp.forEach(server => {
    server.ward = server.ward.replace(/\s/g, '');
    console.log(server);
    if (contListaFtp > 0) { wardList += ","; }
    wardList += server.ward;
    contListaFtp++;
  });
  console.log(wardList);

  var appStart = procesMultipleCandidates(objFtpList.ftp)
}


App();

console.log(new Date().toLocaleString('lt-LT')+" - Debugging...");
setInterval(function(){ console.log(new Date().toLocaleString('lt-LT')+" - Debugging...")},60000) //logs every minute





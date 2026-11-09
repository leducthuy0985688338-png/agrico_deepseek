import {before, after, test} from "node:test";
import assert from "node:assert/strict";
import {initializeApp as adminApp} from "firebase-admin/app";
import {getFirestore as adminFirestore, Timestamp} from "firebase-admin/firestore";
import {getAuth as adminAuth} from "firebase-admin/auth";
import {initializeApp, deleteApp} from "firebase/app";
import {getAuth, connectAuthEmulator, signInWithEmailAndPassword, signOut} from "firebase/auth";
import {getFirestore, connectFirestoreEmulator, doc, setDoc, getDocFromServer, serverTimestamp, runTransaction} from "firebase/firestore";
const project = "demo-agrico-workspace";
for (const [key,value] of Object.entries({GCLOUD_PROJECT:project,GOOGLE_CLOUD_PROJECT:project,
  FIRESTORE_EMULATOR_HOST:"127.0.0.1:8088",FIREBASE_AUTH_EMULATOR_HOST:"127.0.0.1:9099"})) {
  assert.equal(process.env[key],value, "Use only the configured local demo emulators");
}
adminApp({projectId:project});
const db = adminFirestore();
let app, auth, client;
const cmd = (action,entityId,payload={}) => ({action,entityId,expectedRevision:0,payload});
async function call(operation, command, token) {
  return fetch("http://127.0.0.1:5002/"+project+"/asia-southeast1/companyWorkspaceResult", {
    method:"POST",headers:{"Content-Type":"application/json",...(token?{Authorization:"Bearer "+token}:{})},
    body:JSON.stringify({data:{farm:"farm",operation,command}}),
  });
}
async function waitResult(operation, command, token) {
  for (let i=0;i<100;i++) {
    const response=await call(operation,command,token);
    assert.equal(response.status,200,await response.clone().text());
    const value=(await response.json()).result;
    if (value.status === "accepted" || value.status === "rejected") return value;
    await new Promise(resolve=>setTimeout(resolve,100));
  }
  throw Error("Emulated trigger did not finish");
}
before(async()=>{
  app=initializeApp({projectId:project,apiKey:"demo-only",authDomain:project+".firebaseapp.com"},"receipt-http");
  auth=getAuth(app);connectAuthEmulator(auth,"http://127.0.0.1:9099",{disableWarnings:true});
  client=getFirestore(app);connectFirestoreEmulator(client,"127.0.0.1",8088);
  for (const uid of ["worker","other"]) {
    await adminAuth().createUser({uid,email:uid+"@example.test",password:"Synthetic-Test-Only-2026"});
    await db.doc("agrico_memberships/"+uid).set({userId:uid,membershipId:uid,farmId:"farm",active:true,
      roles:[{role:"systemAdmin",scopes:["allFarm"]}],offlineUntil:Timestamp.fromMillis(Date.now()+3600000),adminRevision:1});
  }
});
after(async()=>{if(app) await deleteApp(app);});
test("real callable HTTP verifies Auth token blocks old result and preserves operation replay", async()=>{
  await signInWithEmailAndPassword(auth,"worker@example.test","Synthetic-Test-Only-2026");
  const token=await auth.currentUser.getIdToken();
  const create=cmd("room.create","http-room",{title:"HTTP private room",members:[]});
  const commandPath="agrico_workspace/farm/users/worker/commands/http-room";
  await setDoc(doc(client,commandPath),{...create,status:"pending",schemaVersion:1,createdAt:serverTimestamp()});
  const result=await waitResult("http-room",create,token);
  assert.equal(result.result.record.content.title,"HTTP private room");
  await assert.rejects(()=>getDocFromServer(doc(client,commandPath)),{code:"permission-denied"});
  // Exactly the Firestore retry gate used by the Dart channel: accepted get is
  // denied, then authenticated delivery verifies the same immutable command.
  await assert.rejects(()=>runTransaction(client,async tx=>tx.get(doc(client,commandPath))),{code:"permission-denied"});
  assert.equal((await waitResult("http-room",create,token)).status,"accepted");
  assert.equal((await db.collection("agrico_workspace/farm/records").get()).size,1);
  assert.equal((await db.collection("agrico_workspace/farm/command_audit").get()).size,1);
  const read=cmd("message.list","http-room");
  const readPath="agrico_workspace/farm/users/worker/commands/http-read";
  await setDoc(doc(client,readPath),{...read,status:"pending",schemaVersion:1,createdAt:serverTimestamp()});
  assert.equal((await waitResult("http-read",read,token)).status,"accepted");
  await db.doc("agrico_workspace/farm/records/room~http-room").update({participants:["other"],revision:2});
  assert.equal((await call("http-read",read,token)).status,403);
  await assert.rejects(()=>getDocFromServer(doc(client,readPath)),{code:"permission-denied"});
  await signOut(auth);
  assert.equal((await call("http-read",read)).status,401);
  assert.equal((await call("http-read",read,"not-a-valid-token")).status,401);
  await signInWithEmailAndPassword(auth,"other@example.test","Synthetic-Test-Only-2026");
  assert.equal((await call("http-read",read,await auth.currentUser.getIdToken())).status,403);
});

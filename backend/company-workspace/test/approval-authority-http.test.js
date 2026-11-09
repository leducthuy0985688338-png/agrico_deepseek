import {before,after,test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeApp as adminApp} from 'firebase-admin/app';
import {getFirestore,Timestamp} from 'firebase-admin/firestore';
import {getAuth as adminAuth} from 'firebase-admin/auth';
import {initializeApp,deleteApp} from 'firebase/app';
import {getAuth,connectAuthEmulator,signInWithEmailAndPassword} from 'firebase/auth';
import {getFirestore as clientFirestore,connectFirestoreEmulator,doc,getDocFromServer,setDoc} from 'firebase/firestore';
import {policyDigest} from '../src/approval_authority.js';
const project='demo-agrico-workspace',farm='approval-native-test';
for(const [k,v] of Object.entries({GCLOUD_PROJECT:project,GOOGLE_CLOUD_PROJECT:project,FIRESTORE_EMULATOR_HOST:'127.0.0.1:8088',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:9099'})) assert.equal(process.env[k],v);
adminApp({projectId:project},'approval-authority-admin');
import {getApps} from 'firebase-admin/app';
const backend=getApps().find(a=>a.name==='approval-authority-admin'),db=getFirestore(backend);
let app,auth,client;const tokens={};
const p={farm,kind:'machineRun',currency:'VND',version:1,selfEnabled:true,selfLimit:'100',independentLimit:'900719925474099300000.01',createPermission:'machine.log',approvePermission:'machine.verify',changedBy:'b-manager'};
const request=operation=>({operation,policy:p,digest:policyDigest(p),...(operation==='activate'?{expectedActive:null,expectedDraftHead:{version:p.version,digest:policyDigest(p)},expectedAuthorityRevision:1}:{})});
async function call(name,data,uid){return fetch(`http://127.0.0.1:5002/${project}/asia-southeast1/${name}`,{method:'POST',headers:{'Content-Type':'application/json',...(uid?{Authorization:`Bearer ${tokens[uid]}`}:{})},body:JSON.stringify({data})});}
async function success(data,uid){const r=await call('companyApprovalAuthority',data,uid);assert.equal(r.status,200,await r.clone().text());return (await r.json()).result;}
before(async()=>{
 app=initializeApp({projectId:project,apiKey:'demo-only',authDomain:`${project}.firebaseapp.com`},'approval-authority-http');auth=getAuth(app);connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});client=clientFirestore(app);connectFirestoreEmulator(client,'127.0.0.1',8088);
 const permissions={'b-manager':['approval.policy.manage','approval.limits.manage','finance.view'],'b-activator':['approval.policy.activate','finance.view'],'b-reviewer':['finance.view'],'b-admin':[]};
 for(const [uid,extraPermissions] of Object.entries(permissions)){
  await adminAuth(backend).createUser({uid,email:`${uid}@example.test`,password:'Synthetic-Test-Only-2026'});
  await db.doc(`agrico_memberships/${uid}`).set({userId:uid,membershipId:uid,farmId:farm,active:true,roles:[{role:'systemAdmin',scopes:['allFarm']}],extraPermissions,extraPermissionScopes:['allFarm'],offlineUntil:Timestamp.fromMillis(Date.now()+3600000),adminRevision:1});
  await signInWithEmailAndPassword(auth,`${uid}@example.test`,'Synthetic-Test-Only-2026');tokens[uid]=await auth.currentUser.getIdToken();
 }
 await db.doc(`agrico_approval_authorities/${farm}`).set({active:true,revision:1,managerUids:['b-manager'],activatorUids:['b-activator'],partyMemberships:{external:[],worker:['b-reviewer']}});
});
after(async()=>{if(app)await deleteApp(app);});
test('real Auth/Functions/Firestore authority requires authenticated server draft, independent activation and live revocation',async()=>{
 assert.notEqual((await call('companyApprovalAuthority',request('propose'))).status,200);
 assert.notEqual((await call('companyApprovalAuthority',request('propose'),'b-activator')).status,200);
 assert.notEqual((await call('companyApprovalAuthority',request('activate'),'b-activator')).status,200);
 assert.equal((await success(request('propose'),'b-manager')).proposed,true);
 assert.notEqual((await call('companyApprovalAuthority',request('activate'),'b-manager')).status,200);
 assert.notEqual((await call('companyApprovalAuthority',request('activate'),'b-admin')).status,200);
 const activation=await success(request('activate'),'b-activator'),reference=JSON.parse(activation.reference);
 const verify={...request('verify'),reference:activation.reference,activatedBy:reference.activatedBy,activatedAt:reference.activatedAt};
 assert.equal((await success(verify,'b-reviewer')).current,true);
 assert.deepEqual(await success(request('activate'),'b-activator'),activation);
 assert.equal((await db.collection(`agrico_approval_policies/${farm}/versions`).get()).size,1);
 assert.equal((await db.collection(`agrico_approval_policies/${farm}/audit`).where('action','==','activate').get()).size,1);
 await assert.rejects(getDocFromServer(doc(client,`agrico_approval_authorities/${farm}`)),{code:'permission-denied'});
 await assert.rejects(setDoc(doc(client,`agrico_approval_authorities/${farm}`),{active:true}),{code:'permission-denied'});
 let result=await call('companyApprovalRelations',{farm,partyId:'external'},'b-reviewer');assert.equal(result.status,200);assert.deepEqual((await result.json()).result,{verified:true,users:[]});
 await db.doc('agrico_memberships/b-activator').update({active:false});
 assert.equal((await success(verify,'b-reviewer')).current,false);
 await db.doc(`agrico_approval_authorities/${farm}`).update({active:false});
 assert.notEqual((await call('companyApprovalAuthority',verify,'b-reviewer')).status,200);
 result=await call('companyApprovalRelations',{farm,partyId:'worker'},'b-reviewer');assert.deepEqual((await result.json()).result,{verified:false});
});


test('two isolated Auth clients download genuine drafts, CAS concurrently, retry and revoke without direct Firestore access',async()=>{
 const target='approval-multi-device',apps=[],creds={};
 const people={ 'md-manager':['approval.policy.manage','approval.limits.manage'], 'md-one':['approval.policy.activate'], 'md-two':['approval.policy.activate'], 'md-other':['approval.policy.activate'] };
 try{
  for(const [uid,extraPermissions] of Object.entries(people)){
   await adminAuth(backend).createUser({uid,email:`${uid}@example.test`,password:'Synthetic-Test-Only-2026'});
   await db.doc(`agrico_memberships/${uid}`).set({userId:uid,membershipId:uid,farmId:uid==='md-other'?'other':target,active:true,roles:[{role:'auditor',scopes:['allFarm']}],extraPermissions,extraPermissionScopes:['allFarm'],offlineUntil:Timestamp.fromMillis(Date.now()+3600000),adminRevision:1});
   const a=initializeApp({projectId:project,apiKey:'demo-only',authDomain:`${project}.firebaseapp.com`},uid);apps.push(a);const au=getAuth(a);connectAuthEmulator(au,'http://127.0.0.1:9099',{disableWarnings:true});await signInWithEmailAndPassword(au,`${uid}@example.test`,'Synthetic-Test-Only-2026');creds[uid]=await au.currentUser.getIdToken();
  }
  assert.notEqual(getAuth(apps[0]),getAuth(apps[1]));
  await db.doc(`agrico_approval_authorities/${target}`).set({active:true,revision:1,managerUids:['md-manager'],activatorUids:['md-one','md-two','md-other']});
  const send=async(uid,data)=>fetch(`http://127.0.0.1:5002/${project}/asia-southeast1/companyApprovalAuthority`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${creds[uid]}`},body:JSON.stringify({data})});
  const ok=async(uid,data)=>{const response=await send(uid,data);assert.equal(response.status,200,await response.clone().text());return (await response.json()).result;};
  const policy={...p,farm:target,changedBy:'md-manager'},digest=policyDigest(policy),scope={farm:target,kind:policy.kind,currency:policy.currency};
  await ok('md-manager',{operation:'propose',policy,digest});
  const snapshot=await ok('md-one',{operation:'listDrafts',...scope});
  assert.equal(snapshot.drafts.length,1);assert.equal(snapshot.drafts[0].proposedBy,'md-manager');assert.deepEqual(snapshot.drafts[0].policy,policy);
  assert.equal((await ok('md-one',{operation:'getDraft',...scope,digest})).drafts[0].digest,digest);
  assert.notEqual((await send('md-other',{operation:'listDrafts',...scope})).status,200);
  const activate={operation:'activate',policy,digest,expectedActive:snapshot.expectedActive,expectedDraftHead:snapshot.head,expectedAuthorityRevision:snapshot.authorityRevision};
  const concurrent=await Promise.all(['md-one','md-two'].map(async uid=>({uid,response:await send(uid,activate)})));
  assert.equal(concurrent.filter(x=>x.response.status===200).length,1);const winner=concurrent.find(x=>x.response.status===200);const first=(await winner.response.json()).result;
  assert.deepEqual(await ok(winner.uid,activate),first);
  assert.equal((await ok('md-one',{operation:'getActive',...scope})).active.proposedBy,'md-manager');
  assert.equal((await db.collection(`agrico_approval_policies/${target}/versions`).get()).size,1);
  assert.equal((await db.collection(`agrico_approval_policies/${target}/audit`).where('action','==','activate').get()).size,1);
  const two={...policy,version:2,selfLimit:'50'},twoDigest=policyDigest(two);await ok('md-manager',{operation:'propose',policy:two,digest:twoDigest});
  assert.notEqual((await send(winner.uid,activate)).status,200); // stale head, even idempotent old activation
  assert.notEqual((await send('md-one',{operation:'getDraft',...scope,digest})).status,200);
  const fresh=await ok('md-one',{operation:'listDrafts',...scope});
  await db.doc('agrico_memberships/md-one').update({active:false});
  assert.notEqual((await send('md-one',{operation:'getDraft',...scope,digest:twoDigest})).status,200);
  assert.notEqual((await send('md-one',{operation:'activate',policy:two,digest:twoDigest,expectedActive:fresh.expectedActive,expectedDraftHead:fresh.head,expectedAuthorityRevision:1})).status,200);
  const fs=clientFirestore(apps[0]);connectFirestoreEmulator(fs,'127.0.0.1',8088);
  await assert.rejects(getDocFromServer(doc(fs,`agrico_approval_policies/${target}/drafts/${twoDigest}`)),{code:'permission-denied'});
  await assert.rejects(setDoc(doc(fs,`agrico_approval_policies/${target}/drafts/${twoDigest}`),{policy:two}),{code:'permission-denied'});
  await db.doc(`agrico_approval_authorities/${target}`).update({active:false});
  assert.notEqual((await send('md-manager',{operation:'getActive',...scope})).status,200);
  await assert.rejects(fetch('http://127.0.0.1:1/unavailable',{method:'POST',body:JSON.stringify(activate)}));
  assert.equal((await db.collection(`agrico_approval_policies/${target}/versions`).get()).size,1);
 }finally{await Promise.all(apps.map(a=>deleteApp(a)));}
});

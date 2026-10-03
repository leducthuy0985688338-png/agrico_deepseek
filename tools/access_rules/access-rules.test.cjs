const {before, after, beforeEach, test} = require('node:test');
const {readFileSync} = require('node:fs');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, getDocs, collection, query, where, limit, writeBatch, updateDoc, Timestamp, serverTimestamp, deleteDoc} = require('firebase/firestore');
let env;
const ts = days => Timestamp.fromMillis(Date.now() + days * 86400000);
function member(uid, role = 'fieldWorker', farmId = 'local-farm') {
  return {schemaVersion:1, userId:uid, membershipId:uid, farmId, active:true,
    roles:[{role, scopes:['allFarm']}], offlineUntil:ts(7), extraPermissions:[], deniedPermissions:[],
    extraPermissionScopes:[], projectIds:[], departmentIds:[], teamIds:[], fieldIds:[], taskIds:[],
    machineIds:[], warehouseIds:[], displayName:uid};
}
before(async()=>{env = await initializeTestEnvironment({projectId:'demo-agrico-access',firestore:{host:'127.0.0.1',port:8088,rules:readFileSync(require('node:path').resolve(__dirname,'../../docs/security/agrico-memberships.rules'),'utf8')}});});
after(async()=>{await env?.cleanup();});
beforeEach(async()=>{
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    await setDoc(doc(db,'agrico_memberships/admin'),member('admin','systemAdmin'));
    await setDoc(doc(db,'agrico_memberships/worker'),member('worker'));
    await setDoc(doc(db,'agrico_memberships/other'),member('other','fieldWorker','other-farm'));
    await setDoc(doc(db,'agrico_access_admins/admin'),{active:true,farmId:'local-farm'});
    await setDoc(doc(db,'agrico_access_policy/local-farm'),{autoRenew:true,offlineDays:7,maxOfflineDays:30});
  });
});
function db(uid){return uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore();}
async function save(actor,uid,changes={},audit=true,create=false){
  const d=db(actor), ref=doc(d,'agrico_memberships',uid), a=doc(collection(d,'agrico_access_audit'));
  // Bypass read permissions only for fixtures used to probe denied writes.
  let old=null;
  await env.withSecurityRulesDisabled(async ctx=>{old=(await getDoc(doc(ctx.firestore(),'agrico_memberships',uid))).data() ?? null;});
  let next={...(old ?? member(uid)),...changes, adminRevision:(old?.adminRevision ?? 0)+1,
    adminAuditId:a.id,updatedBy:actor,updatedAt:serverTimestamp()};
  const b=writeBatch(d);b.set(ref,next);
  if(audit)b.set(a,{farmId:next.farmId,actorUid:actor,targetUid:uid,revision:next.adminRevision,
    reason:'test grant',occurredAt:serverTimestamp(),before:old,after:next});
  return b.commit();
}
test('own grant readable, other grant denied, unauthenticated denied',async()=>{
  await assertSucceeds(getDoc(doc(db('worker'),'agrico_memberships/worker')));
  await assertFails(getDoc(doc(db('worker'),'agrico_memberships/admin')));
  await assertFails(getDoc(doc(db(), 'agrico_memberships/worker')));
});
test('admin query is farm scoped and limited',async()=>{
  await assertSucceeds(getDocs(query(collection(db('admin'),'agrico_memberships'),where('farmId','==','local-farm'),limit(200))));
  await assertFails(getDocs(collection(db('admin'),'agrico_memberships')));
  await assertFails(getDocs(query(collection(db('worker'),'agrico_memberships'),where('farmId','==','local-farm'),limit(200))));
});
test('admin creates and updates with mandatory atomic audit',async()=>{
  await assertSucceeds(save('admin','newworker',{roles:[{role:'machineOperator',scopes:['assignedTasks','assignedMachines']}] }));
  await assertSucceeds(save('admin','worker',{active:false}));
  await assertFails(save('admin','worker',{active:true},false));
});
test('cannot change own grant, root grant, or authority registry',async()=>{
  await assertFails(save('admin','admin',{active:false}));
  await assertFails(setDoc(doc(db('worker'),'agrico_access_admins/worker'),{active:true,farmId:'local-farm'}));
  await assertFails(updateDoc(doc(db('admin'),'agrico_access_admins/admin'),{active:false}));
  await assertFails(deleteDoc(doc(db('admin'),'agrico_memberships/worker')));
});
test('role name alone cannot grant server administration',async()=>{
  await env.withSecurityRulesDisabled(async ctx=>{await updateDoc(doc(ctx.firestore(),'agrico_memberships/worker'),{roles:[{role:'systemAdmin',scopes:['allFarm']}]});});
  await assertFails(save('worker','newworker'));
});
test('reject identity/farm changes and unsupported roles/permissions',async()=>{
  for(const change of [{userId:'admin'},{membershipId:'admin'},{farmId:'other-farm'},
    {roles:[{role:'superuser',scopes:['allFarm']}]},{extraPermissions:['super.all']},
    {roles:[{role:'director',scopes:['unknown']}]},{offlineUntil:ts(100)}]){
    await assertFails(save('admin','worker',change));
  }
  await assertFails(save('admin','other'));
});
test('renewal only extends lease, cannot elevate or unlock',async()=>{
  const ref=doc(db('worker'),'agrico_memberships/worker');
  await env.withSecurityRulesDisabled(async ctx=>{await updateDoc(doc(ctx.firestore(),'agrico_memberships/worker'),{offlineUntil:ts(-1)});});
  await assertSucceeds(updateDoc(ref,{offlineUntil:ts(6.99),leaseRenewedAt:serverTimestamp()}));
  await assertFails(updateDoc(ref,{offlineUntil:ts(60),leaseRenewedAt:serverTimestamp()}));
  await assertFails(updateDoc(ref,{offlineUntil:ts(6.999),roles:[{role:'systemAdmin',scopes:['allFarm']}],leaseRenewedAt:serverTimestamp()}));
  await env.withSecurityRulesDisabled(async ctx=>{await updateDoc(doc(ctx.firestore(),'agrico_memberships/worker'),{active:false});});
  await assertFails(updateDoc(ref,{active:true,offlineUntil:ts(6.999),leaseRenewedAt:serverTimestamp()}));
  await assertFails(updateDoc(ref,{offlineUntil:ts(6.999),leaseRenewedAt:serverTimestamp()}));
});
test('revoked admin and denied permission fail server validation',async()=>{
  await env.withSecurityRulesDisabled(async ctx=>{await updateDoc(doc(ctx.firestore(),'agrico_memberships/admin'),{deniedPermissions:['role.manage']});});
  await assertFails(save('admin','worker'));
  await env.withSecurityRulesDisabled(async ctx=>{await updateDoc(doc(ctx.firestore(),'agrico_memberships/admin'),{deniedPermissions:[],active:false});});
  await assertFails(save('admin','worker'));
});
test('audit cannot be rewritten or deleted',async()=>{
  await assertSucceeds(save('admin','worker'));
  const q=query(collection(db('admin'),'agrico_access_audit'),where('farmId','==','local-farm'),limit(50));
  const entries=await assertSucceeds(getDocs(q));
  const ref=entries.docs[0].ref;
  await assertFails(updateDoc(ref,{reason:'hide change'}));
  await assertFails(deleteDoc(ref));
});
test('four role assignments fit rule limits and fifth is refused',async()=>{
  const roles=['director','agronomist','gisOfficer','machineOperator'].map(role=>({role,scopes:['allFarm','team','assignedFields','assignedTasks','own','project','department','assignedMachines','assignedWarehouses']}));
  await assertSucceeds(save('admin','worker',{roles}));
  await assertFails(save('admin','worker',{roles:[...roles,{role:'officeStaff',scopes:['own']}]}));
});
test('protected second administrator and expired authority cannot be edited',async()=>{
  await env.withSecurityRulesDisabled(async ctx=>{
    await setDoc(doc(ctx.firestore(),'agrico_access_admins/worker'),{active:true,farmId:'local-farm'});
  });
  await assertFails(save('admin','worker'));
  await env.withSecurityRulesDisabled(async ctx=>{
    await updateDoc(doc(ctx.firestore(),'agrico_memberships/admin'),{offlineUntil:ts(-1)});
  });
  await assertFails(save('admin','newworker'));
});
test('renewal policy cannot be modified by clients',async()=>{
  await assertFails(updateDoc(doc(db('admin'),'agrico_access_policy/local-farm'),{offlineDays:90}));
  await assertFails(getDoc(doc(db('other'),'agrico_access_policy/local-farm')));
});

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

// A05: probe the actual Rules with direct client writes, independent of Flutter.
let catalogSequence=0;
const catRoot=farm=>`agrico_catalog/${farm}`;
const catKey=(kind,type,value)=>`${kind}~${type}~${require('node:crypto').createHash('sha256').update(value,'utf8').digest('hex').toUpperCase()}`;
const unit=(id='kg',changes={})=>({id,farm_id:'local-farm',kind:'unit',code:id.toUpperCase(),name:id==='kg'?'Kilogram':id,name_key:(id==='kg'?'Kilogram':id).toUpperCase(),unit_id:null,active:1,revision:1,...changes});
async function fixture(path){let result;await env.withSecurityRulesDisabled(async ctx=>{result=(await getDoc(doc(ctx.firestore(),path))).data();});return result;}
async function catalogChange(actor,entity,payload,options={}){
  const farm=options.farm??payload.farm_id, root=catRoot(farm), id=payload.id;
  const bucket=entity==='entry'?'entries':'requests';
  const prior=await fixture(`${root}/${bucket}/${id}`), before=prior?.payload??null;
  const operationId=options.operationId??`catalog-op-${++catalogSequence}`;
  const baseVersion=options.baseVersion??prior?.version??0;
  const command={operationId,farmId:farm,actorUid:options.actorUid??actor,entity,targetId:id,
    baseVersion,newVersion:baseVersion+1,payload,reason:options.reason??'Test catalog change',
    occurredAt:options.occurredAt??new Date().toISOString(),before,acceptedAt:serverTimestamp()};
  const d=db(actor), b=writeBatch(d);
  b.set(doc(d,`${root}/${bucket}/${id}`),{version:command.newVersion,operationId,payload});
  if(!options.withoutReceipt)b.set(doc(d,`${root}/operations/${operationId}`),command);
  if(entity==='entry'){
    if(!options.withoutLocks){
      const locks=new Map([[catKey(payload.kind,'code',payload.code),{targetId:id,type:'code',value:payload.code}],[catKey(payload.kind,'name',payload.name_key),{targetId:id,type:'name',value:payload.name_key}]]);
      if(before&&before.name_key!==payload.name_key)locks.set(catKey(payload.kind,'name',before.name_key),{targetId:null,type:'name',value:before.name_key});
      for(const [key,data] of locks)b.set(doc(d,`${root}/keys/${key}`),{...data,operationId});
    }
    if(!options.withoutUsage){
      const refs=new Set([before?.unit_id,payload.unit_id].filter(Boolean));
      for(const ref of refs){
        const usage=await fixture(`${root}/unit_usage/${ref}`);
        const oldRef=before?.unit_id===ref?1:0, nextRef=payload.unit_id===ref?1:0;
        const activeOld=oldRef&&before.active===1?1:0, activeNext=nextRef&&payload.active===1?1:0;
        b.set(doc(d,`${root}/unit_usage/${ref}`),{references:(usage?.references??0)+nextRef-oldRef,
          activeReferences:options.forgeCount??(usage?.activeReferences??0)+activeNext-activeOld,operationId});
      }
    }
  }
  await b.commit();
  return operationId;
}
function suggestion(id='suggestion',changes={}){return {id,farm_id:'local-farm',actor_uid:'worker',kind:'unit',code:'LIT',name:'Liter',reason:'Need unit',created_at:new Date().toISOString(),status:'pending',...changes};}
async function resolution(actor,changes={}){
  const prior=(await fixture(`${catRoot('local-farm')}/requests/suggestion`)).payload;
  const occurredAt=new Date().toISOString(),reason='Review suggestion';
  return catalogChange(actor,'request',{...prior,status:'approved',entry_id:'kg',resolved_by:actor,resolved_at:occurredAt,resolution:reason,...changes},{occurredAt,reason});
}
test('catalog manager atomically publishes a unit; member reads only with bounded query',async()=>{
  await assertSucceeds(catalogChange('admin','entry',unit()));
  await assertSucceeds(getDoc(doc(db('worker'),`${catRoot('local-farm')}/entries/kg`)));
  await assertSucceeds(getDocs(query(collection(db('worker'),`${catRoot('local-farm')}/entries`),limit(200))));
  await assertFails(getDocs(collection(db('worker'),`${catRoot('local-farm')}/entries`)));
  await assertFails(getDoc(doc(db('other'),`${catRoot('local-farm')}/entries/kg`)));
  await assertFails(getDoc(doc(db(),`${catRoot('local-farm')}/entries/kg`)));
});
test('catalog masters require manager, live lease and cloud permission',async()=>{
  await assertFails(catalogChange('worker','entry',unit()));
  await env.withSecurityRulesDisabled(async ctx=>{await updateDoc(doc(ctx.firestore(),'agrico_memberships/admin'),{offlineUntil:ts(-1)});});
  await assertFails(catalogChange('admin','entry',unit()));
  await env.withSecurityRulesDisabled(async ctx=>{await updateDoc(doc(ctx.firestore(),'agrico_memberships/admin'),{offlineUntil:ts(7),deniedPermissions:['cloud.sync']});});
  await assertFails(catalogChange('admin','entry',unit()));
});
test('catalog publication without receipt or uniqueness locks denied',async()=>{
  await assertFails(catalogChange('admin','entry',unit(),{withoutReceipt:true}));
  await assertFails(catalogChange('admin','entry',unit(),{withoutLocks:true}));
  await assertSucceeds(catalogChange('admin','entry',unit()));
});
test('catalog duplicate code or normalized name denied across IDs including retired entries',async()=>{
  await catalogChange('admin','entry',unit());
  await assertFails(catalogChange('admin','entry',unit('other',{code:'KG'})));
  await assertFails(catalogChange('admin','entry',unit('other',{name:'Kilogram',name_key:'KILOGRAM'})));
  await catalogChange('admin','entry',unit('kg',{active:0,revision:2}));
  await assertFails(catalogChange('admin','entry',unit('other',{code:'KG'})));
});
test('catalog stale versions, actor spoofing and cross-farm write denied',async()=>{
  await catalogChange('admin','entry',unit());
  await assertFails(catalogChange('admin','entry',unit('kg',{revision:2}),{baseVersion:0}));
  await assertFails(catalogChange('admin','entry',unit('lit'),{actorUid:'worker'}));
  await assertFails(catalogChange('admin','entry',unit('lit',{farm_id:'other-farm'})));
});
test('catalog immutable codes, kinds and canonical names enforced',async()=>{
  await catalogChange('admin','entry',unit());
  await assertFails(catalogChange('admin','entry',unit('kg',{code:'KILO',revision:2})));
  await assertFails(catalogChange('admin','entry',unit('kg',{kind:'machine',revision:2})));
  await assertFails(catalogChange('admin','entry',unit('kg',{name_key:'FAKE',revision:2})));
  await assertFails(catalogChange('admin','entry',unit('kg',{name:' Kilogram ',name_key:'KILOGRAM',revision:2})));
});
test('unused unit rename releases prior name but preserves code ownership',async()=>{
  await catalogChange('admin','entry',unit());
  await assertSucceeds(catalogChange('admin','entry',unit('kg',{name:'Kilogramme',name_key:'KILOGRAMME',revision:2})));
  await assertSucceeds(catalogChange('admin','entry',unit('other',{name:'Kilogram',name_key:'KILOGRAM'})));
  await assertFails(catalogChange('admin','entry',unit('third',{code:'KG'})));
});
const material=(changes={})=>({id:'fertilizer',farm_id:'local-farm',kind:'material',code:'FERT',name:'Fertilizer',name_key:'FERTILIZER',unit_id:'kg',active:1,revision:1,...changes});
test('active unit required and reference ledger must be atomic and exact',async()=>{
  await assertFails(catalogChange('admin','entry',material()));
  await catalogChange('admin','entry',unit());
  await assertFails(catalogChange('admin','entry',material(),{withoutUsage:true}));
  await assertFails(catalogChange('admin','entry',material(),{forgeCount:0}));
  await assertSucceeds(catalogChange('admin','entry',material()));
  const usage=await fixture(`${catRoot('local-farm')}/unit_usage/kg`);
  require('node:assert/strict').equal(usage.references,1);
  require('node:assert/strict').equal(usage.activeReferences,1);
});
test('referenced unit cannot rename or deactivate until active consumers retire',async()=>{
  await catalogChange('admin','entry',unit());await catalogChange('admin','entry',material());
  await assertFails(catalogChange('admin','entry',unit('kg',{active:0,revision:2})));
  await assertFails(catalogChange('admin','entry',unit('kg',{name:'Kilo',name_key:'KILO',revision:2})));
  await assertSucceeds(catalogChange('admin','entry',material({active:0,revision:2})));
  await assertSucceeds(catalogChange('admin','entry',unit('kg',{active:0,revision:2})));
  await assertFails(catalogChange('admin','entry',unit('kg',{name:'Kilo',name_key:'KILO',revision:3})));
});
test('material unit immutable even when replacement is valid',async()=>{
  await catalogChange('admin','entry',unit());await catalogChange('admin','entry',unit('lit'));await catalogChange('admin','entry',material());
  await assertFails(catalogChange('admin','entry',material({unit_id:'lit',revision:2})));
});
test('crop unit reassignment updates both unit ledgers',async()=>{
  await catalogChange('admin','entry',unit());await catalogChange('admin','entry',unit('lit'));
  const crop={...material(),id:'crop',kind:'crop',code:'CROP',name:'Lạc / ພືດ',name_key:'LẠC / ພືດ'};
  await catalogChange('admin','entry',crop);
  await assertSucceeds(catalogChange('admin','entry',{...crop,unit_id:'lit',revision:2}));
  require('node:assert/strict').equal((await fixture(`${catRoot('local-farm')}/unit_usage/kg`)).references,0);
  require('node:assert/strict').equal((await fixture(`${catRoot('local-farm')}/unit_usage/lit`)).references,1);
});
test('worker creates own pending suggestion; cannot impersonate, write master or approve',async()=>{
  await assertSucceeds(catalogChange('worker','request',suggestion()));
  await assertFails(catalogChange('worker','request',suggestion('other',{actor_uid:'admin'})));
  await assertFails(resolution('worker'));
  await assertFails(catalogChange('worker','request',suggestion('bad',{status:'approved',entry_id:'kg'})));
});
test('suggestion queries and receipts are private to creator or manager',async()=>{
  const id=await catalogChange('worker','request',suggestion());
  await assertSucceeds(getDocs(query(collection(db('worker'),`${catRoot('local-farm')}/requests`),where('payload.actor_uid','==','worker'),limit(200))));
  await assertFails(getDocs(query(collection(db('worker'),`${catRoot('local-farm')}/requests`),limit(200))));
  await assertSucceeds(getDoc(doc(db('worker'),`${catRoot('local-farm')}/operations/${id}`)));
  await env.withSecurityRulesDisabled(async ctx=>{await setDoc(doc(ctx.firestore(),'agrico_memberships/peer'),member('peer'));});
  await assertFails(getDoc(doc(db('peer'),`${catRoot('local-farm')}/requests/suggestion`)));
  await assertFails(getDoc(doc(db('peer'),`${catRoot('local-farm')}/operations/${id}`)));
});
test('manager resolves pending suggestion against active same-kind master with immutable content',async()=>{
  await catalogChange('admin','entry',unit());await catalogChange('worker','request',suggestion());
  await assertFails(resolution('admin',{name:'Altered suggestion'}));
  await assertSucceeds(resolution('admin'));
  await assertFails(resolution('admin'));
});
test('manager self approval and inactive or wrong-kind targets denied',async()=>{
  await catalogChange('admin','entry',unit());
  await catalogChange('admin','request',suggestion('suggestion',{actor_uid:'admin'}));
  await assertFails(resolution('admin'));
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx=>{await setDoc(doc(ctx.firestore(),'agrico_memberships/admin'),member('admin','systemAdmin'));await setDoc(doc(ctx.firestore(),'agrico_memberships/worker'),member('worker'));});
  await catalogChange('admin','entry',unit('kg',{active:0}));await catalogChange('worker','request',suggestion());
  await assertFails(resolution('admin'));
});
test('immutable receipts and catalog records cannot be deleted; counter cannot be forged alone',async()=>{
  const id=await catalogChange('admin','entry',unit());
  await assertFails(updateDoc(doc(db('admin'),`${catRoot('local-farm')}/operations/${id}`),{reason:'Changed'}));
  await assertFails(deleteDoc(doc(db('admin'),`${catRoot('local-farm')}/operations/${id}`)));
  await assertFails(deleteDoc(doc(db('admin'),`${catRoot('local-farm')}/entries/kg`)));
  await assertFails(setDoc(doc(db('admin'),`${catRoot('local-farm')}/unit_usage/kg`),{references:0,activeReferences:0,operationId:id}));
});
test('two devices with same normalized name cannot both win',async()=>{
  const outcomes=await Promise.allSettled([catalogChange('admin','entry',unit('one',{name:'Same',name_key:'SAME'})),catalogChange('admin','entry',unit('two',{name:'Same',name_key:'SAME'}))]);
  require('node:assert/strict').equal(outcomes.filter(x=>x.status==='fulfilled').length,1);
});
test('explicit scoped catalog grant works and a deny takes priority',async()=>{
  await env.withSecurityRulesDisabled(async ctx=>{await updateDoc(doc(ctx.firestore(),'agrico_memberships/worker'),{extraPermissions:['catalog.manage'],extraPermissionScopes:['own']});});
  await assertFails(catalogChange('worker','entry',unit()));
  await env.withSecurityRulesDisabled(async ctx=>{await updateDoc(doc(ctx.firestore(),'agrico_memberships/worker'),{extraPermissionScopes:['allFarm']});});
  await assertSucceeds(catalogChange('worker','entry',unit()));
  await env.withSecurityRulesDisabled(async ctx=>{await updateDoc(doc(ctx.firestore(),'agrico_memberships/worker'),{deniedPermissions:['catalog.manage']});});
  await assertFails(catalogChange('worker','entry',unit('lit')));
});
test('escaped slash and percent in names have separate uniqueness locks',async()=>{
  await assertSucceeds(catalogChange('admin','entry',unit('one',{name:'A/B',name_key:'A/B'})));
  await assertSucceeds(catalogChange('admin','entry',unit('two',{name:'A%2FB',name_key:'A%2FB'})));
  await assertFails(catalogChange('admin','entry',unit('three',{name:'A/B',name_key:'A/B'})));
});
test('maximum role count and rename plus unit move stay within Rules limits',async()=>{
  await env.withSecurityRulesDisabled(async ctx=>{await updateDoc(doc(ctx.firestore(),'agrico_memberships/admin'),{roles:[{role:'fieldWorker',scopes:['own']},{role:'accountant',scopes:['department']},{role:'auditor',scopes:['own']},{role:'systemAdmin',scopes:['allFarm']}]});});
  await catalogChange('admin','entry',unit());await catalogChange('admin','entry',unit('lit'));
  const crop={...material(),id:'crop',kind:'crop',code:'CROP',name:'Lạc / ພືດ',name_key:'LẠC / ພືດ'};
  await assertSucceeds(catalogChange('admin','entry',crop));
  await assertSucceeds(catalogChange('admin','entry',{...crop,name:'Cây lạc',name_key:'CÂY LẠC',unit_id:'lit',revision:2}));
});
test('receipt alone cannot certify a mutation and old receipt cannot authorize replay',async()=>{
  const p=unit(),operationId='orphan';
  await assertFails(setDoc(doc(db('admin'),`${catRoot('local-farm')}/operations/${operationId}`),{operationId,farmId:'local-farm',actorUid:'admin',entity:'entry',targetId:'kg',baseVersion:0,newVersion:1,payload:p,reason:'Orphan',occurredAt:new Date().toISOString(),before:null,acceptedAt:serverTimestamp()}));
  const id=await catalogChange('admin','entry',p);
  await assertFails(catalogChange('admin','entry',{...p,revision:2},{operationId:id}));
});
test('unit counter cannot be incremented by an unrelated valid operation',async()=>{
  const p=unit('lit'), id='unrelated';
  const d=db('admin'),b=writeBatch(d), root=catRoot('local-farm');
  const operation={operationId:id,farmId:'local-farm',actorUid:'admin',entity:'entry',targetId:'lit',baseVersion:0,newVersion:1,payload:p,reason:'Test unrelated ledger',occurredAt:new Date().toISOString(),before:null,acceptedAt:serverTimestamp()};
  b.set(doc(d,`${root}/operations/${id}`),operation);
  b.set(doc(d,`${root}/entries/lit`),{version:1,operationId:id,payload:p});
  for(const [type,value] of [['code',p.code],['name',p.name_key]])b.set(doc(d,`${root}/keys/${catKey(p.kind,type,value)}`),{targetId:'lit',operationId:id,type,value});
  b.set(doc(d,`${root}/unit_usage/kg`),{references:1,activeReferences:1,operationId:id});
  await assertFails(b.commit());
});

test('Unicode Vietnamese Lao names use canonical server keys',async()=>{ await assertSucceeds(catalogChange('admin','entry',unit('unicode',{name:'Lạc / ພືດ',name_key:'LẠC / ພືດ'}))); });
test('maximum-length Vietnamese name publishes and duplicate case variant is refused',async()=>{
  const name='Lạc'.repeat(33)+'A';
  await assertSucceeds(catalogChange('admin','entry',unit('long',{name,name_key:name.toUpperCase()})));
  await assertFails(catalogChange('admin','entry',unit('long2',{name:name.toUpperCase(),name_key:name.toUpperCase()})));
});
test('regex-looking names are literal; Unicode key spoofing is refused',async()=>{
  const name='À\\E.*\\QZ';
  await assertSucceeds(catalogChange('admin','entry',unit('quoted',{name,name_key:name})));
  await assertFails(catalogChange('admin','entry',unit('badquote',{name,name_key:'Á\\E.*\\QZ'})));
  await assertFails(catalogChange('admin','entry',unit('kelvin',{name:'K',name_key:'K'})));
  await assertFails(catalogChange('admin','entry',unit('lower',{name:'Lạc',name_key:'LạC'})));
});

test('malformed suggestion timestamps and empty text cannot poison receiving devices',async()=>{await assertFails(catalogChange('worker','request',suggestion('badtime',{created_at:'not-a-date'})));await assertFails(catalogChange('worker','request',suggestion('badname',{name:'   '})));await assertFails(catalogChange('worker','request',suggestion('badreason',{reason:'   '})));await assertFails(catalogChange('admin','entry',unit(),{occurredAt:'not-a-date'}));});

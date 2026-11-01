import {createHash} from 'node:crypto';
import {active,has,manages,permissionScopes} from './domain.js';

export function canonical(value){
  if(Array.isArray(value))return value.map(canonical);
  if(value && typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(k=>[k,canonical(value[k])]));
  return value;
}
export const policyDigest=p=>createHash('sha256').update(JSON.stringify(canonical(p))).digest('hex');
const selfKinds=new Set(['materialIssue','machineRun','fieldWork','directExpense']);
const kinds=new Set(['cashReceipt','cashPayment','settlement','payroll','payrollExtra','payrollAdjustment','purchase','overheadAllocation','correction','tradePosting',...selfKinds]);
const reject=()=>{throw new Error('approval-authority-denied');};
function validPolicy(p,digest){
  if(!p || Object.keys(p).sort().join(',')!==['farm','kind','currency','version','selfEnabled','selfLimit','independentLimit','createPermission','approvePermission','changedBy'].sort().join(',') ||
    !/^[A-Za-z0-9_-]{1,128}$/.test(p.farm) || !kinds.has(p.kind) || !['VND','LAK'].includes(p.currency) ||
    !Number.isSafeInteger(p.version) || p.version<1 || typeof p.changedBy!=='string' || !/^[A-Za-z0-9_-]{1,128}$/.test(p.changedBy) ||
    typeof p.selfEnabled!=='boolean' || (p.selfEnabled && !selfKinds.has(p.kind)) ||
    typeof p.createPermission!=='string' || typeof p.approvePermission!=='string' ||
    p.createPermission.length>100 || p.approvePermission.length>100 || policyDigest(p)!==digest)reject();
  for(const limit of [p.selfLimit,p.independentLimit]){
    if(limit!==null && (typeof limit!=='string' || limit.length>512 || !/^\d+(\.\d{1,6})?$/.test(limit)))reject();
  }
  if(p.selfEnabled && p.selfLimit===null)reject();
}
function capability(member,permission,farm,now){
  return active(member,farm,now) && has(member,permission) &&
    member.extraPermissions?.includes(permission) && member.extraPermissionScopes?.includes('allFarm');
}

/// repo methods run in ONE server transaction; no client-supplied authority.
export async function approvalAuthority(repo,uid,input,now){
  if(!uid)reject();
  if(['listDrafts','getDraft','getActive'].includes(input?.operation))return approvalCatalog(repo,uid,input,now);
  const p=input?.policy;validPolicy(p,input.digest);
  const actor=await repo.member(uid),grant=await repo.authority(p.farm);
  if(!active(actor,p.farm,now) || actor.userId!==uid || !grant || grant.active!==true || !Number.isSafeInteger(grant.revision) || grant.revision<1)reject();
  const author=await repo.member(p.changedBy);
  if(author?.userId!==p.changedBy || !capability(author,'approval.policy.manage',p.farm,now) || !capability(author,'approval.limits.manage',p.farm,now) ||
    !grant.managerUids?.includes(p.changedBy))reject();
  const current=await repo.current(p.farm,p.kind,p.currency);
  if(input.operation==='propose'){
    if(uid!==p.changedBy)reject();
    const existing=await repo.draft(p.farm,input.digest),head=await repo.draftHead(p.farm,p.kind,p.currency);
    if(existing){
      if(existing.proposedBy!==uid || existing.authorityRevision!==grant.revision || policyDigest(existing.policy)!==input.digest)reject();
      return {proposed:true};
    }
    if(p.version!==(head?.version??current?.version??0)+1)reject();
    await repo.propose(p.farm,p.kind,p.currency,{policy:canonical(p),digest:input.digest,version:p.version,
      proposedBy:uid,proposedAt:now,authorityRevision:grant.revision});
    await repo.audit(p.farm,'propose',uid,now,{digest:input.digest,version:p.version,authorityRevision:grant.revision});
    return {proposed:true};
  }
  if(input.operation==='activate'){
    if(uid===p.changedBy || !grant.activatorUids?.includes(uid) || !capability(actor,'approval.policy.activate',p.farm,now))reject();
    const head=await repo.draftHead(p.farm,p.kind,p.currency);
    if(input.expectedAuthorityRevision!==grant.revision || !sameIdentity(head,input.expectedDraftHead) ||
      !sameIdentity(head,{version:p.version,digest:input.digest}) || !validIdentity(input.expectedActive))reject();
    if(current?.digest===input.digest && current.authorityRevision===grant.revision){
      if(current.activatedBy!==uid || !sameIdentity(current.expectedBefore,input.expectedActive))reject();return {reference:current.reference};
    }
    if(!sameIdentity(current,input.expectedActive))reject();
    const draft=await repo.draft(p.farm,input.digest);
    if(!draft || draft.proposedBy!==p.changedBy || draft.authorityRevision!==grant.revision ||
      policyDigest(draft.policy)!==input.digest || p.version<=(current?.version??0))reject();
    const reference=JSON.stringify(canonical({farm:p.farm,kind:p.kind,currency:p.currency,digest:input.digest,
      version:p.version,authorityRevision:grant.revision,activatedBy:uid,activatedAt:now}));
    const record={policy:canonical(p),digest:input.digest,version:p.version,authorityRevision:grant.revision,
      proposedBy:draft.proposedBy,proposedAt:draft.proposedAt,expectedBefore:input.expectedActive,
      activatedBy:uid,activatedAt:now,reference};
    await repo.activate(p.farm,p.kind,p.currency,record,current,uid,now);
    return {reference};
  }
  if(input.operation!=='verify')reject();
  if(!current || current.digest!==input.digest || current.authorityRevision!==grant.revision ||
    input.reference!==current.reference || input.activatedBy!==current.activatedBy || input.activatedAt!==current.activatedAt ||
    policyDigest(current.policy)!==input.digest || !grant.activatorUids?.includes(current.activatedBy))return {current:false};
  const activator=await repo.member(current.activatedBy);
  return {current:activator?.userId===current.activatedBy && capability(activator,'approval.policy.activate',p.farm,now)};
}

export async function approvalRelations(repo,uid,input,now){
  if(!uid || !input || typeof input.farm!=='string' || typeof input.partyId!=='string' || input.partyId.length>128)reject();
  const member=await repo.member(uid);
  if(!active(member,input.farm,now) || member.userId!==uid || !has(member,'finance.view'))reject();
  const grant=await repo.authority(input.farm);
  if(grant?.active!==true)return {verified:false};
  const users=grant.partyMemberships?.[input.partyId];
  if(!Array.isArray(users) || users.length>100 || users.some(u=>typeof u!=='string' || !u || u.length>128))return {verified:false};
  const scopes=permissionScopes(member,'finance.view');
  if(!scopes.has('allFarm'))for(const uid of users){
    const target=await repo.member(uid);
    if(!target || target.farmId!==input.farm || target.userId!==uid)return {verified:false};
    const assigned=[['assignedMachines','machineIds'],['assignedWarehouses','warehouseIds'],['assignedFields','fieldIds']]
      .some(([scope,key])=>scopes.has(scope) && (member[key]??[]).some(id=>(target[key]??[]).includes(id)));
    if(!manages(member,'finance.view',target) && !assigned && !(scopes.has('own') && uid===member.userId))return {verified:false};
  }
  return {verified:true,users:[...new Set(users)].sort()};
}


function validIdentity(value){
  return value===null || (value && Object.keys(value).sort().join(',')==='digest,version' &&
    Number.isSafeInteger(value.version) && value.version>0 && /^[a-f0-9]{64}$/.test(value.digest));
}
function identity(value){return value?{version:value.version,digest:value.digest}:null;}
function sameIdentity(a,b){return validIdentity(b) && JSON.stringify(identity(a))===JSON.stringify(b && {version:b.version,digest:b.digest});}

// Bounded catalog: only the current head candidate for one kind/currency.
// Older drafts are never returned or importable through this protocol.
export async function approvalCatalog(repo,uid,input,now){
  const {farm,kind,currency,operation}=input??{};
  if(!uid || !['listDrafts','getDraft','getActive'].includes(operation) ||
    typeof farm!=='string' || !/^[A-Za-z0-9_-]{1,128}$/.test(farm) || !kinds.has(kind) || !['VND','LAK'].includes(currency))reject();
  const actor=await repo.member(uid),grant=await repo.authority(farm);
  if(actor?.userId!==uid || !active(actor,farm,now) || grant?.active!==true || !Number.isSafeInteger(grant.revision) || grant.revision<1)reject();
  const manager=grant.managerUids?.includes(uid) && capability(actor,'approval.policy.manage',farm,now);
  const activator=grant.activatorUids?.includes(uid) && capability(actor,'approval.policy.activate',farm,now);
  if(!manager && !activator)reject();
  const head=await repo.draftHead(farm,kind,currency),current=await repo.current(farm,kind,currency);
  if(!validIdentity(identity(head)) || !validIdentity(identity(current)))reject();
  async function checked(record,activated){
    if(!record || record.authorityRevision!==grant.revision)return null;
    validPolicy(record.policy,record.digest);
    const p=record.policy,author=await repo.member(p.changedBy);
    if(p.farm!==farm || p.kind!==kind || p.currency!==currency || p.version!==record.version ||
      record.proposedBy!==p.changedBy || !Number.isFinite(Date.parse(record.proposedAt)))reject();
    if(author?.userId!==p.changedBy || !grant.managerUids?.includes(p.changedBy) ||
      !capability(author,'approval.policy.manage',farm,now) || !capability(author,'approval.limits.manage',farm,now))return null;
    if(activated){
      const reviewer=await repo.member(record.activatedBy);
      if(record.activatedBy===p.changedBy || !Number.isFinite(Date.parse(record.activatedAt)) || typeof record.reference!=='string')reject();
      if(!grant.activatorUids?.includes(record.activatedBy) || reviewer?.userId!==record.activatedBy || !capability(reviewer,'approval.policy.activate',farm,now))return null;
    }
    return {policy:canonical(p),digest:record.digest,version:record.version,authorityRevision:record.authorityRevision,
      proposedBy:record.proposedBy,proposedAt:record.proposedAt,...(activated?{activatedBy:record.activatedBy,activatedAt:record.activatedAt,reference:record.reference}:{})};
  }
  let drafts=[];
  if(operation!=='getActive' && head){
    if(operation==='getDraft' && input.digest!==head.digest)reject();
    const draft=await checked(await repo.draft(farm,head.digest),false);
    if(draft && (!current || draft.version>current.version))drafts=[draft];
  }
  if(operation==='getDraft' && (drafts.length!==1 || input.digest!==drafts[0].digest))reject();
  const activeRecord=await checked(current,true);
  await repo.audit(farm,operation,uid,now,{kind,currency,head:identity(head),active:identity(current),authorityRevision:grant.revision});
  return {farm,kind,currency,authorityRevision:grant.revision,head:identity(head),expectedActive:identity(current),drafts,active:activeRecord};
}

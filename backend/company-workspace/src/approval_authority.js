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
    return {proposed:true};
  }
  if(input.operation==='activate'){
    if(uid===p.changedBy || !grant.activatorUids?.includes(uid) || !capability(actor,'approval.policy.activate',p.farm,now))reject();
    if(current?.digest===input.digest && current.authorityRevision===grant.revision){
      if(current.activatedBy!==uid)reject();return {reference:current.reference};
    }
    const draft=await repo.draft(p.farm,input.digest);
    if(!draft || draft.proposedBy!==p.changedBy || draft.authorityRevision!==grant.revision ||
      policyDigest(draft.policy)!==input.digest || p.version<=(current?.version??0))reject();
    const reference=JSON.stringify(canonical({farm:p.farm,kind:p.kind,currency:p.currency,digest:input.digest,
      version:p.version,authorityRevision:grant.revision,activatedBy:uid,activatedAt:now}));
    const record={policy:canonical(p),digest:input.digest,version:p.version,authorityRevision:grant.revision,
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

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {approvalAuthority,approvalRelations,policyDigest} from '../src/approval_authority.js';
const now='2026-10-30T02:00:00.000Z';
const member=(uid,permissions=[],role='auditor')=>({userId:uid,membershipId:uid,farmId:'farm',active:true,
  offlineUntil:'2026-11-30T00:00:00Z',roles:[{role,scopes:['allFarm']}],extraPermissions:permissions,extraPermissionScopes:['allFarm']});
const policy=(overrides={})=>({farm:'farm',kind:'machineRun',currency:'VND',version:1,selfEnabled:true,selfLimit:'100',
  independentLimit:'900719925474099300000.01',createPermission:'machine.log',approvePermission:'machine.verify',changedBy:'manager',...overrides});
class Repo{
  constructor(){
    this.members={manager:member('manager',['approval.policy.manage','approval.limits.manage']),
      activator:member('activator',['approval.policy.activate']),reviewer:member('reviewer',['finance.view']),admin:member('admin',[],'systemAdmin')};
    this.grant={active:true,revision:1,managerUids:['manager'],activatorUids:['activator'],partyMemberships:{vendor:[],worker:['reviewer']}};
    this.currents=new Map();this.drafts=new Map();this.heads=new Map();this.events=[];
  }
  async member(uid){return this.members[uid];}
  async authority(){return this.grant;}
  key(farm,kind,currency){return `${farm}/${kind}/${currency}`;}
  async current(...args){return this.currents.get(this.key(...args));}
  async draft(farm,digest){return this.drafts.get(`${farm}/${digest}`);}
  async draftHead(...args){return this.heads.get(this.key(...args));}
  async propose(farm,kind,currency,record){
    assert(!this.drafts.has(`${farm}/${record.digest}`));this.drafts.set(`${farm}/${record.digest}`,structuredClone(record));
    this.heads.set(this.key(farm,kind,currency),{version:record.version});
  }
  async activate(farm,kind,currency,record,before,actor,time){
    this.currents.set(this.key(farm,kind,currency),structuredClone(record));this.events.push({before,after:structuredClone(record),actor,time});
  }
}
const request=(operation,p)=>({operation,policy:p,digest:policyDigest(p)});
async function activate(repo,p=policy()){
  await approvalAuthority(repo,'manager',request('propose',p),now);
  return approvalAuthority(repo,'activator',request('activate',p),now);
}
async function verify(repo,p=policy(),overrides={}){
  const current=await repo.current(p.farm,p.kind,p.currency);
  return approvalAuthority(repo,'reviewer',{...request('verify',p),reference:current?.reference,
    activatedBy:current?.activatedBy,activatedAt:current?.activatedAt,...overrides},now);
}
test('real authenticated author must publish a server draft before independent activation',async()=>{
  const repo=new Repo(),p=policy();await assert.rejects(approvalAuthority(repo,'activator',request('activate',p),now));
  await activate(repo,p);assert.equal((await verify(repo,p)).current,true);
  assert.equal(repo.events.length,1);assert.equal(repo.events[0].actor,'activator');
  assert.equal(repo.events[0].after.policy.independentLimit,'900719925474099300000.01');
});
test('activator cannot impersonate the manager by supplying changedBy in a forged draft',async()=>{
  const repo=new Repo();await assert.rejects(approvalAuthority(repo,'activator',request('propose',policy()),now));
  assert.equal(repo.drafts.size,0);assert.equal(repo.events.length,0);
});
test('policy author cannot activate own changes even after receiving an explicit activation capability',async()=>{
  const repo=new Repo();repo.members.manager.extraPermissions.push('approval.policy.activate');repo.grant.activatorUids.push('manager');
  const p=policy();await approvalAuthority(repo,'manager',request('propose',p),now);
  await assert.rejects(approvalAuthority(repo,'manager',request('activate',p),now));
});
test('technical administrator has no implicit policy activation or authorship capability',async()=>{
  const repo=new Repo();await approvalAuthority(repo,'manager',request('propose',policy()),now);
  repo.grant.activatorUids.push('admin');await assert.rejects(approvalAuthority(repo,'admin',request('activate',policy()),now));
  await assert.rejects(approvalAuthority(repo,'admin',request('propose',policy({changedBy:'admin'})),now));
});
for(const state of ['missing','inactive','wrongRevision'])test(`authority ${state} fails closed`,async()=>{
  const repo=new Repo();repo.grant=state==='missing'?null:{...repo.grant,active:state!=='inactive',revision:state==='wrongRevision'?0:1};
  await assert.rejects(activate(repo));assert.equal(repo.events.length,0);
});
test('authority revision withdrawal invalidates an already activated reference',async()=>{
  const repo=new Repo();await activate(repo);repo.grant.revision=2;assert.equal((await verify(repo)).current,false);
});
test('revoked activator membership invalidates current authority',async()=>{
  const repo=new Repo();await activate(repo);repo.members.activator.active=false;assert.equal((await verify(repo)).current,false);
});
test('revoked manager capability cannot leave its policy current',async()=>{
  const repo=new Repo();await activate(repo);repo.members.manager.deniedPermissions=['approval.limits.manage'];
  await assert.rejects(verify(repo));
});
test('reference cannot be forged, refreshed or used to upgrade older own pending source timestamps',async()=>{
  const repo=new Repo();await activate(repo);
  assert.equal((await verify(repo,policy(),{reference:'forged'})).current,false);
  assert.equal((await verify(repo,policy(),{activatedAt:'2020-01-01T00:00:00Z'})).current,false);
  assert.equal((await verify(repo,policy(),{activatedBy:'admin'})).current,false);
});
test('modified limits cannot reuse the approval reference of another canonical digest',async()=>{
  const repo=new Repo();await activate(repo);assert.equal((await verify(repo,policy({selfLimit:'999999999999999999999'}))).current,false);
});
test('VND and LAK policies are separate server scopes',async()=>{
  const repo=new Repo();await activate(repo);assert.equal((await verify(repo,policy({currency:'LAK'}))).current,false);
  await activate(repo,policy({currency:'LAK'}));assert.equal((await verify(repo,policy({currency:'LAK'}))).current,true);
});
test('activation replay acknowledges the same immutable reference after unknown outcome',async()=>{
  const repo=new Repo(),p=policy(),first=await activate(repo,p);
  const replay=await approvalAuthority(repo,'activator',request('activate',p),'2026-10-30T03:00:00Z');
  assert.deepEqual(replay,first);assert.equal(repo.events.length,1);
});
test('reviewer may skip an unsafe superseded draft without activating it first',async()=>{
  const repo=new Repo(),one=policy(),two=policy({version:2,selfLimit:'50'});
  await approvalAuthority(repo,'manager',request('propose',one),now);
  await approvalAuthority(repo,'manager',request('propose',two),now);
  await approvalAuthority(repo,'activator',request('activate',two),now);
  assert.equal((await verify(repo,two)).current,true);
  await assert.rejects(approvalAuthority(repo,'activator',request('activate',one),now));
});
for(const override of [{selfLimit:1},{independentLimit:100},{selfLimit:'-1'},{kind:'cashPayment',selfEnabled:true},{version:1.5}])
  test(`unsafe policy ${JSON.stringify(override)} is rejected before mutation`,async()=>{
    const repo=new Repo();await assert.rejects(activate(repo,policy(override)));assert.equal(repo.events.length,0);
  });
test('cross-farm, inactive session and forged membership identity are denied',async()=>{
  for(const change of [{farmId:'other'},{active:false},{userId:'someone-else'}]){
    const repo=new Repo();Object.assign(repo.members.manager,change);await assert.rejects(activate(repo));
  }
});
test('verified beneficiary relation distinguishes an external party from an unresolved mapping',async()=>{
  const repo=new Repo();assert.deepEqual(await approvalRelations(repo,'reviewer',{farm:'farm',partyId:'vendor'},now),{verified:true,users:[]});
  assert.deepEqual(await approvalRelations(repo,'reviewer',{farm:'farm',partyId:'worker'},now),{verified:true,users:['reviewer']});
  assert.deepEqual(await approvalRelations(repo,'reviewer',{farm:'farm',partyId:'unknown'},now),{verified:false});
  repo.grant.active=false;assert.deepEqual(await approvalRelations(repo,'reviewer',{farm:'farm',partyId:'worker'},now),{verified:false});
});

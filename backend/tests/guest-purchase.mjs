import assert from 'node:assert/strict';
import { verifyMembership } from '../supabase/functions/_shared/membership-verification.ts';
import { productID, bundleID } from '../supabase/functions/_shared/policy.ts';
const a='11111111-1111-1111-1111-111111111111', b='22222222-2222-2222-2222-222222222222';
const now=1000000;
const base={bundleId:bundleID,productId:productID,type:'Auto-Renewable Subscription',environment:'Production',inAppOwnershipType:'PURCHASED',originalTransactionId:'123',transactionId:'124',expiresDate:now+10000};
let n=0;
function fixtures(tx=base,status=1) {
 const rows=new Map();
 const db={from(){return {
  select(){return {eq(key,value){return {async maybeSingle(){return {data:[...rows.values()].find(row=>row[key]===value)??null,error:null}}}}}},
  async upsert(row){
   if([...rows.values()].some(old=>old.original_transaction_id===row.original_transaction_id&&old.user_id!==row.user_id))return {error: new Error('unique ownership')};
   rows.set(row.user_id,row);return {error:null};
  }
 }}};
 const source={environment:'Production',verifier:{async verifyAndDecodeTransaction(jws){if(jws!=='signed-proof')throw new Error('Invalid signature');return tx}},api:{async getAllSubscriptionStatuses(){return {data:[{lastTransactions:[{status,signedTransactionInfo:'signed-proof'}]}]}}}};
 return {rows,db,source};
}
const verify=(f,user=a,proof='signed-proof',id='124')=>verifyMembership(f.db,f.source,user,id,proof,now);
{const f=fixtures();await assert.rejects(()=>verifyMembership(f.db,f.source,a,'124',undefined,now));assert.equal(f.rows.size,0);n++;}
{const f=fixtures();assert.equal((await verify(f)).active,true);assert.equal(f.rows.get(a).original_transaction_id,'123');n++;
 assert.equal((await verifyMembership(f.db,f.source,a,'123',undefined,now)).active,true);n++;
 await assert.rejects(()=>verify(f,b));assert.equal(f.rows.get(a).user_id,a);assert.equal(f.rows.has(b),false);n++;}
{const f=fixtures();await assert.rejects(()=>verify(f,a,'forged'));assert.equal(f.rows.size,0);n++;}
{const f=fixtures();await assert.rejects(()=>verify(f,a,'signed-proof','999'));n++;}
{const f=fixtures({...base,appAccountToken:b});await assert.rejects(()=>verify(f));assert.equal(f.rows.size,0);n++;}
{const f=fixtures({...base,appAccountToken:a});assert.equal((await verify(f)).active,true);n++;}
for(const change of [{bundleId:'fake'},{productId:'fake'},{environment:'Sandbox'},{inAppOwnershipType:'FAMILY_SHARED'}]){const f=fixtures({...base,...change});await assert.rejects(()=>verify(f));assert.equal(f.rows.size,0);n++;}
for(const [tx,status] of [[{...base,revocationDate:now-1},1],[{...base,expiresDate:now-1},2],[base,5]]){const f=fixtures(tx,status);assert.equal((await verify(f)).active,false);n++;}
{const f=fixtures();const results=await Promise.allSettled([verify(f,a),verify(f,b)]);assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(f.rows.size,1);n++;}
console.log(`${n} guest purchase proof, binding, refund and race checks passed`);

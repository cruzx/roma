import assert from 'node:assert/strict';
import { entitlement,productID,bundleID } from '../supabase/functions/_shared/policy.ts';
const now=1000000,user='11111111-1111-1111-1111-111111111111';
const t={bundleId:bundleID,productId:productID,type:'Auto-Renewable Subscription',environment:'Production',appAccountToken:user,inAppOwnershipType:'PURCHASED',originalTransactionId:'123',expiresDate:now+1000};
let n=0;
const run=(tx=t,renewal=null,status=1,env='Production')=>entitlement(tx,renewal,status,user,env,now);
assert.equal(run().active,true);n++;
for(const status of [2,3,5]){assert.equal(run(t,null,status).active,false);n++;}
assert.equal(run({...t,revocationDate:now-1}).active,false);n++;
assert.equal(run({...t,expiresDate:now}).active,false);n++;
assert.equal(run(t,{gracePeriodExpiresDate:now+2000},4).validUntil,now+2000);n++;
assert.equal(run(t,null,4).active,false);n++;
for(const change of [{appAccountToken:'other'},{productId:'fake'},{bundleId:'other'},{environment:'Sandbox'},{inAppOwnershipType:'FAMILY_SHARED'},{type:'Non-Consumable'},{originalTransactionId:undefined}]){assert.throws(()=>run({...t,...change}));n++;}
console.log(`${n} Apple entitlement policy checks passed`);
// Signed-out purchases have no appAccountToken. Only a verified original-ID proof
// or a server-owned binding may authorize them; IDs and unrelated tokens cannot.
const guest={...t,appAccountToken:undefined};
assert.throws(()=>run(guest));
assert.equal(entitlement(guest,null,1,user,'Production',now,'123').active,true);
assert.throws(()=>entitlement(guest,null,1,user,'Production',now,'456'));
assert.throws(()=>entitlement({...t,appAccountToken:'other'},null,1,user,'Production',now,'123'));
assert.equal(entitlement({...guest,revocationDate:now-1},null,1,user,'Production',now,'123').active,false);
assert.equal(entitlement({...guest,expiresDate:now-1},null,1,user,'Production',now,'123').active,false);
console.log('6 tokenless purchase ownership and expiry checks passed');

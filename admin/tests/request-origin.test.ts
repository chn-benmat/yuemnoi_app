import {test} from 'node:test';
import assert from 'node:assert/strict';
import {isSameOrigin,resolveRequestOrigin} from '../src/lib/request-origin.ts';

const request=(host:string,origin?:string,forwarded?:string)=>new Request('http://localhost:3000/api/activate',{
  method:'POST',headers:{host,...(origin?{origin}:{}),...(forwarded?{'x-forwarded-host':forwarded}:{})},
});

test('uses the incoming loopback Host when Next normalizes its URL to localhost',()=>{
  for(const host of ['127.0.0.1:3000','localhost:3000','[::1]:3000']){
    assert.equal(isSameOrigin(request(host,`http://${host}`)),true);
  }
  assert.equal(isSameOrigin(request('127.0.0.1:3000','http://localhost:3000')),false);
});

test('rejects foreign, missing, malformed and mismatched origins',()=>{
  for(const origin of [undefined,'null','https://attacker.example','http://127.0.0.1:3001','https://127.0.0.1:3000','http://127.0.0.1:3000/path']){
    assert.equal(isSameOrigin(request('127.0.0.1:3000',origin)),false);
  }
  for(const host of ['bad.test/path','bad.test@localhost:3000','bad.test?x','bad.test\\localhost']){
    assert.equal(resolveRequestOrigin(request(host)),null);
  }
  assert.equal(isSameOrigin(request('127.0.0.1:3000','https://attacker.example','attacker.example')),false);
});

test('uses only the configured public origin behind a proxy',()=>{
  const publicOrigin='https://admin.example.com';
  assert.equal(isSameOrigin(request('internal:3000',publicOrigin),publicOrigin),true);
  assert.equal(resolveRequestOrigin(request('internal:3000',publicOrigin),publicOrigin),publicOrigin);
  assert.equal(isSameOrigin(request('internal:3000','http://internal:3000'),publicOrigin),false);
  for(const invalid of ['file:///tmp/admin','https://admin.example.com/path','https://user:pass@admin.example.com']){
    assert.equal(isSameOrigin(request('internal:3000',publicOrigin),invalid),false);
  }
});

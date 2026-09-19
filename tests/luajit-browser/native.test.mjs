import test from 'node:test';
import assert from 'node:assert/strict';
import {validateNativeLibrary,nativeInitialization} from '../../runtime/luajit/native.mjs';
function elf(size=256) {
  const bytes=Uint8Array.from({length:size},(_,i)=>i&255), view=new DataView(bytes.buffer);
  view.setUint32(0,0x7f454c46,false);bytes[4]=1;bytes[5]=1;
  view.setUint16(16,3,true);view.setUint16(18,3,true);return bytes;
}
test('guest native libraries reject host architecture, traversal and oversized payloads',()=>{
  validateNativeLibrary('libapp.so',elf());
  for(const name of ['../libapp.so','/libapp.so','bad".so','lib.dll']) assert.throws(()=>validateNativeLibrary(name,elf()));
  const x64=elf();x64[4]=2;assert.throws(()=>validateNativeLibrary('libapp.so',x64),/i386/);
  const arm=elf();arm[18]=40;assert.throws(()=>validateNativeLibrary('libapp.so',arm),/i386/);
  assert.throws(()=>validateNativeLibrary('libapp.so',elf(1024*1024+1)),/one MiB/);
});
test('native initialization preserves every byte and rejects duplicates and aggregate overflow',async()=>{
  const bytes=elf(), entries=[{file:'native/libapp.so',name:'libapp.so'}];
  const text=new TextDecoder().decode(await nativeInitialization(entries,async()=>bytes));
  const encoded=[...text.matchAll(/\\(\d{3})/g)].map(x=>Number(x[1]));
  assert.deepEqual(encoded,[...bytes]);
  await assert.rejects(nativeInitialization([...entries,...entries],async()=>bytes),/Duplicate/);
  await assert.rejects(nativeInitialization([...entries,{file:'b',name:'b.so'}],async()=>elf(600000)),/total/);
  await assert.rejects(nativeInitialization(entries,async()=>{throw new Error('SHA-256 mismatch');}),/SHA-256/);
});

import {chromium} from 'playwright';
import {createServer} from 'node:http';
import {readFileSync,writeFileSync} from 'node:fs';
import path from 'node:path';
import {gzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
const [directory,output]=process.argv.slice(2), root=path.resolve(directory);
const cache=new Map(), queue=[];
let transferred=0;
// One shared token budget models 10 Mbps across every concurrent response.
const tick=setInterval(()=>{
 let budget=12500;
 while(queue.length && budget>0) {
  const job=queue.shift();
  if(job.response.destroyed)continue;
  const end=Math.min(job.offset+budget,job.bytes.length),part=job.bytes.subarray(job.offset,end);
  job.response.write(part);transferred+=part.length;budget-=part.length;job.offset=end;
  if(end===job.bytes.length)job.response.end();else queue.push(job);
 }
},10);
const types={'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.json':'application/json','.wasm':'application/wasm'};
const server=createServer((request,response)=>{
 try {
  const pathname=new URL(request.url,'http://localhost').pathname;
  const file=path.resolve(root,'.'+decodeURIComponent(pathname==='/'?'/index.html':pathname));
  if(!file.startsWith(root+path.sep))throw new Error('Invalid path');
  let asset=cache.get(file);
  if(!asset) {
   let bytes=readFileSync(file),encoded=/\.(?:html|css|js|mjs|json|svg)$/.test(file);
   if(encoded)bytes=gzipSync(bytes,{level:9});
   asset={bytes,encoded,etag:'"'+createHash('sha256').update(bytes).digest('hex')+'"'};cache.set(file,asset);
  }
  response.setHeader('Content-Type',types[path.extname(file)]||'application/octet-stream');
  response.setHeader('Cache-Control',file.endsWith('.html')?'no-cache':'public,max-age=31536000,immutable');
  response.setHeader('ETag',asset.etag);
  if(request.headers['if-none-match']===asset.etag){response.writeHead(304);response.end();return;}
  if(asset.encoded)response.setHeader('Content-Encoding','gzip');
  response.setHeader('Content-Length',asset.bytes.length);
  setTimeout(()=>queue.push({response,bytes:asset.bytes,offset:0}),25);
 } catch{response.writeHead(404);response.end('Not found');}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await chromium.launch({headless:true,channel:'chrome'}), results=[];
try {
 const context=await browser.newContext();
 for(const mode of ['cold','cached']) {
  const page=await context.newPage(),errors=[];
  page.on('pageerror',e=>errors.push(String(e)));
  const bytesBefore=transferred,begin=performance.now();
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  await page.waitForFunction(()=>document.querySelector('#status')?.textContent.includes('checked'),null,{timeout:60000});
  const checkedMs=performance.now()-begin,compilerBytes=transferred-bytesBefore;
  await page.locator('#compile-button').click();
  await page.waitForFunction(()=>document.querySelector('#output-summary')?.textContent==='ran',null,{timeout:30000});
  const firstOutputMs=performance.now()-begin;
  const row={mode,checkedMs,compilerBytes,firstOutputMs,assetBodyBytes:transferred-bytesBefore,errors};results.push(row);
  writeFileSync(output,JSON.stringify({scope:'Actual playground tour; shared 10 Mbps response budget, 25 ms response delay; gzip text delivery; cached run opens a fresh page in the same browser context',results},null,2)+'\n');
  if(errors.length)throw new Error(errors.join('\n'));
  await page.close();
 }
 await context.close();
} finally{await browser.close();clearInterval(tick);server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}

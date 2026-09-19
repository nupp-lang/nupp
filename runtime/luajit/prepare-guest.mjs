import {execFileSync,execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {readFileSync,writeFileSync,mkdirSync,cpSync,copyFileSync,existsSync,createReadStream} from 'node:fs';
import {stat} from 'node:fs/promises';
import {createServer} from 'node:http';
import path from 'node:path';
// Source artifacts stay immutable in the toolchain cache. Snapshots are derived
// into the build directory and are reproducible from that guest's identity.
export async function prepareGuest(repo, supplied) {
  const source = supplied || process.env.NUPP_BROWSER_GUEST_DIR || execFileSync(path.join(repo,'scripts/toolchain'),['browser-guest'],{encoding:'utf8',stdio:['ignore','pipe','inherit']}).trim();
  const input = JSON.parse(readFileSync(path.join(source,'guest-manifest.json'),'utf8'));
  if (input.snapshots?.runner && input.snapshots?.compiler) return source;
  const destination = path.join(repo,'build/browser-delivery',input.buildKey);
  const manifestFile = path.join(destination,'guest-manifest.json');
  if (!existsSync(manifestFile)) {mkdirSync(destination,{recursive:true}); cpSync(source,destination,{recursive:true});}
  const manifest = JSON.parse(readFileSync(manifestFile,'utf8'));
  if (manifest.buildKey !== input.buildKey) throw new Error('Snapshot cache belongs to another guest');
  if (manifest.snapshots?.runner && manifest.snapshots?.compiler) return destination;
  for (const name of ['snapshot.html','snapshot.mjs']) copyFileSync(path.join(repo,'tests/luajit-browser',name),path.join(destination,name));
  const server = createServer(async (request,response) => {
    try {
      const url = new URL(request.url,'http://localhost');
      const file = path.resolve(destination,'.'+decodeURIComponent(url.pathname));
      if (!file.startsWith(destination+path.sep) || !(await stat(file)).isFile()) throw new Error('Not found');
      response.setHeader('Content-Type',file.endsWith('.mjs')?'text/javascript':file.endsWith('.html')?'text/html':'application/octet-stream');
      createReadStream(file).pipe(response);
    } catch {response.writeHead(404);response.end('Not found');}
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  try {
    const {stdout,stderr}=await promisify(execFile)(process.execPath,[path.join(repo,'scripts/browser-snapshot.mjs'),destination,`http://127.0.0.1:${server.address().port}/`],{cwd:repo,maxBuffer:4*1024*1024});
    if(stderr)process.stderr.write(stderr);
  } finally {await new Promise(resolve=>server.close(resolve));}
  return destination;
}

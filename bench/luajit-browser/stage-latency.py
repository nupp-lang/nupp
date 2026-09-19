"""Prepare a latency measurement from the preserved spike's verified assets.

This is a measurement harness, not the production artifact builder. The source
checkout is read-only. Its revision and hashes are written beside each result.
"""
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
spike = Path(sys.argv[1]).resolve()
web = root / 'build/luajit-browser/latency'
shutil.copytree(spike / 'build/v86-spike/performance/web', web, dirs_exist_ok=True)
for name in ['latency.lua', 'latency.mjs', 'latency-portable.mjs', 'cancellation.mjs']:
    shutil.copyfile(Path(__file__).with_name(name), web / name)
(web / 'latency.html').write_text('<!doctype html><title>Compiler request latency</title>'
    '<pre id="terminal"></pre><pre id="result" data-status="running"></pre>'
    '<script type="module" src="latency.mjs"></script>')
(web / 'cancellation.html').write_text((web / 'latency.html').read_text().replace('latency.mjs', 'cancellation.mjs'))
if '--native' in sys.argv:
    bundle = root / 'build/browser-luajit/nupp-compiler.lua'
    bytecode = web.parent / 'native-compiler.ljbc'
    luajit = Path(subprocess.check_output([str(root / 'scripts/toolchain'), 'luajit'], text=True).strip()) / 'bin/luajit'
    subprocess.run([str(luajit), '-', str(bundle), str(bytecode)], check=True, text=True,
        input='local f=assert(loadfile(arg[1],"tW"));local o=assert(io.open(arg[2],"wb"));o:write(string.dump(f,"sd"));o:close()')
    archive = bytearray()
    for index, (name, data) in enumerate([('nupp/native-compiler.ljbc',bytecode.read_bytes()), ('TRAILER!!!',b'')],1):
        filename=name.encode()+b'\0'
        fields=[index,0o100644,0,0,1,0,len(data),0,0,0,0,len(filename),0]
        archive += b'070701'+''.join(f'{n:08x}' for n in fields).encode()+filename
        archive += bytes(-len(archive)%4)
        archive += data
        archive += bytes(-len(archive)%4)
    initrd = web / 'initramfs.gz'
    initrd.write_bytes(initrd.read_bytes()+gzip.compress(archive,mtime=0))
worker = web / 'vm-worker.mjs'
worker.write_text(worker.read_text().replace("const line = partial; partial = '';", """const line = partial; partial = '';
    if (message.config.timingProbe && line.startsWith('@@NUPP_PHASE@@ ')) {
      const [,sequence,phase] = line.split(' ');
      self.postMessage({type:'phase', sequence:Number(sequence), phase, workerMs:performance.now()});
      return;
    }"""))
host = web / 'guest-runtime.mjs'
host.write_text(host.read_text().replace("if (message.type === 'log')", "if (message.type === 'phase') { onProgress(message); return; }\n      if (message.type === 'log')"))
# Experimental compiler control lane: one JSON envelope, raw source bytes,
# the existing fixed-capacity mailbox, and one retained session.
worker.write_text(worker.read_text().replace("const line = partial; partial = '';", """const line = partial; partial = '';
    if (message.config.compilerTransport && line.startsWith('@@NUPP_COMPILER_FRAME@@ ')) {
      const sequence = Number(line.split(' ')[1]);
      self.postMessage({type:'compiler-result', sequence,
        result:JSON.parse(jsonDecoder.decode(mailboxRead(4096,0,1024*1024)))});
      return;
    }"""))
worker.write_text(worker.read_text().replace("self.addEventListener('message',", """self.addEventListener('message', event => {
  const message = event.data;
  if (message.type !== 'compiler-input') return;
  try {
    mailboxWrite(4*1024*1024,2,1024*1024,encoder.encode(JSON.stringify(message.request)));
    mailboxWrite(5*1024*1024,3,2*1024*1024,new Uint8Array(message.payload));
    send(String(message.sequence)+'\\n');
  } catch (error) { fail(error); }
});
self.addEventListener('message',"""))
host.write_text(host.read_text().replace("if (message.type !== 'effect') return;", """if (message.type === 'compiler-result') {
        const request = await effectHandlers['compiler-request']({result:message.result});
        if (settled) return;
        const payloadField = typeof request.source === 'string' ? 'source' : 'padding';
        const payload = encoder.encode(request[payloadField] || '');
        if (payload.length > 2*1024*1024) throw new Error('Compiler payload exceeds mailbox');
        const header = {...request, payloadField};
        delete header[payloadField];
        worker.postMessage({type:'compiler-input', sequence:message.sequence, request:header,
          payload:payload.buffer}, [payload.buffer]);
        return;
      }
      if (message.type !== 'effect') return;"""))
provenance = {'spikeRevision': subprocess.check_output(['git', '-C', str(spike), 'rev-parse', 'HEAD'], text=True).strip(),
    'measurementRevision': subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(),
    'files': {str(p.relative_to(web)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(web.rglob('*')) if p.is_file()}}
(web / 'latency-provenance.json').write_text(json.dumps(provenance, indent=2)+'\n')
print(web)

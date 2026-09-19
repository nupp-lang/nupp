import {runNuppLuaJITApp} from '../../runtime/luajit/app-runtime.mjs';
import {createCompiler} from '../../runtime/luajit/host.mjs';
const output = document.querySelector('#result');
const terminal = document.querySelector('#terminal');
const bytes = async name => new Uint8Array(await (await fetch(name)).arrayBuffer());
let compiler;
try {
  compiler = await createCompiler({manifestUrl: './guest-manifest.json', app: await bytes('./compiler.ljbc'), deadlineMs:120000});
  const initialize = await bytes('./app-runtime.lua');
  const sources = await (await fetch('./application-sources.json')).json();
  const results = [];
  for (const [name, source] of Object.entries(sources)) {
    terminal.textContent = name;
    const compiled = await compiler.request({kind:'compile', source, filename:'playground.nupp', options:{strict:true, optimize:true}});
    if (!compiled.code || compiled.diagnostics.some(x => x.severity === 'error')) throw new Error(name + ': ' + JSON.stringify(compiled));
    const result = await runNuppLuaJITApp({manifestUrl:'./guest-manifest.json', app:new TextEncoder().encode(compiled.code), initialize, managed:true,
      storageName:'nupp-luajit-integration', limits:{deadlineMs:15000}, onProgress: x => {if(x.log) terminal.textContent = name+'\n'+x.log;}});
    results.push({name, ...result});
  }
  output.textContent = JSON.stringify({ok:true, results}); output.dataset.status='passed';
} catch(error) {output.textContent=JSON.stringify({ok:false,error:String(error.stack||error)});output.dataset.status='failed';}
finally { compiler?.close(); }

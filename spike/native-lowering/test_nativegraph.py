#!/usr/bin/env python3
"""Trusted residual MIR prototype proof; no production loader or E0 adoption."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler-runtime', type=Path, required=True)
    p.add_argument('--compiler-image', type=Path, required=True)
    p.add_argument('--runtime', type=Path, required=True)
    p.add_argument('--raw-runtime', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--full-runtime-layouts', type=Path)
    args = p.parse_args()
    root = Path(__file__).resolve().parents[2]
    out = args.output.resolve(); out.mkdir(parents=True, exist_ok=False)
    project = out/'project'; reference = project/'src/nupp/compiler/s0/referenceclif.nupp'
    reference.parent.mkdir(parents=True)
    original = subprocess.check_output(['git', 'show', '950085466:src/nupp/compiler/clif/graph.nupp'], cwd=root).decode()
    reference.write_text(original.replace('module nupp.compiler.clif.graph', 'module nupp.compiler.s0.referenceclif', 1))
    (project/'nupp.lua').write_text('return {include = {' + ','.join(json.dumps(str(x)) for x in [root/'src', root/'spike/native-lowering/src', root/'spike/native-lowering/nativegraph/src', root/'spike/native-lowering/nativegraph/tests', project/'src']) + '}}\n')
    env = {k:v for k,v in os.environ.items() if not k.startswith(('NUPP_', 'JIT_', 'GC_')) and k not in ['NO_AOT', 'NO_JIT', 'BUILTIN_STATS', 'TRACE_CALLS', 'TRACE_OPS']}
    env.update(NO_JIT='1', NUPP_COMPILER_ROOT=str(root), NUPP_VM_AUTO_REBUILD='0', RUSTC_WRAPPER='/usr/bin/env')
    receipt = {'scope': __doc__, 'status':'running', 'artifacts':{str(x.resolve()):sha(x) for x in [args.compiler_runtime,args.compiler_image,args.runtime,args.raw_runtime]}, 'referenceClifSourceSha256':hashlib.sha256(original.encode()).hexdigest(), 'sourceFiles':{str(p.relative_to(root)):sha(p) for p in sorted((root/'spike/native-lowering/nativegraph').rglob('*')) if p.is_file() and 'build' not in p.relative_to(root/'spike/native-lowering/nativegraph').parts}, 'steps':[], 'native':[]}
    def save(): (out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    def run(name, command, foreign=False, extra=None):
        settings = dict(env, **({'NO_AOT':'1'} if foreign else {}), **(extra or {}))
        with (out/(name+'.out')).open('w') as stdout, (out/(name+'.err')).open('w') as stderr:
            child = subprocess.run(list(map(str,command)),cwd=root,env=settings,stdout=stdout,stderr=stderr,timeout=600)
        receipt['steps'].append({'name':name,'argv':list(map(str,command)),'returnCode':child.returncode});save()
        if child.returncode: raise RuntimeError(name+' failed')
    image = out/'tests.image'
    run('emit',[args.compiler_runtime,'run',args.compiler_image,'nupp.tools.vm.project','emit',project,'nupp.compiler.s0.nativegraphtests','','--output',image])
    receipt['artifacts'][str(image)] = sha(image)
    run('structural',[args.runtime,'run',image,'nupp.compiler.s0.nativegraphtests','cases'],True)
    mask = (1<<64)-1
    cases = []; rows = []
    def add(name, steps, initial):
        expected=initial.copy()
        for op,a,b,c,imm in steps:
            value={'IK':lambda:imm,'IMov':lambda:expected[b],'IAddK':lambda:expected[b]+imm,'IMaskU32':lambda:expected[b]&0xffffffff,'IAdd':lambda:expected[b]+expected[c],'ISub':lambda:expected[b]-expected[c],'IAnd':lambda:expected[b]&expected[c],'IOr':lambda:expected[b]|expected[c]}[op]() & mask
            expected[a]=value
            rows.append(f'{name} {op} {a} {b} {c} {imm:016x}\n')
        cases.append({'name':name,'steps':steps,'initial':initial,'expected':expected})
        for mode in ['normal','spill']: (out/name/mode).mkdir(parents=True)
    ops=['IK','IMov','IAddK','IMaskU32','IAdd','ISub','IAnd','IOr']
    vectors=[(0,1,0),(mask,1,1),(1<<63,mask,1<<63),(0x123456789abcdef0,0xfedcba9876543210,mask)]
    for op in ops:
        for alias,(a,b,c) in enumerate([(0,1,2),(1,1,2),(2,1,2),(1,1,1)]):
            for v,(x,y,imm) in enumerate(vectors): add(f'{op}_{alias}_{v}',[(op,a,b,c,imm)],[0xdeadbeef,x,y,0xcafebabe])
    for count in [1,64]:
        for v,(x,y,imm) in enumerate(vectors): add(f'stitch{count}_{v}',[(ops[i%8],1,1,2,imm) for i in range(count)],[0xdeadbeef,x,y,0xcafebabe])
    (out/'cases.tsv').write_text(''.join(rows)); (out/'cases.json').write_text(json.dumps(cases,indent=2)+'\n')
    layout=subprocess.check_output([str(args.raw_runtime),'native','raw-layout'],text=True).strip()
    run('bundles',[args.runtime,'run',image,'nupp.compiler.s0.nativegraphtests','native',out,layout],True)
    for case in cases:
        directory=out/case['name']; body=(directory/'body.bin').read_bytes()
        assert len(body)==16*(len(case['steps'])+1) and body[-16:]==bytes(16)
        inputs=directory/'input.bin'; inputs.write_bytes(struct.pack('<4Q',*case['initial'])+body)
        expected=[0]+case['expected']+[256+16*len(case['steps']),128,0,192,224,2048]
        for mode in ['normal','spill']:
            output=directory/mode/'output.bin'
            child=subprocess.run([str(args.raw_runtime),'native','raw',str(directory/mode/'bundle.json'),str(inputs),str(output)],env=dict(env,NO_AOT='1'),capture_output=True,timeout=15)
            (directory/mode/'run.out').write_bytes(child.stdout); (directory/mode/'run.err').write_bytes(child.stderr)
            actual=list(struct.unpack('<11Q',output.read_bytes())) if child.returncode==0 else None
            receipt['native'].append({'name':case['name'],'mode':mode,'codeSha256':sha(directory/mode/'code.bin'),'bodySha256':sha(directory/'body.bin'),'returnCode':child.returncode,'actual':actual,'expected':expected});save()
            if actual!=expected: raise RuntimeError('native mismatch: '+case['name']+'/'+mode)
    if args.full_runtime_layouts:
        receipt['artifacts'][str(args.full_runtime_layouts.resolve())] = sha(args.full_runtime_layouts)
        full = out/'full-core'; full.mkdir()
        full_image = full/'tests.image'
        run('emit-full',[args.compiler_runtime,'run',args.compiler_image,'nupp.tools.vm.project','emit',project,'nupp.compiler.s0.nativegraphfull','','--output',full_image])
        run('full-core',[args.runtime,'run',full_image,'nupp.compiler.s0.nativegraphfull','run',root,args.full_runtime_layouts.resolve(),full],True)
        assert (full/'current.clif').read_bytes() == (full/'baseline.clif').read_bytes()
        receipt['fullRuntimeClifSha256'] = sha(full/'current.clif')
    assert all(sha(path)==digest for path,digest in receipt['artifacts'].items())
    receipt.update(status='passed',nativeExecutions=len(receipt['native']),caseVectors=len(cases));save()
    print(receipt['nativeExecutions'],'native dispatch executions passed')


if __name__=='__main__': main()

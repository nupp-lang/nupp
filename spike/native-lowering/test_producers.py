#!/usr/bin/env python3
"""Check bounded producer folds, physical transport, constants, and fallbacks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess

MASK = (1 << 64) - 1


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate(directory):
    cases, functions = [], []

    def add(name, body, width, inputs, results, producer, folded, pattern=0, mask=0xff000000, constant=-1, slots=''):
        params = ', '.join('i' + str(width) for _ in inputs[0])
        block = ', '.join(f'v{i}: i{width}' for i in range(len(inputs[0])))
        source = f'function %{name}({params}) -> i{width} tail {{\n{slots}block0({block}):\n{body}\n}}\n'
        (directory / (name + '.clif')).write_text(source)
        functions.append(f'{name} {producer} {int(folded)} {hex(mask if pattern else 0)} {hex(pattern)} {constant}\n')
        for args, result in zip(inputs, results):
            cases.append(dict(name=name, inputWords=[x & MASK for x in args], expectedWord=result & ((1 << width) - 1)))
        for mode in ('normal', 'spill'):
            (directory / mode / name).mkdir(parents=True)

    for width in (32, 64):
        mask = (1 << width) - 1
        values = [0, 1, (1 << (width - 1))-1, 1 << (width - 1), mask, 0x12345678]
        triples = [(x, values[(i+2) % len(values)], values[(i+4) % len(values)]) for i,x in enumerate(values)]
        for op in ('iadd', 'isub'):
            for left in (False, True):
                for variant in ('single', 'multi', 'gap', 'edge'):
                    args = 'v3, v2' if left else 'v2, v3'
                    gap = '    v8 = bxor v0, v2\n' if variant == 'gap' else ''
                    body = f'    v3 = imul v0, v1\n{gap}    v4 = {op} {args}\n'
                    if variant == 'multi': body += '    v5 = bxor v4, v3\n    return v5'
                    elif variant == 'gap': body += '    v5 = bxor v4, v8\n    return v5'
                    elif variant == 'edge': body += f'    jump block1(v4, v3)\nblock1(v6: i{width}, v7: i{width}):\n    v9 = bxor v6, v7\n    return v9'
                    else: body += '    return v4'
                    expected=[]
                    for x,y,z in triples:
                        product=x*y & mask
                        v=(product+z if op=='iadd' else product-z if left else z-product)&mask
                        expected.append(v ^ product if variant in ('multi','edge') else v ^ (x^z) if variant=='gap' else v)
                    folded=variant=='single' and (op=='iadd' or not left)
                    add(f'mul{width}{op}{int(left)}{variant}',body,width,triples,expected,5,folded,
                        ((0x9b008000 if op=='isub' else 0x9b000000) if width==64 else (0x1b008000 if op=='isub' else 0x1b000000)) if folded else 0,0xffe08000)
                for shift in (0, 1, 7, width-1, width, width+1):
                    args='v3, v1' if left else 'v1, v3'
                    body=f'    v2 = iconst.i{width} {shift}\n    v3 = ishl v0, v2\n    v4 = {op} {args}\n    return v4'
                    inputs=[(x,y) for x,y,_ in triples]
                    expected=[((x << (shift % width)) + y if op=='iadd' else (x << (shift % width))-y if left else y-(x << (shift % width))) & mask for x,y in inputs]
                    folded=op=='iadd' or not left
                    code=(0x8b000000 if op=='iadd' else 0xcb000000) if width==64 else (0x0b000000 if op=='iadd' else 0x4b000000)
                    add(f'shift{width}{op}{int(left)}s{shift}',body,width,inputs,expected,16,folded,
                        code | ((shift % width)<<10) if folded else 0,0xffc0fc00)
        for shift in (0, 1, 7, width-1):
            for length in (1, 8, width-1):
                for variant in ('gap','adjacent','multi','maskmulti','wrongmask'):
                    low=(1<<length)-1 if variant!='wrongmask' else 0x55555555
                    const=f'    v2 = iconst.i{width} {hex(low)}\n'
                    body=f'    v1 = iconst.i{width} {shift}\n'
                    if variant=='adjacent': body+=const
                    body+='    v3 = ushr v0, v1\n'
                    if variant!='adjacent':body+=const
                    body+='    v4 = band v3, v2\n'
                    body+=('    v5 = bxor v4, v3\n    return v5' if variant=='multi' else '    v5 = bxor v4, v2\n    return v5' if variant=='maskmulti' else '    return v4')
                    folded=variant not in ('multi','maskmulti','wrongmask') and length+shift<=width
                    results=[((x>>shift)&low)^((x>>shift) if variant=='multi' else low if variant=='maskmulti' else 0) for x in values]
                    instruction=(0xd3400000 if width==64 else 0x53000000)|(shift<<16)|((length+shift-1)<<10)
                    add(f'extract{width}s{shift}l{length}{variant}',body,width,[(x,) for x in values],results,17,folded,
                        instruction if folded else 0,0xfffffc00)
        for index,literal in enumerate((0,1,0xffff,0xffff0000,0x00ff00ff,0x55555555,0x12345678,0xffff0000ffff0000,0x5555555555555555,0x0000ffffffffffff,0x8000000000000001)):
            value=literal&mask
            halves=[(value>>(n*16))&0xffff for n in range(width//16)]
            base=max(1,min(sum(x!=0 for x in halves),sum(x!=0xffff for x in halves)))
            # These explicit masks are one logical immediate; other literals retain MOVZ/MOVN choices.
            expected=1 if value in (0x00ff00ff,0x55555555,0xffff0000ffff0000,0x5555555555555555,0x0000ffffffffffff,0x8000000000000001) else base
            if width==64 and value in (0x55555555,0x00ff00ff): expected=base
            add(f'constant{width}k{index}',f'    v1 = iconst.i{width} {hex(value)}\n    return v1',width,[(0,)], [value],0,False,constant=expected)

    for width in (8,16):
        mask=(1<<width)-1
        values=[(0,1,3),(mask,mask,mask),(1<<(width-1),3,7)]
        for op,producer in (('imul',5),('ishl',16)):
            for subtract in (False,True):
                body=f'    v3 = {op} v0, v1\n    v4 = {"isub" if subtract else "iadd"} v2, v3\n    return v4'
                result=[(z-(x*y if op=='imul' else x<<(y%(width))) if subtract else z+(x*y if op=='imul' else x<<(y%width)))&mask for x,y,z in values]
                add(f'narrow{width}{op}{int(subtract)}',body,width,values,result,producer,False)
    # Keep thirty values live across the fold: this exercises borrowed scratch
    # alongside allocator-selected registers, independently of the spill mode.
    live=''.join(f'    v{10+i} = iadd v0, v1\n' for i in range(30))
    tail=''.join(f'    v{51+i} = bxor v{50+i}, v{10+i}\n' for i in range(30))+'    return v80'
    for op,producer,operation in (('imul',5,'    v3 = imul v0, v1\n'),('ishl',16,'    v4 = iconst.i64 7\n    v3 = ishl v0, v4\n')):
        body=live+operation+'    v50 = iadd v2, v3\n'+tail
        values=[(1,2,3),(MASK,5,1),(1<<63,7,MASK)]
        expected=[((x*y if op=='imul' else x<<7)+z)&MASK for x,y,z in values]
        add(f'pressure{op}',body,64,values,expected,producer,True)

    for load in ('load.i64', 'sload32.i64', 'uload8.i64'):
        size=8 if load=='load.i64' else 4 if load=='sload32.i64' else 1
        for index,(offset,tail) in enumerate(((0,0),(8,0),(4095*size,0),(4096*size,0),(-8,16),(8,-16),(1,0),(8,8))):
            address=offset+tail
            folded=address>=0 and address%size==0 and address//size<4096 and abs(offset)<=16773120 and (abs(offset)<4096 or offset%4096==0)
            for store in (False,True):
                access=f'{tail:+}'
                prefix=f'    v1 = stack_addr.i64 ss0+32\n    v2 = iconst.i64 {offset}\n    v7 = isub v1, v2\n'
                if store:
                    body=prefix+f'    v3 = iadd v7, v2\n    istore{size*8} v0, v3{access}\n    v4 = {load} v1{access}\n    return v4'
                else:
                    body=prefix+f'    istore{size*8} v0, v1{access}\n    v3 = iadd v2, v7\n    v4 = {load} v3{access}\n    return v4'
                inputs=[(0,),(0x7fffffff,),(0x80000000,),(MASK,)]
                results=[x&((1<<(size*8))-1) for x, in inputs]
                if load=='sload32.i64':results=[x-(1<<32) if x&(1<<31) else x for x in results]
                add(f'memory{size}k{index}store{int(store)}',body,64,inputs,results,3,folded,slots='    ss0 = explicit_slot 64, align = 16\n')
    for width in (32,64):
        for store in (False,True):
            access=f'    store v0, v3\n    v4 = load.f{width} v1+8' if store else f'    v4 = load.f{width} v3'
            prefix='' if store else '    store v0, v1+8\n'
            body=f'    v1 = stack_addr.i64 ss0\n{prefix}    v2 = iconst.i64 8\n    v3 = iadd v1, v2\n{access}\n    v5 = bitcast.i{width} v4\n'
            body+='    v6 = uextend.i64 v5\n    return v6' if width==32 else '    return v5'
            values=[0,1,0x80000000,0x7fc12345] if width==32 else [0,1,1<<63,0x7ff8123456789abc]
            name=f'floatmemory{width}store{int(store)}'
            add(name,body,64,[(x,) for x in values],values,3,True,slots='    ss0 = explicit_slot 32, align = 16\n')
            path=directory/(name+'.clif')
            path.write_text(path.read_text().replace(f'%{name}(i64)',f'%{name}(f{width})').replace('block0(v0: i64)',f'block0(v0: f{width})'))
        for variant in ('multi','edge','gap'):
            gap='    v8 = bnot v1\n' if variant=='gap' else ''
            body=f'    v2 = iconst.i{width} 7\n    v3 = ishl v0, v2\n{gap}    v4 = iadd v1, v3\n'
            if variant=='edge': body+=f'    jump block1(v4, v3)\nblock1(v6: i{width}, v7: i{width}):\n    v9 = bxor v6, v7\n    return v9'
            else: body+=f'    v5 = bxor v4, {"v8" if variant=="gap" else "v3"}\n    return v5'
            inputs=[(0,1),(1,2),(MASK,MASK),(1<<31,1<<63)]
            mask=(1<<width)-1
            expected=[(((x<<7)+y)^((~y) if variant=='gap' else (x<<7)))&mask for x,y in inputs]
            add(f'shiftfallback{width}{variant}',body,width,inputs,expected,16,False)
    for variant in ('multi','gap'):
        gap='    v8 = bnot v0\n' if variant=='gap' else ''
        body=f'    v1 = stack_addr.i64 ss0\n    store v0, v1+8\n    v2 = iconst.i64 8\n    v3 = iadd v1, v2\n{gap}    v4 = load.i64 v3\n'
        if variant=='multi': body+='    v5 = isub v3, v1\n    v6 = bxor v4, v5\n    return v6'
        else: body+='    v6 = bxor v4, v8\n    return v6'
        values=[0,1,MASK,1<<63]
        add(f'memoryfallback{variant}',body,64,[(x,) for x in values],[x^8 if variant=='multi' else MASK for x in values],3,False,slots='    ss0 = explicit_slot 32, align = 16\n')
    (directory / 'functions.tsv').write_text(''.join(functions))
    (directory / 'cases.json').write_text(json.dumps(cases, indent=2) + '\n')
    return cases

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('runtime', 'compiler-image', 'raw-runtime', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    runtime, compiler, raw, output = [p.resolve() for p in
                                     (args.runtime, args.compiler_image, args.raw_runtime, args.output)]
    project = Path(__file__).resolve().parent
    root = project.parent.parent
    output.mkdir(parents=True)
    frozen = output / 'native-runner'
    shutil.copy2(raw, frozen)
    env = dict(os.environ, NO_JIT='1', NO_AOT='1', NUPP_VM_AUTO_REBUILD='0',
               NUPP_COMPILER_ROOT=str(root), NUPP_VM_BINARY=str(runtime), NUPP_VM_CLI_IMAGE=str(compiler))
    layout = subprocess.check_output([str(frozen), 'native', 'raw-layout'], text=True).strip()
    report = dict(status='running', scope='Producer selection correctness and instruction shapes; no timing verdict',
                  source=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
                  artifacts={str(p): digest(p) for p in (runtime, compiler, raw, frozen)},
                  sourceFiles={str(p.relative_to(root)): digest(p) for p in
                               list((project / 'src/s0').glob('*.nupp')) + [Path(__file__).resolve()]},
                  passed=0, steps=[], failures=[])

    def save():
        (output / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n')

    def run(name, command):
        with (output / (name + '.log')).open('w') as log:
            result = subprocess.run(list(map(str, command)), cwd=project, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=300)
        report['steps'].append(dict(name=name, argv=list(map(str, command)), returnCode=result.returncode))
        save()
        if result.returncode:
            raise SystemExit(name + ' failed: ' + str(output / (name + '.log')))

    directory = output / 'cases'
    directory.mkdir()
    cases = generate(directory)
    image = output / 'producers.image'
    run('check', [root / 'bin/nupp', 'check', '--json'])
    run('emit', [runtime, 'run', compiler, 'nupp.tools.vm.project', 'emit', project,
                 's0.producertests', '', '--output', image])
    run('prepare', [runtime, 'run', image, 's0.producertests', 'prepare', directory, layout])
    for mode in ('normal', 'spill'):
        for index, case in enumerate(cases):
            bundle = directory / mode / case['name']
            inputs, outputs = bundle / 'input.bin', bundle / 'output.bin'
            inputs.write_bytes(b''.join(struct.pack('<Q', word) for word in case['inputWords']))
            result = subprocess.run([str(frozen), 'native', 'raw', str(bundle / 'bundle.json'),
                                     str(inputs), str(outputs)], env=env, capture_output=True, timeout=10)
            actual = struct.unpack('<QQQ', outputs.read_bytes()) if result.returncode == 0 else None
            if actual is None or actual[0] != 0 or actual[1] != case['expectedWord']:
                report['status'] = 'native-failed'
                report['failures'].append(dict(mode=mode, index=index, case=case, actual=actual,
                                               returnCode=result.returncode, stderr=result.stderr.decode(errors='replace')))
                save()
                raise SystemExit('native mismatch: ' + str(bundle))
            report['passed'] += 1
        save()
        print(mode, len(cases), 'passed', flush=True)
    assert all(digest(Path(path)) == value for path, value in report['artifacts'].items())
    assert all(digest(root / path) == value for path, value in report['sourceFiles'].items())
    report.update(status='passed', casesSha256=digest(directory / 'cases.json'), imageSha256=digest(image))
    save()


if __name__ == '__main__':
    main()

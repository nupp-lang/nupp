#!/usr/bin/env python3
"""Regenerate committed scalar ARM64 words with Apple's assembler.

The generated Nupp tests consume literal golden words without an assembler.
Encoding formulas originate in f37f0a754:spike/direct-backend/src/asm.rs;
new scalar forms are independently checked by the same assembler oracle.
"""
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parents[1]
CASES = []


def case(name, args, assembly):
    CASES.append((name, args, assembly))


def g(bits, reg, sp=False):
    return ('sp' if bits == 64 else 'wsp') if sp and reg == 31 else ('xzr' if bits == 64 else 'wzr') if reg == 31 else ('x' if bits == 64 else 'w') + str(reg)


def f(bits, reg):
    return ('d' if bits == 64 else 's') + str(reg)


CONDS = ['eq', 'ne', 'hs', 'lo', 'mi', 'pl', 'vs', 'vc', 'hi', 'ls', 'ge', 'lt', 'gt', 'le', 'al', 'nv']
for bits in [32, 64]:
    for rd, rn, rm in [(0, 1, 2), (30, 15, 31), (31, 31, 0)]:
        for name in ['add', 'sub']:
            for shift in [0, bits - 1]:
                case(name + '_reg', [bits, rd, rn, rm, shift], f'{name} {g(bits,rd)}, {g(bits,rn)}, {g(bits,rm)}, lsl #{shift}')
        for name in ['and', 'orr', 'eor', 'lslv', 'lsrv', 'asrv', 'udiv', 'sdiv']:
            api = name + '_reg' if name in ['and','orr','eor'] else name
            case(api, [bits, rd, rn, rm], f'{name} {g(bits,rd)}, {g(bits,rn)}, {g(bits,rm)}')
        case('mov_reg', [bits,rd,rm], f'mov {g(bits,rd)}, {g(bits,rm)}')
        case('mvn', [bits,rd,rm], f'mvn {g(bits,rd)}, {g(bits,rm)}')
        for name in ['madd','msub']:
            case(name,[bits,rd,rn,rm,15],f'{name} {g(bits,rd)}, {g(bits,rn)}, {g(bits,rm)}, {g(bits,15)}')
        for name in ['ubfm','sbfm']:
            for immr, imms in [(0,bits-1),(bits-1,0),(7,15)]:
                case(name,[bits,rd,rn,immr,imms],f'{name} {g(bits,rd)}, {g(bits,rn)}, #{immr}, #{imms}')
    for rn, rm in [(0,31),(30,15),(31,0)]:
        case('cmp_reg',[bits,rn,rm],f'cmp {g(bits,rn)}, {g(bits,rm)}')
    for rd,rn in [(0,31),(31,15),(30,0)]:
        for imm,shift in [(0,0),(4095,0),(1,1),(4095,1)]:
            for name in ['add','sub']:
                case(name+'_imm',[bits,rd,rn,imm,shift],f'{name} {g(bits,rd,True)}, {g(bits,rn,True)}, #{imm}, lsl #{12*shift}')
            case('cmp_imm',[bits,rn,imm,shift],f'cmp {g(bits,rn,True)}, #{imm}, lsl #{12*shift}')
    for name in ['movz','movn','movk']:
        for rd,imm,half in [(0,0,0),(30,65535,bits//16-1),(31,0x8000,1)]:
            case(name,[bits,rd,imm,half],f'{name} {g(bits,rd)}, #{imm}, lsl #{half*16}')
    for condition in range(16):
        case('csel',[bits,0,30,31,condition],f'csel {g(bits,0)}, {g(bits,30)}, {g(bits,31)}, {CONDS[condition]}')
        case('ccmp_reg',[bits,30,31,15,condition],f'ccmp {g(bits,30)}, {g(bits,31)}, #15, {CONDS[condition]}')
        if condition < 14:
            case('cset',[bits,30,condition],f'cset {g(bits,30)}, {CONDS[condition]}')
    for name in ['cbz','cbnz']:
        for rt,offset in [(0,0),(30,-1048576),(31,1048572)]:
            case(name,[bits,rt,offset],f'{name} {g(bits,rt)}, #{offset}')
for name in ['umulh','smulh']:
    for rd,rn,rm in [(0,30,31),(31,15,0)]:
        case(name,[rd,rn,rm],f'{name} {g(64,rd)}, {g(64,rn)}, {g(64,rm)}')
for name in ['b','bl']:
    for offset in [-134217728,0,134217724]: case(name,[offset],f'{name} #{offset}')
for condition in range(16):
    for offset in [-1048576,1048572]: case('b_cond',[condition,offset],f'b.{CONDS[condition]} #{offset}')
for name in ['br','blr','ret']:
    for rn in [0,16,30]: case(name,[rn],f'{name} x{rn}')
for rd,offset in [(0,-1048576),(30,-1),(31,1048575)]: case('adr',[rd,offset],f'adr {g(64,rd)}, #{offset}')
for rt,offset in [(0,-1048576),(30,0),(31,1048572)]: case('ldr_literal',[rt,offset],f'ldr {g(64,rt)}, #{offset}')
for imm in [0,65535]: case('brk',[imm],f'brk #{imm}')
for size in [1,2,4,8]:
    bits = 64 if size==8 else 32
    suffix = {1:'b',2:'h',4:'',8:''}[size]
    for rt,rn,offset in [(0,31,0),(30,15,4095*size),(31,0,size)]:
        for name in ['ldr','str']: case(name,[size,rt,rn,offset],f'{name}{suffix} {g(bits,rt)}, [{g(64,rn,True)}, #{offset}]')
    for rt,rn,offset in [(0,31,-256),(30,15,255),(31,0,0)]:
        for name in ['ldur','stur']: case(name,[size,rt,rn,offset],f'{name}{suffix} {g(bits,rt)}, [{g(64,rn,True)}, #{offset}]')
for rt,rn,offset in [(0,31,0),(30,15,16380),(31,0,4)]: case('ldrsw',[rt,rn,offset],f'ldrsw {g(64,rt)}, [{g(64,rn,True)}, #{offset}]')
for bits in [32,64]:
    for rt,rn,offset in [(0,31,0),(30,15,4095*(bits//8)),(31,0,bits//8)]:
        for name in ['ldr','str']: case(name+'_fp',[bits,rt,rn,offset],f'{name} {f(bits,rt)}, [{g(64,rn,True)}, #{offset}]')
    for name in ['ldp','stp']:
        for floating in [False,True]:
            for mode in range(3):
                for offset in [-64*(bits//8),63*(bits//8)]:
                    addr = f'[sp, #{offset}]' if mode==0 else f'[sp, #{offset}]!' if mode==1 else f'[sp], #{offset}'
                    register=f if floating else g
                    case(name+('_fp' if floating else ''),[bits,0,30,31,offset,mode],f'{name} {register(bits,0)}, {register(bits,30)}, {addr}')
    for rd,rn,rm in [(0,1,2),(31,30,15)]:
        for name in ['fadd','fsub','fmul','fdiv']: case(name,[bits,rd,rn,rm],f'{name} {f(bits,rd)}, {f(bits,rn)}, {f(bits,rm)}')
        for name in ['fmov','fneg','fabs','fsqrt','frintm','frintp']: case(name,[bits,rd,rn],f'{name} {f(bits,rd)}, {f(bits,rn)}')
        case('fcmp',[bits,rn,rm],f'fcmp {f(bits,rn)}, {f(bits,rm)}')
        case('fmadd',[bits,rd,rn,rm,31],f'fmadd {f(bits,rd)}, {f(bits,rn)}, {f(bits,rm)}, {f(bits,31)}')
        case('fcvt',[bits,96-bits,rd,rn],f'fcvt {f(bits,rd)}, {f(96-bits,rn)}')
        case('fmov_to_int',[bits,rd,rn],f'fmov {g(bits,rd)}, {f(bits,rn)}')
        case('fmov_from_int',[bits,rd,rn],f'fmov {f(bits,rd)}, {g(bits,rn)}')
    for condition in range(16):
        case('fccmp',[bits,30,31,15,condition],f'fccmp {f(bits,30)}, {f(bits,31)}, #15, {CONDS[condition]}')
        case('fcsel',[bits,0,30,31,condition],f'fcsel {f(bits,0)}, {f(bits,30)}, {f(bits,31)}, {CONDS[condition]}')
    for integerBits in [32,64]:
        for rd,rn in [(0,30),(31,15)]:
            for name in ['scvtf','ucvtf']:
                case(name,[bits,integerBits,rd,rn],f'{name} {f(bits,rd)}, {g(integerBits,rn)}')
            for name in ['fcvtzs','fcvtzu']:
                case(name,[bits,integerBits,rd,rn],f'{name} {g(integerBits,rd)}, {f(bits,rn)}')


for bits,n,immr,imms,mask in [
    (32,0,0,7,0xff), (32,0,16,15,0xffff0000),
    (32,0,0,60,0x55555555), (32,0,1,1,0x80000001),
    (64,1,0,7,0xff), (64,1,48,15,0xffff0000),
    (64,0,0,60,0x5555555555555555), (64,1,0,47,0xffffffffffff),
    (64,0,0,15,0x0000ffff0000ffff), (64,1,0,62,0x7fffffffffffffff),
]:
    for name in ['and','orr','eor']:
        for rd,rn in [(0,30),(30,31),(31,0)]:
            case(name+'_imm',[bits,rd,rn,n,immr,imms],f'{name} {g(bits,rd,True)}, {g(bits,rn)}, #0x{mask:x}')


def text_section(data):
    assert struct.unpack_from('<I',data)[0] == 0xfeedfacf
    commands = struct.unpack_from('<I',data,16)[0]
    pos=32
    for _ in range(commands):
        command,length=struct.unpack_from('<II',data,pos)
        if command==0x19:
            count=struct.unpack_from('<I',data,pos+64)[0]
            for i in range(count):
                section=pos+72+i*80
                if data[section:section+16].rstrip(b'\0')==b'__text':
                    size=struct.unpack_from('<Q',data,section+40)[0]
                    offset=struct.unpack_from('<I',data,section+48)[0]
                    return data[offset:offset+size]
        pos+=length
    raise ValueError('no Mach-O text section')


def main():
    source='.text\n.p2align 2\n_s0_golden:\n'+'\n'.join(row[2] for row in CASES)+'\n'
    compiler=subprocess.check_output(['xcrun','--find','clang'],text=True).strip()
    with tempfile.TemporaryDirectory(prefix='nupp-arm64-golden-') as directory:
        asm,obj=Path(directory)/'golden.s',Path(directory)/'golden.o'
        asm.write_text(source)
        subprocess.run([compiler,'-target','arm64-apple-macos11','-c',str(asm),'-o',str(obj)],check=True)
        data=text_section(obj.read_bytes())
    assert len(data)==4*len(CASES)
    words=struct.unpack('<'+'I'*len(CASES),data)
    forms=set(re.findall(r'^function arm64\.(\w+)\(', (PROJECT/'src/s0/arm64.nupp').read_text(),re.M))
    assert forms=={row[0] for row in CASES}, (forms-{row[0] for row in CASES}, {row[0] for row in CASES}-forms)
    lines=['# form\targuments\tword\tassembly']
    tests=['module s0.arm64tests','','local arm64 = require("s0.arm64")','local target = require("s0.arm64target")','','export function golden(): string']
    for (name,args,assembly),word in zip(CASES,words):
        arguments=', '.join(map(str,args))
        lines.append(f'{name}\t{arguments}\t{word:08x}\t{assembly}')
        tests.append(f'    assert(arm64.{name}({arguments}) == 0x{word:08x}, "{assembly}")')
    tests+= [f'    return "{len(CASES)} assembler golden cases across {len(forms)} scalar forms"','end','']
    tests+= (PROJECT/'tests/arm64-negative.nupp.txt').read_text().splitlines()
    (PROJECT/'tests/arm64-golden.tsv').write_text('\n'.join(lines)+'\n')
    (PROJECT/'src/s0/arm64tests.nupp').write_text('\n'.join(tests)+'\n')
    metadata={'sourceEncoder':'f37f0a754:spike/direct-backend/src/asm.rs scalar forms','assembler':subprocess.check_output([compiler,'--version'],text=True).splitlines()[0],'target':'arm64-apple-macos11','cases':len(CASES),'forms':sorted(forms),'textSha256':hashlib.sha256(data).hexdigest(),'assemblySha256':hashlib.sha256(source.encode()).hexdigest()}
    (PROJECT/'tests/arm64-golden.json').write_text(json.dumps(metadata,indent=2)+'\n')
    print(json.dumps({'cases':len(CASES),'forms':len(forms)}))


if __name__=='__main__': main()

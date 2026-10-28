#!/usr/bin/env python3
"""Independent exact-integer/IEEE test vectors and bounded random MIR fixtures."""
import argparse, ctypes, math, random, re, struct
from pathlib import Path
MASK = (1 << 64) - 1
ROOT = Path(__file__).resolve().parent
NAMES = re.findall(r'"([a-z_]+)"', (ROOT / 'src/s0/ir.nupp').read_text().split('ir.opNames = {')[1].split('}')[0])
OPS = {name: i + 1 for i, name in enumerate(NAMES)}
WIDTHS = {1:8, 2:16, 3:32, 4:64, 5:32, 6:64}
def bits(x, kind=6):
    try: return int.from_bytes(struct.pack('<f' if kind == 5 else '<d', x), 'little')
    except OverflowError: return bits(math.copysign(math.inf, x), kind)
def value(x, kind=6): return struct.unpack('<f' if kind == 5 else '<d', x.to_bytes(WIDTHS[kind] // 8, 'little'))[0]
def signed(x, w): return (x & ((1 << w) - 1)) - ((1 << w) if x & (1 << (w-1)) else 0)
def integer_bits(a, kind):
    negative=a<0; a=abs(a); fraction=23 if kind==5 else 52; bias=127 if kind==5 else 1023
    if not a: return 0
    exponent=a.bit_length()-1; shift=exponent-fraction
    if shift>0:
        top,rest=divmod(a,1<<shift); half=1<<(shift-1)
        top+=rest>half or rest==half and top&1
        if top==1<<(fraction+1): top>>=1; exponent+=1
    else: top=a<<-shift
    return (int(negative)<<(WIDTHS[kind]-1))|((exponent+bias)<<fraction)|(top-(1<<fraction))
def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--output', type=Path, required=True); out = parser.parse_args().output
    out.mkdir(parents=True, exist_ok=True); rows=[]; rng=random.Random(1729)
    def add(op, kind, args, expected=0, status=0, operand=None, aux=0, imm=0, equivalent=False):
        row=[OPS[op],kind,operand or kind,aux,imm,status,expected,len(args),int(equivalent)]+args
        rows.append(' '.join(str(v) if 0<=v<1<<63 else hex(v & MASK) for v in row))
    boundary=[0,1,2,31,32,63,64,127,128,255,256,0x7fffffff,0x80000000,0xffffffff,1<<53,(1<<63)-1,1<<63,MASK]
    for kind in range(1,5):
        w=WIDTHS[kind]; m=(1<<w)-1
        pairs=[(x&m,y&m) for x in boundary for y in boundary]+[(rng.getrandbits(w),rng.getrandbits(w)) for _ in range(100)]
        for a,b in pairs:
            sa,sb=signed(a,w),signed(b,w); shift=b&(w-1)
            for op,result in [('iadd',a+b),('isub',a-b),('imul',a*b),('band',a&b),('bor',a|b),('bxor',a^b),('ishl',a<<shift),('ushr',a>>shift),('sshr',sa>>shift),('umulhi',(a*b)>>w),('smulhi',(sa*sb)>>w)]: add(op,kind,[a,b],result&m)
            for op in ('udiv','urem','sdiv','srem'):
                status=2 if b==0 else 3 if op=='sdiv' and sa==-(1<<(w-1)) and sb==-1 else 0
                result=0
                if not status:
                    q=abs(sa)//abs(sb) * (-1 if (sa<0)!=(sb<0) else 1)
                    result={'udiv':a//b,'urem':a%b,'sdiv':q,'srem':sa-q*sb}[op]&m
                add(op,kind,[a,b],result,status)
            for c in range(1,11):
                result=[a==b,a!=b,sa<sb,sa<=sb,sa>sb,sa>=sb,a<b,a<=b,a>b,a>=b][c-1]
                add('icmp',1,[a,b],int(result),operand=kind,aux=c)
        for a in boundary:
            a &= m
            add('iconst',kind,[],a,imm=a); add('bnot',kind,[a],(~a)&m); add('popcnt',kind,[a],bin(a).count('1'))
            for destination in range(1,5):
                dw=WIDTHS[destination]
                if dw<w: add('ireduce',destination,[a],a&((1<<dw)-1),operand=kind)
                elif dw>w:
                    add('uextend',destination,[a],a,operand=kind); add('sextend',destination,[a],signed(a,w)&((1<<dw)-1),operand=kind)
    lib=ctypes.CDLL(None); fma=lib.fma; fma.argtypes=[ctypes.c_double]*3; fma.restype=ctypes.c_double
    fmaf=lib.fmaf; fmaf.argtypes=[ctypes.c_float]*3; fmaf.restype=ctypes.c_float
    for kind in (5,6):
        w=WIDTHS[kind]; samples=[0.0,-0.0,1.0,-1.0,1.5,-2.75,math.inf,-math.inf,math.nan,2.0**-149,2.0**-1074,2.0**63,2.0**64,2.0**53]
        words=list(dict.fromkeys(bits(x,kind) for x in samples)); words += [1,(1<<(23 if kind==5 else 52))-1,0x7fc12345 if kind==5 else 0x7ff8123456789abc]
        for a in words:
            x=value(a,kind); add('fconst',kind,[],a,imm=a); add('fneg',kind,[a],a^(1<<(w-1))); add('fabs',kind,[a],a&((1<<(w-1))-1))
            add('bitcast',3 if kind==5 else 4,[a],a,operand=kind); add('bitcast',kind,[a],a,operand=3 if kind==5 else 4)
            add('fdemote' if kind==6 else 'fpromote',5 if kind==6 else 6,[a],bits(x,5 if kind==6 else 6),operand=kind,equivalent=True)
            for op in ('sqrt','floor','ceil'):
                y=math.sqrt(x) if op=='sqrt' and x>=0 else math.nan if op=='sqrt' else x if not math.isfinite(x) or x==0 else math.floor(x) if op=='floor' else math.ceil(x)
                if y==0: y=math.copysign(0.0,x)
                add(op,kind,[a],bits(y,kind),equivalent=True)
            for dest in range(1,5):
                for op,unsigned in [('fcvt_to_sint_sat',False),('fcvt_to_uint_sat',True)]:
                    dw=WIDTHS[dest]; low=0 if unsigned else -(1<<(dw-1)); high=(1<<(dw if unsigned else dw-1))-1
                    y=0 if math.isnan(x) else high if x>=high else low if x<=low else int(x)
                    add(op,dest,[a],y&((1<<dw)-1),operand=kind)
            for b in words:
                y=value(b,kind)
                for op in ('fadd','fsub','fmul','fdiv'):
                    z=x+y if op=='fadd' else x-y if op=='fsub' else x*y if op=='fmul' else (math.nan if x==0 or math.isnan(x) else math.copysign(math.inf,x)*math.copysign(1.0,y)) if y==0 else x/y
                    add(op,kind,[a,b],bits(z,kind),equivalent=True)
                nan=math.isnan(x) or math.isnan(y)
                for c,z in [(1,x==y),(2,x!=y),(7,nan or x<y),(8,nan or x<=y),(9,nan or x>y),(10,nan or x>=y),(11,not nan),(12,nan),(13,x<y),(14,x<=y),(15,x>y),(16,x>=y),(17,nan or x==y),(18,not nan and x!=y),(19,nan),(20,not nan and x!=y)]: add('fcmp',1,[a,b],int(z),operand=kind,aux=c)
        conversion_words=boundary+[(1<<63)+(1<<39)+1,(1<<63)+(1<<39)-1]+[rng.getrandbits(64) for _ in range(1000)]
        for a in conversion_words:
            for op,z in [('fcvt_from_sint',signed(a,64)),('fcvt_from_uint',a)]: add(op,kind,[a],integer_bits(z,kind),operand=4,equivalent=True)
        for x,y,z in [(1.5,2.0,-3.0),(1+2**-27,1-2**-27,-1.0),(math.inf,0.0,1.0),(-0.0,1.0,-0.0)]:
            aa,bb,cc=[bits(v,kind) for v in (x,y,z)]; answer=(fmaf if kind==5 else fma)(value(aa,kind),value(bb,kind),value(cc,kind)); add('fma',kind,[aa,bb,cc],bits(answer,kind),equivalent=True)
    vector_ops={int(row.split()[0]) for row in rows}
    focused={'select','load','sload','store','stack_addr','call','call_indirect','return_call','return_call_indirect','jump','brif','return','trap'}
    assert vector_ops | {OPS[name] for name in focused} == set(OPS.values())
    (out/'coverage.json').write_text(__import__('json').dumps({'vectorOperations':[NAMES[i-1] for i in sorted(vector_ops)],'focusedOperations':sorted(focused)},indent=2)+'\n')
    (out/'vectors.txt').write_text('\n'.join(rows)+'\n')
    # Integer-only random straight-line functions: Python exact integers provide the reference.
    clif=[]; expected=[]
    for test in range(200):
        args=[rng.getrandbits(64) for _ in range(3)]; vals=args[:]; lines=[f'function %random{test}(i64, i64, i64) -> i64 tail {{','block0(v0: i64, v1: i64, v2: i64):']
        for i in range(3,35):
            left,right=rng.randrange(i),rng.randrange(i); a,b=vals[left],vals[right]; op=rng.choice(['iadd','isub','imul','band','bor','bxor','ushr','ishl'])
            z={'iadd':lambda:a+b,'isub':lambda:a-b,'imul':lambda:a*b,'band':lambda:a&b,'bor':lambda:a|b,'bxor':lambda:a^b,'ushr':lambda:a>>(b&63),'ishl':lambda:a<<(b&63)}[op]()&MASK
            vals.append(z);lines.append(f'    v{i} = {op} v{left}, v{right}')
        lines+=['    return v34','}'];clif.append('\n'.join(lines));expected.append(' '.join(hex(v) for v in [vals[-1]]+args))
    (out/'random.clif').write_text('\n\n'.join(clif)+'\n');(out/'random.txt').write_text('\n'.join(expected)+'\n')
    print(f'{len(rows)} independent vectors; 200 deterministic random functions')
if __name__=='__main__': main()

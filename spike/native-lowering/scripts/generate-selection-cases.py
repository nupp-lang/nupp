#!/usr/bin/env python3
import argparse,json,math,random,struct
from pathlib import Path
parser=argparse.ArgumentParser(description='Generate exact scalar ARM64 selection test inputs and expected words.')
parser.add_argument('--output',type=Path,required=True)
output=parser.parse_args().output.resolve();output.mkdir(parents=True,exist_ok=True)
out=output; functions=[]; cases=[]; U=(1<<64)-1

def signed(x,b=64):
 x&=(1<<b)-1
 return x-(1<<b) if x>>(b-1) else x

def word(x):return f'{x&U:016x}'
def fb(x):return struct.unpack('<Q',struct.pack('<d',x))[0]
def real(x):return struct.unpack('<d',struct.pack('<Q',x))[0]
def add(name,kinds,result,body):
 args=', '.join(kinds);params=', '.join(f'v{i}: {k}' for i,k in enumerate(kinds))
 functions.append(f'function %{name}({args}) -> {result} tail {{\nblock0({params}):\n'+body+'\n}\n')
def case(name,ins,expected):cases.append({'function':name,'inputWords':[word(v) for v in ins],'expectedWord':word(expected)})
def div(a,b):return (abs(a)//abs(b))*(-1 if (a<0)!=(b<0) else 1)
ops={'iadd':lambda a,b:a+b,'isub':lambda a,b:a-b,'imul':lambda a,b:a*b,'udiv':lambda a,b:a//b,'urem':lambda a,b:a%b,'sdiv':lambda a,b:div(signed(a),signed(b)),'srem':lambda a,b:signed(a)-div(signed(a),signed(b))*signed(b),'umulhi':lambda a,b:(a*b)>>64,'smulhi':lambda a,b:(signed(a)*signed(b))>>64,'band':lambda a,b:a&b,'bor':lambda a,b:a|b,'bxor':lambda a,b:a^b,'ishl':lambda a,b:a<<(b&63),'ushr':lambda a,b:a>>(b&63),'sshr':lambda a,b:signed(a)>>(b&63)}
rng=random.Random(64017); pairs=[(0,1),(U,1),(1,U),(1<<63,U),(1<<63,2),(U,63),(U,64),(U,65),(0xaaaaaaaaaaaaaaaa,0x5555555555555555)]+[(rng.getrandbits(64),rng.getrandbits(64)) for _ in range(12)]
for op,compute in ops.items():
 add(op,['i64','i64'],'i64',f'    v2 = {op} v0, v1\n    return v2')
 for a,b in pairs:
  if op=='sdiv' and a==1<<63 and b==U:continue
  case(op,[a,b],compute(a,b))
for op,compute in [('bnot',lambda a:~a),('popcnt',lambda a:bin(a).count('1'))]:
 add(op,['i64'],'i64',f'    v1 = {op} v0\n    return v1')
 for a in [0,1,U,1<<63,0x5555555555555555]+[rng.getrandbits(64) for _ in range(10)]:case(op,[a],compute(a))
for condition,compute in {'eq':lambda a,b:a==b,'ne':lambda a,b:a!=b,'ult':lambda a,b:a<b,'ule':lambda a,b:a<=b,'ugt':lambda a,b:a>b,'uge':lambda a,b:a>=b,'slt':lambda a,b:signed(a)<signed(b),'sle':lambda a,b:signed(a)<=signed(b),'sgt':lambda a,b:signed(a)>signed(b),'sge':lambda a,b:signed(a)>=signed(b)}.items():
 name='icmp_'+condition;add(name,['i64','i64'],'i64',f'    v2 = icmp {condition} v0, v1\n    v3 = uextend.i64 v2\n    return v3')
 for a,b in pairs:case(name,[a,b],compute(a,b))
for condition,compute in {'eq':lambda a,b:a==b,'ne':lambda a,b:a!=b,'lt':lambda a,b:a<b,'le':lambda a,b:a<=b,'gt':lambda a,b:a>b,'ge':lambda a,b:a>=b,'ord':lambda a,b:not(math.isnan(a) or math.isnan(b)),'uno':lambda a,b:math.isnan(a) or math.isnan(b),'ueq':lambda a,b:a==b or math.isnan(a) or math.isnan(b),'one':lambda a,b:a!=b and not(math.isnan(a) or math.isnan(b))}.items():
 name='fcmp_'+condition;add(name,['f64','f64'],'i64',f'    v2 = fcmp {condition} v0, v1\n    v3 = uextend.i64 v2\n    return v3')
 for a,b in [(0.,-0.),(-1.,1.),(1.,-1.),(math.inf,math.inf),(math.nan,1.),(1.,math.nan),(math.nan,math.nan)]:case(name,[fb(a),fb(b)],compute(a,b))
for sign in ['sint','uint']:
 name='sat_'+sign;add(name,['f64'],'i64',f'    v1 = fcvt_to_{sign}_sat.i64 v0\n    return v1')
 lo,hi=(-(1<<63),(1<<63)-1) if sign=='sint' else (0,U)
 for value in [0.,-0.,1.9,-1.9,math.nan,math.inf,-math.inf,float(1<<63),math.nextafter(float(1<<63),0),float(1<<64),math.nextafter(float(1<<64),0),-float(1<<63),-1e300,1e300]:
  result=0 if math.isnan(value) else hi if value>=hi else lo if value<=lo else int(value)
  case(name,[fb(value)],result)
for op,compute in [('fadd',lambda a,b:a+b),('fsub',lambda a,b:a-b),('fmul',lambda a,b:a*b),('fdiv',lambda a,b:a/b)]:
 add(op,['f64','f64'],'f64',f'    v2 = {op} v0, v1\n    return v2')
 for a,b in [(1.25,2.5),(-0.,2.),(0.,-2.),(-1e100,1e50),(math.inf,2.)]:case(op,[fb(a),fb(b)],fb(compute(a,b)))
add('fma',['f64','f64','f64'],'f64','    v3 = fma v0, v1, v2\n    return v3')
for a,b,c,result in [(2.,3.,4.,10.),(-0.,2.,-0.,-0.),(1.5,2.,-3.,0.)]:case('fma',[fb(a),fb(b),fb(c)],fb(result))
add('select_int',['i64','i64','i64'],'i64','    v3 = iconst.i64 0\n    v4 = icmp ne v0, v3\n    v5 = select v4, v1, v2\n    return v5')
add('select_float',['i64','f64','f64'],'f64','    v3 = iconst.i64 0\n    v4 = icmp ne v0, v3\n    v5 = select v4, v1, v2\n    return v5')
for condition in [0,1,U]:
 case('select_int',[condition,U,1<<63],U if condition else 1<<63)
 case('select_float',[condition,fb(-0.),fb(1.5)],fb(-0. if condition else 1.5))
for width in [8,16,32]:
 mask=(1<<width)-1
 for op in ['iadd','isub','imul','band','bor','bxor','ishl','ushr','sshr','udiv','sdiv','urem','srem']:
  name=f'{op}{width}';kind=f'i{width}'
  add(name,[kind,kind],kind,f'    v2 = {op} v0, v1\n    return v2')
  for a,b in [(0,1),(mask,1),(1,mask),(1<<(width-1),2),(mask,width),(mask,width+1)]:
   sa,sb=signed(a,width),signed(b,width)
   result={'iadd':lambda:a+b,'isub':lambda:a-b,'imul':lambda:a*b,'band':lambda:a&b,'bor':lambda:a|b,'bxor':lambda:a^b,'ishl':lambda:a<<(b&(width-1)),'ushr':lambda:a>>(b&(width-1)),'sshr':lambda:sa>>(b&(width-1)),'udiv':lambda:a//b,'urem':lambda:a%b,'sdiv':lambda:div(sa,sb),'srem':lambda:sa-div(sa,sb)*sb}[op]()
   case(name,[a,b],result&mask)
 for op in ['sextend','uextend']:
  name=f'{op}{width}';add(name,[f'i{width}'],'i64',f'    v1 = {op}.i64 v0\n    return v1')
  for a in [0,1,mask,1<<(width-1)]:case(name,[a],signed(a,width) if op=='sextend' else a)
def fb32(x):return struct.unpack('<I',struct.pack('<f',x))[0]
for op,compute in [('fadd',lambda a,b:a+b),('fsub',lambda a,b:a-b),('fmul',lambda a,b:a*b),('fdiv',lambda a,b:a/b)]:
 name=op+'32';add(name,['f32','f32'],'f32',f'    v2 = {op} v0, v1\n    return v2')
 for a,b in [(1.25,2.5),(-0.,2.),(0.,-2.),(-1024.5,0.5),(math.inf,2.)]:case(name,[fb32(a),fb32(b)],fb32(compute(a,b)))
for op,compute in [('fneg',lambda a:-a),('fabs',lambda a:abs(a)),('sqrt',lambda a:math.sqrt(a)),('floor',lambda a:math.floor(a)),('ceil',lambda a:math.ceil(a))]:
 for width,kind,fbits in [(32,'f32',fb32),(64,'f64',fb)]:
  name=op+str(width);add(name,[kind],kind,f'    v1 = {op} v0\n    return v1')
  for a in [0.,1.25,4.,9.]:case(name,[fbits(a)],fbits(float(compute(a))))
(out/'scalar.clif').write_text('\n'.join(functions))
(out/'cases.json').write_text(json.dumps({'format':'hex64-inputs-and-result','cases':cases},indent=2)+'\n')
print(len(functions),'functions',len(cases),'cases')

import json,os
from pathlib import Path
out=output/'control';out.mkdir(exist_ok=True)
source='''function %pair_callee(i64, i64) -> i64, i64 tail {
block0(v0: i64, v1: i64):
    return v1, v0
}
function %pair_caller(i64, i64) -> i64 tail {
    sig0 = (i64, i64) -> i64, i64 tail
    fn0 = %pair_callee sig0
block0(v0: i64, v1: i64):
    v2, v3 = call fn0(v0, v1)
    v4 = isub v2, v3
    v5 = iadd v4, v0
    return v5
}
function %callee(i64, i64) -> i64 tail {
block0(v0: i64, v1: i64):
    v2 = isub v0, v1
    return v2
}
function %caller(i64, i64) -> i64 tail {
    sig0 = (i64, i64) -> i64 tail
    fn0 = %callee sig0
block0(v0: i64, v1: i64):
    v2 = call fn0(v1, v0)
    v3 = iadd v2, v0
    return v3
}
function %tailcaller(i64, i64) -> i64 tail {
    sig0 = (i64, i64) -> i64 tail
    fn0 = %callee sig0
block0(v0: i64, v1: i64):
    return_call fn0(v1, v0)
}
function %cycle(i64, i64, i64) -> i64 tail {
block0(v0: i64, v1: i64, v2: i64):
    jump block1(v0, v1, v2)
block1(v3: i64, v4: i64, v5: i64):
    v6 = iconst.i64 1
    v7 = isub v5, v6
    v8 = icmp ne v7, v6
    brif v8, block1(v4, v3, v7), block2(v3)
block2(v9: i64):
    return v9
}
function %foreign(i64) -> i64 tail {
    sig0 = () -> i64 system_v
    fn0 = %nupp_os_page_size sig0
block0(v0: i64):
    v1 = call fn0()
    v2 = iadd v0, v1
    return v2
}
function %foreigntail() -> i64 tail {
    sig0 = () -> i64 system_v
    fn0 = %nupp_os_page_size sig0
block0:
    return_call fn0()
}
function %stackcopy(i64) -> i64 tail {
    ss0 = explicit_slot 4096, align = 16
block0(v0: i64):
    v1 = stack_addr.i64 ss0
    store v0, v1+2049
    v2 = load.i64 v1+2049
    return v2
}
function %signedload(i64) -> i64 tail {
    ss0 = explicit_slot 16, align = 16
block0(v0: i64):
    v1 = stack_addr.i64 ss0
    istore8 v0, v1+5
    v2 = sload8.i64 v1+5
    return v2
}
function %floatcopy(f64) -> f64 tail {
    ss0 = explicit_slot 16, align = 16
block0(v0: f64):
    v1 = stack_addr.i64 ss0
    store v0, v1
    v2 = load.f64 v1
    return v2
}
'''
U=(1<<64)-1;cases=[]
def add(name,ins,result):cases.append({'function':name,'inputWords':[f'{v&U:016x}' for v in ins],'expectedWord':f'{result&U:016x}'})
for a,b in [(1,2),(U,1),(1<<63,U),(123,456)]:
 add('caller',[a,b],b);add('tailcaller',[a,b],b-a)
 add('pair_caller',[a,b],b);add('pair_callee',[a,b],b);cases[-1]['expectedSecondWord']=f'{a&U:016x}'
for n in [2,3,4,17,100]:add('cycle',[123,456,n],123 if n%2==0 else 456)
for a in [0,1,U,1<<63]:
 add('foreign',[a],a+os.sysconf('SC_PAGESIZE'));add('stackcopy',[a],a);add('signedload',[a],(a&255)-256 if a&128 else a&255);add('floatcopy',[a],a)
add('foreigntail',[],os.sysconf('SC_PAGESIZE'))
(out/'scalar.clif').write_text(source);(out/'cases.json').write_text(json.dumps({'cases':cases},indent=2)+'\n')
print(len(cases),'control cases')

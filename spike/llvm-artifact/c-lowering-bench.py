import subprocess, time, statistics, shutil, os
W='/Users/dowling/projects/nupp/.claude/worktrees/spike-llvm-artifact'
D=W+'/spike/direct-backend'
flags=['-std=c11','-O3','-ffp-contract=off','-fno-fast-math','-Wall','-Wextra','-Werror','-Wno-unused-function','-fPIC']
def cc_one(cc):
    return [[cc]+flags+['-dynamiclib','-undefined','dynamic_lookup','-o','ccmp/out.dylib','ccmp/kernels5.c','ccmp/builders.c']]
def run(cmds, parallel=False):
    t=time.perf_counter()
    if parallel:
        ps=[subprocess.Popen(c) for c in cmds[:-1]]
        for p in ps: assert p.wait()==0
        assert subprocess.run(cmds[-1]).returncode==0
    else:
        for c in cmds: assert subprocess.run(c).returncode==0
    return (time.perf_counter()-t)*1e3
def cc_par(cc):
    return [[cc]+flags+['-c','-o','ccmp/k.o','ccmp/kernels5.c'],[cc]+flags+['-c','-o','ccmp/b.o','ccmp/builders.c'],
            [cc,'-dynamiclib','-undefined','dynamic_lookup','-o','ccmp/out2.dylib','ccmp/k.o','ccmp/b.o']]
def llvm():
    shutil.rmtree('ccmp/llvm-out',ignore_errors=True)
    return [[W+'/build/component/release/nupp-llvm','compile','--target','arm64-apple-macosx11.0.0','--kernels',D+'/kernels.json','--builders',D+'/builders.json','--builder-size','64','--out','ccmp/llvm-out']]
cases={'clang -O3, one invocation':lambda: run(cc_one('clang')),
       'clang -O3, two TUs in parallel + link':lambda: run(cc_par('clang'),True),
       'gcc-16 -O3, one invocation':lambda: run(cc_one('gcc-16')),
       'gcc-16 -O3, two TUs in parallel + link':lambda: run(cc_par('gcc-16'),True),
       'LLVM component (spawn to exit)':lambda: run(llvm())}
print(subprocess.run(['uptime'],capture_output=True,text=True).stdout.strip())
for f in cases.values(): f()
res={k:[] for k in cases}
for r in range(15):
    for k,f in cases.items(): res[k].append(f())
for k,v in res.items(): print('%-40s median %6.1f ms  min %6.1f  max %6.1f'%(k,statistics.median(v),min(v),max(v)))
print(subprocess.run(['uptime'],capture_output=True,text=True).stdout.strip())

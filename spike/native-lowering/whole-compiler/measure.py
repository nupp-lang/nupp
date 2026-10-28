#!/usr/bin/env python3
"""Validate or explicitly measure matched full native compiler commands."""
import argparse
import os
import json
import math
import random
import re
import shutil
import signal
import sys
import statistics
import subprocess
import time
from pathlib import Path
import prepare

ROOT, OUT, FROZEN = prepare.ROOT, prepare.OUT, prepare.FROZEN
CHECK_FILES = sorted(str(p.relative_to(FROZEN / 'project')) for directory in ['src/nupp/compiler', 'src/nupp/tools/cli', 'src/nupp/tools/vm'] for p in (FROZEN / 'project' / directory).rglob('*.nupp') if not p.name.endswith('.d.nupp'))


def percentile(values, fraction):
    return sorted(values)[min(len(values) - 1, int(len(values) * fraction))]


def interval(ratios):
    rng = random.Random(6214)
    logs = list(map(math.log, ratios))
    boots = [math.exp(statistics.mean(rng.choices(logs, k=len(logs)))) for _ in range(10000)]
    return [percentile(boots, .025), percentile(boots, .975)]



def run_with_resources(command, cwd, environment, stdout, stderr, timeout):
    """Collect this child's wait4 usage without privileged system queries."""
    with subprocess.Popen(command, cwd=cwd, env=environment, stdout=stdout, stderr=stderr) as process:
        def expired(signum, frame):
            raise subprocess.TimeoutExpired(command, timeout)
        previous = signal.signal(signal.SIGALRM, expired)
        signal.alarm(timeout)
        try:
            _, status, usage = os.wait4(process.pid, 0)
            process.returncode = os.waitstatus_to_exitcode(status)
        except BaseException:
            process.kill()
            process.wait()
            raise
        finally:
            signal.alarm(0)
            signal.signal(signal.SIGALRM, previous)
        return subprocess.CompletedProcess(command, process.returncode), usage



def emitted_function_count(binary, image, environment, cwd, prefix):
    """Read the VM's validated binary image format outside the timed interval."""
    command = list(map(str, [binary, 'verify', image]))
    checked = subprocess.run(command, cwd=cwd, env=environment, capture_output=True, text=True, timeout=120)
    Path(str(prefix) + '.verify.out').write_text(checked.stdout)
    Path(str(prefix) + '.verify.err').write_text(checked.stderr)
    assert checked.returncode == 0, str(prefix)
    found = re.fullmatch(r'verified (\d+) functions\s*', checked.stdout)
    assert found and int(found[1]) > 0, 'Verifier did not report a function count'
    return int(found[1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--measure', action='store_true', help='Collect timings only after a coordinated quiet window')
    parser.add_argument('--quiet-confirmed', action='store_true')
    parser.add_argument('--pilot', action='store_true', help='Collect one to three diagnostic pairs without a duration verdict')
    parser.add_argument('--workloads', default='cold-check,warm-check,emit', help='Pilot workload subset; final measurement always covers all three')
    parser.add_argument('--pairs', type=int, default=12)
    parser.add_argument('--pending-identity', action='store_true', help='Permit preparation checks before the native emit identity gate')
    parser.add_argument('--checks-only', action='store_true', help='Validate checks using the already proven native emit identity')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output = args.output.resolve()
    assert not (args.measure and args.checks_only)
    assert not args.pending_identity or (args.checks_only and not args.measure)
    assert not args.measure or args.quiet_confirmed, 'A coordinated quiet window is required'
    assert not args.pilot or (args.measure and 1 <= args.pairs <= 3)
    assert args.pairs >= 12 or not args.measure or args.pilot
    workloads = args.workloads.split(',')
    assert workloads and len(set(workloads)) == len(workloads)
    assert all(name in ['cold-check', 'warm-check', 'emit'] for name in workloads)
    assert args.pilot or workloads == ['cold-check', 'warm-check', 'emit']
    assert CHECK_FILES
    assert not args.output.exists(), 'Use a fresh evidence directory'
    args.output.mkdir(parents=True)
    inputs = prepare.freeze()
    prepare.check_inputs(inputs)
    proofs = {mode: json.loads((OUT / mode / prepare.PROOF_NAME).read_text()) for mode in ['baseline', 'candidate']}
    for mode, proof in proofs.items():
        assert args.pending_identity or proof.get('identity') == 'passed'
        for path, meta in proof['artifacts'].items():
            assert prepare.digest(path) == meta['sha256']
    report = {'scope': 'Full native AOT compiler process; same source files, separate caches; no Cranelift backend speed claim', 'measured': args.measure, 'diagnostic': args.pilot, 'workloads': workloads, 'nativeEmitIdentityPending': args.pending_identity, 'source': inputs['source'], 'inputsSha256': prepare.digest(OUT / 'inputs.json'), 'checkFiles': CHECK_FILES, 'pairs': args.pairs if args.measure else 1, 'margin': .02, 'rows': [], 'status': 'running'}
    receipt = args.output / 'receipt.json'
    report['proofs'] = {mode: {'path': str(OUT / mode / prepare.PROOF_NAME), 'sha256': prepare.digest(OUT / mode / prepare.PROOF_NAME), 'binarySha256': prepare.digest(OUT / mode / prepare.BINARY_NAME)} for mode in proofs}
    report['harnessFiles'] = {}
    for source in Path(__file__).resolve().parent.iterdir():
        if source.suffix in ['.py', '.json']:
            target = args.output / 'harness' / source.name
            prepare.copy(source, target)
            report['harnessFiles'][str(target)] = prepare.digest(target)
    prepare.save(receipt, report)

    def execute(mode, workload, index, warmup=False):
        lane = args.output / mode
        lane.mkdir(exist_ok=True)
        project = lane / (workload + '-project')
        if workload != 'emit' and not project.exists():
            shutil.copytree(FROZEN / 'project', project)
        image = FROZEN / (mode + '.image')
        binary = OUT / mode / prepare.BINARY_NAME
        env = prepare.environment(image)
        env.update(NUPP_VM_BINARY=str(binary), AOT_VERBOSE='1')
        label = f'{workload}-{index}' + ('-prime' if warmup else '')
        prefix = lane / label
        if workload == 'emit':
            output = lane / (label + '.image')
            command = [binary, 'run', image, 'nupp.tools.vm.project', 'emit', FROZEN / 'project', 'nupp.tools.vm.root', prepare.EXTRAS, '--output', output, '--tasks']
            cwd = ROOT
        else:
            cache = lane / (f'cold-cache-{index}' if workload == 'cold-check' else 'warm-cache')
            assert not cache.exists() if workload == 'cold-check' else True
            env['NUPP_CACHE_DIR'] = str(cache)
            if workload == 'cold-check' and (project / 'build').exists():
                shutil.rmtree(project / 'build')
            command = [binary, 'exec', image, 'nupp.tools.vm.root', 'check', *CHECK_FILES, '--json']
            cwd = project
        command = list(map(str, command))
        row = {'mode': mode, 'workload': workload, 'pair': index, 'warmup': warmup, 'argv': command, 'cwd': str(cwd), 'controls': {key: env.get(key) for key in ['NO_JIT', 'NO_AOT', 'NO_GC', 'NUPP_CACHE_DIR', 'NUPP_VM_AUTO_REBUILD', 'NUPP_COMPILER_ROOT', 'AOT_VERBOSE']}, 'status': 'running'}
        report['rows'].append(row)
        prepare.save(receipt, report)
        with prefix.with_suffix('.out').open('w') as out, prefix.with_suffix('.err').open('w') as err:
            start = time.perf_counter() if args.measure and not warmup else None
            if args.measure and not warmup:
                result, usage = run_with_resources(command, cwd, env, out, err, 3600)
            else:
                result = subprocess.run(command, cwd=cwd, env=env, stdout=out, stderr=err, timeout=3600)
            if start is not None:
                row['wallSeconds'] = time.perf_counter() - start
                row['peakRssBytes'] = int(usage.ru_maxrss) * (1 if sys.platform == 'darwin' else 1024)
                row['userCpuSeconds'] = usage.ru_utime
                row['systemCpuSeconds'] = usage.ru_stime
                row['resourceMethod'] = 'wait4 measured direct child; ru_maxrss converted to bytes'
                prepare.save(Path(str(prefix) + '.resource.json'), {key: row[key] for key in ['peakRssBytes', 'userCpuSeconds', 'systemCpuSeconds', 'resourceMethod']})
        row['returnCode'] = result.returncode
        row['status'] = 'passed' if result.returncode == 0 else 'failed'
        prepare.save(receipt, report)
        assert result.returncode == 0, str(prefix)
        stderr = prefix.with_suffix('.err').read_text()
        attached = re.search(r'aot: attached (\d+) linked entries', stderr)
        assert attached and int(attached[1]) == proofs[mode]['compiledFunctions']
        row['attachedEntries'] = int(attached[1])
        if workload == 'emit':
            entries = re.search(r'compiled frame entries: (\d+)', stderr)
            assert entries and int(entries[1]) > 0
            row.update(outputSha256=prepare.digest(output), outputBytes=output.stat().st_size, compiledFrameEntries=int(entries[1]), emittedFunctions=emitted_function_count(binary, output, env, cwd, prefix))
            assert row['outputSha256'] == proofs[mode]['referenceEmitSha256']
        else:
            data = json.loads(prefix.with_suffix('.out').read_text())
            assert data['ok'] and not data['diagnostics']
            row['checkTiming'] = data.get('timing')
            if workload == 'cold-check':
                assert data['timing']['compiledModules'] > 0, 'Cold check did not compile modules'
            elif not warmup:
                assert data['timing']['reusedModules'] > 0, 'Warm check did not reuse modules'
        if 'wallSeconds' in row:
            if workload == 'emit':
                row['wholePipelineMillisecondsPerFunction'] = 1000 * row['wallSeconds'] / row['emittedFunctions']
        prepare.save(receipt, report)

    def checked_execute(*positional, **named):
        try:
            execute(*positional, **named)
        except Exception as error:
            report['status'] = 'failed'
            report['failure'] = repr(error)
            if report['rows']:
                report['rows'][-1]['status'] = 'failed'
            prepare.save(receipt, report)
            raise

    if not args.pilot or 'warm-check' in workloads:
        for mode in ['baseline', 'candidate']:
            checked_execute(mode, 'warm-check', -1, warmup=True)
    for index in range(report['pairs']):
        for workload in (['cold-check', 'warm-check'] if args.checks_only else workloads):
            order = ['baseline', 'candidate'] if index % 2 == 0 else ['candidate', 'baseline']
            for mode in order:
                checked_execute(mode, workload, index)
    if args.measure:
        report['comparisons'] = {}
        for workload in workloads:
            rows = [row for row in report['rows'] if row['workload'] == workload and not row['warmup']]
            ratios = [next(r['wallSeconds'] for r in rows if r['mode'] == 'candidate' and r['pair'] == i) / next(r['wallSeconds'] for r in rows if r['mode'] == 'baseline' and r['pair'] == i) for i in range(args.pairs)]
            comparison = {'pairedGeometricRatio': math.exp(statistics.mean(map(math.log, ratios))), 'ratios': ratios}
            if args.pilot:
                comparison['verdict'] = 'diagnostic only; no confidence interval or duration verdict'
            else:
                low, high = interval(ratios)
                comparison.update(pairedBootstrap95=[low, high], verdict='improved' if high < .98 else 'regressed' if low > 1.02 else 'unchanged' if low >= .98 and high <= 1.02 else 'inconclusive')
            report['comparisons'][workload] = comparison
    report['status'] = 'passed'
    prepare.check_inputs(inputs)
    prepare.save(receipt, report)
    print(json.dumps({k: v for k, v in report.items() if k not in ['rows', 'checkFiles']}, indent=2))


if __name__ == '__main__':
    main()

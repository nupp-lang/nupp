import hashlib, json, os, platform, random, statistics, subprocess, sys
from pathlib import Path

baseline, candidate, output = sys.argv[1:]
keys = ['spawn_await_us', 'worker_roundtrip_us', 'raw_resume_us', 'held_task_bytes', 'held_worker_bytes', 'dropped_heap_kib', 'final_heap_kib', 'checksum']
pair_count = int(os.getenv('HANDLE_PAIRS', '30'))
children = os.getenv('HANDLE_CHILDREN', '1000000')
env = dict(os.environ, HANDLE_CHILDREN=children, HANDLE_HELD='10000')

def run(binary, variant):
    proc = subprocess.run([binary], env=dict(env, EXPECT_THREAD=str(variant)), text=True, capture_output=True, check=True)
    lines = [line for line in proc.stdout.splitlines() if line.startswith('metrics ')]
    if len(lines) != 1: raise RuntimeError(proc.stdout + proc.stderr)
    return dict(zip(keys, map(float, lines[0].split()[1:])))

for binary, variant in [(baseline, 0), (candidate, 1)]: run(binary, variant)
rows = []
for index in range(pair_count):
    row = {}
    order = [('baseline', baseline, 0), ('candidate', candidate, 1)]
    if index % 2: order.reverse()
    for label, binary, variant in order:
        row[label] = run(binary, variant)
    assert row['baseline']['checksum'] == row['candidate']['checksum']
    rows.append(row)
    print('pair', index + 1, json.dumps(row), flush=True)

rng = random.Random(1107)
summary = {}
for key in keys[:-1]:
    b = [row['baseline'][key] for row in rows]
    c = [row['candidate'][key] for row in rows]
    value = {'baseline_median': statistics.median(b), 'candidate_median': statistics.median(c)}
    if min(b) > 0 and min(c) > 0:
        ratios = [y/x for x,y in zip(b,c)]
        bootstrap = sorted(statistics.median(rng.choices(ratios, k=len(ratios))) for _ in range(20000))
        value.update(paired_ratio_median=statistics.median(ratios), paired_ratio_interval95=[bootstrap[500], bootstrap[19499]])
        if key.endswith('_us'):
            low, high = value['paired_ratio_interval95']
            value['verdict'] = 'regressed' if low > 1.05 else 'improved' if high < .95 else 'unchanged' if low >= .95 and high <= 1.05 else 'inconclusive'
    summary[key] = value
result = {'platform': platform.platform(), 'pairs': rows, 'summary': summary, 'practical_margin': .05, 'workload': {'children': int(children), 'held': 10000, 'workers': 1000},
          'baseline_sha256': hashlib.sha256(Path(baseline).read_bytes()).hexdigest(),
          'candidate_sha256': hashlib.sha256(Path(candidate).read_bytes()).hexdigest()}
Path(output).write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(summary, indent=2))

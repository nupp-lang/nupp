import collections, statistics
d = collections.defaultdict(list)
for line in open('evidence/runs.tsv'):
    who, name, secs = line.split()
    d[(name, who)].append(float(secs))
names = sorted({k[0] for k in d})
for name in names:
    row = {who: statistics.median(v) for (n, who), v in d.items() if n == name}
    base = row.get('proto')
    print(name, '  '.join(f'{who} {secs*1e3:.1f} ms' + (f' ({secs/base:.2f}x proto)' if base and who != 'proto' else '') for who, secs in sorted(row.items())))

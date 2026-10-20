//! Multiple-entry dominance with linear storage. Entry edges include budget
//! resumes, so an authored guard cannot justify a use reached by restoration.
use std::collections::BTreeSet;

pub(crate) struct Dominators {
    enter: Vec<usize>,
    leave: Vec<usize>,
}

impl Dominators {
    pub fn new(preds: &[Vec<usize>], entries: &BTreeSet<usize>) -> Self {
        let n = preds.len();
        let root = n;
        let mut succs = vec![Vec::new(); n + 1];
        for (node, ps) in preds.iter().enumerate() {
            for &p in ps {
                succs[p].push(node);
            }
            if entries.contains(&node) || ps.is_empty() {
                succs[root].push(node);
            }
        }
        // Iterative DFS avoids using the host stack for large functions.
        let mut seen = vec![false; n + 1];
        let mut post = Vec::with_capacity(n + 1);
        let mut stack = vec![(root, false)];
        while let Some((node, exit)) = stack.pop() {
            if exit {
                post.push(node);
                continue;
            }
            if seen[node] {
                continue;
            }
            seen[node] = true;
            stack.push((node, true));
            for &s in succs[node].iter().rev() {
                if !seen[s] {
                    stack.push((s, false));
                }
            }
        }
        post.reverse();
        let mut rank = vec![usize::MAX; n + 1];
        for (r, &node) in post.iter().enumerate() {
            rank[node] = r;
        }
        let mut idom = vec![usize::MAX; n + 1];
        idom[root] = root;
        loop {
            let mut changed = false;
            for &node in post.iter().skip(1) {
                let mut parent = if entries.contains(&node) || preds[node].is_empty() {
                    root
                } else {
                    usize::MAX
                };
                for &p in &preds[node] {
                    if idom[p] == usize::MAX {
                        continue;
                    }
                    if parent == usize::MAX {
                        parent = p;
                        continue;
                    }
                    let mut other = p;
                    while parent != other {
                        while rank[parent] > rank[other] {
                            parent = idom[parent];
                        }
                        while rank[other] > rank[parent] {
                            other = idom[other];
                        }
                    }
                }
                if idom[node] != parent {
                    idom[node] = parent;
                    changed = true;
                }
            }
            if !changed {
                break;
            }
        }
        // Tree intervals make each proof query constant time. The fixed point
        // above is not claimed to take linear time on every possible graph.
        let mut children = vec![Vec::new(); n + 1];
        for node in 0..n {
            if idom[node] != usize::MAX {
                children[idom[node]].push(node);
            }
        }
        let mut result = Self {
            enter: vec![usize::MAX; n + 1],
            leave: vec![0; n + 1],
        };
        let mut stack = vec![(root, false)];
        let mut clock = 0;
        while let Some((node, exit)) = stack.pop() {
            if exit {
                result.leave[node] = clock;
                continue;
            }
            result.enter[node] = clock;
            clock += 1;
            stack.push((node, true));
            for &child in children[node].iter().rev() {
                stack.push((child, false));
            }
        }
        result
    }
    pub fn dominates(&self, a: usize, b: usize) -> bool {
        // Unreachable instructions establish no facts about another instruction.
        a == b
            || self.enter[a] != usize::MAX
                && self.enter[a] <= self.enter[b]
                && self.enter[b] < self.leave[a]
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn matches_set_intersection_with_multiple_entries_and_cycles() {
        // Independent old set-based oracle, including unreachable components.
        let mut seed = 91u64;
        let mut random = || {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            seed
        };
        for n in 1..70 {
            for _ in 0..20 {
                let mut preds = vec![vec![]; n];
                let mut entries = BTreeSet::from([0]);
                for (node, ps) in preds.iter_mut().enumerate() {
                    if random() % 9 == 0 {
                        entries.insert(node);
                    }
                    for p in 0..n {
                        if random() % 11 == 0 {
                            ps.push(p);
                        }
                    }
                }
                let tree = Dominators::new(&preds, &entries);
                let all: BTreeSet<usize> = (0..n).collect();
                let mut sets = vec![all; n];
                loop {
                    let mut changed = false;
                    for node in 0..n {
                        let mut next = if entries.contains(&node) || preds[node].is_empty() {
                            BTreeSet::new()
                        } else {
                            let mut next = sets[preds[node][0]].clone();
                            for &p in &preds[node][1..] {
                                next = next.intersection(&sets[p]).copied().collect();
                            }
                            next
                        };
                        next.insert(node);
                        if sets[node] != next {
                            sets[node] = next;
                            changed = true;
                        }
                    }
                    if !changed {
                        break;
                    }
                }
                for b in 0..n {
                    for a in 0..n {
                        if tree.enter[b] != usize::MAX {
                            assert_eq!(
                                tree.dominates(a, b),
                                sets[b].contains(&a),
                                "{a} -> {b}, {preds:?}, {entries:?}"
                            );
                        } else {
                            assert_eq!(tree.dominates(a, b), a == b);
                        }
                    }
                }
            }
        }
    }
}

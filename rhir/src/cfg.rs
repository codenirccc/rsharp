use crate::ir::Func;

pub fn preds(f: &Func) -> Vec<Vec<usize>> {
    let mut p = vec![Vec::new(); f.blocks.len()];
    for (i, b) in f.blocks.iter().enumerate() {
        for s in b.term.successors() {
            if s < p.len() && !p[s].contains(&i) {
                p[s].push(i);
            }
        }
    }
    p
}

pub fn rpo(f: &Func) -> Vec<usize> {
    let n = f.blocks.len();
    let mut seen = vec![false; n];
    let mut post = Vec::new();
    if n == 0 {
        return post;
    }
    seen[f.entry] = true;
    let mut stack = vec![(f.entry, 0usize)];
    while let Some((b, idx)) = stack.pop() {
        let succ = f.blocks[b].term.successors();
        if idx < succ.len() {
            stack.push((b, idx + 1));
            let s = succ[idx];
            if s < n && !seen[s] {
                seen[s] = true;
                stack.push((s, 0));
            }
        } else {
            post.push(b);
        }
    }
    post.reverse();
    post
}

pub fn reachable(f: &Func) -> Vec<bool> {
    let n = f.blocks.len();
    let mut seen = vec![false; n];
    if n == 0 {
        return seen;
    }
    seen[f.entry] = true;
    let mut stack = vec![f.entry];
    while let Some(b) = stack.pop() {
        for s in f.blocks[b].term.successors() {
            if s < n && !seen[s] {
                seen[s] = true;
                stack.push(s);
            }
        }
    }
    seen
}

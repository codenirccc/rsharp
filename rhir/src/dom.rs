use crate::cfg;
use crate::ir::Func;

pub struct DomTree {
    pub idom: Vec<usize>,
    pub children: Vec<Vec<usize>>,
    pub order: Vec<usize>,
    pub num: Vec<usize>,
}

pub fn build(f: &Func) -> DomTree {
    let n = f.blocks.len();
    let order = cfg::rpo(f);
    let mut num = vec![usize::MAX; n];
    for (i, b) in order.iter().enumerate() {
        num[*b] = i;
    }
    let mut idom = vec![f.entry; n];
    if n > 0 {
        idom[f.entry] = f.entry;
    }
    let preds = cfg::preds(f);
    let mut changed = true;
    while changed {
        changed = false;
        for &b in order.iter().skip(1) {
            let mut new = usize::MAX;
            for &p in &preds[b] {
                if num[p] == usize::MAX {
                    continue;
                }
                new = if new == usize::MAX {
                    p
                } else {
                    intersect(&idom, &num, p, new)
                };
            }
            if new != usize::MAX && idom[b] != new {
                idom[b] = new;
                changed = true;
            }
        }
    }
    let mut children = vec![Vec::new(); n];
    for &b in order.iter() {
        if b != f.entry && idom[b] != usize::MAX {
            children[idom[b]].push(b);
        }
    }
    DomTree {
        idom,
        children,
        order,
        num,
    }
}

fn intersect(idom: &[usize], num: &[usize], mut a: usize, mut b: usize) -> usize {
    while a != b {
        while num[a] > num[b] {
            a = idom[a];
        }
        while num[b] > num[a] {
            b = idom[b];
        }
    }
    a
}

pub fn frontiers(f: &Func, dom: &DomTree) -> Vec<Vec<usize>> {
    let n = f.blocks.len();
    let preds = cfg::preds(f);
    let mut df = vec![Vec::new(); n];
    for b in 0..n {
        if preds[b].len() < 2 {
            continue;
        }
        for &p in &preds[b] {
            let mut runner = p;
            while runner != dom.idom[b] && runner != usize::MAX {
                if !df[runner].contains(&b) {
                    df[runner].push(b);
                }
                if runner == dom.idom[runner] {
                    break;
                }
                runner = dom.idom[runner];
            }
        }
    }
    df
}

pub fn dominates(dom: &DomTree, a: usize, b: usize) -> bool {
    let mut x = b;
    loop {
        if x == a {
            return true;
        }
        if x == dom.idom[x] || dom.idom[x] == usize::MAX {
            return false;
        }
        x = dom.idom[x];
    }
}

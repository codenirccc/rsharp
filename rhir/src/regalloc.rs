use std::collections::HashMap;

use crate::mir::*;

#[derive(Clone, Copy, Debug)]
pub enum Loc {
    Reg(u8),
    Slot(i32),
    None,
}

pub struct Alloc {
    pub loc: Vec<Loc>,
    pub slots: usize,
    pub used: Vec<u8>,
}

struct Block {
    start: usize,
    end: usize,
    uses: Vec<u32>,
    defs: Vec<u32>,
    succ: Vec<usize>,
}

fn is_term(i: &MInst) -> bool {
    matches!(i, MInst::Jmp(_) | MInst::Jcc { .. } | MInst::Ret)
}

fn split(insts: &[MInst]) -> Vec<Block> {
    let mut starts: Vec<usize> = Vec::new();
    for (pos, i) in insts.iter().enumerate() {
        if matches!(i, MInst::Label(_)) {
            starts.push(pos);
        }
    }
    if starts.is_empty() || starts[0] != 0 {
        starts.insert(0, 0);
    }

    let mut by_label: HashMap<u32, usize> = HashMap::new();
    let mut blocks: Vec<Block> = Vec::new();
    for (bi, s) in starts.iter().enumerate() {
        let e = if bi + 1 < starts.len() {
            starts[bi + 1]
        } else {
            insts.len()
        };
        if let MInst::Label(l) = insts[*s] {
            by_label.insert(l, bi);
        }
        blocks.push(Block {
            start: *s,
            end: e,
            uses: Vec::new(),
            defs: Vec::new(),
            succ: Vec::new(),
        });
    }

    for bi in 0..blocks.len() {
        let (s, e) = (blocks[bi].start, blocks[bi].end);
        let mut uses = Vec::new();
        let mut defs = Vec::new();
        let mut succ = Vec::new();
        for pos in s..e {
            for r in insts[pos].uses() {
                if let Reg::V(v) = r {
                    if !defs.contains(&v) && !uses.contains(&v) {
                        uses.push(v);
                    }
                }
            }
            for r in insts[pos].defs() {
                if let Reg::V(v) = r {
                    if !defs.contains(&v) {
                        defs.push(v);
                    }
                }
            }
            match &insts[pos] {
                MInst::Jmp(l) | MInst::Jcc { label: l, .. } => {
                    if let Some(t) = by_label.get(l) {
                        if !succ.contains(t) {
                            succ.push(*t);
                        }
                    }
                }
                _ => {}
            }
        }
        if e > s {
            let last = &insts[e - 1];
            if !is_term(last) && bi + 1 < blocks.len() {
                succ.push(bi + 1);
            }
        }
        blocks[bi].uses = uses;
        blocks[bi].defs = defs;
        blocks[bi].succ = succ;
    }
    blocks
}

pub fn run(m: &MFunc, nvalues: usize, first_slot: usize) -> Alloc {
    let n = nvalues.max(1);
    let mut start = vec![usize::MAX; n];
    let mut end = vec![0usize; n];

    for (pos, inst) in m.insts.iter().enumerate() {
        for r in inst.defs() {
            if let Reg::V(v) = r {
                let v = v as usize;
                if v < n {
                    if pos < start[v] {
                        start[v] = pos;
                    }
                    if pos > end[v] {
                        end[v] = pos;
                    }
                }
            }
        }
        for r in inst.uses() {
            if let Reg::V(v) = r {
                let v = v as usize;
                if v < n {
                    if pos < start[v] {
                        start[v] = pos;
                    }
                    if pos > end[v] {
                        end[v] = pos;
                    }
                }
            }
        }
    }

    let blocks = split(&m.insts);
    let nb = blocks.len();
    let mut live_in: Vec<Vec<bool>> = vec![vec![false; n]; nb];
    let mut live_out: Vec<Vec<bool>> = vec![vec![false; n]; nb];

    let mut changed = true;
    while changed {
        changed = false;
        for bi in (0..nb).rev() {
            let mut out = vec![false; n];
            for s in &blocks[bi].succ {
                for v in 0..n {
                    if live_in[*s][v] {
                        out[v] = true;
                    }
                }
            }
            let mut ins = out.clone();
            for d in &blocks[bi].defs {
                ins[*d as usize] = false;
            }
            for u in &blocks[bi].uses {
                ins[*u as usize] = true;
            }
            if out != live_out[bi] || ins != live_in[bi] {
                live_out[bi] = out;
                live_in[bi] = ins;
                changed = true;
            }
        }
    }

    for bi in 0..nb {
        for v in 0..n {
            if live_in[bi][v] || live_out[bi][v] {
                let s = blocks[bi].start;
                let e = blocks[bi].end.saturating_sub(1);
                if s < start[v] {
                    start[v] = s;
                }
                if e > end[v] {
                    end[v] = e;
                }
            }
        }
    }

    let mut order: Vec<usize> = (0..n).filter(|i| start[*i] != usize::MAX).collect();
    order.sort_by_key(|i| (start[*i], end[*i]));

    let mut loc = vec![Loc::None; n];
    let mut free: Vec<u8> = ALLOCATABLE.to_vec();
    free.reverse();
    let mut active: Vec<(usize, usize, u8)> = Vec::new();
    let mut next_slot = first_slot;
    let mut used: Vec<u8> = Vec::new();

    for v in order {
        let s = start[v];
        let mut i = 0;
        while i < active.len() {
            if active[i].0 < s {
                let (_, _, r) = active.remove(i);
                free.push(r);
            } else {
                i += 1;
            }
        }
        if let Some(r) = free.pop() {
            loc[v] = Loc::Reg(r);
            if !used.contains(&r) {
                used.push(r);
            }
            active.push((end[v], v, r));
            continue;
        }
        let worst = active
            .iter()
            .enumerate()
            .max_by_key(|(_, (e, _, _))| *e)
            .map(|(i, _)| i);
        match worst {
            Some(wi) if active[wi].0 > end[v] => {
                let (_, wv, wr) = active.remove(wi);
                loc[wv] = Loc::Slot(-8 * (next_slot as i32 + 1));
                next_slot += 1;
                loc[v] = Loc::Reg(wr);
                active.push((end[v], v, wr));
            }
            _ => {
                loc[v] = Loc::Slot(-8 * (next_slot as i32 + 1));
                next_slot += 1;
            }
        }
    }

    Alloc {
        loc,
        slots: next_slot,
        used,
    }
}

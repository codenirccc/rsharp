use crate::cfg;
use crate::ir::*;
use crate::mem2reg;

pub fn run(f: &mut Func) {
    simplify_cfg(f);
    mem2reg::run(f);
    let mut rounds = 0;
    loop {
        let mut changed = false;
        changed |= constfold(f);
        changed |= dce(f);
        changed |= simplify_cfg(f);
        rounds += 1;
        if !changed || rounds > 32 {
            break;
        }
    }
}

fn cval(v: &Val) -> Option<i64> {
    match v {
        Val::C(n) => Some(*n),
        _ => None,
    }
}

fn norm(v: i64, ty: Ty) -> i64 {
    let bits = (ty.size() * 8).min(64);
    if bits >= 64 {
        v
    } else {
        let sh = 64 - bits;
        (v << sh) >> sh
    }
}

fn unorm(v: i64, ty: Ty) -> i64 {
    let bits = (ty.size() * 8).min(64);
    if bits >= 64 {
        v
    } else {
        v & ((1i64 << bits) - 1)
    }
}

fn eval_bin(op: BinOp, ty: Ty, a0: i64, b0: i64) -> Option<i64> {
    let a = norm(a0, ty);
    let b = norm(b0, ty);
    let r = match op {
        BinOp::Add => norm(a.wrapping_add(b), ty),
        BinOp::Sub => norm(a.wrapping_sub(b), ty),
        BinOp::Mul => norm(a.wrapping_mul(b), ty),
        BinOp::SDiv => {
            if b == 0 {
                return None;
            }
            norm(a.wrapping_div(b), ty)
        }
        BinOp::UDiv => {
            let ub = unorm(b, ty) as u64;
            if ub == 0 {
                return None;
            }
            norm((unorm(a, ty) as u64 / ub) as i64, ty)
        }
        BinOp::And => norm(a & b, ty),
        BinOp::Or => norm(a | b, ty),
        BinOp::Xor => norm(a ^ b, ty),
        BinOp::Shl => {
            if !(0..64).contains(&b) {
                return None;
            }
            norm(a.wrapping_shl(b as u32), ty)
        }
        BinOp::Sar => {
            if !(0..64).contains(&b) {
                return None;
            }
            norm(a.wrapping_shr(b as u32), ty)
        }
        BinOp::Shr => {
            if !(0..64).contains(&b) {
                return None;
            }
            norm(unorm(a, ty).wrapping_shr(b as u32), ty)
        }
    };
    Some(r)
}

fn eval_cmp(op: CmpOp, ty: Ty, a0: i64, b0: i64) -> bool {
    let a = norm(a0, ty);
    let b = norm(b0, ty);
    let ua = unorm(a, ty) as u64;
    let ub = unorm(b, ty) as u64;
    match op {
        CmpOp::Eq => a == b,
        CmpOp::Ne => a != b,
        CmpOp::Slt => a < b,
        CmpOp::Sle => a <= b,
        CmpOp::Sgt => a > b,
        CmpOp::Sge => a >= b,
        CmpOp::Ult => ua < ub,
        CmpOp::Ule => ua <= ub,
        CmpOp::Ugt => ua > ub,
        CmpOp::Uge => ua >= ub,
    }
}

fn mask(bits: u32) -> i64 {
    if bits >= 64 {
        -1
    } else {
        (1i64 << bits) - 1
    }
}

fn eval_cast(op: CastOp, from: Ty, to: Ty, v: i64) -> i64 {
    let fb = (from.size() * 8).min(64);
    match op {
        CastOp::Trunc => v & mask((to.size() * 8).min(64)),
        CastOp::Zext => v & mask(fb),
        CastOp::Sext => {
            let shift = 64 - fb;
            (v << shift) >> shift
        }
    }
}

fn subst(f: &mut Func, from: Val, to: Val) {
    f.for_each_value_mut(|v| {
        if v == &from {
            *v = to.clone();
        }
    });
}

pub fn constfold(f: &mut Func) -> bool {
    let mut changed = false;
    for bi in 0..f.blocks.len() {
        let mut folded: Vec<(u32, i64)> = Vec::new();
        for i in &f.blocks[bi].insts {
            let r = match i {
                Inst::Bin {
                    op, ty, lhs, rhs, dst, ..
                } => match (cval(lhs), cval(rhs)) {
                    (Some(a), Some(b)) => eval_bin(*op, *ty, a, b).map(|v| (*dst, v)),
                    _ => None,
                },
                Inst::Icmp {
                    op, ty, lhs, rhs, dst, ..
                } => match (cval(lhs), cval(rhs)) {
                    (Some(a), Some(b)) => {
                        Some((*dst, if eval_cmp(*op, *ty, a, b) { 1 } else { 0 }))
                    }
                    _ => None,
                },
                Inst::Cast {
                    op, from, val, to, dst,
                } => cval(val).map(|v| (*dst, eval_cast(*op, *from, *to, v))),
                Inst::Select { cond, a, b, dst, .. } => cval(cond).and_then(|c| {
                    let pick = if c != 0 { a } else { b };
                    cval(pick).map(|v| (*dst, v))
                }),
                Inst::Phi { incoming, dst, .. } => {
                    let vals: Vec<Option<i64>> =
                        incoming.iter().map(|(v, _)| cval(v)).collect();
                    if !vals.is_empty() && vals.iter().all(|v| *v == vals[0]) {
                        vals[0].map(|v| (*dst, v))
                    } else {
                        None
                    }
                }
                _ => None,
            };
            if let Some(x) = r {
                folded.push(x);
            }
        }
        if folded.is_empty() {
            continue;
        }
        changed = true;
        for (dst, v) in folded {
            subst(f, Val::V(dst), Val::C(v));
            f.blocks[bi].insts.retain(|i| i.dst() != Some(dst));
        }
    }
    changed
}

pub fn dce(f: &mut Func) -> bool {
    let mut changed = false;
    loop {
        let uses = count_uses(f);
        let mut removed = false;
        for b in f.blocks.iter_mut() {
            let before = b.insts.len();
            b.insts.retain(|i| {
                if !i.is_pure() {
                    return true;
                }
                match i.dst() {
                    Some(d) => uses.contains_key(&d),
                    None => true,
                }
            });
            if b.insts.len() != before {
                removed = true;
            }
        }
        if !removed {
            break;
        }
        changed = true;
    }
    changed
}

pub fn simplify_cfg(f: &mut Func) -> bool {
    let mut changed = remove_unreachable(f);
    for _ in 0..64 {
        let mut progress = false;
        let preds = cfg::preds(f);
        let mut merged_any = false;
        let mut cut: Vec<(usize, usize)> = Vec::new();
        for b in 0..f.blocks.len() {
            let target = match &f.blocks[b].term {
                Term::Br(t) => *t,
                Term::CondBr { cond, t, f: fb } => match cval(cond) {
                    Some(c) => {
                        let (take, dead) = if c != 0 { (*t, *fb) } else { (*fb, *t) };
                        f.blocks[b].term = Term::Br(take);
                        if dead != take {
                            cut.push((dead, b));
                        }
                        progress = true;
                        take
                    }
                    None => continue,
                },
                Term::Ret(_) => continue,
            };
            if target == b || target == f.entry {
                continue;
            }
            if preds[target].len() != 1 {
                continue;
            }
            let has_phi = f.blocks[target]
                .insts
                .iter()
                .any(|i| matches!(i, Inst::Phi { .. }));
            if has_phi {
                continue;
            }
            let tail = std::mem::take(&mut f.blocks[target].insts);
            let term = f.blocks[target].term.clone();
            f.blocks[b].insts.extend(tail);
            f.blocks[b].term = term;
            merged_any = true;
            progress = true;
        }
        for (dead, pred) in cut {
            drop_phi_incoming(f, dead, pred);
        }
        if merged_any {
            changed = true;
            remove_unreachable(f);
        }
        if !progress {
            break;
        }
    }
    changed
}

fn drop_phi_incoming(f: &mut Func, block: usize, pred: usize) {
    if block >= f.blocks.len() {
        return;
    }
    for inst in f.blocks[block].insts.iter_mut() {
        if let Inst::Phi { incoming, .. } = inst {
            incoming.retain(|(_, p)| *p != pred);
        }
    }
}

fn remove_unreachable(f: &mut Func) -> bool {
    let reach = cfg::reachable(f);
    if reach.iter().all(|x| *x) {
        return false;
    }
    let n = f.blocks.len();
    let mut map = vec![usize::MAX; n];
    let mut keep = Vec::new();
    for i in 0..n {
        if reach[i] {
            map[i] = keep.len();
            keep.push(i);
        }
    }
    let blocks = std::mem::take(&mut f.blocks);
    let mut out: Vec<Block> = Vec::new();
    for i in keep {
        let mut b = blocks[i].clone();
        match &mut b.term {
            Term::Br(t) => *t = map[*t],
            Term::CondBr { t, f: fb, .. } => {
                *t = map[*t];
                *fb = map[*fb];
            }
            Term::Ret(_) => {}
        }
        out.push(b);
    }
    f.blocks = out;
    for b in f.blocks.iter_mut() {
        for i in b.insts.iter_mut() {
            if let Inst::Phi { incoming, .. } = i {
                incoming.retain_mut(|(_, p)| {
                    if *p < map.len() && map[*p] != usize::MAX {
                        *p = map[*p];
                        true
                    } else {
                        false
                    }
                });
            }
        }
    }
    true
}

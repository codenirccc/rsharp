use std::collections::{HashMap, HashSet};

use crate::cfg;
use crate::dom;
use crate::ir::*;

pub fn run(f: &mut Func) {
    let n = f.blocks.len();
    if n == 0 {
        return;
    }

    let mut escapes: HashSet<u32> = HashSet::new();
    for b in &f.blocks {
        for i in &b.insts {
            let uses: Vec<Val> = match i {
                Inst::Load { .. } => vec![],
                Inst::Store { val, .. } => vec![val.clone()],
                other => other.uses(),
            };
            for u in uses {
                if let Val::V(v) = u {
                    escapes.insert(v);
                }
            }
        }
        for u in b.term.uses() {
            if let Val::V(v) = u {
                escapes.insert(v);
            }
        }
    }

    let mut promoted: HashMap<u32, Ty> = HashMap::new();
    for b in &f.blocks {
        for i in &b.insts {
            if let Inst::Alloca { ty, count, dst } = i {
                if *count == 1 && !escapes.contains(dst) {
                    promoted.insert(*dst, *ty);
                }
            }
        }
    }
    if promoted.is_empty() {
        return;
    }

    let mut def_blocks: HashMap<u32, Vec<usize>> = HashMap::new();
    for a in promoted.keys() {
        def_blocks.insert(*a, Vec::new());
    }
    for (bi, b) in f.blocks.iter().enumerate() {
        for i in &b.insts {
            if let Inst::Store { ptr: Val::V(a), .. } = i {
                if let Some(d) = def_blocks.get_mut(a) {
                    if !d.contains(&bi) {
                        d.push(bi);
                    }
                }
            }
        }
    }

    let dt = dom::build(f);
    let df = dom::frontiers(f, &dt);

    let mut phi_at: HashMap<(usize, u32), u32> = HashMap::new();
    let mut phi_alloca: HashMap<u32, u32> = HashMap::new();
    for (a, ty) in promoted.iter() {
        let mut work = def_blocks.get(a).cloned().unwrap_or_default();
        let mut placed: HashSet<usize> = HashSet::new();
        let mut seen: HashSet<usize> = work.iter().copied().collect();
        while let Some(b) = work.pop() {
            for &d in &df[b] {
                if placed.contains(&d) {
                    continue;
                }
                let id = f.new_value(*ty);
                f.blocks[d].insts.insert(
                    0,
                    Inst::Phi {
                        ty: *ty,
                        incoming: Vec::new(),
                        dst: id,
                    },
                );
                placed.insert(d);
                phi_at.insert((d, *a), id);
                phi_alloca.insert(id, *a);
                if seen.insert(d) {
                    work.push(d);
                }
            }
        }
    }

    let mut stacks: HashMap<u32, Vec<Val>> = HashMap::new();
    for a in promoted.keys() {
        stacks.insert(*a, Vec::new());
    }
    let mut replace: Vec<(u32, Val)> = Vec::new();
    let mut out_map: HashMap<usize, HashMap<u32, Val>> = HashMap::new();
    rename(
        f,
        &dt,
        0,
        &promoted,
        &phi_at,
        &mut stacks,
        &mut replace,
        &mut out_map,
    );

    for (old, new) in replace {
        let from = Val::V(old);
        f.for_each_value_mut(|v| {
            if v == &from {
                *v = new.clone();
            }
        });
    }

    let preds = cfg::preds(f);
    for bi in 0..f.blocks.len() {
        let mut updates: Vec<(u32, Vec<(Val, usize)>)> = Vec::new();
        for inst in &f.blocks[bi].insts {
            if let Inst::Phi { dst, .. } = inst {
                if let Some(a) = phi_alloca.get(dst) {
                    let mut inc = Vec::new();
                    for &p in &preds[bi] {
                        if let Some(m) = out_map.get(&p) {
                            if let Some(v) = m.get(a) {
                                inc.push((v.clone(), p));
                            }
                        }
                    }
                    updates.push((*dst, inc));
                }
            }
        }
        for (dst, inc) in updates {
            for inst in f.blocks[bi].insts.iter_mut() {
                if let Inst::Phi {
                    dst: d, incoming, ..
                } = inst
                {
                    if *d == dst {
                        *incoming = inc.clone();
                    }
                }
            }
        }
    }

    for b in f.blocks.iter_mut() {
        b.insts.retain(|i| match i {
            Inst::Alloca { dst, .. } => !promoted.contains_key(dst),
            Inst::Load { ptr: Val::V(a), .. } => !promoted.contains_key(a),
            Inst::Store { ptr: Val::V(a), .. } => !promoted.contains_key(a),
            _ => true,
        });
    }
}

#[allow(clippy::too_many_arguments)]
fn rename(
    f: &mut Func,
    dt: &dom::DomTree,
    b: usize,
    promoted: &HashMap<u32, Ty>,
    phi_at: &HashMap<(usize, u32), u32>,
    stacks: &mut HashMap<u32, Vec<Val>>,
    replace: &mut Vec<(u32, Val)>,
    out_map: &mut HashMap<usize, HashMap<u32, Val>>,
) {
    let mut pushed: Vec<u32> = Vec::new();
    for a in promoted.keys() {
        if let Some(id) = phi_at.get(&(b, *a)) {
            stacks.get_mut(a).unwrap().push(Val::V(*id));
            pushed.push(*a);
        }
    }

    let mut cur_out: HashMap<u32, Val> = HashMap::new();
    for a in promoted.keys() {
        if let Some(v) = stacks.get(a).and_then(|s| s.last()).cloned() {
            cur_out.insert(*a, v);
        }
    }

    let insts = std::mem::take(&mut f.blocks[b].insts);
    for i in &insts {
        match i {
            Inst::Store {
                val,
                ptr: Val::V(a),
                ..
            } if promoted.contains_key(a) => {
                stacks.get_mut(a).unwrap().push(val.clone());
                cur_out.insert(*a, val.clone());
            }
            Inst::Load {
                ptr: Val::V(a),
                dst,
                ..
            } if promoted.contains_key(a) => {
                if let Some(v) = stacks.get(a).and_then(|s| s.last()).cloned() {
                    replace.push((*dst, v));
                }
            }
            _ => {}
        }
    }
    f.blocks[b].insts = insts;

    out_map.insert(b, cur_out);

    let kids = dt.children[b].clone();
    for k in kids {
        rename(f, dt, k, promoted, phi_at, stacks, replace, out_map);
    }

    for a in pushed {
        stacks.get_mut(&a).unwrap().pop();
    }
}

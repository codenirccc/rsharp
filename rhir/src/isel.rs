use std::collections::HashMap;

use crate::ir::*;
use crate::mir::*;

struct Ctx {
    out: Vec<MInst>,
    slots: usize,
    phi_slot: HashMap<u32, i32>,
    next_label: u32,
    outgoing: usize,
}

impl Ctx {
    fn slot(&mut self, bytes: usize) -> i32 {
        let n = (bytes + 7) / 8;
        self.slots += n;
        -8 * (self.slots as i32)
    }

    fn push(&mut self, i: MInst) {
        self.out.push(i);
    }

    fn label(&mut self) -> u32 {
        self.next_label += 1;
        self.next_label
    }
}

fn src(v: &Val) -> Src {
    match v {
        Val::C(n) => Src::I(*n),
        Val::V(id) => Src::R(Reg::V(*id)),
        Val::Global(n) => Src::G(n.clone()),
    }
}

fn as_reg_in(ctx: &mut Ctx, v: &Val, scratch: u8) -> Reg {
    match v {
        Val::V(id) => Reg::V(*id),
        _ => {
            ctx.push(MInst::Mov {
                dst: Reg::P(scratch),
                src: src(v),
            });
            Reg::P(scratch)
        }
    }
}

fn as_reg(ctx: &mut Ctx, v: &Val) -> Reg {
    as_reg_in(ctx, v, RAX)
}

pub fn lower(f: &Func, m: &Module) -> Result<MFunc, String> {
    if f.params.len() > 8 {
        return Err(format!(
            "fn '{}' has {} parameters; the x64 backend supports 8",
            f.name,
            f.params.len()
        ));
    }
    let mut ctx = Ctx {
        out: Vec::new(),
        slots: 0,
        phi_slot: HashMap::new(),
        next_label: f.blocks.len() as u32,
        outgoing: 0,
    };

    for b in &f.blocks {
        for i in &b.insts {
            if let Inst::Phi { dst, .. } = i {
                let s = ctx.slot(8);
                ctx.phi_slot.insert(*dst, s);
            }
        }
    }

    let mut alloca_slot: HashMap<u32, i32> = HashMap::new();
    for b in &f.blocks {
        for i in &b.insts {
            if let Inst::Alloca { ty, count, dst } = i {
                let s = ctx.slot(*count as usize * ty.size() as usize);
                alloca_slot.insert(*dst, s);
            }
        }
    }

    for bi in 0..f.blocks.len() {
        ctx.push(MInst::Label(bi as u32));
        if bi == f.entry {
            for (i, (_ty, id)) in f.params.iter().enumerate() {
                if i < 4 {
                    ctx.push(MInst::Mov {
                        dst: Reg::V(*id),
                        src: Src::R(Reg::P(ARG_REGS[i])),
                    });
                } else {
                    ctx.push(MInst::Load {
                        ty: Ty::I64,
                        sign: false,
                        dst: Reg::V(*id),
                        base: Reg::P(RBP),
                        disp: 48 + 8 * (i as i32 - 4),
                    });
                }
            }
        }
        for inst in &f.blocks[bi].insts {
            lower_inst(&mut ctx, inst, &alloca_slot, m)?;
        }
        lower_term(&mut ctx, f, bi)?;
    }

    Ok(MFunc {
        insts: ctx.out,
        slots: ctx.slots,
        outgoing: ctx.outgoing,
    })
}

fn lower_inst(
    ctx: &mut Ctx,
    inst: &Inst,
    alloca_slot: &HashMap<u32, i32>,
    m: &Module,
) -> Result<(), String> {
    match inst {
        Inst::Phi { dst, .. } => {
            let disp = ctx.phi_slot[dst];
            ctx.push(MInst::Load {
                ty: Ty::I64,
                sign: false,
                dst: Reg::V(*dst),
                base: Reg::P(RBP),
                disp,
            });
        }
        Inst::Alloca { dst, .. } => {
            let disp = alloca_slot[dst];
            ctx.push(MInst::Lea {
                dst: Reg::V(*dst),
                base: Reg::P(RBP),
                index: None,
                disp,
            });
        }
        Inst::Load { ty, ptr, dst } => {
            let base = as_reg(ctx, ptr);
            ctx.push(MInst::Load {
                ty: *ty,
                sign: matches!(ty, Ty::I8 | Ty::I16 | Ty::I32),
                dst: Reg::V(*dst),
                base,
                disp: 0,
            });
        }
        Inst::Store { ty, val, ptr } => {
            let base = as_reg(ctx, ptr);
            let s = as_reg_in(ctx, val, R11);
            ctx.push(MInst::Store {
                ty: *ty,
                base,
                disp: 0,
                src: s,
            });
        }
        Inst::Gep { ty, ptr, idx, dst } => {
            let size = ty.size() as i64;
            let d = Reg::V(*dst);
            let base = as_reg(ctx, ptr);
            match idx {
                Val::C(n) => {
                    let off = n.saturating_mul(size);
                    if off >= i32::MIN as i64 && off <= i32::MAX as i64 {
                        ctx.push(MInst::Lea {
                            dst: d,
                            base,
                            index: None,
                            disp: off as i32,
                        });
                    } else {
                        let index = as_reg_in(ctx, idx, R10);
                        ctx.push(MInst::Lea {
                            dst: d,
                            base,
                            index: Some((index, size as u8)),
                            disp: 0,
                        });
                    }
                }
                Val::V(id) => ctx.push(MInst::Lea {
                    dst: d,
                    base,
                    index: Some((Reg::V(*id), size as u8)),
                    disp: 0,
                }),
                Val::Global(_) => return Err("a global cannot be a gep index".into()),
            }
        }
        Inst::Bin {
            op, ty, lhs, rhs, dst, ..
        } => {
            let d = Reg::V(*dst);
            let narrow = match ty {
                Ty::I8 | Ty::I16 | Ty::I32 => Some(*ty),
                _ => None,
            };
            match op {
                BinOp::Add
                | BinOp::Sub
                | BinOp::Mul
                | BinOp::And
                | BinOp::Or
                | BinOp::Xor => {
                    ctx.push(MInst::Mov {
                        dst: d,
                        src: src(lhs),
                    });
                    ctx.push(MInst::Bin {
                        op: match op {
                            BinOp::Add => MBin::Add,
                            BinOp::Sub => MBin::Sub,
                            BinOp::Mul => MBin::Mul,
                            BinOp::And => MBin::And,
                            BinOp::Or => MBin::Or,
                            _ => MBin::Xor,
                        },
                        dst: d,
                        src: src(rhs),
                    });
                }
                BinOp::SDiv | BinOp::UDiv => {
                    let unsigned = *op == BinOp::UDiv;
                    ctx.push(MInst::Mov {
                        dst: Reg::P(RAX),
                        src: src(lhs),
                    });
                    ctx.push(MInst::Mov {
                        dst: Reg::P(RCX),
                        src: src(rhs),
                    });
                    if unsigned {
                        // narrow values sit sign-extended in the register; unsigned div wants the raw bits
                        if let Some(t) = narrow {
                            ctx.push(MInst::Movzx {
                                from: t,
                                dst: Reg::P(RAX),
                                src: Reg::P(RAX),
                            });
                            ctx.push(MInst::Movzx {
                                from: t,
                                dst: Reg::P(RCX),
                                src: Reg::P(RCX),
                            });
                        }
                        ctx.push(MInst::Mov {
                            dst: Reg::P(RDX),
                            src: Src::I(0),
                        });
                    } else {
                        ctx.push(MInst::Cqo);
                    }
                    ctx.push(MInst::Div {
                        unsigned,
                        by: Reg::P(RCX),
                    });
                    ctx.push(MInst::Mov {
                        dst: d,
                        src: Src::R(Reg::P(RAX)),
                    });
                }
                BinOp::Shl | BinOp::Sar | BinOp::Shr => {
                    let bop = match op {
                        BinOp::Shl => MBin::Shl,
                        BinOp::Sar => MBin::Sar,
                        _ => MBin::Shr,
                    };
                    ctx.push(MInst::Mov {
                        dst: d,
                        src: src(lhs),
                    });
                    // a narrow value is stored sign-extended; a logical shift has to see the raw bits
                    if let (Some(t), BinOp::Shr) = (narrow, op) {
                        ctx.push(MInst::Movzx {
                            from: t,
                            dst: d,
                            src: d,
                        });
                    }
                    match rhs {
                        Val::C(n) => ctx.push(MInst::Bin {
                            op: bop,
                            dst: d,
                            src: Src::I(*n),
                        }),
                        Val::V(id) => {
                            ctx.push(MInst::Mov {
                                dst: Reg::P(RCX),
                                src: Src::R(Reg::V(*id)),
                            });
                            ctx.push(MInst::Bin {
                                op: bop,
                                dst: d,
                                src: Src::R(Reg::P(RCX)),
                            });
                        }
                        Val::Global(_) => return Err("a global cannot be a shift amount".into()),
                    }
                }
            }
            if let Some(t) = narrow {
                ctx.push(MInst::Movsx {
                    from: t,
                    dst: d,
                    src: d,
                });
            }
        }
        Inst::Icmp { op, lhs, rhs, dst, .. } => {
            let a = as_reg(ctx, lhs);
            ctx.push(MInst::Cmp { a, b: src(rhs) });
            ctx.push(MInst::Setcc {
                cc: op.cc(),
                dst: Reg::V(*dst),
            });
        }
        Inst::Cast {
            op, from, val, to, dst, ..
        } => {
            let d = Reg::V(*dst);
            let s = as_reg(ctx, val);
            match op {
                CastOp::Trunc => match to {
                    Ty::I1 => {
                        ctx.push(MInst::Mov {
                            dst: d,
                            src: Src::R(s),
                        });
                        ctx.push(MInst::Bin {
                            op: MBin::And,
                            dst: d,
                            src: Src::I(1),
                        });
                    }
                    Ty::I8 | Ty::I16 => ctx.push(MInst::Movzx {
                        from: *to,
                        dst: d,
                        src: s,
                    }),
                    Ty::I32 => ctx.push(MInst::Movsx {
                        from: Ty::I32,
                        dst: d,
                        src: s,
                    }),
                    _ => ctx.push(MInst::Mov {
                        dst: d,
                        src: Src::R(s),
                    }),
                },
                CastOp::Zext => match from {
                    Ty::I8 | Ty::I16 => ctx.push(MInst::Movzx {
                        from: *from,
                        dst: d,
                        src: s,
                    }),
                    Ty::I1 => {
                        ctx.push(MInst::Mov {
                            dst: d,
                            src: Src::R(s),
                        });
                        ctx.push(MInst::Bin {
                            op: MBin::And,
                            dst: d,
                            src: Src::I(1),
                        });
                    }
                    Ty::I32 => {
                        ctx.push(MInst::Mov {
                            dst: d,
                            src: Src::R(s),
                        });
                        ctx.push(MInst::Bin {
                            op: MBin::And,
                            dst: d,
                            src: Src::I(0xffff_ffff),
                        });
                    }
                    _ => ctx.push(MInst::Mov {
                        dst: d,
                        src: Src::R(s),
                    }),
                },
                CastOp::Sext => match from {
                    Ty::I8 | Ty::I16 | Ty::I32 => ctx.push(MInst::Movsx {
                        from: *from,
                        dst: d,
                        src: s,
                    }),
                    _ => ctx.push(MInst::Mov {
                        dst: d,
                        src: Src::R(s),
                    }),
                },
            }
        }
        Inst::Select {
            cond, a, b, dst, ..
        } => {
            let c = as_reg(ctx, cond);
            let l = ctx.label();
            ctx.push(MInst::Cmp {
                a: c,
                b: Src::I(0),
            });
            ctx.push(MInst::Mov {
                dst: Reg::V(*dst),
                src: src(a),
            });
            ctx.push(MInst::Jcc { cc: 5, label: l });
            ctx.push(MInst::Mov {
                dst: Reg::V(*dst),
                src: src(b),
            });
            ctx.push(MInst::Label(l));
        }
        Inst::Call {
            callee, args, dst, ..
        } => {
            if args.len() > 8 {
                return Err(format!(
                    "call to '{}' has {} arguments; the x64 backend supports 8",
                    callee,
                    args.len()
                ));
            }
            let variadic = m.extern_of(callee).map(|e| e.variadic).unwrap_or(false);
            let stack = args.len().saturating_sub(4);
            if stack > ctx.outgoing {
                ctx.outgoing = stack;
            }
            for (i, (_, v)) in args.iter().enumerate().skip(4) {
                let r = as_reg(ctx, v);
                ctx.push(MInst::Store {
                    ty: Ty::I64,
                    base: Reg::P(RSP),
                    disp: 32 + 8 * (i as i32 - 4),
                    src: r,
                });
            }
            for (i, (_, v)) in args.iter().enumerate().take(4) {
                ctx.push(MInst::Mov {
                    dst: Reg::P(ARG_REGS[i]),
                    src: src(v),
                });
            }
            if variadic {
                ctx.push(MInst::Mov {
                    dst: Reg::P(RAX),
                    src: Src::I(0),
                });
            }
            ctx.push(MInst::Call {
                target: callee.clone(),
                args: Vec::new(),
                dst: dst.map(Reg::V),
                variadic,
            });
        }
    }
    Ok(())
}

fn has_phis(f: &Func, b: usize) -> bool {
    f.blocks[b]
        .insts
        .iter()
        .any(|i| matches!(i, Inst::Phi { .. }))
}

fn edge_copies(ctx: &mut Ctx, f: &Func, pred: usize, succ: usize) {
    for inst in &f.blocks[succ].insts {
        if let Inst::Phi { incoming, dst, .. } = inst {
            let slot = ctx.phi_slot[dst];
            if let Some((v, _)) = incoming.iter().find(|(_, p)| *p == pred) {
                match v {
                    Val::V(id) => ctx.push(MInst::Store {
                        ty: Ty::I64,
                        base: Reg::P(RBP),
                        disp: slot,
                        src: Reg::V(*id),
                    }),
                    other => {
                        ctx.push(MInst::Mov {
                            dst: Reg::P(RAX),
                            src: src(other),
                        });
                        ctx.push(MInst::Store {
                            ty: Ty::I64,
                            base: Reg::P(RBP),
                            disp: slot,
                            src: Reg::P(RAX),
                        });
                    }
                }
            }
        }
    }
}

fn lower_term(ctx: &mut Ctx, f: &Func, bi: usize) -> Result<(), String> {
    match &f.blocks[bi].term {
        Term::Ret(None) => ctx.push(MInst::Ret),
        Term::Ret(Some((_ty, v))) => {
            ctx.push(MInst::Mov {
                dst: Reg::P(RAX),
                src: src(v),
            });
            ctx.push(MInst::Ret);
        }
        Term::Br(t) => {
            if has_phis(f, *t) {
                edge_copies(ctx, f, bi, *t);
            }
            ctx.push(MInst::Jmp(*t as u32));
        }
        Term::CondBr { cond, t, f: fb } => {
            let c = as_reg(ctx, cond);
            if !has_phis(f, *t) && !has_phis(f, *fb) {
                ctx.push(MInst::Cmp {
                    a: c,
                    b: Src::I(0),
                });
                ctx.push(MInst::Jcc {
                    cc: 5,
                    label: *t as u32,
                });
                ctx.push(MInst::Jmp(*fb as u32));
                return Ok(());
            }
            let skip = ctx.label();
            ctx.push(MInst::Cmp {
                a: c,
                b: Src::I(0),
            });
            ctx.push(MInst::Jcc { cc: 4, label: skip });
            edge_copies(ctx, f, bi, *t);
            ctx.push(MInst::Jmp(*t as u32));
            ctx.push(MInst::Label(skip));
            edge_copies(ctx, f, bi, *fb);
            ctx.push(MInst::Jmp(*fb as u32));
        }
    }
    Ok(())
}

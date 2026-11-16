use std::collections::HashMap;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Ty {
    I1,
    I8,
    I16,
    I32,
    I64,
    Ptr,
}

impl Ty {
    pub fn size(self) -> u32 {
        match self {
            Ty::I1 | Ty::I8 => 1,
            Ty::I16 => 2,
            Ty::I32 => 4,
            Ty::I64 | Ty::Ptr => 8,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Ty::I1 => "i1",
            Ty::I8 => "i8",
            Ty::I16 => "i16",
            Ty::I32 => "i32",
            Ty::I64 => "i64",
            Ty::Ptr => "ptr",
        }
    }

    pub fn parse(s: &str) -> Option<Ty> {
        Some(match s {
            "i1" => Ty::I1,
            "i8" => Ty::I8,
            "i16" => Ty::I16,
            "i32" => Ty::I32,
            "i64" => Ty::I64,
            "ptr" => Ty::Ptr,
            _ => return None,
        })
    }

    pub fn is_int(self) -> bool {
        self != Ty::Ptr
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum BinOp {
    Add,
    Sub,
    Mul,
    SDiv,
    UDiv,
    And,
    Or,
    Xor,
    Shl,
    Sar,
    Shr,
}

impl BinOp {
    pub fn parse(s: &str) -> Option<BinOp> {
        Some(match s {
            "add" => BinOp::Add,
            "sub" => BinOp::Sub,
            "mul" => BinOp::Mul,
            "sdiv" => BinOp::SDiv,
            "udiv" => BinOp::UDiv,
            "and" => BinOp::And,
            "or" => BinOp::Or,
            "xor" => BinOp::Xor,
            "shl" => BinOp::Shl,
            "sar" => BinOp::Sar,
            "shr" => BinOp::Shr,
            _ => return None,
        })
    }

    pub fn name(self) -> &'static str {
        match self {
            BinOp::Add => "add",
            BinOp::Sub => "sub",
            BinOp::Mul => "mul",
            BinOp::SDiv => "sdiv",
            BinOp::UDiv => "udiv",
            BinOp::And => "and",
            BinOp::Or => "or",
            BinOp::Xor => "xor",
            BinOp::Shl => "shl",
            BinOp::Sar => "sar",
            BinOp::Shr => "shr",
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum CmpOp {
    Eq,
    Ne,
    Slt,
    Sle,
    Sgt,
    Sge,
    Ult,
    Ule,
    Ugt,
    Uge,
}

impl CmpOp {
    pub fn parse(s: &str) -> Option<CmpOp> {
        Some(match s {
            "eq" => CmpOp::Eq,
            "ne" => CmpOp::Ne,
            "slt" => CmpOp::Slt,
            "sle" => CmpOp::Sle,
            "sgt" => CmpOp::Sgt,
            "sge" => CmpOp::Sge,
            "ult" => CmpOp::Ult,
            "ule" => CmpOp::Ule,
            "ugt" => CmpOp::Ugt,
            "uge" => CmpOp::Uge,
            _ => return None,
        })
    }

    pub fn name(self) -> &'static str {
        match self {
            CmpOp::Eq => "eq",
            CmpOp::Ne => "ne",
            CmpOp::Slt => "slt",
            CmpOp::Sle => "sle",
            CmpOp::Sgt => "sgt",
            CmpOp::Sge => "sge",
            CmpOp::Ult => "ult",
            CmpOp::Ule => "ule",
            CmpOp::Ugt => "ugt",
            CmpOp::Uge => "uge",
        }
    }

    pub fn cc(self) -> u8 {
        match self {
            CmpOp::Eq => 4,
            CmpOp::Ne => 5,
            CmpOp::Slt => 12,
            CmpOp::Sle => 14,
            CmpOp::Sgt => 15,
            CmpOp::Sge => 13,
            CmpOp::Ult => 2,
            CmpOp::Ule => 6,
            CmpOp::Ugt => 7,
            CmpOp::Uge => 3,
        }
    }

    pub fn signed(self) -> bool {
        matches!(self, CmpOp::Slt | CmpOp::Sle | CmpOp::Sgt | CmpOp::Sge)
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum CastOp {
    Trunc,
    Zext,
    Sext,
}

impl CastOp {
    pub fn parse(s: &str) -> Option<CastOp> {
        Some(match s {
            "trunc" => CastOp::Trunc,
            "zext" => CastOp::Zext,
            "sext" => CastOp::Sext,
            _ => return None,
        })
    }

    pub fn name(self) -> &'static str {
        match self {
            CastOp::Trunc => "trunc",
            CastOp::Zext => "zext",
            CastOp::Sext => "sext",
        }
    }
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub enum Val {
    C(i64),
    V(u32),
    Global(String),
}

#[derive(Clone, Debug)]
pub enum Inst {
    Alloca {
        ty: Ty,
        count: u64,
        dst: u32,
    },
    Load {
        ty: Ty,
        ptr: Val,
        dst: u32,
    },
    Store {
        ty: Ty,
        val: Val,
        ptr: Val,
    },
    Gep {
        ty: Ty,
        ptr: Val,
        idx: Val,
        dst: u32,
    },
    Bin {
        op: BinOp,
        ty: Ty,
        lhs: Val,
        rhs: Val,
        dst: u32,
    },
    Icmp {
        op: CmpOp,
        ty: Ty,
        lhs: Val,
        rhs: Val,
        dst: u32,
    },
    Cast {
        op: CastOp,
        from: Ty,
        val: Val,
        to: Ty,
        dst: u32,
    },
    Select {
        ty: Ty,
        cond: Val,
        a: Val,
        b: Val,
        dst: u32,
    },
    Phi {
        ty: Ty,
        incoming: Vec<(Val, usize)>,
        dst: u32,
    },
    Call {
        ret: Ty,
        callee: String,
        args: Vec<(Ty, Val)>,
        dst: Option<u32>,
    },
}

impl Inst {
    pub fn dst(&self) -> Option<u32> {
        match self {
            Inst::Alloca { dst, .. }
            | Inst::Load { dst, .. }
            | Inst::Gep { dst, .. }
            | Inst::Bin { dst, .. }
            | Inst::Icmp { dst, .. }
            | Inst::Cast { dst, .. }
            | Inst::Select { dst, .. }
            | Inst::Phi { dst, .. } => Some(*dst),
            Inst::Call { dst, .. } => *dst,
            Inst::Store { .. } => None,
        }
    }

    pub fn is_pure(&self) -> bool {
        match self {
            Inst::Store { .. } => false,
            Inst::Call { .. } => false,
            Inst::Alloca { .. } => true,
            _ => true,
        }
    }

    pub fn uses(&self) -> Vec<Val> {
        match self {
            Inst::Alloca { .. } => vec![],
            Inst::Load { ptr, .. } => vec![ptr.clone()],
            Inst::Store { val, ptr, .. } => vec![val.clone(), ptr.clone()],
            Inst::Gep { ptr, idx, .. } => vec![ptr.clone(), idx.clone()],
            Inst::Bin { lhs, rhs, .. } => vec![lhs.clone(), rhs.clone()],
            Inst::Icmp { lhs, rhs, .. } => vec![lhs.clone(), rhs.clone()],
            Inst::Cast { val, .. } => vec![val.clone()],
            Inst::Select { cond, a, b, .. } => vec![cond.clone(), a.clone(), b.clone()],
            Inst::Phi { incoming, .. } => incoming.iter().map(|(v, _)| v.clone()).collect(),
            Inst::Call { args, .. } => args.iter().map(|(_, v)| v.clone()).collect(),
        }
    }

    pub fn replace_uses(&mut self, from: &Val, to: &Val) {
        let swap = |v: &mut Val| {
            if v == from {
                *v = to.clone();
            }
        };
        match self {
            Inst::Alloca { .. } => {}
            Inst::Load { ptr, .. } => swap(ptr),
            Inst::Store { val, ptr, .. } => {
                swap(val);
                swap(ptr)
            }
            Inst::Gep { ptr, idx, .. } => {
                swap(ptr);
                swap(idx)
            }
            Inst::Bin { lhs, rhs, .. } => {
                swap(lhs);
                swap(rhs)
            }
            Inst::Icmp { lhs, rhs, .. } => {
                swap(lhs);
                swap(rhs)
            }
            Inst::Cast { val, .. } => swap(val),
            Inst::Select { cond, a, b, .. } => {
                swap(cond);
                swap(a);
                swap(b)
            }
            Inst::Phi { incoming, .. } => {
                for (v, _) in incoming.iter_mut() {
                    swap(v)
                }
            }
            Inst::Call { args, .. } => {
                for (_, v) in args.iter_mut() {
                    swap(v)
                }
            }
        }
    }
}

#[derive(Clone, Debug)]
pub enum Term {
    Ret(Option<(Ty, Val)>),
    Br(usize),
    CondBr {
        cond: Val,
        t: usize,
        f: usize,
    },
}

impl Term {
    pub fn uses(&self) -> Vec<Val> {
        match self {
            Term::Ret(Some((_, v))) => vec![v.clone()],
            Term::Ret(None) => vec![],
            Term::Br(_) => vec![],
            Term::CondBr { cond, .. } => vec![cond.clone()],
        }
    }

    pub fn replace_uses(&mut self, from: &Val, to: &Val) {
        if let Term::CondBr { cond, .. } = self {
            if cond == from {
                *cond = to.clone();
            }
        }
        if let Term::Ret(Some((_, v))) = self {
            if v == from {
                *v = to.clone();
            }
        }
    }

    pub fn successors(&self) -> Vec<usize> {
        match self {
            Term::Ret(_) => vec![],
            Term::Br(b) => vec![*b],
            Term::CondBr { t, f, .. } => vec![*t, *f],
        }
    }
}

#[derive(Clone, Debug)]
pub struct Block {
    pub label: String,
    pub insts: Vec<Inst>,
    pub term: Term,
}

#[derive(Clone, Debug)]
pub struct Func {
    pub name: String,
    pub params: Vec<(Ty, u32)>,
    pub ret: Ty,
    pub blocks: Vec<Block>,
    pub values: Vec<Option<Ty>>,
    pub entry: usize,
}

impl Func {
    pub fn new(name: &str, params: Vec<(Ty, u32)>, ret: Ty) -> Func {
        Func {
            name: name.to_string(),
            params,
            ret,
            blocks: Vec::new(),
            values: Vec::new(),
            entry: 0,
        }
    }

    pub fn new_value(&mut self, ty: Ty) -> u32 {
        let id = self.values.len() as u32;
        self.values.push(Some(ty));
        id
    }

    pub fn ty_of(&self, v: u32) -> Ty {
        self.values
            .get(v as usize)
            .copied()
            .flatten()
            .unwrap_or(Ty::I64)
    }

    pub fn block_index(&self, label: &str) -> Option<usize> {
        self.blocks.iter().position(|b| b.label == label)
    }

    pub fn all_insts(&self) -> impl Iterator<Item = &Inst> {
        self.blocks.iter().flat_map(|b| b.insts.iter())
    }

    pub fn preds(&self) -> Vec<Vec<usize>> {
        let mut p = vec![Vec::new(); self.blocks.len()];
        for (i, b) in self.blocks.iter().enumerate() {
            for s in b.term.successors() {
                if s < p.len() {
                    p[s].push(i);
                }
            }
        }
        p
    }

    pub fn for_each_value_mut<F: FnMut(&mut Val)>(&mut self, mut f: F) {
        for b in self.blocks.iter_mut() {
            for i in b.insts.iter_mut() {
                match i {
                    Inst::Alloca { .. } => {}
                    Inst::Load { ptr, .. } => f(ptr),
                    Inst::Store { val, ptr, .. } => {
                        f(val);
                        f(ptr)
                    }
                    Inst::Gep { ptr, idx, .. } => {
                        f(ptr);
                        f(idx)
                    }
                    Inst::Bin { lhs, rhs, .. } => {
                        f(lhs);
                        f(rhs)
                    }
                    Inst::Icmp { lhs, rhs, .. } => {
                        f(lhs);
                        f(rhs)
                    }
                    Inst::Cast { val, .. } => f(val),
                    Inst::Select { cond, a, b, .. } => {
                        f(cond);
                        f(a);
                        f(b)
                    }
                    Inst::Phi { incoming, .. } => {
                        for (v, _) in incoming.iter_mut() {
                            f(v)
                        }
                    }
                    Inst::Call { args, .. } => {
                        for (_, v) in args.iter_mut() {
                            f(v)
                        }
                    }
                }
            }
            match &mut b.term {
                Term::Ret(Some((_, v))) => f(v),
                Term::CondBr { cond, .. } => f(cond),
                _ => {}
            }
        }
    }
}

#[derive(Clone, Debug)]
pub struct Extern {
    pub name: String,
    pub params: Vec<Ty>,
    pub ret: Ty,
    pub variadic: bool,
}

#[derive(Clone, Debug)]
pub struct Global {
    pub name: String,
    pub bytes: Vec<u8>,
    pub align: u32,
}

#[derive(Clone, Debug, Default)]
pub struct Module {
    pub globals: Vec<Global>,
    pub externs: Vec<Extern>,
    pub funcs: Vec<Func>,
}

impl Module {
    pub fn global(&self, name: &str) -> Option<&Global> {
        self.globals.iter().find(|g| g.name == name)
    }

    pub fn func(&self, name: &str) -> Option<&Func> {
        self.funcs.iter().find(|f| f.name == name)
    }

    pub fn extern_of(&self, name: &str) -> Option<&Extern> {
        self.externs.iter().find(|e| e.name == name)
    }
}

pub type Uses = HashMap<u32, usize>;

pub fn count_uses(f: &Func) -> Uses {
    let mut m = HashMap::new();
    for b in &f.blocks {
        for i in &b.insts {
            for v in i.uses() {
                if let Val::V(id) = v {
                    *m.entry(id).or_insert(0) += 1;
                }
            }
        }
        for v in b.term.uses() {
            if let Val::V(id) = v {
                *m.entry(id).or_insert(0) += 1;
            }
        }
    }
    m
}

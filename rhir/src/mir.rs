use crate::ir::Ty;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Reg {
    V(u32),
    P(u8),
}

pub const RAX: u8 = 0;
pub const RCX: u8 = 1;
pub const RDX: u8 = 2;
pub const RBX: u8 = 3;
pub const RSP: u8 = 4;
pub const RBP: u8 = 5;
pub const RSI: u8 = 6;
pub const RDI: u8 = 7;
pub const R8: u8 = 8;
pub const R9: u8 = 9;
pub const R10: u8 = 10;
pub const R11: u8 = 11;
pub const R12: u8 = 12;
pub const R13: u8 = 13;
pub const R14: u8 = 14;
pub const R15: u8 = 15;

pub const ALLOCATABLE: [u8; 7] = [RBX, RSI, RDI, R12, R13, R14, R15];
pub const ARG_REGS: [u8; 4] = [RCX, RDX, R8, R9];

#[derive(Clone, Debug)]
pub enum Src {
    R(Reg),
    I(i64),
    G(String),
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum MBin {
    Add,
    Sub,
    Mul,
    And,
    Or,
    Xor,
    Shl,
    Sar,
    Shr,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum MUn {
    Neg,
    Not,
}

#[derive(Clone, Debug)]
pub enum MInst {
    Mov {
        dst: Reg,
        src: Src,
    },
    Bin {
        op: MBin,
        dst: Reg,
        src: Src,
    },
    Un {
        op: MUn,
        dst: Reg,
    },
    Cmp {
        a: Reg,
        b: Src,
    },
    Setcc {
        cc: u8,
        dst: Reg,
    },
    Jmp(u32),
    Jcc {
        cc: u8,
        label: u32,
    },
    Label(u32),
    Load {
        ty: Ty,
        sign: bool,
        dst: Reg,
        base: Reg,
        disp: i32,
    },
    Store {
        ty: Ty,
        base: Reg,
        disp: i32,
        src: Reg,
    },
    Lea {
        dst: Reg,
        base: Reg,
        index: Option<(Reg, u8)>,
        disp: i32,
    },
    Movsx {
        from: Ty,
        dst: Reg,
        src: Reg,
    },
    Movzx {
        from: Ty,
        dst: Reg,
        src: Reg,
    },
    Call {
        target: String,
        args: Vec<Src>,
        dst: Option<Reg>,
        variadic: bool,
    },
    Cqo,
    Div {
        unsigned: bool,
        by: Reg,
    },
    Ret,
}

pub struct MFunc {
    pub insts: Vec<MInst>,
    pub slots: usize,
    pub outgoing: usize,
}

impl MInst {
    pub fn defs(&self) -> Vec<Reg> {
        match self {
            MInst::Mov { dst, .. }
            | MInst::Bin { dst, .. }
            | MInst::Un { dst, .. }
            | MInst::Setcc { dst, .. }
            | MInst::Load { dst, .. }
            | MInst::Lea { dst, .. }
            | MInst::Movsx { dst, .. }
            | MInst::Movzx { dst, .. } => vec![*dst],
            MInst::Call { dst, .. } => dst.iter().copied().collect(),
            _ => vec![],
        }
    }

    pub fn uses(&self) -> Vec<Reg> {
        let mut v = Vec::new();
        match self {
            MInst::Mov { src, .. } | MInst::Bin { src, .. } => {
                if let Src::R(r) = src {
                    v.push(*r)
                }
            }
            MInst::Cmp { a, b } => {
                v.push(*a);
                if let Src::R(r) = b {
                    v.push(*r)
                }
            }
            MInst::Load { base, .. } => v.push(*base),
            MInst::Store { base, src, .. } => {
                v.push(*base);
                v.push(*src)
            }
            MInst::Lea { base, index, .. } => {
                v.push(*base);
                if let Some((r, _)) = index {
                    v.push(*r)
                }
            }
            MInst::Movsx { src, .. } | MInst::Movzx { src, .. } => v.push(*src),
            MInst::Call { args, .. } => {
                for a in args {
                    if let Src::R(r) = a {
                        v.push(*r)
                    }
                }
            }
            MInst::Div { by, .. } => v.push(*by),
            _ => {}
        }
        v
    }
}

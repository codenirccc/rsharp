use std::collections::HashMap;

use crate::ir::Ty;
use crate::mir::*;
use crate::regalloc::{Alloc, Loc};

pub struct Code {
    pub bytes: Vec<u8>,
    pub calls: Vec<(usize, String)>,
    pub abs: Vec<(usize, String)>,
}

fn u32le(out: &mut Vec<u8>, v: u32) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn u64le(out: &mut Vec<u8>, v: u64) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn rex(out: &mut Vec<u8>, w: bool, r: u8, x: u8, b: u8) {
    let v = 0x40 | ((w as u8) << 3) | ((r >> 3) << 2) | ((x >> 3) << 1) | (b >> 3);
    if v != 0x40 {
        out.push(v);
    }
}

fn rex_always(out: &mut Vec<u8>, w: bool, r: u8, x: u8, b: u8) {
    let v = 0x40 | ((w as u8) << 3) | ((r >> 3) << 2) | ((x >> 3) << 1) | (b >> 3);
    out.push(v);
}

fn modrm(out: &mut Vec<u8>, md: u8, reg: u8, rm: u8) {
    out.push((md << 6) | ((reg & 7) << 3) | (rm & 7));
}

fn mem(out: &mut Vec<u8>, reg: u8, base: u8, disp: i32) {
    let rm = base & 7;
    let (md, sz) = if disp == 0 && rm != 5 {
        (0u8, 0u8)
    } else if (-128..=127).contains(&disp) {
        (1, 1)
    } else {
        (2, 4)
    };
    modrm(out, md, reg, rm);
    if rm == 4 {
        out.push(0x24);
    }
    match sz {
        0 => {}
        1 => out.push(disp as u8),
        _ => u32le(out, disp as u32),
    }
}

fn mov_rr(out: &mut Vec<u8>, dst: u8, src: u8) {
    rex(out, true, src, 0, dst);
    out.push(0x89);
    modrm(out, 3, src, dst);
}

fn mov_ri(out: &mut Vec<u8>, dst: u8, imm: i64) {
    rex(out, true, 0, 0, dst);
    out.push(0xB8 | (dst & 7));
    u64le(out, imm as u64);
}

fn mov_load(out: &mut Vec<u8>, dst: u8, base: u8, disp: i32) {
    rex(out, true, dst, 0, base);
    out.push(0x8B);
    mem(out, dst, base, disp);
}

fn mov_store(out: &mut Vec<u8>, base: u8, disp: i32, src: u8) {
    rex(out, true, src, 0, base);
    out.push(0x89);
    mem(out, src, base, disp);
}

fn store_sized(out: &mut Vec<u8>, ty: Ty, base: u8, disp: i32, src: u8) {
    match ty.size() {
        1 => {
            rex_always(out, false, src, 0, base);
            out.push(0x88);
            mem(out, src, base, disp);
        }
        2 => {
            out.push(0x66);
            rex(out, false, src, 0, base);
            out.push(0x89);
            mem(out, src, base, disp);
        }
        4 => {
            rex(out, false, src, 0, base);
            out.push(0x89);
            mem(out, src, base, disp);
        }
        _ => mov_store(out, base, disp, src),
    }
}

fn load_sized(out: &mut Vec<u8>, ty: Ty, sign: bool, dst: u8, base: u8, disp: i32) {
    match (ty.size(), sign) {
        (1, true) => {
            rex(out, true, dst, 0, base);
            out.push(0x0F);
            out.push(0xBE);
            mem(out, dst, base, disp);
        }
        (1, false) => {
            rex(out, true, dst, 0, base);
            out.push(0x0F);
            out.push(0xB6);
            mem(out, dst, base, disp);
        }
        (2, true) => {
            rex(out, true, dst, 0, base);
            out.push(0x0F);
            out.push(0xBF);
            mem(out, dst, base, disp);
        }
        (2, false) => {
            rex(out, true, dst, 0, base);
            out.push(0x0F);
            out.push(0xB7);
            mem(out, dst, base, disp);
        }
        (4, true) => {
            rex(out, true, dst, 0, base);
            out.push(0x63);
            mem(out, dst, base, disp);
        }
        (4, false) => {
            rex(out, false, dst, 0, base);
            out.push(0x8B);
            mem(out, dst, base, disp);
        }
        _ => mov_load(out, dst, base, disp),
    }
}

fn bin_rr(out: &mut Vec<u8>, op: MBin, dst: u8, src: u8) {
    match op {
        MBin::Mul => {
            rex(out, true, dst, 0, src);
            out.push(0x0F);
            out.push(0xAF);
            modrm(out, 3, dst, src);
        }
        MBin::Shl | MBin::Sar | MBin::Shr => {
            if src != RCX {
                mov_rr(out, RCX, src);
            }
            rex(out, true, 0, 0, dst);
            out.push(0xD3);
            modrm(out, 3, match op {
                MBin::Shl => 4,
                MBin::Sar => 7,
                _ => 5,
            }, dst);
        }
        _ => {
            let code = match op {
                MBin::Add => 0x01,
                MBin::Sub => 0x29,
                MBin::And => 0x21,
                MBin::Or => 0x09,
                _ => 0x31,
            };
            rex(out, true, src, 0, dst);
            out.push(code);
            modrm(out, 3, src, dst);
        }
    }
}

fn bin_imm(out: &mut Vec<u8>, op: MBin, dst: u8, imm: i32) {
    let ext = match op {
        MBin::Add => 0,
        MBin::Or => 1,
        MBin::And => 4,
        MBin::Sub => 5,
        MBin::Shl => 4,
        MBin::Shr => 5,
        MBin::Sar => 7,
        _ => 6,
    };
    if matches!(op, MBin::Shl | MBin::Sar | MBin::Shr) {
        rex(out, true, 0, 0, dst);
        out.push(0xC1);
        modrm(out, 3, ext, dst);
        out.push(imm as u8);
    } else {
        rex(out, true, 0, 0, dst);
        out.push(0x81);
        modrm(out, 3, ext, dst);
        u32le(out, imm as u32);
    }
}

fn cmp_rr(out: &mut Vec<u8>, a: u8, b: u8) {
    rex(out, true, b, 0, a);
    out.push(0x39);
    modrm(out, 3, b, a);
}

fn cmp_imm(out: &mut Vec<u8>, a: u8, imm: i32) {
    rex(out, true, 0, 0, a);
    out.push(0x81);
    modrm(out, 3, 7, a);
    u32le(out, imm as u32);
}

fn setcc(out: &mut Vec<u8>, cc: u8, dst: u8) {
    rex_always(out, false, 0, 0, dst);
    out.push(0x0F);
    out.push(0x90 | cc);
    modrm(out, 3, 0, dst);
}

fn movzx_rr(out: &mut Vec<u8>, from: Ty, dst: u8, src: u8) {
    match from.size() {
        1 => {
            rex(out, true, dst, 0, src);
            out.push(0x0F);
            out.push(0xB6);
        }
        2 => {
            rex(out, true, dst, 0, src);
            out.push(0x0F);
            out.push(0xB7);
        }
        _ => {
            rex(out, false, dst, 0, src);
            out.push(0x89);
        }
    }
    modrm(out, 3, dst, src);
}

fn movsx_rr(out: &mut Vec<u8>, from: Ty, dst: u8, src: u8) {
    match from.size() {
        1 => {
            rex(out, true, dst, 0, src);
            out.push(0x0F);
            out.push(0xBE);
        }
        2 => {
            rex(out, true, dst, 0, src);
            out.push(0x0F);
            out.push(0xBF);
        }
        _ => {
            rex(out, true, dst, 0, src);
            out.push(0x63);
        }
    }
    modrm(out, 3, dst, src);
}

fn lea_index(out: &mut Vec<u8>, dst: u8, base: u8, index: u8, scale: u8, disp: i32) {
    let sc = match scale {
        1 => 0u8,
        2 => 1,
        4 => 2,
        _ => 3,
    };
    rex(out, true, dst, index, base);
    out.push(0x8D);
    let (md, sz) = if disp == 0 && (base & 7) != 5 {
        (0u8, 0u8)
    } else if (-128..=127).contains(&disp) {
        (1, 1)
    } else {
        (2, 4)
    };
    modrm(out, md, dst, 4);
    out.push((sc << 6) | ((index & 7) << 3) | (base & 7));
    match sz {
        0 => {}
        1 => out.push(disp as u8),
        _ => u32le(out, disp as u32),
    }
}

fn lea(out: &mut Vec<u8>, dst: u8, base: u8, disp: i32) {
    rex(out, true, dst, 0, base);
    out.push(0x8D);
    mem(out, dst, base, disp);
}

fn push(out: &mut Vec<u8>, r: u8) {
    if r >= 8 {
        out.push(0x41);
    }
    out.push(0x50 | (r & 7));
}

struct E<'a> {
    out: Vec<u8>,
    alloc: &'a Alloc,
    rel: Vec<(usize, u32)>,
    calls: Vec<(usize, String)>,
    abs: Vec<(usize, String)>,
    labels: HashMap<u32, usize>,
    externs: &'a [String],
}

impl<'a> E<'a> {
    fn loc(&self, r: Reg) -> Loc {
        match r {
            Reg::P(p) => Loc::Reg(p),
            Reg::V(v) => self
                .alloc
                .loc
                .get(v as usize)
                .copied()
                .unwrap_or(Loc::None),
        }
    }

    fn op_reg(&mut self, r: Reg, scratch: u8) -> u8 {
        match self.loc(r) {
            Loc::Reg(x) => x,
            Loc::Slot(d) => {
                mov_load(&mut self.out, scratch, RBP, d);
                scratch
            }
            Loc::None => scratch,
        }
    }

    fn dst_setup(&mut self, r: Reg) -> (u8, Option<i32>) {
        match self.loc(r) {
            Loc::Reg(x) => (x, None),
            Loc::Slot(d) => (RAX, Some(d)),
            Loc::None => (RAX, None),
        }
    }

    fn dst_finish(&mut self, reg: u8, slot: Option<i32>) {
        if let Some(d) = slot {
            mov_store(&mut self.out, RBP, d, reg);
        }
    }

    fn inst(&mut self, i: &MInst) {
        match i {
            MInst::Mov { dst, src } => {
                let (d, slot) = self.dst_setup(*dst);
                match src {
                    Src::I(n) => mov_ri(&mut self.out, d, *n),
                    Src::G(name) => {
                        self.abs.push((self.out.len() + 2, name.clone()));
                        mov_ri(&mut self.out, d, 0);
                    }
                    Src::R(r) => {
                        let s = self.op_reg(*r, R11);
                        mov_rr(&mut self.out, d, s);
                    }
                }
                self.dst_finish(d, slot);
            }
            MInst::Bin { op, dst, src } => {
                let (d, slot) = self.dst_setup(*dst);
                match src {
                    Src::I(n) if fits_i32(*n) && *op != MBin::Mul => {
                        bin_imm(&mut self.out, *op, d, *n as i32)
                    }
                    Src::I(n) => {
                        mov_ri(&mut self.out, R11, *n);
                        bin_rr(&mut self.out, *op, d, R11);
                    }
                    Src::G(name) => {
                        let pos = self.out.len() + 2;
                        mov_ri(&mut self.out, R11, 0);
                        self.abs.push((pos, name.clone()));
                        bin_rr(&mut self.out, *op, d, R11);
                    }
                    Src::R(r) => {
                        let s = self.op_reg(*r, R11);
                        bin_rr(&mut self.out, *op, d, s);
                    }
                }
                self.dst_finish(d, slot);
            }
            MInst::Un { op, dst } => {
                let (d, slot) = self.dst_setup(*dst);
                rex(&mut self.out, true, 0, 0, d);
                self.out.push(0xF7);
                modrm(&mut self.out, 3, if *op == MUn::Neg { 3 } else { 2 }, d);
                self.dst_finish(d, slot);
            }
            MInst::Cmp { a, b } => {
                let ar = self.op_reg(*a, RAX);
                match b {
                    Src::I(n) if fits_i32(*n) => cmp_imm(&mut self.out, ar, *n as i32),
                    Src::I(n) => {
                        mov_ri(&mut self.out, R11, *n);
                        cmp_rr(&mut self.out, ar, R11);
                    }
                    Src::G(name) => {
                        let pos = self.out.len() + 2;
                        mov_ri(&mut self.out, R11, 0);
                        self.abs.push((pos, name.clone()));
                        cmp_rr(&mut self.out, ar, R11);
                    }
                    Src::R(r) => {
                        let br = self.op_reg(*r, R11);
                        cmp_rr(&mut self.out, ar, br);
                    }
                }
            }
            MInst::Setcc { cc, dst } => {
                let (d, slot) = self.dst_setup(*dst);
                setcc(&mut self.out, *cc, d);
                movzx_rr(&mut self.out, Ty::I1, d, d);
                self.dst_finish(d, slot);
            }
            MInst::Jmp(l) => {
                self.out.push(0xE9);
                self.rel.push((self.out.len(), *l));
                u32le(&mut self.out, 0);
            }
            MInst::Jcc { cc, label } => {
                self.out.push(0x0F);
                self.out.push(0x80 | cc);
                self.rel.push((self.out.len(), *label));
                u32le(&mut self.out, 0);
            }
            MInst::Label(l) => {
                self.labels.insert(*l, self.out.len());
            }
            MInst::Load {
                ty,
                sign,
                dst,
                base,
                disp,
            } => {
                let br = self.op_reg(*base, R10);
                let (d, slot) = self.dst_setup(*dst);
                load_sized(&mut self.out, *ty, *sign, d, br, *disp);
                self.dst_finish(d, slot);
            }
            MInst::Store {
                ty,
                base,
                disp,
                src,
            } => {
                let br = self.op_reg(*base, R10);
                let sr = self.op_reg(*src, R11);
                store_sized(&mut self.out, *ty, br, *disp, sr);
            }
            MInst::Lea {
                dst,
                base,
                index,
                disp,
            } => {
                let br = self.op_reg(*base, R10);
                let (d, slot) = self.dst_setup(*dst);
                match index {
                    None => lea(&mut self.out, d, br, *disp),
                    Some((ir, scale)) => {
                        let xr = self.op_reg(*ir, R11);
                        lea_index(&mut self.out, d, br, xr, *scale, *disp);
                    }
                }
                self.dst_finish(d, slot);
            }
            MInst::Movsx { from, dst, src } => {
                let s = self.op_reg(*src, R11);
                let (d, slot) = self.dst_setup(*dst);
                movsx_rr(&mut self.out, *from, d, s);
                self.dst_finish(d, slot);
            }
            MInst::Movzx { from, dst, src } => {
                let s = self.op_reg(*src, R11);
                let (d, slot) = self.dst_setup(*dst);
                movzx_rr(&mut self.out, *from, d, s);
                self.dst_finish(d, slot);
            }
            MInst::Call { target, dst, .. } => {
                if self.externs.iter().any(|x| x == target) {
                    let pos = self.out.len() + 2;
                    mov_ri(&mut self.out, RAX, 0);
                    self.abs.push((pos, target.clone()));
                    self.out.push(0xFF);
                    self.out.push(0x10);
                } else {
                    self.out.push(0xE8);
                    self.calls.push((self.out.len(), target.clone()));
                    u32le(&mut self.out, 0);
                }
                if let Some(dst) = dst {
                    let (d, slot) = self.dst_setup(*dst);
                    mov_rr(&mut self.out, d, RAX);
                    self.dst_finish(d, slot);
                }
            }
            MInst::Cqo => {
                self.out.push(0x48);
                self.out.push(0x99);
            }
            MInst::Div { unsigned, by } => {
                let r = self.op_reg(*by, R11);
                rex(&mut self.out, true, 0, 0, r);
                self.out.push(0xF7);
                modrm(&mut self.out, 3, if *unsigned { 6 } else { 7 }, r);
            }
            MInst::Ret => {
                self.out.push(0xE9);
                self.rel.push((self.out.len(), u32::MAX));
                u32le(&mut self.out, 0);
            }
        }
    }
}

fn fits_i32(n: i64) -> bool {
    n >= i32::MIN as i64 && n <= i32::MAX as i64
}

pub fn function(m: &MFunc, a: &Alloc, externs: &[String]) -> Code {
    let mut e = E {
        out: Vec::new(),
        alloc: a,
        rel: Vec::new(),
        calls: Vec::new(),
        abs: Vec::new(),
        labels: HashMap::new(),
        externs,
    };

    let k = a.used.len();
    let slots = a.slots;
    let saved_base = 8 * slots;
    let frame = {
        let raw = 32 + 8 * m.outgoing + saved_base + 8 * k;
        let mut f = (raw + 15) & !15;
        if f < raw {
            f += 16;
        }
        f
    };

    push(&mut e.out, RBP);
    mov_rr(&mut e.out, RBP, RSP);
    rex(&mut e.out, true, 0, 0, RSP);
    e.out.push(0x81);
    modrm(&mut e.out, 3, 5, RSP);
    u32le(&mut e.out, frame as u32);

    for (i, r) in a.used.iter().enumerate() {
        mov_store(&mut e.out, RBP, -(saved_base as i32 + 8 * (i as i32 + 1)), *r);
    }

    for i in &m.insts {
        e.inst(i);
    }

    let epilogue = e.out.len();
    for (i, r) in a.used.iter().enumerate() {
        mov_load(&mut e.out, *r, RBP, -(saved_base as i32 + 8 * (i as i32 + 1)));
    }
    rex(&mut e.out, true, 0, 0, RSP);
    e.out.push(0x81);
    modrm(&mut e.out, 3, 0, RSP);
    u32le(&mut e.out, frame as u32);
    e.out.push(0x5D);
    e.out.push(0xC3);

    e.labels.insert(u32::MAX, epilogue);

    for (pos, label) in &e.rel {
        let target = match e.labels.get(label) {
            Some(t) => *t,
            None => panic!("rhir: unresolved block label {}", label),
        };
        let rel = target as i64 - (*pos as i64 + 4);
        let rel = rel as i32;
        e.out[*pos..*pos + 4].copy_from_slice(&rel.to_le_bytes());
    }

    Code {
        bytes: e.out,
        calls: e.calls,
        abs: e.abs,
    }
}

pub fn entry_stub() -> Code {
    let mut out = Vec::new();
    let mut calls = Vec::new();
    let mut abs = Vec::new();

    out.push(0x48);
    out.push(0x83);
    out.push(0xEC);
    out.push(0x28);
    out.push(0xE8);
    calls.push((out.len(), "main".to_string()));
    u32le(&mut out, 0);
    mov_rr(&mut out, RCX, RAX);
    let pos = out.len() + 2;
    mov_ri(&mut out, RAX, 0);
    abs.push((pos, "ExitProcess".to_string()));
    out.push(0xFF);
    out.push(0x10);

    Code { bytes: out, calls, abs }
}

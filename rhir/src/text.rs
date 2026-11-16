use crate::ir::*;

#[derive(Clone, PartialEq, Debug)]
enum T {
    Pct(u32),
    At(String),
    Int(i64),
    Id(String),
    Sym(char),
    Str(Vec<u8>),
}

fn lex(line: &str) -> Result<Vec<T>, String> {
    let b: Vec<char> = line.chars().collect();
    let mut i = 0;
    let mut out = Vec::new();
    while i < b.len() {
        let c = b[i];
        if c.is_whitespace() {
            i += 1;
            continue;
        }
        match c {
            '%' => {
                i += 1;
                let start = i;
                while i < b.len() && b[i].is_ascii_digit() {
                    i += 1;
                }
                if start == i {
                    return Err("expected a number after '%'".into());
                }
                let n: String = b[start..i].iter().collect();
                out.push(T::Pct(n.parse().map_err(|_| "value number too large")?));
            }
            '@' => {
                i += 1;
                let start = i;
                while i < b.len() && (b[i].is_alphanumeric() || b[i] == '_' || b[i] == '.') {
                    i += 1;
                }
                if start == i {
                    return Err("expected a name after '@'".into());
                }
                out.push(T::At(b[start..i].iter().collect()));
            }
            '"' => {
                i += 1;
                let mut s: Vec<u8> = Vec::new();
                loop {
                    if i >= b.len() {
                        return Err("unterminated string literal".into());
                    }
                    let ch = b[i];
                    if ch == '"' {
                        i += 1;
                        break;
                    }
                    if ch == '\\' {
                        i += 1;
                        if i >= b.len() {
                            return Err("unterminated escape".into());
                        }
                        match b[i] {
                            'n' => s.push(b'\n'),
                            't' => s.push(b'\t'),
                            'r' => s.push(b'\r'),
                            '0' => s.push(0),
                            '\\' => s.push(b'\\'),
                            '"' => s.push(b'"'),
                            'x' => {
                                if i + 2 >= b.len() {
                                    return Err("short \\x escape".into());
                                }
                                let h: String = b[i + 1..i + 3].iter().collect();
                                let v = u8::from_str_radix(&h, 16).map_err(|_| "bad \\x escape")?;
                                s.push(v);
                                i += 2;
                            }
                            other => return Err(format!("unknown escape '\\{}'", other)),
                        }
                        i += 1;
                        continue;
                    }
                    let mut buf = [0u8; 4];
                    s.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                    i += 1;
                }
                out.push(T::Str(s));
            }
            '-' if i + 1 < b.len() && b[i + 1].is_ascii_digit() => {
                let start = i;
                i += 1;
                while i < b.len() && b[i].is_ascii_digit() {
                    i += 1;
                }
                let n: String = b[start..i].iter().collect();
                out.push(T::Int(n.parse().map_err(|_| "integer literal out of range")?));
            }
            c if c.is_ascii_digit() => {
                let start = i;
                while i < b.len() && b[i].is_ascii_digit() {
                    i += 1;
                }
                let n: String = b[start..i].iter().collect();
                out.push(T::Int(n.parse().map_err(|_| "integer literal out of range")?));
            }
            c if c.is_alphabetic() || c == '_' => {
                let start = i;
                while i < b.len() && (b[i].is_alphanumeric() || b[i] == '_') {
                    i += 1;
                }
                out.push(T::Id(b[start..i].iter().collect()));
            }
            c if ",[]()=->.{}".contains(c) => {
                out.push(T::Sym(c));
                i += 1;
            }
            other => return Err(format!("unexpected character '{}'", other)),
        }
    }
    Ok(out)
}

struct Cur {
    t: Vec<T>,
    i: usize,
}

impl Cur {
    fn new(t: Vec<T>) -> Cur {
        Cur { t, i: 0 }
    }

    fn peek(&self) -> Option<&T> {
        self.t.get(self.i)
    }

    fn bump(&mut self) -> Option<T> {
        let v = self.t.get(self.i).cloned();
        if v.is_some() {
            self.i += 1;
        }
        v
    }

    fn done(&self) -> bool {
        self.i >= self.t.len()
    }

    fn kw(&self, w: &str) -> bool {
        matches!(self.peek(), Some(T::Id(s)) if s == w)
    }

    fn sym(&mut self, c: char) -> bool {
        if self.peek() == Some(&T::Sym(c)) {
            self.i += 1;
            true
        } else {
            false
        }
    }

    fn expect_sym(&mut self, c: char) -> Result<(), String> {
        if self.sym(c) {
            Ok(())
        } else {
            Err(format!("expected '{}'", c))
        }
    }

    fn id(&mut self) -> Result<String, String> {
        match self.bump() {
            Some(T::Id(s)) => Ok(s),
            _ => Err("expected a word".into()),
        }
    }

    fn ty(&mut self) -> Result<Ty, String> {
        let s = self.id()?;
        Ty::parse(&s).ok_or_else(|| format!("unknown type '{}'", s))
    }

    fn maybe_ty(&mut self) {
        if let Some(T::Id(s)) = self.peek().cloned() {
            if Ty::parse(&s).is_some() {
                self.i += 1;
            }
        }
    }

    fn val(&mut self) -> Result<Val, String> {
        match self.bump() {
            Some(T::Pct(n)) => Ok(Val::V(n)),
            Some(T::Int(n)) => Ok(Val::C(n)),
            Some(T::At(s)) => Ok(Val::Global(s)),
            _ => Err("expected a value".into()),
        }
    }

    fn comma(&mut self) -> Result<(), String> {
        self.expect_sym(',')
    }
}

enum RawTerm {
    Ret(Option<(Ty, Val)>),
    Br(String),
    CondBr { cond: Val, t: String, f: String },
}

fn split_items(src: &str) -> Vec<&str> {
    src.lines().map(|l| l.trim()).filter(|l| !l.is_empty()).collect()
}

pub fn parse(src: &str) -> Result<Module, String> {
    let lines = split_items(src);
    let mut m = Module::default();
    let mut i = 0;
    while i < lines.len() {
        let line = lines[i];
        if line.starts_with("declare ") {
            m.externs.push(parse_declare(line)?);
            i += 1;
        } else if line.starts_with("global ") {
            m.globals.push(parse_global(line)?);
            i += 1;
        } else if line.starts_with("func ") {
            let mut body = Vec::new();
            i += 1;
            while i < lines.len() && lines[i] != "}" {
                body.push(lines[i]);
                i += 1;
            }
            if i >= lines.len() {
                return Err("function is missing its closing '}'".into());
            }
            i += 1;
            m.funcs.push(parse_func(line, &body)?);
        } else {
            return Err(format!("unrecognised top level line: {}", line));
        }
    }
    Ok(m)
}

fn parse_declare(line: &str) -> Result<Extern, String> {
    let mut c = Cur::new(lex(line)?);
    c.id()?;
    let ret = c.ty()?;
    let name = match c.bump() {
        Some(T::At(s)) => s,
        _ => return Err("declare needs an @name".into()),
    };
    c.expect_sym('(')?;
    let mut params = Vec::new();
    let mut variadic = false;
    loop {
        if c.sym(')') {
            break;
        }
        if c.done() {
            return Err("unterminated declare".into());
        }
        if c.sym('.') && c.sym('.') && c.sym('.') {
            variadic = true;
            continue;
        }
        params.push(c.ty()?);
        if !c.sym(',') {
            c.expect_sym(')')?;
            break;
        }
    }
    Ok(Extern {
        name,
        params,
        ret,
        variadic,
    })
}

fn parse_global(line: &str) -> Result<Global, String> {
    let mut c = Cur::new(lex(line)?);
    c.id()?;
    let name = match c.bump() {
        Some(T::At(s)) => s,
        _ => return Err("global needs an @name".into()),
    };
    c.expect_sym('=')?;
    let mut bytes = match c.bump() {
        Some(T::Str(s)) => s,
        _ => return Err("global needs a string value".into()),
    };
    bytes.push(0);
    Ok(Global {
        name,
        bytes,
        align: 1,
    })
}

fn parse_func(header: &str, body: &[&str]) -> Result<Func, String> {
    let mut c = Cur::new(lex(header)?);
    c.id()?;
    let name = match c.bump() {
        Some(T::At(s)) => s,
        Some(T::Id(s)) => s,
        _ => return Err("func needs a name".into()),
    };
    c.expect_sym('(')?;
    let mut f = Func::new(&name, Vec::new(), Ty::I64);
    let mut params = Vec::new();
    loop {
        if c.sym(')') {
            break;
        }
        if c.done() {
            return Err("unterminated parameter list".into());
        }
        let ty = c.ty()?;
        let pname = match c.bump() {
            Some(T::Pct(n)) => n,
            _ => return Err("parameter needs a %name".into()),
        };
        if pname as usize >= f.values.len() {
            f.values.resize(pname as usize + 1, None);
        }
        if f.values[pname as usize].is_some() {
            return Err(format!("value %{} is defined twice", pname));
        }
        f.values[pname as usize] = Some(ty);
        params.push((ty, pname));
        if !c.sym(',') {
            c.expect_sym(')')?;
            break;
        }
    }
    if !c.sym('-') {
        return Err("function header needs '->' and a return type".into());
    }
    c.expect_sym('>')?;
    let ret = c.ty()?;
    f.params = params;
    f.ret = ret;

    let mut labels: Vec<String> = Vec::new();
    for line in body {
        if let Some(l) = line.strip_suffix(':') {
            let l = l.trim();
            if labels.iter().any(|x| x == l) {
                return Err(format!("duplicate block label '{}'", l));
            }
            labels.push(l.to_string());
        }
    }
    if labels.is_empty() {
        return Err(format!("function '{}' has no blocks", name));
    }
    let index_of = |l: &str| -> Result<usize, String> {
        labels
            .iter()
            .position(|x| x == l)
            .ok_or_else(|| format!("branch to unknown label '{}'", l))
    };

    let mut blocks: Vec<Block> = Vec::new();
    let mut ended: Vec<bool> = Vec::new();
    for line in body {
        if let Some(l) = line.strip_suffix(':') {
            blocks.push(Block {
                label: l.trim().to_string(),
                insts: Vec::new(),
                term: Term::Ret(None),
            });
            ended.push(false);
            continue;
        }
        if blocks.is_empty() {
            return Err("instruction before the first block label".into());
        }
        let b = blocks.last_mut().unwrap();
        match parse_line(line, &mut f, &index_of)? {
            Line::Inst(inst) => {
                if *ended.last().unwrap() {
                    return Err(format!(
                        "block '{}' has instructions after its terminator",
                        b.label
                    ));
                }
                b.insts.push(inst)
            }
            Line::Term(t) => {
                if *ended.last().unwrap() {
                    return Err(format!("block '{}' has more than one terminator", b.label));
                }
                *ended.last_mut().unwrap() = true;
                b.term = match t {
                    RawTerm::Ret(v) => Term::Ret(v),
                    RawTerm::Br(l) => Term::Br(index_of(&l)?),
                    RawTerm::CondBr { cond, t, f } => Term::CondBr {
                        cond,
                        t: index_of(&t)?,
                        f: index_of(&f)?,
                    },
                }
            }
        }
    }
    for (i, b) in blocks.iter().enumerate() {
        if !ended[i] {
            return Err(format!("block '{}' has no terminator", b.label));
        }
    }
    f.blocks = blocks;
    let mut undefined: Option<u32> = None;
    for b in &f.blocks {
        for i in &b.insts {
            for u in i.uses() {
                if let Val::V(id) = u {
                    if f.values.get(id as usize).copied().flatten().is_none() {
                        undefined = Some(id);
                    }
                }
            }
        }
        for u in b.term.uses() {
            if let Val::V(id) = u {
                if f.values.get(id as usize).copied().flatten().is_none() {
                    undefined = Some(id);
                }
            }
        }
    }
    if let Some(id) = undefined {
        return Err(format!("value %{} is used but never defined", id));
    }
    Ok(f)
}

enum Line {
    Inst(Inst),
    Term(RawTerm),
}

fn take_dst(f: &mut Func, dst: Option<u32>, ty: Ty) -> Result<u32, String> {
    let d = dst.ok_or("this instruction needs a result name")?;
    if d as usize >= f.values.len() {
        f.values.resize(d as usize + 1, None);
    }
    if f.values[d as usize].is_some() {
        return Err(format!("value %{} is defined twice", d));
    }
    f.values[d as usize] = Some(ty);
    Ok(d)
}

fn parse_line(
    line: &str,
    f: &mut Func,
    index_of: &dyn Fn(&str) -> Result<usize, String>,
) -> Result<Line, String> {
    let mut c = Cur::new(lex(line)?);
    let dst = if let Some(T::Pct(n)) = c.peek().cloned() {
        c.bump();
        if !c.sym('=') {
            return Err("expected '=' after a value name".into());
        }
        Some(n)
    } else {
        None
    };

    let op = c.id()?;
    let out = match op.as_str() {
        "alloca" => {
            let ty = c.ty()?;
            c.comma()?;
            let count = match c.bump() {
                Some(T::Int(n)) if n > 0 => n as u64,
                _ => return Err("alloca needs a positive element count".into()),
            };
            Line::Inst(Inst::Alloca {
                ty,
                count,
                dst: take_dst(f, dst, Ty::Ptr)?,
            })
        }
        "load" => {
            let ty = c.ty()?;
            c.comma()?;
            if c.id()? != "ptr" {
                return Err("load needs a 'ptr' operand".into());
            }
            let ptr = c.val()?;
            Line::Inst(Inst::Load {
                ty,
                ptr,
                dst: take_dst(f, dst, ty)?,
            })
        }
        "store" => {
            let ty = c.ty()?;
            let val = c.val()?;
            c.comma()?;
            if c.id()? != "ptr" {
                return Err("store needs a 'ptr' operand".into());
            }
            let ptr = c.val()?;
            Line::Inst(Inst::Store { ty, val, ptr })
        }
        "gep" => {
            let ty = c.ty()?;
            c.comma()?;
            if c.id()? != "ptr" {
                return Err("gep needs a 'ptr' base".into());
            }
            let ptr = c.val()?;
            c.comma()?;
            let it = c.ty()?;
            if it != Ty::I64 && it != Ty::I32 {
                return Err("gep index must be i32 or i64".into());
            }
            let idx = c.val()?;
            Line::Inst(Inst::Gep {
                ty,
                ptr,
                idx,
                dst: take_dst(f, dst, Ty::Ptr)?,
            })
        }
        "add" | "sub" | "mul" | "sdiv" | "udiv" | "and" | "or" | "xor" | "shl" | "sar" | "shr" => {
            let bop = BinOp::parse(&op).unwrap();
            let ty = c.ty()?;
            let lhs = c.val()?;
            c.comma()?;
            let rhs = c.val()?;
            Line::Inst(Inst::Bin {
                op: bop,
                ty,
                lhs,
                rhs,
                dst: take_dst(f, dst, ty)?,
            })
        }
        "icmp" => {
            let o = c.id()?;
            let cop = CmpOp::parse(&o).ok_or_else(|| format!("unknown comparison '{}'", o))?;
            let ty = c.ty()?;
            let lhs = c.val()?;
            c.comma()?;
            let rhs = c.val()?;
            Line::Inst(Inst::Icmp {
                op: cop,
                ty,
                lhs,
                rhs,
                dst: take_dst(f, dst, Ty::I1)?,
            })
        }
        "trunc" | "zext" | "sext" => {
            let cop = CastOp::parse(&op).unwrap();
            let from = c.ty()?;
            let val = c.val()?;
            if c.id()? != "to" {
                return Err("cast needs 'to' before the target type".into());
            }
            let to = c.ty()?;
            Line::Inst(Inst::Cast {
                op: cop,
                from,
                val,
                to,
                dst: take_dst(f, dst, to)?,
            })
        }
        "select" => {
            let ty = c.ty()?;
            c.maybe_ty();
            let cond = c.val()?;
            c.comma()?;
            c.maybe_ty();
            let a = c.val()?;
            c.comma()?;
            c.maybe_ty();
            let b = c.val()?;
            Line::Inst(Inst::Select {
                ty,
                cond,
                a,
                b,
                dst: take_dst(f, dst, ty)?,
            })
        }
        "phi" => {
            let ty = c.ty()?;
            let mut raw = Vec::new();
            loop {
                c.expect_sym('[')?;
                let v = c.val()?;
                c.comma()?;
                let l = c.id()?;
                c.expect_sym(']')?;
                raw.push((v, l));
                if !c.sym(',') {
                    break;
                }
            }
            let d = take_dst(f, dst, ty)?;
            let incoming = raw
                .into_iter()
                .map(|(v, l)| Ok((v, index_of(&l)?)))
                .collect::<Result<Vec<_>, String>>()?;
            Line::Inst(Inst::Phi {
                ty,
                incoming,
                dst: d,
            })
        }
        "call" => {
            let ret = c.ty()?;
            let name = match c.bump() {
                Some(T::At(s)) => s,
                _ => return Err("call needs an @name".into()),
            };
            c.expect_sym('(')?;
            let mut args = Vec::new();
            loop {
                if c.sym(')') {
                    break;
                }
                if c.done() {
                    return Err("unterminated call".into());
                }
                let ty = c.ty()?;
                let v = c.val()?;
                args.push((ty, v));
                if !c.sym(',') {
                    c.expect_sym(')')?;
                    break;
                }
            }
            let d = if ret == Ty::I64 && dst.is_none() {
                None
            } else {
                Some(take_dst(f, dst, ret)?)
            };
            Line::Inst(Inst::Call {
                ret,
                callee: name,
                args,
                dst: d,
            })
        }
        "ret" => {
            if c.kw("void") {
                c.bump();
                Line::Term(RawTerm::Ret(None))
            } else {
                let ty = c.ty()?;
                let v = c.val()?;
                Line::Term(RawTerm::Ret(Some((ty, v))))
            }
        }
        "br" => Line::Term(RawTerm::Br(c.id()?)),
        "condbr" => {
            let cond = c.val()?;
            c.comma()?;
            let t = c.id()?;
            c.comma()?;
            let f = c.id()?;
            Line::Term(RawTerm::CondBr { cond, t, f })
        }
        other => return Err(format!("unknown instruction '{}'", other)),
    };
    Ok(out)
}

fn v(x: &Val) -> String {
    match x {
        Val::C(n) => format!("{}", n),
        Val::V(id) => format!("%{}", id),
        Val::Global(n) => format!("@{}", n),
    }
}

pub fn print_module(m: &Module) -> String {
    let mut s = String::new();
    for g in &m.globals {
        s.push_str(&format!("global @{} = \"", g.name));
        for b in &g.bytes[..g.bytes.len().saturating_sub(1)] {
            match *b {
                b'\n' => s.push_str("\\n"),
                b'\t' => s.push_str("\\t"),
                b'\r' => s.push_str("\\r"),
                b'"' => s.push_str("\\\""),
                b'\\' => s.push_str("\\\\"),
                0x20..=0x7e => s.push(*b as char),
                other => s.push_str(&format!("\\x{:02x}", other)),
            }
        }
        s.push_str("\"\n");
    }
    for e in &m.externs {
        s.push_str(&format!("declare {} @{}(", e.ret.name(), e.name));
        for (i, p) in e.params.iter().enumerate() {
            if i > 0 {
                s.push_str(", ");
            }
            s.push_str(p.name());
        }
        if e.variadic {
            if !e.params.is_empty() {
                s.push_str(", ");
            }
            s.push_str("...");
        }
        s.push_str(")\n");
    }
    for f in &m.funcs {
        s.push_str(&format!("\nfunc @{}(", f.name));
        for (i, (t, id)) in f.params.iter().enumerate() {
            if i > 0 {
                s.push_str(", ");
            }
            s.push_str(&format!("{} %{}", t.name(), id));
        }
        s.push_str(&format!(") -> {} {{\n", f.ret.name()));
        for b in &f.blocks {
            s.push_str(&format!("{}:\n", b.label));
            for i in &b.insts {
                s.push_str("  ");
                s.push_str(&print_inst(f, i));
                s.push('\n');
            }
            s.push_str("  ");
            s.push_str(&print_term(f, &b.term));
            s.push('\n');
        }
        s.push_str("}\n");
    }
    s
}

pub fn print_inst(f: &Func, i: &Inst) -> String {
    match i {
        Inst::Alloca { ty, count, dst } => {
            format!("%{} = alloca {}, {}", dst, ty.name(), count)
        }
        Inst::Load { ty, ptr, dst } => {
            format!("%{} = load {}, ptr {}", dst, ty.name(), v(ptr))
        }
        Inst::Store { ty, val, ptr } => {
            format!("store {} {}, ptr {}", ty.name(), v(val), v(ptr))
        }
        Inst::Gep { ty, ptr, idx, dst } => {
            format!("%{} = gep {}, ptr {}, i64 {}", dst, ty.name(), v(ptr), v(idx))
        }
        Inst::Bin { op, ty, lhs, rhs, dst } => format!(
            "%{} = {} {} {}, {}",
            dst,
            op.name(),
            ty.name(),
            v(lhs),
            v(rhs)
        ),
        Inst::Icmp { op, ty, lhs, rhs, dst } => format!(
            "%{} = icmp {} {} {}, {}",
            dst,
            op.name(),
            ty.name(),
            v(lhs),
            v(rhs)
        ),
        Inst::Cast { op, from, val, to, dst } => format!(
            "%{} = {} {} {} to {}",
            dst,
            op.name(),
            from.name(),
            v(val),
            to.name()
        ),
        Inst::Select { ty, cond, a, b, dst } => format!(
            "%{} = select {} {}, {}, {}",
            dst,
            ty.name(),
            v(cond),
            v(a),
            v(b)
        ),
        Inst::Phi { ty, incoming, dst } => {
            let mut s = format!("%{} = phi {}", dst, ty.name());
            for (i, (val, blk)) in incoming.iter().enumerate() {
                if i > 0 {
                    s.push(',');
                }
                let label = match f.blocks.get(*blk) {
                    Some(b) => b.label.clone(),
                    None => format!("%{}", blk),
                };
                s.push_str(&format!(" [ {}, {} ]", v(val), label));
            }
            s
        }
        Inst::Call {
            ret,
            callee,
            args,
            dst,
        } => {
            let mut s = match dst {
                Some(d) => format!("%{} = call {} @{}(", d, ret.name(), callee),
                None => format!("call {} @{}(", ret.name(), callee),
            };
            for (i, (t, val)) in args.iter().enumerate() {
                if i > 0 {
                    s.push_str(", ");
                }
                s.push_str(&format!("{} {}", t.name(), v(val)));
            }
            s.push(')');
            s
        }
    }
}

pub fn print_term(f: &Func, t: &Term) -> String {
    match t {
        Term::Ret(None) => "ret void".into(),
        Term::Ret(Some((ty, val))) => format!("ret {} {}", ty.name(), v(val)),
        Term::Br(b) => format!("br {}", f.blocks[*b].label),
        Term::CondBr { cond, t, f: fb } => {
            format!(
                "condbr {}, {}, {}",
                v(cond),
                f.blocks[*t].label,
                f.blocks[*fb].label
            )
        }
    }
}

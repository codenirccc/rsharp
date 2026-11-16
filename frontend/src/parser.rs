use crate::ast::*;
use crate::lexer::{Tok, Token};

fn is_reserved(s: &str) -> bool {
    matches!(
        s,
        "fn" | "let"
            | "var"
            | "const"
            | "if"
            | "else"
            | "while"
            | "loop"
            | "break"
            | "continue"
            | "return"
            | "struct"
            | "enum"
            | "for"
            | "in"
            | "match"
            | "extern"
            | "as"
            | "sizeof"
            | "zero"
            | "ptr"
            | "true"
            | "false"
            | "null"
            | "i8"
            | "i16"
            | "i32"
            | "i64"
            | "u8"
            | "u16"
            | "u32"
            | "u64"
            | "f32"
            | "f64"
            | "bool"
            | "void"
            | "unsafe"
            | "mut"
            | "box"
            | "Box"
            | "_"
            | "async"
            | "await"
            | "poll"
            | "mod"
            | "impl"
            | "static"
    )
}

#[derive(Clone, Copy, PartialEq)]
pub enum SelfKind {
    Shared,
    Exclusive,
}

pub struct Parser {
    toks: Vec<Token>,
    i: usize,
    lifts: Vec<FnDef>,
    clo: usize,
    methods: Vec<(String, String, SelfKind)>,
    pfx: String,
    tmpn: usize,
    tparams: Vec<String>,
}

impl Parser {
    pub fn new(toks: Vec<Token>) -> Self {
        Parser {
            toks,
            i: 0,
            lifts: Vec::new(),
            clo: 0,
            methods: Vec::new(),
            pfx: String::new(),
            tmpn: 0,
            tparams: Vec::new(),
        }
    }

    fn peek(&self) -> &Tok {
        &self.toks[self.i].tok
    }

    fn peek_at(&self, n: usize) -> Option<&Tok> {
        self.toks.get(self.i + n).map(|t| &t.tok)
    }

    fn cur(&self) -> &Token {
        &self.toks[self.i]
    }

    fn bump(&mut self) -> Token {
        if self.i + 1 < self.toks.len() {
            let t = std::mem::replace(&mut self.toks[self.i], Token {
                tok: Tok::Eof,
                line: 0,
                col: 0,
                start: 0,
                end: 0,
            });
            self.i += 1;
            t
        } else {
            self.toks[self.i].clone()
        }
    }

    fn take_ident(&mut self) -> Option<(String, u32, u32)> {
        if !matches!(self.peek(), Tok::Ident(_)) {
            return None;
        }
        let t = self.bump();
        let (line, col) = (t.line, t.col);
        match t.tok {
            Tok::Ident(s) => Some((s, line, col)),
            _ => None,
        }
    }

    fn err<T>(&self, msg: &str) -> Result<T, String> {
        let t = self.cur();
        Err(format!("line {}:{}: {}", t.line, t.col, msg))
    }

    fn at_sym(&self, s: &str) -> bool {
        matches!(self.peek(), Tok::Sym(x) if *x == s)
    }

    fn peek_int(&self) -> Option<i64> {
        match self.peek() {
            Tok::Int(n) => Some(*n),
            _ => None,
        }
    }

    fn peek_str(&self) -> Option<&str> {
        match self.peek() {
            Tok::Str(s) => Some(s),
            _ => None,
        }
    }

    fn eat_sym(&mut self, s: &str) -> bool {
        if self.at_sym(s) {
            self.bump();
            true
        } else {
            false
        }
    }

    fn expect_sym(&mut self, s: &str) -> Result<(), String> {
        if self.eat_sym(s) {
            Ok(())
        } else {
            self.err(&format!("expected '{}', found {}", s, describe(self.peek())))
        }
    }

    fn at_kw(&self, k: &str) -> bool {
        matches!(self.peek(), Tok::Ident(x) if x == k)
    }

    fn eat_kw(&mut self, k: &str) -> bool {
        if self.at_kw(k) {
            self.bump();
            true
        } else {
            false
        }
    }

    fn expect_kw(&mut self, k: &str) -> Result<(), String> {
        if self.eat_kw(k) {
            Ok(())
        } else {
            self.err(&format!("expected '{}', found {}", k, describe(self.peek())))
        }
    }

    fn expect_name(&mut self, want_upper: bool) -> Result<String, String> {
        let Some((name, line, col)) = self.take_ident() else {
            return self.err(&format!("expected a name, found {}", describe(self.peek())));
        };
        if is_reserved(&name) {
            return Err(format!("line {}:{}: '{}' is a reserved word", line, col, name));
        }
        let upper = name.chars().next().map(|c| c.is_ascii_uppercase()).unwrap_or(false);
        if want_upper && !upper {
            return Err(format!(
                "line {}:{}: type name '{}' must start with a capital letter",
                line, col, name
            ));
        }
        if !want_upper && upper {
            return Err(format!(
                "line {}:{}: value name '{}' must start with a lowercase letter",
                line, col, name
            ));
        }
        Ok(name)
    }

    fn name(&mut self) -> Result<String, String> {
        self.expect_name(false)
    }

    fn type_name(&mut self) -> Result<String, String> {
        self.expect_name(true)
    }

    fn type_param_name(&mut self) -> Result<String, String> {
        let Some((s, line, col)) = self.take_ident() else {
            return self.err(&format!(
                "expected a type parameter name, found {}",
                describe(self.peek())
            ));
        };
        if is_reserved(&s) {
            return Err(format!("line {}:{}: '{}' is a reserved word", line, col, s));
        }
        Ok(s)
    }

    fn const_name(&mut self) -> Result<String, String> {
        let Some((s, line, col)) = self.take_ident() else {
            return self.err(&format!("expected a name, found {}", describe(self.peek())));
        };
        if is_reserved(&s) {
            return Err(format!("line {}:{}: '{}' is a reserved word", line, col, s));
        }
        Ok(s)
    }

    pub fn parse_type(&mut self) -> Result<Type, String> {
        if self.eat_sym("(") {
            let mut items = Vec::new();
            if !self.at_sym(")") {
                loop {
                    items.push(self.parse_type()?);
                    if !self.eat_sym(",") {
                        break;
                    }
                }
            }
            self.expect_sym(")")?;
            if items.len() < 2 {
                return self.err("a tuple type needs at least two elements");
            }
            return Ok(Type::Tuple(items));
        }
        if self.at_kw("fn") {
            self.bump();
            self.expect_sym("(")?;            let mut params = Vec::new();
            if !self.at_sym(")") {
                loop {
                    params.push(self.parse_type()?);
                    if !self.eat_sym(",") {
                        break;
                    }
                }
            }
            self.expect_sym(")")?;
            let ret = if self.eat_sym("->") {
                self.parse_type()?
            } else {
                Type::Void
            };
            return Ok(Type::Fn(params, Box::new(ret)));
        }
        if self.at_kw("Task") {
            self.bump();
            self.expect_sym("<")?;
            let inner = self.parse_type()?;
            self.expect_sym(">")?;
            return Ok(Type::Task(Box::new(inner)));
        }
        if self.eat_sym("&") {
            let mutable = self.eat_kw("mut");
            let inner = self.parse_type()?;
            return Ok(Type::Ref(Box::new(inner), mutable));
        }
        if self.at_kw("Box") {
            self.bump();
            self.expect_sym("<")?;
            let inner = self.parse_type()?;
            self.expect_sym(">")?;
            return Ok(Type::Heap(Box::new(inner)));
        }
        if self.eat_kw("ptr") {
            self.expect_sym("<")?;
            let inner = self.parse_type()?;
            self.expect_sym(">")?;
            return Ok(Type::Ptr(Box::new(inner)));
        }
        if self.eat_sym("[") {
            let inner = self.parse_type()?;            self.expect_sym(";")?;
            let size = if let Some(n) = self.peek_int() {
                self.bump();
                if n < 0 {
                    return self.err("array size cannot be negative");
                }
                Size::Lit(n as u64)
            } else if matches!(self.peek(), Tok::Ident(_)) {
                let Some((s, line, col)) = self.take_ident() else {
                    return self.err("expected an array size");
                };
                if Type::from_name(&s).is_some() {
                    return Err(format!(
                        "line {}:{}: array size must be an integer literal or a const",
                        line, col
                    ));
                }
                Size::Name(format!("{}{}", self.pfx, s))
            } else {
                return self.err(&format!(
                    "expected an array size, found {}",
                    describe(self.peek())
                ));
            };
            self.expect_sym("]")?;
            return Ok(Type::Array(Box::new(inner), size));
        }
        let Some((s, tline, tcol)) = self.take_ident() else {
            return self.err(&format!("expected a type, found {}", describe(self.peek())));
        };
        {
            {
                let mut segs = vec![s];
                while self.at_sym("::") {
                    self.bump();
                    segs.push(self.raw_name()?);
                }
                if segs.len() == 1 {
                    if self.tparams.iter().any(|p| *p == segs[0]) {
                        return Ok(Type::Param(segs[0].clone()));
                    }
                    if let Some(ty) = Type::from_name(&segs[0]) {
                        return Ok(ty);
                    }
                    if segs[0].chars().next().map(|c| c.is_ascii_uppercase()).unwrap_or(false) {
                        return Ok(Type::Named(format!("{}{}", self.pfx, segs[0])));
                    }
                    return Err(format!("line {}:{}: unknown type '{}'", tline, tcol, segs[0]));
                }
                let last = segs.last().unwrap();
                if !last.chars().next().map(|c| c.is_ascii_uppercase()).unwrap_or(false) {
                    return Err(format!(
                        "line {}:{}: '{}' is not a type; type names start with a capital letter",
                        tline, tcol, last
                    ));
                }
                Ok(Type::Named(format!("{}{}", self.pfx, segs.join("__"))))
            }
        }
    }

    pub fn parse_program(&mut self) -> Result<Program, String> {
        let mut p = Program::default();
        self.parse_items(&mut p, true)?;
        p.fns.append(&mut self.lifts);
        resolve_methods(&mut p, &self.methods)?;
        Ok(p)
    }

    fn parse_items(&mut self, p: &mut Program, top: bool) -> Result<(), String> {
        loop {
            if matches!(self.peek(), Tok::Eof) {
                if top {
                    break;
                }
                return self.err("unexpected end of file inside a 'mod'");
            }
            if !top && self.at_sym("}") {
                break;
            }
            if self.eat_kw("const") {
                p.consts.push(self.parse_const()?);
            } else if self.eat_kw("struct") {
                p.structs.push(self.parse_struct()?);
            } else if self.eat_kw("enum") {
                p.enums.push(self.parse_enum()?);
            } else if self.eat_kw("extern") {
                p.externs.extend(self.parse_extern()?);
            } else if self.eat_kw("static") {
                p.globals.push(self.parse_static()?);
            } else if self.eat_kw("mod") {
                self.parse_mod(p)?;
            } else if self.eat_kw("impl") {
                self.parse_impl(p)?;
            } else if self.eat_kw("fn") {
                p.fns.push(self.parse_fn()?);
            } else if self.at_kw("async") {
                self.bump();
                self.expect_kw("fn")?;
                p.fns.push(self.parse_fn_async(true)?);
            } else if self.at_kw("end") {
                return self.err("'end;' closes a block that opened without '{', and no block is open here");
            } else {
                return self.err(&format!(
                    "expected 'const', 'struct', 'enum', 'extern', 'static', 'mod', 'impl' or 'fn', found {}",
                    describe(self.peek())
                ));
            }
        }
        Ok(())
    }

    fn parse_mod(&mut self, p: &mut Program) -> Result<(), String> {
        let name = self.name()?;
        self.expect_sym("{")?;
        let saved = self.pfx.clone();
        let pfx = format!("{}{}__", saved, name);
        self.pfx = pfx.clone();
        let mut inner = Program::default();
        let lift_mark = self.lifts.len();
        let r = self.parse_items(&mut inner, false);
        self.pfx = saved;
        r?;
        self.expect_sym("}")?;
        let mut names = std::collections::HashSet::new();
        for f in &inner.fns {
            names.insert(f.name.clone());
        }
        for c in &inner.consts {
            names.insert(c.name.clone());
        }
        for g in &inner.globals {
            names.insert(g.name.clone());
        }
        for f in inner.fns.iter_mut() {
            rename_body(&mut f.body, &f.params, &pfx, &names)?;
        }
        for c in inner.consts.iter_mut() {
            rename_expr(&mut c.value, &pfx, &names)?;
        }
        for g in inner.globals.iter_mut() {
            rename_expr(&mut g.init, &pfx, &names)?;
        }
        let mut lifted: Vec<FnDef> = self.lifts.split_off(lift_mark);
        for f in lifted.iter_mut() {
            rename_body(&mut f.body, &f.params, &pfx, &names)?;
        }
        p.fns.append(&mut lifted);
        p.consts.extend(inner.consts);
        p.globals.extend(inner.globals);
        p.structs.extend(inner.structs);
        p.enums.extend(inner.enums);
        p.externs.extend(inner.externs);
        p.fns.extend(inner.fns);
        Ok(())
    }

    fn parse_impl(&mut self, p: &mut Program) -> Result<(), String> {
        let mut segs = vec![self.type_name()?];
        while self.at_sym("::") {
            self.bump();
            segs.push(self.type_name()?);
        }
        let ty = if segs.len() == 1 {
            format!("{}{}", self.pfx, segs[0])
        } else {
            segs.join("__")
        };
        self.expect_sym("{")?;
        while !self.at_sym("}") {
            if matches!(self.peek(), Tok::Eof) {
                return self.err("unexpected end of file inside an 'impl' block");
            }
            let is_async = if self.at_kw("async") {
                self.bump();
                true
            } else {
                false
            };
            self.expect_kw("fn")?;
            let mut f = self.parse_fn_async(is_async)?;
            let full = format!("{}__{}", ty, f.name);
            if let Some((first, fty)) = f.params.first() {
                if first == "self" {
                    let kind = match fty {
                        Type::Ref(_, true) => Some(SelfKind::Exclusive),
                        Type::Ref(_, false) => Some(SelfKind::Shared),
                        _ => None,
                    };
                    match kind {
                        Some(k) => self.methods.push((f.name.clone(), full.clone(), k)),
                        None => {
                            return Err(format!(
                                "impl {}: 'self' must be a reference, &{} or &mut {}",
                                ty, ty, ty
                            ))
                        }
                    }
                }
            }
            f.name = full;
            p.fns.push(f);
        }
        self.expect_sym("}")?;
        Ok(())
    }

    fn parse_static(&mut self) -> Result<StaticDef, String> {
        let mutable = self.eat_kw("mut");
        let pfx = self.pfx.clone();
        let name = format!("{}{}", pfx, self.const_name()?);
        self.expect_sym(":")?;
        let ty = self.parse_type()?;
        self.expect_sym("=")?;
        let init = self.parse_expr()?;
        self.expect_sym(";")?;
        Ok(StaticDef { name, ty, mutable, init })
    }

    fn parse_const(&mut self) -> Result<ConstDef, String> {
        let pfx = self.pfx.clone();
        let name = format!("{}{}", pfx, self.const_name()?);
        self.expect_sym(":")?;
        let ty = self.parse_type()?;
        self.expect_sym("=")?;
        let value = self.parse_expr()?;
        self.expect_sym(";")?;
        Ok(ConstDef { name, ty, value })
    }

    fn parse_struct(&mut self) -> Result<StructDef, String> {
        let pfx = self.pfx.clone();
        let name = format!("{}{}", pfx, self.type_name()?);
        self.expect_sym("{")?;
        let mut fields = Vec::new();
        while !self.at_sym("}") {
            let fname = self.name()?;
            self.expect_sym(":")?;
            let fty = self.parse_type()?;
            fields.push((fname, fty));
            if !self.eat_sym(",") {
                break;
            }
        }
        self.expect_sym("}")?;
        if fields.is_empty() {
            return Err(format!("struct '{}' needs at least one field", name));
        }
        Ok(StructDef { name, fields })
    }

    fn parse_enum(&mut self) -> Result<EnumDef, String> {
        let pfx = self.pfx.clone();
        let name = format!("{}{}", pfx, self.type_name()?);
        self.expect_sym("{")?;
        let mut variants: Vec<Variant> = Vec::new();
        while !self.at_sym("}") {
            let vname = self.type_name()?;
            let mut payload = Vec::new();
            if self.eat_sym("(") {
                if !self.at_sym(")") {
                    loop {
                        let t = self.parse_type()?;
                        if t == Type::Void {
                            return Err(format!(
                                "variant '{}::{}' cannot carry void",
                                name, vname
                            ));
                        }
                        payload.push(t);
                        if !self.eat_sym(",") {
                            break;
                        }
                    }
                }
                self.expect_sym(")")?;
            }
            if variants.iter().any(|v| v.name == vname) {
                return Err(format!("duplicate variant '{}' in enum '{}'", vname, name));
            }
            variants.push(Variant { name: vname, payload });
            if !self.eat_sym(",") {
                break;
            }
        }
        self.expect_sym("}")?;
        if variants.is_empty() {
            return Err(format!("enum '{}' needs at least one variant", name));
        }
        Ok(EnumDef { name, variants })
    }

    fn raw_name(&mut self) -> Result<String, String> {
        match self.take_ident() {
            Some((s, _, _)) => Ok(s),
            None => self.err(&format!("expected a name, found {}", describe(self.peek()))),
        }
    }

    fn parse_extern(&mut self) -> Result<Vec<ExternFn>, String> {
        let mut lib = None;
        if let Some(s) = self.peek_str() {
            if s.is_empty() || !s.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
                return self.err("a library tag is letters, digits and '_' - e.g. \"winhttp\"");
            }
            let t = self.bump();
            if let Tok::Str(s) = t.tok {
                lib = Some(s);
            }
        }
        if self.at_sym("{") {
            self.bump();
            let mut out = Vec::new();
            while !self.at_sym("}") {
                if matches!(self.peek(), Tok::Eof) {
                    return self.err("unexpected end of file inside an 'extern' block");
                }
                out.push(self.parse_extern_one(lib.clone())?);
            }
            self.expect_sym("}")?;
            return Ok(out);
        }
        Ok(vec![self.parse_extern_one(lib)?])
    }

    fn parse_extern_one(&mut self, lib: Option<String>) -> Result<ExternFn, String> {
        self.expect_kw("fn")?;
        let name = self.raw_name()?;
        self.expect_sym("(")?;
        let mut params = Vec::new();
        let mut variadic = false;
        if !self.at_sym(")") {
            loop {
                if self.eat_sym("...") {
                    variadic = true;
                    break;
                }
                let _pname = self.name()?;
                self.expect_sym(":")?;
                params.push(self.parse_type()?);
                if !self.eat_sym(",") {
                    break;
                }
            }
        }
        self.expect_sym(")")?;
        let ret = if self.eat_sym("->") { self.parse_type()? } else { Type::Void };
        self.expect_sym(";")?;
        Ok(ExternFn { lib, name, params, variadic, ret })
    }

    fn parse_fn(&mut self) -> Result<FnDef, String> {
        self.parse_fn_async(false)
    }

    fn parse_fn_async(&mut self, is_async: bool) -> Result<FnDef, String> {
        let pfx = self.pfx.clone();
        let name = format!("{}{}", pfx, self.name()?);
        let mut tparams: Vec<String> = Vec::new();
        if self.eat_sym("<") {
            loop {
                let t = self.type_param_name()?;
                if tparams.contains(&t) {
                    return Err(format!("duplicate type parameter '{}' in fn '{}'", t, name));
                }
                tparams.push(t);
                if !self.eat_sym(",") {
                    break;
                }
            }
            self.expect_sym(">")?;
        }
        let outer = std::mem::replace(&mut self.tparams, tparams.clone());
        self.expect_sym("(")?;
        let mut params: Vec<(String, Type)> = Vec::new();
        if !self.at_sym(")") {
            loop {
                let pname = self.name()?;
                self.expect_sym(":")?;
                let pty = self.parse_type()?;
                if params.iter().any(|(n, _)| *n == pname) {
                    return Err(format!("duplicate parameter '{}' in fn '{}'", pname, name));
                }
                params.push((pname, pty));
                if !self.eat_sym(",") {
                    break;
                }
            }
        }
        self.expect_sym(")")?;
        let ret = if self.eat_sym("->") { self.parse_type()? } else { Type::Void };
        let body = self.parse_body()?;
        self.tparams = outer;
        Ok(FnDef { name, tparams, params, ret, is_async, body })
    }

    fn parse_block(&mut self) -> Result<Vec<Stmt>, String> {
        self.expect_sym("{")?;
        let mut body = Vec::new();
        while !self.at_sym("}") {
            if matches!(self.peek(), Tok::Eof) {
                return self.err("unexpected end of file inside a block");
            }
            body.extend(self.parse_stmts()?);
        }
        self.expect_sym("}")?;
        Ok(body)
    }

    fn parse_run(&mut self) -> Result<Vec<Stmt>, String> {
        let mut body = Vec::new();
        while !self.at_kw("end") && !self.at_kw("else") {
            if matches!(self.peek(), Tok::Eof) {
                return self.err("unexpected end of file; a block opened without '{' is closed by 'end;'");
            }
            body.extend(self.parse_stmts()?);
        }
        Ok(body)
    }

    fn parse_end(&mut self) -> Result<(), String> {
        self.expect_kw("end")?;
        self.expect_sym(";")
    }

    fn parse_body(&mut self) -> Result<Vec<Stmt>, String> {
        if self.at_sym("{") {
            return self.parse_block();
        }
        let body = self.parse_run()?;
        self.parse_end()?;
        Ok(body)
    }

    fn parse_if_open(&mut self, cond: Expr) -> Result<Stmt, String> {
        let mut conds: Vec<Expr> = vec![cond];
        let mut arms: Vec<Vec<Stmt>> = Vec::new();
        arms.push(self.parse_run()?);
        while self.at_kw("else") {
            self.bump();
            let mut more = false;
            if self.at_kw("if") {
                self.bump();
                self.expect_sym("(")?;
                let c = self.parse_expr()?;
                self.expect_sym(")")?;
                conds.push(c);
                more = true;
            }
            if self.at_sym("{") {
                arms.push(self.parse_block()?);
            } else {
                arms.push(self.parse_run()?);
            }
            if !more {
                break;
            }
        }
        self.parse_end()?;

        let n = conds.len();
        let mut els: Vec<Stmt> = if arms.len() > n { arms[n].clone() } else { Vec::new() };
        let mut k = n;
        while k > 0 {
            k -= 1;
            els = vec![Stmt::If(conds[k].clone(), arms[k].clone(), els)];
        }
        match els.pop() {
            Some(s) => Ok(s),
            None => Ok(Stmt::Block(Vec::new())),
        }
    }

    fn parse_stmts(&mut self) -> Result<Vec<Stmt>, String> {
        if self.eat_kw("let") {
            return self.parse_binding(false);
        }
        if self.eat_kw("var") {
            return self.parse_binding(true);
        }
        if self.at_sym("'") {
            self.bump();
            let label = self.name()?;
            self.expect_sym(":")?;
            let inner = self.parse_stmt1()?;
            return Ok(vec![Stmt::Label(label, Box::new(inner))]);
        }
        Ok(vec![self.parse_stmt1()?])
    }

    fn parse_stmt1(&mut self) -> Result<Stmt, String> {
        if self.at_kw("end") {
            return self.err("'end;' closes a block that opened without '{', and this one opened with '{'");
        }
        if self.eat_kw("unsafe") {
            return Ok(Stmt::Unsafe(self.parse_body()?));
        }
        if self.eat_kw("if") {
            self.expect_sym("(")?;
            let cond = self.parse_expr()?;
            self.expect_sym(")")?;
            if !self.at_sym("{") {
                return self.parse_if_open(cond);
            }
            let then = self.parse_block()?;
            let mut els = Vec::new();
            if self.eat_kw("else") {
                if self.at_kw("if") {
                    els = self.parse_stmts()?;
                } else {
                    els = self.parse_body()?;
                }
            }
            return Ok(Stmt::If(cond, then, els));
        }
        if self.eat_kw("while") {
            self.expect_sym("(")?;
            let cond = self.parse_expr()?;
            self.expect_sym(")")?;
            let body = self.parse_body()?;
            return Ok(Stmt::While(cond, body));
        }
        if self.eat_kw("loop") {
            let body = self.parse_body()?;
            return Ok(Stmt::Loop(body));
        }
        if self.eat_kw("for") {
            let var = self.name()?;
            self.expect_kw("in")?;
            let start = self.parse_expr()?;
            let (incl, end) = self.parse_expr_after_range()?;
            let end =
                if incl { Expr::Bin("+".into(), Box::new(end), Box::new(Expr::Int(1))) } else { end };
            let body = self.parse_body()?;
            return Ok(Stmt::For { var, start, end, body });
        }
        if self.eat_kw("match") {
            let scrut = self.parse_expr()?;
            self.expect_sym("{")?;
            let mut arms = Vec::new();
            while !self.at_sym("}") {
                let pat = self.parse_pat()?;
                self.expect_sym("=>")?;
                let body = self.parse_block()?;
                arms.push(Arm { pat, body });
                self.eat_sym(",");
            }
            self.expect_sym("}")?;
            if arms.is_empty() {
                return self.err("a 'match' needs at least one arm");
            }
            return Ok(Stmt::Match(scrut, arms));
        }
        if self.eat_kw("break") {
            let label = self.eat_label()?;
            self.expect_sym(";")?;
            return Ok(Stmt::Break(label));
        }
        if self.eat_kw("continue") {
            let label = self.eat_label()?;
            self.expect_sym(";")?;
            return Ok(Stmt::Continue(label));
        }
        if self.eat_kw("return") {
            if self.at_sym(";") {
                self.bump();
                return Ok(Stmt::Return(None));
            }
            let e = self.parse_expr()?;
            self.expect_sym(";")?;
            return Ok(Stmt::Return(Some(e)));
        }
        if self.at_sym("{") {
            return Ok(Stmt::Block(self.parse_block()?));
        }

        let lhs = self.parse_expr()?;
        for op in ["=", "+=", "-=", "*=", "/=", "%=", "<<=", ">>=", "&=", "|=", "^="] {
            if self.eat_sym(op) {
                let rhs = self.parse_expr()?;
                self.expect_sym(";")?;
                return Ok(Stmt::Assign(op.to_string(), lhs, rhs));
            }
        }
        self.expect_sym(";")?;
        Ok(Stmt::Expr(lhs))
    }

    fn eat_label(&mut self) -> Result<Option<String>, String> {
        if self.at_sym("'") {
            self.bump();
            let n = self.name()?;
            return Ok(Some(n));
        }
        Ok(None)
    }

    fn parse_expr_after_range(&mut self) -> Result<(bool, Expr), String> {
        let incl = self.eat_sym("..=");
        if !incl {
            self.expect_sym("..")?;
        }
        Ok((incl, self.parse_expr()?))
    }

    fn parse_pat(&mut self) -> Result<Pat, String> {
        if self.eat_kw("_") {
            return Ok(Pat::Wild);
        }
        let neg = self.eat_sym("-");
        if let Tok::Int(n) = *self.peek() {
            self.bump();
            let lo = if neg { -n } else { n };
            if self.eat_sym("..=") {
                let hi = match *self.peek() {
                    Tok::Int(m) => {
                        self.bump();
                        m
                    }
                    _ => return self.err("a range pattern needs an integer on both sides"),
                };
                if hi < lo {
                    return Err(format!("range pattern {}..={} runs backwards", lo, hi));
                }
                return Ok(Pat::Range(lo, hi));
            }
            return Ok(Pat::Lit(lo));
        }
        if neg {
            return self.err("expected a number after '-' in a pattern");
        }
        let mut segs = vec![self.type_name()?];
        while self.at_sym("::") {
            self.bump();
            segs.push(self.type_name()?);
        }
        let vn = segs.pop().unwrap();
        let en = if segs.len() == 1 {
            format!("{}{}", self.pfx, segs[0])
        } else if segs.is_empty() {
            return self.err("a variant pattern needs 'Enum::Variant'");
        } else {
            format!("{}{}", self.pfx, segs.join("__"))
        };
        let mut binds = Vec::new();
        if self.eat_sym("(") {
            if !self.at_sym(")") {
                loop {
                    let b = self.name()?;
                    if binds.contains(&b) {
                        return Err(format!("pattern binds '{}' twice", b));
                    }
                    binds.push(b);
                    if !self.eat_sym(",") {
                        break;
                    }
                }
            }
            self.expect_sym(")")?;
        }
        Ok(Pat::Variant(en, vn, binds))
    }

    fn parse_binding(&mut self, mutable: bool) -> Result<Vec<Stmt>, String> {
        if self.at_kw("_") {
            self.bump();
            if self.eat_sym("=") {
                let e = self.parse_expr()?;
                self.expect_sym(";")?;
                return Ok(vec![Stmt::Expr(e)]);
            }
            self.expect_sym(";")?;
            return Ok(vec![]);
        }

        let t = self.cur().clone();
        let upper =
            matches!(&t.tok, Tok::Ident(s) if s.chars().next().map(|c| c.is_ascii_uppercase()).unwrap_or(false));
        if upper && matches!(self.peek_at(1), Some(Tok::Sym("{"))) {
            let ty = self.parse_type()?;
            self.expect_sym("{")?;
            let mut binds = Vec::new();
            while !self.at_sym("}") {
                let f = self.name()?;
                let b = if self.eat_sym(":") { self.name()? } else { f.clone() };
                binds.push((f, b));
                if !self.eat_sym(",") {
                    break;
                }
            }
            self.expect_sym("}")?;
            self.expect_sym("=")?;
            let rhs = self.parse_expr()?;
            self.expect_sym(";")?;
            let mut out = Vec::new();
            let base = self.tie_to_name(&mut out, ty.clone(), rhs);
            for (f, b) in binds {
                out.push(Stmt::Let {
                    mutable,
                    name: b,
                    ty: Type::Infer,
                    init: Some(Expr::Field(Box::new(base.clone()), f)),
                });
            }
            return Ok(out);
        }

        if self.at_sym("(") && !mutable {
            self.bump();
            let mut slots: Vec<Option<String>> = Vec::new();
            loop {
                if self.at_kw("_") {
                    self.bump();
                    slots.push(None);
                } else {
                    slots.push(Some(self.name()?));
                }
                if !self.eat_sym(",") {
                    break;
                }
            }
            self.expect_sym(")")?;
            let ann = if self.eat_sym(":") { Some(self.parse_type()?) } else { None };
            self.expect_sym("=")?;
            let rhs = self.parse_expr()?;
            self.expect_sym(";")?;
            let parts: Vec<Type> = match ann.clone() {
                Some(Type::Tuple(items)) => {
                    if items.len() != slots.len() {
                        return Err(format!(
                            "the pattern has {} element(s); the tuple type has {}",
                            slots.len(),
                            items.len()
                        ));
                    }
                    items
                }
                Some(_) => return self.err("a tuple pattern needs a tuple type"),
                None => Vec::new(),
            };
            let mut out = Vec::new();
            let hint = ann.unwrap_or(Type::Infer);
            let base = self.tie_to_name(&mut out, hint, rhs);
            for (i, slot) in slots.into_iter().enumerate() {
                let Some(name) = slot else { continue };
                let ty = parts.get(i).cloned().unwrap_or(Type::Infer);
                out.push(Stmt::Let {
                    mutable: false,
                    name,
                    ty,
                    init: Some(Expr::Field(Box::new(base.clone()), i.to_string())),
                });
            }
            return Ok(out);
        }

        let name = self.name()?;
        if name == "self" {
            return Err(format!("line {}:{}: 'self' cannot be rebound", t.line, t.col));
        }
        let ty = if self.eat_sym(":") { self.parse_type()? } else { Type::Infer };
        let init = if self.eat_sym("=") { Some(self.parse_expr()?) } else { None };
        self.expect_sym(";")?;
        Ok(vec![Stmt::Let { mutable, name, ty, init }])
    }

    fn tie_to_name(&mut self, out: &mut Vec<Stmt>, hint: Type, rhs: Expr) -> Expr {
        match &rhs {
            Expr::Var(_) | Expr::Field(..) | Expr::Index(..) | Expr::Deref(_) => rhs,
            _ => {
                let temp = format!("__destr{}", self.tmpn);
                self.tmpn += 1;
                out.push(Stmt::Let {
                    mutable: false,
                    name: temp.clone(),
                    ty: hint,
                    init: Some(rhs),
                });
                Expr::Var(temp)
            }
        }
    }
    pub fn parse_expr(&mut self) -> Result<Expr, String> {
        self.parse_bin(1)
    }

    fn binop(&self) -> Option<(&'static str, u8, usize)> {
        let s = match self.peek() {
            Tok::Sym(s) => *s,
            _ => return None,
        };
        if s == ">" {
            let a = self.cur();
            if let Some(Tok::Sym(">")) = self.peek_at(1) {
                let b = &self.toks[self.i + 1];
                if a.end == b.start {
                    return Some((">>", 8, 2));
                }
            }
        }
        let p = match s {
            "||" => 1,
            "&&" => 2,
            "|" => 3,
            "^" => 4,
            "&" => 5,
            "==" | "!=" => 6,
            "<" | "<=" | ">" | ">=" => 7,
            "<<" => 8,
            "+" | "-" => 9,
            "*" | "/" | "%" => 10,
            _ => return None,
        };
        Some((s, p, 1))
    }

    fn parse_bin(&mut self, min_prec: u8) -> Result<Expr, String> {
        let mut lhs = self.parse_cast()?;
        loop {
            let Some((op, prec, ntoks)) = self.binop() else { break };
            if prec < min_prec {
                break;
            }
            for _ in 0..ntoks {
                self.bump();
            }
            let rhs = self.parse_bin(prec + 1)?;
            lhs = Expr::Bin(op.to_string(), Box::new(lhs), Box::new(rhs));
        }
        Ok(lhs)
    }

    fn parse_cast(&mut self) -> Result<Expr, String> {
        let mut e = self.parse_unary()?;
        while self.eat_kw("as") {
            let t = self.parse_type()?;
            e = Expr::Cast(Box::new(e), t);
        }
        Ok(e)
    }

    fn parse_unary(&mut self) -> Result<Expr, String> {
        if self.eat_sym("-") {
            return Ok(Expr::Un("-".into(), Box::new(self.parse_unary()?)));
        }
        if self.eat_sym("!") {
            return Ok(Expr::Un("!".into(), Box::new(self.parse_unary()?)));
        }
        if self.eat_sym("~") {
            return Ok(Expr::Un("~".into(), Box::new(self.parse_unary()?)));
        }
        if self.eat_sym("*") {
            return Ok(Expr::Deref(Box::new(self.parse_unary()?)));
        }
        if self.eat_sym("&") {
            if self.eat_kw("mut") {
                return Ok(Expr::AddrMut(Box::new(self.parse_unary()?)));
            }
            return Ok(Expr::Addr(Box::new(self.parse_unary()?)));
        }
        self.parse_postfix()
    }

    fn parse_args(&mut self) -> Result<Vec<Expr>, String> {
        self.expect_sym("(")?;
        let mut args = Vec::new();
        if !self.at_sym(")") {
            loop {
                args.push(self.parse_expr()?);
                if !self.eat_sym(",") {
                    break;
                }
            }
        }
        self.expect_sym(")")?;
        Ok(args)
    }

    fn parse_postfix(&mut self) -> Result<Expr, String> {
        let mut e = self.parse_primary()?;
        loop {
            if self.at_sym("(") {
                let args = self.parse_args()?;
                e = match e {
                    Expr::Var(n) => Expr::Call(n, args),
                    other => Expr::CallV(Box::new(other), args),
                };
            } else if self.eat_sym("[") {
                let idx = self.parse_expr()?;
                self.expect_sym("]")?;
                e = Expr::Index(Box::new(e), Box::new(idx));
            } else if self.eat_sym(".") {
                let f = match self.peek().clone() {
                    Tok::Int(n) if n >= 0 => {
                        self.bump();
                        n.to_string()
                    }
                    _ => self.name()?,
                };
                if self.at_sym("(") {
                    let args = self.parse_args()?;
                    e = Expr::Method(Box::new(e), f, args);
                } else {
                    e = Expr::Field(Box::new(e), f);
                }
            } else {
                break;
            }
        }
        Ok(e)
    }

    fn parse_primary(&mut self) -> Result<Expr, String> {
        let t = self.cur().clone();
        match t.tok {
            Tok::Int(n) => {
                self.bump();
                Ok(Expr::Int(n))
            }
            Tok::Float(f) => {
                self.bump();
                Ok(Expr::Float(f))
            }
            Tok::Str(s) => {
                self.bump();
                Ok(Expr::Str(s))
            }
            Tok::Sym("[") => {
                self.bump();
                let mut items = Vec::new();
                if !self.at_sym("]") {
                    loop {
                        items.push(self.parse_expr()?);
                        if !self.eat_sym(",") {
                            break;
                        }
                    }
                }
                self.expect_sym("]")?;
                Ok(Expr::ArrayLit(items))
            }
            Tok::Sym("|") | Tok::Sym("||") => self.parse_closure(),
            Tok::Ident(k) if k == "await" => {
                self.bump();
                Ok(Expr::Await(Box::new(self.parse_unary()?)))
            }
            Tok::Ident(k) if k == "poll" && matches!(self.peek_at(1), Some(Tok::Sym("("))) => {
                self.bump();
                self.expect_sym("(")?;
                let e = self.parse_expr()?;
                self.expect_sym(")")?;
                Ok(Expr::Poll(Box::new(e)))
            }
            Tok::Ident(name) => match name.as_str() {
                "true" => {
                    self.bump();
                    Ok(Expr::Bool(true))
                }
                "false" => {
                    self.bump();
                    Ok(Expr::Bool(false))
                }
                "null" => {
                    self.bump();
                    Ok(Expr::Null)
                }
                "sizeof" => {
                    self.bump();
                    self.expect_sym("(")?;
                    let ty = self.parse_type()?;
                    self.expect_sym(")")?;
                    Ok(Expr::Sizeof(ty))
                }
                "zero" => {
                    self.bump();
                    self.expect_sym("(")?;
                    let ty = self.parse_type()?;
                    self.expect_sym(")")?;
                    Ok(Expr::Zero(ty))
                }
                "box" => {
                    self.bump();
                    self.expect_sym("(")?;
                    let e = self.parse_expr()?;
                    self.expect_sym(")")?;
                    Ok(Expr::BoxNew(Box::new(e)))
                }
                _ => {
                    self.bump();
                    if self.at_sym("::") {
                        let mut segs = vec![name.clone()];
                        while self.at_sym("::") {
                            self.bump();
                            segs.push(self.raw_name()?);
                        }
                        let upper_at = segs
                            .iter()
                            .position(|s| s.chars().next().map(|c| c.is_ascii_uppercase()).unwrap_or(false));
                        match upper_at {
                            None => {
                                let joined = segs.join("__");
                                if self.at_sym("(") {
                                    return Ok(Expr::Call(joined, self.parse_args()?));
                                }
                                return Ok(Expr::Var(joined));
                            }
                            Some(k) => {
                                let rest = &segs[k..];
                                if rest.len() == 1 {
                                    let joined = format!("{}{}", self.pfx, segs.join("__"));
                                    if self.at_sym("{") {
                                        return self.parse_struct_lit(joined);
                                    }
                                    return Ok(Expr::Var(joined));
                                }
                                if rest.len() == 2 {
                                    let ty = format!("{}{}", self.pfx, segs[..=k].join("__"));
                                    let vn = rest[1].clone();
                                    let mut args = Vec::new();
                                    if self.eat_sym("(") {
                                        if !self.at_sym(")") {
                                            loop {
                                                args.push(self.parse_expr()?);
                                                if !self.eat_sym(",") {
                                                    break;
                                                }
                                            }
                                        }
                                        self.expect_sym(")")?;
                                    }
                                    return Ok(Expr::EnumLit(ty, vn, args));
                                }
                                return self.err("too many '::' segments: a name is 'mod::Type::Variant' at most");
                            }
                        }
                    }
                    if self.at_sym("{")
                        && name.chars().next().map(|c| c.is_ascii_uppercase()).unwrap_or(false)
                    {
                        let full = format!("{}{}", self.pfx, name);
                        return self.parse_struct_lit(full);
                    }
                    Ok(Expr::Var(name))
                }
            },
            Tok::Sym("(") => {
                self.bump();
                let first = self.parse_expr()?;
                if self.eat_sym(",") {
                    let mut items = vec![first];
                    loop {
                        items.push(self.parse_expr()?);
                        if !self.eat_sym(",") {
                            break;
                        }
                    }
                    self.expect_sym(")")?;
                    if items.len() < 2 {
                        return self.err("a tuple needs at least two elements");
                    }
                    return Ok(Expr::TupleLit(items));
                }
                self.expect_sym(")")?;
                Ok(first)
            }
            other => self.err(&format!("expected an expression, found {}", describe(&other))),
        }
    }

    fn parse_closure(&mut self) -> Result<Expr, String> {
        let mut params: Vec<(String, Type)> = Vec::new();
        if !self.eat_sym("||") {
            self.expect_sym("|")?;
            if !self.at_sym("|") {
                loop {
                    let pname = self.name()?;
                    self.expect_sym(":")?;
                    let pty = self.parse_type()?;
                    if params.iter().any(|(n, _)| *n == pname) {
                        return Err(format!("duplicate parameter '{}' in closure", pname));
                    }
                    params.push((pname, pty));
                    if !self.eat_sym(",") {
                        break;
                    }
                }
            }
            self.expect_sym("|")?;
        }
        let ret = if self.eat_sym("->") { self.parse_type()? } else { Type::Void };
        let body = self.parse_block()?;
        let name = format!("__clo{}", self.clo);
        self.clo += 1;
        self.lifts.push(FnDef { name: name.clone(), tparams: Vec::new(), params, ret, is_async: false, body });
        Ok(Expr::FnRef(name))
    }

    fn parse_struct_lit(&mut self, name: String) -> Result<Expr, String> {
        self.expect_sym("{")?;
        let mut fields = Vec::new();
        while !self.at_sym("}") {
            let f = self.name()?;
            self.expect_sym(":")?;
            let v = self.parse_expr()?;
            if fields.iter().any(|(n, _): &(String, Expr)| *n == f) {
                return Err(format!("duplicate field '{}' in {} {{ ... }}", f, name));
            }
            fields.push((f, v));
            if !self.eat_sym(",") {
                break;
            }
        }
        self.expect_sym("}")?;
        if fields.is_empty() {
            return Err(format!("{} {{ }} needs at least one field", name));
        }
        Ok(Expr::StructLit(name, fields))
    }
}

fn rename_body(
    body: &mut Vec<Stmt>,
    params: &[(String, Type)],
    pfx: &str,
    names: &std::collections::HashSet<String>,
) -> Result<(), String> {
    let mut locals: Vec<Vec<String>> = vec![params.iter().map(|(n, _)| n.clone()).collect()];
    rename_stmts(body, pfx, names, &mut locals)
}

fn is_local(locals: &[Vec<String>], n: &str) -> bool {
    locals.iter().any(|s| s.iter().any(|x| x == n))
}

fn rename_expr(
    e: &mut Expr,
    pfx: &str,
    names: &std::collections::HashSet<String>,
) -> Result<(), String> {
    rename_expr_scoped(e, pfx, names, &mut vec![Vec::new()])
}

fn rename_expr_scoped(
    e: &mut Expr,
    pfx: &str,
    names: &std::collections::HashSet<String>,
    locals: &mut Vec<Vec<String>>,
) -> Result<(), String> {
    match e {
        Expr::Var(n) => {
            if !is_local(locals, n) && names.contains(&format!("{}{}", pfx, n)) {
                *n = format!("{}{}", pfx, n);
            }
        }
        Expr::FnRef(n) => {
            if names.contains(&format!("{}{}", pfx, n)) {
                *n = format!("{}{}", pfx, n);
            }
        }
        Expr::Call(n, args) => {
            if names.contains(&format!("{}{}", pfx, n)) {
                *n = format!("{}{}", pfx, n);
            }
            for a in args {
                rename_expr_scoped(a, pfx, names, locals)?;
            }
        }
        Expr::Bin(_, a, b) => {
            rename_expr_scoped(a, pfx, names, locals)?;
            rename_expr_scoped(b, pfx, names, locals)?;
        }
        Expr::Un(_, a) => rename_expr_scoped(a, pfx, names, locals)?,
        Expr::Index(a, b) => {
            rename_expr_scoped(a, pfx, names, locals)?;
            rename_expr_scoped(b, pfx, names, locals)?;
        }
        Expr::Field(a, _) | Expr::Deref(a) | Expr::Addr(a) | Expr::AddrMut(a)
        | Expr::BoxNew(a) | Expr::Cast(a, _) | Expr::Await(a) | Expr::Poll(a) => {
            rename_expr_scoped(a, pfx, names, locals)?
        }
        Expr::CallV(f, args) => {
            rename_expr_scoped(f, pfx, names, locals)?;
            for a in args {
                rename_expr_scoped(a, pfx, names, locals)?;
            }
        }
        Expr::Method(r, _, args) => {
            rename_expr_scoped(r, pfx, names, locals)?;
            for a in args {
                rename_expr_scoped(a, pfx, names, locals)?;
            }
        }
        Expr::StructLit(_, fs) => {
            for (_, v) in fs {
                rename_expr_scoped(v, pfx, names, locals)?;
            }
        }
        Expr::ArrayLit(items) | Expr::TupleLit(items) => {
            for it in items {
                rename_expr_scoped(it, pfx, names, locals)?;
            }
        }
        Expr::EnumLit(_, _, args) => {
            for a in args {
                rename_expr_scoped(a, pfx, names, locals)?;
            }
        }
        _ => {}
    }
    Ok(())
}

fn rename_stmts(
    body: &mut Vec<Stmt>,
    pfx: &str,
    names: &std::collections::HashSet<String>,
    locals: &mut Vec<Vec<String>>,
) -> Result<(), String> {
    for st in body.iter_mut() {
        rename_stmt(st, pfx, names, locals)?;
    }
    Ok(())
}

fn rename_stmt(
    st: &mut Stmt,
    pfx: &str,
    names: &std::collections::HashSet<String>,
    locals: &mut Vec<Vec<String>>,
) -> Result<(), String> {
    match st {
        Stmt::Let { name, init, .. } => {
            if let Some(e) = init {
                rename_expr_scoped(e, pfx, names, locals)?;
            }
            locals.last_mut().unwrap().push(name.clone());
        }
        Stmt::Assign(_, l, r) => {
            rename_expr_scoped(l, pfx, names, locals)?;
            rename_expr_scoped(r, pfx, names, locals)?;
        }
        Stmt::Expr(e) => rename_expr_scoped(e, pfx, names, locals)?,
        Stmt::Block(b) | Stmt::Unsafe(b) => {
            locals.push(Vec::new());
            rename_stmts(b, pfx, names, locals)?;
            locals.pop();
        }
        Stmt::If(c, th, el) => {
            rename_expr_scoped(c, pfx, names, locals)?;
            locals.push(Vec::new());
            rename_stmts(th, pfx, names, locals)?;
            locals.pop();
            locals.push(Vec::new());
            rename_stmts(el, pfx, names, locals)?;
            locals.pop();
        }
        Stmt::While(c, b) => {
            rename_expr_scoped(c, pfx, names, locals)?;
            locals.push(Vec::new());
            rename_stmts(b, pfx, names, locals)?;
            locals.pop();
        }
        Stmt::Loop(b) => {
            locals.push(Vec::new());
            rename_stmts(b, pfx, names, locals)?;
            locals.pop();
        }
        Stmt::For { var, start, end, body } => {
            rename_expr_scoped(start, pfx, names, locals)?;
            rename_expr_scoped(end, pfx, names, locals)?;
            locals.push(vec![var.clone()]);
            rename_stmts(body, pfx, names, locals)?;
            locals.pop();
        }
        Stmt::Match(e, arms) => {
            rename_expr_scoped(e, pfx, names, locals)?;
            for a in arms {
                let mut inner: Vec<String> = Vec::new();
                if let Pat::Variant(_, _, binds) = &a.pat {
                    inner.extend(binds.iter().cloned());
                }
                locals.push(inner);
                rename_stmts(&mut a.body, pfx, names, locals)?;
                locals.pop();
            }
        }
        Stmt::Label(_, inner) => rename_stmt(inner, pfx, names, locals)?,
        Stmt::Return(Some(e)) => rename_expr_scoped(e, pfx, names, locals)?,
        _ => {}
    }
    Ok(())
}

fn place_ok(e: &Expr) -> bool {
    matches!(e, Expr::Var(_) | Expr::Field(..) | Expr::Index(..) | Expr::Deref(_))
}

fn resolve_methods(p: &mut Program, methods: &[(String, String, SelfKind)]) -> Result<(), String> {
    let mut fns = std::mem::take(&mut p.fns);
    let r = fns.iter_mut().try_for_each(|f| fix_stmts(&mut f.body, methods));
    p.fns = fns;
    r?;
    for g in p.globals.iter_mut() {
        fix_expr(&mut g.init, methods)?;
    }
    for c in p.consts.iter_mut() {
        fix_expr(&mut c.value, methods)?;
    }
    Ok(())
}

fn fix_stmts(body: &mut Vec<Stmt>, methods: &[(String, String, SelfKind)]) -> Result<(), String> {
    body.iter_mut().try_for_each(|s| fix_stmt(s, methods))
}

fn fix_expr(e: &mut Expr, methods: &[(String, String, SelfKind)]) -> Result<(), String> {
    match e {
        Expr::Bin(_, a, b) => {
            fix_expr(a, methods)?;
            fix_expr(b, methods)?;
        }
        Expr::Un(_, a) | Expr::Deref(a) | Expr::Addr(a) | Expr::AddrMut(a) | Expr::BoxNew(a)
        | Expr::Cast(a, _) | Expr::Await(a) | Expr::Poll(a) => fix_expr(a, methods)?,
        Expr::Index(a, b) => {
            fix_expr(a, methods)?;
            fix_expr(b, methods)?;
        }
        Expr::Field(a, _) => fix_expr(a, methods)?,
        Expr::Call(_, args) | Expr::ArrayLit(args) | Expr::TupleLit(args)
        | Expr::EnumLit(_, _, args) => {
            for a in args {
                fix_expr(a, methods)?;
            }
        }
        Expr::CallV(f, args) => {
            fix_expr(f, methods)?;
            for a in args {
                fix_expr(a, methods)?;
            }
        }
        Expr::StructLit(_, fs) => {
            for (_, v) in fs {
                fix_expr(v, methods)?;
            }
        }
        Expr::Method(recv, name, args) => {
            fix_expr(recv, methods)?;
            for a in args.iter_mut() {
                fix_expr(a, methods)?;
            }
            let hits: Vec<&(String, String, SelfKind)> =
                methods.iter().filter(|(m, _, _)| m == name).collect();
            match hits.len() {
                0 => return Err(format!("no method named '{}'", name)),
                1 => {
                    let (_, full, kind) = hits[0];
                    let mut call = Vec::with_capacity(args.len() + 1);
                    let target = recv.as_ref().clone();
                    call.push(match kind {
                        SelfKind::Shared => Expr::Addr(Box::new(target)),
                        SelfKind::Exclusive => Expr::AddrMut(Box::new(target)),
                    });
                    call.extend(args.drain(..));
                    *e = Expr::Call(full.clone(), call);
                }
                n => {
                    let names: Vec<&str> =
                        hits.iter().map(|(_, f, _)| f.split("__").next().unwrap_or("?")).collect();
                    return Err(format!(
                        "method '{}' is defined by {} types ({}); write Type::{}(...) to pick one",
                        name,
                        n,
                        names.join(", "),
                        name
                    ));
                }
            }
        }
        _ => {}
    }
    Ok(())
}

fn fix_stmt(st: &mut Stmt, methods: &[(String, String, SelfKind)]) -> Result<(), String> {
    match st {
        Stmt::Let { init, .. } => {
            if let Some(e) = init {
                if let Expr::Method(recv, _, _) = e {
                    if !place_ok(recv) {
                        return Err("a method call needs a name to take its address".into());
                    }
                }
                fix_expr(e, methods)?;
            }
        }
        Stmt::Assign(_, l, r) => {
            fix_expr(l, methods)?;
            fix_expr(r, methods)?;
        }
        Stmt::Expr(e) => fix_expr(e, methods)?,
        Stmt::Block(b) | Stmt::Unsafe(b) => fix_stmts(b, methods)?,
        Stmt::If(c, th, el) => {
            fix_expr(c, methods)?;
            fix_stmts(th, methods)?;
            fix_stmts(el, methods)?;
        }
        Stmt::While(c, b) => {
            fix_expr(c, methods)?;
            fix_stmts(b, methods)?;
        }
        Stmt::Loop(b) => fix_stmts(b, methods)?,
        Stmt::For { start, end, body, .. } => {
            fix_expr(start, methods)?;
            fix_expr(end, methods)?;
            fix_stmts(body, methods)?;
        }
        Stmt::Match(e, arms) => {
            fix_expr(e, methods)?;
            for a in arms {
                fix_stmts(&mut a.body, methods)?;
            }
        }
        Stmt::Label(_, inner) => fix_stmt(inner, methods)?,
        Stmt::Return(Some(e)) => fix_expr(e, methods)?,
        _ => {}
    }
    Ok(())
}

fn describe(t: &Tok) -> String {
    match t {
        Tok::Ident(s) => format!("'{}'", s),
        Tok::Int(n) => format!("integer {}", n),
        Tok::Float(f) => format!("float {}", f),
        Tok::Str(_) => "a string literal".to_string(),
        Tok::Sym(s) => format!("'{}'", s),
        Tok::Eof => "end of file".to_string(),
    }
}

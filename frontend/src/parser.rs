use crate::ast::*;
use crate::lexer::{Tok, Token};
use std::collections::{HashMap, HashSet};

fn is_reserved(s: &str) -> bool {
    matches!(
        s,
        "fn" | "Fn" | "trait" | "class" | "let"
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

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum SelfKind {
    Shared,
    Exclusive,
}

#[derive(Clone, Debug)]
struct Binding {
    name: String,
    ty: Type,
    mutable: bool,
}

#[derive(Clone, Debug)]
struct MethodInfo {
    full: String,
    kind: SelfKind,
    trait_name: Option<String>,
}

#[derive(Clone, Debug)]
struct TraitImplInfo {
    trait_name: String,
    type_name: String,
    methods: Vec<TraitMethod>,
}

pub struct Parser {
    toks: Vec<Token>,
    i: usize,
    lifts: Vec<FnDef>,
    clo: usize,
    methods: Vec<(String, String, SelfKind)>,
    method_map: HashMap<(String, String), Vec<MethodInfo>>,
    trait_defs: HashMap<String, TraitDef>,
    trait_impls: Vec<TraitImplInfo>,
    fat_types: HashMap<String, StructDef>,
    fat_sigs: HashMap<String, (Vec<Type>, Type)>,
    fat_values: HashMap<String, (Vec<Type>, Type)>,
    synthetic_structs: HashMap<String, StructDef>,
    dyn_structs: HashMap<String, StructDef>,
    vt_structs: HashMap<String, StructDef>,
    struct_fields: HashMap<String, Vec<(String, Type)>>,
    fn_params: HashMap<String, Vec<Type>>,
    fn_rets: HashMap<String, Type>,
    generated_fns: Vec<FnDef>,
    generated_externs: Vec<ExternFn>,
    adapter_count: usize,
    scopes: Vec<Vec<Binding>>,
    ret_stack: Vec<Type>,
    impl_ty: Option<String>,
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
            method_map: HashMap::new(),
            trait_defs: HashMap::new(),
            trait_impls: Vec::new(),
            fat_types: HashMap::new(),
            fat_sigs: HashMap::new(),
            fat_values: HashMap::new(),
            synthetic_structs: HashMap::new(),
            dyn_structs: HashMap::new(),
            vt_structs: HashMap::new(),
            struct_fields: HashMap::new(),
            fn_params: HashMap::new(),
            fn_rets: HashMap::new(),
            generated_fns: Vec::new(),
            generated_externs: Vec::new(),
            adapter_count: 0,
            scopes: vec![Vec::new()],
            ret_stack: Vec::new(),
            impl_ty: None,
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

    fn parse_fn_type(&mut self, c_abi: bool) -> Result<Type, String> {
        self.bump();
        self.expect_sym("(")?;
        let mut params = Vec::new();
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
        if c_abi {
            Ok(Type::FnC(params, Box::new(ret)))
        } else {
            Ok(Type::Fn(params, Box::new(ret)))
        }
    }

    fn parse_fn_type_fat(&mut self) -> Result<Type, String> {
        self.bump();
        self.expect_sym("(")?;
        let mut params = Vec::new();
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
        Ok(Type::FnFat(params, Box::new(ret)))
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
        if self.eat_kw("extern") {
            if !self.at_kw("fn") {
                return self
                    .err("'extern' in a type names an extern function pointer; write 'extern fn(...)'");
            }
            return self.parse_fn_type(true);
        }
        if self.at_kw("fn") {
            return self.parse_fn_type(false);
        }
        if self.at_kw("Fn") {
            return self.parse_fn_type_fat();
        }
        if self.eat_kw("dyn") {
            let mut segs = vec![self.type_name()?];
            while self.at_sym("::") {
                self.bump();
                segs.push(self.type_name()?);
            }
            let name = if segs.len() == 1 {
                format!("{}{}", self.pfx, segs[0])
            } else {
                format!("{}{}", self.pfx, segs.join("__"))
            };
            if !self.trait_defs.contains_key(&name) {
                return Err(format!("line {}:{}: unknown trait '{}'", self.cur().line, self.cur().col, name));
            }
            return Ok(Type::Dyn(name));
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
        if s == "Self" {
            return Ok(Type::SelfType);
        }
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

    fn push_scope(&mut self) {
        self.scopes.push(Vec::new());
    }

    fn pop_scope(&mut self) {
        self.scopes.pop();
    }

    fn bind(&mut self, name: String, ty: Type, mutable: bool) {
        if let Some(s) = self.scopes.last_mut() {
            s.retain(|b| b.name != name);
            s.push(Binding { name, ty, mutable });
        }
    }

    fn lookup_binding(&self, name: &str) -> Option<&Binding> {
        self.scopes.iter().rev().find_map(|s| s.iter().rev().find(|b| b.name == name))
    }

    fn peel_type(t: &Type) -> &Type {
        match t {
            Type::Ref(inner, _) | Type::Heap(inner) | Type::Ptr(inner) => Self::peel_type(inner),
            _ => t,
        }
    }

    fn subst_self(&self, t: Type) -> Type {
        match &self.impl_ty {
            Some(ty) => subst_self_type(&t, ty),
            None => t,
        }
    }

    fn field_type(&self, base: &Type, field: &str) -> Option<Type> {
        let base = Self::peel_type(base);
        match base {
            Type::Named(name) => {
                let fields = self.struct_fields.get(name)?;
                fields.iter().find(|(n, _)| n == field).map(|(_, t)| t.clone())
            }
            Type::Tuple(items) => {
                let i: usize = field.parse().ok()?;
                items.get(i).cloned()
            }
            _ => None,
        }
    }

    fn fn_value_type(&self, name: &str) -> Option<Type> {
        let ret = self.fn_rets.get(name)?;
        let params = self.fn_params.get(name)?;
        Some(Type::Fn(params.clone(), Box::new(ret.clone())))
    }

    fn expr_ty_hint(&self, e: &Expr) -> Option<Type> {
        match e {
            Expr::Int(_) => Some(Type::I32),
            Expr::Float(_) => Some(Type::F64),
            Expr::Bool(_) => Some(Type::Bool),
            Expr::Str(_) => Some(Type::Ptr(Box::new(Type::U8))),
            Expr::Null => Some(Type::Ptr(Box::new(Type::Void))),
            Expr::Var(n) => match self.lookup_binding(n) {
                Some(b) => Some(b.ty.clone()),
                None => self.fn_value_type(n),
            },
            Expr::Sizeof(_) => Some(Type::U64),
            Expr::Zero(t) => Some(t.clone()),
            Expr::Cast(_, t) => Some(t.clone()),
            Expr::Addr(a) => self.expr_ty_hint(a).map(|t| Type::Ref(Box::new(t), false)),
            Expr::AddrMut(a) => self.expr_ty_hint(a).map(|t| Type::Ref(Box::new(t), true)),
            Expr::Deref(a) => match self.expr_ty_hint(a) {
                Some(Type::Ptr(t)) | Some(Type::Ref(t, _)) | Some(Type::Heap(t)) => Some(*t),
                _ => None,
            },
            Expr::BoxNew(a) => self.expr_ty_hint(a).map(|t| Type::Heap(Box::new(t))),
            Expr::Index(a, _) => match self.expr_ty_hint(a) {
                Some(Type::Ptr(t)) | Some(Type::Array(t, _)) => Some(*t),
                Some(Type::Ref(t, _)) | Some(Type::Heap(t)) => match *t {
                    Type::Array(inner, _) => Some(*inner),
                    Type::Ptr(inner) => Some(*inner),
                    _ => None,
                },
                _ => None,
            },
            Expr::Field(a, f) => {
                let base = self.expr_ty_hint(a)?;
                self.field_type(&base, f)
            }
            Expr::StructLit(n, _) => match self.fat_sigs.get(n) {
                Some((ps, ret)) => Some(Type::FnFat(ps.clone(), Box::new(ret.clone()))),
                None => Some(Type::Named(n.clone())),
            },
            Expr::EnumLit(n, _, _) => Some(Type::Named(n.clone())),
            Expr::TupleLit(items) => {
                let mut ts = Vec::with_capacity(items.len());
                for it in items {
                    ts.push(self.expr_ty_hint(it)?);
                }
                Some(Type::Tuple(ts))
            }
            Expr::FnRef(n) => self.fn_value_type(n),
            Expr::Call(n, _) => match self.fat_values.get(n) {
                Some((ps, ret)) => Some(Type::FnFat(ps.clone(), Box::new(ret.clone()))),
                None => self.fn_rets.get(n).cloned(),
            },
            Expr::CallV(f, _) => match self.expr_ty_hint(f) {
                Some(Type::Fn(_, r)) | Some(Type::FnC(_, r)) | Some(Type::FnFat(_, r)) => Some(*r),
                _ => None,
            },
            Expr::Bin(op, a, b) => match op.as_str() {
                "==" | "!=" | "<" | "<=" | ">" | ">=" | "&&" | "||" => Some(Type::Bool),
                _ => self.expr_ty_hint(a).or_else(|| self.expr_ty_hint(b)),
            },
            Expr::Un(_, a) => self.expr_ty_hint(a),
            Expr::Await(a) => match self.expr_ty_hint(a) {
                Some(Type::Task(t)) => Some(*t),
                _ => None,
            },
            Expr::Poll(_) => Some(Type::I64),
            Expr::Method(_, _, _) => None,
            _ => None,
        }
    }

    fn typed_method(&self, hint: &Option<Type>, name: &str) -> Option<MethodInfo> {
        let hint = hint.as_ref()?;
        let base = Self::peel_type(hint);
        let ty = match base {
            Type::Named(n) => n,
            _ => return None,
        };
        let hits = self.method_map.get(&(ty.clone(), name.to_string()))?;
        if hits.is_empty() {
            return None;
        }
        if hits.len() > 1 && hits.iter().any(|h| h.trait_name.is_some()) {
            let distinct: HashSet<&str> = hits.iter().map(|h| h.full.as_str()).collect();
            if distinct.len() > 1 {
                return None;
            }
        }
        if hits.len() == 1 && hits[0].trait_name.is_none() {
            return None;
        }
        Some(hits[0].clone())
    }

    fn ensure_fat_type(&mut self, params: &[Type], ret: &Type) -> Type {
        let name = fat_name(params, ret);
        if !self.fat_types.contains_key(&name) {
            self.fat_types.insert(
                name.clone(),
                StructDef {
                    name: name.clone(),
                    fields: vec![
                        ("code".into(), Type::Ptr(Box::new(Type::U8))),
                        ("env".into(), Type::Ptr(Box::new(Type::U8))),
                    ],
                },
            );
            self.fat_sigs
                .insert(name.clone(), (params.to_vec(), ret.clone()));
        }
        Type::FnFat(params.to_vec(), Box::new(ret.clone()))
    }

    fn ensure_dyn_type(&mut self, trait_name: &str) -> Type {
        let trait_def = match self.trait_defs.get(trait_name) {
            Some(t) => t.clone(),
            None => return Type::Dyn(trait_name.to_string()),
        };
        let vt_name = vtable_name(trait_name);
        if !self.vt_structs.contains_key(&vt_name) {
            let mut fields = Vec::new();
            for m in &trait_def.methods {
                let mut ps = vec![Type::Ptr(Box::new(Type::U8))];
                for (n, t) in &m.params {
                    if n != "self" {
                        ps.push(t.clone());
                    }
                }
                fields.push((m.name.clone(), Type::Fn(ps, Box::new(m.ret.clone()))));
            }
            self.vt_structs.insert(vt_name.clone(), StructDef { name: vt_name.clone(), fields });
        }
        let dn = dyn_name(trait_name);
        if !self.dyn_structs.contains_key(&dn) {
            self.dyn_structs.insert(
                dn.clone(),
                StructDef {
                    name: dn,
                    fields: vec![
                        ("data".into(), Type::Ptr(Box::new(Type::U8))),
                        ("vt".into(), Type::Ptr(Box::new(Type::Named(vt_name)))),
                    ],
                },
            );
        }
        Type::Dyn(trait_name.to_string())
    }

    fn ensure_malloc(&mut self) {
        if self.generated_externs.iter().any(|e| e.name == "malloc") {
            return;
        }
        self.generated_externs.push(ExternFn {
            lib: None,
            name: "malloc".into(),
            params: vec![Type::U64],
            variadic: false,
            ret: Type::Ptr(Box::new(Type::U8)),
        });
    }

    fn fat_callee(&self, f: Expr, params: &[Type], ret: &Type) -> (Expr, Vec<Expr>) {
        let mut cps = vec![Type::Ptr(Box::new(Type::U8))];
        cps.extend_from_slice(params);
        let code = Expr::Cast(
            Box::new(Expr::Field(Box::new(f.clone()), "code".into())),
            Type::Fn(cps, Box::new(ret.clone())),
        );
        let env = Expr::Field(Box::new(f), "env".into());
        (code, vec![env])
    }

    fn coerce_args(&mut self, name: &str, args: Vec<Expr>) -> Result<Vec<Expr>, String> {
        let ps = match self.fn_params.get(name) {
            Some(p) => p.clone(),
            None => return Ok(args),
        };
        if ps.len() != args.len() {
            return Ok(args);
        }
        let mut out = Vec::with_capacity(args.len());
        for (a, p) in args.into_iter().zip(ps.iter()) {
            out.push(self.coerce_expr(a, p)?);
        }
        Ok(out)
    }

    fn coerce_expr(&mut self, e: Expr, want: &Type) -> Result<Expr, String> {
        match want {
            Type::FnFat(ps, ret) => {
                if matches!(self.expr_ty_hint(&e), Some(Type::FnFat(..))) {
                    return Ok(e);
                }
                match e {
                    Expr::FnRef(n) | Expr::Var(n) if self.fn_rets.contains_key(&n) => {
                        Ok(self.fat_from_fn(&n, ps, ret))
                    }
                    other => Ok(other),
                }
            }
            Type::Dyn(name) => {
                if matches!(self.expr_ty_hint(&e), Some(Type::Dyn(_))) {
                    return Ok(e);
                }
                self.dyn_from(e, name)
            }
            _ => Ok(e),
        }
    }

    fn fat_from_fn(&mut self, name: &str, params: &[Type], ret: &Type) -> Expr {
        let fat = match self.ensure_fat_type(params, ret) {
            Type::FnFat(ps, r) => fat_name(&ps, &r),
            _ => unreachable!(),
        };
        let an = format!("__adopt{}", self.adapter_count);
        self.adapter_count += 1;
        let mut wparams = vec![("__env".to_string(), Type::Ptr(Box::new(Type::U8)))];
        for (i, t) in params.iter().enumerate() {
            wparams.push((format!("a{}", i), t.clone()));
        }
        let args: Vec<Expr> = (0..params.len()).map(|i| Expr::Var(format!("a{}", i))).collect();
        let call = Expr::Call(name.to_string(), args);
        let body = if *ret == Type::Void {
            vec![Stmt::Expr(call), Stmt::Return(None)]
        } else {
            vec![Stmt::Return(Some(call))]
        };
        self.generated_fns.push(FnDef {
            name: an.clone(),
            tparams: Vec::new(),
            params: wparams,
            ret: ret.clone(),
            is_async: false,
            c_abi: false,
            body,
        });
        Expr::StructLit(
            fat,
            vec![
                (
                    "code".into(),
                    Expr::Cast(Box::new(Expr::FnRef(an)), Type::Ptr(Box::new(Type::U8))),
                ),
                ("env".into(), Expr::Cast(Box::new(Expr::Null), Type::Ptr(Box::new(Type::U8)))),
            ],
        )
    }

    fn dyn_from(&mut self, e: Expr, trait_name: &str) -> Result<Expr, String> {
        let trait_def = match self.trait_defs.get(trait_name) {
            Some(t) => t.clone(),
            None => return Err(format!("unknown trait '{}'", trait_name)),
        };
        let src = match self.expr_ty_hint(&e) {
            Some(t) => t,
            None => {
                return Err(format!(
                    "a value needs a known concrete type to become dyn {}",
                    trait_name
                ))
            }
        };
        let src = Self::peel_type(&src).clone();
        let type_name = match &src {
            Type::Named(n) => n.clone(),
            other => {
                return Err(format!(
                    "dyn {} needs a struct value, got {}",
                    trait_name,
                    crate::ast::type_key(other)
                ))
            }
        };
        let has = self
            .trait_impls
            .iter()
            .any(|i| i.trait_name == trait_name && i.type_name == type_name);
        if !has {
            return Err(format!("{} does not implement {}", type_name, trait_name));
        }
        let from_name = format!("__to_{}_{}", trait_name, type_name);
        if !self.generated_fns.iter().any(|f| f.name == from_name) {
            let mut fns = Vec::new();
            let vt_fn = format!("__vt_{}_{}", trait_name, type_name);
            for m in &trait_def.methods {
                let full = format!("{}__{}__{}", type_name, trait_name, m.name);
                let wn = format!("__w_{}_{}_{}", trait_name, type_name, m.name);
                let mut wparams = vec![("__d".to_string(), Type::Ptr(Box::new(Type::U8)))];
                let mut call_args = Vec::new();
                let kind = if m.self_kind == Some(true) {
                    SelfKind::Exclusive
                } else {
                    SelfKind::Shared
                };
                let recv = Expr::Deref(Box::new(Expr::Cast(
                    Box::new(Expr::Var("__d".into())),
                    Type::Ptr(Box::new(Type::Named(type_name.clone()))),
                )));
                call_args.push(match kind {
                    SelfKind::Shared => Expr::Addr(Box::new(recv)),
                    SelfKind::Exclusive => Expr::AddrMut(Box::new(recv)),
                });
                for (i, (pn, pt)) in m.params.iter().enumerate() {
                    if pn == "self" {
                        continue;
                    }
                    let arg = format!("a{}", i);
                    wparams.push((arg.clone(), pt.clone()));
                    call_args.push(Expr::Var(arg));
                }
                let call = Expr::Call(full, call_args);
                let body = if m.ret == Type::Void {
                    vec![Stmt::Unsafe(vec![Stmt::Expr(call)]), Stmt::Return(None)]
                } else {
                    vec![Stmt::Unsafe(vec![Stmt::Return(Some(call))])]
                };
                fns.push(FnDef {
                    name: wn,
                    tparams: Vec::new(),
                    params: wparams,
                    ret: m.ret.clone(),
                    is_async: false,
                    c_abi: false,
                    body,
                });
            }
            let vt_name = vtable_name(trait_name);
            let mut fields = Vec::new();
            for m in &trait_def.methods {
                fields.push((
                    m.name.clone(),
                    Expr::FnRef(format!("__w_{}_{}_{}", trait_name, type_name, m.name)),
                ));
            }
            let vt_body = vec![
                Stmt::Let {
                    mutable: false,
                    name: "__v".into(),
                    ty: Type::Ptr(Box::new(Type::Named(vt_name.clone()))),
                    init: Some(Expr::Cast(
                        Box::new(Expr::Call(
                            "malloc".into(),
                            vec![Expr::Sizeof(Type::Named(vt_name.clone()))],
                        )),
                        Type::Ptr(Box::new(Type::Named(vt_name.clone()))),
                    )),
                },
                Stmt::Unsafe(vec![Stmt::Assign(
                    "=".into(),
                    Expr::Deref(Box::new(Expr::Var("__v".into()))),
                    Expr::StructLit(vt_name.clone(), fields),
                )]),
                Stmt::Return(Some(Expr::Var("__v".into()))),
            ];
            fns.push(FnDef {
                name: vt_fn,
                tparams: Vec::new(),
                params: Vec::new(),
                ret: Type::Ptr(Box::new(Type::Named(vt_name))),
                is_async: false,
                c_abi: false,
                body: vt_body,
            });
            let dname = dyn_name(trait_name);
            let from_body = vec![
                Stmt::Let {
                    mutable: false,
                    name: "__p".into(),
                    ty: Type::Ptr(Box::new(Type::Named(type_name.clone()))),
                    init: Some(Expr::Cast(
                        Box::new(Expr::Call(
                            "malloc".into(),
                            vec![Expr::Sizeof(Type::Named(type_name.clone()))],
                        )),
                        Type::Ptr(Box::new(Type::Named(type_name.clone()))),
                    )),
                },
                Stmt::Unsafe(vec![Stmt::Assign(
                    "=".into(),
                    Expr::Deref(Box::new(Expr::Var("__p".into()))),
                    Expr::Var("__x".into()),
                )]),
                Stmt::Return(Some(Expr::StructLit(
                    dname,
                    vec![
                        (
                            "data".into(),
                            Expr::Cast(
                                Box::new(Expr::Var("__p".into())),
                                Type::Ptr(Box::new(Type::U8)),
                            ),
                        ),
                        ("vt".into(), Expr::Call(format!("__vt_{}_{}", trait_name, type_name), vec![])),
                    ],
                ))),
            ];
            fns.push(FnDef {
                name: from_name.clone(),
                tparams: Vec::new(),
                params: vec![("__x".into(), src)],
                ret: Type::Dyn(trait_name.to_string()),
                is_async: false,
                c_abi: false,
                body: from_body,
            });
            self.ensure_malloc();
            self.generated_fns.extend(fns);
        }
        Ok(Expr::Call(from_name, vec![e]))
    }

    pub fn parse_program(&mut self) -> Result<Program, String> {
        let mut p = Program::default();
        self.parse_items(&mut p, true)?;
        p.fns.append(&mut self.lifts);
        let traits: Vec<String> = self.trait_defs.keys().cloned().collect();
        for t in traits {
            self.ensure_dyn_type(&t);
        }
        p.structs.extend(self.fat_types.values().cloned());
        p.structs.extend(self.synthetic_structs.values().cloned());
        p.structs.extend(self.vt_structs.values().cloned());
        p.structs.extend(self.dyn_structs.values().cloned());
        p.externs.extend(self.generated_externs.drain(..));
        p.fns.extend(self.generated_fns.drain(..));
        for f in &p.fns {
            self.fn_rets.insert(f.name.clone(), f.ret.clone());
            self.fn_params
                .insert(f.name.clone(), f.params.iter().map(|(_, t)| t.clone()).collect());
        }
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
            } else if self.eat_kw("class") {
                p.structs.push(self.parse_struct()?);
            } else if self.eat_kw("trait") {
                p.traits.push(self.parse_trait()?);
            } else if self.eat_kw("enum") {
                p.enums.push(self.parse_enum()?);
            } else if self.eat_kw("extern") {
                if matches!(self.peek(), Tok::Str(s) if s == "C")
                    && matches!(self.peek_at(1), Some(Tok::Ident(k)) if k == "fn")
                {
                    self.bump();
                    self.bump();
                    let mut f = self.parse_fn()?;
                    f.c_abi = true;
                    p.fns.push(f);
                } else {
                    p.externs.extend(self.parse_extern()?);
                }
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
                    "expected 'const', 'struct', 'class', 'trait', 'enum', 'extern', 'static', 'mod', 'impl' or 'fn', found {}",
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

    fn parse_trait(&mut self) -> Result<TraitDef, String> {
        let pfx = self.pfx.clone();
        let name = format!("{}{}", pfx, self.type_name()?);
        self.expect_sym("{")?;
        let mut methods = Vec::new();
        while !self.at_sym("}") {
            if matches!(self.peek(), Tok::Eof) {
                return self.err("unexpected end of file inside a 'trait' block");
            }
            self.expect_kw("fn")?;
            let mname = self.name()?;
            self.expect_sym("(")?;
            let mut params = Vec::new();
            let mut self_kind = None;
            if !self.at_sym(")") {
                loop {
                    let (pname, pty) = if self.at_sym("&") {
                        self.bump();
                        let mutable = self.eat_kw("mut");
                        let pname = self.name()?;
                        if pname != "self" {
                            return Err(format!(
                                "line {}:{}: only 'self' can be written without a type",
                                self.cur().line, self.cur().col
                            ));
                        }
                        (pname, Type::Ref(Box::new(Type::SelfType), mutable))
                    } else {
                        let pname = self.name()?;
                        self.expect_sym(":")?;
                        (pname, self.parse_type()?)
                    };
                    if pname == "self" {
                        if !params.is_empty() {
                            return self.err("'self' must be the first parameter");
                        }
                        match &pty {
                            Type::Ref(inner, m) if **inner == Type::SelfType => {
                                self_kind = Some(*m);
                            }
                            _ => {
                                return Err(format!(
                                    "trait {}: 'self' must be &Self or &mut Self",
                                    name
                                ))
                            }
                        }
                    }
                    params.push((pname, pty));
                    if !self.eat_sym(",") {
                        break;
                    }
                }
            }
            self.expect_sym(")")?;
            let ret = if self.eat_sym("->") { self.parse_type()? } else { Type::Void };
            self.expect_sym(";")?;
            if self_kind.is_none() {
                return Err(format!("trait {}: method '{}' needs a self parameter", name, mname));
            }
            if methods.iter().any(|m: &TraitMethod| m.name == mname) {
                return Err(format!("trait {}: duplicate method '{}'", name, mname));
            }
            methods.push(TraitMethod { name: mname, params, ret, self_kind });
        }
        self.expect_sym("}")?;
        if methods.is_empty() {
            return Err(format!("trait '{}' needs at least one method", name));
        }
        let def = TraitDef { name: name.clone(), methods };
        self.trait_defs.insert(name, def.clone());
        Ok(def)
    }

    fn parse_impl(&mut self, p: &mut Program) -> Result<(), String> {
        let mut segs = vec![self.type_name()?];
        while self.at_sym("::") {
            self.bump();
            segs.push(self.type_name()?);
        }
        let first = if segs.len() == 1 {
            format!("{}{}", self.pfx, segs[0])
        } else {
            segs.join("__")
        };
        if self.eat_kw("for") {
            let trait_name = first;
            let trait_def = match self.trait_defs.get(&trait_name) {
                Some(t) => t.clone(),
                None => return Err(format!("unknown trait '{}'", trait_name)),
            };
            let mut tsegs = vec![self.type_name()?];
            while self.at_sym("::") {
                self.bump();
                tsegs.push(self.type_name()?);
            }
            let ty = if tsegs.len() == 1 {
                format!("{}{}", self.pfx, tsegs[0])
            } else {
                tsegs.join("__")
            };
            self.expect_sym("{")?;
            let mut done: Vec<String> = Vec::new();
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
                let saved = self.impl_ty.replace(ty.clone());
                let parsed = self.parse_fn_async(is_async);
                self.impl_ty = saved;
                let mut f = parsed?;
                let Some(want) = trait_def.methods.iter().find(|m| m.name == f.name) else {
                    return Err(format!(
                        "trait {} has no method '{}'",
                        trait_name, f.name
                    ));
                };
                if done.contains(&f.name) {
                    return Err(format!("trait {}: duplicate method '{}'", trait_name, f.name));
                }
                done.push(f.name.clone());
                let want = substitute_self(want, &ty);
                check_trait_method(&trait_name, &f, &want)?;
                let full = format!("{}__{}__{}", ty, trait_name, f.name);
                let kind = if let Some((n, t)) = f.params.first() {
                    if n == "self" {
                        match t {
                            Type::Ref(_, true) => SelfKind::Exclusive,
                            Type::Ref(_, false) => SelfKind::Shared,
                            _ => {
                                return Err(format!(
                                    "impl {} for {}: 'self' must be a reference",
                                    trait_name, ty
                                ))
                            }
                        }
                    } else {
                        SelfKind::Shared
                    }
                } else {
                    SelfKind::Shared
                };
                self.methods.push((f.name.clone(), full.clone(), kind));
                self.method_map
                    .entry((ty.clone(), f.name.clone()))
                    .or_default()
                    .push(MethodInfo { full: full.clone(), kind, trait_name: Some(trait_name.clone()) });
                f.name = full;
                self.fn_rets.insert(f.name.clone(), f.ret.clone());
                self.fn_params
                    .insert(f.name.clone(), f.params.iter().map(|(_, t)| t.clone()).collect());
                p.fns.push(f);
            }
            self.expect_sym("}")?;
            let missing: Vec<String> = trait_def
                .methods
                .iter()
                .filter(|m| !done.contains(&m.name))
                .map(|m| m.name.clone())
                .collect();
            if !missing.is_empty() {
                return Err(format!(
                    "impl {} for {}: missing method(s) {}",
                    trait_name,
                    ty,
                    missing.join(", ")
                ));
            }
            let methods = trait_def
                .methods
                .iter()
                .map(|m| substitute_self(m, &ty))
                .collect();
            self.trait_impls.push(TraitImplInfo { trait_name, type_name: ty, methods });
            return Ok(());
        }
        let ty = first;
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
            let saved = self.impl_ty.replace(ty.clone());
            let parsed = self.parse_fn_async(is_async);
            self.impl_ty = saved;
            let mut f = parsed?;
            let full = format!("{}__{}", ty, f.name);
            if let Some((first, fty)) = f.params.first() {
                if first == "self" {
                    let kind = match fty {
                        Type::Ref(_, true) => Some(SelfKind::Exclusive),
                        Type::Ref(_, false) => Some(SelfKind::Shared),
                        _ => None,
                    };
                    match kind {
                        Some(k) => {
                            self.methods.push((f.name.clone(), full.clone(), k));
                            self.method_map
                                .entry((ty.clone(), f.name.clone()))
                                .or_default()
                                .push(MethodInfo { full: full.clone(), kind: k, trait_name: None });
                        }
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
            self.fn_rets.insert(f.name.clone(), f.ret.clone());
            self.fn_params
                .insert(f.name.clone(), f.params.iter().map(|(_, t)| t.clone()).collect());
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
        self.struct_fields.insert(name.clone(), fields.clone());
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
            if s.is_empty()
                || !s.chars().all(|c| {
                    c.is_ascii_alphanumeric()
                        || c == '_'
                        || c == '.'
                        || c == '/'
                        || c == '\\'
                        || c == '-'
                        || c == ':'
                })
            {
                return self.err(
                    "a library tag is letters, digits, '_', '.', '/' or '-' - e.g. \"winhttp\" or \"python312.dll\"",
                );
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
                let (pname, mut pty) = if self.at_sym("&") {
                    self.bump();
                    let mutable = self.eat_kw("mut");
                    let pname = self.name()?;
                    if pname != "self" {
                        return Err(format!(
                            "line {}:{}: only 'self' can be written without a type",
                            self.cur().line, self.cur().col
                        ));
                    }
                    (pname, Type::Ref(Box::new(Type::SelfType), mutable))
                } else {
                    let pname = self.name()?;
                    self.expect_sym(":")?;
                    (pname, self.parse_type()?)
                };
                pty = self.subst_self(pty);
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
        let ret = if self.eat_sym("->") {
            self.parse_type()?
        } else {
            Type::Void
        };
        let ret = self.subst_self(ret);
        self.push_scope();
        for (pn, pt) in &params {
            self.bind(pn.clone(), pt.clone(), false);
        }
        self.ret_stack.push(ret.clone());
        let body = self.parse_body();
        self.ret_stack.pop();
        self.pop_scope();
        let body = body?;
        self.tparams = outer;
        let f = FnDef { name, tparams, params, ret, is_async, c_abi: false, body };
        self.fn_rets.insert(f.name.clone(), f.ret.clone());
        self.fn_params
            .insert(f.name.clone(), f.params.iter().map(|(_, t)| t.clone()).collect());
        Ok(f)
    }

    fn parse_block(&mut self) -> Result<Vec<Stmt>, String> {
        self.expect_sym("{")?;
        self.push_scope();
        let mut body = Vec::new();
        while !self.at_sym("}") {
            if matches!(self.peek(), Tok::Eof) {
                self.pop_scope();
                return self.err("unexpected end of file inside a block");
            }
            body.extend(self.parse_stmts()?);
        }
        self.expect_sym("}")?;
        self.pop_scope();
        Ok(body)
    }

    fn parse_run(&mut self) -> Result<Vec<Stmt>, String> {
        self.push_scope();
        let mut body = Vec::new();
        while !self.at_kw("end") && !self.at_kw("else") {
            if matches!(self.peek(), Tok::Eof) {
                self.pop_scope();
                return self.err("unexpected end of file; a block opened without '{' is closed by 'end;'");
            }
            body.extend(self.parse_stmts()?);
        }
        self.pop_scope();
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
            let vt = self.expr_ty_hint(&start).unwrap_or(Type::I64);
            self.push_scope();
            self.bind(var.clone(), vt, false);
            let body = self.parse_body();
            self.pop_scope();
            return Ok(Stmt::For { var, start, end, body: body? });
        }
        if self.eat_kw("match") {
            let scrut = self.parse_expr()?;
            self.expect_sym("{")?;
            let mut arms = Vec::new();
            while !self.at_sym("}") {
                let pat = self.parse_pat()?;
                self.expect_sym("=>")?;
                self.push_scope();
                if let Pat::Variant(_, _, binds) = &pat {
                    for b in binds {
                        self.bind(b.clone(), Type::Infer, false);
                    }
                }
                let body = self.parse_block();
                self.pop_scope();
                arms.push(Arm { pat, body: body? });
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
            let e = match self.ret_stack.last().cloned() {
                Some(ret) => self.coerce_expr(e, &ret)?,
                None => e,
            };
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
            let lo = if neg { n.wrapping_neg() } else { n };
            if self.eat_sym("..=") {
                let hneg = self.eat_sym("-");
                let hi = match *self.peek() {
                    Tok::Int(m) => {
                        self.bump();
                        if hneg { m.wrapping_neg() } else { m }
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
                let ft = self.field_type(&ty, &f).unwrap_or(Type::Infer);
                self.bind(b.clone(), ft.clone(), mutable);
                out.push(Stmt::Let {
                    mutable,
                    name: b,
                    ty: ft,
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
                self.bind(name.clone(), ty.clone(), false);
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
        let mut ty = if self.eat_sym(":") { self.parse_type()? } else { Type::Infer };
        let mut init = if self.eat_sym("=") { Some(self.parse_expr()?) } else { None };
        self.expect_sym(";")?;
        if ty == Type::Infer {
            if let Some(e) = &init {
                if let Some(t @ (Type::FnFat(..) | Type::Dyn(_))) = self.expr_ty_hint(e) {
                    ty = t;
                }
            }
        }
        if let Some(e) = init.take() {
            let e = self.coerce_expr(e, &ty)?;
            init = Some(e);
        }
        self.bind(name.clone(), ty.clone(), mutable);
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
            if let Some(Tok::Sym(">")) = self.peek_at(1) {
                return Some((">>", 8, 2));
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
                let hint = self.expr_ty_hint(&e);
                if let Some(Type::FnFat(ps, ret)) = hint {
                    let (code, mut all) = self.fat_callee(e, &ps, &ret);
                    all.extend(args);
                    e = Expr::CallV(Box::new(code), all);
                } else {
                    e = match e {
                        Expr::Var(n) => {
                            let args = self.coerce_args(&n, args)?;
                            Expr::Call(n, args)
                        }
                        other => Expr::CallV(Box::new(other), args),
                    };
                }
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
                    let hint = self.expr_ty_hint(&e);
                    if let Some(Type::Dyn(tn)) = &hint {
                        let Some(m) = self
                            .trait_defs
                            .get(tn)
                            .and_then(|t| t.methods.iter().find(|m| m.name == f))
                        else {
                            return Err(format!("trait {} has no method '{}'", tn, f));
                        };
                        if m.params.iter().filter(|(n, _)| n != "self").count() != args.len() {
                            return Err(format!(
                                "{}::{} takes {} argument(s), got {}",
                                tn,
                                f,
                                m.params.iter().filter(|(n, _)| n != "self").count(),
                                args.len()
                            ));
                        }
                        let vt =
                            Expr::Field(Box::new(Expr::Field(Box::new(e.clone()), "vt".into())), f);
                        let data = Expr::Field(Box::new(e), "data".into());
                        let mut all = vec![data];
                        all.extend(args);
                        e = Expr::CallV(Box::new(vt), all);
                    } else if let Some(info) = self.typed_method(&hint, &f) {
                        let kind = info.kind;
                        let full = info.full;
                        let args = self.coerce_args(&full, args)?;
                        let mut call = Vec::with_capacity(args.len() + 1);
                        call.push(match kind {
                            SelfKind::Shared => Expr::Addr(Box::new(e)),
                            SelfKind::Exclusive => Expr::AddrMut(Box::new(e)),
                        });
                        call.extend(args);
                        e = Expr::Call(full, call);
                    } else {
                        e = Expr::Method(Box::new(e), f, args);
                    }
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
                                    let args = self.parse_args()?;
                                    let args = self.coerce_args(&joined, args)?;
                                    return Ok(Expr::Call(joined, args));
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
                                    let assoc = format!("{}__{}", ty, vn);
                                    if self.fn_params.contains_key(&assoc) {
                                        let args = self.coerce_args(&assoc, args)?;
                                        return Ok(Expr::Call(assoc, args));
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
        self.push_scope();
        for (pn, pt) in &params {
            self.bind(pn.clone(), pt.clone(), false);
        }
        let body = self.parse_block();
        self.pop_scope();
        let mut body = body?;
        let mut bound: HashSet<String> = params.iter().map(|(n, _)| n.clone()).collect();
        let mut order = Vec::new();
        collect_free_stmts(&body, &mut bound, &mut order);
        let mut captures: Vec<(String, Type, String)> = Vec::new();
        for n in order {
            if let Some(b) = self.lookup_binding(&n) {
                let ty = if b.ty == Type::Infer {
                    return Err(format!(
                        "closure captures '{}', which needs a type annotation",
                        n
                    ));
                } else {
                    b.ty.clone()
                };
                let field = format!("c{}", captures.len());
                captures.push((n, ty, field));
            }
        }
        let idx = self.clo;
        self.clo += 1;
        if captures.is_empty() {
            let name = format!("__clo{}", idx);
            self.lifts.push(FnDef {
                name: name.clone(),
                tparams: Vec::new(),
                params,
                ret,
                is_async: false,
                c_abi: false,
                body,
            });
            return Ok(Expr::FnRef(name));
        }
        let env_name = format!("__Env{}", idx);
        let env_ty = Type::Ptr(Box::new(Type::Named(env_name.clone())));
        let fields: Vec<(String, Type)> = captures
            .iter()
            .map(|(_, ty, field)| (field.clone(), ty.clone()))
            .collect();
        self.synthetic_structs
            .insert(env_name.clone(), StructDef { name: env_name.clone(), fields });
        let mut map: CaptureMap = HashMap::new();
        for (n, ty, field) in &captures {
            let fat = match ty {
                Type::FnFat(ps, ret) => Some((ps.clone(), ret.as_ref().clone())),
                _ => None,
            };
            map.insert(n.clone(), (field.clone(), env_name.clone(), fat));
        }
        let env_var = format!("__env{}", idx);
        rewrite_captures_stmts(&mut body, &env_var, &map);
        let wrapper = format!("__clo{}", idx);
        let mut wparams = vec![(env_var.clone(), env_ty.clone())];
        wparams.extend(params.iter().cloned());
        self.lifts.push(FnDef {
            name: wrapper.clone(),
            tparams: Vec::new(),
            params: wparams,
            ret: ret.clone(),
            is_async: false,
            c_abi: false,
            body: vec![Stmt::Unsafe(body)],
        });
        let fat = self.ensure_fat_type(
            &params.iter().map(|(_, t)| t.clone()).collect::<Vec<_>>(),
            &ret,
        );
        let fat_name = match &fat {
            Type::FnFat(ps, r) => fat_name(ps, r),
            _ => unreachable!(),
        };
        let mk = format!("__mkclo{}", idx);
        let mut mk_params = Vec::new();
        let mut writes = Vec::new();
        for (i, (n, ty, field)) in captures.iter().enumerate() {
            let pn = format!("p{}", i);
            mk_params.push((pn.clone(), ty.clone()));
            writes.push(Stmt::Assign(
                "=".into(),
                Expr::Field(Box::new(Expr::Var("__e".into())), field.clone()),
                Expr::Var(pn),
            ));
            let _ = n;
        }
        let alloc = Expr::Cast(
            Box::new(Expr::Call(
                "malloc".into(),
                vec![Expr::Sizeof(Type::Named(env_name.clone()))],
            )),
            env_ty.clone(),
        );
        let mk_body = vec![
            Stmt::Let {
                mutable: false,
                name: "__e".into(),
                ty: env_ty.clone(),
                init: Some(alloc),
            },
            Stmt::Unsafe(writes),
            Stmt::Return(Some(Expr::StructLit(
                fat_name.clone(),
                vec![
                    (
                        "code".into(),
                        Expr::Cast(
                            Box::new(Expr::FnRef(wrapper)),
                            Type::Ptr(Box::new(Type::U8)),
                        ),
                    ),
                    (
                        "env".into(),
                        Expr::Cast(
                            Box::new(Expr::Var("__e".into())),
                            Type::Ptr(Box::new(Type::U8)),
                        ),
                    ),
                ],
            ))),
        ];
        self.fat_values.insert(
            mk.clone(),
            (params.iter().map(|(_, t)| t.clone()).collect(), ret.clone()),
        );
        self.generated_fns.push(FnDef {
            name: mk.clone(),
            tparams: Vec::new(),
            params: mk_params,
            ret: Type::Named(fat_name),
            is_async: false,
            c_abi: false,
            body: mk_body,
        });
        self.ensure_malloc();
        let args = captures.iter().map(|(n, _, _)| Expr::Var(n.clone())).collect();
        Ok(Expr::Call(mk, args))
    }

    fn parse_struct_lit(&mut self, name: String) -> Result<Expr, String> {
        self.expect_sym("{")?;
        let mut fields = Vec::new();
        while !self.at_sym("}") {
            let f = self.name()?;
            self.expect_sym(":")?;
            let mut v = self.parse_expr()?;
            if let Some(ft) = self.field_type(&Type::Named(name.clone()), &f) {
                v = self.coerce_expr(v, &ft)?;
            }
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

fn subst_self_type(t: &Type, ty: &str) -> Type {
    match t {
        Type::SelfType => Type::Named(ty.to_string()),
        Type::Ptr(inner) => Type::Ptr(Box::new(subst_self_type(inner, ty))),
        Type::Ref(inner, m) => Type::Ref(Box::new(subst_self_type(inner, ty)), *m),
        Type::Heap(inner) => Type::Heap(Box::new(subst_self_type(inner, ty))),
        Type::Array(inner, n) => Type::Array(Box::new(subst_self_type(inner, ty)), n.clone()),
        Type::Tuple(items) => Type::Tuple(items.iter().map(|x| subst_self_type(x, ty)).collect()),
        Type::Fn(ps, r) => Type::Fn(
            ps.iter().map(|x| subst_self_type(x, ty)).collect(),
            Box::new(subst_self_type(r, ty)),
        ),
        Type::FnC(ps, r) => Type::FnC(
            ps.iter().map(|x| subst_self_type(x, ty)).collect(),
            Box::new(subst_self_type(r, ty)),
        ),
        Type::FnFat(ps, r) => Type::FnFat(
            ps.iter().map(|x| subst_self_type(x, ty)).collect(),
            Box::new(subst_self_type(r, ty)),
        ),
        Type::Task(inner) => Type::Task(Box::new(subst_self_type(inner, ty))),
        other => other.clone(),
    }
}

fn substitute_self(m: &TraitMethod, ty: &str) -> TraitMethod {
    TraitMethod {
        name: m.name.clone(),
        params: m
            .params
            .iter()
            .map(|(n, t)| (n.clone(), subst_self_type(t, ty)))
            .collect(),
        ret: subst_self_type(&m.ret, ty),
        self_kind: m.self_kind,
    }
}

fn check_trait_method(trait_name: &str, f: &FnDef, want: &TraitMethod) -> Result<(), String> {
    if f.params.len() != want.params.len() {
        return Err(format!(
            "{}: method '{}' takes {} parameter(s); the trait declares {}",
            trait_name,
            f.name,
            f.params.len(),
            want.params.len()
        ));
    }
    for (i, ((_, got), (_, need))) in f.params.iter().zip(want.params.iter()).enumerate() {
        if got != need {
            return Err(format!(
                "{}: method '{}' parameter {} is {}; the trait declares {}",
                trait_name,
                f.name,
                i + 1,
                crate::ast::type_key(got),
                crate::ast::type_key(need)
            ));
        }
    }
    if f.ret != want.ret {
        return Err(format!(
            "{}: method '{}' returns {}; the trait declares {}",
            trait_name,
            f.name,
            crate::ast::type_key(&f.ret),
            crate::ast::type_key(&want.ret)
        ));
    }
    Ok(())
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
                0 => {
                    let target = recv.as_ref().clone();
                    let callee = Expr::Field(Box::new(target), name.clone());
                    let call_args = args.clone();
                    *e = Expr::CallV(Box::new(callee), call_args);
                }
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

fn collect_free_expr(e: &Expr, bound: &HashSet<String>, out: &mut Vec<String>) {
    let mut add = |n: &String| {
        if !bound.contains(n) && !out.contains(n) {
            out.push(n.clone());
        }
    };
    match e {
        Expr::Var(n) => add(n),
        Expr::Call(n, args) => {
            add(n);
            for a in args {
                collect_free_expr(a, bound, out);
            }
        }
        Expr::Bin(_, a, b) => {
            collect_free_expr(a, bound, out);
            collect_free_expr(b, bound, out);
        }
        Expr::Un(_, a) | Expr::Deref(a) | Expr::Addr(a) | Expr::AddrMut(a)
        | Expr::BoxNew(a) | Expr::Cast(a, _) | Expr::Await(a) | Expr::Poll(a) => {
            collect_free_expr(a, bound, out)
        }
        Expr::Index(a, b) => {
            collect_free_expr(a, bound, out);
            collect_free_expr(b, bound, out);
        }
        Expr::Field(a, _) => collect_free_expr(a, bound, out),
        Expr::StructLit(_, fs) => {
            for (_, v) in fs {
                collect_free_expr(v, bound, out);
            }
        }
        Expr::ArrayLit(items) | Expr::TupleLit(items) => {
            for it in items {
                collect_free_expr(it, bound, out);
            }
        }
        Expr::EnumLit(_, _, args) => {
            for a in args {
                collect_free_expr(a, bound, out);
            }
        }
        Expr::CallV(f, args) => {
            collect_free_expr(f, bound, out);
            for a in args {
                collect_free_expr(a, bound, out);
            }
        }
        Expr::Method(r, _, args) => {
            collect_free_expr(r, bound, out);
            for a in args {
                collect_free_expr(a, bound, out);
            }
        }
        _ => {}
    }
}

fn collect_free_stmts(body: &[Stmt], bound: &mut HashSet<String>, out: &mut Vec<String>) {
    for st in body {
        match st {
            Stmt::Let { name, init, .. } => {
                if let Some(e) = init {
                    collect_free_expr(e, bound, out);
                }
                bound.insert(name.clone());
            }
            Stmt::Assign(_, l, r) => {
                collect_free_expr(l, bound, out);
                collect_free_expr(r, bound, out);
            }
            Stmt::Expr(e) => collect_free_expr(e, bound, out),
            Stmt::Block(b) | Stmt::Unsafe(b) => {
                let mut inner = bound.clone();
                collect_free_stmts(b, &mut inner, out);
            }
            Stmt::If(c, th, el) => {
                collect_free_expr(c, bound, out);
                let mut t = bound.clone();
                collect_free_stmts(th, &mut t, out);
                let mut f = bound.clone();
                collect_free_stmts(el, &mut f, out);
            }
            Stmt::While(c, b) => {
                collect_free_expr(c, bound, out);
                let mut inner = bound.clone();
                collect_free_stmts(b, &mut inner, out);
            }
            Stmt::Loop(b) => {
                let mut inner = bound.clone();
                collect_free_stmts(b, &mut inner, out);
            }
            Stmt::For { var, start, end, body } => {
                collect_free_expr(start, bound, out);
                collect_free_expr(end, bound, out);
                let mut inner = bound.clone();
                inner.insert(var.clone());
                collect_free_stmts(body, &mut inner, out);
            }
            Stmt::Match(e, arms) => {
                collect_free_expr(e, bound, out);
                for a in arms {
                    let mut inner = bound.clone();
                    if let Pat::Variant(_, _, binds) = &a.pat {
                        for b in binds {
                            inner.insert(b.clone());
                        }
                    }
                    collect_free_stmts(&a.body, &mut inner, out);
                }
            }
            Stmt::Label(_, inner) => {
                let mut s = bound.clone();
                collect_free_stmts(std::slice::from_ref(inner.as_ref()), &mut s, out);
            }
            Stmt::Return(Some(e)) => collect_free_expr(e, bound, out),
            _ => {}
        }
    }
}

fn fat_call_expr(f: Expr, ps: &[Type], ret: &Type, args: Vec<Expr>) -> Expr {
    let mut cps = vec![Type::Ptr(Box::new(Type::U8))];
    cps.extend_from_slice(ps);
    let code = Expr::Cast(
        Box::new(Expr::Field(Box::new(f.clone()), "code".into())),
        Type::Fn(cps, Box::new(ret.clone())),
    );
    let env = Expr::Field(Box::new(f), "env".into());
    let mut all = vec![env];
    all.extend(args);
    Expr::CallV(Box::new(code), all)
}

type CaptureMap = HashMap<String, (String, String, Option<(Vec<Type>, Type)>)>;

fn rewrite_captures_expr(e: &mut Expr, env: &str, map: &CaptureMap) {
    match e {
        Expr::Var(n) => {
            if let Some((field, _, _)) = map.get(n) {
                *e = Expr::Field(Box::new(Expr::Var(env.to_string())), field.clone());
            }
        }
        Expr::Call(n, args) => {
            for a in args.iter_mut() {
                rewrite_captures_expr(a, env, map);
            }
            if let Some((field, _, fat)) = map.get(n) {
                let callee =
                    Expr::Field(Box::new(Expr::Var(env.to_string())), field.clone());
                let inner = args.clone();
                *e = match fat {
                    Some((ps, ret)) => fat_call_expr(callee, ps, ret, inner),
                    None => Expr::CallV(Box::new(callee), inner),
                };
            }
        }
        Expr::Bin(_, a, b) => {
            rewrite_captures_expr(a, env, map);
            rewrite_captures_expr(b, env, map);
        }
        Expr::Un(_, a) | Expr::Deref(a) | Expr::Addr(a) | Expr::AddrMut(a)
        | Expr::BoxNew(a) | Expr::Cast(a, _) | Expr::Await(a) | Expr::Poll(a) => {
            rewrite_captures_expr(a, env, map)
        }
        Expr::Index(a, b) => {
            rewrite_captures_expr(a, env, map);
            rewrite_captures_expr(b, env, map);
        }
        Expr::Field(a, _) => rewrite_captures_expr(a, env, map),
        Expr::StructLit(_, fs) => {
            for (_, v) in fs {
                rewrite_captures_expr(v, env, map);
            }
        }
        Expr::ArrayLit(items) | Expr::TupleLit(items) => {
            for it in items {
                rewrite_captures_expr(it, env, map);
            }
        }
        Expr::EnumLit(_, _, args) => {
            for a in args {
                rewrite_captures_expr(a, env, map);
            }
        }
        Expr::CallV(f, args) => {
            rewrite_captures_expr(f, env, map);
            for a in args {
                rewrite_captures_expr(a, env, map);
            }
        }
        Expr::Method(r, _, args) => {
            rewrite_captures_expr(r, env, map);
            for a in args {
                rewrite_captures_expr(a, env, map);
            }
        }
        _ => {}
    }
}

fn rewrite_captures_stmts(body: &mut [Stmt], env: &str, map: &CaptureMap) {
    for st in body {
        match st {
            Stmt::Let { init, .. } => {
                if let Some(e) = init {
                    rewrite_captures_expr(e, env, map);
                }
            }
            Stmt::Assign(_, l, r) => {
                rewrite_captures_expr(l, env, map);
                rewrite_captures_expr(r, env, map);
            }
            Stmt::Expr(e) => rewrite_captures_expr(e, env, map),
            Stmt::Block(b) | Stmt::Unsafe(b) => rewrite_captures_stmts(b, env, map),
            Stmt::If(c, th, el) => {
                rewrite_captures_expr(c, env, map);
                rewrite_captures_stmts(th, env, map);
                rewrite_captures_stmts(el, env, map);
            }
            Stmt::While(c, b) => {
                rewrite_captures_expr(c, env, map);
                rewrite_captures_stmts(b, env, map);
            }
            Stmt::Loop(b) => rewrite_captures_stmts(b, env, map),
            Stmt::For { start, end, body, .. } => {
                rewrite_captures_expr(start, env, map);
                rewrite_captures_expr(end, env, map);
                rewrite_captures_stmts(body, env, map);
            }
            Stmt::Match(e, arms) => {
                rewrite_captures_expr(e, env, map);
                for a in arms {
                    rewrite_captures_stmts(&mut a.body, env, map);
                }
            }
            Stmt::Label(_, inner) => {
                rewrite_captures_stmts(std::slice::from_mut(inner.as_mut()), env, map);
            }
            Stmt::Return(Some(e)) => rewrite_captures_expr(e, env, map),
            _ => {}
        }
    }
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

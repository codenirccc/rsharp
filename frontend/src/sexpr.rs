use crate::ast::*;

macro_rules! push {
    ($s:expr, $($arg:tt)*) => {{
        use std::fmt::Write as _;
        let _ = write!($s, $($arg)*);
    }};
}

fn c_escape(s: &str, out: &mut String) {
    out.push('"');
    for &b in s.as_bytes() {
        match b {
            b'\\' => out.push_str("\\\\"),
            b'"' => out.push_str("\\\""),
            b'\n' => out.push_str("\\n"),
            b'\t' => out.push_str("\\t"),
            b'\r' => out.push_str("\\r"),
            0x20..=0x7e => out.push(b as char),
            _ => {
                out.push('\\');
                out.push((b'0' + (b >> 6)) as char);
                out.push((b'0' + ((b >> 3) & 7)) as char);
                out.push((b'0' + (b & 7)) as char);
            }
        }
    }
    out.push('"');
}

fn type_w(t: &Type, s: &mut String) {
    match t {
        Type::I8 => s.push_str("i8"),
        Type::I16 => s.push_str("i16"),
        Type::I32 => s.push_str("i32"),
        Type::I64 => s.push_str("i64"),
        Type::U8 => s.push_str("u8"),
        Type::U16 => s.push_str("u16"),
        Type::U32 => s.push_str("u32"),
        Type::U64 => s.push_str("u64"),
        Type::F32 => s.push_str("f32"),
        Type::F64 => s.push_str("f64"),
        Type::Bool => s.push_str("bool"),
        Type::Void => s.push_str("void"),
        Type::Ptr(inner) => {
            s.push_str("(ptr ");
            type_w(inner, s);
            s.push(')');
        }
        Type::Ref(inner, false) => {
            s.push_str("(ref ");
            type_w(inner, s);
            s.push(')');
        }
        Type::Ref(inner, true) => {
            s.push_str("(refmut ");
            type_w(inner, s);
            s.push(')');
        }
        Type::Heap(inner) => {
            s.push_str("(box ");
            type_w(inner, s);
            s.push(')');
        }
        Type::Array(inner, size) => {
            s.push_str("(array ");
            type_w(inner, s);
            s.push(' ');
            match size {
                Size::Lit(n) => push!(s, "{}", n),
                Size::Name(c) => s.push_str(c),
            }
            s.push(')');
        }
        Type::Named(n) => {
            s.push_str("(named ");
            s.push_str(n);
            s.push(')');
        }
        Type::Infer => s.push_str("(infer)"),
        Type::Tuple(items) => {
            s.push_str("(tup");
            for t in items {
                s.push(' ');
                type_w(t, s);
            }
            s.push(')');
        }
        Type::Fn(params, ret) => {
            s.push_str("(fnty (");
            for (i, p) in params.iter().enumerate() {
                if i > 0 {
                    s.push(' ');
                }
                type_w(p, s);
            }
            s.push_str(") ");
            type_w(ret, s);
            s.push(')');
        }
        Type::Task(inner) => {
            s.push_str("(task ");
            type_w(inner, s);
            s.push(')');
        }
        Type::Param(n) => {
            s.push_str("(var ");
            s.push_str(n);
            s.push(')');
        }
    }
}

fn expr_w(e: &Expr, s: &mut String) {
    match e {
        Expr::Int(n) => {
            s.push_str("(int ");
            push!(s, "{}", n);
            s.push(')');
        }
        Expr::Float(f) => {
            s.push_str("(float ");
            push!(s, "{:?}", f);
            s.push(')');
        }
        Expr::Str(text) => {
            s.push_str("(str ");
            c_escape(text, s);
            s.push(')');
        }
        Expr::Bool(b) => {
            s.push_str(if *b { "(bool true)" } else { "(bool false)" });
        }
        Expr::Null => s.push_str("(null)"),
        Expr::Var(n) => {
            s.push_str("(var ");
            s.push_str(n);
            s.push(')');
        }
        Expr::Bin(op, a, b) => {
            s.push_str("(bin ");
            s.push_str(op);
            s.push(' ');
            expr_w(a, s);
            s.push(' ');
            expr_w(b, s);
            s.push(')');
        }
        Expr::Un(op, a) => {
            s.push_str("(un ");
            s.push_str(op);
            s.push(' ');
            expr_w(a, s);
            s.push(')');
        }
        Expr::Call(n, args) => {
            s.push_str("(call ");
            s.push_str(n);
            for a in args {
                s.push(' ');
                expr_w(a, s);
            }
            s.push(')');
        }
        Expr::Index(b, i) => {
            s.push_str("(index ");
            expr_w(b, s);
            s.push(' ');
            expr_w(i, s);
            s.push(')');
        }
        Expr::Field(b, f) => {
            s.push_str("(field ");
            expr_w(b, s);
            s.push(' ');
            s.push_str(f);
            s.push(')');
        }
        Expr::Deref(p) => {
            s.push_str("(deref ");
            expr_w(p, s);
            s.push(')');
        }
        Expr::Addr(a) => {
            s.push_str("(addr ");
            expr_w(a, s);
            s.push(')');
        }
        Expr::AddrMut(a) => {
            s.push_str("(addrmut ");
            expr_w(a, s);
            s.push(')');
        }
        Expr::BoxNew(a) => {
            s.push_str("(boxnew ");
            expr_w(a, s);
            s.push(')');
        }
        Expr::Cast(a, t) => {
            s.push_str("(cast ");
            expr_w(a, s);
            s.push(' ');
            type_w(t, s);
            s.push(')');
        }
        Expr::Sizeof(t) => {
            s.push_str("(sizeof ");
            type_w(t, s);
            s.push(')');
        }
        Expr::Zero(t) => {
            s.push_str("(zero ");
            type_w(t, s);
            s.push(')');
        }
        Expr::StructLit(n, fields) => {
            s.push_str("(structlit ");
            s.push_str(n);
            for (f, v) in fields {
                s.push_str(" (field ");
                s.push_str(f);
                s.push(' ');
                expr_w(v, s);
                s.push(')');
            }
            s.push(')');
        }
        Expr::ArrayLit(items) => {
            s.push_str("(arraylit");
            for it in items {
                s.push(' ');
                expr_w(it, s);
            }
            s.push(')');
        }
        Expr::EnumLit(en, vn, args) => {
            s.push_str("(enumlit ");
            s.push_str(en);
            s.push(' ');
            s.push_str(vn);
            for a in args {
                s.push(' ');
                expr_w(a, s);
            }
            s.push(')');
        }
        Expr::TupleLit(items) => {
            s.push_str("(tuplelit");
            for it in items {
                s.push(' ');
                expr_w(it, s);
            }
            s.push(')');
        }
        Expr::FnRef(n) => {
            s.push_str("(fnref ");
            s.push_str(n);
            s.push(')');
        }
        Expr::CallV(callee, args) => {
            s.push_str("(callv ");
            expr_w(callee, s);
            for a in args {
                s.push(' ');
                expr_w(a, s);
            }
            s.push(')');
        }
        Expr::Await(e) => {
            s.push_str("(await ");
            expr_w(e, s);
            s.push(')');
        }
        Expr::Poll(e) => {
            s.push_str("(poll ");
            expr_w(e, s);
            s.push(')');
        }
        Expr::Method(r, n, args) => {
            s.push_str("(method ");
            expr_w(r, s);
            s.push(' ');
            s.push_str(n);
            for a in args {
                s.push(' ');
                expr_w(a, s);
            }
            s.push(')');
        }
    }
}

fn ind(d: usize, s: &mut String) {
    for _ in 0..d {
        s.push_str("  ");
    }
}

fn emit_block(body: &[Stmt], d: usize, s: &mut String) {
    for st in body {
        emit_stmt(st, d, s);
    }
}

fn emit_stmt(st: &Stmt, d: usize, s: &mut String) {
    match st {
        Stmt::Let { mutable, name, ty, init } => {
            ind(d, s);
            s.push_str(if *mutable { "(var " } else { "(let " });
            s.push_str(name);
            s.push(' ');
            type_w(ty, s);
            if let Some(e) = init {
                s.push(' ');
                expr_w(e, s);
            }
            s.push_str(")\n");
        }
        Stmt::Assign(op, l, r) => {
            ind(d, s);
            s.push_str("(assign ");
            s.push_str(op);
            s.push(' ');
            expr_w(l, s);
            s.push(' ');
            expr_w(r, s);
            s.push_str(")\n");
        }
        Stmt::Expr(e) => {
            ind(d, s);
            s.push_str("(expr ");
            expr_w(e, s);
            s.push_str(")\n");
        }
        Stmt::Block(body) => {
            ind(d, s);
            s.push_str("(block\n");
            emit_block(body, d + 1, s);
            ind(d, s);
            s.push_str(")\n");
        }
        Stmt::Unsafe(body) => {
            ind(d, s);
            s.push_str("(unsafe\n");
            emit_block(body, d + 1, s);
            ind(d, s);
            s.push_str(")\n");
        }
        Stmt::If(c, th, el) => {
            ind(d, s);
            s.push_str("(if ");
            expr_w(c, s);
            s.push('\n');
            ind(d + 1, s);
            s.push_str("(then\n");
            emit_block(th, d + 2, s);
            ind(d + 1, s);
            s.push_str(")\n");
            if !el.is_empty() {
                ind(d + 1, s);
                s.push_str("(else\n");
                emit_block(el, d + 2, s);
                ind(d + 1, s);
                s.push_str(")\n");
            }
            ind(d, s);
            s.push_str(")\n");
        }
        Stmt::While(c, body) => {
            ind(d, s);
            s.push_str("(while ");
            expr_w(c, s);
            s.push('\n');
            emit_block(body, d + 1, s);
            ind(d, s);
            s.push_str(")\n");
        }
        Stmt::Loop(body) => {
            ind(d, s);
            s.push_str("(loop\n");
            emit_block(body, d + 1, s);
            ind(d, s);
            s.push_str(")\n");
        }
        Stmt::For { var, start, end, body } => {
            ind(d, s);
            s.push_str("(for ");
            s.push_str(var);
            s.push(' ');
            expr_w(start, s);
            s.push(' ');
            expr_w(end, s);
            s.push('\n');
            emit_block(body, d + 1, s);
            ind(d, s);
            s.push_str(")\n");
        }
        Stmt::Match(scrut, arms) => {
            ind(d, s);
            s.push_str("(match ");
            expr_w(scrut, s);
            s.push('\n');
            for a in arms {
                ind(d + 1, s);
                match &a.pat {
                    Pat::Wild => s.push_str("(arm (pat wild)\n"),
                    Pat::Lit(n) => {
                        s.push_str("(arm (pat lit ");
                        push!(s, "{}", n);
                        s.push_str(")\n");
                    }
                    Pat::Range(a, b) => {
                        s.push_str("(arm (pat range ");
                        push!(s, "{}", a);
                        s.push(' ');
                        push!(s, "{}", b);
                        s.push_str(")\n");
                    }
                    Pat::Variant(en, vn, binds) => {
                        s.push_str("(arm (pat ");
                        s.push_str(en);
                        s.push(' ');
                        s.push_str(vn);
                        for b in binds {
                            s.push(' ');
                            s.push_str(b);
                        }
                        s.push_str(")\n");
                    }
                }
                ind(d + 2, s);
                s.push_str("(body\n");
                emit_block(&a.body, d + 3, s);
                ind(d + 2, s);
                s.push_str(")\n");
                ind(d + 1, s);
                s.push_str(")\n");
            }
            ind(d, s);
            s.push_str(")\n");
        }
        Stmt::Break(l) => {
            ind(d, s);
            match l {
                Some(n) => {
                    s.push_str("(break ");
                    s.push_str(n);
                    s.push_str(")\n");
                }
                None => s.push_str("(break)\n"),
            }
        }
        Stmt::Continue(l) => {
            ind(d, s);
            match l {
                Some(n) => {
                    s.push_str("(continue ");
                    s.push_str(n);
                    s.push_str(")\n");
                }
                None => s.push_str("(continue)\n"),
            }
        }
        Stmt::Label(n, inner) => {
            ind(d, s);
            s.push_str("(label ");
            s.push_str(n);
            s.push('\n');
            emit_stmt(inner, d + 1, s);
            ind(d, s);
            s.push_str(")\n");
        }
        Stmt::Return(None) => {
            ind(d, s);
            s.push_str("(return)\n");
        }
        Stmt::Return(Some(e)) => {
            ind(d, s);
            s.push_str("(return ");
            expr_w(e, s);
            s.push_str(")\n");
        }
    }
}

pub fn emit_program(p: &Program, hint: usize) -> String {
    let mut s = String::with_capacity(hint.saturating_mul(2).saturating_add(4096));
    s.push_str("(program\n");

    for c in &p.consts {
        s.push_str("  (const ");
        s.push_str(&c.name);
        s.push(' ');
        type_w(&c.ty, &mut s);
        s.push(' ');
        expr_w(&c.value, &mut s);
        s.push_str(")\n");
    }

    for g in &p.globals {
        s.push_str("  (static ");
        s.push_str(&g.name);
        s.push(' ');
        type_w(&g.ty, &mut s);
        s.push(' ');
        expr_w(&g.init, &mut s);
        s.push_str(if g.mutable { " mut)\n" } else { " const)\n" });
    }

    for st in &p.structs {
        s.push_str("  (struct ");
        s.push_str(&st.name);
        s.push('\n');
        for (n, t) in &st.fields {
            s.push_str("    (field ");
            s.push_str(n);
            s.push(' ');
            type_w(t, &mut s);
            s.push_str(")\n");
        }
        s.push_str("  )\n");
    }

    for en in &p.enums {
        s.push_str("  (enum ");
        s.push_str(&en.name);
        s.push('\n');
        for v in &en.variants {
            s.push_str("    (variant ");
            s.push_str(&v.name);
            if !v.payload.is_empty() {
                s.push_str(" (payload");
                for t in &v.payload {
                    s.push(' ');
                    type_w(t, &mut s);
                }
                s.push(')');
            }
            s.push_str(")\n");
        }
        s.push_str("  )\n");
    }

    for ex in &p.externs {
        s.push_str("  (extern ");
        s.push_str(&ex.name);
        s.push('\n');
        if let Some(l) = &ex.lib {
            s.push_str("    (lib \"");
            s.push_str(l);
            s.push_str("\")\n");
        }
        for t in &ex.params {
            s.push_str("    (param ");
            type_w(t, &mut s);
            s.push_str(")\n");
        }
        if ex.variadic {
            s.push_str("    (variadic)\n");
        }
        s.push_str("    (ret ");
        type_w(&ex.ret, &mut s);
        s.push_str(")\n");
        s.push_str("  )\n");
    }

    for f in &p.fns {
        s.push_str("  (fn ");
        s.push_str(&f.name);
        s.push('\n');
        if !f.tparams.is_empty() {
            s.push_str("    (generic ");
            for (i, t) in f.tparams.iter().enumerate() {
                if i > 0 {
                    s.push(' ');
                }
                s.push_str(t);
            }
            s.push_str(")\n");
        }
        for (n, t) in &f.params {
            s.push_str("    (param ");
            s.push_str(n);
            s.push(' ');
            type_w(t, &mut s);
            s.push_str(")\n");
        }
        s.push_str("    (ret ");
        type_w(&f.ret, &mut s);
        s.push_str(")\n");
        if f.is_async {
            s.push_str("    (async)\n");
        }
        s.push_str("    (body\n");
        emit_block(&f.body, 3, &mut s);
        s.push_str("    )\n");
        s.push_str("  )\n");
    }

    s.push_str(")\n");
    s
}

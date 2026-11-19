#[derive(Clone, Debug, PartialEq)]
pub enum Size {
    Lit(u64),
    Name(String),
}

#[derive(Clone, Debug, PartialEq)]
pub enum Type {
    I8,
    I16,
    I32,
    I64,
    U8,
    U16,
    U32,
    U64,
    F32,
    F64,
    Bool,
    Void,
    Ptr(Box<Type>),
    Ref(Box<Type>, bool),
    Heap(Box<Type>),
    Array(Box<Type>, Size),
    Named(String),
    Infer,
    Tuple(Vec<Type>),
    Fn(Vec<Type>, Box<Type>),
    FnC(Vec<Type>, Box<Type>),
    FnFat(Vec<Type>, Box<Type>),
    Dyn(String),
    Task(Box<Type>),
    Param(String),
    SelfType,
}

impl Type {
    pub fn from_name(s: &str) -> Option<Type> {
        Some(match s {
            "i8" => Type::I8,
            "i16" => Type::I16,
            "i32" => Type::I32,
            "i64" => Type::I64,
            "u8" => Type::U8,
            "u16" => Type::U16,
            "u32" => Type::U32,
            "u64" => Type::U64,
            "f32" => Type::F32,
            "f64" => Type::F64,
            "bool" => Type::Bool,
            "void" => Type::Void,
            _ => return None,
        })
    }
}

pub fn type_key(t: &Type) -> String {
    match t {
        Type::I8 => "i8".into(),
        Type::I16 => "i16".into(),
        Type::I32 => "i32".into(),
        Type::I64 => "i64".into(),
        Type::U8 => "u8".into(),
        Type::U16 => "u16".into(),
        Type::U32 => "u32".into(),
        Type::U64 => "u64".into(),
        Type::F32 => "f32".into(),
        Type::F64 => "f64".into(),
        Type::Bool => "bool".into(),
        Type::Void => "void".into(),
        Type::Ptr(inner) => format!("p{}", type_key(inner)),
        Type::Ref(inner, m) => format!("{}{}", if *m { "m" } else { "r" }, type_key(inner)),
        Type::Heap(inner) => format!("b{}", type_key(inner)),
        Type::Array(inner, n) => match n {
            Size::Lit(k) => format!("a{}{}", k, type_key(inner)),
            Size::Name(name) => format!("a{}{}", name, type_key(inner)),
        },
        Type::Named(n) => format!("n{}", n),
        Type::Infer => "?".into(),
        Type::Tuple(items) => {
            let mut s = String::from("t");
            for it in items {
                s.push_str(&type_key(it));
                s.push('_');
            }
            s
        }
        Type::Fn(ps, r) => {
            let mut s = String::from("f");
            for p in ps {
                s.push_str(&type_key(p));
                s.push('_');
            }
            s.push_str(&type_key(r));
            s
        }
        Type::FnC(ps, r) => {
            let mut s = String::from("c");
            for p in ps {
                s.push_str(&type_key(p));
                s.push('_');
            }
            s.push_str(&type_key(r));
            s
        }
        Type::FnFat(ps, r) => {
            let mut s = String::from("F");
            for p in ps {
                s.push_str(&type_key(p));
                s.push('_');
            }
            s.push_str(&type_key(r));
            s
        }
        Type::Dyn(name) => format!("d{}", name),
        Type::Task(inner) => format!("k{}", type_key(inner)),
        Type::Param(n) => format!("v{}", n),
        Type::SelfType => "self".into(),
    }
}

pub fn hash64(s: &str) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in s.as_bytes() {
        h ^= *b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    h
}

pub fn fat_name(ps: &[Type], ret: &Type) -> String {
    let mut key = String::from("Fn(");
    for p in ps {
        key.push_str(&type_key(p));
        key.push(',');
    }
    key.push_str(")->");
    key.push_str(&type_key(ret));
    format!("__Fn_{:016x}", hash64(&key))
}

pub fn dyn_name(trait_name: &str) -> String {
    format!("__Dyn_{:016x}", hash64(trait_name))
}

pub fn vtable_name(trait_name: &str) -> String {
    format!("__Vt_{:016x}", hash64(trait_name))
}

#[derive(Clone, Debug)]
pub enum Expr {
    Int(i64),
    Float(f64),
    Str(String),
    Bool(bool),
    Null,
    Var(String),
    Bin(String, Box<Expr>, Box<Expr>),
    Un(String, Box<Expr>),
    Call(String, Vec<Expr>),
    Index(Box<Expr>, Box<Expr>),
    Field(Box<Expr>, String),
    Deref(Box<Expr>),
    Addr(Box<Expr>),
    AddrMut(Box<Expr>),
    BoxNew(Box<Expr>),
    Cast(Box<Expr>, Type),
    Sizeof(Type),
    Zero(Type),
    StructLit(String, Vec<(String, Expr)>),
    ArrayLit(Vec<Expr>),
    EnumLit(String, String, Vec<Expr>),
    TupleLit(Vec<Expr>),
    FnRef(String),
    CallV(Box<Expr>, Vec<Expr>),
    Await(Box<Expr>),
    Poll(Box<Expr>),
    Method(Box<Expr>, String, Vec<Expr>),
}

#[derive(Clone, Debug)]
pub enum Pat {
    Wild,
    Variant(String, String, Vec<String>),
    Lit(i64),
    Range(i64, i64),
}

#[derive(Clone, Debug)]
pub struct Arm {
    pub pat: Pat,
    pub body: Vec<Stmt>,
}

#[derive(Clone, Debug)]
pub enum Stmt {
    Let { mutable: bool, name: String, ty: Type, init: Option<Expr> },
    Assign(String, Expr, Expr),
    Expr(Expr),
    Block(Vec<Stmt>),
    Unsafe(Vec<Stmt>),
    If(Expr, Vec<Stmt>, Vec<Stmt>),
    While(Expr, Vec<Stmt>),
    Loop(Vec<Stmt>),
    For { var: String, start: Expr, end: Expr, body: Vec<Stmt> },
    Match(Expr, Vec<Arm>),
    Break(Option<String>),
    Continue(Option<String>),
    Label(String, Box<Stmt>),
    Return(Option<Expr>),
}

#[derive(Clone, Debug)]
pub struct StaticDef {
    pub name: String,
    pub ty: Type,
    pub mutable: bool,
    pub init: Expr,
}

#[derive(Clone, Debug)]
pub struct ConstDef {
    pub name: String,
    pub ty: Type,
    pub value: Expr,
}

#[derive(Clone, Debug)]
pub struct StructDef {
    pub name: String,
    pub fields: Vec<(String, Type)>,
}

#[derive(Clone, Debug)]
pub struct Variant {
    pub name: String,
    pub payload: Vec<Type>,
}

#[derive(Clone, Debug)]
pub struct EnumDef {
    pub name: String,
    pub variants: Vec<Variant>,
}

#[derive(Clone, Debug)]
pub struct ExternFn {
    pub lib: Option<String>,
    pub name: String,
    pub params: Vec<Type>,
    pub variadic: bool,
    pub ret: Type,
}

#[derive(Clone, Debug)]
pub struct TraitMethod {
    pub name: String,
    pub params: Vec<(String, Type)>,
    pub ret: Type,
    pub self_kind: Option<bool>,
}

#[derive(Clone, Debug)]
pub struct TraitDef {
    pub name: String,
    pub methods: Vec<TraitMethod>,
}

#[derive(Clone, Debug)]
pub struct FnDef {
    pub name: String,
    pub tparams: Vec<String>,
    pub params: Vec<(String, Type)>,
    pub ret: Type,
    pub is_async: bool,
    pub c_abi: bool,
    pub body: Vec<Stmt>,
}

#[derive(Clone, Debug, Default)]
pub struct Program {
    pub consts: Vec<ConstDef>,
    pub globals: Vec<StaticDef>,
    pub structs: Vec<StructDef>,
    pub enums: Vec<EnumDef>,
    pub externs: Vec<ExternFn>,
    pub fns: Vec<FnDef>,
    pub traits: Vec<TraitDef>,
}

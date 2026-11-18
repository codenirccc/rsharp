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
    Task(Box<Type>),
    Param(String),
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
}

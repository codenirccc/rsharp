type typ =
  | TI8
  | TI16
  | TI32
  | TI64
  | TU8
  | TU16
  | TU32
  | TU64
  | TF32
  | TF64
  | TBool
  | TVoid
  | TPtr of typ
  | TRef of typ * bool
  | TBox of typ
  | TArray of typ * int
  | TStruct of string
  | TEnum of string
  | TTuple of typ list
  | TFn of typ list * typ
  | TFnC of typ list * typ
  | TTask of typ
  | TVar of string
  | TInfer
  | TErr

let rec to_string = function
  | TI8 -> "i8"
  | TI16 -> "i16"
  | TI32 -> "i32"
  | TI64 -> "i64"
  | TU8 -> "u8"
  | TU16 -> "u16"
  | TU32 -> "u32"
  | TU64 -> "u64"
  | TF32 -> "f32"
  | TF64 -> "f64"
  | TBool -> "bool"
  | TVoid -> "void"
  | TPtr t -> "ptr<" ^ to_string t ^ ">"
  | TRef (t, true) -> "&mut " ^ to_string t
  | TRef (t, false) -> "&" ^ to_string t
  | TBox t -> "Box<" ^ to_string t ^ ">"
  | TArray (t, n) -> Printf.sprintf "[%s; %d]" (to_string t) n
  | TStruct s -> s
  | TEnum s -> s
  | TTuple ts -> "(" ^ String.concat ", " (List.map to_string ts) ^ ")"
  | TFn (ps, r) ->
      "fn(" ^ String.concat ", " (List.map to_string ps) ^ ") -> " ^ to_string r
  | TFnC (ps, r) ->
      "extern fn(" ^ String.concat ", " (List.map to_string ps) ^ ") -> " ^ to_string r
  | TTask t -> "Task<" ^ to_string t ^ ">"
  | TVar v -> v
  | TInfer -> "_"
  | TErr -> "<error>"

let rec subst_typ (sub : (string * typ) list) (t : typ) : typ =
  match t with
  | TVar v -> ( match List.assoc_opt v sub with Some t -> t | None -> t)
  | TPtr t -> TPtr (subst_typ sub t)
  | TRef (t, m) -> TRef (subst_typ sub t, m)
  | TBox t -> TBox (subst_typ sub t)
  | TArray (t, n) -> TArray (subst_typ sub t, n)
  | TTuple ts -> TTuple (List.map (subst_typ sub) ts)
  | TFn (ps, r) -> TFn (List.map (subst_typ sub) ps, subst_typ sub r)
  | TFnC (ps, r) -> TFnC (List.map (subst_typ sub) ps, subst_typ sub r)
  | TTask t -> TTask (subst_typ sub t)
  | t -> t

let is_int = function
  | TI8 | TI16 | TI32 | TI64 | TU8 | TU16 | TU32 | TU64 -> true
  | _ -> false

let is_float = function TF32 | TF64 -> true | _ -> false
let is_numeric t = is_int t || is_float t
let is_signed = function TI8 | TI16 | TI32 | TI64 -> true | _ -> false
let is_array = function TArray _ -> true | _ -> false

let is_ref = function TRef _ -> true | _ -> false

let is_pointer = function TPtr _ -> true | _ -> false
let is_heap = function TBox _ -> true | _ -> false
let is_enum = function TEnum _ -> true | _ -> false
let is_tuple = function TTuple _ -> true | _ -> false
let is_fn = function TFn _ | TFnC _ -> true | _ -> false
let is_c_fn = function TFnC _ -> true | _ -> false
let is_task = function TTask _ -> true | _ -> false
let rec peel_ref = function TRef (t, _) -> peel_ref t | t -> t

type expr = { mutable node : expr_node; mutable ty : typ }

and expr_node =
  | EInt of int64
  | EFloat of float
  | EStr of string
  | EBool of bool
  | ENull
  | EVar of string
  | EBin of string * expr * expr
  | EUn of string * expr
  | ECall of string * expr list
  | EIndex of expr * expr
  | EField of expr * string
  | EDeref of expr
  | EAddr of expr
  | EAddrMut of expr
  | EBoxNew of expr
  | ECast of expr * typ
  | ESizeof of typ
  | EZero of typ
  | EStructLit of string * (string * expr) list
  | EArrayLit of expr list
  | EEnumLit of string * string * expr list
  | ETupleLit of expr list
  | EFnRef of string
  | ECallV of expr * expr list
  | EAwait of expr
  | EPoll of expr

module ESet = Hashtbl.Make (struct
  type t = expr

  let equal (a : expr) (b : expr) = a == b
  let hash (e : expr) = Hashtbl.hash e
end)

let rec copy_expr (e : expr) : expr = { node = copy_node e.node; ty = e.ty }
and copy_node = function
  | EInt n -> EInt n
  | EFloat f -> EFloat f
  | EStr s -> EStr s
  | EBool b -> EBool b
  | ENull -> ENull
  | EVar n -> EVar n
  | EBin (op, a, b) -> EBin (op, copy_expr a, copy_expr b)
  | EUn (op, a) -> EUn (op, copy_expr a)
  | ECall (n, args) -> ECall (n, List.map copy_expr args)
  | EIndex (a, i) -> EIndex (copy_expr a, copy_expr i)
  | EField (a, f) -> EField (copy_expr a, f)
  | EDeref a -> EDeref (copy_expr a)
  | EAddr a -> EAddr (copy_expr a)
  | EAddrMut a -> EAddrMut (copy_expr a)
  | EBoxNew a -> EBoxNew (copy_expr a)
  | ECast (a, t) -> ECast (copy_expr a, t)
  | ESizeof t -> ESizeof t
  | EZero t -> EZero t
  | EStructLit (n, fs) -> EStructLit (n, List.map (fun (f, v) -> (f, copy_expr v)) fs)
  | EArrayLit items -> EArrayLit (List.map copy_expr items)
  | EEnumLit (e, v, args) -> EEnumLit (e, v, List.map copy_expr args)
  | ETupleLit items -> ETupleLit (List.map copy_expr items)
  | EFnRef n -> EFnRef n
  | ECallV (f, args) -> ECallV (copy_expr f, List.map copy_expr args)
  | EAwait a -> EAwait (copy_expr a)
  | EPoll a -> EPoll (copy_expr a)

type stmt =
  | SLet of bool * string * typ * expr option
  | SAssign of string * expr * expr
  | SExpr of expr
  | SBlock of stmt list
  | SUnsafe of stmt list
  | SIf of expr * stmt list * stmt list
  | SWhile of expr * stmt list
  | SLoop of stmt list
  | SFor of string * expr * expr * stmt list
  | SMatch of expr * arm list
  | SBreak
  | SContinue
  | SReturn of expr option

and pat = PWild | PVariant of string * string * string list

and arm = { apat : pat; abody : stmt list }

type const_def = { cname : string; cty : typ; cvalue : expr }
type struct_def = { sname : string; sfields : (string * typ) list }
type variant = { vname : string; vpayload : typ list }
type enum_def = { ename : string; evariants : variant list }

type extern_fn = {
  ename : string;
  elib : string option;
  eparams : typ list;
  evariadic : bool;
  eret : typ;
}

type fn_def = {
  fname : string;

  fgenerics : string list;
  fparams : (string * typ) list;
  fret : typ;
  fasync : bool;
  fc_c_abi : bool;
  fbody : stmt list;
}

type program = {
  consts : const_def list;
  structs : struct_def list;
  enums : enum_def list;
  externs : extern_fn list;
  fns : fn_def list;
}

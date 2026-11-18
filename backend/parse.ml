open Ast

exception Error of string

let fail fmt = Printf.ksprintf (fun s -> raise (Error s)) fmt

let atom = function
  | Sexp.Atom a -> a
  | Sexp.List _ -> fail "expected an atom in IR, found a list"

let atom_name = function
  | Sexp.Atom a -> a
  | Sexp.List _ -> fail "expected a name in IR, found a list"

let tagged tag = function
  | Sexp.List (Sexp.Atom t :: rest) when t = tag -> rest
  | other ->
      let head =
        match other with
        | Sexp.List (Sexp.Atom t :: _) -> t
        | Sexp.List [] -> "<empty>"
        | Sexp.List (Sexp.List _ :: _) -> "<list>"
        | Sexp.Atom a -> a
      in
      fail "expected '(%s ...)' in IR, found '(%s ...)'" tag head

type env = {
  sizes : (string, int64) Hashtbl.t;
  enums : (string, unit) Hashtbl.t;
}

let rec typ_of (env : env) (s : Sexp.t) : typ =
  match s with
  | Sexp.Atom "i8" -> TI8
  | Sexp.Atom "i16" -> TI16
  | Sexp.Atom "i32" -> TI32
  | Sexp.Atom "i64" -> TI64
  | Sexp.Atom "u8" -> TU8
  | Sexp.Atom "u16" -> TU16
  | Sexp.Atom "u32" -> TU32
  | Sexp.Atom "u64" -> TU64
  | Sexp.Atom "f32" -> TF32
  | Sexp.Atom "f64" -> TF64
  | Sexp.Atom "bool" -> TBool
  | Sexp.Atom "void" -> TVoid
  | Sexp.List [ Sexp.Atom "ptr"; inner ] -> TPtr (typ_of env inner)
  | Sexp.List [ Sexp.Atom "ref"; inner ] -> TRef (typ_of env inner, false)
  | Sexp.List [ Sexp.Atom "refmut"; inner ] -> TRef (typ_of env inner, true)
  | Sexp.List [ Sexp.Atom "box"; inner ] -> TBox (typ_of env inner)
  | Sexp.List [ Sexp.Atom "array"; inner; Sexp.Atom n ] ->
      let elem = typ_of env inner in
      let count =
        match int_of_string_opt n with
        | Some k -> Int64.of_int k
        | None -> (
            match Hashtbl.find_opt env.sizes n with
            | Some v -> v
            | None -> fail "array size '%s' is not a known integer const" n)
      in
      if count <= 0L then fail "array size must be positive, got %s" n;
      if count > Int64.of_int 0x100000 then fail "array size %s is absurd" n;
      TArray (elem, Int64.to_int count)
  | Sexp.List [ Sexp.Atom "named"; Sexp.Atom n ] ->
      if Hashtbl.mem env.enums n then TEnum n else TStruct n
  | Sexp.Atom "infer" | Sexp.List [ Sexp.Atom "infer" ] -> TInfer
  | Sexp.List (Sexp.Atom "tup" :: items) ->
      if List.length items < 2 then fail "a tuple type needs at least two elements";
      TTuple (List.map (typ_of env) items)
  | Sexp.List [ Sexp.Atom "fnty"; Sexp.List ps; ret ] ->
      TFn (List.map (typ_of env) ps, typ_of env ret)
  | Sexp.List [ Sexp.Atom "task"; inner ] -> TTask (typ_of env inner)
  | Sexp.List [ Sexp.Atom "var"; Sexp.Atom v ] -> TVar v
  | Sexp.Atom a -> fail "bad scalar type '%s' in IR" a
  | _ -> fail "bad type in IR"

let rec expr_of (env : env) (s : Sexp.t) : expr =
  let mk node = { node; ty = TVoid } in
  match s with
  | Sexp.List [ Sexp.Atom "int"; a ] -> mk (EInt (Int64.of_string (atom a)))
  | Sexp.List [ Sexp.Atom "float"; a ] -> mk (EFloat (float_of_string (atom a)))
  | Sexp.List [ Sexp.Atom "str"; a ] -> mk (EStr (atom a))
  | Sexp.List [ Sexp.Atom "bool"; a ] -> mk (EBool (atom a = "true"))
  | Sexp.List [ Sexp.Atom "null" ] -> mk ENull
  | Sexp.List [ Sexp.Atom "var"; a ] -> mk (EVar (atom a))
  | Sexp.List (Sexp.Atom "bin" :: rest) -> (
      match rest with
      | [ Sexp.Atom op; x; y ] -> mk (EBin (op, expr_of env x, expr_of env y))
      | _ -> fail "malformed (bin ...) in IR")
  | Sexp.List (Sexp.Atom "un" :: rest) -> (
      match rest with
      | [ Sexp.Atom op; x ] -> mk (EUn (op, expr_of env x))
      | _ -> fail "malformed (un ...) in IR")
  | Sexp.List (Sexp.Atom "call" :: Sexp.Atom n :: args) ->
      mk (ECall (n, List.map (expr_of env) args))
  | Sexp.List (Sexp.Atom "index" :: rest) -> (
      match rest with
      | [ x; y ] -> mk (EIndex (expr_of env x, expr_of env y))
      | _ -> fail "malformed (index ...) in IR")
  | Sexp.List (Sexp.Atom "field" :: rest) -> (
      match rest with
      | [ x; Sexp.Atom f ] -> mk (EField (expr_of env x, f))
      | _ -> fail "malformed (field ...) in IR")
  | Sexp.List [ Sexp.Atom "deref"; x ] -> mk (EDeref (expr_of env x))
  | Sexp.List [ Sexp.Atom "addr"; x ] -> mk (EAddr (expr_of env x))
  | Sexp.List [ Sexp.Atom "addrmut"; x ] -> mk (EAddrMut (expr_of env x))
  | Sexp.List [ Sexp.Atom "boxnew"; x ] -> mk (EBoxNew (expr_of env x))
  | Sexp.List [ Sexp.Atom "cast"; x; t ] -> mk (ECast (expr_of env x, typ_of env t))
  | Sexp.List [ Sexp.Atom "sizeof"; t ] -> mk (ESizeof (typ_of env t))
  | Sexp.List [ Sexp.Atom "zero"; t ] -> mk (EZero (typ_of env t))
  | Sexp.List (Sexp.Atom "structlit" :: Sexp.Atom name :: fields) ->
      let fs =
        List.map
          (fun f ->
            match tagged "field" f with
            | [ Sexp.Atom fname; v ] -> (fname, expr_of env v)
            | _ -> fail "malformed field in struct literal")
          fields
      in
      mk (EStructLit (name, fs))
  | Sexp.List (Sexp.Atom "arraylit" :: items) ->
      mk (EArrayLit (List.map (expr_of env) items))
  | Sexp.List (Sexp.Atom "enumlit" :: Sexp.Atom en :: Sexp.Atom vn :: args) ->
      mk (EEnumLit (en, vn, List.map (expr_of env) args))
  | Sexp.List (Sexp.Atom "tuplelit" :: items) ->
      mk (ETupleLit (List.map (expr_of env) items))
  | Sexp.List [ Sexp.Atom "fnref"; Sexp.Atom n ] -> mk (EFnRef n)
  | Sexp.List (Sexp.Atom "callv" :: f :: args) ->
      mk (ECallV (expr_of env f, List.map (expr_of env) args))
  | Sexp.List [ Sexp.Atom "await"; a ] -> mk (EAwait (expr_of env a))
  | Sexp.List [ Sexp.Atom "poll"; a ] -> mk (EPoll (expr_of env a))
  | other ->
      ignore other;
      fail "unrecognised expression in IR"

let pat_of (s : Sexp.t) : pat =
  match tagged "pat" s with
  | [ Sexp.Atom "wild" ] -> PWild
  | Sexp.Atom en :: Sexp.Atom vn :: binds ->
      PVariant
        (en, vn, List.map (fun b -> match b with Sexp.Atom a -> a | _ -> fail "bad pattern binding") binds)
  | _ -> fail "malformed (pat ...) in IR"

let rec arm_of (env : env) (s : Sexp.t) : arm =
  match tagged "arm" s with
  | [ p; body ] -> { apat = pat_of p; abody = List.map (stmt_of env) (tagged "body" body) }
  | _ -> fail "malformed (arm ...) in IR"

and stmt_of (env : env) (s : Sexp.t) : stmt =
  match s with
  | Sexp.List (Sexp.Atom (("let" | "var") as tag) :: rest) -> (
      match rest with
      | [ Sexp.Atom name; t; init ] -> (
          let ty = typ_of env t in
          match init with
          | Sexp.List [ Sexp.Atom "none" ] -> SLet (tag = "var", name, ty, None)
          | other -> SLet (tag = "var", name, ty, Some (expr_of env other)))
      | [ Sexp.Atom name; t ] -> SLet (tag = "var", name, typ_of env t, None)
      | _ -> fail "malformed binding in IR")
  | Sexp.List (Sexp.Atom "assign" :: rest) -> (
      match rest with
      | [ Sexp.Atom op; lhs; rhs ] ->
          SAssign (op, expr_of env lhs, expr_of env rhs)
      | _ -> fail "malformed (assign ...) in IR")
  | Sexp.List [ Sexp.Atom "expr"; e ] -> SExpr (expr_of env e)
  | Sexp.List [ Sexp.Atom "break" ] -> SBreak
  | Sexp.List [ Sexp.Atom "continue" ] -> SContinue
  | Sexp.List [ Sexp.Atom "return" ] -> SReturn None
  | Sexp.List [ Sexp.Atom "return"; e ] -> SReturn (Some (expr_of env e))
  | Sexp.List (Sexp.Atom "block" :: body) -> SBlock (List.map (stmt_of env) body)
  | Sexp.List (Sexp.Atom "unsafe" :: body) -> SUnsafe (List.map (stmt_of env) body)
  | Sexp.List (Sexp.Atom "if" :: rest) -> (
      match rest with
      | cond :: thenpart :: elsepart ->
          let th = List.map (stmt_of env) (tagged "then" thenpart) in
          let el =
            match elsepart with
            | [ x ] -> List.map (stmt_of env) (tagged "else" x)
            | [] -> []
            | _ -> fail "malformed (if ...) in IR"
          in
          SIf (expr_of env cond, th, el)
      | _ -> fail "malformed (if ...) in IR")
  | Sexp.List (Sexp.Atom "while" :: cond :: body) ->
      SWhile (expr_of env cond, List.map (stmt_of env) body)
  | Sexp.List (Sexp.Atom "loop" :: body) -> SLoop (List.map (stmt_of env) body)
  | Sexp.List (Sexp.Atom "for" :: Sexp.Atom v :: start :: stop :: body) ->
      SFor (v, expr_of env start, expr_of env stop, List.map (stmt_of env) body)
  | Sexp.List (Sexp.Atom "match" :: scrut :: arms) ->
      SMatch (expr_of env scrut, List.map (arm_of env) arms)
  | other ->
      ignore other;
      fail "unrecognised statement in IR"

let program_of (s : Sexp.t) : program =
  let items = tagged "program" s in
  let env =
    { sizes = Hashtbl.create 16; enums = Hashtbl.create 16 }
  in

  List.iter
    (fun item ->
      match item with
      | Sexp.List (Sexp.Atom "enum" :: Sexp.Atom name :: _) -> Hashtbl.replace env.enums name ()
      | _ -> ())
    items;

  let consts =
    List.filter_map
      (fun item ->
        match item with
        | Sexp.List (Sexp.Atom "const" :: Sexp.Atom name :: t :: [ v ]) ->
            let cty = typ_of env t in
            let cvalue = expr_of env v in
            (match Fold.eval_int cvalue with
            | Some n -> Hashtbl.replace env.sizes name n
            | None -> ());
            Some { cname = name; cty; cvalue }
        | Sexp.List (Sexp.Atom "const" :: _) -> fail "malformed const in IR"
        | _ -> None)
      items
  in

  let structs = ref [] and enums = ref [] and externs = ref [] and fns = ref [] in
  List.iter
    (fun item ->
      match item with
      | Sexp.List (Sexp.Atom "const" :: _) -> ()
      | Sexp.List (Sexp.Atom "struct" :: Sexp.Atom name :: fields) ->
          let fs =
            List.map
              (fun f ->
                match tagged "field" f with
                | [ Sexp.Atom fn; t ] -> (fn, typ_of env t)
                | _ -> fail "malformed struct field in IR")
              fields
          in
          structs := { sname = name; sfields = fs } :: !structs
      | Sexp.List (Sexp.Atom "enum" :: Sexp.Atom name :: variants) ->
          let vs =
            List.map
              (fun v ->
                match tagged "variant" v with
                | Sexp.Atom vn :: [] -> { vname = vn; vpayload = [] }
                | Sexp.Atom vn :: [ payload ] -> (
                    match tagged "payload" payload with
                    | [] -> fail "empty payload in enum '%s'" name
                    | ts -> { vname = vn; vpayload = List.map (typ_of env) ts })
                | _ -> fail "malformed variant in IR")
              variants
          in
          enums := { ename = name; evariants = vs } :: !enums
      | Sexp.List (Sexp.Atom "extern" :: Sexp.Atom name :: parts) ->
          let params = ref [] and variadic = ref false and ret = ref TVoid in
          let lib = ref None in
          List.iter
            (fun p ->
              match p with
              | Sexp.List [ Sexp.Atom "param"; t ] -> params := typ_of env t :: !params
              | Sexp.List [ Sexp.Atom "variadic" ] -> variadic := true
              | Sexp.List [ Sexp.Atom "ret"; t ] -> ret := typ_of env t
              | Sexp.List [ Sexp.Atom "lib"; Sexp.Atom l ] ->

                  let l =
                    if String.length l >= 2 && l.[0] = '"' && l.[String.length l - 1] = '"'
                    then String.sub l 1 (String.length l - 2)
                    else l
                  in
                  lib := Some l
              | _ -> fail "malformed extern in IR")
            parts;
          externs :=
            {
              ename = name;
              elib = !lib;
              eparams = List.rev !params;
              evariadic = !variadic;
              eret = !ret;
            }
            :: !externs
      | Sexp.List (Sexp.Atom "fn" :: Sexp.Atom name :: parts) ->
          let params = ref [] and ret = ref TVoid and body = ref [] and asy = ref false in
          let c_abi = ref false in
          let generics = ref [] in
          List.iter
            (fun p ->
              match p with
              | Sexp.List [ Sexp.Atom "param"; Sexp.Atom n; t ] ->
                  params := (n, typ_of env t) :: !params
              | Sexp.List [ Sexp.Atom "ret"; t ] -> ret := typ_of env t
              | Sexp.List [ Sexp.Atom "async" ] -> asy := true
              | Sexp.List [ Sexp.Atom "c-abi" ] -> c_abi := true
              | Sexp.List (Sexp.Atom "generic" :: Sexp.Atom g :: rest) ->

                  generics := !generics @ (g :: List.map atom rest)
              | Sexp.List (Sexp.Atom "body" :: stmts) ->
                  body := List.map (stmt_of env) stmts
              | _ -> fail "malformed fn in IR")
            parts;
          fns :=
            {
              fname = name;
              fgenerics = !generics;
              fparams = List.rev !params;
              fret = !ret;
              fasync = !asy;
              fc_c_abi = !c_abi;
              fbody = !body;
            }
            :: !fns
      | _ -> fail "unexpected top-level item in IR")
    items;

  {
    consts;
    structs = List.rev !structs;
    enums = List.rev !enums;
    externs = List.rev !externs;
    fns = List.rev !fns;
  }

let parse_string (text : string) : program = program_of (Sexp.parse text)

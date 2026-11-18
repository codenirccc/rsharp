open Ast

type fn_sig = { sig_params : typ list; sig_ret : typ; sig_variadic : bool }

type ctx = {
  structs : (string, (string * typ) list) Hashtbl.t;
  enums : (string, variant list) Hashtbl.t;
  funcs : (string, fn_sig) Hashtbl.t;
  consts : (string, expr) Hashtbl.t;

  generics : (string, string list) Hashtbl.t;
  gspec : (string, typ list * typ) Hashtbl.t;
  mutable scopes : (string * typ * bool) list list;
  mutable ret : typ;
  mutable where : string;
  mutable loops : int;
  mutable unsafe_depth : int;
  mutable errors : string list;

  mutable lits : (expr * int64 * string) list;
}

let note ctx fmt =
  Printf.ksprintf (fun s -> ctx.errors <- (ctx.where ^ ": " ^ s) :: ctx.errors) fmt

let push ctx = ctx.scopes <- [] :: ctx.scopes

let pop ctx =
  match ctx.scopes with
  | _ :: tl -> ctx.scopes <- tl
  | [] -> ctx.scopes <- []

let declare ctx name ty mutable_ =
  match ctx.scopes with
  | scope :: rest ->
      let kept = List.filter (fun (n, _, _) -> n <> name) scope in
      ctx.scopes <- ((name, ty, mutable_) :: kept) :: rest
  | [] -> ctx.scopes <- [ [ (name, ty, mutable_) ] ]

let lookup ctx name =
  let rec go = function
    | [] -> None
    | scope :: rest -> (
        match List.find_opt (fun (n, _, _) -> n = name) scope with
        | Some (_, t, m) -> Some (t, m)
        | None -> go rest)
  in
  go ctx.scopes

let broken t = t = TErr
let is_pointer = function TPtr _ -> true | _ -> false

let rec peel_all = function TRef (t, _) -> peel_all t | TBox t -> peel_all t | t -> t

let needs_unsafe ctx what =
  if ctx.unsafe_depth = 0 then
    note ctx "%s is only allowed inside an 'unsafe' block" what

let rec literal_int (e : expr) =
  match e.node with
  | EInt k -> Some k
  | EUn ("-", a) -> Option.map Int64.neg (literal_int a)
  | _ -> None

let is_int_lit (e : expr) =
  match e.node with EInt _ | EUn ("-", { node = EInt _; _ }) -> true | _ -> false

let int_range = function
  | TI8 -> Some (-128L, 127L)
  | TI16 -> Some (-32768L, 32767L)
  | TI32 -> Some (-2147483648L, 2147483647L)
  | TI64 -> None
  | TU8 -> Some (-128L, 255L)
  | TU16 -> Some (-32768L, 65535L)
  | TU32 -> Some (-2147483648L, 4294967295L)
  | TU64 -> None
  | _ -> None

let rec check_type ctx t =
  match t with
  | TStruct s ->
      if not (Hashtbl.mem ctx.structs s) then note ctx "unknown struct type '%s'" s
  | TEnum s ->
      if not (Hashtbl.mem ctx.enums s) then note ctx "unknown enum type '%s'" s
  | TTuple ts ->
      if List.length ts < 2 then note ctx "a tuple type needs at least two elements";
      List.iter
        (fun t -> if t = TVoid then note ctx "a tuple cannot hold void") ts;
      List.iter (check_type ctx) ts
  | TFn (ps, r) ->
      List.iter (fun t -> if t = TVoid then note ctx "a function pointer cannot take void") ps;
      check_type ctx r
  | TFnC (ps, r) ->
      List.iter (fun t -> if t = TVoid then note ctx "a function pointer cannot take void") ps;
      check_type ctx r
  | TTask t ->
      if t = TVoid then note ctx "a Task needs a value type, not void";
      check_type ctx t
  | TInfer -> note ctx "this type has to be written out here"
  | TPtr (TArray _) -> note ctx "pointers to arrays are not supported"
  | TPtr inner -> check_type ctx inner
  | TRef (TVoid, _) -> note ctx "a reference needs a real type, not void"
  | TRef (inner, _) -> check_type ctx inner
  | TBox TVoid -> note ctx "Box needs a real type, not void"
  | TBox inner -> check_type ctx inner
  | TArray (inner, n) ->
      if n <= 0 then note ctx "array size must be positive";
      (match inner with
      | TVoid -> note ctx "an array cannot hold void"
      | TArray _ -> note ctx "nested array types are not supported"
      | TPtr (TArray _) -> ()
      | _ -> ());
      check_type ctx inner
  | _ -> ()

let assignable dst src =
  dst = TErr || src = TErr
  || dst = src
  || match (dst, src) with TPtr _, TPtr TVoid -> true | _ -> false

let default_numeric expect fallback =
  match expect with Some t when is_numeric t -> t | _ -> fallback


let rec mangle_typ = function
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
  | TPtr t -> "ptr_" ^ mangle_typ t
  | TRef (t, true) -> "refmut_" ^ mangle_typ t
  | TRef (t, false) -> "ref_" ^ mangle_typ t
  | TBox t -> "box_" ^ mangle_typ t
  | TArray (t, n) -> Printf.sprintf "arr_%s_%d" (mangle_typ t) n
  | TStruct s -> s
  | TEnum s -> s
  | TTuple ts -> "tup_" ^ String.concat "_" (List.map mangle_typ ts)
  | TFn (ps, r) -> "fn_" ^ String.concat "_" (List.map mangle_typ ps) ^ "_" ^ mangle_typ r
  | TFnC (ps, r) -> "fnc_" ^ String.concat "_" (List.map mangle_typ ps) ^ "_" ^ mangle_typ r
  | TTask t -> "task_" ^ mangle_typ t
  | TVar v -> "ty_" ^ v
  | TInfer -> "infer"
  | TErr -> "err"

let mangle name subst =
  name ^ "$" ^ String.concat "$" (List.map (fun (_, t) -> mangle_typ t) subst)

let rec has_var = function
  | TVar _ -> true
  | TPtr t | TBox t | TArray (t, _) | TTask t -> has_var t
  | TRef (t, _) -> has_var t
  | TTuple ts -> List.exists has_var ts
  | TFn (ps, r) -> List.exists has_var ps || has_var r
  | TFnC (ps, r) -> List.exists has_var ps || has_var r
  | _ -> false

let pending : (string, string * (string * typ) list) Hashtbl.t = Hashtbl.create 32
let pending_order : (string * string * (string * typ) list) list ref = ref []

let reset_pending () =
  Hashtbl.reset pending;
  pending_order := []

let request mangled gname subst =
  if not (Hashtbl.mem pending mangled) then begin
    Hashtbl.replace pending mangled (gname, subst);
    pending_order := (mangled, gname, subst) :: !pending_order
  end

let take_pending () =
  let l = List.rev !pending_order in
  reset_pending ();
  l

let rec unify ctx ~who (bind : (string, typ) Hashtbl.t) (formal : typ) (actual : typ) =
  let bad () =
    note ctx "argument of '%s': expected %s, got %s" who (to_string formal)
      (to_string actual)
  in
  match formal with
  | TVar v -> (
      match Hashtbl.find_opt bind v with
      | None -> Hashtbl.replace bind v actual
      | Some t when t = actual -> ()
      | Some t ->
          note ctx "'%s' cannot be both %s and %s in one call to '%s'" v (to_string t)
            (to_string actual) who)
  | TPtr f -> ( match actual with TPtr a -> unify ctx ~who bind f a | _ -> bad ())
  | TRef (f, m) -> (
      match actual with TRef (a, n) when n = m -> unify ctx ~who bind f a | _ -> bad ())
  | TBox f -> ( match actual with TBox a -> unify ctx ~who bind f a | _ -> bad ())
  | TArray (f, n) -> (
      match actual with TArray (a, k) when k = n -> unify ctx ~who bind f a | _ -> bad ())
  | TTuple fs -> (
      match actual with
      | TTuple as_ when List.length fs = List.length as_ ->
          List.iter2 (unify ctx ~who bind) fs as_
      | _ -> bad ())
  | TFn (fp, fr) -> (
      match actual with
      | TFn (ap, ar) when List.length fp = List.length ap ->
          List.iter2 (unify ctx ~who bind) fp ap;
          unify ctx ~who bind fr ar
      | _ -> bad ())
  | TFnC (fp, fr) -> (
      match actual with
      | TFnC (ap, ar) when List.length fp = List.length ap ->
          List.iter2 (unify ctx ~who bind) fp ap;
          unify ctx ~who bind fr ar
      | _ -> bad ())
  | TTask f -> ( match actual with TTask a -> unify ctx ~who bind f a | _ -> bad ())
  | _ -> if not (assignable formal actual) then bad ()

let share_of ty =
  match ty with
  | TRef (_, true) -> true
  | TRef (_, false) -> false
  | _ -> true

let rec lvalue ctx (e : expr) =
  match e.node with
  | EVar n -> (
      match lookup ctx n with
      | Some (_, true) -> ()
      | Some (_, false) -> note ctx "'%s' is immutable; declare it with 'var' to assign to it" n
      | None -> ())
  | EDeref p -> (
      match p.ty with
      | TRef (_, false) -> note ctx "cannot assign through a shared reference; it is '&', not '&mut'"
      | TRef (_, true) -> ()
      | TPtr _ -> needs_unsafe ctx "writing through a raw pointer"
      | TErr -> ()
      | other -> note ctx "cannot dereference %s" (to_string other))
  | EIndex _ -> ()
  | EField (base, _) -> (
      match base.ty with
      | TPtr (TStruct _) -> needs_unsafe ctx "writing through a raw pointer"
      | TRef (_, false) ->
          note ctx "cannot assign through a shared reference; it is '&', not '&mut'"
      | TRef (TStruct _, true) -> ()
      | TBox (TStruct _) -> ()
      | _ -> lvalue ctx base)
  | _ -> note ctx "this expression is not assignable"

let rec addressable ctx (e : expr) =
  match e.node with
  | EVar n -> if lookup ctx n = None then note ctx "unknown variable '%s'" n
  | EDeref _ -> ()
  | EIndex _ -> ()
  | EField (base, _) -> (
      match base.ty with TPtr (TStruct _) -> () | _ -> addressable ctx base)
  | _ -> note ctx "cannot take the address of this expression"

let needs_mutable ctx (e : expr) =
  let rec go (e : expr) =
    match e.node with
    | EVar n -> (
        match lookup ctx n with
        | Some (_, false) ->
            note ctx "'%s' is immutable; declare it with 'var' to take '&mut' of it" n
        | _ -> ())
    | EField (base, _) -> (
        match base.ty with
        | TPtr _ -> ()
        | TRef (_, false) -> note ctx "cannot take '&mut' through a shared reference"
        | TBox _ -> ()
        | _ -> go base)
    | EDeref p -> (
        match p.ty with
        | TRef (_, false) -> note ctx "cannot take '&mut' through a shared reference"
        | _ -> ())
    | EIndex (base, _) -> ( match peel_ref base.ty with TPtr _ -> () | _ -> go base)
    | _ -> ()
  in
  go e

let infer_field ctx (sname : string) (field : string) : typ option =
  match Hashtbl.find_opt ctx.structs sname with
  | None ->
      note ctx "unknown struct type '%s'" sname;
      None
  | Some fields -> (
      match List.assoc_opt field fields with
      | Some t -> Some t
      | None ->
          note ctx "struct '%s' has no field '%s'" sname field;
          None)

let rec infer ctx ?expect (e : expr) : expr =
  let set t =
    e.ty <- t;
    e
  in
  match e.node with
  | EInt k ->
      ctx.lits <- (e, k, ctx.where) :: ctx.lits;
      set (default_numeric expect TI32)
  | EFloat _ -> set (match expect with Some t when is_float t -> t | _ -> TF64)
  | EBool _ -> set TBool
  | EStr _ -> set (TPtr TU8)
  | ENull -> set (match expect with Some (TPtr _ as t) -> t | _ -> TPtr TVoid)
  | EVar n -> (
      match lookup ctx n with
      | Some (t, _) -> set t
      | None -> (
          match Hashtbl.find_opt ctx.consts n with
          | Some c ->
              let c = copy_expr c in
              e.node <- c.node;
              set c.ty
          | None -> (
              if Hashtbl.mem ctx.generics n then begin
                note ctx
                  "a generic function cannot be used as a value; call '%s' with concrete arguments"
                  n;
                set TErr
              end
              else
                match Hashtbl.find_opt ctx.funcs n with
                | Some sg -> set (TFn (sg.sig_params, sg.sig_ret))
                | None ->
                    note ctx "unknown variable '%s'" n;
                    set TErr)))
  | ESizeof t ->
      check_type ctx t;
      (if t = TVoid then note ctx "sizeof(void) is not a value");
      set TU64
  | EZero t ->
      check_type ctx t;
      if t = TVoid then note ctx "zero(void) is not a value";
      set t
  | ECast (a, t) -> (
      check_type ctx t;

      let a = if is_int_lit a && is_int t then infer ctx ~expect:t a else infer ctx a in
      if broken a.ty then set TErr
      else begin
        if t = TVoid then note ctx "cannot cast to void";
        if is_array t || is_array a.ty then
          note ctx "cannot cast %s to %s" (to_string a.ty) (to_string t)
        else if (match (a.ty, t) with TStruct s1, TStruct s2 -> s1 <> s2 | TStruct _, _ | _, TStruct _ -> true | _ -> false) then
          note ctx "cannot cast between struct types (%s as %s)" (to_string a.ty)
            (to_string t);
        if is_pointer t && is_ref a.ty then
          needs_unsafe ctx "turning a reference into a raw pointer";
        if is_ref t then begin
          if is_pointer a.ty then
            note ctx "a raw pointer cannot become a reference; nothing proves it is valid"
          else note ctx "references do not cast; they are already the value you want"
        end;
        if is_ref a.ty && not (is_pointer t) then
          note ctx "a reference only casts to a raw pointer ('as ptr<T>'), inside unsafe";
        if broken a.ty then set TErr else set t
      end)
  | EUn (op, a) -> (
      let a = infer ctx ?expect a in
      if broken a.ty then set TErr
      else
        match op with
        | "-" ->
            if not (is_numeric a.ty) then begin
              note ctx "unary '-' needs a numeric operand, got %s" (to_string a.ty);
              set TErr
            end
            else begin

              (match a.node with
              | EInt k ->
                  ctx.lits <- List.filter (fun (x, _, _) -> x != a) ctx.lits;
                  ctx.lits <- (e, Int64.neg k, ctx.where) :: ctx.lits
              | _ -> ());
              set a.ty
            end
        | "~" ->
            if not (is_int a.ty) then begin
              note ctx "unary '~' needs an integer operand, got %s" (to_string a.ty);
              set TErr
            end
            else set a.ty
        | "!" ->
            if a.ty <> TBool then begin
              note ctx "'!' needs a bool operand, got %s" (to_string a.ty);
              set TErr
            end
            else set TBool
        | other ->
            note ctx "unknown unary operator '%s'" other;
            set TErr)
  | EAddr a -> (
      let a = infer ctx a in
      addressable ctx a;
      match a.ty with TErr -> set TErr | t -> set (TRef (t, false)))
  | EAddrMut a -> (
      let a = infer ctx a in
      addressable ctx a;
      needs_mutable ctx a;
      match a.ty with TErr -> set TErr | t -> set (TRef (t, true)))
  | EBoxNew a -> (
      let inner_expect = match expect with Some (TBox t) -> Some t | _ -> None in
      let a = infer ctx ?expect:inner_expect a in
      if broken a.ty then set TErr
      else if a.ty = TVoid then begin
        note ctx "box(...) needs a value";
        set TErr
      end
      else set (TBox a.ty))
  | EDeref p -> (
      let p = infer ctx p in
      match p.ty with
      | TErr -> set TErr
      | TPtr t ->
          needs_unsafe ctx "reading through a raw pointer";
          set t
      | TRef (t, _) -> set t
      | TBox t -> set t
      | other ->
          note ctx "cannot dereference %s; expected a pointer, reference or Box" (to_string other);
          set TErr)
  | EIndex (base, idx) -> (
      let base = infer ctx base in
      let idx = infer ctx idx in
      if not (is_int idx.ty) && not (broken idx.ty) then
        note ctx "index must be an integer, got %s" (to_string idx.ty);
      match peel_all base.ty with
      | TErr -> set TErr
      | TPtr t ->
          needs_unsafe ctx "indexing a raw pointer";
          set t
      | TArray (t, n) -> (
          match literal_int idx with
          | Some k when k < 0L || k >= Int64.of_int n ->
              note ctx "index %Ld is out of range for [%s; %d]" k (to_string t) n;
              set TErr
          | _ -> set t)
      | other ->
          note ctx "cannot index %s; expected a pointer, reference or an array" (to_string other);
          set TErr)
  | EField (base, field) -> (
      let base = infer ctx base in
      match peel_all base.ty with
      | TErr -> set TErr
      | TTuple ts -> (
          match int_of_string_opt field with
          | Some i when i >= 0 && i < List.length ts -> set (List.nth ts i)
          | _ ->
              note ctx "a tuple of %d element(s) has no element '%s'" (List.length ts) field;
              set TErr)
      | TStruct s -> (
          match infer_field ctx s field with Some t -> set t | None -> set TErr)
      | TPtr (TStruct s) -> (
          match infer_field ctx s field with Some t -> set t | None -> set TErr)
      | other ->
          note ctx "field access on non-struct type %s" (to_string other);
          set TErr)
  | EStructLit (name, fields) -> (
      match Hashtbl.find_opt ctx.structs name with
      | None ->
          note ctx "unknown struct '%s'" name;
          List.iter (fun (_, v) -> ignore (infer ctx v)) fields;
          set TErr
      | Some sfields ->
          List.iter
            (fun (f, v) ->
              match List.assoc_opt f sfields with
              | Some ft ->
                  let v = infer ctx ~expect:ft v in
                  if not (assignable ft v.ty) then
                    note ctx "%s.%s: expected %s, got %s" name f (to_string ft)
                      (to_string v.ty)
              | None ->
                  note ctx "struct '%s' has no field '%s'" name f;
                  ignore (infer ctx v))
            fields;
          List.iter
            (fun (f, _) ->
              if not (List.mem_assoc f fields) then
                note ctx "%s { ... } is missing field '%s'" name f)
            sfields;
          set (TStruct name))
  | EArrayLit items -> (
      match expect with
      | Some (TArray (et, n)) ->
          if List.length items > n then
            note ctx "array literal has %d element(s) but the type holds %d"
              (List.length items) n;
          List.iter
            (fun it ->
              let it = infer ctx ~expect:et it in
              if not (assignable et it.ty) then
                note ctx "array element: expected %s, got %s" (to_string et)
                  (to_string it.ty))
            items;
          set (TArray (et, n))
      | Some t ->
          note ctx "an array literal cannot initialise %s" (to_string t);
          List.iter (fun it -> ignore (infer ctx it)) items;
          set TErr
      | None ->
          note ctx "an array literal needs an array type to land in";
          List.iter (fun it -> ignore (infer ctx it)) items;
          set TErr)
  | EEnumLit (en, vn, args) -> (
      let args_checked () = List.iter (fun a -> ignore (infer ctx a)) args in
      match Hashtbl.find_opt ctx.enums en with
      | None ->
          note ctx "unknown enum '%s'" en;
          args_checked ();
          set TErr
      | Some variants -> (
          match List.find_opt (fun v -> v.vname = vn) variants with
          | None ->
              note ctx "enum '%s' has no variant '%s'" en vn;
              args_checked ();
              set TErr
          | Some v ->
              let want = List.length v.vpayload in
              let got = List.length args in
              if want <> got then
                note ctx "'%s::%s' carries %d value(s), given %d" en vn want got;
              List.iteri
                (fun i a ->
                  let expect = if i < want then Some (List.nth v.vpayload i) else None in
                  let a = infer ctx ?expect a in
                  if is_heap a.ty then note ctx "a Box cannot be a variant payload"
                  else
                    match expect with
                    | Some t when not (assignable t a.ty) ->
                        note ctx "'%s::%s' field %d: expected %s, got %s" en vn (i + 1)
                          (to_string t) (to_string a.ty)
                    | _ -> ())
                args;
              if want <> got then set TErr else set (TEnum en)))
  | ETupleLit items -> (
      match expect with
      | Some (TTuple ts) when List.length ts = List.length items ->
          List.iter2
            (fun t it ->
              let it = infer ctx ~expect:t it in
              if not (assignable t it.ty) then
                note ctx "tuple element: expected %s, got %s" (to_string t) (to_string it.ty))
            ts items;
          set (TTuple ts)
      | Some (TTuple ts) ->
          note ctx "this tuple type holds %d element(s); the literal has %d"
            (List.length ts) (List.length items);
          List.iter (fun it -> ignore (infer ctx it)) items;
          set TErr
      | Some t ->
          note ctx "a tuple literal cannot initialise %s" (to_string t);
          List.iter (fun it -> ignore (infer ctx it)) items;
          set TErr
      | None ->
          let tys = List.map (fun it -> (infer ctx it).ty) items in
          if List.exists broken tys then set TErr else set (TTuple tys))
  | EFnRef n -> (
      match Hashtbl.find_opt ctx.funcs n with
      | Some sg -> set (TFn (sg.sig_params, sg.sig_ret))
      | None ->
          note ctx "unknown function '%s'" n;
          set TErr)
  | ECallV (f, args) -> (
      let f = infer ctx f in
      match f.ty with
      | TErr ->
          List.iter (fun a -> ignore (infer ctx a)) args;
          set TErr
      | TFn (ps, r) | TFnC (ps, r) ->
          let np = List.length ps in
          if np <> List.length args then
            note ctx "this function pointer takes %d argument(s), got %d" np
              (List.length args);
          List.iteri
            (fun i a ->
              let want = if i < np then Some (List.nth ps i) else None in
              let a = infer ctx ?expect:want a in
              match want with
              | Some t when is_heap t ->
                  note ctx "argument %d is %s; a Box cannot be passed by value" (i + 1)
                    (to_string t)
              | Some t when not (assignable t a.ty) ->
                  note ctx "argument %d: expected %s, got %s" (i + 1) (to_string t)
                    (to_string a.ty)
              | _ -> ())
            args;
          set r
      | other ->
          note ctx "cannot call %s; a call needs a function pointer" (to_string other);
          List.iter (fun a -> ignore (infer ctx a)) args;
          set TErr)
  | EAwait a -> (
      let a = infer ctx a in
      match a.ty with
      | TErr -> set TErr
      | TTask t -> set t
      | other ->
          note ctx "'await' needs a Task, got %s" (to_string other);
          set TErr)
  | EPoll a -> (
      let a = infer ctx a in
      match a.ty with
      | TErr -> set TErr
      | TTask _ -> set TI64
      | other ->
          note ctx "'poll' needs a Task, got %s" (to_string other);
          set TErr)
  | EBin (op, a, b) -> (
      let result =
        match op with
        | "&&" | "||" -> (
            let a = infer ctx ~expect:TBool a in
            if a.ty <> TBool && not (broken a.ty) then
              note ctx "'%s' needs bool operands, left side is %s" op (to_string a.ty);
            let b = infer ctx ~expect:TBool b in
            if b.ty <> TBool && not (broken b.ty) then
              note ctx "'%s' needs bool operands, right side is %s" op (to_string b.ty);
            if broken a.ty || broken b.ty then TErr else TBool)
        | "==" | "!=" | "<" | "<=" | ">" | ">=" -> (
            let a = infer ctx a in
            let b = infer ctx ~expect:a.ty b in
            if is_int_lit a && is_int b.ty then a.ty <- b.ty;
            if broken a.ty || broken b.ty then TErr
            else begin
              if not (is_pointer a.ty) && not (is_ref a.ty) && not (is_numeric a.ty) then
                note ctx "cannot compare %s with '%s'" (to_string a.ty) op;
              if not (assignable a.ty b.ty) then
                note ctx "comparison between %s and %s" (to_string a.ty) (to_string b.ty);
              TBool
            end)
        | "+" | "-" | "*" | "/" | "%" -> (
            let a = infer ctx ?expect a in
            if broken a.ty then TErr
            else
              match peel_ref a.ty with
              | TPtr _ when op = "+" || op = "-" -> (
                  needs_unsafe ctx "pointer arithmetic";
                  let b = infer ctx ~expect:TU64 b in
                  if broken b.ty then TErr
                  else if not (is_int b.ty) then begin
                    note ctx "pointer arithmetic needs an integer offset, got %s"
                      (to_string b.ty);
                    TErr
                  end
                  else a.ty)
              | at when is_numeric at -> (
                  if op = "%" && not (is_int at) then
                    note ctx "'%%' needs integer operands, got %s" (to_string at);
                  let b = infer ctx ~expect:at b in
                  let at = if is_int_lit a && is_int b.ty then b.ty else at in
                  if at <> a.ty then a.ty <- at;
                  if broken b.ty then TErr
                  else if not (is_numeric b.ty) then begin
                    note ctx "arithmetic on non-numeric %s" (to_string b.ty);
                    TErr
                  end
                  else if not (assignable at b.ty) then begin
                    note ctx "type mismatch in '%s': %s and %s" op (to_string at)
                      (to_string b.ty);
                    TErr
                  end
                  else at)
              | TPtr _ -> (
                  note ctx "'%s' does not apply to a raw pointer" op;
                  TErr)
              | other ->
                  note ctx "arithmetic on non-numeric type %s" (to_string other);
                  TErr)
        | "<<" | ">>" | "&" | "|" | "^" -> (
            let a = infer ctx ?expect a in
            if broken a.ty then begin
              ignore (infer ctx b);
              TErr
            end
            else if not (is_int a.ty) then begin
              ignore (infer ctx b);
              note ctx "'%s' needs integer operands, got %s" op (to_string a.ty);
              TErr
            end
            else begin
              let b = infer ctx ~expect:a.ty b in
              if is_int_lit a && is_int b.ty then a.ty <- b.ty;
              if broken b.ty then TErr
              else begin
                if not (assignable a.ty b.ty) then
                  note ctx "type mismatch in '%s': %s and %s" op (to_string a.ty)
                    (to_string b.ty);
                a.ty
              end
            end)
        | other ->
            note ctx "unknown operator '%s'" other;
            TErr
      in
      set result)
  | ECall (name, args) -> (
      match Hashtbl.find_opt ctx.generics name with
      | Some tparams -> instantiate ctx e name tparams args
      | None -> (
          match lookup ctx name with
      | Some (TFn _, _) | Some (TFnC _, _) ->
          e.node <- ECallV ({ node = EVar name; ty = TVoid }, args);
          infer ctx e
      | Some (t, _) ->
          note ctx "'%s' is %s, not a function" name (to_string t);
          List.iter (fun a -> ignore (infer ctx a)) args;
          set TErr
      | None -> (
      match Hashtbl.find_opt ctx.funcs name with
      | None ->
          note ctx "unknown function '%s'" name;
          List.iter (fun a -> ignore (infer ctx a)) args;
          set TErr
      | Some sg ->
          let np = List.length sg.sig_params in
          let na = List.length args in
          if sg.sig_variadic then begin
            if na < np then
              note ctx "'%s' takes at least %d argument(s), got %d" name np na
          end
          else if na <> np then note ctx "'%s' takes %d argument(s), got %d" name np na;
          List.iteri
            (fun i arg ->
              let want = if i < np then Some (List.nth sg.sig_params i) else None in
              let arg = infer ctx ?expect:want arg in
              match want with
              | Some t when is_heap t ->
                  note ctx "argument %d of '%s' is %s; a Box cannot be passed by value" (i + 1)
                    name (to_string t)
              | Some t when not (assignable t arg.ty) ->
                  note ctx "argument %d of '%s': expected %s, got %s" (i + 1) name
                    (to_string t) (to_string arg.ty)
              | _ -> ())
            args;
          set sg.sig_ret)))

and instantiate ctx (e : expr) name (tparams : string list) (args : expr list) =
  let params, ret = Hashtbl.find ctx.gspec name in
  let np = List.length params and na = List.length args in
  if na <> np then note ctx "'%s' takes %d argument(s), got %d" name np na;
  let bind = Hashtbl.create 4 in
  let args =
    List.mapi
      (fun i a ->
        let formal = if i < np then Some (List.nth params i) else None in

        let expect = match formal with Some f when not (has_var f) -> Some f | _ -> None in
        let a = infer ctx ?expect a in
        (match formal with Some f -> unify ctx ~who:name bind f a.ty | None -> ());
        a)
      args
  in
  if List.exists (fun (a : expr) -> broken a.ty) args then begin
    e.ty <- TErr;
    e
  end
  else begin
    let subst =
      List.map
        (fun v -> (v, match Hashtbl.find_opt bind v with Some t -> t | None -> TErr))
        tparams
    in
    List.iter
      (fun (v, t) ->
        if t = TErr then
          note ctx "cannot work out '%s' in a call to '%s'; give the argument a type" v name)
      subst;
    let copy = mangle name subst in
    request copy name subst;
    e.ty <- subst_typ subst ret;
    e.node <- ECall (copy, args);
    e
  end

let check_box_copy ctx name ty allowed =
  if (not allowed) && is_heap ty then
    note ctx "'%s' is %s; a Box owns its memory and cannot be copied or assigned" name
      (to_string ty)

let rec check_stmt ctx (st : stmt) =
  match st with
  | SLet (mutable_, name, TInfer, init) -> (
      match init with
      | None ->
          note ctx "'%s' needs a type; there is nothing here to infer it from" name;
          declare ctx name TErr mutable_
      | Some e ->
          let e = infer ctx e in
          let t = e.ty in
          if broken t then declare ctx name TErr mutable_
          else begin
            let copied =
              match e.node with EVar _ | EField _ | EIndex _ | EDeref _ -> true | _ -> false
            in
            if is_heap t && copied then
              note ctx "'%s' owns its memory; it cannot be copied, only created with box(...)"
                name
            else if t = TVoid then note ctx "cannot declare '%s' with type void" name;
            declare ctx name t mutable_
          end)
  | SLet (mutable_, name, ty, init) ->
      check_type ctx ty;
      if ty = TVoid then note ctx "cannot declare '%s' with type void" name;
      (match (ty, init) with
      | _, None -> ()
      | TArray _, Some ({ node = EArrayLit _; _ } as e) -> ignore (infer ctx ~expect:ty e)
      | TArray _, Some _ -> note ctx "'%s' is an array; it can only be initialised with [...]" name
      | TErr, Some e -> ignore (infer ctx e)
      | _, Some e -> (
          let e = infer ctx ~expect:ty e in
          let copied =
            match e.node with EVar _ | EField _ | EIndex _ | EDeref _ -> true | _ -> false
          in
          if is_heap ty && copied then
            note ctx "'%s' owns its memory; it cannot be copied, only created with box(...)" name
          else if not (assignable ty e.ty) then
            note ctx "cannot initialise '%s' (%s) with %s" name (to_string ty)
              (to_string e.ty)));
      declare ctx name ty mutable_
  | SAssign (op, lhs, rhs) ->
      let lhs = infer ctx lhs in
      if broken lhs.ty then ignore (infer ctx rhs)
      else begin
        lvalue ctx lhs;
        if is_heap lhs.ty then note ctx "a Box cannot be reassigned; it is owned where it is bound"
        else if is_array lhs.ty then note ctx "arrays cannot be assigned"
        else if op = "=" then begin
          let rhs = infer ctx ~expect:lhs.ty rhs in
          check_box_copy ctx "assignment" lhs.ty false;
          if not (assignable lhs.ty rhs.ty) then
            note ctx "cannot assign %s to %s" (to_string rhs.ty) (to_string lhs.ty)
        end
        else begin
          let binop = String.sub op 0 (String.length op - 1) in
          if not (is_numeric lhs.ty) then
            note ctx "'%s' needs a numeric target, got %s" op (to_string lhs.ty)
          else begin
            let rhs = infer ctx ~expect:lhs.ty rhs in
            if not (assignable lhs.ty rhs.ty) then
              note ctx "'%s' type mismatch: %s and %s" op (to_string lhs.ty)
                (to_string rhs.ty);
            if binop = "%" && not (is_int lhs.ty) then
              note ctx "'%s' needs an integer target" op
          end
        end
      end
  | SExpr e -> ignore (infer ctx e)
  | SBlock body ->
      push ctx;
      List.iter (check_stmt ctx) body;
      pop ctx
  | SUnsafe body ->
      ctx.unsafe_depth <- ctx.unsafe_depth + 1;
      push ctx;
      List.iter (check_stmt ctx) body;
      pop ctx;
      ctx.unsafe_depth <- ctx.unsafe_depth - 1
  | SIf (cond, th, el) ->
      let cond = infer ctx ~expect:TBool cond in
      if cond.ty <> TBool && not (broken cond.ty) then
        note ctx "'if' condition must be bool, got %s" (to_string cond.ty);
      push ctx;
      List.iter (check_stmt ctx) th;
      pop ctx;
      push ctx;
      List.iter (check_stmt ctx) el;
      pop ctx
  | SWhile (cond, body) ->
      let cond = infer ctx ~expect:TBool cond in
      if cond.ty <> TBool && not (broken cond.ty) then
        note ctx "'while' condition must be bool, got %s" (to_string cond.ty);
      ctx.loops <- ctx.loops + 1;
      push ctx;
      List.iter (check_stmt ctx) body;
      pop ctx;
      ctx.loops <- ctx.loops - 1
  | SLoop body ->
      ctx.loops <- ctx.loops + 1;
      push ctx;
      List.iter (check_stmt ctx) body;
      pop ctx;
      ctx.loops <- ctx.loops - 1
  | SFor (v, a, b, body) ->
      let a = infer ctx a in
      let b = infer ctx b in
      if is_int_lit a && is_int b.ty then a.ty <- b.ty;
      if is_int_lit b && is_int a.ty then b.ty <- a.ty;
      let t =
        if broken a.ty || broken b.ty then TErr
        else if not (is_int a.ty) then begin
          note ctx "a 'for' range needs integer endpoints, got %s" (to_string a.ty);
          TErr
        end
        else if not (assignable a.ty b.ty) then begin
          note ctx "'for' range endpoints disagree: %s and %s" (to_string a.ty)
            (to_string b.ty);
          TErr
        end
        else a.ty
      in
      ctx.loops <- ctx.loops + 1;
      push ctx;
      declare ctx v t false;
      List.iter (check_stmt ctx) body;
      pop ctx;
      ctx.loops <- ctx.loops - 1
  | SMatch (scrut, arms) ->
      let scrut = infer ctx scrut in
      let walk_bodies () =
        List.iter
          (fun arm ->
            push ctx;
            List.iter (check_stmt ctx) arm.abody;
            pop ctx)
          arms
      in
      (match scrut.ty with
      | TErr -> walk_bodies ()
      | TEnum en -> (
          match Hashtbl.find_opt ctx.enums en with
          | None ->
              note ctx "unknown enum '%s'" en;
              walk_bodies ()
          | Some variants ->
              let seen = Hashtbl.create 8 in
              let wild = ref false in
              let last = List.length arms - 1 in
              List.iteri
                (fun i arm ->
                  push ctx;
                  (match arm.apat with
                  | PWild ->
                      if !wild then note ctx "this 'match' already has a '_' arm"
                      else if i <> last then
                        note ctx "a '_' arm catches every variant left, so it has to be last";
                      wild := true
                  | PVariant (pen, pvn, binds) -> (
                      if pen <> en then
                        note ctx "a '%s' pattern cannot match a %s" pen (to_string scrut.ty);
                      match List.find_opt (fun v -> v.vname = pvn) variants with
                      | None -> note ctx "enum '%s' has no variant '%s'" en pvn
                      | Some v ->
                          if Hashtbl.mem seen pvn then
                            note ctx "variant '%s::%s' is matched twice" en pvn;
                          Hashtbl.replace seen pvn ();
                          let want = List.length v.vpayload in
                          let got = List.length binds in
                          if want <> got then
                            note ctx
                              "the pattern for '%s::%s' binds %d value(s); the variant carries %d"
                              en pvn got want
                          else List.iter2 (fun n t -> declare ctx n t false) binds v.vpayload));
                  List.iter (check_stmt ctx) arm.abody;
                  pop ctx)
                arms;
              if not !wild then
                List.iter
                  (fun v ->
                    if not (Hashtbl.mem seen v.vname) then
                      note ctx "this 'match' is not exhaustive: '%s::%s' is not covered" en
                        v.vname)
                  variants)
      | other ->
          note ctx "cannot match on %s; only an enum can be matched" (to_string other);
          walk_bodies ())
  | SBreak | SContinue -> if ctx.loops = 0 then note ctx "'break'/'continue' outside a loop"
  | SReturn None ->
      if ctx.ret <> TVoid && not (broken ctx.ret) then
        note ctx "bare 'return' in a function returning %s" (to_string ctx.ret)
  | SReturn (Some e) -> (
      let e = infer ctx ~expect:ctx.ret e in
      if ctx.ret = TVoid then note ctx "a void function cannot return a value"
      else if not (assignable ctx.ret e.ty) then
        note ctx "returns %s but the function is declared %s" (to_string e.ty)
          (to_string ctx.ret))

let rec returns (st : stmt) =
  match st with
  | SReturn _ -> true
  | SBlock body | SUnsafe body -> returns_all body
  | SIf (_, th, el) -> el <> [] && returns_all th && returns_all el
  | SWhile (cond, body) -> (
      match cond.node with EBool true -> not (leaves_loop body) | _ -> false)
  | SLoop body -> not (leaves_loop body)
  | SMatch (_, arms) -> arms <> [] && List.for_all (fun a -> returns_all a.abody) arms
  | _ -> false

and returns_all body = List.exists returns body

and leaves_loop body =
  List.exists
    (fun st ->
      match st with
      | SBreak -> true
      | SBlock b | SUnsafe b -> leaves_loop b
      | SIf (_, a, b) -> leaves_loop a || leaves_loop b
      | SMatch (_, arms) -> List.exists (fun a -> leaves_loop a.abody) arms
      | _ -> false)
    body

let check_program (p : program) : string list =
  let ctx =
    {
      structs = Hashtbl.create 16;
      enums = Hashtbl.create 16;
      funcs = Hashtbl.create 32;
      consts = Hashtbl.create 16;
      generics = Hashtbl.create 16;
      gspec = Hashtbl.create 16;
      scopes = [];
      ret = TVoid;
      where = "<top level>";
      loops = 0;
      unsafe_depth = 0;
      errors = [];
      lits = [];
    }
  in

  List.iter
    (fun (s : struct_def) ->
      if Hashtbl.mem ctx.structs s.sname then note ctx "duplicate struct '%s'" s.sname
      else Hashtbl.add ctx.structs s.sname s.sfields)
    p.structs;

  List.iter
    (fun (s : struct_def) ->
      ctx.where <- "struct " ^ s.sname;
      let seen = Hashtbl.create 8 in
      List.iter
        (fun (fname, fty) ->
          if Hashtbl.mem seen fname then
            note ctx "duplicate field '%s' in struct '%s'" fname s.sname;
          Hashtbl.add seen fname ();
          check_type ctx fty)
        s.sfields)
    p.structs;

  List.iter
    (fun (e : enum_def) ->
      if Hashtbl.mem ctx.enums e.ename then note ctx "duplicate enum '%s'" e.ename
      else if Hashtbl.mem ctx.structs e.ename then
        note ctx "'%s' is already a struct" e.ename
      else Hashtbl.add ctx.enums e.ename e.evariants)
    p.enums;

  List.iter
    (fun (e : enum_def) ->
      ctx.where <- "enum " ^ e.ename;
      let seen = Hashtbl.create 8 in
      List.iter
        (fun v ->
          if Hashtbl.mem seen v.vname then
            note ctx "duplicate variant '%s' in enum '%s'" v.vname e.ename;
          Hashtbl.add seen v.vname ();
          List.iter (fun t -> if is_heap t then note ctx "a Box cannot be a variant payload" else check_type ctx t) v.vpayload)
        e.evariants)
    p.enums;

  List.iter
    (fun (c : const_def) ->
      ctx.where <- "const " ^ c.cname;
      if Hashtbl.mem ctx.consts c.cname then note ctx "duplicate const '%s'" c.cname;
      check_type ctx c.cty;
      if c.cty = TVoid then note ctx "a const cannot be void"
      else if is_array c.cty then note ctx "a const cannot be an array"
      else if (match c.cty with TStruct _ | TEnum _ -> true | _ -> false) then
        note ctx "a const cannot be a struct or an enum";
      let v = infer ctx ~expect:c.cty c.cvalue in
      if not (assignable c.cty v.ty) then
        note ctx "declared %s but the value is %s" (to_string c.cty) (to_string v.ty);
      Hashtbl.replace ctx.consts c.cname { node = v.node; ty = c.cty })
    p.consts;

  List.iter
    (fun (e : extern_fn) ->
      ctx.where <- "extern " ^ e.ename;
      (match Hashtbl.find_opt ctx.funcs e.ename with
      | Some sg ->
          if
            sg.sig_params <> e.eparams
            || sg.sig_ret <> e.eret
            || sg.sig_variadic <> e.evariadic
          then
            note ctx "extern '%s' is declared twice with different signatures"
              e.ename
      | None ->
          Hashtbl.add ctx.funcs e.ename
            { sig_params = e.eparams; sig_ret = e.eret; sig_variadic = e.evariadic });
      List.iter (check_type ctx) e.eparams;
      check_type ctx e.eret)
    p.externs;

  List.iter
    (fun (f : fn_def) ->
      ctx.where <- "fn " ^ f.fname;
      if Hashtbl.mem ctx.funcs f.fname then note ctx "duplicate function '%s'" f.fname
      else begin
        Hashtbl.add ctx.funcs f.fname
          {
            sig_params = List.map snd f.fparams;
            sig_ret = (if f.fasync then TTask f.fret else f.fret);
            sig_variadic = false;
          };
        if f.fgenerics <> [] then begin
          Hashtbl.replace ctx.generics f.fname f.fgenerics;
          Hashtbl.replace ctx.gspec f.fname (List.map snd f.fparams, f.fret)
        end
      end;

      if f.fgenerics = [] then begin
        check_type ctx f.fret;
        List.iter (fun (_, t) -> check_type ctx t) f.fparams;
        if f.fasync && f.fret = TVoid then
          note ctx "an async fn needs a return type for its Task";
        if List.exists (fun (_, t) -> is_array t) f.fparams then
          note ctx "array parameters are not supported; take a reference instead";
        if is_array f.fret then note ctx "a function cannot return an array";
        if f.fret <> TVoid && not (returns_all f.fbody) then
          note ctx "not every path through '%s' returns %s" f.fname (to_string f.fret)
      end)
    p.fns;

  ctx.where <- "<top level>";
  (match List.find_opt (fun (f : fn_def) -> f.fname = "main") p.fns with
  | None -> note ctx "no 'fn main' in this program"
  | Some f ->
      if f.fgenerics <> [] then note ctx "fn main cannot be generic";
      if f.fparams <> [] then note ctx "fn main takes no parameters";
      if f.fret <> TI32 then note ctx "fn main must return i32, not %s" (to_string f.fret));

  List.iter
    (fun (f : fn_def) ->
      if f.fgenerics = [] then begin
        ctx.where <- "fn " ^ f.fname;
        ctx.ret <- f.fret;
        ctx.loops <- 0;
        ctx.unsafe_depth <- 0;
        ctx.scopes <- [ [] ];
        List.iter (fun (n, t) -> declare ctx n t true) f.fparams;
        push ctx;
        List.iter (check_stmt ctx) f.fbody;
        pop ctx;
        ctx.scopes <- []
      end)
    p.fns;


  List.iter
    (fun (e, v, where) ->
      match int_range e.ty with
      | None -> ()
      | Some (lo, hi) ->
          if v > hi then begin
            ctx.where <- where;
            note ctx "integer literal %Ld is over the %s limit of %Ld" v (to_string e.ty) hi
          end
          else if v < lo then begin
            ctx.where <- where;
            note ctx "integer literal %Ld is under the %s limit of %Ld" v (to_string e.ty) lo
          end)
    ctx.lits;

  List.rev ctx.errors

open Ast

exception Error of string

let fail fmt = Printf.ksprintf (fun s -> raise (Error s)) fmt
let align_up v a = if a <= 1 then v else (v + a - 1) / a * a

let o_pop = 1
let o_dup = 2
let o_swap = 3
let o_push = 4
let o_ldl8u = 5
let o_ldl8s = 6
let o_ldl16u = 7
let o_ldl16s = 8
let o_ldl32u = 9
let o_ldl32s = 10
let o_ldl64 = 11
let o_stl8 = 12
let o_stl16 = 13
let o_stl32 = 14
let o_stl64 = 15
let o_ldlf32 = 16
let o_stlf32 = 17
let o_ldlf64 = 18
let o_stlf64 = 19
let o_lea = 20
let o_ld8u = 21
let o_ld8s = 22
let o_ld16u = 23
let o_ld16s = 24
let o_ld32u = 25
let o_ld32s = 26
let o_ld64 = 27
let o_ldf32 = 28
let o_ldf64 = 29
let o_st8 = 30
let o_st16 = 31
let o_st32 = 32
let o_st64 = 33
let o_stf32 = 34
let o_stf64 = 35
let o_add = 36
let o_sub = 37
let o_mul = 38
let o_divs = 39
let o_divu = 40
let o_rems = 41
let o_remu = 42
let o_and = 43
let o_or = 44
let o_xor = 45
let o_shl = 46
let o_shrs = 47
let o_shru = 48
let o_fadd = 49
let o_fsub = 50
let o_fmul = 51
let o_fdiv = 52
let o_fneg = 53
let o_eq = 54
let o_ne = 55
let o_lts = 56
let o_les = 57
let o_gts = 58
let o_ges = 59
let o_ltu = 60
let o_leu = 61
let o_gtu = 62
let o_geu = 63
let o_feq = 64
let o_fne = 65
let o_flt = 66
let o_fle = 67
let o_fgt = 68
let o_fge = 69
let o_neg = 70
let o_not = 71
let o_itof = 72
let o_utof = 73
let o_ftoi = 74
let o_roundf32 = 75
let o_jmp = 76
let o_jz = 77
let o_jnz = 78
let o_call = 79
let o_ret = 80
let o_callind = 81
let o_copy = 82
let o_zero = 83
let o_mkthunk = 84
let o_poll = 85
let o_await = 86
let o_str = 87
let o_fnref = 88
let o_malloc = 89
let o_free = 90
let o_bcheck = 91

type cbuf = { mutable data : Bytes.t; mutable len : int }

let cb_create () = { data = Bytes.create 1024; len = 0 }

let cb_reserve b need =
  if b.len + need > Bytes.length b.data then begin
    let cap = ref (max 1024 (Bytes.length b.data)) in
    while b.len + need > !cap do
      cap := !cap * 2
    done;
    let d = Bytes.create !cap in
    Bytes.blit b.data 0 d 0 b.len;
    b.data <- d
  end

let cb_u8 b v =
  cb_reserve b 1;
  Bytes.set b.data b.len (Char.chr (v land 255));
  b.len <- b.len + 1

let cb_u32 b v =
  cb_reserve b 4;
  Bytes.set_int32_le b.data b.len (Int32.of_int v);
  b.len <- b.len + 4

let cb_i64 b v =
  cb_reserve b 8;
  Bytes.set_int64_le b.data b.len v;
  b.len <- b.len + 8

let cb_str b s =
  let n = String.length s in
  cb_reserve b n;
  Bytes.blit_string s 0 b.data b.len n;
  b.len <- b.len + n

let cb_patch b at v = Bytes.set_int32_le b.data at (Int32.of_int v)

type fentry = {
  fe_name : string;
  fe_kind : int;
  fe_sret : bool;
  fe_params : int;
  mutable fe_frame : int;
  mutable fe_code : cbuf;
}

type ctx = {
  code : cbuf;
  labels : (int, int) Hashtbl.t;
  mutable patches : (int * int) list;
  mutable nlabel : int;
  mutable next_off : int;
  mutable tmp_off : int;
  mutable max_off : int;
  mutable scopes : (string, int * typ) Hashtbl.t list;
  mutable loops : (int * int) list;
  mutable sret_slot : int;
}

type gen = {
  info : Cg.info;
  strs : (string, int) Hashtbl.t;
  mutable strtab : string list;
  fnames : (string, int) Hashtbl.t;
  fentries : fentry array;
  rets : (string, typ) Hashtbl.t;
  async : (string, bool) Hashtbl.t;
  consts : (string, expr) Hashtbl.t;
  unchecked : unit ESet.t;
  mutable cguard : string list;
}

let new_label c =
  c.nlabel <- c.nlabel + 1;
  c.nlabel

let place c lbl = Hashtbl.replace c.labels lbl c.code.len

let jump_to c lbl =
  let at = c.code.len in
  cb_u32 c.code 0;
  c.patches <- (at, lbl) :: c.patches

let emit_jmp c = cb_u8 c.code o_jmp; jump_to c
let emit_jz c = cb_u8 c.code o_jz; jump_to c
let emit_jnz c = cb_u8 c.code o_jnz; jump_to c

let alloc c n =
  let off = align_up c.next_off 8 in
  c.next_off <- off + max 1 n;
  if c.next_off > c.max_off then c.max_off <- c.next_off;
  off

let alloc_tmp c n =
  let off = align_up c.tmp_off 8 in
  c.tmp_off <- off + max 1 n;
  if c.tmp_off > c.max_off then c.max_off <- c.tmp_off;
  off

let push_scope c = c.scopes <- Hashtbl.create 8 :: c.scopes
let pop_scope c = match c.scopes with _ :: t -> c.scopes <- t | [] -> ()

let bind c n off ty =
  match c.scopes with
  | s :: _ -> Hashtbl.replace s n (off, ty)
  | [] -> fail "internal: no scope"

let lookup c n =
  let rec go = function
    | [] -> None
    | s :: rest -> ( match Hashtbl.find_opt s n with Some v -> Some v | None -> go rest)
  in
  go c.scopes

let size g t = Cg.size_of g.info t

let is_agg = Cg.is_agg

let rec peel t = match t with TRef (u, _) -> peel u | TBox u -> peel u | t -> t

let field_off g base f =
  let rec p = function TRef (t, _) -> p t | TBox t -> p t | TPtr t -> p t | t -> t in
  match p base with
  | TTuple ts -> (
      match int_of_string_opt f with
      | Some i when i >= 0 && i < List.length ts -> List.nth (Cg.tuple_layout g.info ts).toffs i
      | _ -> fail "a tuple of %d element(s) has no element '%s'" (List.length ts) f)
  | t ->
      let s =
        match t with
        | TStruct s -> s
        | _ -> fail "field access on %s" (to_string base)
      in
      ( match List.assoc_opt f (Cg.layout_of g.info s).lfields with
      | Some o -> o
      | None -> fail "struct '%s' has no field '%s'" s f)

let field_ty g s f =
  match Hashtbl.find_opt g.info.structs s with
  | None -> fail "unknown struct '%s'" s
  | Some fs -> (
      match List.assoc_opt f fs with
      | Some t -> t
      | None -> fail "struct '%s' has no field '%s'" s f)

let variant_of g s v =
  match Hashtbl.find_opt g.info.enums s with
  | None -> fail "unknown enum '%s'" s
  | Some vs -> (
      match List.find_opt (fun x -> x.vname = v) vs with
      | Some x -> x
      | None -> fail "enum '%s' has no variant '%s'" s v)

let variant_index g s v =
  match Hashtbl.find_opt g.info.enums s with
  | None -> fail "unknown enum '%s'" s
  | Some vs ->
      let rec go i = function
        | [] -> fail "enum '%s' has no variant '%s'" s v
        | x :: rest -> if x.vname = v then i else go (i + 1) rest
      in
      go 0 vs

let variant_offs g s v =
  match List.assoc_opt v (Cg.enum_layout_of g.info s).evars with
  | Some o -> o
  | None -> fail "enum '%s' has no variant '%s'" s v

let str_id g s =
  match Hashtbl.find_opt g.strs s with
  | Some i -> i
  | None ->
      let i = List.length g.strtab in
      g.strtab <- s :: g.strtab;
      Hashtbl.replace g.strs s i;
      i

let fn_index g n =
  match Hashtbl.find_opt g.fnames n with
  | Some i -> i
  | None -> fail "unknown function '%s'" n

let f32bits f =
  let b = Int32.bits_of_float f in
  Int64.of_int32 b

let push_int c v = cb_u8 c.code o_push; cb_i64 c.code v
let push_small c v = push_int c (Int64.of_int v)

let ldl_op t =
  match t with
  | TI8 -> o_ldl8s
  | TU8 | TBool -> o_ldl8u
  | TI16 -> o_ldl16s
  | TU16 -> o_ldl16u
  | TI32 -> o_ldl32s
  | TU32 -> o_ldl32u
  | TF32 -> o_ldlf32
  | TF64 -> o_ldlf64
  | _ -> o_ldl64

let stl_op t =
  match t with
  | TI8 | TU8 | TBool -> o_stl8
  | TI16 | TU16 -> o_stl16
  | TI32 | TU32 -> o_stl32
  | TF32 -> o_stlf32
  | TF64 -> o_stlf64
  | _ -> o_stl64

let ld_op t =
  match t with
  | TI8 -> o_ld8s
  | TU8 | TBool -> o_ld8u
  | TI16 -> o_ld16s
  | TU16 -> o_ld16u
  | TI32 -> o_ld32s
  | TU32 -> o_ld32u
  | TF32 -> o_ldf32
  | TF64 -> o_ldf64
  | _ -> o_ld64

let st_op t =
  match t with
  | TI8 | TU8 | TBool -> o_st8
  | TI16 | TU16 -> o_st16
  | TI32 | TU32 -> o_st32
  | TF32 -> o_stf32
  | TF64 -> o_stf64
  | _ -> o_st64

let emit_ldl c off t = cb_u8 c.code (ldl_op t); cb_u32 c.code off
let emit_stl c off t = cb_u8 c.code (stl_op t); cb_u32 c.code off
let emit_ld c t = cb_u8 c.code (ld_op t)
let emit_st c t = cb_u8 c.code (st_op t)

let norm_int c t =
  match t with
  | TI8 ->
      push_small c 56;
      cb_u8 c.code o_shl;
      push_small c 56;
      cb_u8 c.code o_shrs
  | TI16 ->
      push_small c 48;
      cb_u8 c.code o_shl;
      push_small c 48;
      cb_u8 c.code o_shrs
  | TI32 ->
      push_small c 32;
      cb_u8 c.code o_shl;
      push_small c 32;
      cb_u8 c.code o_shrs
  | TU8 ->
      push_small c 255;
      cb_u8 c.code o_and
  | TU16 ->
      push_small c 65535;
      cb_u8 c.code o_and
  | TU32 ->
      push_int c 0xFFFFFFFFL;
      cb_u8 c.code o_and
  | _ -> ()

let to_bool_direct c =
  push_small c 0;
  cb_u8 c.code o_eq

let int_ty = function
  | TI8 | TI16 | TI32 | TI64 | TU8 | TU16 | TU32 | TU64 | TBool | TPtr _ | TRef _ | TBox _
  | TFn _ | TFnC _ | TTask _ ->
      true
  | _ -> false

let rec gen_addr g c (e : expr) =
  match e.node with
  | EVar n -> (
      match lookup c n with
      | Some (off, _) -> cb_u8 c.code o_lea; cb_u32 c.code off
      | None -> fail "unknown variable '%s'" n)
  | EField (base, f) ->
      let off = field_off g base.ty f in
      ( match base.ty with
      | TStruct _ | TTuple _ -> gen_addr g c base
      | TPtr _ | TRef _ | TBox _ -> gen_scalar g c base
      | t -> fail "field access on %s" (to_string t));
      if off <> 0 then begin
        push_small c off;
        cb_u8 c.code o_add
      end
  | EIndex (base, idx) -> (
      let bt = base.ty in
      let et =
        match peel bt with
        | TArray (t, _) -> t
        | TPtr t -> t
        | t -> fail "cannot index %s" (to_string t)
      in
      let bound = match peel bt with TArray (_, n) -> Some n | _ -> None in
      let esz = max 1 (size g et) in
      (match bt with
      | TArray _ -> gen_addr g c base
      | TPtr _ | TRef _ | TBox _ -> gen_scalar g c base
      | t -> fail "cannot index %s" (to_string t));
      gen_scalar g c idx;
      (match bound with
      | Some n when not (ESet.mem g.unchecked e) ->
          cb_u8 c.code o_bcheck;
          cb_u32 c.code n
      | _ -> ());
      if esz <> 1 then begin
        push_small c esz;
        cb_u8 c.code o_mul
      end;
      cb_u8 c.code o_add)
  | EDeref p -> gen_scalar g c p
  | EAddr a | EAddrMut a -> gen_addr g c a
  | EAwait a ->
      gen_value g c a;
      cb_u8 c.code o_await
  | EStructLit (name, fields) -> struct_lit g c name fields
  | EArrayLit items -> (
      match e.ty with
      | TArray (et, n) ->
          let esz = max 1 (size g et) in
          let s = alloc_tmp c (esz * n) in
          cb_u8 c.code o_lea;
          cb_u32 c.code s;
          cb_u8 c.code o_zero;
          cb_u32 c.code (esz * n);
          List.iteri
            (fun i it ->
              if i < n then
                if is_agg et then begin
                  gen_addr g c it;
                  cb_u8 c.code o_lea;
                  cb_u32 c.code (s + (i * esz));
                  cb_u8 c.code o_copy;
                  cb_u32 c.code esz
                end
                else begin
                  cb_u8 c.code o_lea;
                  cb_u32 c.code (s + (i * esz));
                  gen_scalar g c it;
                  emit_st c et
                end)
            items;
          cb_u8 c.code o_lea;
          cb_u32 c.code s
      | t -> fail "array literal typed %s" (to_string t))
  | EEnumLit (en, vn, args) -> enum_lit g c en vn args e.ty
  | EZero t when is_agg t ->
      let n = size g t in
      let s = alloc_tmp c (max 1 n) in
      cb_u8 c.code o_lea;
      cb_u32 c.code s;
      cb_u8 c.code o_zero;
      cb_u32 c.code n;
      cb_u8 c.code o_lea;
      cb_u32 c.code s
  | ETupleLit items -> (
      match e.ty with
      | TTuple ts when List.length ts = List.length items ->
          let l = Cg.tuple_layout g.info ts in
          let s = alloc_tmp c (max 1 l.tsize) in
          cb_u8 c.code o_lea;
          cb_u32 c.code s;
          cb_u8 c.code o_zero;
          cb_u32 c.code l.tsize;
          List.iter2
            (fun off v ->
              if is_agg v.ty then begin
                gen_addr g c v;
                cb_u8 c.code o_lea;
                cb_u32 c.code (s + off);
                cb_u8 c.code o_copy;
                cb_u32 c.code (max 1 (size g v.ty))
              end
              else begin
                cb_u8 c.code o_lea;
                cb_u32 c.code (s + off);
                gen_scalar g c v;
                emit_st c v.ty
              end)
            l.toffs items;
          cb_u8 c.code o_lea;
          cb_u32 c.code s
      | t -> fail "tuple literal typed %s" (to_string t))
  | ECall (name, args) -> gen_call g c name args e.ty
  | ECallV (f, args) -> gen_callv g c f args e.ty
  | _ -> fail "this expression has no address"

and gen_scalar g c (e : expr) =
  match e.node with
  | EInt n -> push_int c n
  | EFloat f ->
      let v =
        if e.ty = TF32 then Int32.float_of_bits (Int32.bits_of_float f) else f
      in
      cb_u8 c.code o_push;
      cb_i64 c.code (Int64.bits_of_float v)
  | EBool v -> push_small c (if v then 1 else 0)
  | ENull -> push_small c 0
  | EStr s ->
      let id = str_id g (Cg.unquote s) in
      cb_u8 c.code o_str;
      cb_u32 c.code id
  | ESizeof t -> push_int c (Int64.of_int (size g t))
  | EZero t -> (
      match t with
      | TF32 | TF64 -> cb_u8 c.code o_push; cb_i64 c.code 0L
      | _ -> push_small c 0)
  | EVar n -> (
      match lookup c n with
      | Some (off, ty) -> emit_ldl c off ty
      | None -> (
          match Hashtbl.find_opt g.fnames n with
          | Some i ->
              cb_u8 c.code o_fnref;
              cb_u32 c.code i
          | None -> (
              match Hashtbl.find_opt g.consts n with
              | Some v when not (List.mem n g.cguard) ->
                  g.cguard <- n :: g.cguard;
                  gen_value g c v;
                  g.cguard <- List.tl g.cguard
              | Some _ -> fail "const '%s' refers to itself" n
              | None -> fail "unknown variable '%s'" n)))
  | EFnRef n ->
      cb_u8 c.code o_fnref;
      cb_u32 c.code (fn_index g n)
  | EPoll a ->
      gen_value g c a;
      cb_u8 c.code o_poll
  | EAwait a ->
      gen_value g c a;
      cb_u8 c.code o_await
  | EAddr a | EAddrMut a -> gen_addr g c a
  | EBoxNew payload ->
      let n = max 1 (size g payload.ty) in
      let t = alloc_tmp c n in
      if is_agg payload.ty then begin
        gen_addr g c payload;
        cb_u8 c.code o_lea;
        cb_u32 c.code t;
        cb_u8 c.code o_copy;
        cb_u32 c.code n;
        push_small c n;
        cb_u8 c.code o_malloc;
        cb_u8 c.code o_dup;
        cb_u8 c.code o_lea;
        cb_u32 c.code t;
        cb_u8 c.code o_swap;
        cb_u8 c.code o_copy;
        cb_u32 c.code n
      end
      else begin
        cb_u8 c.code o_lea;
        cb_u32 c.code t;
        gen_scalar g c payload;
        emit_st c payload.ty;
        push_small c n;
        cb_u8 c.code o_malloc;
        cb_u8 c.code o_dup;
        cb_u8 c.code o_lea;
        cb_u32 c.code t;
        emit_ld c payload.ty;
        emit_st c payload.ty
      end
  | EField _ | EIndex _ | EDeref _ ->
      gen_addr g c e;
      emit_ld c e.ty
  | EBin (op, a, b) -> gen_bin g c op a b
  | EUn (op, a) -> (
      match op with
      | "-" ->
          gen_scalar g c a;
          if a.ty = TF32 || a.ty = TF64 then cb_u8 c.code o_fneg else cb_u8 c.code o_neg
      | "~" ->
          gen_scalar g c a;
          cb_u8 c.code o_not
      | "!" ->
          gen_scalar g c a;
          to_bool_direct c
      | _ -> fail "unknown unary operator '%s' (on %s)" op (to_string e.ty))
  | ECast (a, t) -> gen_cast g c a t
  | ECall (name, args) -> gen_call g c name args e.ty
  | ECallV (f, args) -> gen_callv g c f args e.ty
  | EStructLit _ | EArrayLit _ | EEnumLit _ | ETupleLit _ ->
      fail "aggregate used as a scalar"

and gen_value g c (e : expr) = if is_agg e.ty then gen_addr g c e else gen_scalar g c e

and gen_arg g c (e : expr) = if is_agg e.ty then gen_addr g c e else gen_scalar g c e

and struct_lit g c name fields =
  let l = Cg.layout_of g.info name in
  let s = alloc_tmp c (max 1 l.lsize) in
  cb_u8 c.code o_lea;
  cb_u32 c.code s;
  cb_u8 c.code o_zero;
  cb_u32 c.code l.lsize;
  List.iter
    (fun (fname, v) ->
      let off =
        match List.assoc_opt fname l.lfields with
        | Some o -> o
        | None -> fail "struct '%s' has no field '%s'" name fname
      in
      let ft = field_ty g name fname in
      if is_agg ft then begin
        gen_addr g c v;
        cb_u8 c.code o_lea;
        cb_u32 c.code (s + off);
        cb_u8 c.code o_copy;
        cb_u32 c.code (max 1 (size g ft))
      end
      else begin
        cb_u8 c.code o_lea;
        cb_u32 c.code (s + off);
        gen_scalar g c v;
        emit_st c ft
      end)
    fields;
  cb_u8 c.code o_lea;
  cb_u32 c.code s

and enum_lit g c en vn args ty =
  ignore ty;
  let l = Cg.enum_layout_of g.info en in
  let offs = variant_offs g en vn in
  if List.length offs <> List.length args then
    fail "'%s::%s' carries %d value(s), given %d" en vn (List.length offs)
      (List.length args);
  let s = alloc_tmp c (max 1 l.esize) in
  cb_u8 c.code o_lea;
  cb_u32 c.code s;
  cb_u8 c.code o_zero;
  cb_u32 c.code l.esize;
  cb_u8 c.code o_lea;
  cb_u32 c.code s;
  push_small c (variant_index g en vn);
  cb_u8 c.code o_st64;
  List.iter2
    (fun off (arg : expr) ->
      if is_agg arg.ty then begin
        gen_addr g c arg;
        cb_u8 c.code o_lea;
        cb_u32 c.code (s + off);
        cb_u8 c.code o_copy;
        cb_u32 c.code (max 1 (size g arg.ty))
      end
      else begin
        cb_u8 c.code o_lea;
        cb_u32 c.code (s + off);
        gen_scalar g c arg;
        emit_st c arg.ty
      end)
    offs args;
  cb_u8 c.code o_lea;
  cb_u32 c.code s

and gen_bin g c op a b =
  match op with
  | "&&" ->
      let lfalse = new_label c in
      let lend = new_label c in
      gen_scalar g c a;
      emit_jz c lfalse;
      gen_scalar g c b;
      emit_jmp c lend;
      place c lfalse;
      push_small c 0;
      place c lend
  | "||" ->
      let ltrue = new_label c in
      let lend = new_label c in
      gen_scalar g c a;
      emit_jnz c ltrue;
      gen_scalar g c b;
      emit_jmp c lend;
      place c ltrue;
      push_small c 1;
      place c lend
  | _ ->
      let f32 = a.ty = TF32 in
      let cmp = List.mem op [ "=="; "!="; "<"; "<="; ">"; ">=" ] in
      if a.ty = TF32 || a.ty = TF64 then begin
        gen_scalar g c a;
        gen_scalar g c b;
        (match op with
        | "+" -> cb_u8 c.code o_fadd
        | "-" -> cb_u8 c.code o_fsub
        | "*" -> cb_u8 c.code o_fmul
        | "/" -> cb_u8 c.code o_fdiv
        | "==" -> cb_u8 c.code o_feq
        | "!=" -> cb_u8 c.code o_fne
        | "<" -> cb_u8 c.code o_flt
        | "<=" -> cb_u8 c.code o_fle
        | ">" -> cb_u8 c.code o_fgt
        | ">=" -> cb_u8 c.code o_fge
        | _ -> fail "operator '%s' does not apply to %s" op (to_string a.ty));
        if f32 && not cmp then cb_u8 c.code o_roundf32
      end
      else begin
        gen_scalar g c a;
        gen_scalar g c b;
        let uns = not (is_signed a.ty) in
        (match peel a.ty with
        | TPtr et when op = "+" || op = "-" ->
            let esz = max 1 (size g et) in
            if esz <> 1 then begin
              push_small c esz;
              cb_u8 c.code o_mul
            end
        | _ -> ());
        match op with
        | "+" -> cb_u8 c.code o_add
        | "-" -> cb_u8 c.code o_sub
        | "*" -> cb_u8 c.code o_mul
        | "/" -> cb_u8 c.code (if uns then o_divu else o_divs)
        | "%" -> cb_u8 c.code (if uns then o_remu else o_rems)
        | "&" -> cb_u8 c.code o_and
        | "|" -> cb_u8 c.code o_or
        | "^" -> cb_u8 c.code o_xor
        | "<<" -> cb_u8 c.code o_shl
        | ">>" -> cb_u8 c.code (if uns then o_shru else o_shrs)
        | "==" -> cb_u8 c.code o_eq
        | "!=" -> cb_u8 c.code o_ne
        | "<" -> cb_u8 c.code (if uns then o_ltu else o_lts)
        | "<=" -> cb_u8 c.code (if uns then o_leu else o_les)
        | ">" -> cb_u8 c.code (if uns then o_gtu else o_gts)
        | ">=" -> cb_u8 c.code (if uns then o_geu else o_ges)
        | _ -> fail "unknown operator '%s'" op
      end

and gen_cast g c a t =
  let src = a.ty in
  gen_scalar g c a;
  match (src, t) with
  | TF32, TF64 -> ()
  | TF64, TF32 -> cb_u8 c.code o_roundf32
  | (TF32 | TF64), tt when int_ty tt ->
      cb_u8 c.code o_ftoi;
      if t = TBool then to_bool_direct c else norm_int c t
  | st, (TF32 | TF64) when int_ty st ->
      if st = TU64 then cb_u8 c.code o_utof else cb_u8 c.code o_itof;
      if t = TF32 then cb_u8 c.code o_roundf32
  | TBool, _ -> norm_int c t
  | _, TBool -> to_bool_direct c
  | st, tt when int_ty st && int_ty tt -> norm_int c t
  | _ -> ()

and gen_call g c name args ret_ty =
  match lookup c name with
  | Some (off, fty) when (match fty with TFn _ | TFnC _ -> true | _ -> false) ->
      if is_agg ret_ty then begin
        let res = alloc_tmp c (size g ret_ty) in
        cb_u8 c.code o_lea;
        cb_u32 c.code res;
        emit_ldl c off fty;
        List.iter (gen_arg g c) args;
        cb_u8 c.code o_callind;
        cb_u32 c.code (List.length args);
        cb_u8 c.code o_pop;
        cb_u8 c.code o_lea;
        cb_u32 c.code res
      end
      else begin
        emit_ldl c off fty;
        List.iter (gen_arg g c) args;
        cb_u8 c.code o_callind;
        cb_u32 c.code (List.length args)
      end
  | _ -> (
      match Hashtbl.find_opt g.async name with
      | Some true -> gen_thunk g c name args
      | _ ->
          let idx = fn_index g name in
          if is_agg ret_ty then begin
            let res = alloc_tmp c (size g ret_ty) in
            cb_u8 c.code o_lea;
            cb_u32 c.code res;
            List.iter (gen_arg g c) args;
            cb_u8 c.code o_call;
            cb_u32 c.code idx;
            cb_u32 c.code (List.length args);
            cb_u8 c.code o_pop;
            cb_u8 c.code o_lea;
            cb_u32 c.code res
          end
          else begin
            List.iter (gen_arg g c) args;
            cb_u8 c.code o_call;
            cb_u32 c.code idx;
            cb_u32 c.code (List.length args)
          end)

and gen_callv g c f args ret_ty =
  if is_agg ret_ty then begin
    let res = alloc_tmp c (size g ret_ty) in
    cb_u8 c.code o_lea;
    cb_u32 c.code res;
    gen_scalar g c f;
    List.iter (gen_arg g c) args;
    cb_u8 c.code o_callind;
    cb_u32 c.code (List.length args);
    cb_u8 c.code o_pop;
    cb_u8 c.code o_lea;
    cb_u32 c.code res
  end
  else begin
    gen_scalar g c f;
    List.iter (gen_arg g c) args;
    cb_u8 c.code o_callind;
    cb_u32 c.code (List.length args)
  end

and gen_thunk g c name args =
  let idx = fn_index g name in
  let ret = try Hashtbl.find g.rets name with Not_found -> TVoid in
  let res_size = if is_agg ret then size g ret else 0 in
  List.iter (gen_arg g c) args;
  cb_u8 c.code o_mkthunk;
  cb_u32 c.code idx;
  cb_u32 c.code (List.length args);
  cb_u32 c.code res_size;
  List.iter
    (fun a -> cb_u32 c.code (if is_agg a.ty then max 1 (size g a.ty) else 0))
    args

and gen_stmt g c (s : stmt) =
  c.tmp_off <- c.next_off;
  match s with
  | SLet (_, name, ty, init) ->
      let ty =
        if ty = TInfer then
          match init with
          | Some e -> e.ty
          | None -> fail "cannot infer a type for '%s'" name
        else ty
      in
      let n = max 1 (size g ty) in
      let off = alloc c n in
      c.tmp_off <- c.next_off;
      (match init with
      | None ->
          if is_agg ty then begin
            cb_u8 c.code o_lea;
            cb_u32 c.code off;
            cb_u8 c.code o_zero;
            cb_u32 c.code n
          end
          else begin
            push_small c 0;
            emit_stl c off ty
          end
      | Some e ->
          if is_agg ty then begin
            gen_addr g c e;
            cb_u8 c.code o_lea;
            cb_u32 c.code off;
            cb_u8 c.code o_copy;
            cb_u32 c.code n
          end
          else begin
            gen_scalar g c e;
            emit_stl c off ty
          end);
      bind c name off ty
  | SAssign (op, lhs, rhs) -> gen_assign g c op lhs rhs
  | SExpr e ->
      gen_value g c e;
      cb_u8 c.code o_pop
  | SBlock stmts ->
      push_scope c;
      List.iter (gen_stmt g c) stmts;
      pop_scope c
  | SUnsafe stmts ->
      push_scope c;
      List.iter (gen_stmt g c) stmts;
      pop_scope c
  | SIf (cond, th, el) ->
      let lelse = new_label c in
      gen_scalar g c cond;
      emit_jz c lelse;
      push_scope c;
      List.iter (gen_stmt g c) th;
      pop_scope c;
      if el = [] then place c lelse
      else begin
        let lend = new_label c in
        emit_jmp c lend;
        place c lelse;
        push_scope c;
        List.iter (gen_stmt g c) el;
        pop_scope c;
        place c lend
      end
  | SWhile (cond, body) ->
      let lstart = new_label c in
      let lend = new_label c in
      place c lstart;
      gen_scalar g c cond;
      emit_jz c lend;
      c.loops <- (lend, lstart) :: c.loops;
      push_scope c;
      List.iter (gen_stmt g c) body;
      pop_scope c;
      c.loops <- List.tl c.loops;
      emit_jmp c lstart;
      place c lend
  | SLoop body ->
      let lstart = new_label c in
      let lend = new_label c in
      place c lstart;
      c.loops <- (lend, lstart) :: c.loops;
      push_scope c;
      List.iter (gen_stmt g c) body;
      pop_scope c;
      c.loops <- List.tl c.loops;
      emit_jmp c lstart;
      place c lend
  | SFor (v, lo, hi, body) ->
      let t =
        match peel lo.ty with
        | TErr | TVoid -> TI64
        | x when is_int x -> x
        | _ -> TI64
      in
      let slot = alloc c 8 in
      let lim = alloc c 8 in
      let lbody = new_label c in
      let lcont = new_label c in
      let lcond = new_label c in
      let lend = new_label c in
      c.tmp_off <- c.next_off;
      gen_scalar g c lo;
      emit_stl c slot TI64;
      gen_scalar g c hi;
      emit_stl c lim TI64;
      emit_jmp c lcond;
      c.loops <- (lend, lcont) :: c.loops;
      place c lbody;
      push_scope c;
      bind c v slot t;
      List.iter (gen_stmt g c) body;
      pop_scope c;
      c.loops <- List.tl c.loops;
      place c lcont;
      emit_ldl c slot TI64;
      push_small c 1;
      cb_u8 c.code o_add;
      emit_stl c slot TI64;
      place c lcond;
      emit_ldl c slot TI64;
      emit_ldl c lim TI64;
      cb_u8 c.code (if is_signed t then o_lts else o_ltu);
      emit_jnz c lbody;
      place c lend
  | SMatch (scrut, arms) ->
      let n = max 8 (size g scrut.ty) in
      let slot = alloc c n in
      c.tmp_off <- c.next_off;
      gen_addr g c scrut;
      cb_u8 c.code o_lea;
      cb_u32 c.code slot;
      cb_u8 c.code o_copy;
      cb_u32 c.code n;
      let lend = new_label c in
      let labelled = List.map (fun arm -> (arm, new_label c)) arms in
      let wildcard = ref None in
      List.iter
        (fun (arm, lbl) ->
          match arm.apat with
          | PWild -> wildcard := Some lbl
          | PVariant (en, vn, _) ->
              emit_ldl c slot TI64;
              push_small c (variant_index g en vn);
              cb_u8 c.code o_eq;
              emit_jnz c lbl)
        labelled;
      emit_jmp c (match !wildcard with Some l -> l | None -> lend);
      List.iter
        (fun (arm, lbl) ->
          place c lbl;
          push_scope c;
          (match arm.apat with
          | PWild -> ()
          | PVariant (en, vn, binds) ->
              let v = variant_of g en vn in
              let offs = variant_offs g en vn in
              if List.length offs <> List.length binds then
                fail "the pattern for '%s::%s' binds %d value(s); the variant carries %d" en
                  vn (List.length binds) (List.length offs);
              List.iter2
                (fun b (off, bt) ->
                  let sz = max 1 (size g bt) in
                  let bslot = alloc c sz in
                  c.tmp_off <- c.next_off;
                  if is_agg bt then begin
                    cb_u8 c.code o_lea;
                    cb_u32 c.code (slot + off);
                    cb_u8 c.code o_lea;
                    cb_u32 c.code bslot;
                    cb_u8 c.code o_copy;
                    cb_u32 c.code sz
                  end
                  else begin
                    emit_ldl c (slot + off) bt;
                    emit_stl c bslot bt
                  end;
                  bind c b bslot bt)
                binds
                (List.combine offs v.vpayload));
          List.iter (gen_stmt g c) arm.abody;
          pop_scope c;
          emit_jmp c lend)
        labelled;
      place c lend
  | SBreak -> (
      match c.loops with
      | (brk, _) :: _ -> emit_jmp c brk
      | [] -> fail "'break' outside a loop")
  | SContinue -> (
      match c.loops with
      | (_, cont) :: _ -> emit_jmp c cont
      | [] -> fail "'continue' outside a loop")
  | SReturn None ->
      push_small c 0;
      cb_u8 c.code o_ret
  | SReturn (Some e) ->
      if c.sret_slot >= 0 then begin
        gen_addr g c e;
        emit_ldl c c.sret_slot TI64;
        cb_u8 c.code o_copy;
        cb_u32 c.code (size g e.ty);
        emit_ldl c c.sret_slot TI64;
        cb_u8 c.code o_ret
      end
      else begin
        gen_value g c e;
        cb_u8 c.code o_ret
      end

and gen_assign_op c bop ty =
  if ty = TF32 || ty = TF64 then begin
    (match bop with
    | "+" -> cb_u8 c.code o_fadd
    | "-" -> cb_u8 c.code o_fsub
    | "*" -> cb_u8 c.code o_fmul
    | "/" -> cb_u8 c.code o_fdiv
    | _ -> fail "'%s' does not apply to %s" bop (to_string ty));
    if ty = TF32 then cb_u8 c.code o_roundf32
  end
  else begin
    let uns = not (is_signed ty) in
    match bop with
    | "+" -> cb_u8 c.code o_add
    | "-" -> cb_u8 c.code o_sub
    | "*" -> cb_u8 c.code o_mul
    | "/" -> cb_u8 c.code (if uns then o_divu else o_divs)
    | "%" -> cb_u8 c.code (if uns then o_remu else o_rems)
    | "&" -> cb_u8 c.code o_and
    | "|" -> cb_u8 c.code o_or
    | "^" -> cb_u8 c.code o_xor
    | "<<" -> cb_u8 c.code o_shl
    | ">>" -> cb_u8 c.code (if uns then o_shru else o_shrs)
    | _ -> fail "unknown assignment operator '%s'" bop
  end

and gen_assign g c op lhs rhs =
  let local =
    if is_agg lhs.ty then None
    else match lhs.node with EVar n -> lookup c n | _ -> None
  in
  match local with
  | Some (off, _) ->
      if op = "=" then begin
        gen_scalar g c rhs;
        emit_stl c off lhs.ty
      end
      else begin
        let bop = String.sub op 0 (String.length op - 1) in
        emit_ldl c off lhs.ty;
        gen_scalar g c rhs;
        gen_assign_op c bop lhs.ty;
        emit_stl c off lhs.ty
      end
  | None ->
      if op = "=" then
        if is_agg lhs.ty then begin
          gen_addr g c rhs;
          gen_addr g c lhs;
          cb_u8 c.code o_copy;
          cb_u32 c.code (max 1 (size g lhs.ty))
        end
        else begin
          gen_addr g c lhs;
          gen_scalar g c rhs;
          emit_st c lhs.ty
        end
      else begin
        let bop = String.sub op 0 (String.length op - 1) in
        gen_addr g c lhs;
        cb_u8 c.code o_dup;
        emit_ld c lhs.ty;
        gen_scalar g c rhs;
        gen_assign_op c bop lhs.ty;
        emit_st c lhs.ty
      end

let build_info (p : program) =
  let info =
    {
      Cg.structs = Hashtbl.create 16;
      Cg.enums = Hashtbl.create 16;
      Cg.layouts = [];
      Cg.elayouts = [];
      Cg.busy = [];
      Cg.funcs = Hashtbl.create 16;
      Cg.externs = Hashtbl.create 16;
      Cg.c_abi = Hashtbl.create 16;
    }
  in
  List.iter (fun (s : struct_def) -> Hashtbl.replace info.Cg.structs s.sname s.sfields) p.structs;
  List.iter (fun (e : enum_def) -> Hashtbl.replace info.Cg.enums e.ename e.evariants) p.enums;
  List.iter
    (fun (e : extern_fn) ->
      Hashtbl.replace info.Cg.externs e.ename ();
      Hashtbl.replace info.Cg.funcs e.ename (e.eparams, e.eret, e.evariadic))
    p.externs;
  List.iter
    (fun (f : fn_def) ->
      if f.fc_c_abi then Hashtbl.replace info.Cg.c_abi f.fname ();
      Hashtbl.replace info.Cg.funcs f.fname (List.map snd f.fparams, f.fret, false))
    p.fns;
  info

let compile ~unchecked (p : program) : string =
  let info = build_info p in
  let names = Hashtbl.create 64 in
  let fns = ref [] in
  List.iter
    (fun (f : fn_def) ->
      Hashtbl.replace names f.fname (List.length !fns);
      fns := `Fn f :: !fns)
    p.fns;
  List.iter
    (fun (e : extern_fn) ->
      Hashtbl.replace names e.ename (List.length !fns);
      fns := `Ext e :: !fns)
    p.externs;
  let entries = Array.of_list (List.rev !fns) in
  let fentries =
    Array.map
      (function
        | `Fn f ->
            {
              fe_name = f.fname;
              fe_kind = 0;
              fe_sret = is_agg f.fret;
              fe_params = List.length f.fparams;
              fe_frame = 0;
              fe_code = cb_create ();
            }
        | `Ext e ->
            {
              fe_name = e.ename;
              fe_kind = 1;
              fe_sret = is_agg e.eret;
              fe_params = List.length e.eparams;
              fe_frame = 0;
              fe_code = cb_create ();
            })
      entries
  in
  let g =
    {
      info;
      strs = Hashtbl.create 64;
      strtab = [];
      fnames = names;
      fentries;
      rets = Hashtbl.create 16;
      async = Hashtbl.create 16;
      consts = Hashtbl.create 16;
      unchecked;
      cguard = [];
    }
  in
  List.iter
    (fun (f : fn_def) ->
      Hashtbl.replace g.rets f.fname f.fret;
      Hashtbl.replace g.async f.fname f.fasync)
    p.fns;
  List.iter (fun (c : const_def) -> Hashtbl.replace g.consts c.cname c.cvalue) p.consts;
  List.iter
    (fun (f : fn_def) ->
      let c =
        {
            code = cb_create ();
            labels = Hashtbl.create 16;
            patches = [];
            nlabel = 0;
            next_off = 0;
            tmp_off = 0;
            max_off = 0;
            scopes = [];
            loops = [];
            sret_slot = -1;
          }
        in
        push_scope c;
        if is_agg f.fret then begin
          c.sret_slot <- alloc c 8;
          c.tmp_off <- c.next_off
        end;
        let homes =
          List.map
            (fun (name, ty) ->
              if is_agg ty then
                let slot = alloc c 8 in
                let home = alloc c (max 1 (size g ty)) in
                (name, ty, slot, home)
              else
                let off = alloc c (max 8 (size g ty)) in
                (name, ty, off, off))
            f.fparams
        in
        c.tmp_off <- c.next_off;
        List.iter
          (fun (_, ty, slot, _) -> emit_stl c slot (if is_agg ty then TPtr TU8 else ty))
          (List.rev homes);
        if c.sret_slot >= 0 then emit_stl c c.sret_slot TI64;
        List.iter
          (fun (_, ty, slot, home) ->
            if is_agg ty then begin
              emit_ldl c slot (TPtr TU8);
              cb_u8 c.code o_lea;
              cb_u32 c.code home;
              cb_u8 c.code o_copy;
              cb_u32 c.code (max 1 (size g ty))
            end)
          homes;
        List.iter (fun (name, ty, _, home) -> bind c name home ty) homes;
        List.iter (gen_stmt g c) f.fbody;
        push_small c 0;
        cb_u8 c.code o_ret;
        List.iter (fun (at, lbl) -> match Hashtbl.find_opt c.labels lbl with Some p -> cb_patch c.code at p | None -> fail "internal: unplaced label") (List.rev c.patches);
        pop_scope c;
        let fe = fentries.(fn_index g f.fname) in
        fe.fe_code <- c.code;
        fe.fe_frame <- align_up c.max_off 16)
    p.fns;
  let nstr = List.length g.strtab in
  let strarr = Array.make (max 1 nstr) "" in
  List.iteri (fun i s -> strarr.(nstr - 1 - i) <- s) g.strtab;
  let out = Buffer.create 65536 in
  Buffer.add_string out "RVMB";
  let put32 v = Buffer.add_int32_le out (Int32.of_int v) in
  put32 1;
  put32 nstr;
  Array.iter
    (fun s ->
      put32 (String.length s);
      Buffer.add_string out s)
    (if nstr = 0 then [||] else strarr);
  put32 (Array.length fentries);
  Array.iter
    (fun fe ->
      Buffer.add_char out (Char.chr fe.fe_kind);
      Buffer.add_char out (if fe.fe_sret then '\001' else '\000');
      put32 fe.fe_params;
      put32 fe.fe_frame;
      put32 fe.fe_code.len;
      put32 (String.length fe.fe_name);
      Buffer.add_string out fe.fe_name;
      Buffer.add_subbytes out fe.fe_code.data 0 fe.fe_code.len)
    fentries;
  let entry = try fn_index g "main" with Error _ -> -1 in
  if entry < 0 then fail "no 'main' function";
  put32 entry;
  Buffer.contents out

open Ast

module X = X64

exception Error of string

let fail fmt = Printf.ksprintf (fun s -> raise (Error s)) fmt
let align_up v a = if a <= 1 then v else (v + a - 1) / a * a

type layout = { lsize : int; lalign : int; lfields : (string * int) list }
type elayout = { esize : int; evars : (string * int list) list }
type tlayout = { tsize : int; talign : int; toffs : int list }

type info = {
  structs : (string, (string * typ) list) Hashtbl.t;
  enums : (string, variant list) Hashtbl.t;
  mutable layouts : (string * layout) list;
  mutable elayouts : (string * elayout) list;
  mutable busy : string list;
  funcs : (string, typ list * typ * bool) Hashtbl.t;
  externs : (string, unit) Hashtbl.t;
  c_abi : (string, unit) Hashtbl.t;
}

let rec peel (t : typ) =
  match t with TRef (u, _) -> peel u | TBox u -> peel u | t -> t

let rec size_of info t =
  match t with
  | TI8 | TU8 | TBool -> 1
  | TI16 | TU16 -> 2
  | TI32 | TU32 | TF32 -> 4
  | TI64 | TU64 | TF64 | TPtr _ | TRef _ | TBox _ | TFn _ | TFnC _ | TTask _ -> 8
  | TArray (e, n) -> size_of info e * n
  | TStruct s -> (layout_of info s).lsize
  | TEnum s -> (enum_layout_of info s).esize
  | TTuple ts -> (tuple_layout info ts).tsize
  | TVar v -> fail "type parameter '%s' reached the code generator; it was never instantiated" v
  | TVoid | TErr | TInfer -> 0

and align_of info t =
  match t with
  | TArray (e, _) -> align_of info e
  | TStruct s -> (layout_of info s).lalign
  | TEnum _ -> 8
  | TTuple ts -> (tuple_layout info ts).talign
  | TVoid | TErr | TInfer -> 1
  | _ -> max 1 (size_of info t)

and tuple_layout info ts =
  let pos = ref 0 and al = ref 1 in
  let offs =
    List.map
      (fun t ->
        let a = align_of info t in
        if a > !al then al := a;
        let o = align_up !pos a in
        pos := o + size_of info t;
        o)
      ts
  in
  { tsize = align_up !pos !al; talign = !al; toffs = offs }

and layout_of info s =
  match List.assoc_opt s info.layouts with
  | Some l -> l
  | None ->
      if List.mem s info.busy then fail "struct '%s' contains itself" s;
      let fields =
        match Hashtbl.find_opt info.structs s with
        | Some f -> f
        | None -> fail "unknown struct '%s'" s
      in
      info.busy <- s :: info.busy;
      let pos = ref 0 and al = ref 1 in
      let fs =
        List.map
          (fun (n, t) ->
            let a = align_of info t in
            if a > !al then al := a;
            let o = align_up !pos a in
            pos := o + size_of info t;
            (n, o))
          fields
      in
      info.busy <- List.tl info.busy;
      let l = { lsize = align_up !pos !al; lalign = !al; lfields = fs } in
      info.layouts <- (s, l) :: info.layouts;
      l

and enum_layout_of info s =
  match List.assoc_opt s info.elayouts with
  | Some l -> l
  | None ->
      if List.mem s info.busy then fail "enum '%s' contains itself" s;
      let variants =
        match Hashtbl.find_opt info.enums s with
        | Some v -> v
        | None -> fail "unknown enum '%s'" s
      in
      info.busy <- s :: info.busy;
      let top = ref 8 and al = ref 8 in
      let evars =
        List.map
          (fun v ->
            let pos = ref 8 in
            let offs =
              List.map
                (fun t ->
                  let a = align_of info t in
                  if a > !al then al := a;
                  let o = align_up !pos a in
                  pos := o + size_of info t;
                  o)
                v.vpayload
            in
            if !pos > !top then top := !pos;
            (v.vname, offs))
          variants
      in
      info.busy <- List.tl info.busy;
      let l = { esize = align_up !top !al; evars } in
      info.elayouts <- (s, l) :: info.elayouts;
      l

let is_struct_t = function TStruct _ -> true | _ -> false
let is_agg t = is_struct_t t || is_array t || is_enum t || is_tuple t

type g = {
  x : X.code;
  tgt : Target.t;
  info : info;
  mutable perm : int;
  mutable tmp : int;
  mutable low : int;
  mutable out : int;
  mutable scopes : (string, int * typ) Hashtbl.t list;
  mutable drop_scopes : (string * int) list list;
  mutable loop_drops : int list;
  mutable next_lbl : int;
  lbls : (int, int) Hashtbl.t;
  mutable patches : (int * int) list;
  strs : (string, int) Hashtbl.t;
  strbuf : Buffer.t;
  mutable data_refs : (int * int) list;
  mutable ext_refs : (int * string) list;
  mutable calls : (int * string) list;
  mutable fn_addrs : (int * string) list;
  fns : (string, int) Hashtbl.t;
  mutable loops : (int * int) list;
  mutable ret_lbl : int;
  mutable sret_slot : int;
  mutable cur_ret : typ;
  mutable async_ret : (int * int) option;
  mutable fix : (int * int) list;
  mutable skips : (int * int) list;
  acache : (string, int) Hashtbl.t;

  unchecked : unit ESet.t;
}

let gpr g = Target.int_regs g.tgt

let new_lbl g =
  g.next_lbl <- g.next_lbl + 1;
  g.next_lbl

let place g lbl = Hashtbl.replace g.lbls lbl (X.pos g.x)
let jmp_to g lbl = X.jmp g.x; g.patches <- (X.pos g.x - 4, lbl) :: g.patches

let jcc_to g cc lbl =
  X.jcc g.x cc;
  g.patches <- (X.pos g.x - 4, lbl) :: g.patches

let take g n =
  let n = max 8 (align_up n 8) in
  g.perm <- g.perm - n;
  if g.perm < g.low then g.low <- g.perm;
  g.perm

let scratch g n =
  let n = max 8 (align_up n 8) in
  g.tmp <- g.tmp - n;
  if g.tmp < g.low then g.low <- g.tmp;
  g.tmp

let emit_copy g n =
  if n > 0 then
    if n <= 64 then begin
      let k = n / 8 and r = n mod 8 in
      for i = 0 to k - 1 do
        X.load64 g.x X.rax X.rsi (i * 8);
        X.store64 g.x X.rax X.rdi (i * 8)
      done;
      for i = 0 to r - 1 do
        X.load8 g.x X.rax X.rsi ((k * 8) + i);
        X.store8 g.x X.rax X.rdi ((k * 8) + i)
      done
    end
    else begin
      X.mov_ri32 g.x X.rcx n;
      X.rep_movsb g.x
    end

let lookup g n =
  let rec go = function
    | [] -> None
    | s :: rest -> (
        match Hashtbl.find_opt s n with Some v -> Some v | None -> go rest)
  in
  go g.scopes

let bind g n off ty =
  match g.scopes with
  | s :: _ -> Hashtbl.replace s n (off, ty)
  | [] -> fail "internal: no scope"

let push_scope g =
  g.scopes <- Hashtbl.create 8 :: g.scopes;
  g.drop_scopes <- [] :: g.drop_scopes

let free_slot g slot =
  X.load64 g.x (gpr g).(0) X.rbp slot;
  X.call_ind g.x;
  g.ext_refs <- (X.pos g.x - 4, "free") :: g.ext_refs

let drop_scope g scope = List.iter (fun (_, slot) -> free_slot g slot) scope

let drop_n g k =
  let rec go i = function
    | [] -> ()
    | s :: rest -> if i < k then (drop_scope g s; go (i + 1) rest)
  in
  go 0 g.drop_scopes

let drop_all_but g keep =
  List.iter
    (fun scope ->
      List.iter (fun (_, slot) -> if Some slot <> keep then free_slot g slot) scope)
    g.drop_scopes

let pop_scope g =
  (match g.drop_scopes with s :: _ -> drop_scope g s | [] -> ());
  (match g.scopes with _ :: t -> g.scopes <- t | [] -> ());
  match g.drop_scopes with _ :: t -> g.drop_scopes <- t | [] -> ()

let add_drop g name slot =
  match g.drop_scopes with
  | s :: rest -> g.drop_scopes <- ((name, slot) :: s) :: rest
  | [] -> g.drop_scopes <- [ [ (name, slot) ] ]

let load_at g t off =
  match t with
  | TF32 -> X.movss_load g.x 0 X.rbp off
  | TF64 -> X.movsd_load g.x 0 X.rbp off
  | TI8 -> X.movsx8_m g.x X.rax X.rbp off
  | TI16 -> X.movsx16_m g.x X.rax X.rbp off
  | TI32 -> X.movsxd_m g.x X.rax X.rbp off
  | TU8 | TBool -> X.movzx8_m g.x X.rax X.rbp off
  | TU16 -> X.movzx16_m g.x X.rax X.rbp off
  | TU32 -> X.load32 g.x X.rax X.rbp off
  | _ -> X.load64 g.x X.rax X.rbp off

let store_at g t off =
  match t with
  | TF32 -> X.movss_store g.x 0 X.rbp off
  | TF64 -> X.movsd_store g.x 0 X.rbp off
  | TI8 | TU8 | TBool -> X.store8 g.x X.rax X.rbp off
  | TI16 | TU16 -> X.store16 g.x X.rax X.rbp off
  | TI32 | TU32 -> X.store32 g.x X.rax X.rbp off
  | _ -> X.store64 g.x X.rax X.rbp off

let load_ind g base t disp =
  match t with
  | TF32 -> X.movss_load g.x 0 base disp
  | TF64 -> X.movsd_load g.x 0 base disp
  | TI8 -> X.movsx8_m g.x X.rax base disp
  | TI16 -> X.movsx16_m g.x X.rax base disp
  | TI32 -> X.movsxd_m g.x X.rax base disp
  | TU8 | TBool -> X.movzx8_m g.x X.rax base disp
  | TU16 -> X.movzx16_m g.x X.rax base disp
  | TU32 -> X.load32 g.x X.rax base disp
  | _ -> X.load64 g.x X.rax base disp

let store_ind g base t disp =
  match t with
  | TF32 -> X.movss_store g.x 0 base disp
  | TF64 -> X.movsd_store g.x 0 base disp
  | TI8 | TU8 | TBool -> X.store8 g.x X.rax base disp
  | TI16 | TU16 -> X.store16 g.x X.rax base disp
  | TI32 | TU32 -> X.store32 g.x X.rax base disp
  | _ -> X.store64 g.x X.rax base disp

let zero_slot g off n =
  if n > 0 then
    if n <= 64 then begin
      X.mov_ri32 g.x X.rax 0;
      for i = 0 to n - 1 do
        X.store8 g.x X.rax X.rbp (off + i)
      done
    end
    else begin
      X.mov_ri32 g.x X.rax 0;
      X.lea g.x X.rdi X.rbp off;
      X.mov_ri32 g.x X.rcx n;
      X.rep_stosb g.x
    end

let copy_rax_to g dst n =
  let s = scratch g 8 in
  X.store64 g.x X.rax X.rbp s;
  X.load64 g.x X.rsi X.rbp s;
  X.lea g.x X.rdi X.rbp dst;
  emit_copy g n

let copy_rax_to_ptr g slot n =
  let s = scratch g 8 in
  X.store64 g.x X.rax X.rbp s;
  X.load64 g.x X.rsi X.rbp s;
  X.load64 g.x X.rdi X.rbp slot;
  emit_copy g n

let rec struct_name = function
  | TStruct s -> s
  | TPtr (TStruct s) -> s
  | TRef (t, _) | TBox t -> struct_name t
  | t -> fail "field access on %s" (to_string t)

let field_off g base f =
  let rec peel = function
    | TRef (t, _) -> peel t
    | TBox t -> peel t
    | TPtr t -> peel t
    | t -> t
  in
  match peel base.ty with
  | TTuple ts -> (
      match int_of_string_opt f with
      | Some i when i >= 0 && i < List.length ts ->
          List.nth (tuple_layout g.info ts).toffs i
      | _ -> fail "a tuple of %d element(s) has no element '%s'" (List.length ts) f)
  | t -> (
      let s = struct_name t in
      match List.assoc_opt f (layout_of g.info s).lfields with
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
  | Some variants -> (
      match List.find_opt (fun x -> x.vname = v) variants with
      | Some x -> x
      | None -> fail "enum '%s' has no variant '%s'" s v)

let variant_index g s v =
  let variants =
    match Hashtbl.find_opt g.info.enums s with
    | Some x -> x
    | None -> fail "unknown enum '%s'" s
  in
  let rec go i = function
    | [] -> fail "enum '%s' has no variant '%s'" s v
    | x :: rest -> if x.vname = v then i else go (i + 1) rest
  in
  go 0 variants

let variant_offs g s v =
  let l = enum_layout_of g.info s in
  match List.assoc_opt v l.evars with
  | Some o -> o
  | None -> fail "enum '%s' has no variant '%s'" s v

let int_regs = function
  | TI8 | TI16 | TI32 | TI64 | TU8 | TU16 | TU32 | TU64 | TBool | TPtr _ | TRef _ | TBox _ ->
      true
  | _ -> false

let norm_int g t =
  match t with
  | TI8 -> X.movsx8 g.x X.rax X.rax
  | TI16 -> X.movsx16 g.x X.rax X.rax
  | TI32 -> X.movsxd g.x X.rax X.rax
  | TU8 -> X.movzx8 g.x X.rax X.rax
  | TU16 -> X.movzx16 g.x X.rax X.rax
  | TU32 -> X.mov_rr g.x X.rax X.rax
  | _ -> ()

let to_bool g =
  X.test_rr g.x X.rax X.rax;
  X.setcc g.x 5 X.rax;
  X.movzx8 g.x X.rax X.rax

let load_slot g dst t off =
  match t with
  | TF32 -> X.movss_load g.x 0 X.rbp off
  | TF64 -> X.movsd_load g.x 0 X.rbp off
  | TI8 -> X.movsx8_m g.x dst X.rbp off
  | TI16 -> X.movsx16_m g.x dst X.rbp off
  | TI32 -> X.movsxd_m g.x dst X.rbp off
  | TU8 | TBool -> X.movzx8_m g.x dst X.rbp off
  | TU16 -> X.movzx16_m g.x dst X.rbp off
  | TU32 -> X.load32 g.x dst X.rbp off
  | _ -> X.load64 g.x dst X.rbp off

let slot_of g (e : expr) =
  match e.node with
  | EVar n -> (
      match lookup g n with
      | Some (off, ty) when int_regs ty -> Some (off, ty)
      | _ -> None)
  | ECast (a, t) -> (
      match a.node with
      | EVar n -> (
          match lookup g n with
          | Some (off, sty)
            when int_regs sty && int_regs t && t <> TBool
                 && size_of g.info sty >= size_of g.info t ->
              Some (off, t)
          | _ -> None)
      | _ -> None)
  | _ -> None

let rec pure_e (e : expr) =
  match e.node with
  | ECall _ | ECallV _ | EAwait _ | EPoll _ | EBoxNew _ -> false
  | EBin (_, a, b) | EIndex (a, b) -> pure_e a && pure_e b
  | EUn (_, a) | ECast (a, _) | EField (a, _) | EDeref a | EAddr a | EAddrMut a -> pure_e a
  | _ -> true

let rec akey (e : expr) =
  match e.node with
  | EVar n -> Some ("v:" ^ n)
  | EInt k -> Some ("i:" ^ Int64.to_string k)
  | EBin (op, a, b) -> (
      match (akey a, akey b) with
      | Some x, Some y -> Some ("b:" ^ op ^ "(" ^ x ^ "," ^ y ^ ")")
      | _ -> None)
  | ECast (a, t) -> (
      match akey a with Some x -> Some ("c:" ^ to_string t ^ "(" ^ x ^ ")") | None -> None)
  | EIndex (a, b) -> (
      match (akey a, akey b) with
      | Some x, Some y -> Some ("x(" ^ x ^ "," ^ y ^ ")")
      | _ -> None)
  | EField (a, f) -> (match akey a with Some x -> Some ("f(" ^ x ^ "," ^ f ^ ")") | None -> None)
  | EDeref a -> (match akey a with Some x -> Some ("d(" ^ x ^ ")") | None -> None)
  | _ -> None

let is_cmp = function
  | "==" | "!=" | "<" | "<=" | ">" | ">=" -> true
  | _ -> false

let cmp_cc op uns =
  match op with
  | "==" -> 4
  | "!=" -> 5
  | "<" -> if uns then 2 else 12
  | "<=" -> if uns then 6 else 14
  | ">" -> if uns then 7 else 15
  | ">=" -> if uns then 3 else 13
  | _ -> fail "unknown comparison '%s'" op

let inv_cc = function
  | 4 -> 5
  | 5 -> 4
  | 12 -> 13
  | 13 -> 12
  | 14 -> 15
  | 15 -> 14
  | 2 -> 3
  | 3 -> 2
  | 6 -> 7
  | 7 -> 6
  | c -> c

let bool_of_cc g cc =
  X.setcc g.x cc X.rax;
  X.movzx8 g.x X.rax X.rax

let int_arith g op uns dst src =
  match op with
  | "+" -> X.add_rr g.x dst src
  | "-" -> X.sub_rr g.x dst src
  | "*" -> X.imul_rr g.x dst src
  | "/" ->
      if uns then begin
        X.mov_ri32 g.x X.rdx 0;
        X.div_rr g.x src
      end
      else begin
        X.cqo g.x;
        X.idiv_rr g.x src
      end
  | "%" ->
      if uns then begin
        X.mov_ri32 g.x X.rdx 0;
        X.div_rr g.x src
      end
      else begin
        X.cqo g.x;
        X.idiv_rr g.x src
      end;
      X.mov_rr64 g.x dst X.rdx
  | "&" -> X.and_rr g.x dst src
  | "|" -> X.or_rr g.x dst src
  | "^" -> X.xor_rr g.x dst src
  | "<<" -> X.shl_cl g.x dst
  | ">>" -> if uns then X.shr_cl g.x dst else X.sar_cl g.x dst
  | _ -> fail "unknown operator '%s'" op

let int_arith_imm g op uns dst ki =
  match op with
  | "+" -> X.add_ri g.x dst ki
  | "-" -> X.sub_ri g.x dst ki
  | "*" -> X.imul_ri g.x dst ki
  | "&" -> X.and_ri g.x dst ki
  | "|" -> X.or_ri g.x dst ki
  | "^" -> X.xor_ri g.x dst ki
  | "<<" -> X.shl_imm g.x dst (ki land 63)
  | ">>" -> if uns then X.shr_imm g.x dst (ki land 63) else X.sar_imm g.x dst (ki land 63)
  | _ -> fail "unknown operator '%s'" op

let fits32 k = Int64.compare k (-2147483648L) >= 0 && Int64.compare k 2147483647L <= 0

let str_off g s =
  match Hashtbl.find_opt g.strs s with
  | Some o -> o
  | None ->
      let o = Buffer.length g.strbuf in
      Buffer.add_string g.strbuf s;
      Buffer.add_char g.strbuf '\000';
      Hashtbl.replace g.strs s o;
      o

let unquote s =
  let n = String.length s in
  if n < 2 || s.[0] <> '"' then s
  else begin
    let buf = Buffer.create n in
    let i = ref 1 in
    let stop = n - 1 in
    let oct c = c >= '0' && c <= '7' in
    while !i < stop do
      if s.[!i] = '\\' && !i + 1 < stop then begin
        let c = s.[!i + 1] in
        if oct c && !i + 3 < stop && oct s.[!i + 2] && oct s.[!i + 3] then begin

          let v =
            ((Char.code c - 48) * 64)
            + ((Char.code s.[!i + 2] - 48) * 8)
            + (Char.code s.[!i + 3] - 48)
          in
          Buffer.add_char buf (Char.chr (v land 0xff));
          i := !i + 4
        end
        else begin
          (match c with
          | 'n' -> Buffer.add_char buf '\n'
          | 't' -> Buffer.add_char buf '\t'
          | 'r' -> Buffer.add_char buf '\r'
          | '0' -> Buffer.add_char buf '\000'
          | '\\' -> Buffer.add_char buf '\\'
          | '"' -> Buffer.add_char buf '"'
          | c -> Buffer.add_char buf c);
          i := !i + 2
        end
      end
      else begin
        Buffer.add_char buf s.[!i];
        incr i
      end
    done;
    Buffer.contents buf
  end

let const_index (e : expr) =
  match e.node with
  | EInt k when k >= 0L -> Some (Int64.to_int k)
  | _ -> None

let fn_addr_raw g n =
  X.lea_rip g.x X.rax;
  g.fn_addrs <- (X.pos g.x - 4, n) :: g.fn_addrs

let fn_addr g n =
  if not (Hashtbl.mem g.info.funcs n) then fail "unknown function '%s'" n;
  fn_addr_raw g n

let rec addr g (e : expr) =
  match e.node with
  | EIndex _ | EField _ -> (
      match akey e with
      | Some k -> (
          match Hashtbl.find_opt g.acache k with
          | Some slot -> X.load64 g.x X.rax X.rbp slot
          | None ->
              addr_raw g e;
              if pure_e e then begin
                let slot = scratch g 8 in
                X.store64 g.x X.rax X.rbp slot;
                Hashtbl.replace g.acache k slot
              end)
      | None -> addr_raw g e)
  | _ -> addr_raw g e

and addr_raw g (e : expr) =
  match e.node with
  | EVar n -> (
      match lookup g n with
      | Some (off, _) -> X.lea g.x X.rax X.rbp off
      | None -> fail "unknown variable '%s'" n)
  | EField (base, f) ->
      let off = field_off g base f in
      (match (base.ty, base.node) with
      | (TStruct _ | TTuple _), EVar n -> (
          match lookup g n with
          | Some (boff, _) -> X.lea g.x X.rax X.rbp (boff + off)
          | None -> fail "unknown variable '%s'" n)
      | TStruct _, _ | TTuple _, _ ->
          addr g base;
          if off <> 0 then X.lea g.x X.rax X.rax off
      | (TPtr _ | TRef _ | TBox _), EVar _ -> (
          value g base;
          if off <> 0 then X.lea g.x X.rax X.rax off)
      | (TPtr _ | TRef _ | TBox _), _ -> (
          value g base;
          if off <> 0 then X.lea g.x X.rax X.rax off)
      | t, _ -> fail "field access on %s" (to_string t))
  | EIndex (base, idx) -> (
      let bt = base.ty in
      let et =
        match peel bt with
        | TArray (t, _) -> t
        | TPtr t -> t
        | t -> fail "cannot index %s" (to_string t)
      in
      let bound = match peel bt with TArray (_, n) -> Some n | _ -> None in
      let esz = max 1 (size_of g.info et) in
      let pow2 = esz <= 8 && esz land (esz - 1) = 0 in
      let direct =
        if not (pow2 && pure_e idx) then None
        else
          match base.node with
          | EVar n when (match bt with TArray _ -> true | _ -> false) -> (
              match lookup g n with Some (boff, _) -> Some (`Arr boff) | None -> None)
          | EVar n
            when (match bt with TPtr _ | TRef _ | TBox _ -> true | _ -> false) -> (
              match lookup g n with Some (boff, _) -> Some (`Ptr boff) | None -> None)
          | _ -> None
      in
      let slot = match direct with Some _ -> 0 | None -> scratch g 8 in
      (match direct with
      | Some _ -> ()
      | None ->
          (match bt with
          | TArray _ -> addr g base
          | TPtr _ | TRef _ | TBox _ -> value g base
          | t -> fail "cannot index %s" (to_string t));
          X.store64 g.x X.rax X.rbp slot);
      value g idx;
      (match bound with
      | Some _ when ESet.mem g.unchecked e -> ()
      | Some n -> (
          match const_index idx with
          | Some k when k < n -> ()
          | _ ->
              X.mov_ri32 g.x X.rcx n;
              X.cmp_rr g.x X.rax X.rcx;
              let ok = new_lbl g in
              jcc_to g 2 ok;
              X.ud2 g.x;
              place g ok)
      | None -> ());
      match direct with
      | Some (`Arr boff) -> X.lea_s g.x X.rax X.rbp X.rax esz boff
      | Some (`Ptr boff) ->
          X.load64 g.x X.rcx X.rbp boff;
          X.lea_s g.x X.rax X.rcx X.rax esz 0
      | None ->
          if esz <> 1 then begin
            X.mov_ri32 g.x X.rcx esz;
            X.imul_rr g.x X.rax X.rcx
          end;
          X.load64 g.x X.rcx X.rbp slot;
          X.add_rr g.x X.rax X.rcx)
  | EDeref p -> value g p
  | EAddr a | EAddrMut a -> addr g a
  | EAwait a ->
      await_block g a;
      X.lea g.x X.rax X.rax 16
  | EStructLit (name, fields) -> struct_lit g name fields
  | EArrayLit items -> (
      match e.ty with
      | TArray _ -> array_lit g e.ty items
      | t -> fail "array literal typed %s" (to_string t))
  | EEnumLit (en, vn, args) ->
      let l = enum_layout_of g.info en in
      let offs = variant_offs g en vn in
      if List.length offs <> List.length args then
        fail "'%s::%s' carries %d value(s), given %d" en vn (List.length offs)
          (List.length args);
      let s = scratch g (max 1 l.esize) in
      zero_slot g s l.esize;
      X.mov_ri32 g.x X.rax (variant_index g en vn);
      X.store64 g.x X.rax X.rbp s;
      List.iter2
        (fun off (arg : expr) ->
          if is_agg arg.ty then begin
            addr g arg;
            copy_rax_to g (s + off) (max 1 (size_of g.info arg.ty))
          end
          else begin
            value g arg;
            store_at g arg.ty (s + off)
          end)
        offs args;
      X.lea g.x X.rax X.rbp s
  | EZero t when is_agg t ->
      let n = size_of g.info t in
      let s = scratch g (max 1 n) in
      zero_slot g s n;
      X.lea g.x X.rax X.rbp s
  | ETupleLit items -> (
      match e.ty with
      | TTuple ts when List.length ts = List.length items -> tuple_lit g ts items
      | t -> fail "tuple literal typed %s" (to_string t))
  | ECall (name, args) -> call g name args e.ty
  | ECallV (f, args) -> callv g f args e.ty
  | _ -> fail "this expression has no address"

and struct_lit g name fields =
  let l = layout_of g.info name in
  let s = scratch g (max 1 l.lsize) in
  zero_slot g s l.lsize;
  List.iter
    (fun (fname, v) ->
      let off =
        match List.assoc_opt fname l.lfields with
        | Some o -> o
        | None -> fail "struct '%s' has no field '%s'" name fname
      in
      let ft = field_ty g name fname in
      if is_agg ft then begin
        addr g v;
        copy_rax_to g (s + off) (size_of g.info ft)
      end
      else begin
        value g v;
        store_at g ft (s + off)
      end)
    fields;
  X.lea g.x X.rax X.rbp s

and tuple_lit g ts items =
  let l = tuple_layout g.info ts in
  let s = scratch g (max 1 l.tsize) in
  zero_slot g s l.tsize;
  List.iter2
    (fun off (v : expr) ->
      if is_agg v.ty then begin
        addr g v;
        copy_rax_to g (s + off) (max 1 (size_of g.info v.ty))
      end
      else begin
        value g v;
        store_at g v.ty (s + off)
      end)
    l.toffs items;
  X.lea g.x X.rax X.rbp s

and array_lit g ty items =  let et, n =
    match ty with TArray (t, n) -> (t, n) | _ -> fail "array literal without an array type"
  in
  let esz = max 1 (size_of g.info et) in
  let s = scratch g (max 1 (esz * n)) in
  zero_slot g s (esz * n);
  List.iteri
    (fun i it ->
      if i < n then
        if is_agg et then begin
          addr g it;
          copy_rax_to g (s + (i * esz)) esz
        end
        else begin
          value g it;
          store_at g et (s + (i * esz))
        end)
    items;
  X.lea g.x X.rax X.rbp s

and value g (e : expr) = if is_agg e.ty then addr g e else scalar g e

and scalar g (e : expr) =
  match e.node with
  | EInt n -> X.mov_ri g.x X.rax n
  | EFloat f ->
      let bits =
        if e.ty = TF32 then
          Int64.logand (Int64.of_int32 (Int32.bits_of_float f)) 0xFFFFFFFFL
        else Int64.bits_of_float f
      in
      X.mov_ri g.x X.rax bits;
      X.movq_xmm_gpr g.x 0 X.rax
  | EBool v -> X.mov_ri32 g.x X.rax (if v then 1 else 0)
  | ENull -> X.mov_ri32 g.x X.rax 0
  | EStr s ->
      let o = str_off g (unquote s) in
      X.lea_rip g.x X.rax;
      g.data_refs <- (X.pos g.x - 4, o) :: g.data_refs
  | ESizeof t -> X.mov_ri g.x X.rax (Int64.of_int (size_of g.info t))
  | EZero t -> (
      match t with
      | TF32 | TF64 -> X.pxor_rr g.x 0 0
      | _ -> X.mov_ri32 g.x X.rax 0)
  | EVar n -> (
      match lookup g n with
      | Some (off, ty) -> load_at g ty off
      | None -> fn_addr g n)
  | EFnRef n -> fn_addr g n
  | EPoll a -> poll_task g a
  | EAwait a ->
      await_block g a;
      load_ind g X.rax e.ty 16
  | EAddr a | EAddrMut a -> addr g a
  | EBoxNew payload -> box_new g payload
  | EField _ | EIndex _ | EDeref _ ->
      addr g e;
      load_ind g X.rax e.ty 0
  | EBin (op, a, b) -> binop g op a b
  | EUn (op, a) -> unop g op a e
  | ECast (a, t) -> cast g a t
  | ECall (name, args) -> call g name args e.ty
  | ECallV (f, args) -> callv g f args e.ty
  | EStructLit _ | EArrayLit _ | EEnumLit _ | ETupleLit _ ->
      fail "aggregate used as a scalar"

and box_new g payload =
  let n = max 1 (size_of g.info payload.ty) in
  let t = scratch g 8 in
  X.mov_ri32 g.x (gpr g).(0) n;
  X.call_ind g.x;
  g.ext_refs <- (X.pos g.x - 4, "malloc") :: g.ext_refs;
  X.store64 g.x X.rax X.rbp t;
  if is_agg payload.ty then begin
    let s = scratch g 8 in
    addr g payload;
    X.store64 g.x X.rax X.rbp s;
    X.load64 g.x X.rsi X.rbp s;
    X.load64 g.x X.rdi X.rbp t;
    emit_copy g n
  end
  else begin
    scalar g payload;
    X.load64 g.x X.rcx X.rbp t;
    store_ind g X.rcx payload.ty 0
  end;
  X.load64 g.x X.rax X.rbp t

and binop g op a b =
  match op with
  | "&&" ->
      let lfalse = new_lbl g in
      let lend = new_lbl g in
      scalar g a;
      X.test_rr g.x X.rax X.rax;
      jcc_to g 4 lfalse;
      scalar g b;
      jmp_to g lend;
      place g lfalse;
      X.mov_ri32 g.x X.rax 0;
      place g lend
  | "||" ->
      let ltrue = new_lbl g in
      let lend = new_lbl g in
      scalar g a;
      X.test_rr g.x X.rax X.rax;
      jcc_to g 5 ltrue;
      scalar g b;
      jmp_to g lend;
      place g ltrue;
      X.mov_ri32 g.x X.rax 1;
      place g lend
  | _ -> (
      let t = scratch g 8 in
      if is_float a.ty then begin
        let f32 = a.ty = TF32 in
        scalar g a;
        (if f32 then X.movss_store else X.movsd_store) g.x 0 X.rbp t;
        scalar g b;
        (if f32 then X.movss_rr else X.movsd_rr) g.x 1 0;
        (if f32 then X.movss_load else X.movsd_load) g.x 0 X.rbp t;
        match op with
        | "+" -> if f32 then X.addss_rr g.x 0 1 else X.addsd_rr g.x 0 1
        | "-" -> if f32 then X.subss_rr g.x 0 1 else X.subsd_rr g.x 0 1
        | "*" -> if f32 then X.mulss_rr g.x 0 1 else X.mulsd_rr g.x 0 1
        | "/" -> if f32 then X.divss_rr g.x 0 1 else X.divsd_rr g.x 0 1
        | "==" ->
            (if f32 then X.ucomiss_rr else X.ucomisd_rr) g.x 0 1;
            X.setcc g.x 4 X.rax;
            X.movzx8 g.x X.rax X.rax;
            X.setcc g.x 11 X.rcx;
            X.movzx8 g.x X.rcx X.rcx;
            X.and_rr g.x X.rax X.rcx
        | "!=" ->
            (if f32 then X.ucomiss_rr else X.ucomisd_rr) g.x 0 1;
            X.setcc g.x 4 X.rax;
            X.movzx8 g.x X.rax X.rax;
            X.setcc g.x 11 X.rcx;
            X.movzx8 g.x X.rcx X.rcx;
            X.and_rr g.x X.rax X.rcx;
            X.mov_ri32 g.x X.rcx 1;
            X.xor_rr g.x X.rax X.rcx
        | "<" ->
            (if f32 then X.ucomiss_rr else X.ucomisd_rr) g.x 1 0;
            X.setcc g.x 7 X.rax;
            X.movzx8 g.x X.rax X.rax
        | "<=" ->
            (if f32 then X.ucomiss_rr else X.ucomisd_rr) g.x 1 0;
            X.setcc g.x 3 X.rax;
            X.movzx8 g.x X.rax X.rax
        | ">" ->
            (if f32 then X.ucomiss_rr else X.ucomisd_rr) g.x 0 1;
            X.setcc g.x 7 X.rax;
            X.movzx8 g.x X.rax X.rax
        | ">=" ->
            (if f32 then X.ucomiss_rr else X.ucomisd_rr) g.x 0 1;
            X.setcc g.x 3 X.rax;
            X.movzx8 g.x X.rax X.rax
        | _ -> fail "operator '%s' does not apply to %s" op (to_string a.ty)
      end
      else begin
        let uns = not (is_signed a.ty) in
        let factor =
          match peel a.ty with TPtr et -> max 1 (size_of g.info et) | _ -> 1
        in
        let scaled k =
          if factor = 1 || not (op = "+" || op = "-") then k
          else Int64.mul k (Int64.of_int factor)
        in
        let imm_ok =
          match op with
          | "+" | "-" | "*" | "&" | "|" | "^" | "<<" | ">>" -> true
          | o -> is_cmp o
        in
        let done_with dst src = if is_cmp op then (X.cmp_rr g.x dst src; bool_of_cc g (cmp_cc op uns))
          else int_arith g op uns dst src in
        match b.node with
        | EInt k0 when imm_ok && fits32 (scaled k0) ->
            let ki = Int64.to_int (scaled k0) in
            scalar g a;
            if is_cmp op then begin
              X.cmp_ri g.x X.rax ki;
              bool_of_cc g (cmp_cc op uns)
            end
            else int_arith_imm g op uns X.rax ki
        | _ -> (
            match slot_of g b with
            | Some (off, bty) ->
                scalar g a;
                load_slot g X.rcx bty off;
                done_with X.rax X.rcx
            | None ->
                scalar g a;
                X.store64 g.x X.rax X.rbp t;
                scalar g b;
                X.mov_rr64 g.x X.rcx X.rax;
                X.load64 g.x X.rax X.rbp t;
                if factor <> 1 && (op = "+" || op = "-") then begin
                  X.mov_ri32 g.x X.rdx factor;
                  X.imul_rr g.x X.rcx X.rdx
                end;
                done_with X.rax X.rcx)
      end)

and unop g op a (e : expr) =
  match op with
  | "-" ->
      if is_float a.ty then begin
        let f32 = a.ty = TF32 in
        scalar g a;
        X.pxor_rr g.x 1 1;
        (if f32 then X.subss_rr else X.subsd_rr) g.x 1 0;
        (if f32 then X.movss_rr else X.movsd_rr) g.x 0 1
      end
      else begin
        scalar g a;
        X.neg_rr g.x X.rax
      end
  | "~" ->
      scalar g a;
      X.not_rr g.x X.rax
  | "!" ->
      scalar g a;
      to_bool g;
      X.mov_ri32 g.x X.rcx 1;
      X.xor_rr g.x X.rax X.rcx
  | _ -> fail "unknown unary operator '%s' (on %s)" op (to_string e.ty)

and cast g a t =
  let src = a.ty in
  scalar g a;
  match (src, t) with
  | TF32, TF64 -> X.cvtss2sd g.x 0 0
  | TF64, TF32 -> X.cvtsd2ss g.x 0 0
  | (TF32 | TF64), tt when int_regs tt ->
      (if src = TF32 then X.cvttss2si g.x X.rax 0 else X.cvttsd2si g.x X.rax 0);
      if t = TBool then to_bool g else norm_int g t
  | TU64, (TF32 | TF64) ->
      let lpos = new_lbl g in
      let lend = new_lbl g in
      X.test_rr g.x X.rax X.rax;
      jcc_to g 9 lpos;
      X.mov_rr64 g.x X.rcx X.rax;
      X.shr_imm g.x X.rcx 1;
      X.and_ri g.x X.rax 1;
      X.or_rr g.x X.rcx X.rax;
      X.cvtsi2sd g.x 0 X.rcx;
      X.addsd_rr g.x 0 0;
      jmp_to g lend;
      place g lpos;
      X.cvtsi2sd g.x 0 X.rax;
      place g lend;
      if t = TF32 then X.cvtsd2ss g.x 0 0
  | st, (TF32 | TF64) when int_regs st ->
      if t = TF32 then X.cvtsi2ss g.x 0 X.rax else X.cvtsi2sd g.x 0 X.rax
  | TBool, tt when int_regs tt -> norm_int g t
  | _, TBool -> to_bool g
  | st, tt when int_regs st && int_regs tt -> norm_int g t
  | _ -> ()

and call g name args ret_ty =
  match lookup g name with
  | Some (off, TFn _) ->
      let slot = scratch g 8 in
      X.load64 g.x X.rax X.rbp off;
      X.store64 g.x X.rax X.rbp slot;
      emit_call g args ret_ty false false (`Slot slot)
  | Some (off, TFnC _) ->
      let slot = scratch g 8 in
      X.load64 g.x X.rax X.rbp off;
      X.store64 g.x X.rax X.rbp slot;
      emit_call g args ret_ty false true (`Slot slot)
  | _ ->
      let variadic =
        match Hashtbl.find_opt g.info.funcs name with Some (_, _, v) -> v | None -> false
      in
      if Hashtbl.mem g.info.externs name then emit_call g args ret_ty variadic true (`Ext name)
      else emit_call g args ret_ty variadic (Hashtbl.mem g.info.c_abi name) (`Local name)

and callv g f args ret_ty =
  let slot = scratch g 8 in
  scalar g f;
  X.store64 g.x X.rax X.rbp slot;
  emit_call g args ret_ty false (is_c_fn f.ty) (`Slot slot)

and emit_call g args ret_ty variadic use_c tail =
  let sret = is_agg ret_ty in
  let res = if sret then scratch g (max 1 (size_of g.info ret_ty)) else 0 in
  let staged =
    let rec go acc = function
      | [] -> List.rev acc
      | a :: rest ->
          let t = scratch g 8 in
          let ty = if variadic && a.ty = TF32 then TF64 else a.ty in
          if is_agg a.ty then begin
            addr g a;
            X.store64 g.x X.rax X.rbp t
          end
          else if is_float a.ty then begin
            scalar g a;
            if ty = TF64 && a.ty = TF32 then X.cvtss2sd g.x 0 0;
            (if ty = TF32 then X.movss_store else X.movsd_store) g.x 0 X.rbp t
          end
          else begin
            scalar g a;
            X.store64 g.x X.rax X.rbp t
          end;
          go ((ty, t) :: acc) rest
    in
    go [] args
  in
  let nvec = ref 0 in
  let reserved = ref 0 in
  (if not use_c then
     let regs = [| X.rdi; X.rsi; X.r10; X.r11; X.r12; X.r13; X.r14; X.r15 |] in
     let ni = ref (if sret then 1 else 0) and nf = ref 0 and ns = ref 0 in
     let stack_arg ty t =
       let d = 8 * !ns in
       incr ns;
       if d + 8 > g.out then g.out <- d + 8;
       if is_float ty then begin
         (if ty = TF32 then X.movss_load else X.movsd_load) g.x 11 X.rbp t;
         (if ty = TF32 then X.movss_store else X.movsd_store) g.x 11 X.rsp d
       end
       else begin
         X.load64 g.x X.rax X.rbp t;
         X.store64 g.x X.rax X.rsp d
       end
     in
     List.iter
       (fun (ty, t) ->
         if is_float ty then
           if !nf < 8 then begin
             (if ty = TF32 then X.movss_load else X.movsd_load) g.x !nf X.rbp t;
             incr nf
           end
           else stack_arg ty t
         else if !ni < 8 then begin
           X.load64 g.x regs.(!ni) X.rbp t;
           incr ni
         end
         else stack_arg ty t)
       staged;
     reserved := !nf
   else match g.tgt.Target.abi with
   | Target.Win64 ->
      let base = if sret then 1 else 0 in
      List.iteri
        (fun i (ty, t) ->
          let p = i + base in
          if p < 4 then begin
             if is_float ty then begin
               (if ty = TF32 then X.movss_load else X.movsd_load) g.x p X.rbp t;
               incr nvec;
               if variadic then X.load64 g.x (gpr g).(p) X.rbp t
             end
             else X.load64 g.x (gpr g).(p) X.rbp t
           end
           else begin
             let d = 32 + (8 * (p - 4)) in
             if d + 8 > g.out then g.out <- d + 8;
             if is_float ty then begin
               (if ty = TF32 then X.movss_load else X.movsd_load) g.x 4 X.rbp t;
               (if ty = TF32 then X.movss_store else X.movsd_store) g.x 4 X.rsp d
             end
             else begin
               X.load64 g.x X.rax X.rbp t;
               X.store64 g.x X.rax X.rsp d
             end
           end)
        staged
   | Target.SysV ->
      let ni = ref (if sret then 1 else 0) and nf = ref 0 and ns = ref 0 in
      let stack_arg ty t =
        let d = 8 * !ns in
        incr ns;
        if d + 8 > g.out then g.out <- d + 8;
        if is_float ty then begin
          (if ty = TF32 then X.movss_load else X.movsd_load) g.x 11 X.rbp t;
          (if ty = TF32 then X.movss_store else X.movsd_store) g.x 11 X.rsp d
        end
        else begin
          X.load64 g.x X.rax X.rbp t;
          X.store64 g.x X.rax X.rsp d
        end
      in
      List.iter
        (fun (ty, t) ->
          if is_float ty then
            if !nf < 8 then begin
              (if ty = TF32 then X.movss_load else X.movsd_load) g.x !nf X.rbp t;
              incr nf
            end
            else stack_arg ty t
          else if !ni < 6 then begin
            X.load64 g.x (gpr g).(!ni) X.rbp t;
            incr ni
          end
          else stack_arg ty t)
        staged;
      reserved := !nf);
  if sret then
    (if use_c then X.lea g.x (Target.sret_reg g.tgt) X.rbp res
     else X.lea g.x X.rdi X.rbp res);
  (match tail with
  | `Ext name ->
      if variadic then
        X.mov_al_imm8 g.x (if g.tgt.Target.abi = Target.SysV then !reserved else !nvec);
      X.call_ind g.x;
      g.ext_refs <- (X.pos g.x - 4, name) :: g.ext_refs
  | `Local name ->
      X.call_rel g.x;
      g.calls <- (X.pos g.x - 4, name) :: g.calls
  | `Slot off ->
      X.load64 g.x X.rax X.rbp off;
      X.call_reg g.x X.rax);
  if sret then X.lea g.x X.rax X.rbp res

and task_ptr g a =
  let t = scratch g 8 in
  scalar g a;
  X.store64 g.x X.rax X.rbp t;
  let p = scratch g 8 in
  X.load64 g.x X.rax X.rbp t;
  X.load64 g.x X.rax X.rax 8;
  X.store64 g.x X.rax X.rbp p;
  (t, p)

and poll_task g a =
  let t, p = task_ptr g a in
  push_scope g;
  bind g "$task" t (TTask TVoid);
  emit_call g [ { node = EVar "$task"; ty = TTask TVoid } ] TI64 false false (`Slot p);
  pop_scope g

and await_block g a =
  let t, p = task_ptr g a in
  push_scope g;
  bind g "$task" t (TTask TVoid);
  let lloop = new_lbl g in
  place g lloop;
  emit_call g [ { node = EVar "$task"; ty = TTask TVoid } ] TI64 false false (`Slot p);
  X.test_rr g.x X.rax X.rax;
  let ldone = new_lbl g in
  jcc_to g 5 ldone;
  jmp_to g lloop;
  place g ldone;
  pop_scope g;
  X.load64 g.x X.rax X.rbp t

and assign g op lhs rhs =
  match lhs.node with
  | EVar n -> (
      match lookup g n with
      | Some (off, ty) when int_regs ty ->
          if op = "=" then begin
            value g rhs;
            store_at g ty off
          end
          else begin
            let bop = String.sub op 0 (String.length op - 1) in
            load_at g ty off;
            compound_slot g bop ty off rhs
          end
      | _ -> assign_generic g op lhs rhs)
  | _ -> assign_generic g op lhs rhs

and compound_slot g bop ty off rhs =
  let uns = not (is_signed ty) in
  let imm_ok =
    match bop with
    | "+" | "-" | "*" | "&" | "|" | "^" | "<<" | ">>" -> true
    | _ -> false
  in
  (match rhs.node with
  | EInt k when imm_ok && fits32 k -> int_arith_imm g bop uns X.rax (Int64.to_int k)
  | _ -> (
      match slot_of g rhs with
      | Some (roff, rty) ->
          load_slot g X.rcx rty roff;
          int_arith g bop uns X.rax X.rcx
      | None ->
          let t = scratch g 8 in
          X.store64 g.x X.rax X.rbp t;
          scalar g rhs;
          X.mov_rr64 g.x X.rcx X.rax;
          X.load64 g.x X.rax X.rbp t;
          int_arith g bop uns X.rax X.rcx));
  store_at g ty off

and assign_generic g op lhs rhs =
  let a = scratch g 8 in
  addr g lhs;
  X.store64 g.x X.rax X.rbp a;
  if op = "=" then
    if is_agg lhs.ty then begin
      addr g rhs;
      copy_rax_to_ptr g a (size_of g.info lhs.ty)
    end
    else begin
      scalar g rhs;
      X.load64 g.x X.rcx X.rbp a;
      store_ind g X.rcx lhs.ty 0
    end
  else begin
    let bop = String.sub op 0 (String.length op - 1) in
    let t = scratch g 8 in
    let f32 = lhs.ty = TF32 in
    X.load64 g.x X.rcx X.rbp a;
    load_ind g X.rcx lhs.ty 0;
    if is_float lhs.ty then
      (if f32 then X.movss_store else X.movsd_store) g.x 0 X.rbp t
    else X.store64 g.x X.rax X.rbp t;
    scalar g rhs;
    if is_float lhs.ty then begin
      (if f32 then X.movss_rr else X.movsd_rr) g.x 1 0;
      (if f32 then X.movss_load else X.movsd_load) g.x 0 X.rbp t;
      match bop with
      | "+" -> if f32 then X.addss_rr g.x 0 1 else X.addsd_rr g.x 0 1
      | "-" -> if f32 then X.subss_rr g.x 0 1 else X.subsd_rr g.x 0 1
      | "*" -> if f32 then X.mulss_rr g.x 0 1 else X.mulsd_rr g.x 0 1
      | "/" -> if f32 then X.divss_rr g.x 0 1 else X.divsd_rr g.x 0 1
      | _ -> fail "'%s' does not apply to %s" bop (to_string lhs.ty)
    end
    else begin
      X.mov_rr64 g.x X.rcx X.rax;
      X.load64 g.x X.rax X.rbp t;
      int_arith g bop (not (is_signed lhs.ty)) X.rax X.rcx
    end;
    X.load64 g.x X.rcx X.rbp a;
    store_ind g X.rcx lhs.ty 0
  end

and cond_false g (c : expr) lbl =
  match c.node with
  | EBin (op, a, b) when is_cmp op && not (is_float a.ty) -> (
      let uns = not (is_signed a.ty) in
      let cc = inv_cc (cmp_cc op uns) in
      (match slot_of g b with
      | Some (off, bty) ->
          scalar g a;
          load_slot g X.rcx bty off;
          X.cmp_rr g.x X.rax X.rcx
      | None -> (
          match b.node with
          | EInt k when fits32 k ->
              scalar g a;
              X.cmp_ri g.x X.rax (Int64.to_int k)
          | _ ->
              let t = scratch g 8 in
              scalar g a;
              X.store64 g.x X.rax X.rbp t;
              scalar g b;
              X.mov_rr64 g.x X.rcx X.rax;
              X.load64 g.x X.rax X.rbp t;
              X.cmp_rr g.x X.rax X.rcx));
      jcc_to g cc lbl)
  | _ ->
      scalar g c;
      X.test_rr g.x X.rax X.rax;
      jcc_to g 4 lbl

and stmt g (s : stmt) =
  g.tmp <- g.perm;
  Hashtbl.reset g.acache;
  match s with
  | SLet (_, name, ty, init) ->
      let ty =
        if ty = TInfer then
          match init with
          | Some e -> e.ty
          | None -> fail "cannot infer a type for '%s'" name
        else ty
      in
      let n = max 1 (size_of g.info ty) in
      let off = take g n in
      g.tmp <- g.perm;
      (match init with
      | None -> if is_agg ty then zero_slot g off n
      | Some e ->
          if is_agg ty then begin
            addr g e;
            copy_rax_to g off n
          end
          else begin
            value g e;
            store_at g ty off
          end);
      bind g name off ty;
      if is_heap ty then add_drop g name off
  | SAssign (op, lhs, rhs) -> assign g op lhs rhs
  | SExpr e -> value g e
  | SBlock stmts ->
      push_scope g;
      List.iter (stmt g) stmts;
      pop_scope g
  | SUnsafe stmts ->
      push_scope g;
      List.iter (stmt g) stmts;
      pop_scope g
  | SIf (c, th, el) ->
      let lelse = new_lbl g in
      cond_false g c lelse;
      push_scope g;
      List.iter (stmt g) th;
      pop_scope g;
      if el = [] then place g lelse
      else begin
        let lend = new_lbl g in
        jmp_to g lend;
        place g lelse;
        push_scope g;
        List.iter (stmt g) el;
        pop_scope g;
        place g lend
      end
  | SWhile (c, b) ->
      let lstart = new_lbl g in
      let lend = new_lbl g in
      place g lstart;
      cond_false g c lend;
      g.loops <- (lend, lstart) :: g.loops;
      g.loop_drops <- List.length g.drop_scopes :: g.loop_drops;
      push_scope g;
      List.iter (stmt g) b;
      pop_scope g;
      g.loop_drops <- List.tl g.loop_drops;
      g.loops <- List.tl g.loops;
      jmp_to g lstart;
      place g lend
  | SLoop b ->
      let lstart = new_lbl g in
      let lend = new_lbl g in
      place g lstart;
      g.loops <- (lend, lstart) :: g.loops;
      g.loop_drops <- List.length g.drop_scopes :: g.loop_drops;
      push_scope g;
      List.iter (stmt g) b;
      pop_scope g;
      g.loop_drops <- List.tl g.loop_drops;
      g.loops <- List.tl g.loops;
      jmp_to g lstart;
      place g lend
  | SFor (v, lo, hi, body) ->
      let t =
        match peel lo.ty with
        | TErr | TVoid -> TI64
        | x when is_int x -> x
        | _ -> TI64
      in
      let slot = take g 8 in
      let lim = take g 8 in
      let lbody = new_lbl g in
      let lcont = new_lbl g in
      let lcond = new_lbl g in
      let lend = new_lbl g in
      g.tmp <- g.perm;
      scalar g lo;
      X.store64 g.x X.rax X.rbp slot;
      scalar g hi;
      X.store64 g.x X.rax X.rbp lim;
      jmp_to g lcond;
      g.loops <- (lend, lcont) :: g.loops;
      g.loop_drops <- List.length g.drop_scopes :: g.loop_drops;
      place g lbody;
      push_scope g;
      bind g v slot t;
      List.iter (stmt g) body;
      pop_scope g;
      g.loop_drops <- List.tl g.loop_drops;
      g.loops <- List.tl g.loops;
      place g lcont;
      X.load64 g.x X.rax X.rbp slot;
      X.mov_ri32 g.x X.rcx 1;
      X.add_rr g.x X.rax X.rcx;
      X.store64 g.x X.rax X.rbp slot;
      place g lcond;
      X.load64 g.x X.rax X.rbp slot;
      X.load64 g.x X.rcx X.rbp lim;
      X.cmp_rr g.x X.rax X.rcx;
      jcc_to g (if is_signed t then 12 else 2) lbody;
      place g lend
  | SMatch (scrut, arms) ->
      let n = max 8 (size_of g.info scrut.ty) in
      let slot = take g n in
      g.tmp <- g.perm;
      addr g scrut;
      copy_rax_to g slot n;
      let lend = new_lbl g in
      let labelled = List.map (fun arm -> (arm, new_lbl g)) arms in
      let wildcard = ref None in
      List.iter
        (fun (arm, lbl) ->
          match arm.apat with
          | PWild -> wildcard := Some lbl
          | PVariant (en, vn, _) ->
              X.load64 g.x X.rax X.rbp slot;
              X.mov_ri32 g.x X.rcx (variant_index g en vn);
              X.cmp_rr g.x X.rax X.rcx;
              jcc_to g 4 lbl)
        labelled;
      jmp_to g (match !wildcard with Some lbl -> lbl | None -> lend);
      List.iter
        (fun (arm, lbl) ->
          place g lbl;
          push_scope g;
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
                  let sz = max 1 (size_of g.info bt) in
                  let bslot = take g sz in
                  g.tmp <- g.perm;
                  if is_agg bt then begin
                    X.lea g.x X.rsi X.rbp (slot + off);
                    X.lea g.x X.rdi X.rbp bslot;
                    emit_copy g sz
                  end
                  else begin
                    load_at g bt (slot + off);
                    store_at g bt bslot
                  end;
                  bind g b bslot bt)
                binds
                (List.combine offs v.vpayload));
          List.iter (stmt g) arm.abody;
          pop_scope g;
          jmp_to g lend)
        labelled;
      place g lend
  | SBreak -> (
      match g.loops with
      | (brk, _) :: _ ->
          drop_n g (List.length g.drop_scopes - List.hd g.loop_drops);
          jmp_to g brk
      | [] -> fail "'break' outside a loop")
  | SContinue -> (
      match g.loops with
      | (_, cont) :: _ ->
          drop_n g (List.length g.drop_scopes - List.hd g.loop_drops);
          jmp_to g cont
      | [] -> fail "'continue' outside a loop")
  | SReturn None ->
      drop_all_but g None;
      (match g.async_ret with
      | None -> ()
      | Some (tp, _) ->
          X.mov_ri32 g.x X.rax 1;
          X.load64 g.x X.rcx X.rbp tp;
          X.store64 g.x X.rax X.rcx 0);
      jmp_to g g.ret_lbl
  | SReturn (Some e) ->
      let keep =
        match e.node with
        | EVar n -> ( match lookup g n with Some (off, _) -> Some off | None -> None)
        | _ -> None
      in
      (match g.async_ret with
      | Some (tp, roff) ->
          if is_agg e.ty then begin
            addr g e;
            X.mov_rr64 g.x X.rsi X.rax;
            X.load64 g.x X.rdi X.rbp tp;
            if roff <> 0 then X.lea g.x X.rdi X.rdi roff;
            emit_copy g (size_of g.info e.ty);
            drop_all_but g keep;
            X.mov_ri32 g.x X.rax 1;
            X.load64 g.x X.rcx X.rbp tp;
            X.store64 g.x X.rax X.rcx 0
          end
          else begin
            let t = scratch g 8 in
            let f32 = e.ty = TF32 in
            value g e;
            if is_float e.ty then
              (if f32 then X.movss_store else X.movsd_store) g.x 0 X.rbp t
            else X.store64 g.x X.rax X.rbp t;
            drop_all_but g keep;
            if is_float e.ty then
              (if f32 then X.movss_load else X.movsd_load) g.x 0 X.rbp t
            else X.load64 g.x X.rax X.rbp t;
            X.load64 g.x X.rcx X.rbp tp;
            if is_float e.ty then
              (if f32 then X.movss_store else X.movsd_store) g.x 0 X.rcx roff
            else store_ind g X.rcx e.ty roff;
            X.mov_ri32 g.x X.rax 1;
            X.store64 g.x X.rax X.rcx 0
          end
      | None ->
          if is_agg g.cur_ret then begin
            let n = size_of g.info g.cur_ret in
            let t = scratch g 8 in
            addr g e;
            X.store64 g.x X.rax X.rbp t;
            X.load64 g.x X.rsi X.rbp t;
            X.load64 g.x X.rdi X.rbp g.sret_slot;
            emit_copy g n;
            drop_all_but g keep;
            X.load64 g.x X.rax X.rbp g.sret_slot
          end
          else begin
            let t = scratch g 8 in
            let f32 = e.ty = TF32 in
            value g e;
            if is_float e.ty then
              (if f32 then X.movss_store else X.movsd_store) g.x 0 X.rbp t
            else X.store64 g.x X.rax X.rbp t;
            drop_all_but g keep;
            if is_float e.ty then
              (if f32 then X.movss_load else X.movsd_load) g.x 0 X.rbp t
            else X.load64 g.x X.rax X.rbp t
          end);
      jmp_to g g.ret_lbl

let open_fn g ~name ~ret =
  g.perm <- 0;
  g.tmp <- 0;
  g.low <- 0;
  g.out <- 0;
  g.scopes <- [];
  g.drop_scopes <- [];
  g.loop_drops <- [];
  g.loops <- [];
  g.sret_slot <- 0;
  g.async_ret <- None;
  g.cur_ret <- ret;
  while X.pos g.x mod 16 <> 0 do
    X.nop g.x
  done;
  Hashtbl.replace g.fns name (X.pos g.x);
  X.push g.x X.rbp;
  X.mov_rr64 g.x X.rbp X.rsp;
  let sub_at = X.pos g.x + 3 in
  X.sub_rsp_imm32 g.x 0;
  let probe_rel = X.pos g.x + 1 in
  X.jmp g.x;
  let skip_lbl = new_lbl g in
  X.mov_rr64 g.x X.rax X.rbp;
  place g skip_lbl;
  X.lea g.x X.rax X.rax (-4096);
  X.touch_rax g.x;
  X.cmp_rr g.x X.rax X.rsp;
  jcc_to g 7 skip_lbl;
  (sub_at, probe_rel, X.pos g.x)

let bind_params g ~ret (f : fn_def) =
  let sret = is_agg ret in
  let sret_slot = if sret then take g 8 else 0 in
  if sret then
    (if f.fc_c_abi then X.store64 g.x (Target.sret_reg g.tgt) X.rbp sret_slot
     else X.store64 g.x X.rdi X.rbp sret_slot);
  g.sret_slot <- sret_slot;
  let base = if sret then 1 else 0 in
  push_scope g;
  let homes =
    if not f.fc_c_abi then
      let regs = [| X.rdi; X.rsi; X.r10; X.r11; X.r12; X.r13; X.r14; X.r15 |] in
      let ni = ref base and nf = ref 0 and ns = ref 0 in
      List.map
        (fun (name, ty) ->
          let off = take g (max 8 (size_of g.info ty)) in
          if is_float ty then
            if !nf < 8 then begin
              (if ty = TF32 then X.movss_store else X.movsd_store) g.x !nf X.rbp off;
              incr nf
            end
            else begin
              let d = 16 + (8 * !ns) in
              incr ns;
              (if ty = TF32 then X.movss_load else X.movsd_load) g.x 11 X.rbp d;
              (if ty = TF32 then X.movss_store else X.movsd_store) g.x 11 X.rbp off
            end
          else if !ni < 8 then begin
            X.store64 g.x regs.(!ni) X.rbp off;
            incr ni
          end
          else begin
            let d = 16 + (8 * !ns) in
            incr ns;
            X.load64 g.x X.rax X.rbp d;
            X.store64 g.x X.rax X.rbp off
          end;
          (name, ty, off))
        f.fparams
    else match g.tgt.Target.abi with
    | Target.Win64 ->
        let rec spill i = function
          | [] -> []
          | (name, ty) :: rest ->
              let p = i + base in
              let off = take g (max 8 (size_of g.info ty)) in
              if p < 4 then begin
                if is_float ty then
                  (if ty = TF32 then X.movss_store else X.movsd_store) g.x p X.rbp off
                else X.store64 g.x (gpr g).(p) X.rbp off
              end
              else begin
                let d = 48 + (8 * (p - 4)) in
                if is_float ty then begin
                  (if ty = TF32 then X.movss_load else X.movsd_load) g.x 4 X.rbp d;
                  (if ty = TF32 then X.movss_store else X.movsd_store) g.x 4 X.rbp off
                end
                else begin
                  X.load64 g.x X.rax X.rbp d;
                  X.store64 g.x X.rax X.rbp off
                end
              end;
              (name, ty, off) :: spill (i + 1) rest
        in
        spill 0 f.fparams
    | Target.SysV ->
        let ni = ref base and nf = ref 0 and ns = ref 0 in
        List.map
          (fun (name, ty) ->
            let off = take g (max 8 (size_of g.info ty)) in
            if is_float ty then
              if !nf < 8 then begin
                (if ty = TF32 then X.movss_store else X.movsd_store) g.x !nf X.rbp off;
                incr nf
              end
              else begin
                let d = 16 + (8 * !ns) in
                incr ns;
                (if ty = TF32 then X.movss_load else X.movsd_load) g.x 11 X.rbp d;
                (if ty = TF32 then X.movss_store else X.movsd_store) g.x 11 X.rbp off
              end
            else if !ni < 6 then begin
              X.store64 g.x (gpr g).(!ni) X.rbp off;
              incr ni
            end
            else begin
              let d = 16 + (8 * !ns) in
              incr ns;
              X.load64 g.x X.rax X.rbp d;
              X.store64 g.x X.rax X.rbp off
            end;
            (name, ty, off))
          f.fparams
  in
  List.iter
    (fun (name, ty, home) ->
      if is_agg ty then begin
        let n = size_of g.info ty in
        let off = take g n in
        X.load64 g.x X.rsi X.rbp home;
        X.lea g.x X.rdi X.rbp off;
        emit_copy g n;
        bind g name off ty
      end
      else bind g name home ty)
    homes;
  homes

let finish_fn g (sub_at, probe_rel, probe_end) pre =
  pre ();
  drop_all_but g None;
  place g g.ret_lbl;
  X.b g.x 0xC9;
  X.b g.x 0xC3;
  pop_scope g;
  let frame = align_up (Target.shadow g.tgt + (-g.low) + g.out) 16 in
  g.fix <- (sub_at, frame) :: g.fix;
  if frame <= 4096 then g.skips <- (probe_rel, probe_end - (probe_rel + 4)) :: g.skips

let gen_fn g (f : fn_def) =
  let probe = open_fn g ~name:f.fname ~ret:f.fret in
  ignore (bind_params g ~ret:f.fret f);
  g.ret_lbl <- new_lbl g;
  List.iter (stmt g) f.fbody;
  finish_fn g probe (fun () -> ())

let gen_async g (f : fn_def) =
  let result_off = 16 in
  let rsize = align_up (max 1 (size_of g.info f.fret)) 8 in
  let pos = ref (result_off + rsize) in
  let param_offs =
    List.map
      (fun (_, ty) ->
        let o = align_up !pos 8 in
        pos := o + align_up (max 1 (size_of g.info ty)) 8;
        o)
      f.fparams
  in
  let block_size = !pos in
  let poll_name = f.fname ^ "$poll" in
  let probe = open_fn g ~name:f.fname ~ret:(TTask f.fret) in
  let homes = bind_params g ~ret:(TTask f.fret) f in
  g.tmp <- g.perm;
  let blk = scratch g 8 in
  X.mov_ri32 g.x (gpr g).(0) block_size;
  X.call_ind g.x;
  g.ext_refs <- (X.pos g.x - 4, "malloc") :: g.ext_refs;
  X.store64 g.x X.rax X.rbp blk;
  X.mov_ri32 g.x X.rax 0;
  X.load64 g.x X.rcx X.rbp blk;
  X.store64 g.x X.rax X.rcx 0;
  fn_addr_raw g poll_name;
  X.load64 g.x X.rcx X.rbp blk;
  X.store64 g.x X.rax X.rcx 8;
  List.iter2
    (fun (_, ty, home) poff ->
      X.lea g.x X.rsi X.rbp home;
      X.load64 g.x X.rdi X.rbp blk;
      if poff <> 0 then X.lea g.x X.rdi X.rdi poff;
      emit_copy g (max 8 (size_of g.info ty)))
    homes param_offs;
  X.load64 g.x X.rax X.rbp blk;
  g.ret_lbl <- new_lbl g;
  jmp_to g g.ret_lbl;
  finish_fn g probe (fun () -> ());
  let probe = open_fn g ~name:poll_name ~ret:TI64 in
  push_scope g;
  let tp = take g 8 in
  X.store64 g.x X.rdi X.rbp tp;
  g.ret_lbl <- new_lbl g;
  X.load64 g.x X.rax X.rbp tp;
  X.load64 g.x X.rcx X.rax 0;
  X.test_rr g.x X.rcx X.rcx;
  jcc_to g 5 g.ret_lbl;
  List.iter2
    (fun (name, ty) poff ->
      let n = max 1 (size_of g.info ty) in
      let off = take g n in
      X.load64 g.x X.rcx X.rbp tp;
      X.lea g.x X.rsi X.rcx poff;
      X.lea g.x X.rdi X.rbp off;
      emit_copy g (align_up n 8);
      bind g name off ty)
    f.fparams param_offs;
  g.async_ret <- Some (tp, result_off);
  List.iter (stmt g) f.fbody;
  finish_fn g probe (fun () -> X.mov_ri32 g.x X.rax 1)

type image = {
  im_text : Bytes.t;
  im_rdata : Bytes.t;
  im_entry : int;
  im_ext : (int * string) list;
  im_data : (int * int) list;
  im_imports : (string * string) list;
}

let uniq l =
  let seen = Hashtbl.create 16 in
  List.filter
    (fun x ->
      if Hashtbl.mem seen x then false
      else begin
        Hashtbl.add seen x ();
        true
      end)
    l

let compile ~unchecked (tgt : Target.t) (p : program) : image =
  let info =
    {
      structs = Hashtbl.create 16;
      enums = Hashtbl.create 16;
      layouts = [];
      elayouts = [];
      busy = [];
      funcs = Hashtbl.create 16;
      externs = Hashtbl.create 16;
      c_abi = Hashtbl.create 16;
    }
  in
  List.iter
    (fun (s : struct_def) -> Hashtbl.replace info.structs s.sname s.sfields)
    p.structs;
  List.iter
    (fun (e : enum_def) -> Hashtbl.replace info.enums e.ename e.evariants)
    p.enums;
  List.iter
    (fun (e : extern_fn) ->
      Hashtbl.replace info.externs e.ename ();
      Hashtbl.replace info.funcs e.ename (e.eparams, e.eret, e.evariadic))
    p.externs;

  let lib_of_sym = Hashtbl.create 16 in
  List.iter
    (fun (e : extern_fn) -> Hashtbl.replace lib_of_sym e.ename e.elib)
    p.externs;
  List.iter
    (fun (f : fn_def) ->
      if f.fc_c_abi then Hashtbl.replace info.c_abi f.fname ();
      Hashtbl.replace info.funcs f.fname (List.map snd f.fparams, f.fret, false))
    p.fns;
  let g =
    {
      x = X.create ();
      tgt;
      info;
      perm = 0;
      tmp = 0;
      low = 0;
      out = 0;
      scopes = [];
      drop_scopes = [];
      loop_drops = [];
      next_lbl = 0;
      lbls = Hashtbl.create 64;
      patches = [];
      strs = Hashtbl.create 16;
      strbuf = Buffer.create 4096;
      data_refs = [];
      ext_refs = [];
      calls = [];
      fn_addrs = [];
      fns = Hashtbl.create 16;
      loops = [];
      ret_lbl = 0;
      sret_slot = 0;
      cur_ret = TVoid;
      async_ret = None;
      fix = [];
      skips = [];
      acache = Hashtbl.create 16;
      unchecked;
    }
  in
  List.iter (fun (f : fn_def) -> if f.fasync then gen_async g f else gen_fn g f) p.fns;
  let entry = X.pos g.x in
  (match tgt.Target.abi with
  | Target.Win64 ->
      X.and_rsp_imm8 g.x 0xF0;
      X.sub_rsp_imm32 g.x 32;
      X.call_rel g.x;
      g.calls <- (X.pos g.x - 4, "main") :: g.calls;
      X.mov_rr g.x X.rcx X.rax;
      X.call_ind g.x;
      g.ext_refs <- (X.pos g.x - 4, "ExitProcess") :: g.ext_refs;
      X.hlt g.x
  | Target.SysV ->
      X.and_rsp_imm8 g.x 0xF0;
      X.call_rel g.x;
      g.calls <- (X.pos g.x - 4, "main") :: g.calls;
      (match tgt.Target.fmt with
      | Target.MachO ->
          X.mov_rr g.x X.rdi X.rax;
          X.mov_ri32 g.x X.rax 0x2000001;
          X.syscall g.x
      | Target.Elf ->
          X.mov_rr g.x X.rdi X.rax;
          X.mov_ri32 g.x X.rax 231;
          X.syscall g.x
      | Target.Pe -> fail "windows target on the SysV abi");
      X.hlt g.x);
  let bytes = Bytes.of_string (X.raw g.x) in
  List.iter
    (fun (pos, lbl) ->
      X.patch32 bytes pos (Hashtbl.find g.lbls lbl - (pos + 4)))
    g.patches;
  List.iter (fun (pos, v) -> X.patch32 bytes pos v) g.fix;
  List.iter (fun (pos, v) -> X.patch32 bytes pos v) g.skips;
  List.iter
    (fun (pos, name) ->
      match Hashtbl.find_opt g.fns name with
      | Some tgt -> X.patch32 bytes pos (tgt - (pos + 4))
      | None -> fail "call to unknown function '%s'" name)
    g.calls;
  List.iter
    (fun (pos, name) ->
      match Hashtbl.find_opt g.fns name with
      | Some tgt -> X.patch32 bytes pos (tgt - (pos + 4))
      | None -> fail "address of unknown function '%s'" name)
    g.fn_addrs;
  let imports =
    List.map
      (fun n ->
        let lib = match Hashtbl.find_opt lib_of_sym n with Some l -> l | None -> None in
        (Target.lib_of ?lib g.tgt n, n))
      (uniq (List.rev_map snd g.ext_refs))
  in
  {
    im_text = bytes;
    im_rdata = Bytes.of_string (Buffer.contents g.strbuf);
    im_entry = entry;
    im_ext = g.ext_refs;
    im_data = g.data_refs;
    im_imports = imports;
  }

open Vm

let align_up v a = if a <= 1 then v else (v + a - 1) / a * a

let tag_heap = 0x4000000000000000L
let tag_fn = 0x2000000000000000L
let tag_mask = 0x7000000000000000L
let off_mask = 0x00000000FFFFFFFFL

let is_heap a = Int64.logand a tag_mask = tag_heap
let is_fn a = Int64.logand a tag_mask = tag_fn
let off_of a = Int64.to_int (Int64.logand a off_mask)

let fmem = ref (Bytes.create (1 lsl 20))
let fused = ref 0
let heap = ref (Bytes.create (1 lsl 16))
let hused = ref 0

let grow_f n =
  while n > Bytes.length !fmem do
    let d = Bytes.create (Bytes.length !fmem * 3 / 2) in
    Bytes.blit !fmem 0 d 0 !fused;
    fmem := d
  done

let alloc_frame n =
  let n = align_up n 16 in
  grow_f (!fused + n);
  let base = !fused in
  Bytes.fill !fmem base n '\000';
  fused := base + n;
  base

let grow_h n =
  while n > Bytes.length !heap do
    let d = Bytes.create (Bytes.length !heap * 3 / 2) in
    Bytes.blit !heap 0 d 0 !hused;
    heap := d
  done

let h_alloc n =
  let n = max 0 n in
  let total = align_up (n + 8) 8 in
  grow_h (!hused + total);
  let base = !hused in
  Bytes.set_int64_le !heap base (Int64.of_int n);
  Bytes.fill !heap (base + 8) n '\000';
  hused := base + total;
  Int64.logor tag_heap (Int64.of_int (base + 8))

let h_size a =
  let off = off_of a in
  if off < 8 || off > !hused then fail "bad heap pointer 0x%Lx" a;
  Int64.to_int (Bytes.get_int64_le !heap (off - 8))

let bget8 a i =
  if is_heap a then Bytes.get !heap (off_of a + i) else Bytes.get !fmem (Int64.to_int a + i)

let get8u a =
  if is_heap a then Char.code (Bytes.get !heap (off_of a))
  else Char.code (Bytes.get !fmem (Int64.to_int a))

let get8s a =
  let v = get8u a in
  if v >= 128 then v - 256 else v

let get16u a =
  let b = Int64.add a 1L in
  get8u a lor (get8u b lsl 8)

let get16s a =
  let v = get16u a in
  if v >= 32768 then v - 65536 else v

let get32u a =
  Int64.logand
    (if is_heap a then Int64.of_int32 (Bytes.get_int32_le !heap (off_of a))
     else Int64.of_int32 (Bytes.get_int32_le !fmem (Int64.to_int a)))
    0xFFFFFFFFL

let get32s a =
  if is_heap a then Int64.of_int32 (Bytes.get_int32_le !heap (off_of a))
  else Int64.of_int32 (Bytes.get_int32_le !fmem (Int64.to_int a))

let get64 a =
  if is_heap a then Bytes.get_int64_le !heap (off_of a)
  else Bytes.get_int64_le !fmem (Int64.to_int a)

let set8 a v =
  if is_heap a then Bytes.set !heap (off_of a) (Char.chr (Int64.to_int v land 255))
  else Bytes.set !fmem (Int64.to_int a) (Char.chr (Int64.to_int v land 255))

let set16 a v =
  let b = Int64.add a 1L in
  set8 a v;
  set8 b (Int64.shift_right_logical v 8)

let set32 a v =
  if is_heap a then Bytes.set_int32_le !heap (off_of a) (Int64.to_int32 v)
  else Bytes.set_int32_le !fmem (Int64.to_int a) (Int64.to_int32 v)

let set64 a v =
  if is_heap a then Bytes.set_int64_le !heap (off_of a) v
  else Bytes.set_int64_le !fmem (Int64.to_int a) v

let copy_bytes dst src n =
  if n > 0 then
    if is_heap dst = is_heap src then
      if is_heap dst then
        Bytes.blit !heap (off_of src) !heap (off_of dst) n
      else Bytes.blit !fmem (Int64.to_int src) !fmem (Int64.to_int dst) n
    else
      for i = 0 to n - 1 do
        Bytes.set
          (if is_heap dst then !heap else !fmem)
          ((if is_heap dst then off_of dst else Int64.to_int dst) + i)
          (bget8 src i)
      done

let zero_bytes dst n =
  for i = 0 to n - 1 do
    Bytes.set
      (if is_heap dst then !heap else !fmem)
      ((if is_heap dst then off_of dst else Int64.to_int dst) + i)
      '\000'
  done

let cstr a =
  if a = 0L then "(null)"
  else begin
    let b = Buffer.create 32 in
    let i = ref 0 in
    let stop = ref false in
    while not !stop do
      let ch = get8u (Int64.add a (Int64.of_int !i)) in
      if ch = 0 then stop := true
      else begin
        Buffer.add_char b (Char.chr ch);
        incr i;
        if !i > 1 lsl 28 then fail "string at 0x%Lx is not terminated" a
      end
    done;
    Buffer.contents b
  end

type fn = {
  f_name : string;
  f_kind : int;
  f_sret : bool;
  f_nparams : int;
  f_frame : int;
  f_ops : int array;
  f_imm : int64 array;
}

let fns : fn array ref = ref [||]
let strs : string array ref = ref [||]
let str_ptrs : int64 array ref = ref [||]
let entry = ref 0

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let decode_raw name code =
  let n = String.length code in
  let ops = Array.make (max 1 n) 0 in
  let starts = Hashtbl.create 256 in
  let jumps = ref [] in
  let imms = ref [] in
  let ni = ref 0 in
  let p = ref 0 and k = ref 0 in
  let u32 () =
    if !p + 4 > n then fail "bytecode overrun in '%s'" name;
    let v =
      Char.code (String.unsafe_get code !p)
      lor (Char.code (String.unsafe_get code (!p + 1)) lsl 8)
      lor (Char.code (String.unsafe_get code (!p + 2)) lsl 16)
      lor (Char.code (String.unsafe_get code (!p + 3)) lsl 24)
    in
    p := !p + 4;
    v
  in
  while !p < n do
    let at = !p in
    let op = Char.code (String.unsafe_get code at) in
    incr p;
    Hashtbl.replace starts at !k;
    ops.(!k) <- op;
    incr k;
    match op with
    | 4 ->
        let lo = u32 () in
        let hi = u32 () in
        imms := Int64.logor (Int64.of_int lo) (Int64.shift_left (Int64.of_int hi) 32) :: !imms;
        ops.(!k) <- !ni;
        incr ni;
        incr k
    | 76 | 77 | 78 ->
        let t = u32 () in
        jumps := (!k, t) :: !jumps;
        ops.(!k) <- t;
        incr k
    | 79 ->
        ops.(!k) <- u32 ();
        ops.(!k + 1) <- u32 ();
        k := !k + 2
    | 84 ->
        let idx = u32 () in
        let nargs = u32 () in
        ops.(!k) <- idx;
        ops.(!k + 1) <- nargs;
        ops.(!k + 2) <- u32 ();
        k := !k + 3;
        for _ = 1 to nargs do
          ops.(!k) <- u32 ();
          incr k
        done
    | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 81 | 82
    | 83 | 87 | 88 | 91 ->
        ops.(!k) <- u32 ();
        incr k
    | _ -> ()
  done;
  List.iter
    (fun (cell, t) ->
      match Hashtbl.find_opt starts t with
      | Some c -> ops.(cell) <- c
      | None -> fail "jump into the middle of an instruction in '%s'" name)
    !jumps;
  (Array.sub ops 0 !k, Array.of_list (List.rev !imms))

let f_addi_l = 92
let f_subi_l = 93
let f_cmpj_l = 94
let f_sext32 = 95
let f_lea_idx = 96
let f_lea_ld = 97
let f_lea_st = 98
let f_bin_i = 99
let f_sext32_l = 100
let f_inc_j = 101

let inst_len ops i =
  match Array.unsafe_get ops i with
  | 84 -> 4 + Array.unsafe_get ops (i + 2)
  | 79 -> 3
  | 97 | 98 -> 7
  | 101 -> 6
  | 99 -> 3
  | 100 -> 4
  | 4 | 76 | 77 | 78 | 81 | 82 | 83 | 87 | 88 | 91 -> 2
  | op when op >= 5 && op <= 20 -> 2
  | _ -> 1

let ldw = function 5 | 6 -> 8 | 7 | 8 -> 16 | 9 | 10 -> 32 | 11 -> 64 | _ -> 0
let stw = function 12 -> 8 | 13 -> 16 | 14 -> 32 | 15 -> 64 | _ -> 0

let fuse name ops imm =
  let n = Array.length ops in
  if Sys.getenv_opt "RSC_NOFUSE" <> None then ops else
  let cap = max 8 n in
  let o = Array.make cap 0 in
  let map = Array.make cap 0 in
  let tgt = Array.make cap false in
  let i = ref 0 in
  while !i < n do
    let op = Array.unsafe_get ops !i in
    if op = 76 || op = 77 || op = 78 then begin
      let t = Array.unsafe_get ops (!i + 1) in
      if t < 0 || t >= n then fail "jump out of range in '%s'" name;
      tgt.(t) <- true
    end;
    i := !i + inst_len ops !i
  done;
  let at k = Array.unsafe_get ops k in
  let free k = not tgt.(k) in
  let i = ref 0 and out = ref 0 in
  let fix = ref [] in
  while !i < n do
    let i0 = !i in
    let start = !out in
    let op = at i0 in
    let n0 = inst_len ops i0 in
    let done' = ref false in
    if i0 + 8 < n && op >= 5 && op <= 11 && at (i0 + 2) = 4
       && (at (i0 + 4) = 36 || at (i0 + 4) = 37)
       && at (i0 + 5) >= 12 && at (i0 + 5) <= 15
       && ldw op = stw (at (i0 + 5))
       && at (i0 + 1) = at (i0 + 6)
       && at (i0 + 7) = 76
       && free (i0 + 2) && free (i0 + 4) && free (i0 + 5) && free (i0 + 7)
    then begin
      o.(start) <- f_inc_j;
      o.(start + 1) <- op;
      o.(start + 2) <- at (i0 + 1);
      o.(start + 3) <- at (i0 + 3);
      o.(start + 4) <- (if at (i0 + 4) = 36 then 0 else 1);
      o.(start + 5) <- at (i0 + 8);
      fix := (start + 5, at (i0 + 8)) :: !fix;
      out := start + 6;
      i := i0 + 9;
      done' := true
    end;
    if (not !done') && i0 + 6 < n && op >= 5 && op <= 11 && at (i0 + 2) = 4
       && (at (i0 + 4) = 36 || at (i0 + 4) = 37)
       && at (i0 + 5) >= 12 && at (i0 + 5) <= 15
       && ldw op = stw (at (i0 + 5))
       && at (i0 + 1) = at (i0 + 6)
       && free (i0 + 2) && free (i0 + 4) && free (i0 + 5)
    then begin
      o.(start) <- (if at (i0 + 4) = 36 then f_addi_l else f_subi_l);
      o.(start + 1) <- op;
      o.(start + 2) <- at (i0 + 1);
      o.(start + 3) <- at (i0 + 3);
      out := start + 4;
      i := i0 + 7;
      done' := true
    end;
    if (not !done') && i0 + 5 < n && op = 4 && at (i0 + 2) = 46 && at (i0 + 3) = 4
       && at (i0 + 5) = 47
       && Array.unsafe_get imm (at (i0 + 1)) = 32L
       && Array.unsafe_get imm (at (i0 + 4)) = 32L
       && free (i0 + 2) && free (i0 + 3) && free (i0 + 5)
    then begin
      o.(start) <- f_sext32;
      out := start + 1;
      i := i0 + 6;
      done' := true
    end;
    if (not !done') && i0 + 7 < n && op >= 5 && op <= 11
       && at (i0 + 2) = 4 && at (i0 + 4) = 46 && at (i0 + 5) = 4 && at (i0 + 7) = 47
       && Array.unsafe_get imm (at (i0 + 3)) = 32L
       && Array.unsafe_get imm (at (i0 + 6)) = 32L
       && free (i0 + 2) && free (i0 + 4) && free (i0 + 5) && free (i0 + 7)
    then begin
      let add = i0 + 8 < n && at (i0 + 8) = 36 && free (i0 + 8) in
      o.(start) <- f_sext32_l;
      o.(start + 1) <- op;
      o.(start + 2) <- at (i0 + 1);
      o.(start + 3) <- (if add then 1 else 0);
      out := start + 4;
      i := (if add then i0 + 9 else i0 + 8);
      done' := true
    end;
    if (not !done') && i0 + 2 < n && op = 4 && at (i0 + 2) >= 36 && at (i0 + 2) <= 48
       && free (i0 + 2)
    then begin
      o.(start) <- f_bin_i;
      o.(start + 1) <- at (i0 + 2);
      o.(start + 2) <- at (i0 + 1);
      out := start + 3;
      i := i0 + 3;
      done' := true
    end;
    if (not !done') && i0 + 7 < n && op >= 5 && op <= 11 && at (i0 + 2) >= 5 && at (i0 + 2) <= 11
       && at (i0 + 4) = 4 && at (i0 + 6) = 38 && at (i0 + 7) = 36
       && free (i0 + 2) && free (i0 + 4) && free (i0 + 6) && free (i0 + 7)
    then begin
      let s = Array.unsafe_get imm (at (i0 + 5)) in
      let sh =
        if s = 1L then 0 else if s = 2L then 1 else if s = 4L then 2 else if s = 8L then 3 else -1
      in
      if sh >= 0 then begin
        let nx = i0 + 8 in
        let ext =
          if nx < n && free nx then
            let x = at nx in
            if x >= 21 && x <= 29 then 1 else if x >= 30 && x <= 35 then 2 else 0
          else 0
        in
        o.(start) <- (if ext = 1 then f_lea_ld else if ext = 2 then f_lea_st else f_lea_idx);
        o.(start + 1) <- op;
        o.(start + 2) <- at (i0 + 1);
        o.(start + 3) <- at (i0 + 2);
        o.(start + 4) <- at (i0 + 3);
        o.(start + 5) <- sh;
        if ext = 0 then begin
          out := start + 6;
          i := i0 + 8
        end
        else begin
          o.(start + 6) <- at nx;
          out := start + 7;
          i := nx + 1
        end;
        done' := true
      end
    end;
    if (not !done') && i0 + 6 < n && op >= 5 && op <= 11 && at (i0 + 2) = 4
       && at (i0 + 4) >= 54 && at (i0 + 4) <= 63 && at (i0 + 5) = 77
       && free (i0 + 2) && free (i0 + 4) && free (i0 + 5)
    then begin
      o.(start) <- f_cmpj_l;
      o.(start + 1) <- op;
      o.(start + 2) <- at (i0 + 1);
      o.(start + 3) <- at (i0 + 4);
      o.(start + 4) <- at (i0 + 3);
      o.(start + 5) <- at (i0 + 6);
      fix := (start + 5, at (i0 + 6)) :: !fix;
      out := start + 6;
      i := i0 + 7;
      done' := true
    end;
    if not !done' then begin
      for k = 0 to n0 - 1 do
        o.(!out + k) <- at (i0 + k)
      done;
      if op = 76 || op = 77 || op = 78 then fix := (!out + 1, at (i0 + 1)) :: !fix;
      map.(i0) <- !out;
      out := !out + n0;
      i := i0 + n0
    end
    else map.(i0) <- start
  done;
  List.iter
    (fun (cell, t) ->
      if t < 0 || t >= n then fail "jump out of range in '%s'" name;
      o.(cell) <- map.(t))
    !fix;
  Array.sub o 0 !out

let decode name code =
  let ops, imm = decode_raw name code in
  (fuse name ops imm, imm)

let load_image path =
  let img = try read_file path with Sys_error e -> fail "cannot read '%s': %s" path e in
  let n = String.length img in
  let p = ref 0 in
  let need k = if !p + k > n then fail "'%s' is not a VM image: truncated" path in
  let u8 () =
    need 1;
    let v = Char.code (String.unsafe_get img !p) in
    incr p;
    v
  in
  let u32 () =
    need 4;
    let v =
      Char.code (String.unsafe_get img !p)
      lor (Char.code (String.unsafe_get img (!p + 1)) lsl 8)
      lor (Char.code (String.unsafe_get img (!p + 2)) lsl 16)
      lor (Char.code (String.unsafe_get img (!p + 3)) lsl 24)
    in
    p := !p + 4;
    v
  in
  let str k =
    need k;
    let s = String.sub img !p k in
    p := !p + k;
    s
  in
  if n < 4 || String.sub img 0 4 <> "RVMB" then
    fail "'%s' is not a VM image: bad magic" path;
  p := 4;
  let ver = u32 () in
  if ver <> 1 then fail "'%s' is a version %d VM image; this rscvm reads version 1" path ver;
  let nstr = u32 () in
  let st = Array.make nstr "" in
  for i = 0 to nstr - 1 do
    st.(i) <- str (u32 ())
  done;
  let nfn = u32 () in
  let fns' =
    Array.make nfn
      { f_name = ""; f_kind = 0; f_sret = false; f_nparams = 0; f_frame = 0; f_ops = [||]; f_imm = [||] }
  in
  for i = 0 to nfn - 1 do
    let kind = u8 () in
    let sret = u8 () <> 0 in
    let nparams = u32 () in
    let frame = u32 () in
    let clen = u32 () in
    let name = str (u32 ()) in
    let code = str clen in
    let f_ops, f_imm = decode name code in
    fns'.(i) <-
      { f_name = name; f_kind = kind; f_sret = sret; f_nparams = nparams; f_frame = frame; f_ops; f_imm }
  done;
  let e = u32 () in
  if e < 0 || e >= nfn then fail "'%s' is not a VM image: bad entry point" path;
  fns := fns';
  strs := st;
  str_ptrs := Array.map (fun s -> h_alloc (String.length s + 1)) st;
  Array.iteri
    (fun i s ->
      for k = 0 to String.length s - 1 do
        set8 (Int64.add (!str_ptrs).(i) (Int64.of_int k)) (Int64.of_int (Char.code s.[k]))
      done;
      set8 (Int64.add (!str_ptrs).(i) (Int64.of_int (String.length s))) 0L)
    st;
  entry := e

let opcheck =
  [|
    o_pop; o_dup; o_swap; o_push; o_ldl8u; o_ldl8s;
    o_ldl16u; o_ldl16s; o_ldl32u; o_ldl32s; o_ldl64; o_stl8;
    o_stl16; o_stl32; o_stl64; o_ldlf32; o_stlf32; o_ldlf64;
    o_stlf64; o_lea; o_ld8u; o_ld8s; o_ld16u; o_ld16s;
    o_ld32u; o_ld32s; o_ld64; o_ldf32; o_ldf64; o_st8;
    o_st16; o_st32; o_st64; o_stf32; o_stf64; o_add;
    o_sub; o_mul; o_divs; o_divu; o_rems; o_remu;
    o_and; o_or; o_xor; o_shl; o_shrs; o_shru;
    o_fadd; o_fsub; o_fmul; o_fdiv; o_fneg; o_eq;
    o_ne; o_lts; o_les; o_gts; o_ges; o_ltu;
    o_leu; o_gtu; o_geu; o_feq; o_fne; o_flt;
    o_fle; o_fgt; o_fge; o_neg; o_not; o_itof;
    o_utof; o_ftoi; o_roundf32; o_jmp; o_jz; o_jnz;
    o_call; o_ret; o_callind; o_copy; o_zero; o_mkthunk;
    o_poll; o_await; o_str; o_fnref; o_malloc; o_free;
    o_bcheck;
  |]

let () =
  Array.iteri (fun i v -> if v <> i + 1 then fail "internal: opcode table %d is %d" (i + 1) v) opcheck

let fp = ref 0
let pc = ref 0
let cur_fn = ref 0
let cur_ops : int array ref = ref [||]
let cur_imm : int64 array ref = ref [||]

let where () =
  let i = !cur_fn in
  let j = !pc - 1 in
  let op = if j >= 0 && j < Array.length !cur_ops then Array.unsafe_get !cur_ops j else -1 in
  if i >= 0 && i < Array.length !fns then
    Printf.sprintf " in '%s' at word %d (op %d)" (!fns.(i)).f_name !pc op
  else ""

let underflow () =
  let a = max 0 (!pc - 12) and b = min (Array.length !cur_ops) (!pc + 12) in
  let sb = Buffer.create 64 in
  for i = a to b - 1 do
    Buffer.add_string sb (string_of_int (Array.unsafe_get !cur_ops i));
    Buffer.add_char sb ' '
  done;
  fail "stack underflow%s near [%d..%d]: %s" (where ()) a b (Buffer.contents sb)

let stack = ref (Array.make 65536 0L)
let sp = ref 0

let[@inline] push v =
  if !sp >= Array.length !stack then begin
    let d = Array.make (Array.length !stack * 3 / 2) 0L in
    Array.blit !stack 0 d 0 !sp;
    stack := d
  end;
  !stack.(!sp) <- v;
  incr sp

let[@inline] pop () =
  if !sp <= 0 then underflow ();
  decr sp;
  !stack.(!sp)

let[@inline] peek k =
  let i = !sp - 1 - k in
  if i < 0 then underflow ();
  !stack.(i)

type frame = { r_pc : int; r_base : int; r_fp : int; r_fsp : int; r_fn : int }

let frames = ref (Array.make 256 { r_pc = 0; r_base = 0; r_fp = 0; r_fsp = 0; r_fn = 0 })
let nf = ref 0

let grow_frames () =
  let d = Array.make (Array.length !frames * 2) (Array.get !frames 0) in
  Array.blit !frames 0 d 0 !nf;
  frames := d

let stl_of_ld = function 5 | 6 -> 12 | 7 | 8 -> 13 | 9 | 10 -> 14 | 11 -> 15 | _ -> 0

let load_l op off =
  let a = !fp + off in
  match op with
  | 5 -> Int64.of_int (Char.code (Bytes.unsafe_get !fmem a))
  | 6 ->
      let v = Char.code (Bytes.unsafe_get !fmem a) in
      Int64.of_int (if v >= 128 then v - 256 else v)
  | 7 -> Int64.of_int (Bytes.get_uint16_le !fmem a)
  | 8 -> Int64.of_int (Bytes.get_int16_le !fmem a)
  | 9 -> Int64.logand (Int64.of_int32 (Bytes.get_int32_le !fmem a)) 0xFFFFFFFFL
  | 10 -> Int64.of_int32 (Bytes.get_int32_le !fmem a)
  | _ -> Bytes.get_int64_le !fmem a

let store_l op off v =
  let a = !fp + off in
  match op with
  | 12 -> Bytes.unsafe_set !fmem a (Char.chr (Int64.to_int v land 255))
  | 13 -> Bytes.set_int16_le !fmem a (Int64.to_int v)
  | 14 -> Bytes.set_int32_le !fmem a (Int64.to_int32 v)
  | _ -> Bytes.set_int64_le !fmem a v

let[@inline] ldv op off =
  if op = 11 then Bytes.get_int64_le !fmem (!fp + off) else load_l op off

let[@inline] stv op off v =
  if op = 15 then Bytes.set_int64_le !fmem (!fp + off) v else store_l op off v

let ld_mem op a =
  match op with
  | 21 -> Int64.of_int (get8u a)
  | 22 -> Int64.of_int (get8s a)
  | 23 -> Int64.of_int (get16u a)
  | 24 -> Int64.of_int (get16s a)
  | 25 -> get32u a
  | 26 -> get32s a
  | 27 -> get64 a
  | 28 -> Int64.bits_of_float (Int32.float_of_bits (Int64.to_int32 (get32u a)))
  | _ -> get64 a

let st_mem op a v =
  match op with
  | 30 -> set8 a v
  | 31 -> set16 a v
  | 32 -> set32 a v
  | 33 -> set64 a v
  | 34 -> set32 a (Int64.of_int32 (Int32.bits_of_float (Int64.float_of_bits v)))
  | _ -> set64 a v

let int_binop bop a b =
  match bop with
  | 36 -> Int64.add a b
  | 37 -> Int64.sub a b
  | 38 -> Int64.mul a b
  | 39 -> if b = 0L then fail "division by zero" else Int64.div a b
  | 40 -> if b = 0L then fail "division by zero" else Int64.unsigned_div a b
  | 41 -> if b = 0L then fail "division by zero" else Int64.rem a b
  | 42 -> if b = 0L then fail "division by zero" else Int64.unsigned_rem a b
  | 43 -> Int64.logand a b
  | 44 -> Int64.logor a b
  | 45 -> Int64.logxor a b
  | 46 -> Int64.shift_left a (Int64.to_int b land 63)
  | 47 -> Int64.shift_right a (Int64.to_int b land 63)
  | 48 -> Int64.shift_right_logical a (Int64.to_int b land 63)
  | _ -> fail "internal: bad fused binop %d" bop

let cmp_rel rel a b =
  match rel with
  | 54 -> a = b
  | 55 -> a <> b
  | 56 -> Int64.compare a b < 0
  | 57 -> Int64.compare a b <= 0
  | 58 -> Int64.compare a b > 0
  | 59 -> Int64.compare a b >= 0
  | 60 -> Int64.unsigned_compare a b < 0
  | 61 -> Int64.unsigned_compare a b <= 0
  | 62 -> Int64.unsigned_compare a b > 0
  | 63 -> Int64.unsigned_compare a b >= 0
  | _ -> false

let unsigned_float v =
  if v >= 0L then Int64.to_float v
  else Int64.to_float (Int64.logand v 0x7FFFFFFFFFFFFFFFL) +. 9223372036854775808.0

let fmt_printf fmt args =
  let out = Buffer.create (String.length fmt + 32) in
  let n = String.length fmt in
  let ai = ref 0 in
  let next () =
    let v = if !ai < Array.length args then args.(!ai) else 0L in
    incr ai;
    v
  in
  let i = ref 0 in
  while !i < n do
    let c = fmt.[!i] in
    if c <> '%' then begin
      Buffer.add_char out c;
      incr i
    end
    else begin
      incr i;
      if !i >= n then Buffer.add_char out '%'
      else begin
        let flags = ref "" in
        let more = ref true in
        while !more && !i < n do
          match fmt.[!i] with
          | '-' | '+' | ' ' | '0' | '#' ->
              flags := !flags ^ String.make 1 fmt.[!i];
              incr i
          | _ -> more := false
        done;
        let width = ref 0 in
        if !i < n && fmt.[!i] = '*' then begin
          incr i;
          width := Int64.to_int (next ())
        end
        else
          while !i < n && fmt.[!i] >= '0' && fmt.[!i] <= '9' do
            width := (!width * 10) + Char.code fmt.[!i] - 48;
            incr i
          done;
        let prec = ref (-1) in
        if !i < n && fmt.[!i] = '.' then begin
          incr i;
          prec := 0;
          if !i < n && fmt.[!i] = '*' then begin
            incr i;
            prec := Int64.to_int (next ())
          end
          else
            while !i < n && fmt.[!i] >= '0' && fmt.[!i] <= '9' do
              prec := (!prec * 10) + Char.code fmt.[!i] - 48;
              incr i
            done
        end;
        while
          !i < n
          &&
          match fmt.[!i] with 'h' | 'l' | 'z' | 'j' | 't' | 'L' -> true | _ -> false
        do
          incr i
        done;
        let conv = if !i < n then fmt.[!i] else '?' in
        if !i < n then incr i;
        let f = !flags in
        let has ch = String.contains f ch in
        let body = ref "" and sign = ref "" and numeric = ref true in
        (match conv with
        | 'd' | 'i' ->
            let v = next () in
            let s = Int64.to_string v in
            if String.length s > 0 && s.[0] = '-' then begin
              sign := "-";
              body := String.sub s 1 (String.length s - 1)
            end
            else begin
              body := s;
              if has '+' then sign := "+" else if has ' ' then sign := " "
            end;
            if !prec >= 0 then begin
              if !prec = 0 && v = 0L then body := ""
              else if String.length !body < !prec then
                body := String.make (!prec - String.length !body) '0' ^ !body
            end
        | 'u' ->
            body := Printf.sprintf "%Lu" (next ());
            if !prec >= 0 then begin
              if !prec = 0 && !body = "0" then body := ""
              else if String.length !body < !prec then
                body := String.make (!prec - String.length !body) '0' ^ !body
            end
        | 'o' ->
            let v = next () in
            body := Printf.sprintf "%Lo" v;
            if has '#' && (!body = "" || !body.[0] <> '0') then body := "0" ^ !body;
            if !prec >= 0 && String.length !body < !prec then
              body := String.make (!prec - String.length !body) '0' ^ !body
        | 'x' | 'X' | 'p' ->
            let v = next () in
            body := Printf.sprintf "%Lx" v;
            if conv = 'X' then body := String.uppercase_ascii !body;
            let prefix = if conv = 'p' || has '#' then if conv = 'X' then "0X" else "0x" else "" in
            if prefix <> "" && !body <> "0" then begin
              sign := prefix;
              numeric := false
            end;
            if !prec >= 0 && String.length !body < !prec then
              body := String.make (!prec - String.length !body) '0' ^ !body
        | 'c' ->
            body := String.make 1 (Char.chr (Int64.to_int (next ()) land 255));
            numeric := false
        | 's' ->
            body := cstr (next ());
            if !prec >= 0 && String.length !body > !prec then
              body := String.sub !body 0 !prec;
            numeric := false
        | 'f' | 'F' | 'e' | 'E' | 'g' | 'G' ->
            let x = Int64.float_of_bits (next ()) in
            let p = if !prec >= 0 then !prec else 6 in
            let s = Printf.sprintf "%.*f" p x in
            let s =
              match conv with
              | 'e' -> Printf.sprintf "%.*e" p x
              | 'E' -> String.uppercase_ascii (Printf.sprintf "%.*e" p x)
              | 'g' -> Printf.sprintf "%.*g" (if p = 0 then 1 else p) x
              | 'G' -> String.uppercase_ascii (Printf.sprintf "%.*g" (if p = 0 then 1 else p) x)
              | 'F' -> String.uppercase_ascii s
              | _ -> s
            in
            if String.length s > 0 && s.[0] = '-' then begin
              sign := "-";
              body := String.sub s 1 (String.length s - 1)
            end
            else begin
              body := s;
              if has '+' then sign := "+" else if has ' ' then sign := " "
            end;
            numeric := true
        | '%' ->
            body := "%";
            numeric := false
        | _ ->
            body := "%" ^ String.make 1 conv;
            numeric := false);
        let len = String.length !sign + String.length !body in
        if !width <= len then begin
          Buffer.add_string out !sign;
          Buffer.add_string out !body
        end
        else begin
          let k = !width - len in
          if has '-' then begin
            Buffer.add_string out !sign;
            Buffer.add_string out !body;
            Buffer.add_string out (String.make k ' ')
          end
          else if has '0' && !numeric then begin
            Buffer.add_string out !sign;
            Buffer.add_string out (String.make k '0');
            Buffer.add_string out !body
          end
          else begin
            Buffer.add_string out (String.make k ' ');
            Buffer.add_string out !sign;
            Buffer.add_string out !body
          end
        end
      end
    end
  done;
  Buffer.contents out

let memcpy_bytes dst src n =
  for i = 0 to n - 1 do
    set8 (Int64.add dst (Int64.of_int i)) (Int64.of_int (get8u (Int64.add src (Int64.of_int i))))
  done

let call_builtin_raw name args =
  match name with
  | "printf" ->
      let fmt = cstr args.(0) in
      let rest = Array.sub args 1 (max 0 (Array.length args - 1)) in
      let s = fmt_printf fmt rest in
      output_string stdout s;
      Int64.of_int (String.length s)
  | "puts" ->
      output_string stdout (cstr args.(0));
      output_char stdout '\n';
      0L
  | "putchar" ->
      output_char stdout (Char.chr (Int64.to_int args.(0) land 255));
      args.(0)
  | "fflush" -> 0L
  | "exit" ->
      flush stdout;
      exit (Int64.to_int args.(0))
  | "malloc" -> h_alloc (Int64.to_int args.(0))
  | "calloc" ->
      let n = Int64.to_int args.(0) * Int64.to_int args.(1) in
      h_alloc (max 0 n)
  | "realloc" ->
      let p = args.(0) in
      let n = Int64.to_int args.(1) in
      if p = 0L then h_alloc n
      else begin
        let old = h_size p in
        let d = h_alloc n in
        copy_bytes d p (min old n);
        d
      end
  | "free" -> 0L
  | "memcpy" | "memmove" ->
      let d = args.(0) and s = args.(1) and n = Int64.to_int args.(2) in
      memcpy_bytes d s n;
      d
  | "memset" ->
      let d = args.(0) and c = args.(1) and n = Int64.to_int args.(2) in
      for i = 0 to n - 1 do
        set8 (Int64.add d (Int64.of_int i)) c
      done;
      d
  | "memcmp" ->
      let a = args.(0) and b = args.(1) and n = Int64.to_int args.(2) in
      let r = ref 0 in
      let i = ref 0 in
      while !r = 0 && !i < n do
        let x = get8u (Int64.add a (Int64.of_int !i)) in
        let y = get8u (Int64.add b (Int64.of_int !i)) in
        if x <> y then r := if x < y then -1 else 1;
        incr i
      done;
      Int64.of_int !r
  | "strlen" -> Int64.of_int (String.length (cstr args.(0)))
  | "strcmp" ->
      let a = cstr args.(0) and b = cstr args.(1) in
      Int64.of_int (compare a b)
  | "strncmp" ->
      let a = cstr args.(0) and b = cstr args.(1) and n = Int64.to_int args.(2) in
      let a = if String.length a > n then String.sub a 0 n else a in
      let b = if String.length b > n then String.sub b 0 n else b in
      Int64.of_int (compare a b)
  | "strcpy" ->
      let d = args.(0) in
      let s = cstr args.(1) in
      String.iteri (fun i c -> set8 (Int64.add d (Int64.of_int i)) (Int64.of_int (Char.code c))) s;
      set8 (Int64.add d (Int64.of_int (String.length s))) 0L;
      d
  | "GetTickCount64" | "mach_absolute_time" -> Int64.of_float (Sys.time () *. 1000.)
  | _ -> fail "extern '%s' is not available to the VM" name

let[@inline] nu32 () =
  let v = Array.unsafe_get !cur_ops !pc in
  incr pc;
  v

let ni64 () =
  let k = Array.unsafe_get !cur_ops !pc in
  incr pc;
  Array.unsafe_get !cur_imm k

let call_builtin name args =
  try call_builtin_raw name args with Division_by_zero -> fail "division by zero in '%s'" name

let rec exec depth =
  while !nf > depth do
    let ops = !cur_ops in
    let here = !pc in
    if here < 0 || here >= Array.length ops then
      fail "bytecode overrun in '%s'" (!fns.(!cur_fn)).f_name;
    let op = Array.unsafe_get ops here in
    pc := here + 1;
    match op with
  | 1 -> ignore (pop ())
  | 2 -> push (peek 0)
  | 3 ->
      let a = pop () in
      let b = pop () in
      push a;
      push b
  | 4 -> push (ni64 ())
  | 5 -> let o = nu32 () in push (Int64.of_int (Char.code (Bytes.get !fmem (!fp + o))))
  | 6 -> let o = nu32 () in push (Int64.of_int (let v = Char.code (Bytes.get !fmem (!fp + o)) in if v >= 128 then v - 256 else v))
  | 7 -> let o = nu32 () in push (Int64.of_int (Bytes.get_uint16_le !fmem (!fp + o)))
  | 8 -> let o = nu32 () in push (Int64.of_int (Bytes.get_int16_le !fmem (!fp + o)))
  | 9 -> let o = nu32 () in push (Int64.logand (Int64.of_int32 (Bytes.get_int32_le !fmem (!fp + o))) 0xFFFFFFFFL)
  | 10 -> let o = nu32 () in push (Int64.of_int32 (Bytes.get_int32_le !fmem (!fp + o)))
  | 11 -> let o = nu32 () in push (Bytes.get_int64_le !fmem (!fp + o))
  | 12 -> let o = nu32 () in let v = pop () in Bytes.set !fmem (!fp + o) (Char.chr (Int64.to_int v land 255))
  | 13 -> let o = nu32 () in let v = pop () in Bytes.set_int16_le !fmem (!fp + o) (Int64.to_int v)
  | 14 -> let o = nu32 () in let v = pop () in Bytes.set_int32_le !fmem (!fp + o) (Int64.to_int32 v)
  | 15 -> let o = nu32 () in let v = pop () in Bytes.set_int64_le !fmem (!fp + o) v
  | 16 -> let o = nu32 () in push (Int64.bits_of_float (Int32.float_of_bits (Bytes.get_int32_le !fmem (!fp + o))))
  | 17 ->
      let o = nu32 () in
      let v = pop () in
      Bytes.set_int32_le !fmem (!fp + o) (Int32.bits_of_float (Int64.float_of_bits v))
  | 18 -> let o = nu32 () in push (Bytes.get_int64_le !fmem (!fp + o))
  | 19 -> let o = nu32 () in let v = pop () in Bytes.set_int64_le !fmem (!fp + o) v
  | 20 -> let o = nu32 () in push (Int64.of_int (!fp + o))
  | 21 -> push (Int64.of_int (get8u (pop ())))
  | 22 -> push (Int64.of_int (get8s (pop ())))
  | 23 -> push (Int64.of_int (get16u (pop ())))
  | 24 -> push (Int64.of_int (get16s (pop ())))
  | 25 -> push (get32u (pop ()))
  | 26 -> push (get32s (pop ()))
  | 27 -> push (get64 (pop ()))
  | 28 ->
      let a = pop () in
      push (Int64.bits_of_float (Int32.float_of_bits (Int64.to_int32 (get32u a))))
  | 29 -> push (get64 (pop ()))
  | 30 -> let v = pop () in let a = pop () in set8 a v
  | 31 -> let v = pop () in let a = pop () in set16 a v
  | 32 -> let v = pop () in let a = pop () in set32 a v
  | 33 -> let v = pop () in let a = pop () in set64 a v
  | 34 ->
      let v = pop () in
      let a = pop () in
      set32 a (Int64.of_int32 (Int32.bits_of_float (Int64.float_of_bits v)))
  | 35 -> let v = pop () in let a = pop () in set64 a v
  | 36 -> let b = pop () in let a = pop () in push (Int64.add a b)
  | 37 -> let b = pop () in let a = pop () in push (Int64.sub a b)
  | 38 -> let b = pop () in let a = pop () in push (Int64.mul a b)
  | 39 ->
      let b = pop () in
      let a = pop () in
      if b = 0L then fail "division by zero";
      push (Int64.div a b)
  | 40 ->
      let b = pop () in
      let a = pop () in
      if b = 0L then fail "division by zero";
      push (Int64.unsigned_div a b)
  | 41 ->
      let b = pop () in
      let a = pop () in
      if b = 0L then fail "division by zero";
      push (Int64.rem a b)
  | 42 ->
      let b = pop () in
      let a = pop () in
      if b = 0L then fail "division by zero";
      push (Int64.unsigned_rem a b)
  | 43 -> let b = pop () in let a = pop () in push (Int64.logand a b)
  | 44 -> let b = pop () in let a = pop () in push (Int64.logor a b)
  | 45 -> let b = pop () in let a = pop () in push (Int64.logxor a b)
  | 46 -> let b = pop () in let a = pop () in push (Int64.shift_left a (Int64.to_int b land 63))
  | 47 -> let b = pop () in let a = pop () in push (Int64.shift_right a (Int64.to_int b land 63))
  | 48 -> let b = pop () in let a = pop () in push (Int64.shift_right_logical a (Int64.to_int b land 63))
  | 49 -> let b = pop () in let a = pop () in push (Int64.bits_of_float (Int64.float_of_bits a +. Int64.float_of_bits b))
  | 50 -> let b = pop () in let a = pop () in push (Int64.bits_of_float (Int64.float_of_bits a -. Int64.float_of_bits b))
  | 51 -> let b = pop () in let a = pop () in push (Int64.bits_of_float (Int64.float_of_bits a *. Int64.float_of_bits b))
  | 52 -> let b = pop () in let a = pop () in push (Int64.bits_of_float (Int64.float_of_bits a /. Int64.float_of_bits b))
  | 53 -> push (Int64.logxor (pop ()) 0x8000000000000000L)
  | 54 -> let b = pop () in let a = pop () in push (if a = b then 1L else 0L)
  | 55 -> let b = pop () in let a = pop () in push (if a <> b then 1L else 0L)
  | 56 -> let b = pop () in let a = pop () in push (if Int64.compare a b < 0 then 1L else 0L)
  | 57 -> let b = pop () in let a = pop () in push (if Int64.compare a b <= 0 then 1L else 0L)
  | 58 -> let b = pop () in let a = pop () in push (if Int64.compare a b > 0 then 1L else 0L)
  | 59 -> let b = pop () in let a = pop () in push (if Int64.compare a b >= 0 then 1L else 0L)
  | 60 -> let b = pop () in let a = pop () in push (if Int64.unsigned_compare a b < 0 then 1L else 0L)
  | 61 -> let b = pop () in let a = pop () in push (if Int64.unsigned_compare a b <= 0 then 1L else 0L)
  | 62 -> let b = pop () in let a = pop () in push (if Int64.unsigned_compare a b > 0 then 1L else 0L)
  | 63 -> let b = pop () in let a = pop () in push (if Int64.unsigned_compare a b >= 0 then 1L else 0L)
  | 64 -> let b = pop () in let a = pop () in let x = Int64.float_of_bits a and y = Int64.float_of_bits b in push (if x = y then 1L else 0L)
  | 65 -> let b = pop () in let a = pop () in let x = Int64.float_of_bits a and y = Int64.float_of_bits b in push (if x = y then 0L else 1L)
  | 66 -> let b = pop () in let a = pop () in let x = Int64.float_of_bits a and y = Int64.float_of_bits b in push (if x < y then 1L else 0L)
  | 67 -> let b = pop () in let a = pop () in let x = Int64.float_of_bits a and y = Int64.float_of_bits b in push (if x <= y then 1L else 0L)
  | 68 -> let b = pop () in let a = pop () in let x = Int64.float_of_bits a and y = Int64.float_of_bits b in push (if x > y then 1L else 0L)
  | 69 -> let b = pop () in let a = pop () in let x = Int64.float_of_bits a and y = Int64.float_of_bits b in push (if x >= y then 1L else 0L)
  | 70 -> push (Int64.neg (pop ()))
  | 71 -> push (Int64.lognot (pop ()))
  | 72 -> push (Int64.bits_of_float (Int64.to_float (pop ())))
  | 73 -> push (Int64.bits_of_float (unsigned_float (pop ())))
  | 74 ->
      let x = Int64.float_of_bits (pop ()) in
      push (try Int64.of_float x with _ -> Int64.min_int)
  | 75 -> push (Int64.bits_of_float (Int32.float_of_bits (Int32.bits_of_float (Int64.float_of_bits (pop ())))))
  | 76 -> pc := nu32 ()
  | 77 -> let t = nu32 () in if pop () = 0L then pc := t
  | 78 -> let t = nu32 () in if pop () <> 0L then pc := t
  | 79 -> let idx = nu32 () in let n = nu32 () in call_index idx n false
  | 81 ->
      let n = nu32 () in
      let fptr = peek n in
      if not (is_fn fptr) then fail "call through a value that is not a function";
      let idx = Int64.to_int (Int64.logand fptr 0x0FFFFFFFFFFFFFFFL) - 1 in
      if idx < 0 || idx >= Array.length !fns then fail "call through an unknown function pointer";
      call_index idx n true
  | 80 ->
      let v = pop () in
      let r = !frames.(!nf - 1) in
      decr nf;
      sp := r.r_base;
      push v;
      fp := r.r_fp;
      fused := r.r_fsp;
      cur_fn := r.r_fn;
      cur_ops := (!fns.(r.r_fn)).f_ops;
      cur_imm := (!fns.(r.r_fn)).f_imm;
      pc := r.r_pc
  | 82 -> let n = nu32 () in let dst = pop () in let src = pop () in copy_bytes dst src n
  | 83 -> let n = nu32 () in let a = pop () in zero_bytes a n
  | 87 -> let i = nu32 () in push (!str_ptrs).(i)
  | 88 -> let i = nu32 () in push (Int64.logor tag_fn (Int64.of_int (i + 1)))
  | 89 -> push (h_alloc (Int64.to_int (pop ())))
  | 90 -> ignore (pop ())
  | 91 ->
      let n = nu32 () in
      let idx = peek 0 in
      if Int64.compare idx 0L < 0 || Int64.compare idx (Int64.of_int n) >= 0 then
        fail "index %Ld is out of bounds for a %d-element array%s" idx n (where ())
  | 84 ->
      let idx = nu32 () in
      let nargs = nu32 () in
      let res_size = nu32 () in
      let sizes = Array.init nargs (fun _ -> nu32 ()) in
      let payload = Array.fold_left ( + ) 0 sizes in
      let res_off = 40 + (8 * nargs) in
      let total = res_off + max res_size 8 + payload in
      let blk = h_alloc total in
      let at k = Int64.add blk (Int64.of_int k) in
      set64 (at 8) (Int64.of_int idx);
      set64 (at 16) (Int64.of_int nargs);
      set64 (at 24) (Int64.of_int res_off);
      set64 (at 32) (Int64.of_int res_size);
      let pay = ref (res_off + max res_size 8) in
      for k = 0 to nargs - 1 do
        let sz = sizes.(k) in
        let v = pop () in
        if sz > 0 then begin
          set64 (at (40 + (8 * k))) (at !pay);
          copy_bytes (at !pay) v sz;
          pay := !pay + sz
        end
        else set64 (at (40 + (8 * k))) v
      done;
      push blk
  | 85 -> let t = pop () in ignore (run_thunk t); push 1L
  | 86 ->
      let t = pop () in
      let res = run_thunk t in
      push (if get64 (Int64.add t 32L) > 0L then res else get64 res)
  | 92 ->
      let ldop = Array.unsafe_get ops (here + 1) in
      let off = Array.unsafe_get ops (here + 2) in
      let k = Array.unsafe_get ops (here + 3) in
      pc := here + 4;
      let v = Int64.add (ldv ldop off) (Array.unsafe_get !cur_imm k) in
      stv (stl_of_ld ldop) off v
  | 93 ->
      let ldop = Array.unsafe_get ops (here + 1) in
      let off = Array.unsafe_get ops (here + 2) in
      let k = Array.unsafe_get ops (here + 3) in
      pc := here + 4;
      let v = Int64.sub (ldv ldop off) (Array.unsafe_get !cur_imm k) in
      stv (stl_of_ld ldop) off v
  | 94 ->
      let ldop = Array.unsafe_get ops (here + 1) in
      let off = Array.unsafe_get ops (here + 2) in
      let rel = Array.unsafe_get ops (here + 3) in
      let k = Array.unsafe_get ops (here + 4) in
      let t = Array.unsafe_get ops (here + 5) in
      pc := here + 6;
      if not (cmp_rel rel (ldv ldop off) (Array.unsafe_get !cur_imm k)) then pc := t
  | 95 ->
      let v = pop () in
      push (Int64.shift_right (Int64.shift_left v 32) 32)
  | 96 ->
      let bop = Array.unsafe_get ops (here + 1) in
      let boff = Array.unsafe_get ops (here + 2) in
      let iop = Array.unsafe_get ops (here + 3) in
      let ioff = Array.unsafe_get ops (here + 4) in
      let sh = Array.unsafe_get ops (here + 5) in
      pc := here + 6;
      push (Int64.add (ldv bop boff) (Int64.shift_left (ldv iop ioff) sh))
  | 97 ->
      let bop = Array.unsafe_get ops (here + 1) in
      let boff = Array.unsafe_get ops (here + 2) in
      let iop = Array.unsafe_get ops (here + 3) in
      let ioff = Array.unsafe_get ops (here + 4) in
      let sh = Array.unsafe_get ops (here + 5) in
      let ldx = Array.unsafe_get ops (here + 6) in
      pc := here + 7;
      let a = Int64.add (ldv bop boff) (Int64.shift_left (ldv iop ioff) sh) in
      push (ld_mem ldx a)
  | 98 ->
      let bop = Array.unsafe_get ops (here + 1) in
      let boff = Array.unsafe_get ops (here + 2) in
      let iop = Array.unsafe_get ops (here + 3) in
      let ioff = Array.unsafe_get ops (here + 4) in
      let sh = Array.unsafe_get ops (here + 5) in
      let stx = Array.unsafe_get ops (here + 6) in
      pc := here + 7;
      let a = Int64.add (ldv bop boff) (Int64.shift_left (ldv iop ioff) sh) in
      let v = pop () in
      st_mem stx a v
  | 99 ->
      let bop = Array.unsafe_get ops (here + 1) in
      let b = Array.unsafe_get !cur_imm (Array.unsafe_get ops (here + 2)) in
      pc := here + 3;
      let a = pop () in
      push (int_binop bop a b)
  | 100 ->
      let ldop = Array.unsafe_get ops (here + 1) in
      let off = Array.unsafe_get ops (here + 2) in
      let mode = Array.unsafe_get ops (here + 3) in
      pc := here + 4;
      let v = Int64.shift_right (Int64.shift_left (ldv ldop off) 32) 32 in
      if mode = 0 then push v
      else begin
        let a = pop () in
        push (Int64.add a v)
      end
  | 101 ->
      let ldop = Array.unsafe_get ops (here + 1) in
      let off = Array.unsafe_get ops (here + 2) in
      let k = Array.unsafe_get !cur_imm (Array.unsafe_get ops (here + 3)) in
      let mode = Array.unsafe_get ops (here + 4) in
      let t = Array.unsafe_get ops (here + 5) in
      let v = if mode = 0 then Int64.add (ldv ldop off) k else Int64.sub (ldv ldop off) k in
      stv (stl_of_ld ldop) off v;
      pc := t
  | _ -> fail "unknown opcode %d in '%s'" op (!fns.(!cur_fn)).f_name
  done

and call_index idx nargs hasptr =
  if idx < 0 || idx >= Array.length !fns then fail "call to an unknown function";
  let f = !fns.(idx) in
  if f.f_kind = 1 then begin
    if f.f_sret then fail "extern '%s' returning an aggregate is not available to the VM" f.f_name;
    let base = !sp - nargs in
    if base < 0 then fail "stack underflow in '%s'" f.f_name;
    let args = Array.init nargs (fun k -> !stack.(base + k)) in
    sp := base;
    push (call_builtin f.f_name args)
  end
  else begin
    let consumed = nargs + (if hasptr then 1 else 0) + if f.f_sret then 1 else 0 in
    let base = !sp - consumed in
    if base < 0 then fail "stack underflow";
    if !nf >= Array.length !frames then grow_frames ();
    !frames.(!nf) <- { r_pc = !pc; r_base = base; r_fp = !fp; r_fsp = !fused; r_fn = !cur_fn };
    incr nf;
    fp := alloc_frame (max 16 f.f_frame);
    cur_fn := idx;
    cur_ops := f.f_ops;
    cur_imm := f.f_imm;
    pc := 0
  end

and run_thunk t =
  if not (is_heap t) then fail "poll on a value that is not a task";
  let res = Int64.add t (get64 (Int64.add t 24L)) in
  if get64 t = 0L then begin
    set64 t 1L;
    let idx = Int64.to_int (get64 (Int64.add t 8L)) in
    let nargs = Int64.to_int (get64 (Int64.add t 16L)) in
    let f = !fns.(idx) in
    if f.f_sret then push res;
    for k = 0 to nargs - 1 do
      push (get64 (Int64.add t (Int64.of_int (40 + (8 * k)))))
    done;
    call_index idx nargs false;
    exec (!nf - 1);
    let v = pop () in
    if not f.f_sret then set64 res v
  end;
  res

let run () =
  pc := 0;
  cur_fn := !entry;
  cur_ops := (!fns.(!entry)).f_ops;
  cur_imm := (!fns.(!entry)).f_imm;
  fp := 0;
  call_index !entry 0 false;
  exec 0;
  let v = pop () in
  flush stdout;
  exit (Int64.to_int v)

let () =
  if Array.length Sys.argv < 2 then begin
    prerr_endline "usage: rscvm <image>";
    exit 2
  end;
  try
    load_image Sys.argv.(1);
    run ()
  with
  | Error e ->
      flush stdout;
      Printf.eprintf "rscvm: %s\n" e;
      exit 1
  | Invalid_argument e ->
      flush stdout;
      Printf.eprintf "rscvm: memory fault: %s\n" e;
      exit 1

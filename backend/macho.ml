let align_up v a = if a <= 1 then v else (v + a - 1) / a * a

let page = 0x1000
let base = 0x100000000

let bput b p v = Bytes.set b p (Char.chr (v land 0xff))
let wput b p v = bput b p v; bput b (p + 1) (v lsr 8)
let dput b p v = wput b p v; wput b (p + 2) (v lsr 16)
let qput b p v = dput b p v; dput b (p + 4) (v lsr 32)
let str_at b p s = String.iteri (fun i c -> Bytes.set b (p + i) c) s

let uleb b v =
  let v = ref v in
  let go = ref true in
  while !go do
    let k = !v land 0x7f in
    v := !v lsr 7;
    if !v <> 0 then Buffer.add_char b (Char.chr (k lor 0x80))
    else begin
      Buffer.add_char b (Char.chr k);
      go := false
    end
  done

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

let segment b p name vmaddr vmsize fileoff filesize maxprot initprot nsects flags =
  dput b p 0x19;
  dput b (p + 4) (72 + (80 * nsects));
  str_at b (p + 8) name;
  qput b (p + 24) vmaddr;
  qput b (p + 32) vmsize;
  qput b (p + 40) fileoff;
  qput b (p + 48) filesize;
  dput b (p + 56) maxprot;
  dput b (p + 60) initprot;
  dput b (p + 64) nsects;
  dput b (p + 68) flags

let section b p name segname addr size offset align flags reserved1 =
  str_at b p name;
  str_at b (p + 16) segname;
  qput b (p + 32) addr;
  qput b (p + 40) size;
  dput b (p + 48) offset;
  dput b (p + 52) align;
  dput b (p + 56) 0;
  dput b (p + 60) 0;
  dput b (p + 64) flags;
  dput b (p + 68) reserved1;
  dput b (p + 72) 0;
  dput b (p + 76) 0

let link ~text ~rdata ~entry ~ext_refs ~data_refs ~imports =
  let text = Bytes.copy text in
  let syms = uniq (List.map snd imports) in
  let nsym = List.length syms in
  let dylinker = "/usr/lib/dyld" in

  let dylibs =
    "/usr/lib/libSystem.B.dylib"
    :: uniq (List.filter (fun d -> d <> "/usr/lib/libSystem.B.dylib") (List.map fst imports))
  in
  let ndylib = List.length dylibs in
  let dylib_arr = Array.of_list dylibs in
  let sym_dylib = Array.of_list (List.map (fun (d, s) -> (s, d)) imports) in
  let ordinal_of sym =
    let rec find i =
      if i >= ndylib then 1
      else
        let d = dylib_arr.(i) in
        let rec any j =
          if j >= Array.length sym_dylib then false
          else
            let s, lib = sym_dylib.(j) in
            if s = sym && lib = d then true else any (j + 1)
        in
        if any 0 then i + 1 else find (i + 1)
    in
    find 0
  in
  let sz_pagezero = 72 in
  let sz_text = 72 + 160 in
  let sz_data = 72 + 80 in
  let sz_linkedit = 72 in
  let sz_dylinker = align_up (8 + String.length dylinker + 1) 8 in
  let dylib_sizes = Array.map (fun d -> align_up (24 + String.length d + 1) 8) dylib_arr in
  let sz_dylibs = Array.fold_left ( + ) 0 dylib_sizes in
  let sz_info = 48 in
  let sz_symtab = 24 in
  let sz_dysym = 80 in
  let sz_main = 24 in
  let sz_build = 24 in
  let hdr =
    32 + sz_pagezero + sz_text + sz_data + sz_linkedit + sz_dylinker + sz_dylibs + sz_info
    + sz_symtab + sz_dysym + sz_main + sz_build
  in
  let text_off = align_up hdr 16 in
  let text_len = Bytes.length text in
  let cstr_off = align_up (text_off + text_len) 16 in
  let cstr_len = Bytes.length rdata in
  let text_file = align_up (cstr_off + cstr_len) 16 in
  let text_vm = align_up text_file page in
  let got_off = text_vm in
  let got_len = nsym * 8 in
  let data_vm = align_up (max 1 (got_len + 8)) page in
  let link_off = text_vm + data_vm in

  let bind = Buffer.create 128 in
  Buffer.add_char bind (Char.chr 0x51);
  List.iteri
    (fun i s ->
      let ord = ordinal_of s in
      if ord < 16 then Buffer.add_char bind (Char.chr (0x10 lor ord))
      else begin
        Buffer.add_char bind (Char.chr 0x20);
        uleb bind ord
      end;
      Buffer.add_char bind (Char.chr 0x72);
      uleb bind (8 * i);
      Buffer.add_char bind (Char.chr 0x40);
      Buffer.add_string bind ("_" ^ s);
      Buffer.add_char bind '\000';
      Buffer.add_char bind (Char.chr 0x90))
    syms;
  Buffer.add_char bind '\000';
  let bind_len = Buffer.length bind in

  let strx = Hashtbl.create 16 in
  let strtab = Buffer.create 128 in
  Buffer.add_char strtab '\000';
  List.iter
    (fun s ->
      Hashtbl.replace strx s (Buffer.length strtab);
      Buffer.add_string strtab ("_" ^ s);
      Buffer.add_char strtab '\000')
    syms;
  let str_len = Buffer.length strtab in

  let bind_off = link_off in
  let sym_off = align_up (bind_off + bind_len) 8 in
  let sym_len = 16 * nsym in
  let str_off = sym_off + sym_len in
  let ind_off = align_up (str_off + str_len) 4 in
  let ind_len = 4 * nsym in
  let link_len = align_up (ind_off + ind_len - link_off) 8 in

  let slot = Hashtbl.create 16 in
  List.iteri (fun i s -> Hashtbl.replace slot s i) syms;
  List.iter
    (fun (pos, sym) ->
      match Hashtbl.find_opt slot sym with
      | Some i -> dput text pos ((got_off + (8 * i)) - (text_off + pos + 4))
      | None -> raise (Failure ("no import provides '" ^ sym ^ "'")))
    ext_refs;
  List.iter
    (fun (pos, roff) -> dput text pos ((cstr_off + roff) - (text_off + pos + 4)))
    data_refs;

  let h = Bytes.make hdr '\000' in
  dput h 0 0xFEEDFACF;
  dput h 4 0x01000007;
  dput h 8 3;
  dput h 12 2;
  dput h 16 (10 + ndylib);
  dput h 20 (hdr - 32);
  dput h 24 0x00200085;
  dput h 28 0;

  let at = ref 32 in
  let p = !at in
  dput h p 0x19;
  dput h (p + 4) sz_pagezero;
  str_at h (p + 8) "__PAGEZERO";
  qput h (p + 32) 0x100000000;
  at := p + sz_pagezero;

  let p = !at in
  segment h p "__TEXT" base text_vm 0 text_vm 7 5 2 0;
  section h (p + 72) "__text" "__TEXT" (base + text_off) text_len text_off 4 0x80000400 0;
  section h (p + 152) "__cstring" "__TEXT" (base + cstr_off) cstr_len cstr_off 0 0x2 0;
  at := p + sz_text;

  let p = !at in
  segment h p "__DATA" (base + got_off) data_vm got_off data_vm 3 3 1 0;
  section h (p + 72) "__got" "__DATA" (base + got_off) got_len got_off 3 0x6 0;
  at := p + sz_data;

  let p = !at in
  segment h p "__LINKEDIT" (base + link_off) (align_up link_len page) link_off link_len 1 1 0 0;
  at := p + sz_linkedit;

  let p = !at in
  dput h p 0x8000001C;
  dput h (p + 4) sz_dylinker;
  dput h (p + 8) 12;
  str_at h (p + 12) dylinker;
  at := p + sz_dylinker;

  for i = 0 to ndylib - 1 do
    let p = !at in
    let d = dylib_arr.(i) in
    dput h p 0x8000000C;
    dput h (p + 4) dylib_sizes.(i);
    dput h (p + 8) 24;
    dput h (p + 12) (i + 1);
    dput h (p + 16) 0x00010000;
    dput h (p + 20) 0x00010000;
    str_at h (p + 24) d;
    at := p + dylib_sizes.(i)
  done;

  let p = !at in
  dput h p 0x80000022;
  dput h (p + 4) sz_info;
  dput h (p + 16) bind_off;
  dput h (p + 20) bind_len;
  at := p + sz_info;

  let p = !at in
  dput h p 0x2;
  dput h (p + 4) sz_symtab;
  dput h (p + 8) sym_off;
  dput h (p + 12) nsym;
  dput h (p + 16) str_off;
  dput h (p + 20) str_len;
  at := p + sz_symtab;

  let p = !at in
  dput h p 0xB;
  dput h (p + 4) sz_dysym;
  dput h (p + 28) nsym;
  dput h (p + 56) ind_off;
  dput h (p + 60) nsym;
  at := p + sz_dysym;

  let p = !at in
  dput h p 0x80000028;
  dput h (p + 4) sz_main;
  dput h (p + 8) (text_off + entry);
  at := p + sz_main;

  let p = !at in
  dput h p 0x32;
  dput h (p + 4) sz_build;
  dput h (p + 8) 1;
  dput h (p + 12) 0x000B0000;
  dput h (p + 16) 0x000B0000;
  at := p + sz_build;

  let total = link_off + link_len in
  let exe = Bytes.make total '\000' in
  Bytes.blit h 0 exe 0 hdr;
  Bytes.blit text 0 exe text_off text_len;
  if cstr_len > 0 then Bytes.blit rdata 0 exe cstr_off cstr_len;
  let bind_s = Buffer.contents bind in
  Bytes.blit_string bind_s 0 exe bind_off (String.length bind_s);
  let str_s = Buffer.contents strtab in
  Bytes.blit_string str_s 0 exe str_off (String.length str_s);
  List.iteri
    (fun i s ->
      let p = sym_off + (16 * i) in
      dput exe p (Hashtbl.find strx s);
      bput exe (p + 4) 0x01;
      bput exe (p + 5) 0;
      wput exe (p + 6) ((ordinal_of s) lsl 8);
      qput exe (p + 8) 0;
      dput exe (ind_off + (4 * i)) i)
    syms;
  exe

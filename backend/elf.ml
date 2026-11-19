let align_up v a = if a <= 1 then v else (v + a - 1) / a * a

let page = 0x1000
let base = 0x400000
let interp = "/lib64/ld-linux-x86-64.so.2"

let bput b p v = Bytes.set b p (Char.chr (v land 0xff))
let wput b p v = bput b p v; bput b (p + 1) (v lsr 8)
let dput b p v = wput b p v; wput b (p + 2) (v lsr 16)
let qput b p v = dput b p v; dput b (p + 4) (v lsr 32)
let str_at b p s = String.iteri (fun i c -> Bytes.set b (p + i) c) s

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

let hash s =
  let h = ref 0 in
  String.iter
    (fun c ->
      h := ((!h lsl 4) + Char.code c) land 0xffffffff;
      h := !h lxor (!h lsr 24))
    s;
  !h land 0xffffffff

let phdr b p ptype flags off vaddr filesz memsz al =
  dput b p ptype;
  dput b (p + 4) flags;
  qput b (p + 8) off;
  qput b (p + 16) vaddr;
  qput b (p + 24) vaddr;
  qput b (p + 32) filesz;
  qput b (p + 40) memsz;
  qput b (p + 48) al

let shdr b p name typ flags addr off size link info al ent =
  dput b p name;
  dput b (p + 4) typ;
  qput b (p + 8) flags;
  qput b (p + 16) addr;
  qput b (p + 24) off;
  qput b (p + 32) size;
  dput b (p + 40) link;
  dput b (p + 44) info;
  qput b (p + 48) al;
  qput b (p + 56) ent

let link ~text ~rdata ~entry ~ext_refs ~data_refs ~imports =
  let syms = uniq (List.rev_map snd imports) in
  let libs = uniq (List.map fst imports) in
  let nsym = List.length syms + 1 in
  let text = Bytes.copy text in
  let text_len = Bytes.length text in
  let cstr_len = Bytes.length rdata in

  let dynstr = Buffer.create 256 in
  Buffer.add_char dynstr '\000';
  let libx = Hashtbl.create 8 in
  List.iter
    (fun l ->
      Hashtbl.replace libx l (Buffer.length dynstr);
      Buffer.add_string dynstr l;
      Buffer.add_char dynstr '\000')
    libs;
  let symx = Hashtbl.create 16 and symoff = Hashtbl.create 16 in
  List.iteri
    (fun i s ->
      Hashtbl.replace symx s (i + 1);
      Hashtbl.replace symoff s (Buffer.length dynstr);
      Buffer.add_string dynstr s;
      Buffer.add_char dynstr '\000')
    syms;
  let dynstr_len = Buffer.length dynstr in

  let shstr =
    "\000.interp\000.dynsym\000.dynstr\000.rela.dyn\000.hash\000.text\000.rodata\000.dynamic\000.got\000.shstrtab\000"
  in
  let shstr_len = String.length shstr in
  let sname s =
    let n = String.length shstr in
    let rec find i =
      if i + String.length s >= n then 0
      else if String.sub shstr i (String.length s) = s then i
      else find (i + 1)
    in
    find 0
  in

  let nph = 5 and nsec = 11 and phoff = 64 in
  let shoff = align_up (64 + (nph * 56)) 8 in
  let interp_off = align_up (shoff + (nsec * 64)) 8 in
  let interp_len = String.length interp + 1 in
  let dynsym_off = align_up (interp_off + interp_len) 8 in
  let dynsym_len = 24 * nsym in
  let dynstr_off = dynsym_off + dynsym_len in
  let rela_off = align_up (dynstr_off + dynstr_len) 8 in
  let rela_len = 24 * (nsym - 1) in
  let nbucket = max 2 nsym in
  let hash_off = align_up (rela_off + rela_len) 8 in
  let hash_len = 4 * (2 + nbucket + nsym) in
  let text_off = align_up (hash_off + hash_len) 16 in
  let cstr_off = align_up (text_off + text_len) 16 in
  let shstr_off = align_up (cstr_off + cstr_len) 8 in
  let rx_end = shstr_off + shstr_len in
  let rw_off = align_up rx_end page in
  let ndyn = List.length libs + 10 in
  let dynamic_off = rw_off in
  let dynamic_len = 16 * ndyn in
  let got_off = align_up (dynamic_off + dynamic_len) 8 in
  let got_len = 8 * nsym in
  let total = got_off + got_len in

  let text_vaddr = base + text_off in
  let cstr_vaddr = base + cstr_off in
  let got_vaddr = base + got_off in
  let dynsym_vaddr = base + dynsym_off in
  let dynstr_vaddr = base + dynstr_off in
  let rela_vaddr = base + rela_off in
  let hash_vaddr = base + hash_off in

  List.iter
    (fun (pos, sym) ->
      match Hashtbl.find_opt symx sym with
      | Some i -> dput text pos ((got_vaddr + (8 * i)) - (text_vaddr + pos + 4))
      | None -> raise (Failure ("no import provides '" ^ sym ^ "'")))
    ext_refs;
  List.iter
    (fun (pos, roff) -> dput text pos ((cstr_vaddr + roff) - (text_vaddr + pos + 4)))
    data_refs;

  let exe = Bytes.make total '\000' in

  bput exe 0 0x7f;
  bput exe 1 0x45;
  bput exe 2 0x4c;
  bput exe 3 0x46;
  bput exe 4 2;
  bput exe 5 1;
  bput exe 6 1;
  bput exe 7 0;
  wput exe 16 2;
  wput exe 18 62;
  dput exe 20 1;
  qput exe 24 (text_vaddr + entry);
  qput exe 32 phoff;
  qput exe 40 shoff;
  dput exe 48 0;
  wput exe 52 64;
  wput exe 54 56;
  wput exe 56 nph;
  wput exe 58 64;
  wput exe 60 nsec;
  wput exe 62 10;

  phdr exe phoff 1 5 0 base rx_end rx_end page;
  phdr exe (phoff + 56) 1 6 rw_off (base + rw_off) (total - rw_off) (total - rw_off) page;
  phdr exe (phoff + 112) 2 6 dynamic_off (base + dynamic_off) dynamic_len dynamic_len 8;
  phdr exe (phoff + 168) 3 4 interp_off (base + interp_off) interp_len interp_len 1;
  phdr exe (phoff + 224) 0x6474e551 6 0 0 0 0 16;

  str_at exe interp_off interp;

  List.iteri
    (fun i s ->
      let p = dynsym_off + (24 * (i + 1)) in
      dput exe p (Hashtbl.find symoff s);
      bput exe (p + 4) 0x12;
      bput exe (p + 5) 0;
      wput exe (p + 6) 0;
      qput exe (p + 8) 0;
      qput exe (p + 16) 0;
      let r = rela_off + (24 * i) in
      qput exe r (got_vaddr + (8 * (i + 1)));
      qput exe (r + 8) (((i + 1) lsl 32) lor 6);
      qput exe (r + 16) 0)
    syms;

  let buckets = Array.make nbucket 0 in
  let chain = Array.make nsym 0 in
  List.iteri
    (fun i s ->
      let b = hash s mod nbucket in
      chain.(i + 1) <- buckets.(b);
      buckets.(b) <- i + 1)
    syms;
  wput exe hash_off nbucket;
  wput exe (hash_off + 4) nsym;
  Array.iteri (fun i v -> wput exe (hash_off + 8 + (4 * i)) v) buckets;
  Array.iteri (fun i v -> wput exe (hash_off + 8 + (4 * nbucket) + (4 * i)) v) chain;

  Bytes.blit text 0 exe text_off text_len;
  if cstr_len > 0 then Bytes.blit rdata 0 exe cstr_off cstr_len;
  Bytes.blit_string (Buffer.contents dynstr) 0 exe dynstr_off dynstr_len;
  Bytes.blit_string shstr 0 exe shstr_off shstr_len;

  let dpos = ref dynamic_off in
  let emit tag v =
    qput exe !dpos tag;
    qput exe (!dpos + 8) v;
    dpos := !dpos + 16
  in
  List.iter (fun l -> emit 1 (Hashtbl.find libx l)) libs;
  emit 4 hash_vaddr;
  emit 5 dynstr_vaddr;
  emit 6 dynsym_vaddr;
  emit 10 dynstr_len;
  emit 11 24;
  emit 7 rela_vaddr;
  emit 8 rela_len;
  emit 9 24;
  emit 0 0;

  let sp = ref shoff in
  let s name typ flags addr off size link info al ent =
    shdr exe !sp (if name = "" then 0 else sname name) typ flags addr off size link info al ent;
    sp := !sp + 64
  in
  s "" 0 0 0 0 0 0 0 0 0;
  s ".interp" 1 2 (base + interp_off) interp_off interp_len 0 0 1 0;
  s ".dynsym" 11 2 dynsym_vaddr dynsym_off dynsym_len 3 1 8 24;
  s ".dynstr" 3 2 dynstr_vaddr dynstr_off dynstr_len 0 0 1 0;
  s ".rela.dyn" 4 2 rela_vaddr rela_off rela_len 2 0 8 24;
  s ".hash" 5 2 hash_vaddr hash_off hash_len 2 0 8 4;
  s ".text" 1 6 text_vaddr text_off text_len 0 0 16 0;
  s ".rodata" 1 2 cstr_vaddr cstr_off cstr_len 0 0 16 0;
  s ".dynamic" 6 3 (base + dynamic_off) dynamic_off dynamic_len 3 0 8 16;
  s ".got" 1 3 got_vaddr got_off got_len 0 0 8 8;
  s ".shstrtab" 3 0 0 shstr_off shstr_len 0 0 1 0;

  exe

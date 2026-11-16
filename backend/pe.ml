let align_up v a =
  if a <= 1 then v else (v + a - 1) / a * a

let bput (b : Bytes.t) p v = Bytes.set b p (Char.chr (v land 0xff))

let wput b p v =
  bput b p v;
  bput b (p + 1) (v lsr 8)

let dput b p v =
  wput b p v;
  wput b (p + 2) (v lsr 16)

let qput b p v =
  dput b p v;
  dput b (p + 4) (v lsr 32)

let str_at b p s = String.iteri (fun i c -> Bytes.set b (p + i) c) s

let group imports =
  let order = ref [] in
  let tbl = Hashtbl.create 8 in
  List.iter
    (fun (dll, sym) ->
      match Hashtbl.find_opt tbl dll with
      | Some l ->
          if not (List.mem sym !l) then l := sym :: !l
      | None ->
          Hashtbl.replace tbl dll (ref [ sym ]);
          order := dll :: !order)
    imports;
  List.rev_map
    (fun dll -> (dll, List.rev !(Hashtbl.find tbl dll)))
    !order

let section_header b at name vsize vaddr rawsize rawptr flags =
  str_at b at name;
  dput b (at + 8) vsize;
  dput b (at + 12) vaddr;
  dput b (at + 16) rawsize;
  dput b (at + 20) rawptr;
  dput b (at + 24) 0;
  dput b (at + 28) 0;
  wput b (at + 32) 0;
  wput b (at + 34) 0;
  dput b (at + 36) flags

let link ~text ~rdata ~entry ~ext_refs ~data_refs ~imports =
  let text = Bytes.copy text in
  let text_size = max 0x200 (align_up (Bytes.length text) 0x200) in
  let text_rva = 0x200 in
  let rdata_rva = text_rva + text_size in
  let rdata_size = max 0x200 (align_up (Bytes.length rdata) 0x200) in
  let idata_rva = rdata_rva + rdata_size in

  let grouped = group imports in
  let ndll = List.length grouped in
  let arr_dll = Array.of_list (List.map fst grouped) in
  let arr_syms = Array.of_list (List.map snd grouped) in
  let cap = max 1 ndll in

  let desc_size = (ndll + 1) * 20 in
  let ilt_off = Array.make cap 0 in
  let iat_off = Array.make cap 0 in
  let name_off = Array.make cap 0 in
  let hn_off = Array.make cap (Array.make 0 0) in
  let off = ref desc_size in
  for i = 0 to ndll - 1 do
    ilt_off.(i) <- !off;
    off := !off + ((List.length arr_syms.(i) + 1) * 8)
  done;
  let iat_start = !off in
  for i = 0 to ndll - 1 do
    iat_off.(i) <- !off;
    off := !off + ((List.length arr_syms.(i) + 1) * 8)
  done;
  let iat_end = !off in
  for i = 0 to ndll - 1 do
    name_off.(i) <- !off;
    off := !off + String.length arr_dll.(i) + 1
  done;
  for i = 0 to ndll - 1 do
    let syms = arr_syms.(i) in
    let a = Array.make (List.length syms) 0 in
    List.iteri
      (fun k s ->
        a.(k) <- !off;
        off := !off + 2 + String.length s + 1;
        if !off land 1 = 1 then off := !off + 1)
      syms;
    hn_off.(i) <- a
  done;
  let idata_len = !off in
  let idata = Bytes.make (max 1 idata_len) '\000' in

  for i = 0 to ndll - 1 do
    let d = i * 20 in
    dput idata d (idata_rva + ilt_off.(i));
    dput idata (d + 12) (idata_rva + name_off.(i));
    dput idata (d + 16) (idata_rva + iat_off.(i));
    let syms = Array.of_list arr_syms.(i) in
    let k = Array.length syms in
    for j = 0 to k - 1 do
      qput idata (ilt_off.(i) + (j * 8)) (idata_rva + hn_off.(i).(j));
      qput idata (iat_off.(i) + (j * 8)) (idata_rva + hn_off.(i).(j))
    done;
    str_at idata name_off.(i) arr_dll.(i);
    for j = 0 to k - 1 do
      str_at idata (hn_off.(i).(j) + 2) syms.(j)
    done
  done;

  let slot_of sym =
    let rec dll i =
      if i >= ndll then None
      else
        let syms = Array.of_list arr_syms.(i) in
        let k = Array.length syms in
        let rec sym_at j =
          if j >= k then dll (i + 1)
          else if syms.(j) = sym then
            Some (idata_rva + iat_off.(i) + (j * 8))
          else sym_at (j + 1)
        in
        sym_at 0
    in
    dll 0
  in

  List.iter
    (fun (pos, sym) ->
      match slot_of sym with
      | Some rva -> dput text pos (rva - (text_rva + pos + 4))
      | None -> raise (Failure ("no import provides '" ^ sym ^ "'")))
    ext_refs;
  List.iter
    (fun (pos, roff) -> dput text pos (rdata_rva + roff - (text_rva + pos + 4)))
    data_refs;

  let idata_size = max 0x200 (align_up idata_len 0x200) in
  let image_size = idata_rva + idata_size in
  let img = Bytes.make image_size '\000' in
  Bytes.blit text 0 img text_rva (Bytes.length text);
  Bytes.blit rdata 0 img rdata_rva (Bytes.length rdata);
  Bytes.blit idata 0 img idata_rva (Bytes.length idata);

  bput img 0 0x4D;
  bput img 1 0x5A;
  dput img 0x3C 0x40;
  str_at img 0x40 "PE\000\000";

  wput img 0x44 0x8664;
  wput img 0x46 3;
  dput img 0x48 0;
  dput img 0x4C 0;
  dput img 0x50 0;
  wput img 0x54 240;
  wput img 0x56 0x0023;

  wput img 0x58 0x20B;
  bput img 0x5A 14;
  bput img 0x5B 0;
  dput img 0x5C text_size;
  dput img 0x60 (rdata_size + idata_size);
  dput img 0x64 0;
  dput img 0x68 (text_rva + entry);
  dput img 0x6C text_rva;
  qput img 0x70 0x140000000;
  dput img 0x78 0x200;
  dput img 0x7C 0x200;
  wput img 0x80 6;
  wput img 0x82 0;
  wput img 0x84 0;
  wput img 0x86 0;
  wput img 0x88 6;
  wput img 0x8A 0;
  dput img 0x8C 0;
  dput img 0x90 image_size;
  dput img 0x94 0x200;
  dput img 0x98 0;
  wput img 0x9C 3;
  wput img 0x9E 0;
  qput img 0xA0 0x100000;
  qput img 0xA8 0x1000;
  qput img 0xB0 0x100000;
  qput img 0xB8 0x1000;
  dput img 0xC0 0;
  dput img 0xC4 16;

  if ndll > 0 then begin
    dput img (0xC8 + (1 * 8)) idata_rva;
    dput img (0xC8 + (1 * 8) + 4) idata_len;
    dput img (0xC8 + (12 * 8)) (idata_rva + iat_start);
    dput img (0xC8 + (12 * 8) + 4) (iat_end - iat_start)
  end;

  section_header img 0x148 ".text" (Bytes.length text) text_rva text_size text_rva
    0x60000020;
  section_header img 0x170 ".rdata" (Bytes.length rdata) rdata_rva rdata_size
    rdata_rva 0x40000040;
  section_header img 0x198 ".idata" (Bytes.length idata) idata_rva idata_size
    idata_rva 0xC0000040;

  img

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let write_file path text =
  let oc = open_out_bin path in
  output_string oc text;
  close_out oc

let die code fmt =
  Printf.ksprintf
    (fun s ->
      Printf.eprintf "rscb: %s\n" s;
      exit code)
    fmt

let timing = Sys.getenv_opt "RSCB_TIME" <> None
let t_start = Sys.time ()
let t_prev = ref t_start
let words0 = ref 0.
let wordsmaj0 = ref 0.

let words () =
  let s = Gc.quick_stat () in
  (s.Gc.minor_words, s.Gc.major_words)

let () =
  let mn, mj = words () in
  words0 := mn;
  wordsmaj0 := mj

let stamp name =
  if timing then begin
    let now = Sys.time () in
    let mn, mj = words () in
    Printf.eprintf "rscb: %-8s %7.2f ms  cum %7.2f  alloc %7.1f MB minor %7.1f MB major\n"
      name
      ((now -. !t_prev) *. 1000.) ((now -. t_start) *. 1000.)
      ((mn -. !words0) *. 8. /. 1048576.)
      ((mj -. !wordsmaj0) *. 8. /. 1048576.);
    t_prev := now;
    words0 := mn;
    wordsmaj0 := mj
  end

let () =
  let args = Array.to_list Sys.argv |> List.tl in
  let input = ref None and output = ref None and verbose = ref false in
  let src = ref None and target = ref Target.host and vm = ref false in
  let rec scan = function
    | [] -> ()
    | "-o" :: path :: rest ->
        output := Some path;
        scan rest
    | "-s" :: path :: rest ->
        src := Some path;
        scan rest
    | "-t" :: name :: rest -> (
        match Target.parse name with
        | Some t ->
            target := t;
            scan rest
        | None -> die 2 "unknown target '%s' (windows, macos)" name)
    | "-v" :: rest ->
        verbose := true;
        scan rest
    | "--vm" :: rest ->
        vm := true;
        scan rest
    | a :: _ when String.length a > 0 && a.[0] = '-' -> die 2 "unknown flag '%s'" a
    | a :: rest -> (
        match !input with
        | None ->
            input := Some a;
            scan rest
        | Some _ -> die 2 "only one input file is supported")
  in
  scan args;

  let path =
    match !input with
    | None -> die 2 "usage: rscb <input.rsi> [-o <output>] [-t windows|macos]"
    | Some p -> p
  in

  let tgt = !target in
  let label = match !src with Some s -> s | None -> path in

  let text = try read_file path with Sys_error e -> die 1 "cannot read '%s': %s" path e in
  stamp "read";

  let program =
    try Parse.parse_string text
    with Sexp.Error e | Parse.Error e -> die 1 "%s: malformed IR: %s" label e
  in
  stamp "parse";

  let program, mono = Mono.run program in
  stamp "mono";

  let errors = Typeck.check_program program @ Borrow.check_program program in
  if errors <> [] then begin
    List.iter (fun e -> Printf.eprintf "rscb: %s: %s\n" label e) errors;
    exit 1
  end;
  stamp "check";

  let program = Fold.run program in
  stamp "fold1";
  let program, lto = Lto.run program in
  stamp "lto";
  let program = Fold.run program in
  stamp "fold2";
  let unchecked = Range.run program in
  stamp "range";
  let bytes =
    if !vm then begin
      let s =
        try Vm.compile ~unchecked program
        with Vm.Error e -> die 1 "%s: %s" label e
      in
      stamp "vm";
      Bytes.of_string s
    end
    else begin
      let image =
        try Cg.compile ~unchecked tgt program
        with Cg.Error e -> die 1 "%s: %s" label e | Failure e -> die 1 "%s: %s" label e
      in
      stamp "cg";
      let b =
        try
          match tgt.Target.fmt with
          | Target.Pe ->
              Pe.link ~text:image.Cg.im_text ~rdata:image.Cg.im_rdata
                ~entry:image.Cg.im_entry ~ext_refs:image.Cg.im_ext
                ~data_refs:image.Cg.im_data ~imports:image.Cg.im_imports
          | Target.MachO ->
              Macho.link ~text:image.Cg.im_text ~rdata:image.Cg.im_rdata
                ~entry:image.Cg.im_entry ~ext_refs:image.Cg.im_ext
                ~data_refs:image.Cg.im_data ~imports:image.Cg.im_imports
          | Target.Elf ->
              Elf.link ~text:image.Cg.im_text ~rdata:image.Cg.im_rdata
                ~entry:image.Cg.im_entry ~ext_refs:image.Cg.im_ext
                ~data_refs:image.Cg.im_data ~imports:image.Cg.im_imports
        with Failure e -> die 1 "%s: %s" label e
      in
      stamp "link";
      b
    end
  in

  let out =
    match !output with
    | Some o -> o
    | None ->
        if !vm then "a.rvm"
        else ( match tgt.Target.fmt with Target.Pe -> "a.exe" | Target.MachO | Target.Elf -> "a.out")
  in
  (try write_file out (Bytes.to_string bytes)
   with Sys_error e -> die 1 "cannot write '%s': %s" out e);
  stamp "write";

  if (not !vm) && tgt.Target.fmt <> Target.Pe && not Sys.win32 then
    ignore (Sys.command (Printf.sprintf "chmod 755 %s" (Filename.quote out)));

  if !verbose then
    Printf.eprintf "rscb: mono: %d copy(s) of %d generic fn(s)\n" mono.Mono.copies
      mono.Mono.generic;

  if !verbose then
    Printf.eprintf "rscb: lto: %d site(s) inlined, %d of %d fn(s) unreachable\n"
      lto.Lto.inlined lto.Lto.stripped lto.Lto.before;

  if !verbose then
    Printf.eprintf
      "rscb: %s: %d const(s), %d struct(s), %d extern(s), %d fn(s) -> %d bytes of image\n"
      (if !vm then "vm" else tgt.Target.name)
      (List.length program.Ast.consts)
      (List.length program.Ast.structs)
      (List.length program.Ast.externs)
      (List.length program.Ast.fns)
      (Bytes.length bytes)

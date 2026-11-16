type t =
  | Atom of string
  | List of t list

exception Error of string

let fail fmt = Printf.ksprintf (fun s -> raise (Error s)) fmt

let atom_stop = Array.make 256 false

let () =
  List.iter
    (fun c -> atom_stop.(Char.code c) <- true)
    [ ' '; '\t'; '\r'; '\n'; '('; ')'; '"' ]

let is_stop c = atom_stop.(Char.code c)

let max_depth = 512

let parse (s : string) : t =
  let n = String.length s in
  let pos = ref 0 in

  let rec skip () =
    if !pos < n then
      match s.[!pos] with
      | ' ' | '\t' | '\r' | '\n' ->
          incr pos;
          skip ()
      | ';' ->
          while !pos < n && s.[!pos] <> '\n' do
            incr pos
          done;
          skip ()
      | _ -> ()
  in

  let rec datum depth =
    if depth > max_depth then
      fail "IR nests more than %d deep at byte %d" max_depth !pos;
    skip ();
    if !pos >= n then fail "unexpected end of IR"
    else
      match s.[!pos] with
      | '(' ->
          incr pos;
          let items = ref [] in
          let rec loop () =
            skip ();
            if !pos >= n then fail "unclosed list in IR"
            else if s.[!pos] = ')' then incr pos
            else begin
              items := datum (depth + 1) :: !items;
              loop ()
            end
          in
          loop ();
          List (List.rev !items)
      | ')' -> fail "unexpected ')' in IR at byte %d" !pos
      | '"' ->
          let start = !pos in
          incr pos;
          let rec scan () =
            if !pos >= n then fail "unterminated string atom in IR"
            else
              match s.[!pos] with
              | '\\' -> pos := !pos + 2; scan ()
              | '"' -> incr pos
              | _ -> incr pos; scan ()
          in
          scan ();
          Atom (String.sub s start (!pos - start))
      | _ ->
          let start = !pos in
          while !pos < n && not (is_stop s.[!pos]) do
            incr pos
          done;
          Atom (String.sub s start (!pos - start))
  in

  let d = datum 0 in
  skip ();
  if !pos <> n then fail "trailing garbage in IR at byte %d" !pos;
  d

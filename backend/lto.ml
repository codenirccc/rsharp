open Ast

let max_rounds = 4
let budget_per_round = 4000
let max_stmt_body = 20
let max_pure_expr = 40
let max_body_size = 80

type stats = {
  mutable inlined : int;
  mutable stripped : int;
  mutable before : int;
  mutable after : int;
}

let stat () = { inlined = 0; stripped = 0; before = 0; after = 0 }

let rec subst_e (sub : (string * expr) list) (e : expr) : expr =
  let node =
    match e.node with
    | EVar n -> (
        match List.assoc_opt n sub with
        | Some r -> (copy_expr r).node
        | None -> EVar n)
    | EBin (op, a, b) -> EBin (op, subst_e sub a, subst_e sub b)
    | EUn (op, a) -> EUn (op, subst_e sub a)
    | ECall (n, args) -> ECall (n, List.map (subst_e sub) args)
    | EIndex (a, i) -> EIndex (subst_e sub a, subst_e sub i)
    | EField (a, f) -> EField (subst_e sub a, f)
    | EDeref a -> EDeref (subst_e sub a)
    | EAddr a -> EAddr (subst_e sub a)
    | EAddrMut a -> EAddrMut (subst_e sub a)
    | EBoxNew a -> EBoxNew (subst_e sub a)
    | ECast (a, t) -> ECast (subst_e sub a, t)
    | EStructLit (n, fs) -> EStructLit (n, List.map (fun (f, v) -> (f, subst_e sub v)) fs)
    | EArrayLit items -> EArrayLit (List.map (subst_e sub) items)
    | EEnumLit (en, v, args) -> EEnumLit (en, v, List.map (subst_e sub) args)
    | ETupleLit items -> ETupleLit (List.map (subst_e sub) items)
    | ECallV (f, args) -> ECallV (subst_e sub f, List.map (subst_e sub) args)
    | EAwait a -> EAwait (subst_e sub a)
    | EPoll a -> EPoll (subst_e sub a)
    | EInt _ | EFloat _ | EStr _ | EBool _ | ENull | ESizeof _ | EZero _ | EFnRef _ -> e.node
  in
  { node; ty = e.ty }

let drop_sub name sub = List.filter (fun (n, _) -> n <> name) sub

let pat_sub p sub =
  match p with
  | PVariant (_, _, binds) -> List.fold_left (fun s n -> drop_sub n s) sub binds
  | PWild -> sub

let rec subst_body sub (body : stmt list) : stmt list =
  let rec go sub acc = function
    | [] -> List.rev acc
    | st :: rest ->
        let st' = subst_s sub st in
        let sub = match st with SLet (_, n, _, _) -> drop_sub n sub | _ -> sub in
        go sub (st' :: acc) rest
  in
  go sub [] body

and subst_s sub (s : stmt) : stmt =
  match s with
  | SLet (m, n, t, init) -> SLet (m, n, t, Option.map (subst_e sub) init)
  | SAssign (op, l, r) -> SAssign (op, subst_e sub l, subst_e sub r)
  | SExpr e -> SExpr (subst_e sub e)
  | SBlock b -> SBlock (subst_body sub b)
  | SUnsafe b -> SUnsafe (subst_body sub b)
  | SIf (c, a, b) -> SIf (subst_e sub c, subst_body sub a, subst_body sub b)
  | SWhile (c, b) -> SWhile (subst_e sub c, subst_body sub b)
  | SLoop b -> SLoop (subst_body sub b)
  | SFor (v, lo, hi, b) ->
      SFor (v, subst_e sub lo, subst_e sub hi, subst_body (drop_sub v sub) b)
  | SMatch (sc, arms) ->
      SMatch
        ( subst_e sub sc,
          List.map
            (fun a -> { a with abody = subst_body (pat_sub a.apat sub) a.abody })
            arms )
  | SReturn e -> SReturn (Option.map (subst_e sub) e)
  | SBreak | SContinue -> s

let rec expr_size (e : expr) : int =
  let n = expr_size in
  let sum = List.fold_left (fun s x -> s + n x) 0 in
  match e.node with
  | EBin (_, a, b) | EIndex (a, b) -> 1 + n a + n b
  | EUn (_, a) | EDeref a | EAddr a | EAddrMut a | EBoxNew a | ECast (a, _)
  | EField (a, _) | EAwait a | EPoll a ->
      1 + n a
  | ECall (_, args) | EArrayLit args | EEnumLit (_, _, args) | ETupleLit args -> 1 + sum args
  | ECallV (f, args) -> 1 + n f + sum args
  | EStructLit (_, fs) -> 1 + List.fold_left (fun s (_, v) -> s + n v) 0 fs
  | _ -> 1

let rec stmt_size (s : stmt) : int =
  let b = body_size in
  let e = function None -> 0 | Some x -> expr_size x in
  match s with
  | SLet (_, _, _, init) -> 1 + e init
  | SAssign (_, l, r) -> 1 + expr_size l + expr_size r
  | SExpr x -> 1 + expr_size x
  | SBlock x | SUnsafe x -> 1 + b x
  | SIf (c, a, d) -> 1 + expr_size c + b a + b d
  | SWhile (c, x) -> 1 + expr_size c + b x
  | SLoop x -> 1 + b x
  | SFor (_, lo, hi, x) -> 1 + expr_size lo + expr_size hi + b x
  | SMatch (sc, arms) -> 1 + expr_size sc + List.fold_left (fun s a -> s + b a.abody) 0 arms
  | SReturn x -> 1 + e x
  | SBreak | SContinue -> 1

and body_size (body : stmt list) : int = List.fold_left (fun s x -> s + stmt_size x) 0 body

let rec escapes ~depth (s : stmt) : bool =
  match s with
  | SReturn _ -> true
  | SBreak | SContinue -> depth = 0
  | SBlock b | SUnsafe b -> List.exists (escapes ~depth) b
  | SIf (_, a, b) -> List.exists (escapes ~depth) a || List.exists (escapes ~depth) b
  | SWhile (_, b) | SLoop b -> List.exists (escapes ~depth:(depth + 1)) b
  | SFor (_, _, _, b) -> List.exists (escapes ~depth:(depth + 1)) b
  | SMatch (_, arms) -> List.exists (fun a -> List.exists (escapes ~depth) a.abody) arms
  | _ -> false

let splittable (f : fn_def) : (stmt list * expr option) option =
  if f.fasync || List.length f.fbody > max_stmt_body || body_size f.fbody > max_body_size then
    None
  else if is_heap f.fret || List.exists (fun (_, t) -> is_heap t) f.fparams then None
  else
    match List.rev f.fbody with
    | SReturn v :: rest_rev ->
        let rest = List.rev rest_rev in
        if List.exists (escapes ~depth:0) rest then None else Some (rest, v)
    | _ -> None

let pure_body (f : fn_def) : expr option =
  if f.fasync then None
  else
    match f.fbody with
    | [ SReturn (Some e) ] when expr_size e <= max_pure_expr -> Some e
    | _ -> None

let split_memo : (string, (stmt list * expr option) option) Hashtbl.t = Hashtbl.create 64
let pure_memo : (string, expr option) Hashtbl.t = Hashtbl.create 64

let forget_shapes () =
  Hashtbl.clear split_memo;
  Hashtbl.clear pure_memo

let shape_split (f : fn_def) : (stmt list * expr option) option =
  match Hashtbl.find_opt split_memo f.fname with
  | Some r -> r
  | None ->
      let r = splittable f in
      Hashtbl.replace split_memo f.fname r;
      r

let shape_pure (f : fn_def) : expr option =
  match Hashtbl.find_opt pure_memo f.fname with
  | Some r -> r
  | None ->
      let r = pure_body f in
      Hashtbl.replace pure_memo f.fname r;
      r

let trivial (e : expr) : bool =
  match e.node with
  | EVar _ | EInt _ | EFloat _ | EBool _ | ENull | ESizeof _ -> true
  | _ -> false

let counter = ref 0

let fresh base =
  incr counter;
  Printf.sprintf "$lto%d$%s" !counter base

let inline_parts (f : fn_def) (args : expr list) : (stmt list * expr option) option =
  if List.length f.fparams <> List.length args then None
  else
    match shape_split f with
    | None -> None
    | Some (rest, last) ->
        let sub, binds =
          List.split
            (List.map2
               (fun (pname, pty) arg ->
                 let tmp = fresh pname in
                 ( (pname, { node = EVar tmp; ty = pty }),
                   SLet (false, tmp, pty, Some (copy_expr arg)) ))
               f.fparams args)
        in
        Some (binds @ subst_body sub rest, Option.map (subst_e sub) last)

let lookup env n = Hashtbl.find_opt env n

let rec map_keep (f : 'a -> 'a) (l : 'a list) : 'a list =
  match l with
  | [] -> l
  | x :: rest ->
      let y = f x in
      let rest' = map_keep f rest in
      if y == x && rest' == rest then l else y :: rest'

type ctx = {
  env : (string, fn_def) Hashtbl.t;
  self : string;
  budget : int ref;
  stats : stats;
}

let rw_parts (c : ctx) (fn : string) (args : expr list) : (stmt list * expr option) option =
  match lookup c.env fn with
  | Some f when f.fname <> c.self && !(c.budget) > 0 -> (
      match inline_parts f args with
      | Some parts ->
          decr c.budget;
          c.stats.inlined <- c.stats.inlined + 1;
          Some parts
      | None -> None)
  | _ -> None

let rec rw_expr (c : ctx) (e : expr) : expr =
  let node = rw_node c e.node in
  let e = if node == e.node then e else { e with node } in
  match e.node with
  | ECall (n, args) when !(c.budget) > 0 -> (
      match lookup c.env n with
      | Some f when f.fname <> c.self -> (
          match shape_pure f with
          | Some body when List.length f.fparams = List.length args && List.for_all trivial args
            ->
              decr c.budget;
              c.stats.inlined <- c.stats.inlined + 1;
              let sub = List.map2 (fun (p, _) a -> (p, copy_expr a)) f.fparams args in
              subst_e sub body
          | _ -> e)
      | _ -> e)
  | _ -> e

and rw_node (c : ctx) (n : expr_node) : expr_node =
  match n with
  | EBin (op, a, b) ->
      let b' = rw_expr c b in
      let a' = rw_expr c a in
      if a' == a && b' == b then n else EBin (op, a', b')
  | EUn (op, a) ->
      let a' = rw_expr c a in
      if a' == a then n else EUn (op, a')
  | ECall (name, args) ->
      let args' = map_keep (rw_expr c) args in
      if args' == args then n else ECall (name, args')
  | EIndex (a, i) ->
      let i' = rw_expr c i in
      let a' = rw_expr c a in
      if a' == a && i' == i then n else EIndex (a', i')
  | EField (a, f) ->
      let a' = rw_expr c a in
      if a' == a then n else EField (a', f)
  | EDeref a ->
      let a' = rw_expr c a in
      if a' == a then n else EDeref a'
  | EAddr a ->
      let a' = rw_expr c a in
      if a' == a then n else EAddr a'
  | EAddrMut a ->
      let a' = rw_expr c a in
      if a' == a then n else EAddrMut a'
  | EBoxNew a ->
      let a' = rw_expr c a in
      if a' == a then n else EBoxNew a'
  | ECast (a, t) ->
      let a' = rw_expr c a in
      if a' == a then n else ECast (a', t)
  | EStructLit (s, fs) ->
      let fs' =
        map_keep
          (fun ((f, v) as fv) ->
            let v' = rw_expr c v in
            if v' == v then fv else (f, v'))
          fs
      in
      if fs' == fs then n else EStructLit (s, fs')
  | EArrayLit items ->
      let items' = map_keep (rw_expr c) items in
      if items' == items then n else EArrayLit items'
  | EEnumLit (en, vn, args) ->
      let args' = map_keep (rw_expr c) args in
      if args' == args then n else EEnumLit (en, vn, args')
  | ETupleLit items ->
      let items' = map_keep (rw_expr c) items in
      if items' == items then n else ETupleLit items'
  | ECallV (f, args) ->
      let args' = map_keep (rw_expr c) args in
      let f' = rw_expr c f in
      if f' == f && args' == args then n else ECallV (f', args')
  | EAwait a ->
      let a' = rw_expr c a in
      if a' == a then n else EAwait a'
  | EPoll a ->
      let a' = rw_expr c a in
      if a' == a then n else EPoll a'
  | other -> other

and rw_body (c : ctx) (body : stmt list) : stmt list =
  let changed = ref false in
  let out =
    List.concat_map
      (fun st ->
        let r = rw_stmt c st in
        (match r with [ s ] -> if s != st then changed := true | _ -> changed := true);
        r)
      body
  in
  if !changed then out else body

and rw_stmt (c : ctx) (st : stmt) : stmt list =
  match st with
  | SExpr ({ node = ECall (fn, args); _ } as call) -> (
      match rw_parts c fn args with
      | Some (inner, last) ->
          let tail = match last with Some e -> [ SExpr e ] | None -> [] in
          [ SBlock (inner @ tail) ]
      | None ->
          let e' = rw_expr c call in
          if e' == call then [ st ] else [ SExpr e' ])
  | SReturn (Some ({ node = ECall (fn, args); _ } as call)) -> (
      match rw_parts c fn args with
      | Some (inner, last) -> [ SBlock (inner @ [ SReturn last ]) ]
      | None ->
          let e' = rw_expr c call in
          if e' == call then [ st ] else [ SReturn (Some e') ])
  | SLet (m, n, t, Some ({ node = ECall (fn, args); _ } as call)) -> (
      match rw_parts c fn args with
      | Some (inner, last) -> (
          let ty = if t = TInfer then call.ty else t in
          match last with
          | None -> [ SLet (m, n, ty, None); SBlock inner ]
          | Some last ->
              let res = fresh "res" in
              [
                SLet (m, n, ty, None);
                SLet (false, res, ty, None);
                SBlock (inner @ [ SAssign ("=", { node = EVar res; ty }, last) ]);
                SAssign ("=", { node = EVar n; ty }, { node = EVar res; ty });
              ])
      | None ->
          let e' = rw_expr c call in
          if e' == call then [ st ] else [ SLet (m, n, t, Some e') ])
  | SAssign
      ("=", ({ node = EVar _; _ } as lhs), ({ node = ECall (fn, args); _ } as call)) -> (
      match rw_parts c fn args with
      | Some (inner, last) -> (
          match last with
          | None -> [ SBlock inner ]
          | Some last ->
              let ty = lhs.ty in
              let res = fresh "res" in
              [
                SLet (false, res, ty, None);
                SBlock (inner @ [ SAssign ("=", { node = EVar res; ty }, last) ]);
                SAssign ("=", lhs, { node = EVar res; ty });
              ])
      | None ->
          let e' = rw_expr c call in
          if e' == call then [ st ] else [ SAssign ("=", lhs, e') ])
  | SLet (_, _, _, None) -> [ st ]
  | SLet (m, n, t, Some init) ->
      let init' = rw_expr c init in
      if init' == init then [ st ] else [ SLet (m, n, t, Some init') ]
  | SAssign (op, l, r) ->
      let r' = rw_expr c r in
      let l' = rw_expr c l in
      if l' == l && r' == r then [ st ] else [ SAssign (op, l', r') ]
  | SExpr e ->
      let e' = rw_expr c e in
      if e' == e then [ st ] else [ SExpr e' ]
  | SBlock b ->
      let b' = rw_body c b in
      if b' == b then [ st ] else [ SBlock b' ]
  | SUnsafe b ->
      let b' = rw_body c b in
      if b' == b then [ st ] else [ SUnsafe b' ]
  | SIf (cond, a, d) ->
      let d' = rw_body c d in
      let a' = rw_body c a in
      let cond' = rw_expr c cond in
      if cond' == cond && a' == a && d' == d then [ st ] else [ SIf (cond', a', d') ]
  | SWhile (cond, b) ->
      let b' = rw_body c b in
      let cond' = rw_expr c cond in
      if cond' == cond && b' == b then [ st ] else [ SWhile (cond', b') ]
  | SLoop b ->
      let b' = rw_body c b in
      if b' == b then [ st ] else [ SLoop b' ]
  | SFor (v, lo, hi, b) ->
      let b' = rw_body c b in
      let hi' = rw_expr c hi in
      let lo' = rw_expr c lo in
      if lo' == lo && hi' == hi && b' == b then [ st ] else [ SFor (v, lo', hi', b') ]
  | SMatch (sc, arms) ->
      let arms' =
        map_keep
          (fun a ->
            let ab = rw_body c a.abody in
            if ab == a.abody then a else { a with abody = ab })
          arms
      in
      let sc' = rw_expr c sc in
      if sc' == sc && arms' == arms then [ st ] else [ SMatch (sc', arms') ]
  | SReturn (Some e) ->
      let e' = rw_expr c e in
      if e' == e then [ st ] else [ SReturn (Some e') ]
  | SReturn None | SBreak | SContinue -> [ st ]

let rec scan_e (known : (string, unit) Hashtbl.t) (tbl : (string, unit) Hashtbl.t) (e : expr) :
    unit =
  (match e.node with
  | ECall (n, args) ->
      if Hashtbl.mem known n then Hashtbl.replace tbl n ();
      List.iter (scan_e known tbl) args
  | EVar n -> if Hashtbl.mem known n then Hashtbl.replace tbl n ()
  | EFnRef n -> if Hashtbl.mem known n then Hashtbl.replace tbl n ()
  | EBin (_, a, b) | EIndex (a, b) ->
      scan_e known tbl a;
      scan_e known tbl b
  | EUn (_, a) | EDeref a | EAddr a | EAddrMut a | EBoxNew a | ECast (a, _)
  | EField (a, _) | EAwait a | EPoll a ->
      scan_e known tbl a
  | EArrayLit items | EEnumLit (_, _, items) | ETupleLit items ->
      List.iter (scan_e known tbl) items
  | ECallV (f, args) ->
      scan_e known tbl f;
      List.iter (scan_e known tbl) args
  | EStructLit (_, fs) -> List.iter (fun (_, v) -> scan_e known tbl v) fs
  | _ -> ());
  ()

let rec scan_s (known : (string, unit) Hashtbl.t) (tbl : (string, unit) Hashtbl.t) (s : stmt) :
    unit =
  match s with
  | SLet (_, _, _, init) -> Option.iter (scan_e known tbl) init
  | SAssign (_, l, r) ->
      scan_e known tbl l;
      scan_e known tbl r
  | SExpr e -> scan_e known tbl e
  | SBlock b | SUnsafe b | SLoop b -> List.iter (scan_s known tbl) b
  | SIf (c, a, b) ->
      scan_e known tbl c;
      List.iter (scan_s known tbl) a;
      List.iter (scan_s known tbl) b
  | SWhile (c, b) ->
      scan_e known tbl c;
      List.iter (scan_s known tbl) b
  | SFor (_, lo, hi, b) ->
      scan_e known tbl lo;
      scan_e known tbl hi;
      List.iter (scan_s known tbl) b
  | SMatch (sc, arms) ->
      scan_e known tbl sc;
      List.iter (fun a -> List.iter (scan_s known tbl) a.abody) arms
  | SReturn (Some e) -> scan_e known tbl e
  | SReturn None | SBreak | SContinue -> ()

let strip (p : program) : program * int =
  if not (List.exists (fun f -> f.fname = "main") p.fns) then (p, 0)
  else begin
    let known = Hashtbl.create 32 in
    List.iter (fun (f : fn_def) -> Hashtbl.replace known f.fname ()) p.fns;
    let edges = Hashtbl.create 32 in
    List.iter
      (fun (f : fn_def) ->
        let tbl = Hashtbl.create 8 in
        List.iter (scan_s known tbl) f.fbody;
        Hashtbl.replace edges f.fname tbl)
      p.fns;
    let seen = Hashtbl.create 32 in
    let queue = Queue.create () in
    Hashtbl.replace seen "main" ();
    Queue.add "main" queue;
    while not (Queue.is_empty queue) do
      let n = Queue.pop queue in
      match Hashtbl.find_opt edges n with
      | None -> ()
      | Some out ->
          Hashtbl.iter
            (fun m () ->
              if Hashtbl.mem known m && not (Hashtbl.mem seen m) then begin
                Hashtbl.replace seen m ();
                Queue.add m queue
              end)
            out
    done;
    let kept = List.filter (fun f -> Hashtbl.mem seen f.fname) p.fns in
    ({ p with fns = kept }, List.length p.fns - List.length kept)
  end

let run (p : program) : program * stats =
  let stats = stat () in
  stats.before <- List.length p.fns;
  let env = Hashtbl.create 32 in
  List.iter (fun f -> Hashtbl.replace env f.fname f) p.fns;
  let rec rounds n fns =
    if n <= 0 then fns
    else begin
      forget_shapes ();
      let budget = ref budget_per_round in
      let before = stats.inlined in
      let fns =
        List.map
          (fun (f : fn_def) ->
            if f.fasync then f
            else
              let c = { env; self = f.fname; budget; stats } in
              let body = rw_body c f.fbody in
              if body == f.fbody then f else { f with fbody = body })
          fns
      in
      List.iter (fun f -> Hashtbl.replace env f.fname f) fns;
      if stats.inlined = before then fns else rounds (n - 1) fns
    end
  in
  let fns = rounds max_rounds p.fns in
  let p, dropped = strip { p with fns } in
  stats.stripped <- dropped;
  stats.after <- List.length p.fns;
  (p, stats)

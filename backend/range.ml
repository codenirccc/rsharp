open Ast





let big = 4_000_000_000_000_000L
let bottom = -8_000_000_000_000_000L
let top = 8_000_000_000_000_000L

exception Over

let add_ck a b =
  let r = Int64.add a b in
  if Int64.compare a 0L >= 0 && Int64.compare b 0L >= 0 && Int64.compare r 0L < 0 then raise Over
  else if Int64.compare a 0L < 0 && Int64.compare b 0L < 0 && Int64.compare r 0L >= 0 then raise Over
  else r

let sub_ck a b = if b = Int64.min_int then raise Over else add_ck a (Int64.neg b)

let mul_ck a b =
  if a = 0L || b = 0L then 0L
  else begin
    if Int64.compare (Int64.abs a) big > 0 || Int64.compare (Int64.abs b) big > 0 then raise Over;
    let r = Int64.mul a b in
    if Int64.div r b <> a then raise Over;
    r
  end

let min64 a b = if Int64.compare a b <= 0 then a else b
let max64 a b = if Int64.compare a b >= 0 then a else b

let rec peel = function TRef (t, _) -> peel t | TBox t -> peel t | t -> t

let rec interval env consts (e : expr) : (int64 * int64) option =
  try
    match e.node with
    | EInt k -> Some (k, k)
    | EUn ("-", a) ->
        Option.map (fun (lo, hi) -> (Int64.neg hi, Int64.neg lo)) (interval env consts a)
    | EVar n -> (
        match List.assoc_opt n env with
        | Some r -> Some r
        | None -> (
            match Hashtbl.find_opt consts n with
            | Some v -> Some (v, v)
            | None -> None))
    | EBin (op, a, b) -> (
        match (interval env consts a, interval env consts b) with
        | Some (alo, ahi), Some (blo, bhi) -> bin_iv op alo ahi blo bhi
        | _ -> None)
    | _ -> None
  with Over -> None

and bin_iv op alo ahi blo bhi =
  match op with
  | "+" -> Some (add_ck alo blo, add_ck ahi bhi)
  | "-" -> Some (sub_ck alo bhi, sub_ck ahi blo)
  | "*" ->
      let p1 = mul_ck alo blo and p2 = mul_ck alo bhi in
      let p3 = mul_ck ahi blo and p4 = mul_ck ahi bhi in
      Some (min64 (min64 p1 p2) (min64 p3 p4), max64 (max64 p1 p2) (max64 p3 p4))
  | "/" ->
      if Int64.compare blo 0L <= 0 && Int64.compare bhi 0L >= 0 then None
      else
        let q1 = Int64.div alo blo and q2 = Int64.div alo bhi in
        let q3 = Int64.div ahi blo and q4 = Int64.div ahi bhi in
        Some (min64 (min64 q1 q2) (min64 q3 q4), max64 (max64 q1 q2) (max64 q3 q4))
  | ("&" | "|" | "^" | "<<" | ">>") when alo = ahi && blo = bhi -> (
      let x = alo and y = blo in
      match op with
      | "&" -> Some (Int64.logand x y, Int64.logand x y)
      | "|" -> Some (Int64.logor x y, Int64.logor x y)
      | "^" -> Some (Int64.logxor x y, Int64.logxor x y)
      | "<<" ->
          if Int64.compare y 0L < 0 || Int64.compare y 63L > 0 then None
          else begin
            let v = Int64.shift_left x (Int64.to_int y) in
            Some (v, v)
          end
      | ">>" ->
          if Int64.compare y 0L < 0 || Int64.compare y 63L > 0 then None
          else begin
            let v = Int64.shift_right x (Int64.to_int y) in
            Some (v, v)
          end
      | _ -> None)
  | _ -> None

let rec walk_expr tbl consts env (e : expr) : unit =
  (match e.node with
  | EBin (_, a, b) | EIndex (a, b) ->
      walk_expr tbl consts env a;
      walk_expr tbl consts env b
  | EUn (_, a) | EDeref a | EAddr a | EAddrMut a | EBoxNew a | ECast (a, _)
  | EField (a, _) | EAwait a | EPoll a ->
      walk_expr tbl consts env a
  | ECall (_, args) | EArrayLit args | EEnumLit (_, _, args) | ETupleLit args ->
      List.iter (walk_expr tbl consts env) args
  | ECallV (f, args) ->
      walk_expr tbl consts env f;
      List.iter (walk_expr tbl consts env) args
  | EStructLit (_, fs) -> List.iter (fun (_, v) -> walk_expr tbl consts env v) fs
  | _ -> ());

  match e.node with
  | EIndex (base, idx) -> (
      match peel base.ty with
      | TArray (_, n) -> (
          match interval env consts idx with
          | Some (lo, hi)
            when Int64.compare lo 0L >= 0 && Int64.compare hi (Int64.of_int n) < 0 ->
              ESet.replace tbl e ()
          | _ -> ())
      | _ -> ())
  | _ -> ()

let rec root_name (n : expr_node) : string list =
  match n with
  | EVar s -> [ s ]
  | EField (b, _) -> root_name b.node
  | EIndex (b, _) -> root_name b.node
  | EDeref _ | EAddr _ | EAddrMut _ -> []
  | _ -> []

let rec addresses (acc : string list) (e : expr) : string list =
  let acc = match e.node with EAddr a | EAddrMut a -> root_name a.node @ acc | _ -> acc in
  match e.node with
  | EBin (_, a, b) | EIndex (a, b) -> addresses (addresses acc a) b
  | EUn (_, a) | EDeref a | EAddr a | EAddrMut a | EBoxNew a | ECast (a, _)
  | EField (a, _) | EAwait a | EPoll a ->
      addresses acc a
  | ECall (_, args) | EArrayLit args | EEnumLit (_, _, args) | ETupleLit args ->
      List.fold_left addresses acc args
  | ECallV (f, args) -> List.fold_left addresses (addresses acc f) args
  | EStructLit (_, fs) -> List.fold_left (fun a (_, v) -> addresses a v) acc fs
  | _ -> acc

let rec touched (acc : string list) (st : stmt) : string list =
  match st with
  | SLet (_, n, _, _) -> n :: acc
  | SBlock b | SUnsafe b -> List.fold_left touched acc b
  | SIf (_, a, b) -> List.fold_left touched (List.fold_left touched acc a) b
  | SWhile (_, b) | SLoop b -> List.fold_left touched acc b
  | SFor (v, _, _, b) -> List.fold_left touched (v :: acc) b
  | SMatch (_, arms) ->
      List.fold_left (fun a arm -> List.fold_left touched a arm.abody) acc arms
  | SAssign (_, lhs, _) -> root_name lhs.node @ acc
  | _ -> acc

let pat_names acc = function PVariant (_, _, binds) -> binds @ acc | PWild -> acc

let touched_list acc stmts = List.fold_left touched acc stmts

let drop env names = List.filter (fun (n, _) -> not (List.mem n names)) env

let seed env name iv =
  match iv with
  | Some r -> (name, r) :: List.remove_assoc name env
  | None -> List.remove_assoc name env

let intersect (lo, hi) (lo2, hi2) =
  let l = max64 lo lo2 and h = min64 hi hi2 in
  if Int64.compare l h <= 0 then Some (l, h) else None

let refine_cmp env consts op a b truth =
  let op =
    if truth then op
    else
      match op with
      | "<" -> ">="
      | "<=" -> ">"
      | ">" -> "<="
      | ">=" -> "<"
      | "==" -> "!="
      | "!=" -> "=="
      | other -> other
  in
  let apply var op c =
    let iv =
      match op with
      | "<" when c <> Int64.min_int -> Some (bottom, Int64.sub c 1L)
      | "<=" -> Some (bottom, c)
      | ">" when c <> Int64.max_int -> Some (Int64.add c 1L, top)
      | ">=" -> Some (c, top)
      | "==" -> Some (c, c)
      | _ -> None
    in
    match iv with
    | None -> env
    | Some iv ->
        let current =
          match List.assoc_opt var env with Some r -> r | None -> (bottom, top)
        in
        (match intersect current iv with
        | Some r -> (var, r) :: List.remove_assoc var env
        | None -> List.remove_assoc var env)
  in
  match (a.node, interval env consts b) with
  | EVar n, Some (c1, c2) when c1 = c2 -> apply n op c1
  | _ -> (
      match (b.node, interval env consts a) with
      | EVar n, Some (c1, c2) when c1 = c2 ->
          let flipped =
            match op with
            | "<" -> ">"
            | "<=" -> ">="
            | ">" -> "<"
            | ">=" -> "<="
            | other -> other
          in
          apply n flipped c1
      | _ -> env)

let rec refine env consts (c : expr) truth =
  match (c.node, truth) with
  | EBin ("&&", a, b), true -> refine (refine env consts a true) consts b true
  | EBin ("||", a, b), false -> refine (refine env consts a false) consts b false
  | EUn ("!", a), _ -> refine env consts a (not truth)
  | EBin (op, a, b), _ when List.mem op [ "<"; "<="; ">"; ">="; "=="; "!=" ] ->
      refine_cmp env consts op a b truth
  | _ -> env

let rec walk_stmt tbl consts env (st : stmt) : (string * (int64 * int64)) list =
  match st with
  | SLet (_, n, _, init) ->
      Option.iter (walk_expr tbl consts env) init;
      seed env n (Option.bind init (interval env consts))
  | SAssign (op, lhs, rhs) ->
      walk_expr tbl consts env lhs;
      walk_expr tbl consts env rhs;
      (match lhs.node with
      | EVar n ->
          if op = "=" then seed env n (interval env consts rhs)
          else begin
            let bop = String.sub op 0 (String.length op - 1) in
            match (interval env consts lhs, interval env consts rhs) with
            | Some (alo, ahi), Some (blo, bhi) ->
                seed env n (bin_iv bop alo ahi blo bhi)
            | _ -> List.remove_assoc n env
          end
      | _ -> env)
  | SExpr e ->
      walk_expr tbl consts env e;
      drop env (addresses [] e)
  | SBlock body | SUnsafe body ->
      let env = List.fold_left (walk_stmt tbl consts) env body in
      drop env (touched [] (SBlock body))
  | SIf (c, th, el) ->
      walk_expr tbl consts env c;
      let th_env = refine env consts c true in
      let el_env = refine env consts c false in
      ignore (List.fold_left (walk_stmt tbl consts) th_env th);
      ignore (List.fold_left (walk_stmt tbl consts) el_env el);
      drop env (touched_list (touched_list [] th) el)
  | SWhile (c, body) ->
      walk_expr tbl consts env c;
      let body_env = refine env consts c true in
      ignore (List.fold_left (walk_stmt tbl consts) body_env body);
      drop env (touched_list [] body)
  | SLoop body ->
      ignore (List.fold_left (walk_stmt tbl consts) env body);
      drop env (touched_list [] body)
  | SFor (v, lo, hi, body) ->
      walk_expr tbl consts env lo;
      walk_expr tbl consts env hi;
      let body_env =
        match (interval env consts lo, interval env consts hi) with
        | Some (ll, _), Some (_, hh) when Int64.compare ll hh < 0 ->
            seed env v (Some (ll, Int64.sub hh 1L))
        | _ -> seed env v None
      in
      ignore (List.fold_left (walk_stmt tbl consts) body_env body);
      drop env (v :: touched_list [] body)
  | SMatch (scrut, arms) ->
      walk_expr tbl consts env scrut;
      let binds = List.fold_left (fun a arm -> pat_names a arm.apat) [] arms in
      List.iter
        (fun arm -> ignore (List.fold_left (walk_stmt tbl consts) env arm.abody))
        arms;
      drop env (binds @ touched [] (SMatch (scrut, arms)))  | SReturn (Some e) ->
      walk_expr tbl consts env e;
      env
  | SReturn None | SBreak | SContinue -> env

let run (p : program) : unit ESet.t =
  let tbl = ESet.create 64 in
  let consts = Hashtbl.create 16 in
  List.iter
    (fun c ->
      match Fold.eval_int c.cvalue with
      | Some v -> Hashtbl.replace consts c.cname v
      | None -> ())
    p.consts;
  List.iter
    (fun f ->
      let env = List.map (fun (n, _) -> (n, (bottom, top))) f.fparams in
      ignore (List.fold_left (walk_stmt tbl consts) env f.fbody))
    p.fns;
  tbl

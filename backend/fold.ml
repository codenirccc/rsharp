open Ast

let wrap_int ty v =
  match ty with
  | TI8 -> Int64.shift_right (Int64.shift_left v 56) 56
  | TI16 -> Int64.shift_right (Int64.shift_left v 48) 48
  | TI32 -> Int64.of_int32 (Int64.to_int32 v)
  | TU8 -> Int64.logand v 0xFFL
  | TU16 -> Int64.logand v 0xFFFFL
  | TU32 -> Int64.logand v 0xFFFFFFFFL
  | _ -> v

let shr_int ty x y =
  let x = wrap_int ty x in
  if is_signed ty then Int64.shift_right x y else Int64.shift_right_logical x y

let cmp_int ty x y =
  if is_signed ty then Int64.compare x y else Int64.unsigned_compare x y

let rec eval_int (e : expr) : int64 option =
  match e.node with
  | EInt n -> Some n
  | EUn ("-", a) -> Option.map Int64.neg (eval_int a)
  | EUn ("~", a) -> Option.map Int64.lognot (eval_int a)
  | ECast (a, t) when is_int t -> Option.map (wrap_int t) (eval_int a)
  | ECast (a, TBool) -> Option.map (fun n -> if n <> 0L then 1L else 0L) (eval_int a)
  | EBin (op, a, b) -> (
      match (eval_int a, eval_int b) with
      | Some x, Some y -> (
          let ty = a.ty in
          let x = wrap_int ty x and y = wrap_int ty y in
          match op with
          | "+" -> Some (wrap_int ty (Int64.add x y))
          | "-" -> Some (wrap_int ty (Int64.sub x y))
          | "*" -> Some (wrap_int ty (Int64.mul x y))
          | "/" ->
              if y = 0L then None
              else if is_signed ty then Some (wrap_int ty (Int64.div x y))
              else Some (wrap_int ty (Int64.unsigned_div x y))
          | "%" ->
              if y = 0L then None
              else if is_signed ty then Some (wrap_int ty (Int64.rem x y))
              else Some (wrap_int ty (Int64.unsigned_rem x y))
          | "&" -> Some (Int64.logand x y)
          | "|" -> Some (Int64.logor x y)
          | "^" -> Some (Int64.logxor x y)
          | "<<" ->
              if y < 0L || y > 63L then None
              else Some (wrap_int ty (Int64.shift_left x (Int64.to_int y)))
          | ">>" ->
              if y < 0L || y > 63L then None else Some (shr_int ty x (Int64.to_int y))
          | "==" -> Some (if cmp_int ty x y = 0 then 1L else 0L)
          | "!=" -> Some (if cmp_int ty x y <> 0 then 1L else 0L)
          | "<" -> Some (if cmp_int ty x y < 0 then 1L else 0L)
          | "<=" -> Some (if cmp_int ty x y <= 0 then 1L else 0L)
          | ">" -> Some (if cmp_int ty x y > 0 then 1L else 0L)
          | ">=" -> Some (if cmp_int ty x y >= 0 then 1L else 0L)
          | _ -> None)
      | _ -> None)
  | _ -> None

let rec eval_bool (e : expr) : bool option =
  match e.node with
  | EBool b -> Some b
  | EUn ("!", a) -> Option.map not (eval_bool a)
  | EBin ("&&", a, b) -> (
      match (eval_bool a, eval_bool b) with Some x, Some y -> Some (x && y) | _ -> None)
  | EBin ("||", a, b) -> (
      match (eval_bool a, eval_bool b) with Some x, Some y -> Some (x || y) | _ -> None)
  | EBin (op, a, b) when List.mem op [ "=="; "!="; "<"; "<="; ">"; ">=" ] -> (
      match (eval_int a, eval_int b) with
      | Some x, Some y ->
          let c = cmp_int a.ty x y in
          Some
            (match op with
            | "==" -> c = 0
            | "!=" -> c <> 0
            | "<" -> c < 0
            | "<=" -> c <= 0
            | ">" -> c > 0
            | _ -> c >= 0)
      | _ -> None)
  | _ -> None

let float_fold op x y =
  match op with
  | "+" -> Some (x +. y)
  | "-" -> Some (x -. y)
  | "*" -> Some (x *. y)
  | "/" -> if y = 0.0 then None else Some (x /. y)
  | _ -> None

let int_fold ty op x y =
  let x = wrap_int ty x and y = wrap_int ty y in
  match op with
  | "+" -> Some (wrap_int ty (Int64.add x y))
  | "-" -> Some (wrap_int ty (Int64.sub x y))
  | "*" -> Some (wrap_int ty (Int64.mul x y))
  | "/" ->
      if y = 0L then None
      else if is_signed ty then Some (wrap_int ty (Int64.div x y))
      else Some (wrap_int ty (Int64.unsigned_div x y))
  | "%" ->
      if y = 0L then None
      else if is_signed ty then Some (wrap_int ty (Int64.rem x y))
      else Some (wrap_int ty (Int64.unsigned_rem x y))
  | "&" -> Some (Int64.logand x y)
  | "|" -> Some (Int64.logor x y)
  | "^" -> Some (Int64.logxor x y)
  | "<<" ->
      if y < 0L || y > 63L then None
      else Some (wrap_int ty (Int64.shift_left x (Int64.to_int y)))
  | ">>" ->
      if y < 0L || y > 63L then None else Some (shr_int ty x (Int64.to_int y))
  | _ -> None

let is_compare = function "==" | "!=" | "<" | "<=" | ">" | ">=" -> true | _ -> false

let rec fold_expr (e : expr) : unit =
  (match e.node with
  | EBin (_, a, b) ->
      fold_expr a;
      fold_expr b
  | EUn (_, a) | EDeref a | EAddr a | EAddrMut a | EBoxNew a | ECast (a, _) -> fold_expr a
  | EIndex (a, b) ->
      fold_expr a;
      fold_expr b
  | EField (a, _) -> fold_expr a
  | ECall (_, args) | EArrayLit args -> List.iter fold_expr args
  | EEnumLit (_, _, args) -> List.iter fold_expr args
  | ETupleLit args -> List.iter fold_expr args
  | ECallV (f, args) ->
      fold_expr f;
      List.iter fold_expr args
  | EAwait a | EPoll a -> fold_expr a
  | EStructLit (_, fs) -> List.iter (fun (_, v) -> fold_expr v) fs
  | _ -> ());

  match e.node with
  | EUn ("-", { node = EInt n; _ }) -> e.node <- EInt (Int64.neg n)
  | EUn ("-", { node = EFloat f; _ }) -> e.node <- EFloat (-.f)
  | EUn ("~", a) -> ( match eval_int a with Some n -> e.node <- EInt (Int64.lognot n) | None -> ())
  | EUn ("!", a) -> ( match eval_bool a with Some b -> e.node <- EBool (not b) | None -> ())
  | EBin (op, a, b) -> fold_bin e op a b
  | _ -> ()

and fold_bin e op a b =
  (match (op, a.node, b.node) with
  | "&&", EBool true, _ -> e.node <- b.node
  | "&&", _, EBool true -> e.node <- a.node
  | "||", EBool false, _ -> e.node <- b.node
  | "||", _, EBool false -> e.node <- a.node
  | _ -> ());

  match e.node with
  | EBin (op, a, b) -> fold_const e op a b
  | _ -> ()

and fold_const e op a b =
  match (a.node, b.node) with
  | EFloat x, EFloat y -> (
      match float_fold op x y with Some v -> e.node <- EFloat v | None -> ())
  | EFloat x, EInt y -> (
      match float_fold op x (Int64.to_float y) with Some v -> e.node <- EFloat v | None -> ())
  | EInt x, EFloat y -> (
      match float_fold op (Int64.to_float x) y with Some v -> e.node <- EFloat v | None -> ())
  | EBool x, EBool y when op = "&&" || op = "||" ->
      e.node <- EBool (if op = "&&" then x && y else x || y)
  | _ -> (
      match (eval_int a, eval_int b) with
      | Some x, Some y ->
          (match int_fold a.ty op x y with
          | Some v ->
              if is_compare op then e.node <- EBool (v = 1L) else e.node <- EInt v
          | None -> ())
      | _ -> ())

let is_terminal = function SReturn _ | SBreak | SContinue -> true | _ -> false

let rec prune (body : stmt list) : stmt list =
  let rec go acc = function
    | [] -> List.rev acc
    | st :: rest ->
        let st = prune_stmt st in
        let acc = match st with Some s -> s :: acc | None -> acc in
        let stop = match st with Some s -> is_terminal s | None -> false in
        if stop then List.rev acc else go acc rest
  in
  go [] body

and prune_stmt (st : stmt) : stmt option =
  match st with
  | SBlock body -> Some (SBlock (prune body))
  | SUnsafe body -> Some (SUnsafe (prune body))
  | SIf (cond, th, el) -> (
      fold_expr cond;
      let th = prune th in
      let el = prune el in
      match eval_bool cond with
      | Some true -> Some (SBlock th)
      | Some false -> if el = [] then None else Some (SBlock el)
      | None -> (
          match (th, el) with
          | [], [] -> None
          | _, [] -> Some (SIf (cond, th, []))
          | _ -> Some (SIf (cond, th, el))))
  | SWhile (cond, body) -> (
      fold_expr cond;
      let body = prune body in
      match eval_bool cond with Some false -> None | _ -> Some (SWhile (cond, body)))
  | SLoop body -> Some (SLoop (prune body))
  | SFor (v, a, b, body) ->
      fold_expr a;
      fold_expr b;
      Some (SFor (v, a, b, prune body))
  | SMatch (scrut, arms) ->
      fold_expr scrut;
      Some
        (SMatch
           ( scrut,
             List.map (fun arm -> { arm with abody = prune arm.abody }) arms ))
  | SExpr e ->
      fold_expr e;
      Some (SExpr e)
  | SLet (m, n, t, init) ->
      Option.iter fold_expr init;
      Some (SLet (m, n, t, init))
  | SAssign (op, l, r) ->
      fold_expr l;
      fold_expr r;
      Some (SAssign (op, l, r))
  | SReturn (Some e) ->
      fold_expr e;
      Some (SReturn (Some e))
  | SReturn None -> Some (SReturn None)
  | SBreak -> Some SBreak
  | SContinue -> Some SContinue

let run (p : program) : program =
  List.iter (fun c -> fold_expr c.cvalue) p.consts;
  { p with fns = List.map (fun f -> { f with fbody = prune f.fbody }) p.fns }

open Ast

type bkind = Shared | Exclusive

type var_info = {
  vty : typ;
  vdepth : int;
  mutable vinit : bool;
  mutable vborrowed : int;
}

type bctx = {
  mutable scopes : (string, var_info) Hashtbl.t list;
  enums : (string, variant list) Hashtbl.t;
  mutable depth : int;
  mutable stmt_borrows : (string * bkind) list;
  mutable scope_borrows : (string * bkind * int) list;
  mutable where : string;
  mutable errors : string list;
}

let note ctx fmt =
  Printf.ksprintf (fun s -> ctx.errors <- (ctx.where ^ ": " ^ s) :: ctx.errors) fmt

let push ctx =
  ctx.depth <- ctx.depth + 1;
  ctx.scopes <- Hashtbl.create 8 :: ctx.scopes

let pop ctx =
  ctx.scope_borrows <- List.filter (fun (_, _, d) -> d < ctx.depth) ctx.scope_borrows;
  (match ctx.scopes with _ :: tl -> ctx.scopes <- tl | [] -> ());
  ctx.depth <- ctx.depth - 1

let declare ctx name ty init =
  match ctx.scopes with
  | s :: _ -> Hashtbl.replace s name { vty = ty; vdepth = ctx.depth; vinit = init; vborrowed = 0 }
  | [] -> ()
  | [] -> ()

let find ctx name =
  let rec go = function
    | [] -> None
    | s :: rest -> ( match Hashtbl.find_opt s name with Some v -> Some v | None -> go rest)
  in
  go ctx.scopes

let rec holds_ref = function
  | TRef _ -> true
  | TPtr t | TBox t -> holds_ref t
  | TArray (t, _) -> holds_ref t
  | TTuple ts -> List.exists holds_ref ts
  | _ -> false

let rec holds_borrow = function
  | TRef _ | TBox _ | TStruct _ | TEnum _ -> true
  | TPtr _ -> false
  | TArray (t, _) -> holds_borrow t
  | TTuple ts -> List.exists holds_borrow ts
  | _ -> false

let is_agg = function
  | TArray _ | TStruct _ | TEnum _ | TTuple _ -> true
  | _ -> false

let rec base_var (e : expr) =
  match e.node with
  | EVar n -> Some n
  | EField (b, _) -> base_var b
  | EIndex (b, _) -> base_var b
  | EDeref p -> base_var p
  | _ -> None

let borrows_of ctx name =
  List.filter (fun (n, _) -> n = name) ctx.stmt_borrows
  @ List.filter_map
      (fun (n, k, _) -> if n = name then Some (n, k) else None)
      ctx.scope_borrows

let check_read ctx name =
  match find ctx name with
  | Some v when not v.vinit ->
      note ctx "'%s' is declared but never assigned before this use" name
  | _ -> ()

let borrow_of ctx (e : expr) kind =
  match base_var e with
  | None -> ()
  | Some name ->
      let live = borrows_of ctx name in
      let clashes =
        match kind with
        | Shared -> List.exists (fun (_, k) -> k = Exclusive) live
        | Exclusive -> live <> []
      in
      if clashes then
        note ctx "'%s' is already borrowed; %s" name
          (if kind = Exclusive then "an '&mut' needs exclusive access"
           else "it cannot be borrowed again while an '&mut' is live");
      ctx.stmt_borrows <- (name, kind) :: ctx.stmt_borrows

let max_borrow_depth ctx (e : expr) : int =
  let rec go acc (e : expr) =
    let acc =
      match e.node with
      | EVar n -> (
          match find ctx n with
          | Some v when holds_borrow v.vty -> max acc v.vborrowed
          | _ -> acc)
      | EAddr a | EAddrMut a -> (
          match base_var a with
          | Some n -> ( match find ctx n with Some v -> max acc v.vdepth | None -> acc)
          | None -> go acc a)
      | _ -> acc
    in
    match e.node with
    | EBin (_, a, b) -> go (go acc a) b
    | EUn (_, a) | EDeref a | ECast (a, _) | EAddr a | EAddrMut a | EBoxNew a -> (
        match e.node with EAddr _ | EAddrMut _ -> acc | _ -> go acc a)
    | EIndex (a, b) -> go (go acc a) b
    | EField (a, _) -> go acc a
    | ECall (_, args) | EArrayLit args -> List.fold_left go acc args
    | ETupleLit args -> List.fold_left go acc args
    | ECallV (f, args) -> List.fold_left go (go acc f) args
    | EAwait a | EPoll a -> go acc a
    | EStructLit (_, fs) -> List.fold_left (fun a (_, v) -> go a v) acc fs
    | _ -> acc
  in
  go 0 e

let rec walk_place ctx (e : expr) =
  match e.node with
  | EVar _ -> ()
  | EField (b, _) -> walk_place ctx b
  | EIndex (b, i) ->
      walk_expr ctx b;
      walk_expr ctx i
  | EDeref p -> walk_expr ctx p
  | _ -> walk_expr ctx e

and walk_expr ctx (e : expr) =
  match e.node with
  | EVar n -> check_read ctx n
  | EAddr a ->
      borrow_of ctx a Shared;
      walk_place ctx a
  | EAddrMut a ->
      borrow_of ctx a Exclusive;
      walk_place ctx a
  | EBoxNew a -> walk_expr ctx a
  | EBin (_, a, b) ->
      walk_expr ctx a;
      walk_expr ctx b
  | EUn (_, a) | EDeref a | ECast (a, _) -> walk_expr ctx a
  | EIndex (a, b) ->
      walk_expr ctx a;
      walk_expr ctx b
  | EField (a, _) -> walk_expr ctx a
  | ECall (_, args) | EArrayLit args -> List.iter (walk_expr ctx) args
  | EEnumLit (_, _, args) -> List.iter (walk_expr ctx) args
  | ETupleLit args -> List.iter (walk_expr ctx) args
  | ECallV (f, args) ->
      walk_expr ctx f;
      List.iter (walk_expr ctx) args
  | EAwait a | EPoll a -> walk_expr ctx a
  | EStructLit (_, fs) -> List.iter (fun (_, v) -> walk_expr ctx v) fs
  | _ -> ()

let depth_for_binding ctx (ty : typ) name init =
  if holds_ref ty then
    match init with
    | Some e ->
        let need = max_borrow_depth ctx e in
        if need > ctx.depth then
          note ctx "'%s' would outlive what it points at; the borrowed value is in a deeper scope"
            name
    | None -> ()

let root_assign ctx name =
  let borrowed = List.filter (fun (n, _, _) -> n = name) ctx.scope_borrows in
  if borrowed <> [] then
    note ctx "'%s' is borrowed; assigning to it would pull the value out from under a reference"
      name;
  match find ctx name with Some v -> v.vinit <- true | None -> ()

let rec walk_stmt ctx (s : stmt) =
  ctx.stmt_borrows <- [];
  match s with
  | SLet (_, name, ty, init) ->
      Option.iter (walk_expr ctx) init;
      let ty =
        if ty = TInfer then
          match init with Some e -> e.ty | None -> TErr
        else ty
      in
      depth_for_binding ctx ty name init;
      declare ctx name ty (init <> None || is_agg ty);
      if holds_borrow ty then begin
        let b =
          match init with
          | Some e -> max_borrow_depth ctx e
          | None -> 0
        in
        (match find ctx name with
         | Some v -> v.vborrowed <- b
         | None -> ())
      end;
      if holds_ref ty then begin
        let d = ctx.depth in
        List.iter (fun (n, k) -> ctx.scope_borrows <- (n, k, d) :: ctx.scope_borrows)
          (List.filter (fun (n, _) -> find ctx n <> None) ctx.stmt_borrows)
      end;
      ctx.stmt_borrows <- []
  | SAssign (_, lhs, rhs) -> (
      match base_var lhs with
      | Some root -> root_assign ctx root
      | None -> walk_expr ctx lhs);
      walk_expr ctx rhs;
      if holds_borrow lhs.ty then begin
        let need = max_borrow_depth ctx rhs in
        if need > ctx.depth then
          note ctx "assigning a reference to something in a deeper scope; it would dangle";
        (match base_var lhs with
         | Some root -> (
             match find ctx root with
             | Some v -> v.vborrowed <- need
             | None -> ())
         | None -> ())
      end;
      ctx.stmt_borrows <- []
  | SExpr e ->
      walk_expr ctx e;
      ctx.stmt_borrows <- []
  | SBlock body ->
      push ctx;
      List.iter (walk_stmt ctx) body;
      pop ctx
  | SUnsafe body ->
      push ctx;
      List.iter (walk_stmt ctx) body;
      pop ctx
  | SIf (c, th, el) ->
      walk_expr ctx c;
      ctx.stmt_borrows <- [];
      push ctx;
      List.iter (walk_stmt ctx) th;
      pop ctx;
      push ctx;
      List.iter (walk_stmt ctx) el;
      pop ctx
  | SWhile (c, b) ->
      walk_expr ctx c;
      ctx.stmt_borrows <- [];
      push ctx;
      List.iter (walk_stmt ctx) b;
      pop ctx
  | SLoop b ->
      push ctx;
      List.iter (walk_stmt ctx) b;
      pop ctx
  | SFor (v, a, b, body) ->
      walk_expr ctx a;
      walk_expr ctx b;
      ctx.stmt_borrows <- [];
      push ctx;
      declare ctx v TI64 true;
      List.iter (walk_stmt ctx) body;
      pop ctx
  | SMatch (scrut, arms) ->
      walk_expr ctx scrut;
      ctx.stmt_borrows <- [];
      List.iter
        (fun arm ->
          push ctx;
          (match arm.apat with
          | PWild -> ()
          | PVariant (en, vn, binds) -> (
              let payload =
                match Hashtbl.find_opt ctx.enums en with
                | None -> []
                | Some vs -> (
                    match List.find_opt (fun v -> v.vname = vn) vs with
                    | Some v -> v.vpayload
                    | None -> [])
              in
              List.iteri
                (fun i n ->
                  let t = if i < List.length payload then List.nth payload i else TErr in
                  declare ctx n t true)
                binds));
          List.iter (walk_stmt ctx) arm.abody;
          pop ctx)
        arms
  | SBreak | SContinue -> ()
  | SReturn None -> ()
  | SReturn (Some e) -> (
      walk_expr ctx e;
      ctx.stmt_borrows <- [];
      if max_borrow_depth ctx e > 0 then
        note ctx "returning a reference to a local; the local is gone before the caller looks")

let check_program (p : program) : string list =
  let ctx =
    {
      scopes = [];
      enums = Hashtbl.create 16;
      depth = 0;
      stmt_borrows = [];
      scope_borrows = [];
      where = "<top level>";
      errors = [];
    }
  in
  List.iter (fun (e : enum_def) -> Hashtbl.replace ctx.enums e.ename e.evariants) p.enums;
  List.iter
    (fun (f : fn_def) ->
      ctx.where <- "fn " ^ f.fname;
      ctx.depth <- 0;
      ctx.scopes <- [];
      ctx.stmt_borrows <- [];
      ctx.scope_borrows <- [];
      let top = Hashtbl.create 8 in
      List.iter (fun (n, t) -> Hashtbl.replace top n { vty = t; vdepth = 0; vinit = true; vborrowed = 0 })
        f.fparams;
      ctx.scopes <- [ top ];
      push ctx;
      List.iter (walk_stmt ctx) f.fbody;
      pop ctx)
    p.fns;
  List.rev ctx.errors

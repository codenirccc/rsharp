open Ast





let max_rounds = 12

type stats = { mutable copies : int; mutable generic : int }


let rec sub_e (subst : (string * typ) list) (e : expr) : expr =
  { node = sub_node subst e.node; ty = subst_typ subst e.ty }

and sub_node subst (n : expr_node) : expr_node =
  let e x = sub_e subst x in
  let es xs = List.map e xs in
  match n with
  | EInt k -> EInt k
  | EFloat f -> EFloat f
  | EStr s -> EStr s
  | EBool b -> EBool b
  | ENull -> ENull
  | EVar v -> EVar v
  | EBin (op, a, b) -> EBin (op, e a, e b)
  | EUn (op, a) -> EUn (op, e a)
  | ECall (name, args) -> ECall (name, es args)
  | EIndex (a, i) -> EIndex (e a, e i)
  | EField (a, f) -> EField (e a, f)
  | EDeref a -> EDeref (e a)
  | EAddr a -> EAddr (e a)
  | EAddrMut a -> EAddrMut (e a)
  | EBoxNew a -> EBoxNew (e a)
  | ECast (a, t) -> ECast (e a, subst_typ subst t)
  | ESizeof t -> ESizeof (subst_typ subst t)
  | EZero t -> EZero (subst_typ subst t)
  | EStructLit (s, fs) -> EStructLit (s, List.map (fun (f, v) -> (f, e v)) fs)
  | EArrayLit items -> EArrayLit (es items)
  | EEnumLit (en, vn, args) -> EEnumLit (en, vn, es args)
  | ETupleLit items -> ETupleLit (es items)
  | EFnRef name -> EFnRef name
  | ECallV (f, args) -> ECallV (e f, es args)
  | EAwait a -> EAwait (e a)
  | EPoll a -> EPoll (e a)

let rec sub_s subst (s : stmt) : stmt =
  let e x = sub_e subst x in
  let b xs = List.map (sub_s subst) xs in
  match s with
  | SLet (m, n, t, init) -> SLet (m, n, subst_typ subst t, Option.map e init)
  | SAssign (op, l, r) -> SAssign (op, e l, e r)
  | SExpr x -> SExpr (e x)
  | SBlock body -> SBlock (b body)
  | SUnsafe body -> SUnsafe (b body)
  | SIf (c, a, z) -> SIf (e c, b a, b z)
  | SWhile (c, body) -> SWhile (e c, b body)
  | SLoop body -> SLoop (b body)
  | SFor (v, lo, hi, body) -> SFor (v, e lo, e hi, b body)
  | SMatch (sc, arms) ->
      SMatch
        ( e sc,
          List.map (fun a -> { a with abody = b a.abody }) arms )
  | SReturn v -> SReturn (Option.map e v)
  | SBreak -> SBreak
  | SContinue -> SContinue

let instantiate (f : fn_def) (name : string) (subst : (string * typ) list) : fn_def =
  {
    fname = name;
    fgenerics = [];
    fparams = List.map (fun (n, t) -> (n, subst_typ subst t)) f.fparams;
    fret = subst_typ subst f.fret;
    fasync = f.fasync;
    fbody = List.map (sub_s subst) f.fbody;
  }



let run (p : program) : program * stats =
  let stats = { copies = 0; generic = 0 } in
  let defs = Hashtbl.create 16 in
  List.iter
    (fun (f : fn_def) -> if f.fgenerics <> [] then Hashtbl.replace defs f.fname f)
    p.fns;

  if Hashtbl.length defs = 0 then (p, stats)
  else begin
    let built = Hashtbl.create 16 in

    let owner = Hashtbl.create 16 in
    let order = ref [] in
    let rec go round fns =
      if round > max_rounds then fns
      else begin

        Typeck.reset_pending ();
        ignore (Typeck.check_program { p with fns });
        let reqs =
          List.filter (fun (m, _, _) -> not (Hashtbl.mem built m)) (Typeck.take_pending ())
        in
        if reqs = [] then fns
        else begin
          let fresh =
            List.filter_map
              (fun (m, g, s) ->
                match Hashtbl.find_opt defs g with
                | Some f ->
                    Hashtbl.replace built m ();
                    Hashtbl.replace owner m g;
                    order := !order @ [ m ];
                    stats.copies <- stats.copies + 1;
                    Some (instantiate f m s)
                | None -> None)
              reqs
          in
          go (round + 1) (fns @ fresh)
        end
      end
    in
    let fns = go 1 p.fns in
    stats.generic <- List.length (List.filter (fun f -> f.fgenerics <> []) fns);
    let by_name = Hashtbl.create 16 in
    List.iter (fun f -> if f.fgenerics = [] then Hashtbl.replace by_name f.fname f) fns;
    let keep =
      List.concat_map
        (fun (f : fn_def) ->
          if f.fgenerics = [] then [ f ]
          else
            List.filter_map
              (fun m ->
                match Hashtbl.find_opt owner m with
                | Some g when g = f.fname -> Hashtbl.find_opt by_name m
                | _ -> None)
              !order)
        p.fns
    in
    ({ p with fns = keep }, stats)
  end

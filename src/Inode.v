Require Import Arith.
Require Import Pred PredCrash.
Require Import Word.
Require Import Prog.
Require Import Hoare.
Require Import SepAuto.
Require Import BasicProg.
Require Import Omega.
Require Import Log.
Require Import Array.
Require Import List ListUtils.
Require Import Bool.
Require Import Eqdep_dec.
Require Import Setoid.
Require Import Rec.
Require Import FunctionalExtensionality.
Require Import NArith.
Require Import WordAuto.
Require Import RecArrayUtils LogRecArray.
Require Import GenSepN.
Require Import Balloc.
Require Import ListPred.
Require Import FSLayout.
Require Import AsyncDisk.
Require Import BlockPtr.
Require Import GenSepAuto.

Import ListNotations.

Set Implicit Arguments.



Module INODE.

  (************* on-disk representation of inode *)

  Definition iattrtype : Rec.type := Rec.RecF ([
    ("bytes",  Rec.WordF 64) ;       (* file size in bytes *)
    ("uid",    Rec.WordF 32) ;        (* user id *)
    ("gid",    Rec.WordF 32) ;        (* group id *)
    ("dev",    Rec.WordF 64) ;        (* device major/minor *)
    ("mtime",  Rec.WordF 32) ;        (* last modify time *)
    ("atime",  Rec.WordF 32) ;        (* last access time *)
    ("ctime",  Rec.WordF 32) ;        (* create time *)
    ("itype",  Rec.WordF  8) ;        (* type code, 0 = regular file, 1 = directory, ... *)
    ("unused", Rec.WordF 24)          (* reserved (permission bits) *)
  ]).

  Definition NDirect := 9.

  Definition irectype : Rec.type := Rec.RecF ([
    ("len", Rec.WordF addrlen);     (* number of blocks *)
    ("attrs", iattrtype);           (* file attributes *)
    ("indptr", Rec.WordF addrlen);  (* indirect block pointer *)
    ("blocks", Rec.ArrayF (Rec.WordF addrlen) NDirect)]).


  (* RecArray for inodes records *)
  Module IRecSig <: RASig.

    Definition xparams := inode_xparams.
    Definition RAStart := IXStart.
    Definition RALen := IXLen.
    Definition xparams_ok (_ : xparams) := True.

    Definition itemtype := irectype.
    Definition items_per_val := valulen / (Rec.len itemtype).


    Theorem blocksz_ok : valulen = Rec.len (Rec.ArrayF itemtype items_per_val).
    Proof.
      unfold items_per_val; rewrite valulen_is; compute; auto.
    Qed.

  End IRecSig.

  Module IRec := LogRecArray IRecSig.
  Hint Extern 0 (okToUnify (IRec.rep _ _) (IRec.rep _ _)) => constructor : okToUnify.


  Definition iattr := Rec.data iattrtype.
  Definition irec := IRec.Defs.item.
  Definition bnlist := list waddr.

  Module BPtrSig <: BlockPtrSig.

    Definition irec     := irec.
    Definition iattr    := iattr.
    Definition NDirect  := NDirect.

    Fact NDirect_bound : NDirect <= addrlen.
      compute; omega.
    Qed.

    Definition IRLen    (x : irec) := Eval compute_rec in # ( x :-> "len").
    Definition IRIndPtr (x : irec) := Eval compute_rec in # ( x :-> "indptr").
    Definition IRBlocks (x : irec) := Eval compute_rec in ( x :-> "blocks").
    Definition IRAttrs  (x : irec) := Eval compute_rec in ( x :-> "attrs").

    Definition upd_len (x : irec) v  := Eval compute_rec in (x :=> "len" := $ v).

    Definition upd_irec (x : irec) len ibptr dbns := Eval compute_rec in
      (x :=> "len" := $ len :=> "indptr" := $ ibptr :=> "blocks" := dbns).

    (* getter/setter lemmas *)
    Fact upd_len_get_len : forall ir n,
      goodSize addrlen n -> IRLen (upd_len ir n) = n.
    Proof.
      unfold IRLen, upd_len; intros; simpl.
      rewrite wordToNat_natToWord_idempotent'; auto.
    Qed.

    Fact upd_len_get_ind : forall ir n, IRIndPtr (upd_len ir n) = IRIndPtr ir.
    Proof. intros; simpl; auto. Qed.

    Fact upd_len_get_blk : forall ir n, IRBlocks (upd_len ir n) = IRBlocks ir.
    Proof. intros; simpl; auto. Qed.

    Fact upd_len_get_iattr : forall ir n, IRAttrs (upd_len ir n) = IRAttrs ir.
    Proof. intros; simpl; auto. Qed.

    Fact upd_irec_get_len : forall ir len ibptr dbns,
      goodSize addrlen len -> IRLen (upd_irec ir len ibptr dbns) = len.
    Proof.
      intros; cbn.
      rewrite wordToNat_natToWord_idempotent'; auto.
    Qed.

    Fact upd_irec_get_ind : forall ir len ibptr dbns,
      goodSize addrlen ibptr -> IRIndPtr (upd_irec ir len ibptr dbns) = ibptr.
    Proof.
      intros; cbn.
      rewrite wordToNat_natToWord_idempotent'; auto.
    Qed.

    Fact upd_irec_get_blk : forall ir len ibptr dbns, 
      IRBlocks (upd_irec ir len ibptr dbns) = dbns.
    Proof. intros; simpl; auto. Qed.

    Fact upd_irec_get_iattr : forall ir len ibptr dbns, 
      IRAttrs (upd_irec ir len ibptr dbns) = IRAttrs ir.
    Proof. intros; simpl; auto. Qed.

  End BPtrSig.

  Module Ind := BlockPtr BPtrSig.

  Definition NBlocks := NDirect + Ind.IndSig.items_per_val.

  Definition items_per_val := IRecSig.items_per_val.


  (************* program *)


  Definition init lxp xp ms : prog _ :=
    ms <- IRec.init lxp xp ms;
    Ret ms.

  Definition getlen lxp xp inum ms : prog _ := Eval compute_rec in
    let^ (ms, (ir : irec)) <- IRec.get_array lxp xp inum ms;
    Ret ^(ms, # (ir :-> "len" )).

  (* attribute getters *)

  Definition ABytes  (a : iattr) := Eval cbn in ( a :-> "bytes" ).
  Definition AMTime  (a : iattr) := Eval cbn in ( a :-> "mtime" ).
  Definition AType   (a : iattr) := Eval cbn in ( a :-> "itype" ).
  Definition ADev    (a : iattr) := Eval cbn in ( a :-> "dev" ).

  Definition getattrs lxp xp inum ms : prog _ := Eval compute_rec in
    let^ (ms, (i : irec)) <- IRec.get_array lxp xp inum ms;
    Ret ^(ms, (i :-> "attrs")).

  Definition setattrs lxp xp inum attr ms : prog _ := Eval compute_rec in
    let^ (ms, (i : irec)) <- IRec.get_array lxp xp inum ms;
    ms <- IRec.put_array lxp xp inum (i :=> "attrs" := attr) ms;
    Ret ms.

  (* For updattr : a convenient way for setting individule attribute *)

  Inductive iattrupd_arg :=
  | UBytes (v : word 64)
  | UMTime (v : word 32)
  | UType  (v : word  8)
  | UDev   (v : word 64)
  .

  Definition iattr_upd (e : iattr) (a : iattrupd_arg) := Eval compute_rec in
  match a with
  | UBytes v => (e :=> "bytes" := v)
  | UMTime v => (e :=> "mtime" := v)
  | UType  v => (e :=> "itype" := v)
  | UDev   v => (e :=> "dev"   := v)
  end.

  Definition updattr lxp xp inum a ms : prog _ := Eval compute_rec in
    let^ (ms, (i : irec)) <- IRec.get_array lxp xp inum ms;
    ms <- IRec.put_array lxp xp inum (i :=> "attrs" := (iattr_upd (i :-> "attrs") a)) ms;
    Ret ms.


  Definition getbnum lxp xp inum off ms : prog _ :=
    let^ (ms, (ir : irec)) <- IRec.get_array lxp xp inum ms;
    ms <- Ind.get lxp ir off ms;
    Ret ms.

  Definition getallbnum lxp xp inum ms : prog _ :=
    let^ (ms, (ir : irec)) <- IRec.get_array lxp xp inum ms;
    ms <- Ind.read lxp ir ms;
    Ret ms.

  Definition shrink lxp bxp xp inum nr ms : prog _ :=
    let^ (ms, (ir : irec)) <- IRec.get_array lxp xp inum ms;
    let^ (ms, ir') <- Ind.shrink lxp bxp ir nr ms;
    ms <- IRec.put_array lxp xp inum ir' ms;
    Ret ms.

  Definition grow lxp bxp xp inum bn ms : prog _ :=
    let^ (ms, (ir : irec)) <- IRec.get_array lxp xp inum ms;
    let^ (ms, r) <- Ind.grow lxp bxp ir ($ bn) ms;
    match r with
    | None => Ret ^(ms, false)
    | Some ir' =>
        ms <- IRec.put_array lxp xp inum ir' ms;
        Ret ^(ms, true)
    end.


  (************** rep invariant *)

  Record inode := mk_inode {
    IBlocks : bnlist;
    IAttr   : iattr
  }.

  Definition iattr0 := @Rec.of_word iattrtype $0.
  Definition inode0 := mk_inode nil iattr0.
  Definition irec0 := IRec.Defs.item0.


  Definition inode_match bxp ino (ir : irec) := Eval compute_rec in
    ( [[ IAttr ino = (ir :-> "attrs") ]] *
      [[ Forall (fun a => BALLOC.bn_valid bxp (# a) ) (IBlocks ino) ]] *
      Ind.rep bxp ir (IBlocks ino) )%pred.

  Definition rep bxp xp (ilist : list inode) := (
     exists reclist, IRec.rep xp reclist *
     listmatch (inode_match bxp) ilist reclist)%pred.


  (************** Basic lemmas *)

  Lemma irec_well_formed : forall Fm xp l i inum m,
    (Fm * IRec.rep xp l)%pred m
    -> i = selN l inum irec0
    -> Rec.well_formed i.
  Proof.
    intros; subst.
    eapply IRec.item_wellforemd; eauto.
  Qed.

  Lemma direct_blocks_length: forall (i : irec),
    Rec.well_formed i
    -> length (i :-> "blocks") = NDirect.
  Proof.
    intros; simpl in H.
    destruct i; repeat destruct p.
    repeat destruct d0; repeat destruct p; intuition.
  Qed.

  Lemma irec_blocks_length: forall m xp l inum Fm,
    (Fm * IRec.rep xp l)%pred m ->
    length (selN l inum irec0 :-> "blocks") = NDirect.
  Proof.
    intros.
    apply direct_blocks_length.
    eapply irec_well_formed; eauto.
  Qed.

  Lemma irec_blocks_length': forall m xp l inum Fm d d0 d1 d2 u,
    (Fm * IRec.rep xp l)%pred m ->
    (d, (d0, (d1, (d2, u)))) = selN l inum irec0 ->
    length d2 = NDirect.
  Proof.
    intros.
    eapply IRec.item_wellforemd with (i := inum) in H.
    setoid_rewrite <- H0 in H.
    unfold Rec.well_formed in H; simpl in H; intuition.
  Qed.

  Theorem rep_bxp_switch : forall bxp bxp' xp ilist,
    BmapNBlocks bxp = BmapNBlocks bxp' ->
    rep bxp xp ilist <=p=> rep bxp' xp ilist.
  Proof.
    unfold rep, inode_match, Ind.rep, Ind.indrep, BALLOC.bn_valid; intros.
    split; rewrite H; reflexivity.
  Qed.

  (**************  Automation *)

  Fact resolve_selN_irec0 : forall l i d,
    d = irec0 -> selN l i d = selN l i irec0.
  Proof.
    intros; subst; auto.
  Qed.

  Fact resolve_selN_inode0 : forall l i d,
    d = inode0 -> selN l i d = selN l i inode0.
  Proof.
    intros; subst; auto.
  Qed.

  Hint Rewrite resolve_selN_irec0   using reflexivity : defaults.
  Hint Rewrite resolve_selN_inode0  using reflexivity : defaults.


  Ltac destruct_irec' x :=
    match type of x with
    | irec => let b := fresh in destruct x as [? b] eqn:? ; destruct_irec' b
    | iattr => let b := fresh in destruct x as [? b] eqn:? ; destruct_irec' b
    | prod _ _ => let b := fresh in destruct x as [? b] eqn:? ; destruct_irec' b
    | _ => idtac
    end.

  Ltac destruct_irec x :=
    match x with
    | (?a, ?b) => (destruct_irec a || destruct_irec b)
    | fst ?a => destruct_irec a
    | snd ?a => destruct_irec a
    | _ => destruct_irec' x; simpl
    end.

  Ltac smash_rec_well_formed' :=
    match goal with
    | [ |- Rec.well_formed ?x ] => destruct_irec x
    end.

  Ltac smash_rec_well_formed :=
    subst; autorewrite with defaults;
    repeat smash_rec_well_formed';
    unfold Rec.well_formed; simpl;
    try rewrite Forall_forall; intuition.


  Ltac irec_wf :=
    smash_rec_well_formed;
    match goal with
      | [ H : ?p %pred ?mm |- length ?d = NDirect ] =>
      match p with
        | context [ IRec.rep ?xp ?ll ] => 
          eapply irec_blocks_length' with (m := mm) (l := ll) (xp := xp); eauto;
          pred_apply; cancel
      end
    end.

  Arguments Rec.well_formed : simpl never.



  (********************** SPECs *)

  Theorem getlen_ok : forall lxp bxp xp inum ms,
    {< F Fm Fi m0 m ilist ino,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) ms hm *
           [[[ m ::: (Fm * rep bxp xp ilist) ]]] *
           [[[ ilist ::: Fi * inum |-> ino ]]]
    POST:hm' RET:^(ms,r)
           LOG.rep lxp F (LOG.ActiveTxn m0 m) ms hm' *
           [[ r = length (IBlocks ino) ]]
    CRASH:hm'  exists ms',
           LOG.rep lxp F (LOG.ActiveTxn m0 m) ms' hm'
    >} getlen lxp xp inum ms.
  Proof.
    unfold getlen, rep; pose proof irec0.
    safestep.
    sepauto.
    safestep.

    extract.
    denote Ind.rep as Hx; unfold Ind.rep in Hx; destruct_lift Hx.
    seprewrite; subst; eauto.
  Qed.


  Theorem getattrs_ok : forall lxp bxp xp inum ms,
    {< F Fm Fi m0 m ilist ino,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) ms hm *
           [[[ m ::: (Fm * rep bxp xp ilist) ]]] *
           [[[ ilist ::: (Fi * inum |-> ino) ]]]
    POST:hm' RET:^(ms,r)
           LOG.rep lxp F (LOG.ActiveTxn m0 m) ms hm' *
           [[ r = IAttr ino ]]
    CRASH:hm'  exists ms',
           LOG.rep lxp F (LOG.ActiveTxn m0 m) ms' hm'
    >} getattrs lxp xp inum ms.
  Proof.
    unfold getattrs, rep.
    safestep.
    sepauto.

    safestep.
    extract.
    seprewrite; subst; eauto.
  Qed.


  Theorem setattrs_ok : forall lxp bxp xp inum attr ms,
    {< F Fm Fi m0 m ilist ino,
    PRE:hm 
           LOG.rep lxp F (LOG.ActiveTxn m0 m) ms hm *
           [[[ m ::: (Fm * rep bxp xp ilist) ]]] *
           [[[ ilist ::: (Fi * inum |-> ino) ]]]
    POST:hm' RET:ms exists m' ilist' ino',
           LOG.rep lxp F (LOG.ActiveTxn m0 m') ms hm' *
           [[[ m' ::: (Fm * rep bxp xp ilist') ]]] *
           [[[ ilist' ::: (Fi * inum |-> ino') ]]] *
           [[ ino' = mk_inode (IBlocks ino) attr ]]
    CRASH:hm'  LOG.intact lxp F m0 hm'
    >} setattrs lxp xp inum attr ms.
  Proof.
    unfold setattrs, rep.
    safestep.
    sepauto.

    safestep.
    irec_wf.
    sepauto.

    safestep.
    eapply listmatch_updN_selN; simplen.
    instantiate (1 := mk_inode (IBlocks ino) attr).
    unfold inode_match; cancel; sepauto.
    sepauto.

    eauto.
    cancel.
    cancel; eauto.
    Unshelve. exact irec0.
  Qed.


  Theorem updattr_ok : forall lxp bxp xp inum kv ms,
    {< F Fm Fi m0 m ilist ino,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) ms hm *
           [[[ m ::: (Fm * rep bxp xp ilist) ]]] *
           [[[ ilist ::: (Fi * inum |-> ino) ]]]
    POST:hm' RET:ms exists m' ilist' ino',
           LOG.rep lxp F (LOG.ActiveTxn m0 m') ms hm' *
           [[[ m' ::: (Fm * rep bxp xp ilist') ]]] *
           [[[ ilist' ::: (Fi * inum |-> ino') ]]] *
           [[ ino' = mk_inode (IBlocks ino) (iattr_upd (IAttr ino) kv) ]]
    CRASH:hm'  LOG.intact lxp F m0 hm'
    >} updattr lxp xp inum kv ms.
  Proof.
    unfold updattr, rep.
    safestep.
    sepauto.

    safestep.
    filldef; abstract (destruct kv; simpl; subst; irec_wf).
    sepauto.

    safestep.
    eapply listmatch_updN_selN; simplen.
    instantiate (1 := mk_inode (IBlocks ino) (iattr_upd (IAttr ino) kv)).
    unfold inode_match; cancel; sepauto.

    sepauto.
    auto.
    cancel.
    cancel; eauto.
    Unshelve. exact irec0.
  Qed.


  Theorem getbnum_ok : forall lxp bxp xp inum off ms,
    {< F Fm Fi m0 m ilist ino,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) ms hm *
           [[ off < length (IBlocks ino) ]] *
           [[[ m ::: (Fm * rep bxp xp ilist) ]]] *
           [[[ ilist ::: (Fi * inum |-> ino) ]]]
    POST:hm' RET:^(ms, r)
           LOG.rep lxp F (LOG.ActiveTxn m0 m) ms hm' *
           [[ r = selN (IBlocks ino) off $0 ]]
    CRASH:hm'  exists ms',
           LOG.rep lxp F (LOG.ActiveTxn m0 m) ms' hm'
    >} getbnum lxp xp inum off ms.
  Proof.
    unfold getbnum, rep.
    safestep.
    sepauto.

    prestep; norml.
    extract; seprewrite.
    cancel.
    step.
    cancel.
  Qed.


  Theorem getallbnum_ok : forall lxp bxp xp inum ms,
    {< F Fm Fi m0 m ilist ino,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) ms hm *
           [[[ m ::: (Fm * rep bxp xp ilist) ]]] *
           [[[ ilist ::: (Fi * inum |-> ino) ]]]
    POST:hm' RET:^(ms, r)
           LOG.rep lxp F (LOG.ActiveTxn m0 m) ms hm' *
           [[ r = (IBlocks ino) ]]
    CRASH:hm'  exists ms',
           LOG.rep lxp F (LOG.ActiveTxn m0 m) ms' hm'
    >} getallbnum lxp xp inum ms.
  Proof.
    unfold getallbnum, rep.
    safestep.
    sepauto.

    prestep; norml.
    extract; seprewrite.
    cancel.
    step.
    cancel.
  Qed.


  Theorem shrink_ok : forall lxp bxp xp inum nr ms,
    {< F Fm Fi m0 m ilist ino freelist,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) ms hm *
           [[[ m ::: (Fm * rep bxp xp ilist * BALLOC.rep bxp freelist) ]]] *
           [[[ ilist ::: (Fi * inum |-> ino) ]]]
    POST:hm' RET:ms exists m' ilist' ino' freelist',
           LOG.rep lxp F (LOG.ActiveTxn m0 m') ms hm' *
           [[[ m' ::: (Fm * rep bxp xp ilist' * BALLOC.rep bxp freelist') ]]] *
           [[[ ilist' ::: (Fi * inum |-> ino') ]]] *
           [[ ino' = mk_inode (cuttail nr (IBlocks ino)) (IAttr ino) ]] *
           [[ incl freelist freelist' ]]
    CRASH:hm'  LOG.intact lxp F m0 hm'
    >} shrink lxp bxp xp inum nr ms.
  Proof.
    unfold shrink, rep.
    safestep.
    sepauto.

    extract; seprewrite.
    step.
    step.
    subst; unfold BPtrSig.upd_len, BPtrSig.IRLen.
    irec_wf.
    sepauto.

    safestep.
    2: sepauto.
    rewrite listmatch_updN_removeN by omega.
    cancel.
    unfold inode_match, BPtrSig.upd_len, BPtrSig.IRLen; simpl.
    2: eauto.
    cancel.
    apply forall_firstn; auto.
    cancel; auto.
    Unshelve. exact IRec.Defs.item0.
  Qed.


  Lemma grow_wellformed : forall (a : BPtrSig.irec) inum reclist F1 F2 F3 F4 m xp,
    ((((F1 * IRec.rep xp reclist) * F2) * F3) * F4)%pred m ->
    length (BPtrSig.IRBlocks a) = length (BPtrSig.IRBlocks (selN reclist inum irec0)) ->
    inum < length reclist ->
    Rec.well_formed a.
  Proof.
    unfold IRec.rep, IRec.items_valid; intros.
    destruct_lift H.
    denote Forall as Hx.
    apply Forall_selN with (i := inum) (def := irec0) in Hx; auto.
    apply direct_blocks_length in Hx.
    setoid_rewrite <- H0 in Hx.
    cbv in Hx; cbv in a.
    cbv.
    destruct a; repeat destruct p. destruct p0; destruct p.
    intuition.
  Qed.

  Theorem grow_ok : forall lxp bxp xp inum bn ms,
    {< F Fm Fi m0 m ilist ino freelist,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) ms hm *
           [[ length (IBlocks ino) < NBlocks ]] *
           [[ BALLOC.bn_valid bxp bn ]] *
           [[[ m ::: (Fm * rep bxp xp ilist * BALLOC.rep bxp freelist) ]]] *
           [[[ ilist ::: (Fi * inum |-> ino) ]]]
    POST:hm' RET:^(ms, r)
           [[ r = false ]] * LOG.rep lxp F (LOG.ActiveTxn m0 m) ms hm' \/
           [[ r = true ]] * exists m' ilist' ino' freelist',
           LOG.rep lxp F (LOG.ActiveTxn m0 m') ms hm' *
           [[[ m' ::: (Fm * rep bxp xp ilist' * BALLOC.rep bxp freelist') ]]] *
           [[[ ilist' ::: (Fi * inum |-> ino') ]]] *
           [[ ino' = mk_inode ((IBlocks ino) ++ [$ bn]) (IAttr ino) ]] *
           [[ incl freelist' freelist ]]
    CRASH:hm'  LOG.intact lxp F m0 hm'
    >} grow lxp bxp xp inum bn ms.
  Proof.
    unfold grow, rep.
    safestep.
    sepauto.

    extract; seprewrite.
    step.
    step.
    eapply grow_wellformed; eauto.
    sepauto.

    step.
    or_r; cancel.
    2: sepauto.
    rewrite listmatch_updN_removeN by omega.
    cancel.
    unfold inode_match, BPtrSig.IRAttrs in *; simpl.
    cancel.
    substl (IAttr (selN ilist inum inode0)); eauto.
    apply Forall_app; auto.
    eapply BALLOC.bn_valid_roundtrip; eauto.
    cancel; auto.

    Unshelve. all: eauto; exact emp.
  Qed.


  Hint Extern 1 ({{_}} Bind (getlen _ _ _ _) _) => apply getlen_ok : prog.
  Hint Extern 1 ({{_}} Bind (getattrs _ _ _ _) _) => apply getattrs_ok : prog.
  Hint Extern 1 ({{_}} Bind (setattrs _ _ _ _ _) _) => apply setattrs_ok : prog.
  Hint Extern 1 ({{_}} Bind (updattr _ _ _ _ _) _) => apply updattr_ok : prog.
  Hint Extern 1 ({{_}} Bind (getbnum _ _ _ _ _) _) => apply getbnum_ok : prog.
  Hint Extern 1 ({{_}} Bind (getallbnum _ _ _ _) _) => apply getallbnum_ok : prog.
  Hint Extern 1 ({{_}} Bind (grow _ _ _ _ _ _) _) => apply grow_ok : prog.
  Hint Extern 1 ({{_}} Bind (shrink _ _ _ _ _ _) _) => apply shrink_ok : prog.

  Hint Extern 0 (okToUnify (rep _ _ _) (rep _ _ _)) => constructor : okToUnify.


  Lemma inode_rep_bn_valid_piff : forall bxp xp l,
    rep bxp xp l <=p=> rep bxp xp l *
      [[ forall inum, inum < length l ->
         Forall (fun a => BALLOC.bn_valid bxp (# a) ) (IBlocks (selN l inum inode0)) ]].
  Proof.
    intros; split;
    unfold pimpl; intros; pred_apply;
    unfold rep in H; destruct_lift H; cancel.
    extract at inum; auto.
  Qed.

  Lemma inode_rep_bn_nonzero_pimpl : forall bxp xp l,
    rep bxp xp l =p=> rep bxp xp l *
      [[ forall inum off, inum < length l ->
         off < length (IBlocks (selN l inum inode0)) ->
         # (selN (IBlocks (selN l inum inode0)) off $0) <> 0 ]].
  Proof.
    intros.
    setoid_rewrite inode_rep_bn_valid_piff at 1; cancel.
    specialize (H1 _ H).
    rewrite Forall_forall in H1.
    eapply H1; eauto.
    apply in_selN; eauto.
  Qed.

  Lemma crash_xform_inode_match : forall xp a b,
    crash_xform (inode_match xp a b) <=p=> inode_match xp a b.
  Proof.
    unfold inode_match; split.
    xform_norm.
    rewrite Ind.xform_rep; cancel.
    cancel.
    xform_normr.
    rewrite Ind.xform_rep; cancel.
  Qed.


  Theorem xform_rep : forall bxp xp l,
    crash_xform (rep bxp xp l) <=p=> rep bxp xp l.
  Proof.
    unfold rep; intros; split.
    xform_norm.
    rewrite IRec.xform_rep.
    rewrite xform_listmatch_idem.
    cancel.
    apply crash_xform_inode_match.

    cancel.
    xform_normr.
    rewrite IRec.xform_rep.
    rewrite xform_listmatch_idem.
    cancel.
    apply crash_xform_inode_match.
  Qed.

End INODE.


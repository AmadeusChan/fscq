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
Require Import Inode.
Require Import GenSepAuto.
Require Import DiskSet.
Require Import Errno.


Import ListNotations.

Set Implicit Arguments.

(** BFILE is a block-based file implemented on top of the log and the
inode representation. The API provides reading/writing single blocks,
changing the size of the file, and managing file attributes (which are
the same as the inode attributes). *)

Module BFILE.

  Definition memstate := (bool * LOG.memstate)%type.
  Definition mk_memstate a b : memstate := (a, b).
  Definition MSAlloc (ms : memstate) := fst ms.   (* which block allocator to use? *)
  Definition MSLL (ms : memstate) := snd ms.      (* lower-level state *)


  (* interface implementation *)

  Definition getlen lxp ixp inum fms :=
    let '(al, ms) := (MSAlloc fms, MSLL fms) in
    let^ (ms, n) <- INODE.getlen lxp ixp inum ms;
    Ret ^(mk_memstate al ms, n).

  Definition getattrs lxp ixp inum fms :=
    let '(al, ms) := (MSAlloc fms, MSLL fms) in
    let^ (ms, n) <- INODE.getattrs lxp ixp inum ms;
    Ret ^(mk_memstate al ms, n).

  Definition setattrs lxp ixp inum a fms :=
    let '(al, ms) := (MSAlloc fms, MSLL fms) in
    ms <- INODE.setattrs lxp ixp inum a ms;
    Ret (mk_memstate al ms).

  Definition updattr lxp ixp inum kv fms :=
    let '(al, ms) := (MSAlloc fms, MSLL fms) in
    ms <- INODE.updattr lxp ixp inum kv ms;
    Ret (mk_memstate al ms).

  Definition read lxp ixp inum off fms :=
    let '(al, ms) := (MSAlloc fms, MSLL fms) in
    let^ (ms, bn) <-INODE.getbnum lxp ixp inum off ms;
    let^ (ms, v) <- LOG.read lxp (# bn) ms;
    Ret ^(mk_memstate al ms, v).

  Definition write lxp ixp inum off v fms :=
    let '(al, ms) := (MSAlloc fms, MSLL fms) in
    let^ (ms, bn) <-INODE.getbnum lxp ixp inum off ms;
    ms <- LOG.write lxp (# bn) v ms;
    Ret (mk_memstate al ms).

  Definition dwrite lxp ixp inum off v fms :=
    let '(al, ms) := (MSAlloc fms, MSLL fms) in
    let^ (ms, bn) <- INODE.getbnum lxp ixp inum off ms;
    ms <- LOG.dwrite lxp (# bn) v ms;
    Ret (mk_memstate al ms).

  Definition datasync lxp ixp inum fms :=
    let '(al, ms) := (MSAlloc fms, MSLL fms) in
    let^ (ms, bns) <- INODE.getallbnum lxp ixp inum ms;
    ms <- LOG.dsync_vecs lxp (map (@wordToNat _) bns) ms;
    Ret (mk_memstate al ms).

  Definition sync lxp (ixp : INODE.IRecSig.xparams) fms :=
    let '(al, ms) := (MSAlloc fms, MSLL fms) in
    ms <- LOG.flushsync lxp ms;
    Ret (mk_memstate (negb al) ms).

  Definition sync_noop lxp (ixp : INODE.IRecSig.xparams) fms :=
    let '(al, ms) := (MSAlloc fms, MSLL fms) in
    ms <- LOG.flushsync_noop lxp ms;
    Ret (mk_memstate (negb al) ms).

  Definition pick_balloc A (a : A * A) (flag : bool) :=
    if flag then fst a else snd a.

  Definition grow lxp bxps ixp inum v fms :=
    let '(al, ms) := (MSAlloc fms, MSLL fms) in
    let^ (ms, len) <- INODE.getlen lxp ixp inum ms;
    If (lt_dec len INODE.NBlocks) {
      let^ (ms, r) <- BALLOC.alloc lxp (pick_balloc bxps al) ms;
      match r with
      | None => Ret ^(mk_memstate al ms, Err ENOSPCBLOCK)
      | Some bn =>
           let^ (ms, succ) <- INODE.grow lxp (pick_balloc bxps al) ixp inum bn ms;
           match succ with
           | Err e =>
             Ret ^(mk_memstate al ms, Err e)
           | OK _ =>
             ms <- LOG.write lxp bn v ms;
             Ret ^(mk_memstate al ms, OK tt)
           end
      end
    } else {
      Ret ^(mk_memstate al ms, Err EFBIG)
    }.

  Definition shrink lxp bxps ixp inum nr fms :=
    let '(al, ms) := (MSAlloc fms, MSLL fms) in
    let^ (ms, bns) <- INODE.getallbnum lxp ixp inum ms;
    let l := map (@wordToNat _) (skipn ((length bns) - nr) bns) in
    ms <- BALLOC.freevec lxp (pick_balloc bxps (negb al)) l ms;
    ms <- INODE.shrink lxp (pick_balloc bxps (negb al)) ixp inum nr ms;
    Ret (mk_memstate al ms).

  Definition shuffle_allocs lxp bxps ms :=
    let^ (ms) <- ForN i < (BmapNBlocks (fst bxps) * valulen)
    Hashmap hm
    Ghost [ F Fm crash m0 ]
    Loopvar [ ms ]
    Invariant
         exists m' frees,
         LOG.rep lxp F (LOG.ActiveTxn m0 m') ms hm *
         [[[ m' ::: (Fm * BALLOC.rep (fst bxps) (fst frees) *
                         BALLOC.rep (snd bxps) (snd frees)) ]]] *
         [[ forall bn, bn < (BmapNBlocks (fst bxps)) * valulen /\ bn >= i
             -> In bn (fst frees) ]]
    OnCrash crash
    Begin
      If (bool_dec (Nat.odd i) true) {
        ms <- BALLOC.steal lxp (fst bxps) i ms;
        ms <- BALLOC.free lxp (snd bxps) i ms;
        Ret ^(ms)
      } else {
        Ret ^(ms)
      }
    Rof ^(ms);
    Ret ms.

  Definition init lxp bxps bixp ixp ms :=
    ms <- BALLOC.init_nofree lxp (snd bxps) ms;
    ms <- BALLOC.init lxp (fst bxps) ms;
    ms <- IAlloc.init lxp bixp ms;
    ms <- INODE.init lxp ixp ms;
    ms <- shuffle_allocs lxp bxps ms;
    Ret (mk_memstate true ms).

  (* rep invariants *)

  Definition attr := INODE.iattr.
  Definition attr0 := INODE.iattr0.

  Definition datatype := valuset.

  Record bfile := mk_bfile {
    BFData : list datatype;
    BFAttr : attr
  }.

  Definition bfile0 := mk_bfile nil attr0.

  Definition file_match f i : @pred _ addr_eq_dec datatype :=
    (listmatch (fun v a => a |-> v ) (BFData f) (map (@wordToNat _) (INODE.IBlocks i)) *
     [[ BFAttr f = INODE.IAttr i ]])%pred.

  Definition rep (bxps : balloc_xparams * balloc_xparams) ixp (flist : list bfile) ilist frees :=
    (BALLOC.rep (fst bxps) (fst frees) *
     BALLOC.rep (snd bxps) (snd frees) *
     INODE.rep (fst bxps) ixp ilist *
     listmatch file_match flist ilist *
     [[ BmapNBlocks (fst bxps) = BmapNBlocks (snd bxps) ]]
    )%pred.

  Definition rep_length_pimpl : forall bxps ixp flist ilist frees,
    rep bxps ixp flist ilist frees =p=>
    (rep bxps ixp flist ilist frees *
     [[ length flist = ((INODE.IRecSig.RALen ixp) * INODE.IRecSig.items_per_val)%nat ]] *
     [[ length ilist = ((INODE.IRecSig.RALen ixp) * INODE.IRecSig.items_per_val)%nat ]])%pred.
  Proof.
    unfold rep; intros.
    rewrite INODE.rep_length_pimpl at 1.
    rewrite listmatch_length_pimpl at 1.
    cancel.
  Qed.

  Definition block_belong_to_file ilist bn inum off :=
    off < length (INODE.IBlocks (selN ilist inum INODE.inode0)) /\
    bn = # (selN (INODE.IBlocks (selN ilist inum INODE.inode0)) off $0).

  Definition block_is_unused freeblocks (bn : addr) := In bn freeblocks.

  Definition block_is_unused_dec freeblocks (bn : addr) :
    { block_is_unused freeblocks bn } + { ~ block_is_unused freeblocks bn }
    := In_dec addr_eq_dec bn freeblocks.

  Definition ilist_safe ilist1 free1 ilist2 free2 :=
    incl free2 free1 /\
    forall inum off bn,
        block_belong_to_file ilist2 bn inum off ->
        (block_belong_to_file ilist1 bn inum off \/
         block_is_unused free1 bn).

  Theorem ilist_safe_refl : forall i f,
    ilist_safe i f i f.
  Proof.
    unfold ilist_safe; intuition.
  Qed.
  Local Hint Resolve ilist_safe_refl.

  Theorem ilist_safe_trans : forall i1 f1 i2 f2 i3 f3,
    ilist_safe i1 f1 i2 f2 ->
    ilist_safe i2 f2 i3 f3 ->
    ilist_safe i1 f1 i3 f3.
  Proof.
    unfold ilist_safe; intros.
    destruct H.
    destruct H0.
    split.
    - eapply incl_tran; eauto.
    - intros.
      specialize (H2 _ _ _ H3).
      destruct H2; eauto.
      right.
      unfold block_is_unused in *.
      eauto.
  Qed.

  Lemma block_belong_to_file_inum_ok : forall ilist bn inum off,
    block_belong_to_file ilist bn inum off ->
    inum < length ilist.
  Proof.
    intros.
    destruct (lt_dec inum (length ilist)); eauto.
    unfold block_belong_to_file in *.
    rewrite selN_oob in H by omega.
    simpl in H.
    omega.
  Qed.

  Theorem rep_safe_used: forall F bxps ixp flist ilist m bn inum off frees v,
    (F * rep bxps ixp flist ilist frees)%pred (list2nmem m) ->
    block_belong_to_file ilist bn inum off ->
    let f := selN flist inum bfile0 in
    let f' := mk_bfile (updN (BFData f) off v) (BFAttr f) in
    let flist' := updN flist inum f' in
    (F * rep bxps ixp flist' ilist frees)%pred (list2nmem (updN m bn v)).
  Proof.
    unfold rep; intros.
    destruct_lift H.
    rewrite listmatch_length_pimpl in H; destruct_lift H.
    rewrite listmatch_extract with (i := inum) in H.
    2: substl (length flist); eapply block_belong_to_file_inum_ok; eauto.

    assert (inum < length ilist) by ( eapply block_belong_to_file_inum_ok; eauto ).
    assert (inum < length flist) by ( substl (length flist); eauto ).

    denote block_belong_to_file as Hx; assert (Hy := Hx).
    unfold block_belong_to_file in Hy; intuition.
    unfold file_match at 2 in H.
    rewrite listmatch_length_pimpl with (a := BFData _) in H; destruct_lift H.
    denote! (length _ = _) as Heq.
    rewrite listmatch_extract with (i := off) (a := BFData _) in H.
    2: rewrite Heq; rewrite map_length; eauto.

    erewrite selN_map in H; eauto.

    eapply pimpl_trans; [ apply pimpl_refl | | eapply list2nmem_updN; pred_apply ].
    2: eassign (natToWord addrlen 0).
    2: cancel.

    cancel.

    eapply pimpl_trans.
    2: eapply listmatch_isolate with (i := inum); eauto.
    2: rewrite length_updN; eauto.

    rewrite removeN_updN. cancel.
    unfold file_match; cancel.
    2: rewrite selN_updN_eq by ( substl (length flist); eauto ).
    2: simpl; eauto.

    eapply pimpl_trans.
    2: eapply listmatch_isolate with (i := off).
    2: rewrite selN_updN_eq by ( substl (length flist); eauto ).
    2: simpl.
    2: rewrite length_updN.
    2: rewrite Heq; rewrite map_length; eauto.
    2: rewrite map_length; eauto.

    rewrite selN_updN_eq; eauto; simpl.
    erewrite selN_map by eauto.
    rewrite removeN_updN.
    rewrite selN_updN_eq by ( rewrite Heq; rewrite map_length; eauto ).
    cancel.

    Grab Existential Variables.
    all: eauto.
    exact BFILE.bfile0.
  Qed.

  Theorem rep_safe_unused: forall F bxps ixp flist ilist m frees bn v flag,
    (F * rep bxps ixp flist ilist frees)%pred (list2nmem m) ->
    block_is_unused (pick_balloc frees flag) bn ->
    (F * rep bxps ixp flist ilist frees)%pred (list2nmem (updN m bn v)).
  Proof.
    unfold rep, pick_balloc, block_is_unused; intros.
    destruct_lift H.
    destruct flag.
    - unfold BALLOC.rep at 1 in H.
      unfold BALLOC.Alloc.rep in H.
      destruct_lift H.

      denote listpred as Hx.
      assert (Hy := Hx).
      rewrite listpred_nodup_piff in Hy; [ | apply addr_eq_dec | apply ptsto_conflict ].
      rewrite listpred_remove in Hy; [ | apply ptsto_conflict | eauto ].
      rewrite Hy in H.
      destruct_lift H.
      eapply pimpl_trans; [ apply pimpl_refl | | eapply list2nmem_updN; pred_apply; cancel ].
      unfold BALLOC.rep at 2. unfold BALLOC.Alloc.rep.
      cancel; eauto.
      eapply pimpl_trans; [ | eapply listpred_remove'; eauto; apply ptsto_conflict ].
      cancel.
    - unfold BALLOC.rep at 2 in H.
      unfold BALLOC.Alloc.rep in H.
      destruct_lift H.

      denote listpred as Hx.
      assert (Hy := Hx).
      rewrite listpred_nodup_piff in Hy; [ | apply addr_eq_dec | apply ptsto_conflict ].
      rewrite listpred_remove in Hy; [ | apply ptsto_conflict | eauto ].
      rewrite Hy in H.
      destruct_lift H.
      eapply pimpl_trans; [ apply pimpl_refl | | eapply list2nmem_updN; pred_apply; cancel ].
      unfold BALLOC.rep at 3. unfold BALLOC.Alloc.rep.
      cancel; eauto.
      eapply pimpl_trans; [ | eapply listpred_remove'; eauto; apply ptsto_conflict ].
      cancel.

    Unshelve.
    all: apply addr_eq_dec.
  Qed.

  Theorem block_belong_to_file_bfdata_length : forall bxp ixp flist ilist frees m F inum off bn,
    (F * rep bxp ixp flist ilist frees)%pred m ->
    block_belong_to_file ilist bn inum off ->
    off < length (BFData (selN flist inum BFILE.bfile0)).
  Proof.
    intros.
    apply block_belong_to_file_inum_ok in H0 as H0'.
    unfold block_belong_to_file, rep in *.
    rewrite listmatch_extract with (i := inum) in H.
    unfold file_match at 2 in H.
    rewrite listmatch_length_pimpl with (a := BFData _) in H.
    destruct_lift H.
    rewrite map_length in *.
    intuition.
    rewrite H11; eauto.
    rewrite listmatch_length_pimpl in H.
    destruct_lift H.
    rewrite H8. eauto.
  Qed.

  Definition synced_file f := mk_bfile (synced_list (map fst (BFData f))) (BFAttr f).

  Lemma add_nonzero_exfalso_helper2 : forall a b,
    a * valulen + b = 0 -> a <> 0 -> False.
  Proof.
    intros.
    destruct a; auto.
    rewrite Nat.mul_succ_l in H.
    assert (0 < a * valulen + valulen + b).
    apply Nat.add_pos_l.
    apply Nat.add_pos_r.
    rewrite valulen_is; simpl.
    apply Nat.lt_0_succ.
    omega.
  Qed.

  Lemma file_match_init_ok : forall n,
    emp =p=> listmatch file_match (repeat bfile0 n) (repeat INODE.inode0 n).
  Proof.
    induction n; simpl; intros.
    unfold listmatch; cancel.
    rewrite IHn.
    unfold listmatch; cancel.
    unfold file_match, listmatch; cancel.
  Qed.

  Lemma odd_nonzero : forall n,
    Nat.odd n = true -> n <> 0.
  Proof.
    destruct n; intros; auto.
    cbv in H; congruence.
  Qed.

  Local Hint Resolve odd_nonzero.

  (**** automation **)

  Fact resolve_selN_bfile0 : forall l i d,
    d = bfile0 -> selN l i d = selN l i bfile0.
  Proof.
    intros; subst; auto.
  Qed.

  Fact resolve_selN_vs0 : forall l i (d : valuset),
    d = ($0, nil) -> selN l i d = selN l i ($0, nil).
  Proof.
    intros; subst; auto.
  Qed.

  Hint Rewrite resolve_selN_bfile0 using reflexivity : defaults.
  Hint Rewrite resolve_selN_vs0 using reflexivity : defaults.

  Ltac assignms :=
    match goal with
    [ fms : memstate |- LOG.rep _ _ _ ?ms _ =p=> LOG.rep _ _ _ (MSLL ?e) _ ] =>
      is_evar e; eassign (mk_memstate (MSAlloc fms) ms); simpl; eauto
    end.

  Local Hint Extern 1 (LOG.rep _ _ _ ?ms _ =p=> LOG.rep _ _ _ (MSLL ?e) _) => assignms.

  (*** specification *)


  Theorem shuffle_allocs_ok : forall lxp bxps ms,
    {< F Fm m0 m frees,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) ms hm *
           [[[ m ::: (Fm * BALLOC.rep (fst bxps) (fst frees) *
                           BALLOC.rep (snd bxps) (snd frees)) ]]] *
           [[ forall bn, bn < (BmapNBlocks (fst bxps)) * valulen -> In bn (fst frees) ]] *
           [[ BmapNBlocks (fst bxps) = BmapNBlocks (snd bxps) ]]
    POST:hm' RET:ms'  exists m' frees',
           LOG.rep lxp F (LOG.ActiveTxn m0 m') ms' hm' *
           [[[ m' ::: (Fm * BALLOC.rep (fst bxps) (fst frees') *
                            BALLOC.rep (snd bxps) (snd frees')) ]]]
    CRASH:hm'  LOG.intact lxp F m0 hm'
    >} shuffle_allocs lxp bxps ms.
  Proof.
    unfold shuffle_allocs.
    step.
    step.
    step.
    unfold BALLOC.bn_valid; split; auto.
    step.
    unfold BALLOC.bn_valid; split; auto.
    substl (BmapNBlocks bxps_2); auto.
    step.
    apply remove_other_In.
    omega.
    intuition.
    step.
    step.
    eapply LOG.intact_hashmap_subset.
    eauto.
    Unshelve. exact tt.
  Qed.

  Hint Extern 1 ({{_}} Bind (shuffle_allocs _ _ _) _) => apply shuffle_allocs_ok : prog.

  Local Hint Resolve INODE.IRec.Defs.items_per_val_gt_0 INODE.IRec.Defs.items_per_val_not_0 valulen_gt_0.

  Theorem init_ok : forall lxp bxps ibxp ixp ms,
    {< F Fm m0 m l,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) ms hm *
           [[[ m ::: (Fm * arrayN (@ptsto _ _ _) 0 l) ]]] *
           [[ let data_bitmaps := (BmapNBlocks (fst bxps)) in
              let inode_bitmaps := (IAlloc.Sig.BMPLen ibxp) in
              let data_blocks := (data_bitmaps * valulen)%nat in
              let inode_blocks := (inode_bitmaps * valulen / INODE.IRecSig.items_per_val)%nat in
              let inode_base := data_blocks in
              let balloc_base1 := inode_base + inode_blocks + inode_bitmaps in
              let balloc_base2 := balloc_base1 + data_bitmaps in
              length l = balloc_base2 + data_bitmaps /\
              BmapNBlocks (fst bxps) = BmapNBlocks (snd bxps) /\
              BmapStart (fst bxps) = balloc_base1 /\
              BmapStart (snd bxps) = balloc_base2 /\
              IAlloc.Sig.BMPStart ibxp = inode_base + inode_blocks /\
              IXStart ixp = inode_base /\ IXLen ixp = inode_blocks /\
              data_bitmaps <> 0 /\ inode_bitmaps <> 0 /\
              data_bitmaps <= valulen * valulen /\
             inode_bitmaps <= valulen * valulen
           ]]
    POST:hm' RET:ms'  exists m' n frees freeinodes freeinode_pred,
           LOG.rep lxp F (LOG.ActiveTxn m0 m') (MSLL ms') hm' *
           [[[ m' ::: (Fm * rep bxps ixp (repeat bfile0 n) (repeat INODE.inode0 n) frees * 
                            @IAlloc.rep bfile ibxp freeinodes freeinode_pred) ]]] *
           [[ n = ((IXLen ixp) * INODE.IRecSig.items_per_val)%nat /\ n > 1 ]] *
           [[ forall dl, length dl = n -> arrayN (@ptsto _ _ _) 0 dl =p=> freeinode_pred ]]
    CRASH:hm'  LOG.intact lxp F m0 hm'
    >} init lxp bxps ibxp ixp ms.
  Proof.
    unfold init, rep.

    (* BALLOC.init_nofree *)
    prestep. norm. cancel.
    intuition simpl. pred_apply.

    (* now we need to split the LHS several times to get the correct layout *)
    erewrite arrayN_split at 1; repeat rewrite Nat.add_0_l.
    (* data alloc2 is the last chunk *)
    apply sep_star_assoc.
    omega. omega.
    rewrite skipn_length; omega.

    (* BALLOC.init *)
    prestep. norm. cancel.
    intuition simpl. pred_apply.
    erewrite arrayN_split at 1; repeat rewrite Nat.add_0_l.
    erewrite arrayN_split with (i := (BmapNBlocks bxps_1) * valulen) at 1; repeat rewrite Nat.add_0_l.
    (* data region is the first chunk, and data alloc1 is the last chunk *)
    eassign(BmapStart bxps_1); cancel.
    omega.
    rewrite skipn_length.
    rewrite firstn_length_l; omega.
    repeat rewrite firstn_firstn.
    repeat rewrite Nat.min_l; try omega.
    rewrite firstn_length_l; omega.

    (* IAlloc.init *)
    prestep. norm. cancel.
    intuition simpl. pred_apply.
    erewrite arrayN_split at 1; repeat rewrite Nat.add_0_l.
    (* inode region is the first chunk, and inode alloc is the second chunk *)
    substl (IAlloc.Sig.BMPStart ibxp).
    eassign (IAlloc.Sig.BMPLen ibxp * valulen / INODE.IRecSig.items_per_val).
    cancel.

    denote (IAlloc.Sig.BMPStart) as Hx; contradict Hx.
    substl (IAlloc.Sig.BMPStart ibxp); intro.
    eapply add_nonzero_exfalso_helper2; eauto.
    rewrite skipn_skipn, firstn_firstn.
    rewrite Nat.min_l, skipn_length by omega.
    rewrite firstn_length_l by omega.
    omega.

    (* Inode.init *)
    prestep. norm. cancel.
    intuition simpl. pred_apply.
    substl (IXStart ixp); cancel.

    rewrite firstn_firstn, firstn_length, skipn_length, firstn_length.
    repeat rewrite Nat.min_l with (n := (BmapStart bxps_1)) by omega.
    rewrite Nat.min_l; omega.
    denote (IXStart ixp) as Hx; contradict Hx.
    substl (IXStart ixp); intro.
    eapply add_nonzero_exfalso_helper2 with (b := 0).
    rewrite Nat.add_0_r; eauto.
    auto.

    (* shuffle_allocs *)
    step.

    (* post condition *)
    prestep; unfold IAlloc.rep; cancel.
    apply file_match_init_ok.
    substl (IXLen ixp).

    apply Rounding.div_lt_mul_lt; auto.
    rewrite Nat.div_small.
    apply Nat.div_str_pos; split.
    apply INODE.IRec.Defs.items_per_val_gt_0.
    rewrite Nat.mul_comm.
    apply Rounding.div_le_mul; try omega.
    cbv; omega.
    unfold INODE.IRecSig.items_per_val.
    rewrite valulen_is.
    compute; omega.

    denote (_ =p=> freepred) as Hx; apply Hx.
    substl (length dl); substl (IXLen ixp).
    apply Rounding.mul_div; auto.
    apply Nat.mod_divide; auto.
    apply Nat.divide_mul_r.
    unfold INODE.IRecSig.items_per_val.
    apply Nat.mod_divide; auto.
    rewrite valulen_is.
    compute; auto.

    all: auto; cancel.
    Unshelve. eauto.
  Qed.

  Theorem getlen_ok : forall lxp bxps ixp inum ms,
    {< F Fm Fi m0 m f flist ilist frees,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms) hm *
           [[[ m ::: (Fm * rep bxps ixp flist ilist frees) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]]
    POST:hm' RET:^(ms',r)
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms') hm' *
           [[ r = length (BFData f) /\ MSAlloc ms = MSAlloc ms' ]]
    CRASH:hm'  exists ms',
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms') hm'
    >} getlen lxp ixp inum ms.
  Proof.
    unfold getlen, rep.
    safestep.
    sepauto.

    safestep.
    extract; seprewrite; subst.
    denote (_ (list2nmem m)) as Hx.
    setoid_rewrite listmatch_length_pimpl in Hx at 2.
    destruct_lift Hx; eauto.
    simplen.

    cancel.
    eauto.
    Unshelve. all: eauto.
  Qed.

  Theorem getattrs_ok : forall lxp bxp ixp inum ms,
    {< F Fm Fi m0 m flist ilist frees f,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms) hm *
           [[[ m ::: (Fm * rep bxp ixp flist ilist frees) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]]
    POST:hm' RET:^(ms',r)
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms') hm' *
           [[ r = BFAttr f /\ MSAlloc ms = MSAlloc ms' ]]
    CRASH:hm'  exists ms',
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms') hm'
    >} getattrs lxp ixp inum ms.
  Proof.
    unfold getattrs, rep.
    safestep.
    sepauto.

    safestep.
    extract; seprewrite.
    subst; eauto.

    cancel.
    eauto.
  Qed.

  Definition treeseq_ilist_safe inum ilist1 ilist2 :=
    (forall off bn,
        block_belong_to_file ilist1 bn inum off ->
        block_belong_to_file ilist2 bn inum off) /\
    (forall i def,
        (inum <> i /\ i < Datatypes.length ilist1) -> selN ilist1 i def = selN ilist2 i def).

  Theorem setattrs_ok : forall lxp bxps ixp inum a ms,
    {< F Fm Ff m0 m flist ilist frees f,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms) hm *
           [[[ m ::: (Fm * rep bxps ixp flist ilist frees) ]]] *
           [[[ flist ::: (Ff * inum |-> f) ]]] 
    POST:hm' RET:ms'  exists m' flist' f' ilist',
           LOG.rep lxp F (LOG.ActiveTxn m0 m') (MSLL ms') hm' *
           [[[ m' ::: (Fm * rep bxps ixp flist' ilist' frees) ]]] *
           [[[ flist' ::: (Ff * inum |-> f') ]]] *
           [[ f' = mk_bfile (BFData f) a ]] *
           [[ MSAlloc ms = MSAlloc ms' /\
              let free := pick_balloc frees (MSAlloc ms') in
              ilist_safe ilist free ilist' free ]] *
           [[ treeseq_ilist_safe inum ilist ilist' ]]
    CRASH:hm'  LOG.intact lxp F m0 hm'
    >} setattrs lxp ixp inum a ms.
  Proof.
    unfold setattrs, rep.
    safestep.
    sepauto.
    safestep.
    repeat extract. seprewrite.
    2: sepauto.
    2: eauto.
    eapply listmatch_updN_selN; try omega.
    unfold file_match; cancel.

    denote (list2nmem m') as Hm'.
    rewrite listmatch_length_pimpl in Hm'; destruct_lift Hm'.
    denote (list2nmem ilist') as Hilist'.
    assert (inum < length ilist) by simplen'.
    apply arrayN_except_upd in Hilist'; eauto.
    apply list2nmem_array_eq in Hilist'; subst.
    unfold ilist_safe; intuition. left.
    destruct (addr_eq_dec inum inum0); subst.
    - unfold block_belong_to_file in *; intuition.
      all: erewrite selN_updN_eq in * by eauto; simpl; eauto.
    - unfold block_belong_to_file in *; intuition.
      all: erewrite selN_updN_ne in * by eauto; simpl; eauto.
    - unfold treeseq_ilist_safe.
      split.
      intros.
      unfold block_belong_to_file in *.
      intuition.
      eapply list2nmem_sel in H12 as H12'.
      rewrite <- H12'; eauto.
      eapply list2nmem_sel in H12 as H12'.
      rewrite <- H12'; eauto.

      intuition.
      assert (inum < length ilist) by simplen'.
      apply arrayN_except_upd in H12; auto.
      apply list2nmem_array_eq in H12; subst.
      rewrite selN_updN_ne; auto.
  Qed.

  Theorem updattr_ok : forall lxp bxps ixp inum kv ms,
    {< F Fm Fi m0 m flist ilist frees f,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms) hm *
           [[[ m ::: (Fm * rep bxps ixp flist ilist frees) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]]
    POST:hm' RET:ms'  exists m' flist' ilist' f',
           LOG.rep lxp F (LOG.ActiveTxn m0 m') (MSLL ms') hm' *
           [[[ m' ::: (Fm * rep bxps ixp flist' ilist' frees) ]]] *
           [[[ flist' ::: (Fi * inum |-> f') ]]] *
           [[ f' = mk_bfile (BFData f) (INODE.iattr_upd (BFAttr f) kv) ]] *
           [[ MSAlloc ms = MSAlloc ms' /\
              let free := pick_balloc frees (MSAlloc ms') in
              ilist_safe ilist free ilist' free ]]
    CRASH:hm'  LOG.intact lxp F m0 hm'
    >} updattr lxp ixp inum kv ms.
  Proof.
    unfold updattr, rep.
    step.
    sepauto.

    safestep.
    repeat extract. seprewrite.
    2: sepauto.
    2: eauto.
    eapply listmatch_updN_selN; try omega.
    unfold file_match; cancel.

    denote (list2nmem m') as Hm'.
    rewrite listmatch_length_pimpl in Hm'; destruct_lift Hm'.
    denote (list2nmem ilist') as Hilist'.
    assert (inum < length ilist) by simplen'.
    apply arrayN_except_upd in Hilist'; eauto.
    apply list2nmem_array_eq in Hilist'; subst.
    unfold ilist_safe; intuition. left.
    destruct (addr_eq_dec inum inum0); subst.
    - unfold block_belong_to_file in *; intuition.
      all: erewrite selN_updN_eq in * by eauto; simpl; eauto.
    - unfold block_belong_to_file in *; intuition.
      all: erewrite selN_updN_ne in * by eauto; simpl; eauto.
  Qed.

  Theorem read_ok : forall lxp bxp ixp inum off ms,
    {< F Fm Fi Fd m0 m flist ilist frees f vs,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms) hm *
           [[ off < length (BFData f) ]] *
           [[[ m ::: (Fm * rep bxp ixp flist ilist frees) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]] *
           [[[ (BFData f) ::: (Fd * off |-> vs) ]]]
    POST:hm' RET:^(ms', r)
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms') hm' *
           [[ r = fst vs /\ MSAlloc ms = MSAlloc ms' ]]
    CRASH:hm'  exists ms',
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms') hm'
    >} read lxp ixp inum off ms.
  Proof.
    unfold read, rep.
    prestep; norml.
    extract; seprewrite; subst.
    denote (_ (list2nmem m)) as Hx.
    setoid_rewrite listmatch_length_pimpl in Hx at 2.
    rewrite map_length in *.
    destruct_lift Hx.
    safecancel.
    eauto.

    sepauto.
    denote (_ (list2nmem m)) as Hx.
    setoid_rewrite listmatch_extract with (i := off) in Hx at 2; try omega.
    destruct_lift Hx; filldef.
    safestep.
    erewrite selN_map by omega; filldef.
    setoid_rewrite surjective_pairing at 1.
    cancel.
    step.
    cancel; eauto.
    cancel; eauto.
    Unshelve. all: eauto.
  Qed.


  Theorem write_ok : forall lxp bxp ixp inum off v ms,
    {< F Fm Fi Fd m0 m flist ilist frees f vs0,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms) hm *
           [[ off < length (BFData f) ]] *
           [[[ m ::: (Fm * rep bxp ixp flist ilist frees) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]] *
           [[[ (BFData f) ::: (Fd * off |-> vs0) ]]]
    POST:hm' RET:ms'  exists m' flist' f',
           LOG.rep lxp F (LOG.ActiveTxn m0 m') (MSLL ms') hm' *
           [[[ m' ::: (Fm * rep bxp ixp flist' ilist frees) ]]] *
           [[[ flist' ::: (Fi * inum |-> f') ]]] *
           [[[ (BFData f') ::: (Fd * off |-> (v, nil)) ]]] *
           [[ f' = mk_bfile (updN (BFData f) off (v, nil)) (BFAttr f) ]] *
           [[ MSAlloc ms = MSAlloc ms' ]]
    CRASH:hm'  LOG.intact lxp F m0 hm'
    >} write lxp ixp inum off v ms.
  Proof.
    unfold write, rep.
    prestep; norml.
    extract; seprewrite; subst.
    denote (_ (list2nmem m)) as Hx.
    setoid_rewrite listmatch_length_pimpl in Hx at 2.
    rewrite map_length in *.
    destruct_lift Hx; safecancel.
    eauto.
    sepauto.

    denote (_ (list2nmem m)) as Hx.
    setoid_rewrite listmatch_extract with (i := off) in Hx at 2; try omega.
    destruct_lift Hx; filldef.
    step.

    setoid_rewrite INODE.inode_rep_bn_nonzero_pimpl in H.
    destruct_lift H; denote (_ <> 0) as Hx; subst.
    eapply Hx; eauto; omega.
    erewrite selN_map by omega; filldef.
    setoid_rewrite surjective_pairing at 2.
    cancel.

    safestep; [ | sepauto .. ].
    setoid_rewrite <- updN_selN_eq with (l := ilist) (ix := inum) at 4.
    rewrite listmatch_updN_removeN by omega.
    unfold file_match at 3; cancel; eauto.
    setoid_rewrite <- updN_selN_eq with (ix := off) at 15.
    rewrite listmatch_updN_removeN by omega.
    erewrite selN_map by omega; filldef.
    cancel.
    sepauto.

    pimpl_crash; cancel; auto.
    Grab Existential Variables.
    all: try exact unit; eauto using tt.
  Qed.

  Lemma grow_treeseq_ilist_safe: forall (ilist: list INODE.inode) ilist' inum a,
    inum < Datatypes.length ilist ->
    (arrayN_ex (ptsto (V:=INODE.inode)) ilist inum
     ✶ inum
       |-> {|
           INODE.IBlocks := INODE.IBlocks (selN ilist inum INODE.inode0) ++ [$ (a)];
           INODE.IAttr := INODE.IAttr (selN ilist inum INODE.inode0) |})%pred (list2nmem ilist') ->
    treeseq_ilist_safe inum ilist ilist'.
  Proof.
    intros.
    unfold treeseq_ilist_safe, block_belong_to_file.
    apply arrayN_except_upd in H0 as Hselupd; auto.
    apply list2nmem_array_eq in Hselupd; subst.
    split. 
    intros.
    split.
    erewrite selN_updN_eq; simpl.
    erewrite app_length.
    omega.
    simplen'.
    intuition.
    erewrite selN_updN_eq; simpl.
    erewrite selN_app; eauto.
    simplen'.
    intros.
    erewrite selN_updN_ne; eauto.
    intuition.
  Qed.


  Theorem grow_ok : forall lxp bxp ixp inum v ms,
    {< F Fm Fi Fd m0 m flist ilist frees f,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms) hm *
           [[[ m ::: (Fm * rep bxp ixp flist ilist frees) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]] *
           [[[ (BFData f) ::: Fd ]]]
    POST:hm' RET:^(ms', r) [[ MSAlloc ms = MSAlloc ms' ]] * exists m',
           [[ isError r ]] * LOG.rep lxp F (LOG.ActiveTxn m0 m') (MSLL ms') hm' \/
           [[ r = OK tt  ]] * exists flist' ilist' frees' f',
           LOG.rep lxp F (LOG.ActiveTxn m0 m') (MSLL ms') hm' *
           [[[ m' ::: (Fm * rep bxp ixp flist' ilist' frees') ]]] *
           [[[ flist' ::: (Fi * inum |-> f') ]]] *
           [[[ (BFData f') ::: (Fd * (length (BFData f)) |-> (v, nil)) ]]] *
           [[ f' = mk_bfile ((BFData f) ++ [(v, nil)]) (BFAttr f) ]] *
           [[ ilist_safe ilist  (pick_balloc frees  (MSAlloc ms'))
                         ilist' (pick_balloc frees' (MSAlloc ms')) ]] *
           [[ treeseq_ilist_safe inum ilist ilist' ]]
    CRASH:hm'  LOG.intact lxp F m0 hm'
    >} grow lxp bxp ixp inum v ms.
  Proof.
    unfold grow, rep.
    prestep; norml.
    extract; seprewrite; subst.
    denote removeN as Hx.
    setoid_rewrite listmatch_length_pimpl in Hx at 2.
    rewrite map_length in *.
    destruct_lift Hx; safecancel.
    eauto.

    sepauto.
    step.

    (* file size ok, do allocation *)
    destruct (MSAlloc ms); simpl.
    - step.
      safestep.
      sepauto.
      step.

      eapply BALLOC.bn_valid_facts; eauto.
      step.

      or_r; cancel.
      2: sepauto.
      seprewrite.
      rewrite listmatch_updN_removeN by simplen.
      unfold file_match; cancel.
      rewrite map_app; simpl.
      rewrite <- listmatch_app_tail.
      cancel.
      rewrite map_length; omega.
      rewrite wordToNat_natToWord_idempotent'; auto.
      eapply BALLOC.bn_valid_goodSize; eauto.
      apply list2nmem_app; eauto.

      2: eapply grow_treeseq_ilist_safe in H24; eauto.

      2: cancel.
      2: or_l; cancel.

      denote (list2nmem ilist') as Hilist'.
      assert (inum < length ilist) by simplen'.
      apply arrayN_except_upd in Hilist'; eauto.
      apply list2nmem_array_eq in Hilist'; subst.
      unfold ilist_safe; intuition.
      eapply incl_tran; eauto. eapply incl_remove.
      destruct (addr_eq_dec inum inum0); subst.
      + unfold block_belong_to_file in *; intuition.
        all: erewrite selN_updN_eq in * by eauto; simpl in *; eauto.
        destruct (addr_eq_dec off (length (INODE.IBlocks (selN ilist inum0 INODE.inode0)))).
        * right.
          rewrite selN_last in * by auto.
          subst. rewrite wordToNat_natToWord_idempotent'. eauto.
          eapply BALLOC.bn_valid_goodSize; eauto.
        * left.
          rewrite app_length in *; simpl in *.
          split. omega.
          subst. rewrite selN_app1 by omega. auto.
      + unfold block_belong_to_file in *; intuition.
        all: erewrite selN_updN_ne in * by eauto; simpl; eauto.

    - step.
      safestep.
      erewrite INODE.rep_bxp_switch by eassumption. cancel.
      sepauto.

      step.
      eapply BALLOC.bn_valid_facts; eauto.
      step.

      or_r; cancel.
      erewrite INODE.rep_bxp_switch by ( apply eq_sym; eassumption ). cancel.
      2: sepauto.
      seprewrite.
      rewrite listmatch_updN_removeN by simplen.
      unfold file_match; cancel.
      rewrite map_app; simpl.
      rewrite <- listmatch_app_tail.
      cancel.
      rewrite map_length; omega.
      rewrite wordToNat_natToWord_idempotent'; auto.
      eapply BALLOC.bn_valid_goodSize; eauto.
      apply list2nmem_app; eauto.

      2: eapply grow_treeseq_ilist_safe in H24; eauto.

      2: cancel.
      2: or_l; cancel.

      denote (list2nmem ilist') as Hilist'.
      assert (inum < length ilist) by simplen'.
      apply arrayN_except_upd in Hilist'; eauto.
      apply list2nmem_array_eq in Hilist'; subst.
      unfold ilist_safe; intuition.
      eapply incl_tran; eauto. eapply incl_remove.
      destruct (addr_eq_dec inum inum0); subst.
      + unfold block_belong_to_file in *; intuition.
        all: erewrite selN_updN_eq in * by eauto; simpl in *; eauto.
        destruct (addr_eq_dec off (length (INODE.IBlocks (selN ilist inum0 INODE.inode0)))).
        * right.
          rewrite selN_last in * by auto.
          subst. rewrite wordToNat_natToWord_idempotent'. eauto.
          eapply BALLOC.bn_valid_goodSize; eauto.
        * left.
          rewrite app_length in *; simpl in *.
          split. omega.
          subst. rewrite selN_app1 by omega. auto.
      + unfold block_belong_to_file in *; intuition.
        all: erewrite selN_updN_ne in * by eauto; simpl; eauto.

    - step.
    - cancel; eauto.

    Unshelve. all: easy.
  Qed.

  Local Hint Extern 0 (okToUnify (listmatch _ _ _) (listmatch _ _ _)) => constructor : okToUnify.


  Theorem shrink_ok : forall lxp bxp ixp inum nr ms,
    {< F Fm Fi m0 m flist ilist frees f,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms) hm *
           [[[ m ::: (Fm * rep bxp ixp flist ilist frees) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]]
    POST:hm' RET:ms'  exists m' flist' f' ilist' frees',
           LOG.rep lxp F (LOG.ActiveTxn m0 m') (MSLL ms') hm' *
           [[[ m' ::: (Fm * rep bxp ixp flist' ilist' frees') ]]] *
           [[[ flist' ::: (Fi * inum |-> f') ]]] *
           [[ f' = mk_bfile (firstn ((length (BFData f)) - nr) (BFData f)) (BFAttr f) ]] *
           [[ MSAlloc ms = MSAlloc ms' /\
              ilist_safe ilist  (pick_balloc frees  (MSAlloc ms'))
                         ilist' (pick_balloc frees' (MSAlloc ms')) ]]
    CRASH:hm'  LOG.intact lxp F m0 hm'
    >} shrink lxp bxp ixp inum nr ms.
  Proof.
    unfold shrink, rep.
    step.
    sepauto.
    extract; seprewrite; subst; denote removeN as Hx.
    setoid_rewrite listmatch_length_pimpl in Hx at 2.
    rewrite map_length in *.

    destruct (MSAlloc ms); simpl.
    - step.
      erewrite INODE.rep_bxp_switch in Hx by eassumption.
      rewrite INODE.inode_rep_bn_valid_piff in Hx; destruct_lift Hx.
      denote Forall as Hv; specialize (Hv inum); subst.
      rewrite <- Forall_map.
      apply forall_skipn; apply Hv; eauto.
      erewrite <- listmatch_ptsto_listpred.
      setoid_rewrite listmatch_split at 2.
      rewrite skipn_map_comm; cancel.
      destruct_lift Hx; denote (length (BFData _)) as Heq.

      step.
      erewrite INODE.rep_bxp_switch by eassumption. cancel.
      sepauto.
      denote listmatch as Hx.
      setoid_rewrite listmatch_length_pimpl in Hx at 2.
      prestep; norm. cancel. intuition simpl.
      2: sepauto.
      pred_apply; cancel.
      erewrite INODE.rep_bxp_switch by ( apply eq_sym; eassumption ). cancel.
      seprewrite.
      rewrite listmatch_updN_removeN by omega.
      rewrite firstn_map_comm, Heq.
      unfold file_match, cuttail; cancel; eauto.
      2: eauto.

      denote (list2nmem ilist') as Hilist'.
      assert (inum < length ilist) by simplen.
      apply arrayN_except_upd in Hilist'; eauto.
      apply list2nmem_array_eq in Hilist'; subst.
      unfold ilist_safe; intuition. left.
      destruct (addr_eq_dec inum inum0); subst.
      + unfold block_belong_to_file in *; intuition simpl.
        all: erewrite selN_updN_eq in * by eauto; simpl in *; eauto.
        rewrite cuttail_length in *. omega.
        rewrite selN_cuttail in *; auto.
      + unfold block_belong_to_file in *; intuition simpl.
        all: erewrite selN_updN_ne in * by eauto; simpl; eauto.

    - step.
      erewrite <- BALLOC.bn_valid_switch; eauto.
      rewrite INODE.inode_rep_bn_valid_piff in Hx; destruct_lift Hx.
      denote Forall as Hv; specialize (Hv inum); subst.
      rewrite <- Forall_map.
      apply forall_skipn; apply Hv; eauto.

      erewrite <- listmatch_ptsto_listpred.
      setoid_rewrite listmatch_split at 2.
      rewrite skipn_map_comm; cancel.
      destruct_lift Hx; denote (length (BFData _)) as Heq.

      step.
      sepauto.
      denote listmatch as Hx.
      setoid_rewrite listmatch_length_pimpl in Hx at 2.
      prestep; norm. cancel. intuition simpl.
      2: sepauto.
      pred_apply; cancel.
      cancel.
      seprewrite.
      rewrite listmatch_updN_removeN by omega.
      rewrite firstn_map_comm, Heq.
      unfold file_match, cuttail; cancel; eauto.
      2: eauto.

      denote (list2nmem ilist') as Hilist'.
      assert (inum < length ilist) by simplen.
      apply arrayN_except_upd in Hilist'; eauto.
      apply list2nmem_array_eq in Hilist'; subst.
      unfold ilist_safe; intuition. left.
      destruct (addr_eq_dec inum inum0); subst.
      + unfold block_belong_to_file in *; intuition simpl.
        all: erewrite selN_updN_eq in * by eauto; simpl in *; eauto.
        rewrite cuttail_length in *. omega.
        rewrite selN_cuttail in *; auto.
      + unfold block_belong_to_file in *; intuition simpl.
        all: erewrite selN_updN_ne in * by eauto; simpl; eauto.

    Unshelve. easy. all: try exact bfile0.
  Qed.

  Theorem sync_ok : forall lxp ixp ms,
    {< F ds,
    PRE:hm
      LOG.rep lxp F (LOG.NoTxn ds) (MSLL ms) hm *
      [[ sync_invariant F ]]
    POST:hm' RET:ms'
      LOG.rep lxp F (LOG.NoTxn (ds!!, nil)) (MSLL ms') hm' *
      [[ MSAlloc ms' = negb (MSAlloc ms) ]]
    XCRASH:hm'
      LOG.recover_any lxp F ds hm'
    >} sync lxp ixp ms.
  Proof.
    unfold sync, rep.
    step.
    step.
  Qed.

  Theorem sync_noop_ok : forall lxp ixp ms,
    {< F ds,
    PRE:hm
      LOG.rep lxp F (LOG.NoTxn ds) (MSLL ms) hm *
      [[ sync_invariant F ]]
    POST:hm' RET:ms'
      LOG.rep lxp F (LOG.NoTxn ds) (MSLL ms') hm' *
      [[ MSAlloc ms' = negb (MSAlloc ms) ]]
    XCRASH:hm'
      LOG.recover_any lxp F ds hm'
    >} sync_noop lxp ixp ms.
  Proof.
    unfold sync_noop, rep.
    step.
    step.
  Qed.

  Lemma block_belong_to_file_off_ok : forall Fm Fi bxp ixp flist ilist frees inum off f m,
    (Fm * rep bxp ixp flist ilist frees)%pred m ->
    (Fi * inum |-> f)%pred (list2nmem flist) ->
    off < Datatypes.length (BFData f) -> 
    block_belong_to_file ilist # (selN (INODE.IBlocks (selN ilist inum INODE.inode0)) off $0) inum off.
  Proof.
    unfold block_belong_to_file; intros; split; auto.
    unfold rep, INODE.rep in H; destruct_lift H.
    extract. destruct_lift H.
    setoid_rewrite listmatch_extract with (i := inum) in H at 2.
    unfold file_match in H at 2; destruct_lift H.
    setoid_rewrite listmatch_extract with (i := off) in H at 3.
    destruct_lift H.
    rewrite map_length in *.
    rewrite <- H7. simplen. simplen. simplen.
    Unshelve. eauto.
  Qed.

  Lemma block_belong_to_file_ok : forall Fm Fi Fd bxp ixp flist ilist frees inum off f vs m,
    (Fm * rep bxp ixp flist ilist frees)%pred m ->
    (Fi * inum |-> f)%pred (list2nmem flist) ->
    (Fd * off |-> vs)%pred (list2nmem (BFData f)) ->
    block_belong_to_file ilist # (selN (INODE.IBlocks (selN ilist inum INODE.inode0)) off $0) inum off.
  Proof.
    intros.
    eapply list2nmem_inbound in H1.
    eapply block_belong_to_file_off_ok; eauto.
  Qed.

  Definition diskset_was (ds0 ds : diskset) := ds0 = ds \/ ds0 = (ds!!, nil).

  Theorem d_in_diskset_was : forall d ds ds',
    d_in d ds ->
    diskset_was ds ds' ->
    d_in d ds'.
  Proof.
    intros.
    inversion H0; subst; eauto.
    inversion H; simpl in *; intuition; subst.
    apply latest_in_ds.
  Qed.

  Theorem dwrite_ok : forall lxp bxp ixp inum off v ms,
    {< F Fm Fi Fd ds flist ilist frees f vs,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn ds ds!!) (MSLL ms) hm *
           [[ off < length (BFData f) ]] *
           [[[ ds!! ::: (Fm  * rep bxp ixp flist ilist frees) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]] *
           [[[ (BFData f) ::: (Fd * off |-> vs) ]]] *
           [[ sync_invariant F ]]
    POST:hm' RET:ms'  exists flist' f' bn ds',
           LOG.rep lxp F (LOG.ActiveTxn ds' ds'!!) (MSLL ms') hm' *
           [[ ds' = dsupd ds bn (v, vsmerge vs) ]] *
           [[ block_belong_to_file ilist bn inum off ]] *
           [[ MSAlloc ms = MSAlloc ms' ]] *
           (* spec about files on the latest diskset *)
           [[[ ds'!! ::: (Fm  * rep bxp ixp flist' ilist frees) ]]] *
           [[[ flist' ::: (Fi * inum |-> f') ]]] *
           [[[ (BFData f') ::: (Fd * off |-> (v, vsmerge vs)) ]]] *
           [[ f' = mk_bfile (updN (BFData f) off (v, vsmerge vs)) (BFAttr f) ]]
    XCRASH:hm'
           LOG.recover_any lxp F ds hm' \/
           exists bn, [[ block_belong_to_file ilist bn inum off ]] *
           LOG.recover_any lxp F (dsupd ds bn (v, vsmerge vs)) hm'
    >} dwrite lxp ixp inum off v ms.
  Proof.
    unfold dwrite.
    prestep; norml.
    denote  (list2nmem ds !!) as Hz.
    eapply block_belong_to_file_ok in Hz as Hb; eauto.
    unfold rep in *; destruct_lift Hz.
    extract; seprewrite; subst.
    denote removeN as Hx.
    setoid_rewrite listmatch_length_pimpl in Hx at 2.
    rewrite map_length in *.
    destruct_lift Hx; cancel; eauto.

    sepauto.
    denote removeN as Hx.
    setoid_rewrite listmatch_extract with (i := off) (bd := 0) in Hx; try omega.
    destruct_lift Hx.

    step.
    erewrite selN_map by omega; filldef.
    setoid_rewrite surjective_pairing at 2. cancel.

    prestep. norm. cancel.
    intuition simpl.
    2: sepauto. 2: sepauto.
    pred_apply; cancel.
    setoid_rewrite <- updN_selN_eq with (l := ilist) (ix := inum) at 4.
    rewrite listmatch_updN_removeN by omega.
    unfold file_match at 3; cancel; eauto.
    setoid_rewrite <- updN_selN_eq with (l := INODE.IBlocks _) (ix := off) at 3.
    erewrite map_updN by omega; filldef.
    rewrite listmatch_updN_removeN by omega.
    cancel.
    eauto.
    cancel.

    repeat xcrash_rewrite.
    xform_norm; xform_normr.
    cancel.

    or_r; cancel.
    xform_norm; cancel.

    cancel.
    xcrash.
    or_l; rewrite LOG.active_intact, LOG.intact_any; auto.

    Unshelve. all: easy.
  Qed.


  Lemma synced_list_map_fst_map : forall (vsl : list valuset),
    synced_list (map fst vsl) = map (fun x => (fst x, nil)) vsl.
  Proof.
    unfold synced_list; induction vsl; simpl; auto.
    f_equal; auto.
  Qed.

  Theorem datasync_ok : forall lxp bxp ixp inum ms,
    {< F Fm Fi ds flist ilist free f,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn ds ds!!) (MSLL ms) hm *
           [[[ ds!!  ::: (Fm  * rep bxp ixp flist ilist free) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]] *
           [[ sync_invariant F ]]
    POST:hm' RET:ms'  exists ds' flist' al,
           LOG.rep lxp F (LOG.ActiveTxn ds' ds'!!) (MSLL ms') hm' *
           [[ ds' = dssync_vecs ds al ]] *
           [[[ ds'!! ::: (Fm * rep bxp ixp flist' ilist free) ]]] *
           [[[ flist' ::: (Fi * inum |-> synced_file f) ]]] *
           [[ MSAlloc ms = MSAlloc ms' ]] *
           [[ length al = length (BFILE.BFData f) /\ forall i, i < length al ->
              BFILE.block_belong_to_file ilist (selN al i 0) inum i ]]
    CRASH:hm' LOG.recover_any lxp F ds hm'
    >} datasync lxp ixp inum ms.
  Proof.
    unfold datasync, synced_file, rep.
    step.
    sepauto.

    extract.
    step.
    prestep. norm. cancel.
    intuition simpl. pred_apply.
    2: sepauto.

    cancel.
    setoid_rewrite <- updN_selN_eq with (l := ilist) (ix := inum) at 3.
    rewrite listmatch_updN_removeN by simplen.
    unfold file_match; cancel; eauto.
    rewrite synced_list_map_fst_map.
    rewrite listmatch_map_l; sepauto.
    sepauto.

    seprewrite; apply eq_sym.
    eapply listmatch_length_r with (m := list2nmem ds!!).
    pred_apply; cancel.
    erewrite selN_map by simplen.
    eapply block_belong_to_file_ok with (m := list2nmem ds!!); eauto.
    eassign (bxp_1, bxp_2); pred_apply; unfold rep, file_match.
    setoid_rewrite listmatch_isolate with (i := inum) at 3.
    repeat erewrite fst_pair by eauto.
    cancel. simplen. simplen.
    apply list2nmem_ptsto_cancel.
    seprewrite.
    erewrite listmatch_length_r with (m := list2nmem ds!!); eauto.
    auto.

    rewrite LOG.active_intact, LOG.intact_any; auto.
    Unshelve. all: exact ($0, nil).
  Qed.


  Hint Extern 1 ({{_}} Bind (init _ _ _ _ _) _) => apply init_ok : prog.
  Hint Extern 1 ({{_}} Bind (getlen _ _ _ _) _) => apply getlen_ok : prog.
  Hint Extern 1 ({{_}} Bind (getattrs _ _ _ _) _) => apply getattrs_ok : prog.
  Hint Extern 1 ({{_}} Bind (setattrs _ _ _ _ _) _) => apply setattrs_ok : prog.
  Hint Extern 1 ({{_}} Bind (updattr _ _ _ _ _) _) => apply updattr_ok : prog.
  Hint Extern 1 ({{_}} Bind (read _ _ _ _ _) _) => apply read_ok : prog.
  Hint Extern 1 ({{_}} Bind (write _ _ _ _ _ _) _) => apply write_ok : prog.
  Hint Extern 1 ({{_}} Bind (dwrite _ _ _ _ _ _) _) => apply dwrite_ok : prog.
  Hint Extern 1 ({{_}} Bind (grow _ _ _ _ _ _) _) => apply grow_ok : prog.
  Hint Extern 1 ({{_}} Bind (shrink _ _ _ _ _ _) _) => apply shrink_ok : prog.
  Hint Extern 1 ({{_}} Bind (datasync _ _ _ _) _) => apply datasync_ok : prog.
  Hint Extern 1 ({{_}} Bind (sync _ _ _) _) => apply sync_ok : prog.
  Hint Extern 1 ({{_}} Bind (sync_noop _ _ _) _) => apply sync_noop_ok : prog.
  Hint Extern 0 (okToUnify (rep _ _ _ _ _) (rep _ _ _ _ _)) => constructor : okToUnify.


  Definition read_array lxp ixp inum a i ms :=
    let^ (ms, r) <- read lxp ixp inum (a + i) ms;
    Ret ^(ms, r).

  Definition write_array lxp ixp inum a i v ms :=
    ms <- write lxp ixp inum (a + i) v ms;
    Ret ms.

  Theorem read_array_ok : forall lxp bxp ixp inum a i ms,
    {< F Fm Fi Fd m0 m flist ilist free f vsl,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms) hm *
           [[[ m ::: (Fm * rep bxp ixp flist ilist free) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]] *
           [[[ (BFData f) ::: Fd * arrayN (@ptsto _ addr_eq_dec _) a vsl ]]] *
           [[ i < length vsl]]
    POST:hm' RET:^(ms', r)
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms') hm' *
           [[ r = fst (selN vsl i ($0, nil)) /\ MSAlloc ms = MSAlloc ms' ]]
    CRASH:hm'  exists ms',
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms') hm'
    >} read_array lxp ixp inum a i ms.
  Proof.
    unfold read_array.
    hoare.

    denote (arrayN _ a vsl) as Hx.
    destruct (list2nmem_arrayN_bound vsl _ Hx); subst; simpl in *; omega.
    rewrite isolateN_fwd with (i:=i) by auto.
    cancel.
    Unshelve. eauto.
  Qed.


  Theorem write_array_ok : forall lxp bxp ixp inum a i v ms,
    {< F Fm Fi Fd m0 m flist ilist free f vsl,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms) hm *
           [[[ m ::: (Fm * rep bxp ixp flist ilist free) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]] *
           [[[ (BFData f) ::: Fd * arrayN (@ptsto _ addr_eq_dec _) a vsl ]]] *
           [[ i < length vsl]]
    POST:hm' RET:ms' exists m' flist' f',
           LOG.rep lxp F (LOG.ActiveTxn m0 m') (MSLL ms') hm' *
           [[[ m' ::: (Fm * rep bxp ixp flist' ilist free) ]]] *
           [[[ flist' ::: (Fi * inum |-> f') ]]] *
           [[[ (BFData f') ::: Fd * arrayN (@ptsto _ addr_eq_dec _) a (updN vsl i (v, nil)) ]]] *
           [[ f' = mk_bfile (updN (BFData f) (a + i) (v, nil)) (BFAttr f) ]] *
           [[ MSAlloc ms = MSAlloc ms' ]]
    CRASH:hm'  LOG.intact lxp F m0 hm'
    >} write_array lxp ixp inum a i v ms.
  Proof.
    unfold write_array.
    prestep. cancel.
    denote (arrayN _ a vsl) as Hx.
    destruct (list2nmem_arrayN_bound vsl _ Hx); subst; simpl in *; try omega.
    rewrite isolateN_fwd with (i:=i) by auto; filldef; cancel.

    step.
    rewrite <- isolateN_bwd_upd by auto; cancel.
    Unshelve. eauto.
  Qed.


  Hint Extern 1 ({{_}} Bind (read_array _ _ _ _ _ _) _) => apply read_array_ok : prog.
  Hint Extern 1 ({{_}} Bind (write_array _ _ _ _ _ _ _) _) => apply write_array_ok : prog.


  Definition read_range A lxp ixp inum a nr (vfold : A -> valu -> A) v0 ms0 :=
    let^ (ms, r) <- ForN i < nr
    Hashmap hm
    Ghost [ bxp F Fm Fi Fd crash m0 m flist ilist frees f vsl ]
    Loopvar [ ms pf ]
    Invariant
      LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms) hm *
      [[[ m ::: (Fm * rep bxp ixp flist ilist frees) ]]] *
      [[[ flist ::: (Fi * inum |-> f) ]]] *
      [[[ (BFData f) ::: Fd * arrayN (@ptsto _ addr_eq_dec _) a vsl ]]] *
      [[ pf = fold_left vfold (firstn i (map fst vsl)) v0 ]] *
      [[ MSAlloc ms = MSAlloc ms0 ]]
    OnCrash  crash
    Begin
      let^ (ms, v) <- read_array lxp ixp inum a i ms;
      Ret ^(ms, vfold pf v)
    Rof ^(ms0, v0);
    Ret ^(ms, r).


  Theorem read_range_ok : forall A lxp bxp ixp inum a nr (vfold : A -> valu -> A) v0 ms,
    {< F Fm Fi Fd m0 m flist ilist frees f vsl,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms) hm *
           [[[ m ::: (Fm * rep bxp ixp flist ilist frees) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]] *
           [[[ (BFData f) ::: Fd * arrayN (@ptsto _ addr_eq_dec _) a vsl ]]] *
           [[ nr <= length vsl]]
    POST:hm' RET:^(ms', r)
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms') hm' *
           [[ r = fold_left vfold (firstn nr (map fst vsl)) v0 ]] *
           [[ MSAlloc ms = MSAlloc ms' ]]
    CRASH:hm'  exists ms',
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms') hm'
    >} read_range lxp ixp inum a nr vfold v0 ms.
  Proof.
    unfold read_range.
    safestep. eauto.
    step.

    assert (m1 < length vsl).
    denote (arrayN _ a vsl) as Hx.
    destruct (list2nmem_arrayN_bound vsl _ Hx); subst; simpl in *; omega.
    safestep.

    rewrite firstn_S_selN_expand with (def := $0) by (rewrite map_length; auto).
    rewrite fold_left_app; simpl.
    erewrite selN_map; subst; auto.

    safestep.
    cancel.
    erewrite <- LOG.rep_hashmap_subset; eauto.
    Unshelve. all: eauto; exact tt.
  Qed.


  (* like read_range, but stops when cond is true *)
  Definition read_cond A lxp ixp inum (vfold : A -> valu -> A)
                       v0 (cond : A -> bool) ms0 :=
    let^ (ms, nr) <- getlen lxp ixp inum ms0;
    let^ (ms, r, ret) <- ForN i < nr
    Hashmap hm
    Ghost [ bxp F Fm Fi crash m0 m flist f ilist frees ]
    Loopvar [ ms pf ret ]
    Invariant
      LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms) hm *
      [[[ m ::: (Fm * rep bxp ixp flist ilist frees) ]]] *
      [[[ flist ::: (Fi * inum |-> f) ]]] *
      [[ ret = None ->
        pf = fold_left vfold (firstn i (map fst (BFData f))) v0 ]] *
      [[ ret = None ->
        cond pf = false /\ MSAlloc ms = MSAlloc ms0 ]] *
      [[ forall v, ret = Some v ->
        cond v = true ]]
    OnCrash  crash
    Begin
      If (is_some ret) {
        Ret ^(ms, pf, ret)
      } else {
        let^ (ms, v) <- read lxp ixp inum i ms;
        let pf' := vfold pf v in
        If (bool_dec (cond pf') true) {
          Ret ^(ms, pf', Some pf')
        } else {
          Ret ^(ms, pf', None)
        }
      }
    Rof ^(ms, v0, None);
    Ret ^(ms, ret).


  Theorem read_cond_ok : forall A lxp bxp ixp inum (vfold : A -> valu -> A)
                                v0 (cond : A -> bool) ms,
    {< F Fm Fi m0 m flist ilist frees f,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms) hm *
           [[[ m ::: (Fm * rep bxp ixp flist ilist frees) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]] *
           [[ cond v0 = false ]]
    POST:hm' RET:^(ms', r)
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms') hm' *
           [[ MSAlloc ms = MSAlloc ms' ]] *
           ( exists v, 
             [[ r = Some v /\ cond v = true ]] \/
             [[ r = None /\ cond (fold_left vfold (map fst (BFData f)) v0) = false ]])
    CRASH:hm'  exists ms',
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms') hm'
    >} read_cond lxp ixp inum vfold v0 cond ms.
  Proof.
    unfold read_cond.
    prestep. cancel.
    safestep. eauto.
    prestep; norm. cancel. intuition simpl. eauto.
    step.
    admit. (* where does this obligation come from? *)
    sepauto. sepauto.

    destruct a2; safestep.
    admit. (* again crash => something *)
    (* TODO: debug what changed about this proof due to monads.

    Not especially concerning for now given that read_cond is never used. *)
    (*
    pred_apply; cancel.
    safestep.
    or_l; cancel; filldef; eauto.

    safestep.
    rewrite firstn_S_selN_expand with (def := $0) by (rewrite map_length; auto).
    rewrite fold_left_app; simpl.
    erewrite selN_map; subst; auto.
    apply not_true_is_false; auto.

    cancel.
    safestep.
    or_r; cancel.
    denote cond as Hx; rewrite firstn_oob in Hx; auto.
    rewrite map_length; auto.
    cancel.
    apply LOG.rep_hashmap_subset; eauto.

    Unshelve. all: try easy. exact ($0, nil).
    *)
  Admitted.


  Hint Extern 1 ({{_}} Bind (read_range _ _ _ _ _ _ _ _) _) => apply read_range_ok : prog.
  Hint Extern 1 ({{_}} Bind (read_cond _ _ _ _ _ _ _) _) => apply read_cond_ok : prog.


  Definition grown lxp bxp ixp inum l ms0 :=
    let^ (ms, ret) <- ForN i < length l
      Hashmap hm
      Ghost [ F Fm Fi m0 f ilist frees ]
      Loopvar [ ms ret ]
      Invariant
        exists m' flist' ilist' frees' f',
        LOG.rep lxp F (LOG.ActiveTxn m0 m') (MSLL ms) hm *
        [[[ m' ::: (Fm * rep bxp ixp flist' ilist' frees') ]]] *
        [[[ flist' ::: (Fi * inum |-> f') ]]] *
        [[ ret = OK tt ->
          f' = mk_bfile ((BFData f) ++ synced_list (firstn i l)) (BFAttr f) ]] *
        [[ MSAlloc ms = MSAlloc ms0 /\
           ilist_safe ilist (pick_balloc frees (MSAlloc ms)) 
                      ilist' (pick_balloc frees' (MSAlloc ms)) ]]
      OnCrash
        LOG.intact lxp F m0 hm
      Begin
        match ret with
        | Err e => Ret ^(ms, ret)
        | OK _ =>
          let^ (ms, ok) <- grow lxp bxp ixp inum (selN l i $0) ms;
          Ret ^(ms, ok)
        end
      Rof ^(ms0, OK tt);
    Ret ^(ms, ret).



  Definition truncate lxp bxp xp inum newsz ms :=
    let^ (ms, sz) <- getlen lxp xp inum ms;
    If (lt_dec newsz sz) {
      ms <- shrink lxp bxp xp inum (sz - newsz) ms;
      Ret ^(ms, OK tt)
    } else {
      let^ (ms, ok) <- grown lxp bxp xp inum (repeat $0 (newsz - sz))  ms;
      Ret ^(ms, ok)
    }.


  Definition reset lxp bxp xp inum ms :=
    let^ (ms, sz) <- getlen lxp xp inum ms;
    ms <- shrink lxp bxp xp inum sz ms;
    ms <- setattrs lxp xp inum attr0 ms;
    Ret ms.


  Theorem grown_ok : forall lxp bxp ixp inum l ms,
    {< F Fm Fi Fd m0 m flist ilist frees f,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms) hm *
           [[[ m ::: (Fm * rep bxp ixp flist ilist frees) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]] *
           [[[ (BFData f) ::: Fd ]]]
    POST:hm' RET:^(ms', r) [[ MSAlloc ms' = MSAlloc ms ]] * exists m',
           [[ isError r ]] * LOG.rep lxp F (LOG.ActiveTxn m0 m') (MSLL ms') hm' \/
           [[ r = OK tt  ]] * exists flist' ilist' frees' f',
           LOG.rep lxp F (LOG.ActiveTxn m0 m') (MSLL ms') hm' *
           [[[ m' ::: (Fm * rep bxp ixp flist' ilist' frees') ]]] *
           [[[ flist' ::: (Fi * inum |-> f') ]]] *
           [[[ (BFData f') ::: (Fd * arrayN (@ptsto _ addr_eq_dec _) (length (BFData f)) (synced_list l)) ]]] *
           [[ f' = mk_bfile ((BFData f) ++ (synced_list l)) (BFAttr f) ]] *
           [[ ilist_safe ilist (pick_balloc frees (MSAlloc ms')) 
                      ilist' (pick_balloc frees' (MSAlloc ms'))  ]]
    CRASH:hm'  LOG.intact lxp F m0 hm'
    >} grown lxp bxp ixp inum l ms.
  Proof.
    unfold grown; intros.
    safestep.
    unfold synced_list; simpl; rewrite app_nil_r.
    eassign f; destruct f; auto.
    eauto. eauto.

    safestep.
    safestep.
    safestep.
    subst; simpl; apply list2nmem_arrayN_app; eauto.

    (* TODO: fix proof for monadic loop break - should be
    similar to Log.v's read_cond, but something is broken *)
    (*
    safestep; safestep.
    or_l; cancel.
    erewrite firstn_S_selN_expand by omega.
    rewrite synced_list_app, <- app_assoc.
    unfold synced_list at 3; simpl; eauto.
    denote (MSAlloc a = MSAlloc a0) as Heq; rewrite Heq in *.
    eapply ilist_safe_trans; eauto.

    cancel.
    safestep.
    or_r; cancel.
    rewrite firstn_oob; auto.
    apply list2nmem_arrayN_app; auto.
    rewrite firstn_oob; auto.

    cancel.
    Unshelve. all: easy.
    *)
  Admitted.


  Hint Extern 1 ({{_}} Bind (grown _ _ _ _ _ _) _) => apply grown_ok : prog.

  Theorem truncate_ok : forall lxp bxp ixp inum sz ms,
    {< F Fm Fi m0 m flist ilist frees f,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms) hm *
           [[[ m ::: (Fm * rep bxp ixp flist ilist frees ) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]]
    POST:hm' RET:^(ms', r) [[ MSAlloc ms = MSAlloc ms' ]] * exists m',
           [[ isError r ]] * LOG.rep lxp F (LOG.ActiveTxn m0 m') (MSLL ms') hm' \/
           [[ r = OK tt  ]] * exists flist' ilist' frees' f',
           LOG.rep lxp F (LOG.ActiveTxn m0 m') (MSLL ms') hm' *
           [[[ m' ::: (Fm * rep bxp ixp flist' ilist' frees') ]]] *
           [[[ flist' ::: (Fi * inum |-> f') ]]] *
           [[ f' = mk_bfile (setlen (BFData f) sz ($0, nil)) (BFAttr f) ]] *
           [[ ilist_safe ilist (pick_balloc frees (MSAlloc ms')) 
                         ilist' (pick_balloc frees' (MSAlloc ms'))  ]]
    CRASH:hm'  LOG.intact lxp F m0 hm'
    >} truncate lxp bxp ixp inum sz ms.
  Proof.
    unfold truncate; intros.
    step.
    step.

    - safestep.
      step.
      or_r; safecancel.
      rewrite setlen_inbound, Rounding.sub_sub_assoc by omega; auto.
      cancel.

    - safestep.
      apply list2nmem_array.
      step.

      or_r; safecancel.
      rewrite setlen_oob by omega.
      unfold synced_list.
      rewrite repeat_length, combine_repeat; auto.
      cancel.
  Qed.


  Theorem reset_ok : forall lxp bxp ixp inum ms,
    {< F Fm Fi m0 m flist ilist frees f,
    PRE:hm
           LOG.rep lxp F (LOG.ActiveTxn m0 m) (MSLL ms) hm *
           [[[ m ::: (Fm * rep bxp ixp flist ilist frees) ]]] *
           [[[ flist ::: (Fi * inum |-> f) ]]]
    POST:hm' RET:ms' exists m' flist' ilist' frees',
           LOG.rep lxp F (LOG.ActiveTxn m0 m') (MSLL ms') hm' *
           [[[ m' ::: (Fm * rep bxp ixp flist' ilist' frees') ]]] *
           [[[ flist' ::: (Fi * inum |-> bfile0) ]]] *
           [[ MSAlloc ms = MSAlloc ms' /\ 
              ilist_safe ilist (pick_balloc frees (MSAlloc ms')) 
                         ilist' (pick_balloc frees' (MSAlloc ms'))  ]]

    CRASH:hm'  LOG.intact lxp F m0 hm'
    >} reset lxp bxp ixp inum ms.
  Proof.
    unfold reset; intros.
    step.
    step.
    step.
    step.
    rewrite Nat.sub_diag; simpl; auto.
    denote (MSAlloc r_ = MSAlloc r_0) as Heq; rewrite Heq in *.
    eapply ilist_safe_trans; eauto.
  Qed.

  Hint Extern 1 ({{_}} Bind (truncate _ _ _ _ _ _) _) => apply truncate_ok : prog.
  Hint Extern 1 ({{_}} Bind (reset _ _ _ _ _) _) => apply reset_ok : prog.


  (** crash and recovery *)

  Definition FSynced f : Prop :=
     forall n, snd (selN (BFData f) n ($0, nil)) = nil.

  Definition file_crash f f' : Prop :=
    exists vs, possible_crash_list (BFData f) vs /\
    f' = mk_bfile (synced_list vs) (BFAttr f).

  Definition flist_crash fl fl' : Prop :=
    Forall2 file_crash fl fl'.

  Lemma flist_crash_length : forall a b,
    flist_crash a b -> length a = length b.
  Proof.
    unfold flist_crash; intros.
    eapply forall2_length; eauto.
  Qed.

  Lemma fsynced_synced_file : forall f,
    FSynced (synced_file f).
  Proof.
    unfold FSynced, synced_file, synced_list; simpl; intros.
    setoid_rewrite selN_combine; simpl.
    destruct (lt_dec n (length (BFData f))).
    rewrite repeat_selN; auto.
    rewrite map_length; auto.
    rewrite selN_oob; auto.
    rewrite repeat_length, map_length.
    apply not_lt; auto.
    rewrite repeat_length, map_length; auto.
  Qed.

  Lemma arrayN_synced_list_fsynced : forall f l,
    arrayN (@ptsto _ addr_eq_dec _) 0 (synced_list l) (list2nmem (BFData f)) ->
    FSynced f.
  Proof.
    unfold FSynced; intros.
    erewrite list2nmem_array_eq with (l' := (BFData f)) by eauto.
    rewrite synced_list_selN; simpl; auto.
  Qed.

  Lemma file_crash_attr : forall f f',
    file_crash f f' -> BFAttr f' = BFAttr f.
  Proof.
    unfold file_crash; intros.
    destruct H; intuition; subst; auto.
  Qed.

  Lemma file_crash_possible_crash_list : forall f f',
    file_crash f f' ->
    possible_crash_list (BFData f) (map fst (BFData f')).
  Proof.
    unfold file_crash; intros; destruct H; intuition subst.
    unfold synced_list; simpl.
    rewrite map_fst_combine; auto.
    rewrite repeat_length; auto.
  Qed.

  Lemma file_crash_data_length : forall f f',
    file_crash f f' -> length (BFData f) = length (BFData f').
  Proof.
    unfold file_crash; intros.
    destruct H; intuition subst; simpl.
    rewrite synced_list_length.
    apply possible_crash_list_length; auto.
  Qed.

  Lemma file_crash_synced : forall f f',
    file_crash f f' ->
    FSynced f ->
    f = f'.
  Proof.
    unfold FSynced, file_crash; intuition.
    destruct H; intuition subst; simpl.
    destruct f; simpl in *.
    f_equal.
    eapply list_selN_ext.
    rewrite synced_list_length.
    apply possible_crash_list_length; auto.
    intros.
    setoid_rewrite synced_list_selN.
    rewrite surjective_pairing at 1.
    rewrite H0.
    f_equal.
    erewrite possible_crash_list_unique with (b := x); eauto.
    erewrite selN_map; eauto.
  Qed.

  Lemma file_crash_fsynced : forall f f',
    file_crash f f' ->
    FSynced f'.
  Proof.
    unfold FSynced, file_crash; intuition.
    destruct H; intuition subst; simpl.
    rewrite synced_list_selN; auto.
  Qed.

  Lemma file_crash_ptsto : forall f f' vs F a,
    file_crash f f' ->
    (F * a |-> vs)%pred (list2nmem (BFData f)) ->
    (exists v, [[ In v (vsmerge vs) ]]  *
       crash_xform F * a |=> v)%pred (list2nmem (BFData f')).
  Proof.
    unfold file_crash; intros.
    repeat deex.
    eapply list2nmem_crash_xform in H0; eauto.
    pred_apply.
    xform_norm.
    rewrite crash_xform_ptsto.
    cancel.
  Qed.

  Lemma xform_file_match : forall f ino,
    crash_xform (file_match f ino) =p=> 
      exists f', [[ file_crash f f' ]] * file_match f' ino.
  Proof.
    unfold file_match, file_crash; intros.
    xform_norm.
    rewrite xform_listmatch_ptsto.
    cancel; eauto; simpl; auto.
  Qed.

  Lemma xform_file_list : forall fs inos,
    crash_xform (listmatch file_match fs inos) =p=>
      exists fs', [[ flist_crash fs fs' ]] * listmatch file_match fs' inos.
  Proof.
    unfold listmatch, pprd.
    induction fs; destruct inos; xform_norm.
    cancel. instantiate(1 := nil); simpl; auto.
    apply Forall2_nil. simpl; auto.
    inversion H0.
    inversion H0.

    specialize (IHfs inos).
    rewrite crash_xform_sep_star_dist, crash_xform_lift_empty in IHfs.
    setoid_rewrite lift_impl with (Q := length fs = length inos) at 4; intros; eauto.
    rewrite IHfs; simpl.

    rewrite xform_file_match.
    cancel.
    eassign (f' :: fs'); cancel.
    apply Forall2_cons; auto.
    simpl; omega.
  Qed.

  Lemma xform_rep : forall bxp ixp flist ilist frees,
    crash_xform (rep bxp ixp flist ilist frees) =p=> 
      exists flist', [[ flist_crash flist flist' ]] *
      rep bxp ixp flist' ilist frees.
  Proof.
    unfold rep; intros.
    xform_norm.
    rewrite INODE.xform_rep, BALLOC.xform_rep, BALLOC.xform_rep.
    rewrite xform_file_list.
    cancel.
  Qed.

  Lemma xform_file_match_ptsto : forall F a vs f ino,
    (F * a |-> vs)%pred (list2nmem (BFData f)) ->
    crash_xform (file_match f ino) =p=>
      exists f' v, file_match f' ino * 
      [[ In v (vsmerge vs) ]] *
      [[ (crash_xform F * a |=> v)%pred (list2nmem (BFData f')) ]].
  Proof.
    unfold file_crash, file_match; intros.
    xform_norm.
    rewrite xform_listmatch_ptsto.
    xform_norm.
    pose proof (list2nmem_crash_xform _ H1 H) as Hx.
    apply crash_xform_sep_star_dist in Hx.
    rewrite crash_xform_ptsto in Hx; destruct_lift Hx.

    norm.
    eassign (mk_bfile (synced_list l) (BFAttr f)); cancel.
    eassign (dummy).
    intuition subst; eauto.
  Qed.

 Lemma xform_rep_file : forall F bxp ixp fs f i ilist frees,
    (F * i |-> f)%pred (list2nmem fs) ->
    crash_xform (rep bxp ixp fs ilist frees) =p=> 
      exists fs' f',  [[ flist_crash fs fs' ]] * [[ file_crash f f' ]] *
      rep bxp ixp fs' ilist frees *
      [[ (arrayN_ex (@ptsto _ addr_eq_dec _) fs' i * i |-> f')%pred (list2nmem fs') ]].
  Proof.
    unfold rep; intros.
    xform_norm.
    rewrite INODE.xform_rep, BALLOC.xform_rep, BALLOC.xform_rep.
    rewrite xform_file_list.
    cancel.
    erewrite list2nmem_sel with (x := f) by eauto.
    apply forall2_selN; eauto.
    eapply list2nmem_inbound; eauto.
    apply list2nmem_ptsto_cancel.
    erewrite <- flist_crash_length; eauto.
    eapply list2nmem_inbound; eauto.
    Unshelve. all: eauto.
  Qed.

 Lemma xform_rep_file_pred : forall (F Fd : pred) bxp ixp fs f i ilist frees,
    (F * i |-> f)%pred (list2nmem fs) ->
    (Fd (list2nmem (BFData f))) ->
    crash_xform (rep bxp ixp fs ilist frees) =p=>
      exists fs' f',  [[ flist_crash fs fs' ]] * [[ file_crash f f' ]] *
      rep bxp ixp fs' ilist frees *
      [[ (arrayN_ex (@ptsto _ addr_eq_dec _) fs' i * i |-> f')%pred (list2nmem fs') ]] *
      [[ (crash_xform Fd)%pred (list2nmem (BFData f')) ]].
  Proof.
    intros.
    rewrite xform_rep_file by eauto.
    cancel. eauto.
    unfold file_crash in *.
    repeat deex; simpl.
    eapply list2nmem_crash_xform; eauto.
  Qed.

  Lemma xform_rep_off : forall Fm Fd bxp ixp ino off f fs vs ilist frees,
    (Fm * ino |-> f)%pred (list2nmem fs) ->
    (Fd * off |-> vs)%pred (list2nmem (BFData f)) ->
    crash_xform (rep bxp ixp fs ilist frees) =p=> 
      exists fs' f' v, [[ flist_crash fs fs' ]] * [[ file_crash f f' ]] *
      rep bxp ixp fs' ilist frees * [[ In v (vsmerge vs) ]] *
      [[ (arrayN_ex (@ptsto _ addr_eq_dec _) fs' ino * ino |-> f')%pred (list2nmem fs') ]] *
      [[ (crash_xform Fd * off |=> v)%pred (list2nmem (BFData f')) ]].
  Proof.
    Opaque vsmerge.
    intros.
    rewrite xform_rep_file by eauto.
    xform_norm.
    eapply file_crash_ptsto in H0; eauto.
    destruct_lift H0.
    cancel; eauto.
    Transparent vsmerge.
  Qed.

End BFILE.



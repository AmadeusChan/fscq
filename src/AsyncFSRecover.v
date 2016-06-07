Require Import Prog.
Require Import Log.
Require Import BFile.
Require Import Word.
Require Import Omega.
Require Import BasicProg.
Require Import Bool.
Require Import Pred PredCrash.
Require Import DirName.
Require Import Hoare.
Require Import GenSepN.
Require Import ListPred.
Require Import SepAuto.
Require Import Idempotent.
Require Import Inode.
Require Import List ListUtils.
Require Import Balloc.
Require Import Bytes.
Require Import DirTree.
Require Import Rec.
Require Import Arith.
Require Import Array.
Require Import FSLayout.
Require Import Cache.
Require Import Errno.
Require Import AsyncDisk.
Require Import GroupLog.
Require Import DiskLogHash.
Require Import SuperBlock.
Require Import DiskSet.
Require Import AsyncFS.

Set Implicit Arguments.
Import ListNotations.


Module AFS_RECOVER.

  Import AFS.
  Import DIRTREE.

  Parameter cachesize : nat.
  Axiom cachesize_ok : cachesize <> 0.

  Notation MSLL := BFILE.MSLL.
  Notation MSAlloc := BFILE.MSAlloc.


  Theorem file_getattr_recover_ok : forall fsxp inum mscs,
  {X<< ds pathname Fm Ftop tree f ilist frees,
  PRE:hm LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn ds) (MSLL mscs) hm *
         [[[ ds!! ::: (Fm * DIRTREE.rep fsxp Ftop tree ilist frees) ]]] *
         [[ DIRTREE.find_subtree pathname tree = Some (DIRTREE.TreeFile inum f) ]]
  POST:hm' RET:^(mscs',r)
         LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn ds) (MSLL mscs') hm' *
         [[ r = BFILE.BFAttr f ]]
  REC:hm' RET:^(mscs, fsxp)
         exists d n, LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn (d, nil)) (MSLL mscs) hm' *
         [[ n <= length (snd ds) ]] *
         [[[ d ::: crash_xform (diskIs (list2nmem (nthd n ds))) ]]]
  >>X} file_get_attr fsxp inum mscs >> recover cachesize.
  Proof.
    unfold forall_helper.
    recover_ro_ok.
    destruct v.
    cancel.
    eauto.
    step.

    norm'l. unfold stars; simpl.
    cancel.
    eassign_idempred.

    simpl_idempred_l.
    xform_norml;
      rewrite SB.crash_xform_rep;
      (rewrite LOG.notxn_after_crash_diskIs || rewrite LOG.rollbacktxn_after_crash_diskIs);
      try eassumption.
    cancel.
    safestep; subst.
    simpl_idempred_r.
    rewrite <- LOG.before_crash_idempred.
    cancel. auto.

    cancel.
    safestep; subst.
    simpl_idempred_r.
    rewrite <- LOG.before_crash_idempred.
    cancel. auto.
  Qed.


  Theorem read_fblock_recover_ok : forall fsxp inum off mscs,
    {X<< ds Fm Ftop tree pathname f Fd vs ilist frees,
    PRE:hm LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn ds) (MSLL mscs) hm *
           [[[ ds!! ::: (Fm * DIRTREE.rep fsxp Ftop tree ilist frees)]]] *
           [[ DIRTREE.find_subtree pathname tree = Some (DIRTREE.TreeFile inum f) ]] *
           [[[ (BFILE.BFData f) ::: (Fd * off |-> vs) ]]]
    POST:hm' RET:^(mscs', r)
           LOG.rep (FSXPLog fsxp) (SB.rep  fsxp) (LOG.NoTxn ds) (MSLL mscs') hm' *
           [[ r = fst vs ]]
    REC:hm' RET:^(mscs,fsxp)
         exists d n, LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn (d, nil)) (MSLL mscs) hm' *
         [[ n <= length (snd ds) ]] *
         [[[ d ::: crash_xform (diskIs (list2nmem (nthd n ds))) ]]]
    >>X} read_fblock fsxp inum off mscs >> recover cachesize.
  Proof.
    unfold forall_helper.
    recover_ro_ok.
    destruct v.
    cancel.
    eauto.
    eauto.
    step.

    eassign_idempred.

    simpl_idempred_l.
    xform_norml;
      rewrite SB.crash_xform_rep;
      (rewrite LOG.notxn_after_crash_diskIs || rewrite LOG.rollbacktxn_after_crash_diskIs);
      try eassumption.
    cancel.
    safestep; subst.
    simpl_idempred_r.
    rewrite <- LOG.before_crash_idempred.

    cancel. auto.

    cancel.
    safestep; subst.
    simpl_idempred_r.
    rewrite <- LOG.before_crash_idempred.
    cancel. auto.
  Qed.


  Lemma instantiate_crash : forall idemcrash (F_ : rawpred) (hm_crash : hashmap),
    (fun hm => F_ * idemcrash hm) hm_crash =p=> F_ * idemcrash hm_crash.
  Proof.
    reflexivity.
  Qed.

  Theorem file_truncate_recover_ok : forall fsxp inum sz mscs,
    {<< ds Fm Ftop tree pathname f ilist frees,
    PRE:hm
      LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn ds) (MSLL mscs) hm *
      [[[ ds!! ::: (Fm * DIRTREE.rep fsxp Ftop tree ilist frees)]]] *
      [[ DIRTREE.find_subtree pathname tree = Some (DIRTREE.TreeFile inum f) ]]
    POST:hm' RET:^(mscs', r)
      [[ r = false ]] * LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn ds) (MSLL mscs') hm' \/
      [[ r = true  ]] * exists d tree' f' ilist' frees',
        LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn (pushd d ds)) (MSLL mscs') hm' *
        [[[ d ::: (Fm * DIRTREE.rep fsxp Ftop tree' ilist' frees')]]] *
        [[ tree' = DIRTREE.update_subtree pathname (DIRTREE.TreeFile inum f') tree ]] *
        [[ f' = BFILE.mk_bfile (setlen (BFILE.BFData f) sz ($0, nil)) (BFILE.BFAttr f) ]]
    REC:hm' RET:^(mscs,fsxp)
      (exists d n, LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn (d, nil)) (MSLL mscs) hm' *
         [[ n <= length (snd ds) ]] *
         [[[ d ::: crash_xform (diskIs (list2nmem (nthd n ds))) ]]]) \/
      (exists d dnew n ds' tree' f' ilist' frees',
         LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn (d, nil)) (MSLL mscs) hm' *
         [[ n <= length (snd ds') ]] *
         [[[ d ::: crash_xform (diskIs (list2nmem (nthd n ds'))) ]]] *
         [[ ds' = pushd dnew ds ]] *
         [[[ dnew ::: (Fm * DIRTREE.rep fsxp Ftop tree' ilist' frees')]]] *
         [[ tree' = DIRTREE.update_subtree pathname (DIRTREE.TreeFile inum f') tree ]] *
         [[ f' = BFILE.mk_bfile (setlen (BFILE.BFData f) sz ($0, nil)) (BFILE.BFAttr f) ]])
     >>} file_truncate fsxp inum sz mscs >> recover cachesize.
  Proof.
    recover_ro_ok.
    destruct v.
    cancel.
    eauto.
    safestep.  (* crucial to use safe version *)
    or_l.
    cancel. cancel.

    apply instantiate_crash.
    cancel.
    cancel.

    cancel.

    eassign_idempred.
    cancel.

    simpl.
    repeat xform_dist.
    repeat xform_deex_l.
    xform_dist.
    rewrite crash_xform_lift_empty.
    norml. unfold stars; simpl. rewrite H8.
    xform_dist. xform_deex_l.

    - rewrite LOG.idempred_idem.
      norml; unfold stars; simpl.
      rewrite SB.crash_xform_rep.
      cancel.

      prestep. norm. cancel.
      recover_ro_ok.
      cancel.
      or_l.
      safecancel; eauto.

      intuition.
      simpl_idempred_r.
      rewrite crash_xform_or_dist in *.
      auto.

      simpl_idempred_r.
      or_l; cancel.
      rewrite <- LOG.before_crash_idempred.
      auto.

    - norml; unfold stars; simpl.
      xform_deex_l. norml; unfold stars; simpl.
      xform_deex_l. norml; unfold stars; simpl.
      repeat xform_dist.
      rewrite LOG.idempred_idem.
      norml; unfold stars; simpl.
      rewrite SB.crash_xform_rep.
      cancel.

      prestep. norm. cancel.
      recover_ro_ok.
      cancel.
      or_r.
      safecancel; eauto.
      reflexivity.

      intuition.
      simpl_idempred_r.
      rewrite crash_xform_or_dist in *.
      auto.

      simpl_idempred_r.
      or_r; cancel.
      do 4 (xform_norm; cancel).
      rewrite <- LOG.before_crash_idempred.
      safecancel; eauto.
      auto.
      (* XXX: Goals proven, but getting
       * "Error: No such section variable or assumption: d." *)
  Admitted.


  Theorem update_fblock_d_recover_ok : forall fsxp inum off v mscs,
    {<< ds Fm Ftop tree pathname f Fd vs frees ilist,
    PRE:hm
      LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn ds) (MSLL mscs) hm *
      [[[ ds!! ::: (Fm * DIRTREE.rep fsxp Ftop tree ilist frees)]]] *
      [[ DIRTREE.find_subtree pathname tree = Some (DIRTREE.TreeFile inum f) ]] *
      [[[ (BFILE.BFData f) ::: (Fd * off |-> vs) ]]]
    POST:hm' RET:^(mscs')
      exists tree' f' ds',
       LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn ds') (MSLL mscs') hm' *
       [[[ ds'!! ::: (Fm  * DIRTREE.rep fsxp Ftop tree' ilist frees) ]]] *
       [[ tree' = update_subtree pathname (TreeFile inum f') tree ]] *
       [[[ (BFILE.BFData f') ::: (Fd * off |-> (v, vsmerge vs)) ]]] *
       [[ BFILE.BFAttr f' = BFILE.BFAttr f ]]
    REC:hm' RET:^(mscs,fsxp)
      exists d, LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn (d, nil)) (MSLL mscs) hm' *
      ((exists n, 
        [[[ d ::: crash_xform (diskIs (list2nmem (nthd n ds))) ]]] ) \/
       (exists tree' f' v' ilist' frees',
        [[[ d ::: (crash_xform Fm * DIRTREE.rep fsxp Ftop tree' ilist' frees')]]] *
        [[ tree' = DIRTREE.update_subtree pathname (DIRTREE.TreeFile inum f') tree ]] *
        [[[ (BFILE.BFData f') ::: (crash_xform Fd * off |=> v') ]]] *
        [[ BFILE.BFAttr f' = BFILE.BFAttr f ]] *
        [[ In v' (v :: vsmerge vs) ]]))
   >>} update_fblock_d fsxp inum off v mscs >> recover cachesize.
  Proof.
    recover_ro_ok.
    cancel.
    instantiate (pathname := v4); eauto.
    eauto.
    step.
    apply pimpl_refl.
    (* follows one of the earlier recover proofs but isn't used by atomiccp. *)
  Admitted.



  Theorem file_sync_recover_ok : forall fsxp inum mscs,
    {<< ds Fm Ftop tree pathname f frees ilist,
    PRE:hm
      LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn ds) (MSLL mscs) hm *
      [[[ ds!! ::: (Fm * DIRTREE.rep fsxp Ftop tree ilist frees)]]] *
      [[ DIRTREE.find_subtree pathname tree = Some (DIRTREE.TreeFile inum f) ]]
    POST:hm' RET:^(mscs')
      exists ds' tree' ds0 al,
        LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn ds') (MSLL mscs') hm' *
        [[ ds' = dssync_vecs ds0 al /\ BFILE.diskset_was ds0 ds ]] *
        [[[ ds!! ::: (Fm * DIRTREE.rep fsxp Ftop tree' ilist frees)]]] *
        [[ tree' = update_subtree pathname (TreeFile inum  (BFILE.synced_file f)) tree ]]
    REC:hm' RET:^(mscs,fsxp)
      exists d,
       LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn (d, nil)) (MSLL mscs) hm' *
       ((exists n,  [[[ d ::: crash_xform (diskIs (list2nmem (nthd n ds))) ]]]) \/
         exists flist' F',
         [[[ d ::: (F' * BFILE.rep (FSXPBlockAlloc fsxp) (FSXPInode fsxp) flist' ilist frees) ]]] *
         [[[ flist' ::: (arrayN_ex (@ptsto _ addr_eq_dec _) flist' inum * inum |-> BFILE.synced_file f) ]]]
       )
   >>} file_sync fsxp inum mscs >> recover cachesize.
  Proof.
    intros.
    recover_ro_ok.
    cancel. eauto.
    step.

    (* build a new idemcrash predicate that carries the XCRASH facts *)
    instantiate (1 :=  (fun hm => (exists p, p * [[ crash_xform p =p=> crash_xform
         (LOG.idempred (FSXPLog fsxp) (SB.rep fsxp) v hm
      \/ (exists d tree',
           LOG.idempred (FSXPLog fsxp) (SB.rep fsxp) (d, []) hm *
           [[[ d ::: v0 ✶ DIRTREE.rep fsxp v1 tree' ]]] *
           [[ tree' = DIRTREE.update_subtree v3 (DIRTREE.TreeFile inum (BFILE.synced_file v4)) v2 ]])) ]]))%pred).
    apply pimpl_refl.
    cancel.
    simpl.
    repeat xform_dist.
    repeat xform_deex_l.
    xform_dist.
    rewrite crash_xform_lift_empty.
    norml. unfold stars; simpl. rewrite H8.
    xform_dist. xform_deex_l.

    - rewrite LOG.idempred_idem; xform_deex_l;
      rewrite SB.crash_xform_rep.
      cancel.

      prestep. norm. cancel.
      recover_ro_ok.
      cancel.
      destruct v.
      or_l; cancel.

      intuition.
      cancel.

      simpl_idempred_r.
      or_l; cancel.
      rewrite <- LOG.before_crash_idempred.
      auto.

    - repeat xform_deex_l.
      repeat xform_dist.
      rewrite LOG.idempred_idem; xform_deex_l;
      rewrite SB.crash_xform_rep.
      cancel.

      step.
      denote crash_xform as Hx.
      replace n with 0 in Hx by omega; rewrite nthd_0 in Hx; simpl in Hx.
      denote! (_ (list2nmem x1)) as Hy.
      apply (crash_xform_diskIs_pred _ Hy) in Hx.
      apply crash_xform_sep_star_dist in Hx.

      (* unfold DIRTREE.rep in Hx to extract the file list *)
      unfold DIRTREE.rep in Hx; apply sep_star_comm in Hx.
      repeat (rewrite crash_xform_exists_comm in Hx;
        apply pimpl_exists_r_star_r in Hx;
        destruct Hx as [ ? Hx ]).
      repeat rewrite crash_xform_sep_star_dist in Hx.
      repeat rewrite crash_xform_lift_empty in Hx.
      rewrite BFILE.xform_rep, IAlloc.xform_rep in Hx.
      destruct_lift Hx.
      recover_ro_ok. cancel.
      or_r; cancel.

      (* XXX: should be able to tell from H8 and H7, though not very interesting.
         Need to prove (BFILE.synced_file v4) = selN dummy inum _ *)
      admit.

      simpl_idempred_r.
      or_r; cancel.
      do 3 (xform_norm; cancel).
      rewrite <- LOG.before_crash_idempred.
      eauto.
      auto.

    Unshelve. all: eauto.
  Admitted.

(*
  Theorem lookup_recover_ok : forall fsxp dnum fnlist mscs,
    {<< ds Fm Ftop tree ilist frees,
    PRE:hm
     LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn ds) (MSLL mscs) hm *
      [[[ ds!! ::: (Fm * DIRTREE.rep fsxp Ftop tree ilist frees) ]]] *
      [[ DIRTREE.dirtree_inum tree = dnum]] *
      [[ DIRTREE.dirtree_isdir tree = true ]]
    POST:hm' RET:^(mscs',r)
      LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn ds) (MSLL mscs') hm' *
      [[ r = DIRTREE.find_name fnlist tree ]]
    REC:hm' RET:^(mscs, fsxp)
      exists d, LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn (d, nil)) mscs hm' *
       [[[ d ::: crash_xform (diskIs (list2nmem (fst ds))) ]]]
    >>} lookup fsxp dnum fnlist mscs >> recover cachesize.
  Proof.
    recover_ro_ok.
    cancel.
    eauto.
    step.
    instantiate (1 := (LOG.idempred (FSXPLog fsxp) (SB.rep fsxp) v \/
      (exists cs : cachestate, LOG.after_crash (FSXPLog fsxp) (SB.rep fsxp) (fst v, []) cs))%pred).
    cancel; cancel.
    cancel.
    or_l.
    cancel.
    xform_norm.
    recover_ro_ok.
    rewrite LOG.crash_xform_intact.
    xform_norm.
    rewrite SB.crash_xform_rep.

    cancel.
    rewrite LOG.notxn_after_crash_diskIs. cancel.
    rewrite nthd_0; eauto. omega.

    safestep; subst.
    eassign d0; eauto.
    pred_apply; instantiate (1 := nil).
    replace n with 0 in *.
    rewrite nthd_0; simpl; auto.
    simpl in *; omega.

    cancel; cancel.
    rewrite LOG.after_crash_idem.
    xform_norm.
    rewrite SB.crash_xform_rep.
    recover_ro_ok.
    cancel.

    step.
    cancel; cancel.
  Qed.
*)

(*
  Theorem create_recover_ok : forall fsxp dnum name mscs,
    {<< ds pathname Fm Ftop tree tree_elem ilist frees,
    PRE:hm
      LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn ds) (MSLL mscs) hm *
      [[[ ds!! ::: (Fm * DIRTREE.rep fsxp Ftop tree ilist frees) ]]] *
      [[ DIRTREE.find_subtree pathname tree = Some (DIRTREE.TreeDir dnum tree_elem) ]]
    POST:hm' RET:^(mscs',r)
       [[ r = None ]] *
        LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn ds) (MSLL mscs') hm'
      \/ exists inum,
       [[ r = Some inum ]] * exists d tree' ilist' frees',
       LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn (pushd d ds)) (MSLL mscs') hm' *
       [[ tree' = DIRTREE.tree_graft dnum tree_elem pathname name 
                           (DIRTREE.TreeFile inum BFILE.bfile0) tree ]] *
       [[[ d ::: (Fm * DIRTREE.rep fsxp Ftop tree' ilist' frees') ]]]
    REC:hm' RET:^(mscs,fsxp)
      exists d,
      LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn (d, nil)) mscs hm' *
      [[[ d ::: crash_xform (diskIs (list2nmem (fst ds))) ]]]
    >>} create fsxp dnum name mscs >> recover cachesize.
  Proof.
    recover_ro_ok.
    cancel.
    eauto.
    safestep.
    or_l.
    cancel.
    subst.
    apply pimpl_refl.
    or_r.
    cancel.
    subst.
    apply pimpl_refl.

    (* if CRASH is LOG.idempred, we must manually instantiate idemcrash to include
       the after_crash case *)
    eassign ( LOG.idempred (FSXPLog fsxp) (SB.rep fsxp) v \/
      (exists cs : cachestate, LOG.after_crash (FSXPLog fsxp) (SB.rep fsxp) (fst v, []) cs))%pred.
    cancel; cancel.
    xform_norm; recover_ro_ok.

    - rewrite LOG.crash_xform_intact.
      xform_norm.
      rewrite SB.crash_xform_rep.
      rewrite LOG.notxn_after_crash_diskIs with (n := 0) (ds := (fst v, nil)); auto.
      cancel.
      safestep.
      cancel.
      pred_apply; subst.
      replace n with 0 by omega.
      rewrite nthd_0; eauto.
      cancel; cancel.

    - rewrite LOG.after_crash_idem.
      xform_norm.
      rewrite SB.crash_xform_rep.
      cancel.
      step.
      cancel; cancel.
  Qed.
*)

(*
  Theorem rename_recover_ok : forall fsxp dnum srcpath srcname dstpath dstname mscs,
    {<< ds Fm Ftop tree cwd tree_elem ilist frees,
    PRE:hm
      LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn ds) (MSLL mscs) hm *
      [[[ ds!! ::: (Fm * DIRTREE.rep fsxp Ftop tree ilist frees) ]]] *
      [[ DIRTREE.find_subtree cwd tree = Some (DIRTREE.TreeDir dnum tree_elem) ]]
    POST:hm' RET:^(mscs',ok)
      [[ ok = false ]] * LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn ds) (MSLL mscs') hm' \/
      [[ ok = true ]] * 
        rename_rep ds mscs' Fm fsxp Ftop tree ilist frees cwd dnum srcpath srcname dstpath dstname hm'
    REC:hm' RET:^(mscs,fsxp)
      exists d,
        LOG.rep (FSXPLog fsxp) (SB.rep fsxp) (LOG.NoTxn (d, nil)) mscs hm' *
        [[[ d ::: crash_xform (diskIs (list2nmem (fst ds))) ]]]
    >>} rename fsxp dnum srcpath srcname dstpath dstname mscs >> recover cachesize.
  Proof.
    recover_ro_ok.
    cancel.
    eauto.
    safestep.
    or_l.
    cancel.
    subst.
    apply pimpl_refl.
    or_r.
    cancel.
    subst.
    apply pimpl_refl.

    (* if CRASH is LOG.idempred, we must manually instantiate idemcrash to include
       the after_crash case *)
    eassign ( LOG.idempred (FSXPLog fsxp) (SB.rep fsxp) v \/
      (exists cs : cachestate, LOG.after_crash (FSXPLog fsxp) (SB.rep fsxp) (fst v, []) cs))%pred.
    cancel; cancel.
    xform_norm; recover_ro_ok.

    - rewrite LOG.crash_xform_intact.
      xform_norm.
      rewrite SB.crash_xform_rep.
      rewrite LOG.notxn_after_crash_diskIs with (n := 0) (ds := (fst v, nil)); auto.
      cancel.
      safestep.
      cancel.
      pred_apply; subst.
      replace n with 0 by omega.
      rewrite nthd_0; eauto.
      cancel; cancel.

    - rewrite LOG.after_crash_idem.
      xform_norm.
      rewrite SB.crash_xform_rep.
      cancel.
      step.
      cancel; cancel.
  Qed.
*)

End AFS_RECOVER.

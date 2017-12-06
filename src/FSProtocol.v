Require Import CCL.
Require Import Hashmap.
Require Import FSLayout.

Require AsyncFS.
(* imports for DirTreeRep.rep *)
Import Log FSLayout Inode.INODE BFile.

(* various other imports *)
Export BFILE. (* importantly, exports memstate *)
Import SuperBlock.
Import GenSepN.
Import Pred.

Require Export HomeDirProtocol.
Require Export OptimisticTranslator.

Record FsParams :=
  { ccache: ident; (* : Cache *)
    fsmem: ident; (* : memsstate *)
    fstree: ident; (* : dirtree *)
    fshomedirs: ident; (* thread_homes *)
    fsxp: fs_xparams;
  }.

Section FilesystemProtocol.

  Variable P:FsParams.

  Set Default Proof Using "P".

  Definition fs_rep vd hm mscs tree :=
    exists sm ds ilist frees,
      LOG.rep (FSLayout.FSXPLog (fsxp P)) (SB.rep (fsxp P))
              (LOG.NoTxn ds) (MSLL mscs) sm hm (add_buffers vd) /\
      (DirTreeRep.rep (fsxp P) Pred.emp tree ilist frees mscs sm)
        (list2nmem (ds!!)).

  Definition root_inode_rep tree :=
    dirtree_inum tree = FSXPRootInum (fsxp P) /\
    dirtree_isdir tree = true.

  Definition fs_invariant l d_i d hm tree (homedirs: thread_homes) : heappred :=
    (fstree P |-> abs tree *
     [[ root_inode_rep tree ]] *
     fshomedirs P |-> abs homedirs *
     exists c vd mscs,
       ccache P |-> val c *
       [[ cache_rep d c vd \/ cache_rep d_i c vd ]] *
       [[ l = Free -> d_i = d ]] *
       fsmem P |-> val mscs *
       [[ fs_rep vd hm mscs tree ]])%pred.

  Theorem fs_invariant_unfold : forall l d_i d hm tree homedirs h,
      fs_invariant l d_i d hm tree homedirs h ->
      exists c vd mscs,
        (fstree P |-> abs tree * fshomedirs P |-> abs homedirs *
         ccache P |-> val c *
         fsmem P |-> val mscs)%pred h /\
        (cache_rep d c vd \/ cache_rep d_i c vd) /\
        (l = Free -> d_i = d) /\
        fs_rep vd hm mscs tree /\
        root_inode_rep tree.
  Proof.
    unfold fs_invariant; intros.
    SepAuto.destruct_lifts.
    descend; intuition eauto.
  Qed.

  Theorem fs_invariant_unfold_exists_disk : forall l d_i d hm tree homedirs h,
      fs_invariant l d_i d hm tree homedirs h ->
      exists d c vd mscs,
        (fstree P |-> abs tree * fshomedirs P |-> abs homedirs *
         ccache P |-> val c *
         fsmem P |-> val mscs)%pred h /\
        (cache_rep d c vd) /\
        fs_rep vd hm mscs tree /\
        root_inode_rep tree.
  Proof.
    unfold fs_invariant; intros.
    SepAuto.destruct_lifts.
    match goal with
    | [ H: _ \/ _ |- _ ] =>
      destruct H; descend; intuition eauto
    end.
  Qed.

  Theorem fs_invariant_unfold_same_disk : forall l d_i d hm tree homedirs h,
      fs_invariant l d_i d hm tree homedirs h ->
      l = Free ->
      d_i = d /\
      exists c vd mscs,
        (fstree P |-> abs tree * fshomedirs P |-> abs homedirs *
         ccache P |-> val c *
         fsmem P |-> val mscs)%pred h /\
        (cache_rep d c vd) /\
        fs_rep vd hm mscs tree /\
        root_inode_rep tree.
  Proof.
    intros; subst.
    edestruct fs_invariant_unfold; repeat deex; descend;
      intuition (subst; eauto).
  Qed.

  Lemma root_inode_rep_update : forall tree path subtree,
      root_inode_rep tree ->
      (path = nil -> root_inode_rep subtree) ->
      root_inode_rep (update_subtree path subtree tree).
  Proof.
    unfold root_inode_rep; intros.
    destruct path; simpl; auto.
    destruct tree; simpl; intuition; subst.
  Qed.

  Lemma root_inode_rep_file : forall tree path subtree inum f,
      root_inode_rep tree ->
      find_subtree path tree = Some (TreeFile inum f) ->
      root_inode_rep (update_subtree path subtree tree).
  Proof.
    intros.
    apply root_inode_rep_update; auto.
    intros; subst; simpl in *.
    exfalso.
    inversion H0; subst.
    unfold root_inode_rep in *.
    intuition.
  Qed.

  Lemma root_inode_rep_dir : forall tree path subtree dnum elems,
      root_inode_rep tree ->
      find_subtree path tree = Some (TreeDir dnum elems) ->
      dirtree_inum subtree = dnum ->
      dirtree_isdir subtree = true ->
      root_inode_rep (update_subtree path subtree tree).
  Proof.
    intros.
    apply root_inode_rep_update; auto.
    intros; subst; simpl in *.
    inversion H0; subst.
    unfold root_inode_rep in *; intuition.
  Qed.

  Local Lemma root_inode_rep_refold : forall tree,
      dirtree_inum tree = FSLayout.FSXPRootInum (fsxp P) ->
      dirtree_isdir tree = true ->
      root_inode_rep tree.
  Proof.
    unfold root_inode_rep; intuition.
  Qed.

  Hint Resolve root_inode_rep_refold.

  Ltac simp :=
    repeat match goal with
           | _ => solve [ auto ]
           | _ => progress intros
           | [ H: Some _ = Some _ |- _ ] =>
             inversion H; subst; clear H
           | [ H: TreeDir _ _ = TreeDir _ _ |- _ ] =>
             inversion H; subst; clear H
           | _ => progress subst
           | _ => progress simpl in *
           end.

  Lemma root_inode_rep_rename:
    forall (dnum : nat) (srcpath dstpath : list string) (tree : dirtree)
      (tree_elem : list (string * dirtree)),
      root_inode_rep tree ->
      forall (srcnum : nat) (srcents : list (string * dirtree)) (dstnum : nat)
        (dstents : list (string * dirtree)),
        find_subtree srcpath (TreeDir dnum tree_elem) = Some (TreeDir srcnum srcents) ->
        forall (cwd : list string) (tree_ents'' tree_ents' : list (string * dirtree)),
          find_subtree dstpath (update_subtree srcpath (TreeDir srcnum tree_ents') (TreeDir dnum tree_elem)) =
          Some (TreeDir dstnum dstents) ->
          find_subtree cwd tree = Some (TreeDir dnum tree_elem) ->
          root_inode_rep (update_subtree cwd
                                         (update_subtree dstpath (TreeDir dstnum tree_ents'')
                                                         (update_subtree srcpath (TreeDir srcnum tree_ents') (TreeDir dnum tree_elem))) tree).
  Proof.
    intros.
    unfold root_inode_rep in *|-; intuition.
    eapply root_inode_rep_update; simp.
    destruct dstpath, srcpath; simp.
  Qed.

  Notation "'fs_inv' ( sigma , tree , homedirs )" :=
    (fs_invariant (Sigma.l sigma) (Sigma.init_disk sigma) (Sigma.disk sigma) (Sigma.hm sigma) tree homedirs (Sigma.mem sigma))
      (at level 50,
       format "'fs_inv' '(' sigma ','  tree ','  homedirs ')'").

  Definition fs_guarantee tid (sigma sigma':Sigma) :=
    exists tree tree' homedirs,
      fs_inv(sigma, tree, homedirs) /\
      fs_inv(sigma', tree', homedirs) /\
      homedir_guarantee tid homedirs tree tree'.

  Theorem fs_rely_same_fstree : forall tid sigma sigma' tree homedirs,
      fs_inv(sigma, tree, homedirs) ->
      fs_inv(sigma', tree, homedirs) ->
      Rely fs_guarantee tid sigma sigma'.
  Proof.
    intros.
    constructor.
    exists (S tid); intuition.
    unfold fs_guarantee.
    descend; intuition eauto.
    reflexivity.
  Qed.

  Section InvariantUniqueness.

    Ltac mem_eq m a v :=
      match goal with
      | [ H: context[ptsto a v] |- _ ] =>
        let Hptsto := fresh in
        assert ((exists F, F * a |-> v)%pred m) as Hptsto by
              (SepAuto.pred_apply' H; SepAuto.cancel);
        unfold exis in Hptsto; destruct Hptsto;
        apply ptsto_valid' in Hptsto
      end.

    Lemma fs_invariant_tree_unique : forall l d_i d hm tree homedirs
                                       l' d_i' d' hm' tree' homedirs' m,
        fs_invariant l d_i d hm tree homedirs m ->
        fs_invariant l' d_i' d' hm' tree' homedirs' m ->
        tree = tree'.
    Proof.
      unfold fs_invariant; intros.
      mem_eq m (fstree P) (abs tree).
      mem_eq m (fstree P) (abs tree').
      rewrite H1 in H2; inversion H2; inj_pair2.
      auto.
    Qed.

    Lemma fs_invariant_homedirs_unique : forall l d_i d hm tree homedirs
                                           l' d_i' d' hm' tree' homedirs' m,
        fs_invariant l d_i d hm tree homedirs m ->
        fs_invariant l' d_i' d' hm' tree' homedirs' m ->
        homedirs = homedirs'.
    Proof.
      unfold fs_invariant; intros.
      mem_eq m (fshomedirs P) (abs homedirs).
      mem_eq m (fshomedirs P) (abs homedirs').
      rewrite H1 in H2; inversion H2; inj_pair2.
      auto.
    Qed.

  End InvariantUniqueness.

  Ltac invariant_unique :=
    repeat match goal with
           | [ H: fs_invariant _ _ _ _ ?tree _ ?m,
                  H': fs_invariant _ _ _ _ ?tree' _ ?m |- _ ] =>
             first [ constr_eq tree tree'; fail 1 |
                     assert (tree' = tree) by
                         apply (fs_invariant_tree_unique H' H); subst ]
           | [ H: fs_invariant _ _ _ _ _ ?homedirs ?m,
                  H': fs_invariant _ _ _ _ _ ?homedirs' ?m |- _ ] =>
             first [ constr_eq homedirs homedirs'; fail 1 |
                     assert (homedirs' = homedirs) by
                         apply (fs_invariant_homedirs_unique H' H); subst ]
           end.

  Theorem fs_rely_invariant : forall tid sigma sigma' tree homedirs,
      fs_inv(sigma, tree, homedirs) ->
      Rely fs_guarantee tid sigma sigma' ->
      (exists tree',
        fs_inv(sigma', tree', homedirs)).
  Proof.
    unfold fs_guarantee; intros.
    generalize dependent tree.
    induction H0; intros; repeat deex; eauto.
    invariant_unique.
    eauto.
    edestruct IHclos_refl_trans1; eauto.
  Qed.

  Lemma fs_rely_invariant' : forall tid sigma sigma',
      Rely fs_guarantee tid sigma sigma' ->
      forall tree homedirs,
        fs_inv(sigma, tree, homedirs) ->
        exists tree',
          fs_inv(sigma', tree', homedirs).
  Proof.
    intros.
    eapply fs_rely_invariant; eauto.
  Qed.

  Theorem homedir_guarantee_rely : forall tid homedirs tree tree',
      Relation_Operators.clos_refl_trans
        _ (fun tree tree' =>
             exists tid', tid <> tid' /\
                     homedir_guarantee tid' homedirs tree tree') tree tree' ->
      homedir_rely tid homedirs tree tree'.
  Proof.
    intros.
    apply Operators_Properties.clos_rt_rt1n in H.
    induction H.
    unfold homedir_rely; auto.
    deex.
    specialize (H2 tid); intuition.
    unfold homedir_rely in *; congruence.
  Qed.

  Theorem fs_homedir_rely : forall tid sigma sigma' tree homedirs tree',
      fs_inv(sigma, tree, homedirs) ->
      Rely fs_guarantee tid sigma sigma' ->
      fs_inv(sigma', tree', homedirs) ->
      homedir_rely tid homedirs tree tree'.
  Proof.
    unfold fs_guarantee; intros.
    generalize dependent tree'.
    generalize dependent tree.
    apply Operators_Properties.clos_rt_rt1n in H0.
    induction H0; intros; repeat deex; invariant_unique.
    - reflexivity.
    - match goal with
      | [ H: homedir_guarantee _ _ _ _ |- _ ] =>
        specialize (H _ ltac:(intuition eauto))
      end.
      specialize (IHclos_refl_trans_1n _ ltac:(eauto) _ ltac:(eauto)).
      unfold homedir_rely in *; congruence.
  Qed.

  Lemma fs_rely_preserves_subtree : forall tid sigma sigma' tree homedirs tree' path f,
      find_subtree (homedirs tid ++ path) tree = Some f ->
      fs_inv(sigma, tree, homedirs) ->
      Rely fs_guarantee tid sigma sigma' ->
      fs_inv(sigma', tree', homedirs) ->
      find_subtree (homedirs tid ++ path) tree' = Some f.
  Proof.
    intros.
    eapply fs_homedir_rely in H1; eauto.
    unfold homedir_rely in H1.
    eapply find_subtree_app' in H; repeat deex.
    erewrite find_subtree_app; eauto.
    congruence.
  Qed.

  Theorem fs_guarantee_refl : forall tid sigma homedirs,
      (exists tree, fs_inv(sigma, tree, homedirs)) ->
      fs_guarantee tid sigma sigma.
  Proof.
    intros; deex.
    unfold fs_guarantee; descend; intuition eauto.
    reflexivity.
  Qed.

  Theorem fs_guarantee_trans : forall tid sigma sigma' sigma'',
      fs_guarantee tid sigma sigma' ->
      fs_guarantee tid sigma' sigma'' ->
      fs_guarantee tid sigma sigma''.
  Proof.
    unfold fs_guarantee; intuition.
    repeat deex; invariant_unique.

    descend; intuition eauto.
    etransitivity; eauto.
  Qed.

  Theorem fs_rep_hashmap_incr : forall vd tree mscs hm hm',
      fs_rep vd hm mscs tree ->
      hashmap_le hm hm' ->
      fs_rep vd hm' mscs tree.
  Proof.
    unfold fs_rep; intros.
    repeat deex.
    exists sm, ds, ilist, frees; intuition.
    eapply LOG.rep_hashmap_subset; eauto.
  Qed.

  Lemma fs_invariant_free : forall d_i d hm tree homedirs h,
      fs_invariant Free d_i d hm tree homedirs h ->
      d_i = d.
  Proof.
    unfold fs_invariant; intros.
    SepAuto.destruct_lifts; intuition.
  Qed.

  Lemma fs_invariant_free_to_owned : forall tid d_i d hm tree homedirs h,
      fs_invariant Free d_i d hm tree homedirs h ->
      fs_invariant (Owned tid) d d hm tree homedirs h.
  Proof.
    intros.
    unfold fs_invariant in *.
    SepAuto.destruct_lifts; intuition subst.
    SepAuto.pred_apply; SepAuto.cancel; eauto.
    SepAuto.pred_apply; SepAuto.cancel; eauto.
  Qed.

End FilesystemProtocol.

(* re-export this notation with the P parameter *)
Notation "'fs_inv' ( P , sigma , tree , homedirs )" :=
  (fs_invariant P (Sigma.l sigma) (Sigma.init_disk sigma) (Sigma.disk sigma) (Sigma.hm sigma) tree homedirs (Sigma.mem sigma))
    (at level 50,
     format "'fs_inv' '(' P ','  sigma ','  tree ','  homedirs ')'").

(* Local Variables: *)
(* company-coq-local-symbols: (("Sigma" . ?Σ) ("sigma" . ?σ) ("sigma'" . (?σ (Br . Bl) ?'))) *)
(* End: *)
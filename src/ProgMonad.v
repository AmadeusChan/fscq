Require Import Prog.
Require Import Hoare.
Require Import Eqdep.
Require Import Morphisms.

Set Implicit Arguments.

Ltac inj_existT :=
  match goal with
  | [ H: existT ?P ?p _ = existT ?P ?p _ |- _ ] =>
    apply inj_pair2 in H
  end.

Ltac inv_step :=
  match goal with
  | [ H: step _ _ _ _ _ _ |- _ ] =>
    inversion H;
    repeat inj_existT;
    subst;
    clear H
  end.

Ltac inv_fail_step :=
  try match goal with
      | [ H: exec _ _ _ (Failed _) |- _ ] =>
        inversion H; repeat inj_existT; subst; clear H
      end;
  match goal with
  | [ H: fail_step _ _ |- _ ] =>
    inversion H; subst; clear H
  end.

Ltac inv_crash_step :=
  try match goal with
      | [ H: exec _ _ _ (Crashed _ _ _) |- _ ] =>
        inversion H; repeat inj_existT; subst; clear H
      end;
  match goal with
  | [ H: crash_step _ |- _ ] =>
    inversion H; subst; clear H
  end.

Ltac inv_exec' H :=
    inversion H;
    repeat inj_existT; subst;
    try inv_step;
    try inv_fail_step;
    try inv_crash_step;
    subst;
    clear H.

Ltac inv_exec :=
  lazymatch goal with
  | [ H: exec _ _ (Ret _) _ |- _ ] =>
    inv_exec' H
  | [ H: exec _ _ (Bind _ _) _ |- _ ] =>
    inv_exec' H
  | [ H: exec _ _ _ _ |- _ ] =>
    inv_exec' H
  end.

Section MonadLaws.

  Definition prog_equiv T : prog T -> prog T -> Prop :=
    fun p1 p2 => forall m hm out,
        exec m hm p1 out <-> exec m hm p2 out.

  Arguments prog_equiv {T} _ _.

  Infix "~=" := prog_equiv (at level 50, left associativity).

  Global Instance prog_equiv_equivalence T :
    Equivalence (@prog_equiv T).
  Proof.
    split; hnf; unfold prog_equiv; firstorder.
    eapply H0. eapply H. trivial.
    eapply H. eapply H0. trivial.
  Qed.

  Theorem bind_left_id : forall T T' v (p: T -> prog T'),
      Bind (Ret v) p ~= p v.
  Proof.
    split; intros.
    - inv_exec.
      inv_exec; eauto.
    - eauto.
  Qed.

  Theorem bind_right_id : forall T (p: prog T),
      Bind p Ret ~= p.
  Proof.
    split; intros.
    - inv_exec; eauto.
      inv_exec; eauto.
    - destruct out; eauto.
  Qed.

  Theorem bind_assoc : forall T T' T'' (p1: prog T) (p2: T -> prog T') (p3: T' -> prog T''),
      Bind (Bind p1 p2) p3 ~= Bind p1 (fun x => Bind (p2 x) p3).
  Proof.
    split; intros.
    - inv_exec; eauto;
        inv_exec; eauto.
    - inv_exec; eauto.
      inv_exec; eauto.
  Qed.

  Theorem corr2_equivalence : forall T (p p': prog T) pre,
      corr2 pre p' ->
      prog_equiv p p' ->
      corr2 pre p.
  Proof.
    unfold corr2; intros.
    match goal with
    | [ H: _ ~= _ |- _ ] =>
      edestruct H; eauto
    end.
  Qed.

End MonadLaws.

Ltac monad_simpl_one :=
  match goal with
  | [ |- {{_}} Bind (Ret _) _ ] =>
    eapply corr2_equivalence;
    [ | apply bind_left_id ]
  | [ |- {{_}} Bind _ Ret ] =>
    eapply corr2_equivalence;
    [ | apply bind_right_id ]
  | [ |- {{_}} Bind (Bind _ _) _ ] =>
    eapply corr2_equivalence;
    [ | apply bind_assoc ]
  end.

Ltac monad_simpl := repeat monad_simpl_one.
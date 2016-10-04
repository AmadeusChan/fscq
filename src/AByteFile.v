Require Import Arith.
Require Import Pred PredCrash.
Require Import Word.
Require Import Prog ProgMonad.
Require Import Hoare.
Require Import SepAuto.
Require Import BasicProg.
Require Import Omega.
Require Import Log.
Require Import Array.
Require Import List ListUtils.
Require Import Bool.
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
Require Import BFile.
Require Import Bytes.
Require Import VBConv.
Require Import Fscq.Hashmap.
Require Import Errno.


Set Implicit Arguments.

Module ABYTEFILE.

(* Definitions *)
Definition attr := INODE.iattr.
Definition attr0 := INODE.iattr0.

Record proto_bytefile := mk_proto_bytefile {
  PByFData : list (list byteset)
}.
Definition proto_bytefile0 := mk_proto_bytefile nil.

Record unified_bytefile := mk_unified_bytefile {
  UByFData : list byteset
}.
Definition unified_bytefile0 := mk_unified_bytefile nil.

Record bytefile := mk_bytefile {
  ByFData : list byteset;
  ByFAttr : INODE.iattr
}.
Definition bytefile0 := mk_bytefile nil attr0.

Definition bfiledata2protobytefile fd : proto_bytefile :=
mk_proto_bytefile (map valuset2bytesets fd).

Definition protobytefile2unifiedbytefile pfy : unified_bytefile :=
mk_unified_bytefile (concat (PByFData pfy)). 

Definition unifiedbytefile2bytefiledata ufy len: list byteset :=
(firstn len (UByFData ufy)).

Definition unifiedbytefile2bytefile ufy len iattr: bytefile :=
mk_bytefile (firstn len (UByFData ufy)) iattr.

Definition bfiledata2bytefiledata fd len: list byteset:=
unifiedbytefile2bytefiledata (protobytefile2unifiedbytefile (bfiledata2protobytefile fd)) len.

Definition bfile2bytefile f len: bytefile:=
unifiedbytefile2bytefile (protobytefile2unifiedbytefile (bfiledata2protobytefile (BFILE.BFData f))) len (BFILE.BFAttr f).

Fixpoint upd_range {V} (m : @Mem.mem addr addr_eq_dec V) (a : addr) (l : list V) : @Mem.mem addr _ V :=
		match l with
		| nil => m
		| h::t => upd_range (Mem.upd m a h) (a+1) t
		end.


Definition ext_opt T (ov: option T) def :=
match ov with
| None => def
| Some v => v
end.

(* rep invariants *)
Definition proto_bytefile_valid f pfy: Prop :=
(PByFData pfy) = map valuset2bytesets (BFILE.BFData f).

Definition unified_bytefile_valid pfy ufy: Prop := 
UByFData ufy = concat (PByFData pfy).

Definition bytefile_valid ufy fy: Prop :=
ByFData fy = firstn (length(ByFData fy)) (UByFData ufy).
  
Definition rep (f:BFILE.bfile) (fy:bytefile) :=
(exis (AT:= addr) (AEQ:= addr_eq_dec) (V:= valuset) (fun pfy:proto_bytefile => 
  (exis (fun ufy:unified_bytefile => 
    [[ proto_bytefile_valid f pfy ]] *
    [[ unified_bytefile_valid pfy ufy ]] *
    [[ bytefile_valid ufy fy ]] * 
    [[ ByFAttr fy = BFILE.BFAttr f ]] *
    [[ #(INODE.ABytes (ByFAttr fy)) = length (ByFData fy)]] *
    [[ length (ByFData fy) > 0 -> length (ByFData fy) > (length (BFILE.BFData f) - 1) * valubytes ]]))))%pred .


(* Helper lemmas.*)

Lemma diskIs_id: forall AT AEQ V (m:Mem.mem), @diskIs AT AEQ V m m.
Proof. intros; unfold diskIs; reflexivity. Qed.

Lemma addr_id: forall A (l: list A) a def, 
a < length l ->
((diskIs (mem_except (list2nmem l) a)) * a |-> (selN l a def))%pred (list2nmem l).
Proof.
intros.
eapply diskIs_extract.
eapply list2nmem_ptsto_cancel in H.
pred_apply; cancel.
firstorder.
Qed.

Lemma mem_except_range_O: forall AEQ V (m: @Mem.mem _ AEQ V) a,
mem_except_range m a 0 = m.
Proof.
intros.
unfold mem_except_range.
rewrite <- plus_n_O.
apply functional_extensionality.
intros.
destruct (le_dec a x);
destruct (lt_dec x a); try omega; try reflexivity.
Qed.

Fact out_except_range_then_in: forall (l: list valuset) s a n def,
a < length l ->
a < s \/ a >= s + n ->
(exists F0 : pred, (sep_star (AEQ:= addr_eq_dec) F0 (a |-> ext_opt ((list2nmem l) a) def))%pred (@mem_except_range addr_eq_dec valuset (list2nmem l) s n)).
Proof.
intros.
eexists.
apply sep_star_comm.
apply mem_except_ptsto with (a:= a).
unfold mem_except_range.
destruct H0.
destruct (le_dec s a); try omega.
unfold list2nmem, ext_opt.
erewrite selN_map.
reflexivity. auto.
destruct (lt_dec a (s + n)); try omega.
destruct (le_dec s a); try omega.
unfold list2nmem, ext_opt.
erewrite selN_map.
reflexivity. auto.
instantiate (1:= diskIs (mem_except (mem_except_range (list2nmem l) s n) a)).
apply diskIs_id.
Grab Existential Variables.
apply valuset0.
apply valuset0.
Qed.

Fact mem_ex_mem_ex_range_head: forall V AEQ i j (m: @Mem.mem _ AEQ V),
mem_except (AEQ:= AEQ) (mem_except_range m (i + 1) j) i = mem_except_range m i (j + 1).
Proof.
intros.
unfold mem_except, mem_except_range.
apply functional_extensionality; intros.
destruct (AEQ x i).
rewrite e.
destruct (le_dec i i).
destruct (lt_dec i (i + (j + 1))).
reflexivity.
omega.
omega.

destruct (le_dec i x).
destruct (le_dec (i+1) x).
destruct (lt_dec x (i + 1 + j)).
destruct (lt_dec x (i + (j + 1))).
reflexivity.
omega.
destruct (lt_dec x (i + (j + 1))).
omega.
reflexivity.
destruct (lt_dec x (i + (j + 1))).
omega.
reflexivity.
destruct (le_dec (i+1) x).
destruct (lt_dec x (i + 1 + j)).
omega.
all: reflexivity.
Qed.

Fact mem_ex_mem_ex_range_tail: forall V AEQ i j (m: @Mem.mem _ AEQ V),
mem_except (AEQ:= AEQ) (mem_except_range m i j) (i + j) = mem_except_range m i (j + 1).
Proof.
intros.
unfold mem_except, mem_except_range.
apply functional_extensionality; intros.
destruct (AEQ x (i + j)).
rewrite e.
destruct (le_dec i (i + j)).
destruct (lt_dec (i + j) (i + (j + 1))).
reflexivity.
omega.
omega.

destruct (le_dec i x).
destruct (lt_dec x (i + j)).
destruct (lt_dec x (i + (j + 1))).
reflexivity.
omega.
destruct (lt_dec x (i + (j + 1))).
omega.
reflexivity.
reflexivity.
Qed.


Lemma block_content_match: forall F f vs block_off def, 
(F * block_off|-> vs)%pred (list2nmem(BFILE.BFData f))-> 
vs = selN (BFILE.BFData f) block_off def.
Proof.
intros.
unfold valu2list.
eapply ptsto_valid' in H.
unfold list2nmem in H.
erewrite selN_map in H.
simpl in H.
unfold map in H.
symmetry;
apply some_eq. apply H.
eapply selN_map_some_range.
apply H.
Qed.

Lemma pick_from_block: forall F f block_off vs i def def', 
i < valubytes -> (F * block_off |-> vs)%pred (list2nmem (BFILE.BFData f)) ->
selN (valu2list (fst vs)) i def = selN (valu2list (fst (selN (BFILE.BFData f) block_off def'))) i def.
Proof.
intros.
erewrite block_content_match with (f:=f) (vs:=vs) (block_off:= block_off) (def:= def').
reflexivity.
apply H0.
Qed.

Lemma len_f_fy: forall f fy,
ByFData fy =
     firstn (length(ByFData fy))
       (flat_map valuset2bytesets (BFILE.BFData f))->
 length (ByFData fy) <= length (BFILE.BFData f) * valubytes.
Proof.
intros.
rewrite H.
rewrite firstn_length.
rewrite flat_map_len.
apply Min.le_min_r.
Qed.

Lemma bytefile_unified_byte_len: forall ufy fy, 
bytefile_valid ufy fy -> 
length(ByFData fy) <= length(UByFData ufy).
Proof.
intros.
rewrite H.
rewrite firstn_length.
apply Min.le_min_r.
Qed.

Lemma unified_byte_protobyte_len: forall pfy ufy k,
unified_bytefile_valid pfy ufy ->
Forall (fun sublist : list byteset => length sublist = k) (PByFData pfy) ->
length(UByFData ufy) = length (PByFData pfy) * k.
Proof.
intros.
rewrite H.
apply concat_hom_length with (k:= k).
apply H0.
Qed.

Lemma byte2unifiedbyte: forall ufy fy F a b,
bytefile_valid ufy fy ->
(F * a|-> b)%pred (list2nmem (ByFData fy)) ->
 (F * (arrayN (ptsto (V:= byteset)) (length(ByFData fy)) 
          (skipn (length(ByFData fy)) (UByFData ufy)))
  * a|->b)%pred (list2nmem (UByFData ufy)).
Proof.
unfold bytefile_valid; intros.
pose proof H0.
rewrite H in H0.
apply list2nmem_sel with (def:= byteset0) in H0.
rewrite H0.
rewrite selN_firstn.
apply sep_star_comm.
apply sep_star_assoc.
replace (list2nmem(UByFData ufy))
    with (list2nmem(ByFData fy ++ skipn (length (ByFData fy)) (UByFData ufy))).
apply list2nmem_arrayN_app.
apply sep_star_comm.
rewrite selN_firstn in H0.
rewrite <- H0.
apply H1.
apply list2nmem_inbound in H1.
apply H1.
rewrite H.
rewrite firstn_length.
rewrite Min.min_l. 
rewrite firstn_skipn.
reflexivity.
apply bytefile_unified_byte_len.
apply H.
apply list2nmem_inbound in H1.
apply H1.
Qed.

Lemma unifiedbyte2protobyte: forall pfy ufy a b F k,
unified_bytefile_valid pfy ufy ->
Forall (fun sublist : list byteset => length sublist = k) (PByFData pfy) ->
k > 0 ->
(F * a|->b)%pred (list2nmem (UByFData ufy)) ->
(diskIs (mem_except (list2nmem (PByFData pfy)) (a/k))  * 
(a/k) |-> get_sublist (UByFData ufy) ((a/k) * k) k)%pred (list2nmem (PByFData pfy)).
Proof.
unfold get_sublist, unified_bytefile_valid.
intros.
rewrite H.
rewrite concat_hom_skipn with (k:= k).
replace (k) with (1 * k) by omega.
rewrite concat_hom_firstn.
rewrite firstn1.
rewrite skipn_selN.
simpl.
repeat rewrite <- plus_n_O.
apply addr_id.
apply Nat.div_lt_upper_bound.
unfold not; intros.
rewrite H3 in H1; inversion H1.
rewrite Nat.mul_comm.
rewrite <- unified_byte_protobyte_len with (ufy:= ufy).
apply list2nmem_inbound in H2.
apply H2.
apply H.
apply H0.
simpl;  rewrite <- plus_n_O.
apply forall_skipn.
apply H0.
apply H0.
Qed.

Lemma protobyte2block: forall a b f pfy,
proto_bytefile_valid f pfy ->
(diskIs (mem_except (list2nmem (PByFData pfy)) a) * a|->b)%pred (list2nmem (PByFData pfy)) ->
(diskIs (mem_except (list2nmem (BFILE.BFData f)) a) * a|->(bytesets2valuset b))%pred (list2nmem (BFILE.BFData f)).
Proof.
unfold proto_bytefile_valid; intros.
rewrite H in H0.
pose proof H0.
eapply list2nmem_sel in H0.
erewrite selN_map in H0.
rewrite H0.
rewrite valuset2bytesets2valuset.
apply addr_id.
apply list2nmem_inbound in H1.
rewrite map_length in H1.
apply H1.
apply list2nmem_inbound in H1.
rewrite map_length in H1.
apply H1.
Grab Existential Variables.
apply nil.
apply valuset0.
Qed. 

Lemma bytefile_bfile_eq: forall f pfy ufy fy,
proto_bytefile_valid f pfy -> 
unified_bytefile_valid pfy ufy -> 
bytefile_valid ufy fy ->
ByFData fy = firstn (length (ByFData fy)) (flat_map valuset2bytesets (BFILE.BFData f)).
Proof.
unfold proto_bytefile_valid, 
    unified_bytefile_valid, 
    bytefile_valid.
intros.
destruct_lift H.
rewrite flat_map_concat_map.
rewrite <- H.
rewrite <- H0.
apply H1.
Qed.

Fact inlen_bfile: forall f pfy ufy fy i j Fd data, 
proto_bytefile_valid f pfy ->
unified_bytefile_valid pfy ufy ->
bytefile_valid ufy fy ->
j < valubytes -> length data > 0 ->
(Fd ✶ arrayN (ptsto (V:=byteset)) (i * valubytes + j) data)%pred (list2nmem (ByFData fy)) ->
i < length (BFILE.BFData f).
Proof.
intros.
eapply list2nmem_arrayN_bound in H4.
destruct H4.
rewrite H4 in H3.
inversion H3.
rewrite len_f_fy with (f:=f) (fy:=fy) in H4.
apply le2lt_l in H4.
apply lt_weaken_l with (m:= j) in H4.
apply lt_mult_weaken in H4.
apply H4.
apply H3.
eapply bytefile_bfile_eq; eauto.
Qed.

Fact block_exists: forall f pfy ufy fy i j Fd data,
proto_bytefile_valid f pfy ->
unified_bytefile_valid pfy ufy ->
bytefile_valid ufy fy ->
j < valubytes -> length data > 0 ->
(Fd ✶ arrayN (ptsto (V:=byteset)) (i * valubytes + j) data)%pred (list2nmem (ByFData fy)) ->
exists F vs, (F ✶ i |-> vs)%pred (list2nmem (BFILE.BFData f)).
Proof.
intros.
repeat eexists.
eapply unifiedbyte2protobyte with (a:= i * valubytes + j) (k:= valubytes)in H0.
rewrite div_eq in H0.
unfold proto_bytefile_valid in H.
eapply protobyte2block; eauto.
apply H2.
apply Forall_forall; intros.
rewrite H in H5.
apply in_map_iff in H5.
destruct H5.
inversion H5.
rewrite <- H6.
apply valuset2bytesets_len.
omega.
eapply byte2unifiedbyte.
eauto.
pred_apply.
rewrite arrayN_isolate with (i:=0).
rewrite <- plus_n_O .
cancel.
auto.
Grab Existential Variables.
apply byteset0.
Qed.

Fact proto_len: forall f pfy,
proto_bytefile_valid f pfy ->
Forall (fun sublist : list byteset => length sublist = valubytes) (PByFData pfy).
Proof.
intros.
apply Forall_forall; intros.
rewrite H in H0.
apply in_map_iff in H0.
destruct H0.
inversion H0.
rewrite <- H1.
apply valuset2bytesets_len.
Qed.

Fact proto_skip_len: forall f pfy i,
proto_bytefile_valid f pfy ->
Forall (fun sublist : list byteset => length sublist = valubytes) (skipn i (PByFData pfy)).
Proof.
intros.
apply Forall_forall; intros.
apply in_skipn_in in H0.
rewrite H in H0.
rewrite in_map_iff in H0.
repeat destruct H0.
apply valuset2bytesets_len.
Qed.

Fact content_match: forall Fd f pfy ufy fy i j data,
proto_bytefile_valid f pfy ->
unified_bytefile_valid pfy ufy ->
bytefile_valid ufy fy ->
(Fd ✶ arrayN (ptsto (V:=byteset)) (i * valubytes + j) data)%pred (list2nmem (ByFData fy)) ->
j < valubytes ->
length data > 0 ->
j + length data <= valubytes ->
get_sublist (valu2list (fst (bytesets2valuset (selN (PByFData pfy) i nil)))) j (length data) = map fst data.
 Proof.
 intros.
       
unfold get_sublist.
apply arrayN_list2nmem in H2 as H1'.
rewrite H1 in H1'.
rewrite <- skipn_firstn_comm in H1'.
rewrite firstn_firstn in H1'.
rewrite Min.min_l in H1'.
rewrite H0 in H1'.

rewrite skipn_firstn_comm in H1'.
rewrite Nat.add_comm in H1'.
rewrite <- skipn_skipn with (m:= i * valubytes) in H1'.
rewrite concat_hom_skipn in H1'.
rewrite <- skipn_firstn_comm in H1'.
erewrite <- concat_hom_subselect_firstn with (k:= valubytes) in H1'.

rewrite H in *.
erewrite selN_map in *.
rewrite valuset2bytesets2valuset.

rewrite skipn_firstn_comm in H1'.
rewrite H1'.
rewrite firstn_length.
rewrite skipn_length.
rewrite Min.min_l.
rewrite <- firstn_map_comm.
rewrite <- skipn_map_comm.

rewrite mapfst_valuset2bytesets.
reflexivity.

rewrite valuset2bytesets_len.
omega.

all: try eapply inlen_bfile; eauto.
all: try eapply proto_len; eauto.

rewrite H; rewrite map_length.
eapply inlen_bfile; eauto.

apply list2nmem_arrayN_bound in H2.
destruct H2.
rewrite H2 in H4; inversion H4.
omega.


apply byteset0.

Grab Existential Variables.
apply valuset0.
apply valuset0.
apply nil.
Qed.



Fact iblocks_file_len_eq: forall F bxp ixp flist ilist frees m inum,
inum < length ilist ->
(F * BFILE.rep bxp ixp flist ilist frees)%pred m ->
length (INODE.IBlocks (selN ilist inum INODE.inode0)) = length (BFILE.BFData (selN flist inum BFILE.bfile0)).
Proof. 
intros.
unfold BFILE.rep in H0.
repeat rewrite sep_star_assoc in H0.
apply sep_star_comm in H0.
repeat rewrite <- sep_star_assoc in H0.

unfold BFILE.file_match in H0.
rewrite listmatch_isolate with (i:=inum) in H0.
sepauto.
rewrite listmatch_length_pimpl in H0.
sepauto.
rewrite listmatch_length_pimpl in H0.
sepauto.
Qed.



Fact flist_eq_ilist: forall F F' flist flist' ilist m, 
  (@sep_star addr addr_eq_dec BFILE.datatype 
      F  (listmatch (fun (v : BFILE.datatype) (a : addr) => a |-> v) flist ilist))%pred m ->
  (@sep_star addr addr_eq_dec BFILE.datatype 
      F'  (listmatch (fun (v : BFILE.datatype) (a : addr) => a |-> v) flist' ilist))%pred m ->
  forall i def, i < length flist -> selN flist i def = selN flist' i def.
Proof.
  intros.
  eapply sep_star_ptsto_some_eq with (a:= (selN ilist i _)).
  erewrite listmatch_isolate with (i:= i) in H.
  apply sep_star_comm.
  eapply sep_star_assoc in H.
  eapply H.
  auto.
  apply listmatch_length_r in H as H'.
  rewrite <- H'; auto.
  rewrite listmatch_extract with (i:= i) in H0.
  destruct_lift H; destruct_lift H0.
  apply ptsto_valid' in H0.
  apply H0.
  apply listmatch_length_r in H as H'.
  apply listmatch_length_r in H0 as H0'.
  omega.
  Grab Existential Variables.
  apply O.
Qed.


Fact unibyte_len: forall f pfy ufy fy i,
proto_bytefile_valid f pfy ->
unified_bytefile_valid pfy ufy ->
bytefile_valid ufy fy ->
i * valubytes < length (ByFData fy) ->
(S i) * valubytes <= length (UByFData ufy).
Proof.
intros.
erewrite unified_byte_protobyte_len with (k:= valubytes); eauto.
apply mult_le_compat_r.
apply lt_le_S.
eapply lt_le_trans with (m:= length (ByFData fy)) in H2.
Focus 2.
apply bytefile_unified_byte_len; eauto.
erewrite unified_byte_protobyte_len with (k:= valubytes) in H2; eauto.
apply lt_mult_weaken in H2; auto.
eapply proto_len; eauto.
eapply proto_len; eauto.
Qed.


Fact inbound_bytefile_bfile: forall a  b f pfy ufy fy,
  proto_bytefile_valid f pfy ->
  unified_bytefile_valid pfy ufy ->
  bytefile_valid ufy fy ->
  a * valubytes + b < length (ByFData fy) ->
  a < length (BFILE.BFData f).
Proof.
intros.
apply bytefile_unified_byte_len in H1.
eapply lt_le_trans with (m:= length (ByFData fy))in H2.
2:eauto.
erewrite unified_byte_protobyte_len with (k:= valubytes) in H2.
2:eauto.
apply lt_weaken_l in H2.
rewrite H in H2.
rewrite map_length in H2.
apply lt_mult_weaken in H2.
auto.
eapply proto_len; eauto.
Qed. 


Fact bfile_bytefile_same: forall a  b f pfy ufy fy,
a * valubytes + b < length (ByFData fy) ->
b < valubytes ->
proto_bytefile_valid f pfy ->
unified_bytefile_valid pfy ufy ->
bytefile_valid ufy fy ->
selN (ByFData fy) (a * valubytes + b) byteset0 = selN (valuset2bytesets (selN (BFILE.BFData f) a valuset0)) b byteset0.
Proof.
intros.
rewrite H3; rewrite H2; rewrite H1.
rewrite selN_firstn.
rewrite concat_hom_selN.
erewrite selN_map.
reflexivity.
eapply inbound_bytefile_bfile; eauto.
rewrite <- H1; eapply proto_len; eauto.
auto.
auto.
Qed.

Fact inbound_protobyte: forall f pfy ufy fy block_off m1 nb data Fd,
proto_bytefile_valid f pfy ->
unified_bytefile_valid pfy ufy ->
bytefile_valid ufy fy ->
(Fd ✶ arrayN (ptsto (V:=byteset)) (block_off * valubytes) data)%pred (list2nmem (ByFData fy)) -> 
nb > 0 ->
length data = nb * valubytes ->
m1 < nb ->
block_off + m1 < length (PByFData pfy).
Proof.
intros.
rewrite H.
rewrite map_length.
apply list2nmem_arrayN_bound in H2 as H'.
destruct H'.
rewrite <- length_zero_iff_nil in H6.
rewrite H6 in H4; symmetry in H4; apply mult_is_O in H4.
destruct H4.
omega.
rewrite valubytes_is in *; omega.
apply list2nmem_arrayN_bound in H2.
destruct H2.
apply length_zero_iff_nil in H2; rewrite valubytes_is in *; omega.


rewrite bytefile_unified_byte_len with (ufy:= ufy) in H6; eauto.
rewrite unified_byte_protobyte_len with (pfy:= pfy)(k:=valubytes) in H6; eauto.
rewrite H4 in H6.
eapply le_lt_weaken with (k:= m1 * valubytes) in H6; eauto.
rewrite <- Nat.mul_add_distr_r in H6.
apply lt_mult_weaken in H6.
rewrite H in H6.
rewrite map_length in H6.
auto.
rewrite valubytes_is in *; omega.
eapply proto_len; eauto.
Qed.


Lemma exists_unique_bytefile_length: forall f pfy ufy fy,
proto_bytefile_valid f pfy ->
unified_bytefile_valid pfy ufy ->
bytefile_valid ufy fy ->
length (ByFData fy) mod valubytes = 0 ->
length (ByFData fy) > 0 ->
exists ! x, length (ByFData fy) = x * valubytes.
Proof.
intros.
unfold unique.
apply Nat.mod_divides in H2; destruct H2.
exists x.
split.
rewrite Nat.mul_comm; auto.
intros.
rewrite H2 in H4.
rewrite Nat.mul_comm in H4.
apply Nat.mul_cancel_r in H4; auto.
apply valubytes_ne_O.
unfold not; intros.
unfold not in *; apply mod_dem_neq_dem with (a:= length (ByFData fy)) (b:= valubytes); intros; rewrite valubytes_is in *; omega.
Qed.


Lemma bfile_protobyte_len_eq: forall f pfy,
  proto_bytefile_valid f pfy ->
  length (PByFData pfy) = length (BFILE.BFData f).
Proof.
intros.
rewrite H.
apply map_length.
Qed.



Lemma list2nmem_arrayN_middle: forall A  (l2 l1 l3: list A) a b (F:pred),
a = length l1 -> b = length l2 ->
F (mem_except_range (list2nmem (l1 ++ l2 ++ l3)) a b ) -> (F * arrayN (ptsto (V:= A)) a l2)%pred (list2nmem (l1 ++ l2 ++ l3)).
Proof.
induction l2; intros.
simpl.
apply emp_star_r.
subst.
unfold mem_except_range in H1.
rewrite app_assoc in H1.
rewrite app_nil_r in H1.
simpl in H1.
rewrite <- plus_n_O in H1.
replace (list2nmem (l1 ++ l3)) with 
        (fun a' : addr =>
       if le_dec (length l1) a' then if lt_dec a' (length l1) then None else list2nmem (l1 ++ l3) a' else list2nmem (l1 ++ l3) a').
auto.
apply functional_extensionality; intros.
destruct (le_dec (length l1) x);
destruct (lt_dec x (length l1)); try reflexivity.
omega.

subst.
rewrite arrayN_isolate with (i := 0).
simpl.
apply sep_star_assoc.
replace (length l1 + 0 + 1) with (length (l1 ++ a :: nil)).
replace (l1 ++ a :: l2 ++ l3) with ((l1 ++ (a :: nil)) ++ l2 ++ l3).
eapply IHl2 with (F:= (F ✶ (emp ✶ (length l1 + 0) |-> a))%pred).
auto.
instantiate (1:= length l2).
reflexivity.
apply sep_star_assoc.
apply sep_star_comm.
apply mem_except_ptsto.
rewrite <- plus_n_O.
unfold list2nmem.
unfold mem_except_range.
erewrite selN_map.
rewrite selN_app.
rewrite selN_app2.
replace (length l1 - length l1) with 0 by omega.
simpl.
rewrite app_length; simpl.
destruct (le_dec (length l1 + 1) (length l1)); try omega; try reflexivity.
omega.
rewrite app_length; simpl; omega.
repeat rewrite app_length; simpl; omega.
apply emp_star_r.
unfold mem_except, mem_except_range.
rewrite <- plus_n_O.
repeat rewrite app_length in *; simpl in *.
replace (fun a' : addr =>
   if addr_eq_dec a' (length l1)
   then None
   else
    if le_dec (length l1 + 1) a'
    then if lt_dec a' (length l1 + 1 + length l2) then None else list2nmem ((l1 ++ a :: nil) ++ l2 ++ l3) a'
    else list2nmem ((l1 ++ a :: nil) ++ l2 ++ l3) a')
    
with (mem_except_range (list2nmem (l1 ++ a :: l2 ++ l3)) (length l1) (S (length l2))).
auto.
unfold mem_except_range.
apply functional_extensionality; intros.

replace ((length l1 + 1 + length l2)) with (length l1 + S (length l2)) by omega.
replace (((l1 ++ a :: nil) ++ l2 ++ l3)) with (l1 ++ a :: l2 ++ l3).

destruct (le_dec (length l1 + 1) x);
destruct (le_dec (length l1) x);
destruct (addr_eq_dec x (length l1)); try omega; try reflexivity.
destruct (lt_dec x (length l1 + S (length l2))); try omega; try reflexivity.

rewrite <- app_assoc.
rewrite <- cons_app.
reflexivity.

rewrite <- app_assoc.
rewrite <- cons_app.
reflexivity.

rewrite app_length; simpl; omega.
simpl; omega.

Unshelve.
auto.
Grab Existential Variables.
auto.
Qed. 

Lemma arrayN_frame_mem_ex_range: forall A (l: list A) (F:pred) a m,
(F * arrayN (ptsto (V:= A)) a l)%pred m -> F (mem_except_range m a (length l) ).
Proof.
induction l; intros.
simpl in *.
unfold mem_except_range.
rewrite <- plus_n_O.
replace ((fun a' : addr => if le_dec a a' then if lt_dec a' a then None else m a' else m a')) with m.
apply sep_star_comm in H.
apply star_emp_pimpl in H; auto.
apply functional_extensionality; intros.
destruct (le_dec a x);
destruct (lt_dec x a);
try omega; try reflexivity.
replace (mem_except_range m a0 (length (a :: l))) with (mem_except_range (mem_except m a0) (a0 + 1) (length l)).
apply IHl.
rewrite isolateN_fwd with (i:= 0) in H; simpl in H.
rewrite star_emp_pimpl in H.
rewrite <- plus_n_O in H.
apply sep_star_comm in H.
apply sep_star_assoc in H.
apply ptsto_mem_except in H. pred_apply; cancel.
simpl; omega.
apply functional_extensionality; intros.
unfold mem_except, mem_except_range; simpl.
replace (S (length l)) with ( 1 + length l) by omega.
rewrite Nat.add_assoc.
destruct (le_dec (a0 + 1) x);
destruct (lt_dec x (a0 + 1 + length l));
destruct (addr_eq_dec x a0);
destruct (le_dec a0 x);
try omega; try reflexivity.
Grab Existential Variables.
auto.
Qed. 



Lemma bfile_ge_block_off: forall f pfy ufy fy block_off old_data Fd m1 l_old_blocks,
m1 < l_old_blocks ->
length old_data = l_old_blocks * valubytes ->
proto_bytefile_valid f pfy ->
unified_bytefile_valid pfy ufy ->
bytefile_valid ufy fy ->
(Fd ✶ arrayN (ptsto (V:=byteset)) (block_off * valubytes) old_data)%pred (list2nmem (ByFData fy)) ->
block_off <= length (BFILE.BFData f).
Proof.
intros.
apply Nat.lt_le_incl.
eapply inlen_bfile with (j:= 0); eauto; try omega.
apply valubytes_ge_O.

Focus 2.
pred_apply.
rewrite <- plus_n_O.
cancel.
rewrite valubytes_is in *; omega.
Qed.

Lemma bfile_gt_block_off_m1: forall f pfy ufy fy block_off Fd m1 old_blocks,
length old_blocks > 0 -> 
m1 < length old_blocks ->
proto_bytefile_valid f pfy ->
unified_bytefile_valid pfy ufy ->
bytefile_valid ufy fy ->
(Fd ✶ arrayN (ptsto (V:=valuset)) block_off old_blocks)%pred (list2nmem (BFILE.BFData f)) ->
block_off + m1 < length (BFILE.BFData f).
Proof.
intros.
apply list2nmem_arrayN_bound in H4 as H''.
destruct H''.
apply length_zero_iff_nil in H5.
assert (X: forall a, a = 0 -> a > 0 -> False). intros. omega.
apply X in H5.  
contradiction.
auto.
eapply le_lt_weaken in H5.
eapply H5.
auto.
Qed.

Lemma bfile_ge_block_off_m1: forall f pfy ufy fy block_off Fd m1 old_blocks,
length old_blocks > 0 -> 
m1 < length old_blocks ->
proto_bytefile_valid f pfy ->
unified_bytefile_valid pfy ufy ->
bytefile_valid ufy fy ->
(Fd ✶ arrayN (ptsto (V:=valuset)) block_off old_blocks)%pred (list2nmem (BFILE.BFData f)) ->
block_off + m1 <= length (BFILE.BFData f).
Proof.
intros.
apply list2nmem_arrayN_bound in H4 as H''.
destruct H''.
apply length_zero_iff_nil in H5.
assert (X: forall a, a = 0 -> a > 0 -> False). intros. omega.
apply X in H5.  
contradiction.
auto.

eapply le_lt_weaken in H5.
2: eauto.
omega.
Qed.

Lemma bytefile_ge_block_off_v: forall fy block_off Fd old_data, 
length old_data > 0 ->
(Fd ✶ arrayN (ptsto (V:=byteset)) (block_off * valubytes) old_data)%pred (list2nmem (ByFData fy)) ->
block_off * valubytes <= length (ByFData fy).
Proof. 
intros.
apply list2nmem_arrayN_bound in H0 as H'.
destruct H'.
rewrite H1 in H; inversion H.
omega.
Qed.

Lemma bytefile_ge_block_off_m1_v: forall fy block_off Fd old_data m1 l_old_blocks, 
m1 < l_old_blocks ->
length old_data = l_old_blocks * valubytes ->
(Fd ✶ arrayN (ptsto (V:=byteset)) (block_off * valubytes) old_data)%pred (list2nmem (ByFData fy)) ->
(block_off + m1 + 1) * valubytes <= length (ByFData fy).
Proof. 
intros.
apply list2nmem_arrayN_bound in H1 as H'.
destruct H'.
pose proof length_old_data_ge_O; eauto.
apply length_zero_iff_nil in H2.
eapply H3 in H; eauto.
inversion H.
omega.
rewrite valubytes_is in *; omega.
Qed.

Lemma bfile_bytefile_length: forall f pfy ufy fy,
  proto_bytefile_valid f pfy ->
  unified_bytefile_valid pfy ufy ->
  bytefile_valid ufy fy -> 
  length (ByFData fy) <= length (BFILE.BFData f) * valubytes.
Proof.
	intros.
	erewrite <- bfile_protobyte_len_eq; eauto.
	erewrite <- unified_byte_protobyte_len; eauto.
	apply bytefile_unified_byte_len; eauto.
	eapply proto_len; eauto.
Qed. 

Lemma list2nmem_upd_updN: forall A a (l l': list A) x,
a < length l' ->
Mem.upd (list2nmem l') a x = list2nmem l -> l = updN l' a x.
Proof.
	intros.
	rewrite <- listupd_memupd in H0.
	apply list2nmem_inj in H0.
	symmetry; auto.
	auto.
Qed.

Lemma mem_except_range_unfold: forall A (l: list A) a n,
a < length l ->
mem_except_range (list2nmem l) a (S n) = mem_except_range (mem_except (list2nmem l) a) (S a) n.
Proof.
	intros.
	apply functional_extensionality; intros.
	unfold mem_except_range; simpl.
	destruct (le_dec a x); simpl.
	destruct (le_dec (S a) x).
	rewrite plus_n_Sm.
	destruct (lt_dec x (a + S n)).
	reflexivity.
	unfold mem_except; simpl.
	destruct (Nat.eq_dec x a).
	omega.
	reflexivity.
	apply Nat.nle_gt in n0.
	inversion n0.
	destruct (lt_dec a (a + S n)).
	rewrite mem_except_eq.
	reflexivity.
	omega.
	omega.
	destruct (le_dec (S a) x).
	omega.
	unfold mem_except.
	destruct (Nat.eq_dec x a).
	omega.
	reflexivity.
Qed.

Lemma mem_except_range_out_apply: forall A (l1 l2 l2' l3: list A) a1 a2 le1 le2,
a1 = a2 -> le1 = le2 -> a1 = length l1 -> le1 = length l2 -> length l2 = length l2' ->
mem_except_range (list2nmem (l1++l2++l3)) a1 le1 = (mem_except_range (list2nmem (l1++l2'++l3)) a2 le2).
Proof.
	intros; apply functional_extensionality; intros.
	unfold mem_except_range; simpl; subst.
	destruct (le_dec a2 x);
	destruct (lt_dec x (a2 + le2)); try reflexivity; try omega.
	unfold list2nmem.
	apply Nat.nlt_ge in n.
	repeat rewrite map_app.
	repeat rewrite selN_app2.
	repeat rewrite map_length.
	rewrite H3.
	reflexivity.
	all: repeat rewrite map_length.
	all: subst.
	all: try omega.
	apply Nat.nle_gt in n.
	unfold list2nmem.
	repeat rewrite map_app.
	repeat rewrite selN_app1.
	reflexivity.
	all: repeat rewrite map_length; omega.
Qed.

Lemma diskIs_arrayN: forall A (l: list A) a b,
a + b <= length l ->
(diskIs (mem_except_range (list2nmem l) a b) * arrayN (ptsto (V:= A)) a (firstn b (skipn a l)))%pred (list2nmem l).
Proof.
	intros;
	remember (diskIs (mem_except_range (list2nmem l) a b)) as F;
	remember (firstn b (skipn a l)) as x.
	replace l with (firstn a l ++ firstn b (skipn a l) ++ skipn (a + b) l).
	rewrite Heqx; eapply list2nmem_arrayN_middle.
	rewrite firstn_length_l. reflexivity.
	omega.
	instantiate (1:= b).
	rewrite firstn_length_l. reflexivity.
	rewrite skipn_length.
	omega.
	rewrite app_assoc.
	rewrite <- firstn_sum_split.
	rewrite firstn_skipn.
	rewrite HeqF; apply diskIs_id.
	rewrite app_assoc.
	rewrite <- firstn_sum_split.
	rewrite firstn_skipn.
	reflexivity.
Qed.

Lemma diskIs_eq: forall AT AEQ V (m m': @Mem.mem AT AEQ V),
(diskIs m') m ->
m = m'.
Proof.
    unfold diskIs.
    intros; symmetry; auto.
Qed.

  
Lemma upd_mem_except_range_comm: forall AEQ V a a0 b v (m: _ AEQ V),
a0 < a \/ a0 > a + b ->
Mem.upd (AEQ:= AEQ) (mem_except_range m a b) a0 v = mem_except_range (Mem.upd m a0 v) a b.
Proof.
  intros; unfold Mem.upd, mem_except_range.
  destruct H;
  apply functional_extensionality; intros;
  destruct (AEQ x a0); 
  destruct (le_dec a x);
  destruct (lt_dec x (a+b)); try omega; try reflexivity.
Qed.

Lemma diskIs_combine_upd_range: forall V (l: list V) m a b ,
b = length l ->
(diskIs (mem_except_range m a b) * arrayN (ptsto (V:=V)) a l) =p=> diskIs (upd_range m a l).
Proof.
  induction l; intros.
  simpl in *.
  rewrite H.
  rewrite mem_except_range_O.
  cancel.
  destruct b.
  simpl in H; inversion H.
  rewrite arrayN_isolate_hd.
  simpl.
  rewrite <- sep_star_assoc.
  erewrite diskIs_combine_upd.
  replace (S b) with (b + 1) by omega.
  rewrite <- mem_ex_mem_ex_range_head.
  
  rewrite diskIs_combine_upd.
  rewrite upd_mem_except_range_comm.
  apply IHl.
  simpl in H; inversion H; auto.
  left; omega.
  destruct (m a0) eqn:D.
  eapply ptsto_upd' with (v0:= v).
  apply sep_star_comm.
  apply mem_except_ptsto.
  auto.
  apply diskIs_id.
  apply ptsto_upd_disjoint.
  rewrite mem_except_none.
  apply diskIs_id.
  all: auto.
  simpl; omega.
  Grab Existential Variables.
  trivial.
Qed.

Lemma upd_range_list2nmem_comm: forall A (l' l: list A) a,
a + length l' <= length l ->
upd_range (list2nmem l) a l' = list2nmem (firstn a l ++ l' ++ skipn (a + length l') l).
Proof.
  induction l'; intros.
  simpl.
  rewrite <- plus_n_O; rewrite firstn_skipn; reflexivity.
  simpl.
  rewrite <- listupd_memupd.
  replace (firstn a0 l ++ a :: l' ++ skipn (a0 + S (length l')) l)
    with (firstn (a0 + 1) (l ⟦ a0 := a ⟧) ++ l' ++ skipn ((a0 + 1) + length l') (l ⟦ a0 := a ⟧)).
  apply IHl'.
  rewrite length_updN.
  simpl in H; omega.
  rewrite updN_firstn_skipn.
  rewrite app_comm_cons.
  rewrite app_assoc.
  rewrite app_assoc.
  rewrite firstn_app_l.
  rewrite firstn_oob.
  rewrite skipn_app_r_ge.
  rewrite skipn_skipn.
  replace (a0 + 1 + length l' - length (firstn a0 l ++ a :: nil) + (a0 + 1))
    with (a0 + S (length l')).
  repeat rewrite app_assoc_reverse.
  rewrite <-cons_app.
  reflexivity.
  all: try (rewrite app_length; rewrite firstn_length_l; simpl in *).
  all: simpl in H; try omega.
Qed.



Lemma diskIs_arrayN_length: forall A b a (l l' l'': list A) ,
length l' = b ->
a + b <= length l ->
(diskIs (mem_except_range (list2nmem l) a b) * arrayN (ptsto (V:= A)) a l')%pred (list2nmem l'') ->
length l'' = length l.
Proof.
  intros.
  apply diskIs_combine_upd_range in H1.
  apply diskIs_eq in H1.
  rewrite upd_range_list2nmem_comm in H1.
  apply list2nmem_inj in H1.
  rewrite H1.
  repeat rewrite app_length.
  rewrite skipn_length.
  rewrite firstn_length_l.
  all: omega.
Qed.

Lemma bfile_length_eq: forall a f f' v,
a < length (BFILE.BFData f) ->
(diskIs (mem_except (list2nmem (BFILE.BFData f)) a) * a |-> v )%pred (list2nmem (BFILE.BFData f')) ->
length (BFILE.BFData f') = length (BFILE.BFData f).
Proof.
  intros.
  apply diskIs_combine_upd in H0 as H'.
  apply diskIs_eq in H'.
  symmetry in H'; apply list2nmem_upd_updN in H'.
  rewrite H'.
  apply length_updN.
  auto.
Qed.

Lemma bfile_range_length_eq: forall a b f f' l,
length l = b ->
a + b <= length (BFILE.BFData f) ->
(diskIs (mem_except_range (list2nmem (BFILE.BFData f)) a b) * LOG.arrayP a l)%pred (list2nmem (BFILE.BFData f')) ->
length (BFILE.BFData f') = length (BFILE.BFData f).
Proof.
  intros.
  apply diskIs_arrayN_length in H1.
  all: auto.
Qed.

Lemma list2nmem_arrayN_updN_range: forall f f' l a,
a + length l <= length (BFILE.BFData f) ->
(diskIs (upd_range (list2nmem (BFILE.BFData f)) a l)) (list2nmem (BFILE.BFData f')) ->
BFILE.BFData f' = firstn a (BFILE.BFData f) ++ l ++ skipn (a + length l) (BFILE.BFData f).
Proof.
  intros.
  apply diskIs_eq in H0.
  rewrite upd_range_list2nmem_comm in H0.
  apply list2nmem_inj in H0.
  all: auto.
Qed.

Lemma off_div_v_inlen_bfile: forall off f pfy ufy fy old_data length_data Fd,
length_data > 0 ->
length old_data = length_data ->
proto_bytefile_valid f pfy ->
unified_bytefile_valid pfy ufy ->
bytefile_valid ufy fy ->
(Fd ✶ arrayN (ptsto (V:=byteset)) off old_data)%pred (list2nmem (ByFData fy)) ->
off / valubytes < length (BFILE.BFData f).
	Proof.
		intros;
		eapply inlen_bfile; eauto; try omega.
		instantiate (1:= off mod valubytes); apply Nat.mod_upper_bound.
		apply valubytes_ne_O.
		Focus 2.
		rewrite Nat.mul_comm.
		rewrite <- Nat.div_mod.
		eauto.
		apply valubytes_ne_O.
		omega.
	Qed.

Lemma valu2list_sublist_v: forall f i,
Forall (fun sublist : list byte => length sublist = valubytes)
  (valu2list (fst (selN (BFILE.BFData f) i valuset0))
   :: map valu2list (snd (selN (BFILE.BFData f) i valuset0))).
	Proof.
		intros; rewrite Forall_forall; intros.
		repeat destruct H.
		apply valu2list_len.
		apply in_map_iff in H.
		repeat destruct H.
		apply valu2list_len.
	Qed.


Lemma bytefile_equiv1: forall fy off length_data,
0 < length_data ->
off / valubytes * valubytes + valubytes <= length (ByFData fy) ->
length_data <= valubytes - off mod valubytes ->
length (ByFData fy) - (off / valubytes * valubytes + valubytes) =
length (ByFData fy) - off / valubytes * valubytes -
(off / valubytes * valubytes + off mod valubytes - off / valubytes * valubytes +
 (length_data +
  (off / valubytes * valubytes + valubytes -
   (off / valubytes * valubytes + off mod valubytes + length_data)))).
	Proof. intros; omega. Qed.
	
Lemma off_plus_mod_inlen_unified: forall ufy fy off,
bytefile_valid ufy fy ->
off < length (ByFData fy) ->
off / valubytes * valubytes + off mod valubytes <= length (UByFData ufy).
	Proof.
	intros;
erewrite <- bytefile_unified_byte_len; eauto.
rewrite Nat.mul_comm; rewrite <- Nat.div_mod.
apply Nat.lt_le_incl; auto.
apply valubytes_ne_O.
	Qed.

Lemma off_div_mul_inlen_unified: forall ufy fy off,
bytefile_valid ufy fy ->
off < length (ByFData fy) ->
off / valubytes * valubytes <= length (UByFData ufy).
	Proof.
	intros;
	erewrite <- bytefile_unified_byte_len; eauto.
	rewrite Nat.mul_comm; rewrite Nat.mul_div_le.
	apply Nat.lt_le_incl; auto.
	apply valubytes_ne_O.
	Qed.
	



	Lemma list2nmem_arrayN_app': forall A (l l': list A) a (F: pred),
a = length l ->
F (list2nmem l) ->
(F * arrayN (ptsto (V:= A)) a l')%pred (list2nmem (l++l')).
	Proof. intros; subst; apply list2nmem_arrayN_app; auto. Qed.
	
	
Definition ptsto_subset_b {AT AEQ} (a : AT) (bs : byteset) : @pred AT AEQ byteset :=
  (exists old, a |-> (fst bs, old) * [[incl (fst bs :: old) (fst bs :: snd bs)]])%pred.

Lemma ptsto_subset_b_to_ptsto: forall l l' F a,
(F ✶ arrayN ptsto_subset_b a l')%pred (list2nmem l) ->
exists l'', (F ✶ arrayN (ptsto (V:= byteset)) a l'')%pred (list2nmem l) /\ length l' = length l''.
	Proof.
		induction l'; intros.
		simpl in H.
		exists nil.
		simpl; auto.
		rewrite arrayN_isolate_hd in H.
		simpl in H.
		apply sep_star_assoc in H.
		apply IHl' in H.
		destruct H.
		unfold ptsto_subset_b in H.
		simpl in H.
		destruct_lift H.
		apply sep_star_assoc in H.
		replace (a0 |-> (a_1, dummy) ✶ arrayN (ptsto (V:=byteset)) (a0 + 1) x)%pred
			with (a0 |-> (selN ((a_1, dummy)::x) 0 byteset0) ✶ arrayN (ptsto (V:=byteset)) (a0 + 1) (skipn 1 ((a_1, dummy)::x)))%pred in H.
		rewrite <- arrayN_isolate_hd in H.
		exists ((a_1, dummy)::x).
		split; simpl; auto.
		simpl; omega.
		reflexivity.
		simpl; omega.
		Grab Existential Variables.
		apply byteset0.
Qed.

Lemma S_length_exists: forall A (l: list A) def,
l <> nil -> l = (selN l 0 def)::(skipn 1 l).
	Proof.
		intros.
		destruct l.
		unfold not in H; destruct H; reflexivity.
		reflexivity.
	Qed.

Lemma mapsnd_sndsplit: forall A B (l:list (A * B)),
map snd l = snd (split l).
	Proof.
		intros.
		induction l.
		reflexivity.
		simpl.
		rewrite IHl.
		destruct a.
		simpl.
		destruct (split l).
		reflexivity.
	Qed.



Lemma ptsto_subset_b_list2nmem: forall l l' F a,
(F * arrayN ptsto_subset_b a l)%pred (list2nmem l') ->
map fst l = map fst (firstn (length l) (skipn a l')).
	Proof.
		induction l; intros.
		reflexivity.
		pose proof H.
		rewrite arrayN_isolate with (i:= 0) in H.
		simpl in H.
		unfold ptsto_subset_b in H.
		replace (firstn (length (a :: l)) (skipn a0 l')) 
				with ((selN (skipn a0 l') 0 byteset0)::(firstn (length l) (skipn (a0 + 1) l'))).
				
		rewrite <- plus_n_O in H.
		destruct_lift H.
		apply IHl in H as H'.
		destruct H'.
		apply sep_star_comm in H.
		apply sep_star_assoc in H.
		eapply list2nmem_sel in H.
		rewrite skipn_selN.
		rewrite <- plus_n_O.
		rewrite <- H.
		reflexivity.
		rewrite cons_app.
		rewrite <- firstn_1_selN.
		replace (skipn (a0 + 1) l') with (skipn 1 (skipn a0 l')).
		rewrite <- firstn_sum_split.
		reflexivity.
		rewrite skipn_skipn.
		rewrite Nat.add_comm;
		reflexivity.
		unfold not; intros.
		apply length_zero_iff_nil in H1.
		rewrite skipn_length in H1.
		apply ptsto_subset_b_to_ptsto in H0.
		repeat destruct H0.
		apply list2nmem_arrayN_bound in H0.
		destruct H0.
		rewrite H0 in H2; simpl in H2; inversion H2.
		rewrite <- H2 in H0.
		simpl in H0.
		omega.
		simpl; omega.
		Grab Existential Variables.
		apply byteset0.
	Qed.

Lemma merge_bs_nil_l: forall l,
merge_bs nil l = nil.
Proof. destruct l; reflexivity. Qed.

Lemma merge_bs_app: forall l1 l2 l1' l2',
	length l1 = length l1' ->
	merge_bs (l1 ++ l2) (l1'++l2') = merge_bs l1 l1' ++ merge_bs l2 l2'.
	Proof.
		induction l1;	intros.
		simpl in H; symmetry in H; apply length_zero_iff_nil in H; subst.
		reflexivity.
		destruct l1'.
		simpl in H; inversion H.
		simpl.
		rewrite IHl1.
		reflexivity.
		simpl in H; omega.
	Qed.
	
Lemma list2nmem_arrayN_ptsto2ptsto_subset_b: forall l1 l1' l a F,
length l1 = length l1' ->
(F * arrayN (ptsto (V:= byteset)) a l1)%pred (list2nmem l) ->
(forall i, i < length l1 -> fst (selN l1 i byteset0) = fst (selN l1' i byteset0) /\
						incl (byteset2list (selN l1 i byteset0)) (byteset2list (selN l1' i byteset0))) ->
(F * arrayN ptsto_subset_b a l1')%pred (list2nmem l).
	Proof.
			induction l1; intros.
			simpl in *.
			symmetry in H; apply length_zero_iff_nil in H; subst.
			simpl; auto.
			destruct l1'.
			simpl in H; inversion H.
			rewrite arrayN_isolate_hd.
			apply sep_star_assoc.
			eapply IHl1.
			simpl in *; omega.
			assert (0 < length (a::l1)).
			simpl; omega.
			apply H1 in H2.
			destruct H2; simpl in *.
			replace (a0 + 1) with (S a0) by omega.
			unfold ptsto_subset_b; pred_apply; cancel.
			
			intros.
			simpl.
			simpl in H1.
			apply lt_n_S in H2.
			apply H1 in H2.
			auto.
			simpl; omega.
			Grab Existential Variables.
			apply byteset0.
		Qed.

Lemma merge_bs_selN: forall l l' i,
i < length l ->
i < length l' ->
selN (merge_bs l l') i byteset0 = ((selN l i byte0),fst (selN l' i byteset0) :: snd (selN l' i byteset0)).
	Proof.
			induction l; intros.
			simpl in H; inversion H.
			destruct l'.
			simpl in H0; inversion H0.
			destruct i; simpl.
			reflexivity.
			apply IHl; simpl in *; omega.
	Qed.

Lemma selN_eq: forall A (l l': list A) i def,
l = l' ->
selN l i def = selN l' i def.
	Proof. intros; subst; reflexivity. Qed.

Lemma ptsto_subset_b_incl: forall l1 l1' l a F,
length l1 = length l1' ->
(F * arrayN (ptsto (V:= byteset)) a l1)%pred (list2nmem l) ->
(F * arrayN ptsto_subset_b a l1')%pred (list2nmem l) ->
(forall i, i < length l1 -> incl (byteset2list (selN l1 i byteset0)) (byteset2list (selN l1' i byteset0))).
	Proof.
		induction l1; intros.
		simpl in H2; inversion H2.
		destruct l1'.
		simpl in H; inversion H.
		destruct i; simpl.
		rewrite arrayN_isolate_hd in H1.
		unfold ptsto_subset_b in H1.
		destruct_lift H1.
		apply sep_star_comm in H1.
		apply sep_star_assoc in H1.
	 	eapply list2nmem_sel in H1.
	 	
		apply sep_star_comm in H0.
		apply sep_star_assoc in H0.
		apply sep_star_comm in H0.
	 	eapply list2nmem_sel in H0.
	 	rewrite <- H1 in H0.
	 	inversion H0.
	 	apply H7.
	 	simpl; omega.
	 	eapply IHl1.
	 	auto.

	 	simpl in *.
	 	apply sep_star_assoc in H0; eauto.
	 	simpl in *.
	 	destruct_lift H1.
	 	unfold ptsto_subset_b in H1; destruct_lift H1.
	 	
	 	apply sep_star_comm in H1 as H'.
		apply sep_star_assoc in H'.
	 	eapply list2nmem_sel in H'.
	 	
		apply sep_star_comm in H0 as H''.
		apply sep_star_assoc in H''.
		apply sep_star_comm in H''.
	 	eapply list2nmem_sel in H''.
	 	rewrite <- H' in H''.
	 	inversion H''.
	 	apply H1.
	 	simpl in H2; omega.
	 	Grab Existential Variables.
	 	all: apply byteset0.
 	Qed.

  	Lemma merge_bs_firstn_skipn: forall a b c l l',
	a + b = c ->
	merge_bs (firstn c l) (firstn c l') = merge_bs (firstn a l) (firstn a l') 
																					++ merge_bs (firstn b (skipn a l)) (firstn b (skipn a l')).
		Proof.
			induction a; intros.
			simpl.
			simpl in H.
			subst; reflexivity.
			simpl.
			destruct l.
			repeat rewrite firstn_nil.
			reflexivity.
			simpl.
			destruct l'.
			simpl.
			repeat rewrite firstn_nil.
			repeat rewrite merge_bs_nil.
			rewrite <- H.
			simpl.
			rewrite <- map_app.
			rewrite firstn_sum_split.
			reflexivity.
			
			simpl.
			rewrite <- H; simpl.
			erewrite IHa with (b:= b).
			reflexivity.
			reflexivity.
		Qed.

Lemma arrayN_app': forall V (a b: list V) st l pts,
	l = length a ->
	arrayN pts st (a++b) <=p=> arrayN pts st a ✶ arrayN pts (st + l) b.
	Proof. intros; subst;	apply arrayN_app.	Qed.
	
Definition some_strip {V} (o: option V) def: V :=
match o with
	| None => def
	| Some v => v
end.

Definition subset_invariant_bs (p: pred) : Prop :=
forall (bsl bsl': @Mem.mem addr addr_eq_dec byteset), 
	(forall a, bsl' a = bsl a \/ 
		( bsl a <> None /\ bsl' a = Some (fst (some_strip (bsl a) byteset0), fst (some_strip (bsl a) byteset0)::snd(some_strip (bsl a) byteset0)))) -> 
	p bsl -> p bsl'.

Lemma list2nmem_arrayN_ptsto_subset_b_frame_extract: forall a l l' F,
(F * arrayN ptsto_subset_b a l')%pred (list2nmem l) ->
F (mem_except_range (list2nmem l) a (length l')).
	Proof.
		intros.
		eapply ptsto_subset_b_to_ptsto in H.
		repeat destruct H.
		apply arrayN_frame_mem_ex_range in H. 
		rewrite H0; auto.
	Qed.

Lemma block_off_le_length_proto_bytefile: forall  f pfy ufy fy block_off byte_off data F,
proto_bytefile_valid f pfy ->
unified_bytefile_valid pfy ufy ->
bytefile_valid ufy fy -> 
(F * arrayN ptsto_subset_b (block_off * valubytes + byte_off) data)%pred (list2nmem (ByFData fy)) ->
byte_off < valubytes ->
length data > 0 ->
block_off <= length (PByFData pfy).

	Proof.
		intros.
		erewrite bfile_protobyte_len_eq; eauto.
		apply ptsto_subset_b_to_ptsto in H2 as Hx.
		repeat destruct Hx.
		destruct H5.
		apply Nat.lt_le_incl; eapply inlen_bfile. 
		eauto.
		eauto.
		eauto.
		3: eauto.
		omega.
		omega.
	Qed.

Lemma proto_len_firstn: forall f pfy a,
proto_bytefile_valid f pfy ->
Forall (fun sublist : list byteset => length sublist = valubytes) (firstn a (PByFData pfy)).
Proof.
intros.
apply Forall_forall; intros.
apply in_firstn_in in H0.
rewrite H in H0.
apply in_map_iff in H0.
destruct H0.
inversion H0.
rewrite <- H1.
apply valuset2bytesets_len.
Qed.

Lemma valu2list_selN_fst: forall block_off a0 f pfy ufy fy,
  proto_bytefile_valid f pfy ->
  unified_bytefile_valid pfy ufy ->
  bytefile_valid ufy fy ->
  block_off < length (BFILE.BFData f) ->
  a0 < length (ByFData fy) ->
  block_off * valubytes + valubytes > a0 ->
  a0 >= block_off * valubytes ->
  (selN (valu2list (fst (selN (BFILE.BFData f) block_off valuset0))) (a0 - block_off * valubytes) byte0) = fst (selN (ByFData fy) a0 byteset0).
Proof.
  intros.
  rewrite H1; rewrite H0; rewrite H.
  rewrite selN_firstn; auto.
  rewrite between_exists with (a:= a0)(b:= block_off + 1) (c:= valubytes).
  replace (block_off + 1 - 1) with block_off by omega.
  rewrite concat_hom_selN with (k:= valubytes).
  rewrite selN_map with (default':= valuset0).
  unfold valuset2bytesets. simpl.
  destruct  (snd (selN (BFILE.BFData f) block_off valuset0)) eqn:D.
  replace (snd (BFILE.BFData f) ⟦ block_off ⟧) with (nil: list valu).
  simpl.
  rewrite v2b_rec_nil.
  rewrite l2b_cons_x_nil.
  erewrite selN_map.
  simpl.
  replace ( block_off * valubytes + a0 mod valubytes - block_off * valubytes )
  with (a0 mod valubytes) by omega.
  reflexivity.
  rewrite valu2list_len; apply Nat.mod_upper_bound.
  apply valubytes_ne_O.
  rewrite valu2list_len. reflexivity.


  rewrite valuset2bytesets_rec_cons_merge_bs.
  rewrite merge_bs_selN; simpl.
  replace ( block_off * valubytes + a0 mod valubytes - block_off * valubytes )
  with (a0 mod valubytes) by omega.
  reflexivity.
  rewrite valu2list_len; apply Nat.mod_upper_bound.
  apply valubytes_ne_O.
  rewrite map_length.
  rewrite valuset2bytesets_rec_len.
  apply Nat.mod_upper_bound.
  apply valubytes_ne_O.
  replace (snd (BFILE.BFData f) ⟦ block_off ⟧) with (w::l).
  unfold not; intros Hx; inversion Hx.
  rewrite Forall_forall; intros l' Hx; destruct Hx.
  destruct H6.
  apply valu2list_len.
  apply in_map_iff in H6. repeat destruct H6.
  apply valu2list_len.
  auto.
  rewrite <- H; eapply proto_len; eauto.
  apply Nat.mod_upper_bound.
  apply valubytes_ne_O.
  replace (block_off + 1 - 1) with block_off. auto.
  omega.
  rewrite Nat.mul_add_distr_r; omega.
Qed.

Lemma byteset2list_selN_snd: forall block_off a0 f pfy ufy fy,
  proto_bytefile_valid f pfy ->
  unified_bytefile_valid pfy ufy ->
  bytefile_valid ufy fy ->
  block_off < length (BFILE.BFData f) ->
  a0 < length (ByFData fy) ->
  block_off * valubytes + valubytes > a0 ->
  a0 >= block_off * valubytes ->
  (snd (selN (BFILE.BFData f) block_off valuset0)) <> nil ->
fst (list2byteset byte0
        (selN (valuset2bytesets_rec (map valu2list (snd (selN (BFILE.BFData f) block_off valuset0))) valubytes) (a0 - block_off * valubytes) nil))
   :: snd (list2byteset byte0
           (selN (valuset2bytesets_rec (map valu2list (snd (selN (BFILE.BFData f) block_off valuset0))) valubytes) (a0 - block_off * valubytes) nil)) =
   snd (selN (ByFData fy) a0 byteset0).
Proof.
  intros.
  rewrite H1; rewrite H0; rewrite H.
  rewrite selN_firstn; auto.
  rewrite between_exists with (a:= a0)(b:= block_off + 1) (c:= valubytes).
  replace (block_off + 1 - 1) with block_off by omega.
  rewrite concat_hom_selN with (k:= valubytes).
  rewrite selN_map with (default':= valuset0).
  unfold valuset2bytesets. simpl.
  destruct  (snd (selN (BFILE.BFData f) block_off valuset0)) eqn:D.
  destruct H6; reflexivity.
  simpl.
  rewrite valuset2bytesets_rec_cons_merge_bs.
  rewrite merge_bs_selN; simpl.
  replace ( block_off * valubytes + a0 mod valubytes - block_off * valubytes )
  with (a0 mod valubytes) by omega.
  erewrite selN_map.
  replace (snd (BFILE.BFData f) ⟦ block_off ⟧) with (w::l).
  simpl.
  reflexivity.
  rewrite valuset2bytesets_rec_len.
  apply Nat.mod_upper_bound.
  apply valubytes_ne_O.
  replace (snd (BFILE.BFData f) ⟦ block_off ⟧) with (w::l).
  unfold not; intros Hx; inversion Hx.
  rewrite valu2list_len; apply Nat.mod_upper_bound.
  apply valubytes_ne_O.
  rewrite map_length.
  rewrite valuset2bytesets_rec_len.
  apply Nat.mod_upper_bound.
  apply valubytes_ne_O.
  replace (snd (BFILE.BFData f) ⟦ block_off ⟧) with (w::l).
  unfold not; intros Hx; inversion Hx.
  rewrite Forall_forall; intros l' Hx; destruct Hx.
  destruct H7.
  apply valu2list_len.
  apply in_map_iff in H7. repeat destruct H7.
  apply valu2list_len.
  auto.
  rewrite <- H; eapply proto_len; eauto.
  apply Nat.mod_upper_bound.
  apply valubytes_ne_O.
  replace (block_off + 1 - 1) with block_off. auto.
  omega.
  rewrite Nat.mul_add_distr_r; omega.
Qed.

Lemma bfile_bytefile_snd_nil: forall block_off a0 f pfy ufy fy,
  proto_bytefile_valid f pfy ->
  unified_bytefile_valid pfy ufy ->
  bytefile_valid ufy fy ->
  block_off < length (BFILE.BFData f) ->
  a0 < length (ByFData fy) ->
  block_off * valubytes + valubytes > a0 ->
  a0 >= block_off * valubytes ->
  snd (selN (BFILE.BFData f) block_off valuset0) = nil ->
  snd (selN (ByFData fy) a0 byteset0) = nil.
Proof.
  intros.
  rewrite H1; rewrite H0; rewrite H.
  rewrite selN_firstn; auto.
  rewrite between_exists with (a:= a0)(b:= block_off + 1) (c:= valubytes).
  replace (block_off + 1 - 1) with block_off by omega.
  rewrite concat_hom_selN with (k:= valubytes).
  erewrite selN_map with (default':= valuset0).
  (* destruct (selN (BFILE.BFData f) block_off valuset0) eqn:D. *)
  unfold valuset2bytesets.
  erewrite selN_map.
  unfold byteset2list.
  replace (snd (BFILE.BFData f) ⟦ block_off ⟧) with (nil: list valu).
  simpl.
  rewrite v2b_rec_nil.
  erewrite selN_map.
  reflexivity.
   rewrite valu2list_len; apply Nat.mod_upper_bound.
  apply valubytes_ne_O.
  rewrite valu2list_len; reflexivity.
  rewrite valuset2bytesets_rec_len.
  apply Nat.mod_upper_bound.
  apply valubytes_ne_O.
  unfold byteset2list, not; intros Hx; inversion Hx.
  auto.
  rewrite <- H; eapply proto_len; eauto.
  apply Nat.mod_upper_bound.
  apply valubytes_ne_O.
  replace (block_off + 1 - 1) with block_off. auto.
  omega.
  rewrite Nat.mul_add_distr_r; omega.
  Unshelve.
  apply nil.
  apply byte0.
Qed.

Lemma unified_bytefile_bytefile_selN_eq: forall a0 ufy fy,
  bytefile_valid ufy fy ->
  a0 < length (ByFData fy) ->
  selN (UByFData ufy) a0 byteset0 = selN (ByFData fy) a0 byteset0.
Proof.
  intros.
  rewrite H.
  rewrite selN_firstn.
  reflexivity.
  auto.
Qed.

Lemma merge_bs_skipn_comm: forall l l1 a,
skipn a (merge_bs l l1) = merge_bs (skipn a l) (skipn a l1).
Proof.
  induction l; intros.
  repeat rewrite skipn_nil.
  reflexivity.
  destruct a0.
  reflexivity.
  destruct l1.
  simpl.
  rewrite IHl.
  rewrite skipn_nil; reflexivity.
  simpl.
  auto.
Qed.


Lemma subset_invariant_bs_union: forall F1 F2,
subset_invariant_bs F1 -> subset_invariant_bs F2 ->
  subset_invariant_bs (F1 * F2)%pred.
Proof.
    intros.
    unfold subset_invariant_bs.
    intros.
    unfold sep_star in H2; rewrite sep_star_is in H2; unfold sep_star_impl in H2.
    destruct H2.
    destruct H2.
    destruct H2.
    destruct H3.
    destruct H4.
    
    unfold_sep_star.
    exists (fun a => match x a with
                     | None => None
                     | Some v => bsl' a
                     end).
    exists (fun a => match x0 a with
                     | None => None
                     | Some v => bsl' a
                     end).
    repeat split.
    apply functional_extensionality; intros.
    unfold mem_union.
    destruct (bsl x1) eqn:D.
    rewrite H2 in D. unfold mem_union in D.
    destruct (x x1) eqn:D1.
    destruct (bsl' x1).
    reflexivity.
    destruct (x0 x1); reflexivity.
    rewrite D; reflexivity.
    
    rewrite H2 in D.
    unfold mem_union in D.
    destruct (x x1) eqn:D1.
    inversion D.
    
    destruct H1 with (a:= x1).
    rewrite H2 in H6.
    unfold mem_union in H6.
    rewrite D1 in H6; simpl in H6; rewrite D in H6.
    rewrite H6; rewrite D; reflexivity.
    
    destruct H6.
    rewrite H2 in H6.
    unfold mem_union in H6.
    rewrite D1 in H6; simpl in H6; rewrite D in H6.
    destruct H6; reflexivity.
    
    unfold mem_disjoint in *.
    unfold not; intros.
    do 4 destruct H6.
    destruct H3.
    destruct (x x1) eqn:D.
    destruct (x0 x1) eqn:D1.
    exists x1.
    exists p.
    exists p0.
    split; auto.
    inversion H7.
    inversion H6.
    eapply H.
    intros.
    2: eauto.
    
    destruct H1 with (a:= a).
    left.
    unfold mem_union in *.
    rewrite H2 in H6.
    destruct (x a) eqn:D.
    auto.
    reflexivity.
    
    destruct H6.
    rewrite H2 in H7.
    unfold some_strip, mem_union in *.
    destruct (x a) eqn:D.
    right.
    split.
    unfold not; intros Hx; inversion Hx.
    auto.
    left.
    reflexivity. 
    
    eapply H0.
    intros.
    2: eauto.
    
    destruct H1 with (a:= a).
    left.
    unfold mem_union in *.
    rewrite H2 in H6.
    destruct (x0 a) eqn:D.
    unfold mem_disjoint in *.
    unfold not in *.
    destruct (x a) eqn:D1.
    destruct H3.
    exists a, p0, p.
    split; auto.
    auto.
    reflexivity.
    
    destruct H6.
    rewrite H2 in H7.
    unfold some_strip, mem_union in *.
    destruct (x0 a) eqn:D.
    right.
    split.
    unfold not; intros Hx; inversion Hx.
    destruct (x a) eqn:D1.
    destruct H3.
    exists a, p0, p.
    split; auto.
    auto.
    left; reflexivity.
Qed.

Lemma subset_invariant_bs_ptsto_subset_b: forall l a,
subset_invariant_bs (arrayN ptsto_subset_b a l).
  Proof.
    induction l; intros.
    unfold subset_invariant_bs; intros.
    simpl in *.
    unfold emp in *; intros.
    destruct H with (a:= a0).
    rewrite H0 in H1; auto.
    repeat destruct H1.
    apply H0.
    
    simpl in *.
    apply subset_invariant_bs_union.
    unfold subset_invariant_bs; intros.
    unfold ptsto_subset_b in *;
    destruct_lift H0.
    
    destruct H with (a:= a0).
    apply emp_star in H0 as H'.
    apply ptsto_valid' in H'.
    
    
    exists dummy.
    rewrite H' in H1.
    apply sep_star_lift_apply'.
    apply emp_star.
    apply sep_star_comm.
    apply mem_except_ptsto.
    auto.
    
    assert (forall AT AEQ V (m: @Mem.mem AT AEQ V), m = Mem.empty_mem -> emp m).
    intros.
    rewrite H2.
    apply emp_empty_mem.
    apply H2.
    unfold Mem.empty_mem.
    apply functional_extensionality; intros.
    unfold mem_except.
    destruct (addr_eq_dec x a0).
    reflexivity.
    
    destruct H with (a:= x).
    apply ptsto_ne with (a':= x) in H0 as Hx.
    rewrite H4; rewrite Hx; reflexivity.
    unfold not; intros.
    apply n; omega.
    
    
    destruct H4.
    apply ptsto_ne with (a':= x) in H0 as Hx.
    rewrite Hx in H4.
    destruct H4; reflexivity.
    unfold not; intros.
    apply n; omega.
    auto.
    
    (* part2 *)
    destruct H1.
    apply emp_star in H0 as H'.
    apply ptsto_valid' in H'.
    rewrite H' in H2; simpl in H2.
    
    
    exists (a_1::dummy).
    apply sep_star_lift_apply'.
    apply emp_star.
    apply sep_star_comm.
    apply mem_except_ptsto.
    auto.
    
    assert (forall AT AEQ V (m: @Mem.mem AT AEQ V), m = Mem.empty_mem -> emp m).
    intros.
    rewrite H4.
    apply emp_empty_mem.
    apply H4.
    unfold Mem.empty_mem.
    apply functional_extensionality; intros.
    unfold mem_except.
    destruct (addr_eq_dec x a0).
    reflexivity.
   
   destruct H with (a:= x).
    apply ptsto_ne with (a':= x) in H0 as Hx.
    rewrite H5; rewrite Hx; reflexivity.
    unfold not; intros; apply n; omega.
    
    
    destruct H5.
    apply ptsto_ne with (a':= x) in H0 as Hx.
    rewrite Hx in H5.
    destruct H5; reflexivity.
    unfold not; intros; apply n; omega.
    unfold incl; intros.
    apply H3.
    repeat destruct H4.
    apply in_eq.
    apply in_eq.
    apply in_cons.
    auto.
    auto.
Qed.


Lemma minus_le_0_eq: forall a b,
a >= b -> a - b = 0 -> a = b.
Proof. intros; omega. Qed.

Lemma list2nmem_arrayN_ptsto_subset_b_inlen: forall F off l fy,
length l > 0 -> 
(F ✶ arrayN ptsto_subset_b off l)%pred (list2nmem (ByFData fy)) ->
off < length (ByFData fy).
  Proof.
    intros.
    apply ptsto_subset_b_to_ptsto in H0.
    repeat destruct H0.
    apply list2nmem_arrayN_bound in H0.
    destruct H0.
    rewrite H0 in H1; simpl in H1.
    omega.
    omega.
  Qed.


Lemma bsplit_list_O_byte0: forall b l sz,
bsplit_list (natToWord (sz * 8) 0) = b::l ->
b = byte0.
Proof. Admitted.

Lemma unified_bytefile_bytefile_same: forall ufy fy,
bytefile_valid ufy fy ->
length (ByFData fy) = length (UByFData ufy) ->
ByFData fy = UByFData ufy.
Proof.
  intros.
  rewrite H.
  rewrite H0; apply firstn_exact.
Qed.

Fixpoint list_zero_pad l a :=
match a with
| O => l
| S a' => list_zero_pad (l ++ (byte0 :: nil)) a'
end.

Lemma list_zero_pad_length: forall a l,
length (list_zero_pad l a) = length l + a.
Proof.
  induction a; intros.
  simpl; apply plus_n_O.
  simpl.
  rewrite IHa.
  rewrite app_length; simpl; omega.
Qed.

Lemma list_zero_pad_selN_l: forall a l i def,
i < length l ->
selN (list_zero_pad l a) i def = selN l i def.
Proof.
  induction a; intros.
  reflexivity.
  simpl.
  rewrite IHa.
  rewrite selN_app1.
  reflexivity.
  auto.
  rewrite app_length.
  simpl; omega.
Qed.

Lemma list_zero_pad_selN_pad: forall a l i,
i >= length l ->
selN (list_zero_pad l a) i byte0 = byte0.
Proof.
  intros.
  destruct (lt_dec i (length l + a)).
  generalize dependent l.
  induction a; intros.
  simpl.
  rewrite selN_oob; auto.
  simpl.
  destruct (le_dec (S (length l)) i).
  apply IHa.
  rewrite app_length; simpl; omega.
  rewrite app_length; simpl; omega.
  apply Nat.nle_gt in n.
  rewrite list_zero_pad_selN_l.
  rewrite selN_app2.
  simpl.
  destruct (i - length l); try omega; reflexivity.
  auto.
  rewrite app_length; simpl; omega.
  apply selN_oob.
  rewrite list_zero_pad_length; omega.
Qed.

Lemma between_mod_ne_0: forall c a b,
b <> 0 ->
a > (c - 1) * b ->
a < c * b ->
a mod b <> 0.
Proof.
  induction c; intros.
  inversion H1.
  destruct (lt_dec a b).
  Search 0 Nat.modulo lt.
  apply Nat.mod_small_iff in l.
  rewrite l.
  unfold not; intros.
  rewrite H2 in H0; inversion H0.
  auto.
  apply Nat.nlt_ge in n.
  replace (S c - 1) with c in H0 by omega.
  simpl in *.
  rewrite <- modulo_eq.
  apply IHc.
  all: try omega.
  rewrite Nat.mul_sub_distr_r.
  apply Nat.lt_add_lt_sub_r.
  simpl; rewrite <- plus_n_O.
  rewrite Nat.sub_add; try omega.
  destruct c. omega.
  simpl;  apply le_plus_l.
Qed.

Lemma merge_bs_firstn_comm: forall l l' a,
firstn a (merge_bs l l') = merge_bs (firstn a l) (firstn a l').
Proof. induction l; intros.
  simpl.
  repeat rewrite firstn_nil.
  reflexivity.
  destruct l'.
  rewrite firstn_nil.
  repeat rewrite merge_bs_nil.
  apply firstn_map_comm.
  destruct a0.
  reflexivity.
  simpl.
  rewrite IHl.
  reflexivity.
Qed.

Lemma list_zero_pad_expand: forall a l,
list_zero_pad l a = l ++ list_zero_pad nil a.
Proof. 
  induction a; intros; simpl.
  rewrite app_nil_r; reflexivity.
  rewrite IHa.
  simpl.
  remember ((l ++ byte0 :: nil) ++ list_zero_pad nil a) as x.
  rewrite IHa.
  rewrite Heqx.
  rewrite <- app_comm_cons.
  apply app_assoc_reverse.
Qed.  
  
Lemma list_zero_pad_nil_iff: forall a l,
list_zero_pad l a = nil <-> l = nil /\ a = 0.
Proof.
  induction a; intros.
  split; intros.
  split; simpl in *; auto.
  destruct H.
  rewrite H; reflexivity.
  split; intros.
  simpl in H.
  apply IHa in H.
  destruct H.
  apply app_eq_nil in H.
  destruct H.
  inversion H1.
  destruct H.
  inversion H0.
Qed.

Lemma pmp_1_4_cancel: forall a b c,
a + b - a + c = b + c.
Proof. intros; omega. Qed.

Lemma lt_minus_S: forall a b,
a > b ->
exists n, a - b = S n.
Proof.
  induction a; intros.
  inversion H.
  destruct b.
  exists a.
  omega.
  simpl.
  apply IHa.
  omega.
Qed.

Lemma list2nmem_app': forall V (F: pred) a (l: list V) v,
a = length l ->
F (list2nmem l) ->
(F * a |-> v)%pred (list2nmem (l ++ (v::nil))).
Proof. intros; subst; apply list2nmem_app; auto. Qed.

Lemma mod_upper_bound_le: forall a b,
a mod b < b ->
a mod b + 1 <= b.
Proof. intros. omega. Qed.

Lemma subset_invariant_bs_apply: forall (F:pred) l a,
subset_invariant_bs F ->
F (list2nmem l) ->
F (list2nmem (firstn a l ++ merge_bs (map fst (skipn a l)) (skipn a l))).
Proof.
  intros.
  unfold subset_invariant_bs in H.
  eapply H.
  2: apply H0.
  intros.
  destruct (le_dec a (length l)).
  destruct (lt_dec a0 a).
  left.
  unfold list2nmem.
  repeat erewrite selN_map.
  apply some_eq.
  rewrite selN_app1.
  rewrite selN_firstn.
  reflexivity.
  auto.
  rewrite firstn_length_l; auto.
  omega.
  rewrite app_length.
  rewrite firstn_length_l.
  omega.
  auto.
  
  destruct (lt_dec a0 (length l)).
  right.
  split.
  unfold list2nmem, not; erewrite selN_map. intros Hx; inversion Hx.
  auto.
  unfold list2nmem.
  erewrite selN_map. 
  rewrite selN_app2.
  rewrite merge_bs_selN.
  erewrite selN_map.
  repeat rewrite skipn_selN.
  repeat rewrite firstn_length_l.
  repeat rewrite <- le_plus_minus.
  apply some_eq.
  unfold some_strip.
  repeat erewrite selN_map.
  reflexivity.
  all: try rewrite firstn_length_l.
  all: try rewrite map_length.
  all: try rewrite skipn_length.
  all: try omega.
  rewrite app_length.
  rewrite merge_bs_length.
  rewrite map_length.
  rewrite skipn_length.
  rewrite firstn_length_l.
  omega.
  auto.
  left.
  unfold list2nmem.
  repeat rewrite selN_oob.
  reflexivity.
  rewrite map_length; omega.
  rewrite map_length.
  rewrite app_length.
  rewrite merge_bs_length.
  rewrite map_length.
  rewrite skipn_length.
  rewrite firstn_length_l.
  omega.
  omega.
  rewrite skipn_oob.
  rewrite firstn_oob.
  simpl.
  rewrite app_nil_r.
  left.
  reflexivity.
  all: omega.
  Grab Existential Variables.
  all: apply byteset0.
Qed.

Lemma between_lt_upper: forall a b c,
b <> 0 ->
a > (c - 1) * b ->
a <= c * b ->
a mod b > 0 ->
a < c * b.
	Proof. Admitted.
	
Lemma unified_bytefile_bytefile_firstn: forall a ufy fy,
a <= length (ByFData fy) ->
bytefile_valid ufy fy ->
firstn a (ByFData fy) = firstn a (UByFData ufy).
	Proof.
		intros.
		rewrite H0.
		rewrite firstn_firstn.
		rewrite Nat.min_l.
		reflexivity.
		auto.
	Qed.
	
Lemma lt_mp: forall a b c,
a > b -> 
c < b ->
a - b + c < a.
Proof. intros; omega. Qed.

Lemma unified_bytefile_minus: forall f pfy ufy fy a,
		proto_bytefile_valid f pfy ->
		unified_bytefile_valid pfy ufy ->
		bytefile_valid ufy fy ->
		length (ByFData fy) > (length (BFILE.BFData f) - 1) * valubytes ->
		 a >= valubytes ->
		 length (ByFData fy) >= length (UByFData ufy) - a.
		 Proof.
		 	intros.
		 	eapply le_trans.
		 	instantiate (1:= length (UByFData ufy) - valubytes).
		 	omega.
		 	Search UByFData ByFData.
		 	rewrite H1.
		 	rewrite H0.
		 	rewrite H.
		 	rewrite concat_hom_length with (k:= valubytes).
		 	rewrite map_length.
		 	rewrite firstn_length_l.
		 	rewrite Nat.mul_sub_distr_r in H2.
		 	simpl in H2.
		 	rewrite <- plus_n_O in H2.
		 	apply Nat.lt_le_incl.
		 	auto.
	 		rewrite concat_hom_length with (k:= valubytes).
		 	rewrite map_length.
		 	eapply bfile_bytefile_length; eauto.
		 	rewrite <- H.
		 	eapply proto_len; eauto.
		 	rewrite <- H.
		 	eapply proto_len; eauto.
	 	Qed.


	Lemma n2w_id: forall a b sz,
	a = b -> natToWord sz a = natToWord sz b.
		Proof. intros; subst; reflexivity. Qed.
	
	Lemma mod_minus: forall a b,
	b <> 0 ->
	a - a mod b = (a / b) * b.
	Proof.
	 intros.
	 remember (a mod b) as x.
	 remember (a / b * b) as y.
	 rewrite Nat.div_mod with (x:= a)(y:= b); eauto.
	 rewrite Heqx; rewrite Heqy.
	 rewrite Nat.add_sub.
	 apply Nat.mul_comm.
 Qed.
	
	Lemma bfile_bytefile_length_eq: forall f pfy ufy fy a,
	proto_bytefile_valid f pfy ->
	unified_bytefile_valid pfy ufy ->
	bytefile_valid ufy fy ->
	length (ByFData fy) = a - a mod valubytes ->
	length (ByFData fy) > (length (BFILE.BFData f) - 1) * valubytes ->
	length (ByFData fy) = length (BFILE.BFData f) * valubytes.
	Proof. 
		intros.
		rewrite mod_minus in H2.
		assert (length (ByFData fy) <= length (BFILE.BFData f) * valubytes).
		eapply bfile_bytefile_length; eauto.
		rewrite H2 in *.
		apply lt_mult_weaken in H3.
		apply le_mult_weaken in H4.
		apply eq_rect_word_mult_helper.
		omega.
		apply valubytes_ge_O.
		apply valubytes_ne_O.
	Qed.
	
	Lemma mod_minus_eq: forall c a b,
	b <> 0 ->
	a >= c * b ->
	(a - c * b) mod b = a mod b.
	Proof.
		induction c; intros.
		simpl.
		rewrite <- minus_n_O.
		reflexivity.
		replace (a - S c * b) with ((a - b) - c * b).
		rewrite IHc.
		Search Nat.modulo minus.
		apply modulo_eq.
		all: auto.
		simpl in H0.
		eapply le_trans.
		2: apply H0.
		apply le_plus_l.
		apply Nat.le_add_le_sub_l.
		simpl in H0; auto.
		simpl.
		rewrite Nat.sub_add_distr.
		reflexivity.
	Qed.
	


(* Interface *)

Definition getattrs := BFILE.getattrs.
Definition setattrs := BFILE.setattrs.
Definition updattr := BFILE.updattr.
Definition datasync := BFILE.datasync.
Definition sync := BFILE.sync.
Definition sync_noop := BFILE.sync_noop.



(*Specs*)


Definition getlen lxp ixp inum fms:=
    let^ (ms, attr) <- BFILE.getattrs lxp ixp inum fms;
    Ret ^(ms, #(INODE.ABytes attr)).



Theorem getlen_ok : forall lxp bxp ixp inum fms,
{< F Fm Fi m0 m flist ilist frees f fy,
PRE:hm
       LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL fms) hm *
       [[[ m ::: (Fm * BFILE.rep bxp ixp flist ilist frees) ]]] *
       [[[ flist ::: (Fi * inum |-> f) ]]] *
       rep f fy
POST:hm' RET:^(fms',r)
       LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL fms') hm' *
       [[ r = length (ByFData fy)]] *
       [[ BFILE.MSAlloc fms = BFILE.MSAlloc fms' ]]
CRASH:hm'  exists fms',
       LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL fms') hm'
>} getlen lxp ixp inum fms.
Proof. Admitted. (* CORRECT: Cheked on Sept 13 *)
(* unfold getlen, rep.
hoare.
Qed.
 *)
Hint Extern 1 ({{_}} Bind (getlen _ _ _ _) _) => apply getlen_ok : prog.

(* -------------------------------------------------------------------------------- *)



(* ------------------------------------------------------------------------------------- *)

(* ------------------------------------------------------------------------------------ *)

Definition shrink_in_block lxp bxp ixp inum fms n :=
  If (lt_dec 0 n)
  {
		let^ (ms1, bylen) <- getlen lxp ixp inum fms;
		If (lt_dec n (bylen mod valubytes))
		{
			ms2 <- BFILE.updattr lxp ixp inum (INODE.UBytes $(bylen - n)) ms1;
			Ret (ms2)
		}
		else
		{
			ms2 <- BFILE.shrink lxp bxp ixp inum 1 ms1;
			ms3 <- BFILE.updattr lxp ixp inum (INODE.UBytes $(bylen - n)) ms2;
			Ret (ms3)
		}
	}
	else
	{
		Ret(fms)
	}.
  
Theorem shrink_in_block_ok : forall lxp bxp ixp inum ms n,
  {< F Fm Fi m0 m flist ilist frees f fy,
  PRE:hm
         LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL ms) hm *
         [[[ m ::: (Fm * BFILE.rep bxp ixp flist ilist frees) ]]] *
         [[[ flist ::: (Fi * inum |-> f) ]]] *
         rep f fy *
         [[ length (ByFData fy) mod valubytes >= n ]]
  POST:hm' RET:ms'  exists m' flist' f' fy' ilist' frees',
         LOG.rep lxp F (LOG.ActiveTxn m0 m') (BFILE.MSLL ms') hm' *
         [[[ m' ::: (Fm * BFILE.rep bxp ixp flist' ilist' frees') ]]] *
         [[[ flist' ::: (Fi * inum |-> f') ]]] *
         rep f' fy' *
         [[ BFILE.MSAlloc ms = BFILE.MSAlloc ms' ]] * 
         [[ length (ByFData fy') = length (ByFData fy) - n ]]
  CRASH:hm'  LOG.intact lxp F m0 hm'
  >} shrink_in_block lxp bxp ixp inum ms n.
  
Proof. Admitted. (* CORRECT: Oct 4 *)
(*   unfold shrink_in_block, rep.
  step. 
  prestep.
  norm.
  unfold stars, rep; cancel; eauto.
  intuition; eauto.
  
  step.
  step.
  safestep.

  eauto.
  eauto.
  instantiate (1:= mk_bytefile (firstn (length (ByFData fy) - n) (ByFData fy)) 
  			($ (length (ByFData fy) - n), snd (ByFAttr fy))).
	
	unfold bytefile_valid; simpl.
	rewrite firstn_length_l.
	rewrite H16.
	rewrite firstn_firstn.
	rewrite Nat.min_l.
	reflexivity.
	rewrite firstn_length_l.
	omega.
	apply bytefile_unified_byte_len; eauto.
	omega.
	rewrite H15; reflexivity.
	simpl.
	rewrite firstn_length_l.
	apply n2w_w2n_eq.
	omega.
	simpl.
	rewrite firstn_length_l.
	simpl in H26.
	rewrite firstn_length_l in H26.
	assert (length (ByFData fy) > 0).
	omega.
	apply H13 in H8.
	all: try omega.
	2: simpl; rewrite firstn_length_l; omega.
	3: cancel; apply LOG.active_intact.
	
	assert (length (ByFData fy) <= length (BFILE.BFData f) * valubytes).
	eapply bfile_bytefile_length; eauto.
	apply Nat.lt_le_incl in H8 as H'.
	apply between_exists in H'; auto.
	rewrite H'.
	omega.
	
	apply between_lt_upper; auto.
	apply valubytes_ne_O.
	omega.

	step.
	step.
	safestep.

	instantiate (1:= mk_proto_bytefile (firstn (length (PByFData pfy) - 1) (PByFData pfy))).
	unfold proto_bytefile_valid; simpl.
	rewrite H11.
	rewrite map_length.
	apply firstn_map_comm.
	
	instantiate (1:= mk_unified_bytefile (firstn (length (UByFData ufy) - valubytes) (UByFData ufy))).
	unfold unified_bytefile_valid; simpl.
	rewrite H17.
	rewrite concat_hom_length with (k:= valubytes).
	replace (length (PByFData pfy) * valubytes - valubytes)
		with ((length (PByFData pfy) - 1)* valubytes).
	apply concat_hom_firstn.
	eapply proto_len; eauto.
	rewrite Nat.mul_sub_distr_r; simpl; rewrite <- plus_n_O; reflexivity.
	eapply proto_len; eauto.

	instantiate (1:= mk_bytefile (firstn (length (ByFData fy) - length (ByFData fy) mod valubytes) (ByFData fy)) 
			($ (length (ByFData fy) - length (ByFData fy) mod valubytes), snd (ByFAttr fy))).
	unfold bytefile_valid; simpl.
	rewrite firstn_length_l.
	rewrite firstn_firstn.
	rewrite Nat.min_l.
	
	
	apply unified_bytefile_bytefile_firstn; eauto.
	omega.
	replace (length (ByFData fy) - length (ByFData fy) mod valubytes)
		with (length (ByFData fy) / valubytes * valubytes).
	apply Nat.le_add_le_sub_r.
	replace (length (ByFData fy) / valubytes * valubytes + valubytes)
		with ((S (length (ByFData fy) / valubytes)) * valubytes).
	eapply unibyte_len; eauto.
	apply Rounding.div_mul_lt.
	apply valubytes_ne_O.
	omega.
	simpl.
	omega.
	Search le minus plus.
	replace (length (ByFData fy) - length (ByFData fy) mod valubytes)
		with ((valubytes * (length (ByFData fy) / valubytes) + length (ByFData fy) mod valubytes) - length (ByFData fy) mod valubytes).
	rewrite Nat.add_sub.
	apply Nat.mul_comm.
	rewrite <- Nat.div_mod.
	reflexivity.
	apply valubytes_ne_O.
	omega.
	simpl.
	assert (Hx: length (ByFData fy) mod valubytes = n).
	omega.
	rewrite Hx;
	rewrite H15; reflexivity.
	simpl.
	rewrite firstn_length_l.
	apply n2w_w2n_eq.
	omega.
	simpl.
	
	rewrite firstn_length_l.
	2: omega.
	rewrite firstn_length_l.
	2: omega.
	rewrite Nat.mul_sub_distr_r.
	apply Nat.lt_add_lt_sub_r.
	simpl in H31.
	rewrite firstn_length_l in H31.
	assert (length (ByFData fy) > 0).
	omega.
	apply H13 in H12.
	destruct (le_dec ((length (BFILE.BFData f) - 1) * valubytes) (1*valubytes)).
	Search minus le 0.
	replace ((length (BFILE.BFData f) - 1) * valubytes - 1 * valubytes) with 0.
	simpl.
	omega.
	symmetry; apply Nat.sub_0_le; auto.
	eapply lt_trans.
	2: eauto.

	apply lt_mp.
	omega.
	simpl.
	rewrite <- plus_n_O.
	apply Nat.mod_upper_bound.
	apply valubytes_ne_O.
	omega.
	
	simpl.
	assert (Hx: length (ByFData fy) mod valubytes = n).
	omega.
	rewrite Hx;
	apply firstn_length_l; omega.

	step.
Qed. *)

Hint Extern 1 ({{_}} Bind (shrink_in_block _ _ _ _ _ _) _) => apply shrink_in_block_ok : prog.

Definition shrink_from_end lxp ixp inum fms n :=
  If (lt_dec 0 n)
  {
		let^ (ms1, bylen) <- getlen lxp ixp inum fms;
		ms2 <- BFILE.updattr lxp ixp inum (INODE.UBytes $(bylen - n)) ms1;
		Ret (ms2)
	}
	else
	{
		Ret(fms)
	}.
	
		Lemma lt_minus_r: forall a b c,
	b > c -> a > c -> a - c > a -b.
	Proof. intros; omega. Qed.
	
	
Theorem shrink_from_end_ok : forall lxp bxp ixp inum ms n,
  {< F Fm Fi m0 m flist ilist frees f fy,
  PRE:hm
         LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL ms) hm *
         [[[ m ::: (Fm * BFILE.rep bxp ixp flist ilist frees) ]]] *
         [[[ flist ::: (Fi * inum |-> f) ]]] *
         rep f fy *
         [[ length (ByFData fy) mod valubytes = 0 ]] *
         [[ length (ByFData fy) > 0 ]] *
         [[ n < valubytes ]]
  POST:hm' RET:ms'  exists m' flist' f' fy' ilist' frees',
         LOG.rep lxp F (LOG.ActiveTxn m0 m') (BFILE.MSLL ms') hm' *
         [[[ m' ::: (Fm * BFILE.rep bxp ixp flist' ilist' frees') ]]] *
         [[[ flist' ::: (Fi * inum |-> f') ]]] *
         rep f' fy' *
         [[ BFILE.MSAlloc ms = BFILE.MSAlloc ms' ]] * 
         [[ length (ByFData fy') = length (ByFData fy) - n ]]
  CRASH:hm'  LOG.intact lxp F m0 hm'
  >} shrink_from_end lxp ixp inum ms n.
Proof. Admitted. (* CORRECT: Oct 4 *)
(* 	unfold shrink_from_end, rep; step.
	prestep; norm.
	unfold stars, rep; cancel; eauto.
	intuition; eauto.
	step.
	safestep.
	eauto.
	eauto.
	instantiate (1:= mk_bytefile (firstn (length (ByFData fy) - n) (ByFData fy)) ($ (length (ByFData fy) - n), snd (ByFAttr fy))).
	unfold bytefile_valid; simpl.
	rewrite firstn_length_l.
	eapply unified_bytefile_bytefile_firstn; eauto.
	omega.
	omega.
	simpl.
	rewrite H17; reflexivity.
	simpl.
	rewrite firstn_length_l.
	apply n2w_w2n_eq.
	omega.
	simpl.
	rewrite firstn_length_l.
	assert (length (ByFData fy) = length (ByFData fy) - length (ByFData fy) mod valubytes).
	omega.
	erewrite bfile_bytefile_length_eq; eauto.
	rewrite Nat.mul_sub_distr_r.
	simpl; rewrite <- plus_n_O.
	apply lt_minus_r.
	auto.
	erewrite <- bfile_bytefile_length_eq; eauto.
	simpl in H27.
	rewrite firstn_length_l in H27.
	omega.
	omega.
	omega.
	simpl.
	apply firstn_length_l.
	omega.
	cancel.
	apply LOG.active_intact.
	step.
Qed.  *)

Hint Extern 1 ({{_}} Bind (shrink_from_end _ _ _ _ _) _) => apply shrink_from_end_ok : prog.

Definition shrink lxp bxp ixp inum fms n :=
 If (lt_dec 0 n)
 {
		let^ (ms1, bylen) <- getlen lxp ixp inum fms;
		If(lt_dec n bylen)
		{
			let last_por := bylen mod valubytes in
			If (le_dec n last_por)(* last byte removed from block *)
			{
				  ms2 <- shrink_in_block lxp bxp ixp inum ms1 n;
				  Ret (ms2)
			}
			else
			{
					ms2 <- shrink_in_block lxp bxp ixp inum ms1 last_por;
					let rem_n := n - last_por in
					let num_of_middle_blocks := rem_n / valubytes in
					If (lt_dec 0 num_of_middle_blocks)
					{
						let last_n := rem_n mod valubytes in
				  	ms3 <- BFILE.shrink lxp bxp ixp inum num_of_middle_blocks ms2;
				  	ms4 <- BFILE.updattr lxp ixp inum (INODE.UBytes $(bylen - last_por - num_of_middle_blocks * valubytes)) ms3;
				  	If (lt_dec 0 last_n)
				  	{
				  		ms5 <- shrink_from_end lxp ixp inum ms4 last_n;
				  		Ret (ms5)
				  	}
				  	else
				  	{
				  		Ret (ms4)
				  	}
					}
					else
					{
						ms3 <- shrink_from_end lxp ixp inum ms2 rem_n;
			  		Ret (ms3)
					}
			}
		}
		else
		{
			ms2 <- BFILE.reset lxp bxp ixp inum ms1;
			Ret (ms2)
		}
 }
 else
 {
 		Ret (fms)
 }.
  

  
Theorem shrink_ok : forall lxp bxp ixp inum ms n,
  {< F Fm Fi m0 m flist ilist frees f fy,
  PRE:hm
         LOG.rep lxp F (LOG.ActiveTxn m0 m) (BFILE.MSLL ms) hm *
         [[[ m ::: (Fm * BFILE.rep bxp ixp flist ilist frees) ]]] *
         [[[ flist ::: (Fi * inum |-> f) ]]] *
         rep f fy
  POST:hm' RET:ms'  exists m' flist' f' fy' ilist' frees',
         LOG.rep lxp F (LOG.ActiveTxn m0 m') (BFILE.MSLL ms') hm' *
         [[[ m' ::: (Fm * BFILE.rep bxp ixp flist' ilist' frees') ]]] *
         [[[ flist' ::: (Fi * inum |-> f') ]]] *
         rep f' fy' *
         [[ BFILE.MSAlloc ms = BFILE.MSAlloc ms' ]] * 
         [[ length (ByFData fy') = length (ByFData fy) - n ]]
  CRASH:hm'  LOG.intact lxp F m0 hm'
  >} shrink lxp bxp ixp inum ms n.
Proof.
  unfold shrink, rep.
  step. (* If (lt_dec 0 n) *)
  prestep.
  norm.
  unfold stars, rep; cancel; eauto.
  intuition; eauto.
  step. (* If(lt_dec n bylen) *)
  step.
  prestep.
  norm.
  unfold stars, rep; cancel; eauto.
  intuition; eauto.
  
  unfold rep; step.
  cancel.
  
  prestep.
  norm.
  unfold stars, rep; cancel; eauto.
  intuition; eauto.
 
  step.
  unfold rep; step.
  step.
  step.
  
  prestep.
  norm.
  unfold stars; cancel.
  unfold rep.

  2: repeat split.
  2: eauto.
  2: eauto.
  cancel.
  
  unfold proto_bytefile_valid; simpl.
  instantiate (1:= mk_proto_bytefile (firstn (length (BFILE.BFData f') -
                     (n - length (ByFData fy) mod valubytes) / valubytes) (PByFData pfy0))).
 	simpl.
 	rewrite H7.
 	apply firstn_map_comm.
 	
 	instantiate (1:= mk_unified_bytefile (firstn ((length (BFILE.BFData f') -
                     (n - length (ByFData fy) mod valubytes) / valubytes) * valubytes) (UByFData ufy0))).
  unfold unified_bytefile_valid; simpl.
  rewrite H32.
  apply concat_hom_firstn with (k:= valubytes).
	eapply proto_len; eauto.
	
	instantiate (1:= mk_bytefile (firstn
                ((length (BFILE.BFData f') -
                  (n -
                   length (ByFData fy) mod valubytes) /
                  valubytes) * valubytes) (ByFData fy')) ($
 ((length (BFILE.BFData f') -
                  (n -
                   length (ByFData fy) mod valubytes) /
                  valubytes) * valubytes), snd (BFILE.BFAttr f'))).
	unfold bytefile_valid; simpl.
	
	rewrite firstn_length_l.
	rewrite firstn_firstn.
	rewrite Nat.min_id.
	apply unified_bytefile_bytefile_firstn.
	
	rewrite Nat.mul_sub_distr_r.
	erewrite <- bfile_bytefile_length_eq; eauto.
	apply Nat.le_sub_l.
	apply H28. omega.
	
	auto.
	
	rewrite Nat.mul_sub_distr_r.
	erewrite <- bfile_bytefile_length_eq; eauto.
	apply Nat.le_sub_l.
	apply H28. omega.
	
	
	simpl; apply injective_projections; simpl.
	apply n2w_id.
	rewrite <- H21.
	rewrite Nat.mul_sub_distr_r.


	
	erewrite <- bfile_bytefile_length_eq; eauto.
	apply H28. omega.
	reflexivity.
	simpl.
	rewrite firstn_length_l.
	apply n2w_w2n_eq.
	rewrite Nat.mul_sub_distr_r.
	erewrite <- bfile_bytefile_length_eq; eauto.
	apply Nat.le_sub_l.
	apply H28. omega.
	
	simpl.
	repeat rewrite firstn_length_l.
	repeat rewrite Nat.mul_sub_distr_r.
	apply Nat.sub_lt.
	simpl; rewrite <- plus_n_O.
	simpl in H26.
	rewrite firstn_length_l in H26.
	rewrite <- Nat.mul_sub_distr_r.
	remember ((length (BFILE.BFData f') - (n - length (ByFData fy) mod valubytes) / valubytes) *
valubytes) as x.
	replace valubytes with (1*valubytes) by omega.
	rewrite Heqx in *; apply mult_le_compat_r.
	apply Nat.lt_0_mul' in H26.
	destruct H26.
	omega.

	rewrite Nat.mul_sub_distr_r.
	erewrite <- bfile_bytefile_length_eq; eauto.
	apply Nat.le_sub_l.
	apply H28. omega.
	rewrite valubytes_is; omega.
	apply Nat.le_sub_l.
	rewrite Nat.mul_sub_distr_r.
	erewrite <- bfile_bytefile_length_eq; eauto.
	apply Nat.le_sub_l.
	apply H28. omega.
	
	simpl.
	rewrite firstn_length_l.
	Search Nat.modulo minus.
	rewrite Nat.mul_sub_distr_r.
	erewrite <- bfile_bytefile_length_eq; eauto.
	
	rewrite mod_minus_eq.
	rewrite H21.
	
	Lemma mod_minus_mod: forall a b,
	b <> 0 ->
	(a - a mod b) mod b = 0.
	Proof.
		intros.
		rewrite mod_minus.
		apply Nat.mod_mul.
		all: auto.
	Qed.
	
	apply mod_minus_mod.
	apply valubytes_ne_O.
	apply valubytes_ne_O.
	
	rewrite H21.
	rewrite mod_minus.
	apply mult_le_compat_r.
	Search Nat.div lt le.
	Lemma div_lt_le: forall a b c,
	b <> 0 ->
	a >= c ->
	a / b >= c / b.
	Proof. 
	
	apply Nat.div_le_compat_l.
	omega.
	Search Nat.modulo 0 minus.
		
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	














Qed.

(* ------------------------------------------------------------------------------------- *)




End ABYTEFILE.
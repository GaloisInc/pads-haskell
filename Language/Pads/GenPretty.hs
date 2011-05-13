{-# LANGUAGE TypeSynonymInstances, TemplateHaskell, QuasiQuotes, MultiParamTypeClasses, FlexibleInstances, DeriveDataTypeable, NamedFieldPuns, ScopedTypeVariables #-}
{-
** *********************************************************************
*                                                                      *
*              This software is part of the pads package               *
*           Copyright (c) 2005-2011 AT&T Knowledge Ventures            *
*                      and is licensed under the                       *
*                        Common Public License                         *
*                      by AT&T Knowledge Ventures                      *
*                                                                      *
*                A copy of the License is available at                 *
*                    www.padsproj.org/License.html                     *
*                                                                      *
*  This program contains certain software code or other information    *
*  ("AT&T Software") proprietary to AT&T Corp. ("AT&T").  The AT&T     *
*  Software is provided to you "AS IS". YOU ASSUME TOTAL RESPONSIBILITY*
*  AND RISK FOR USE OF THE AT&T SOFTWARE. AT&T DOES NOT MAKE, AND      *
*  EXPRESSLY DISCLAIMS, ANY EXPRESS OR IMPLIED WARRANTIES OF ANY KIND  *
*  WHATSOEVER, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF*
*  MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE, WARRANTIES OF  *
*  TITLE OR NON-INFRINGEMENT.  (c) AT&T Corp.  All rights              *
*  reserved.  AT&T is a registered trademark of AT&T Corp.             *
*                                                                      *
*                   Network Services Research Center                   *
*                          AT&T Labs Research                          *
*                           Florham Park NJ                            *
*                                                                      *
*              Kathleen Fisher <kfisher@research.att.com>              *
*                                                                      *
************************************************************************
-}

module Language.Pads.GenPretty where
import Language.Pads.Padsc 
import Language.Pads.Errors
import Language.Pads.MetaData
import Language.Pads.TH

import Language.Haskell.TH as TH hiding (ppr)

import Text.PrettyPrint.Mainland

import qualified Data.List as L
import qualified Data.Set as S
import Control.Monad

import System.Posix.Types
import Data.Word
import Data.Int
import Data.Time


pprE argE = AppE (VarE 'ppr) argE
pprListEs argEs = ListE (map pprE argEs) 
pprCon1E argE = AppE (VarE 'pprCon1) argE
pprCon2E argE = AppE (VarE 'pprCon2) argE

pprCon1 arg = ppr (toList1 arg)
pprCon2 arg = ppr (toList2 arg)



getTyNames :: TH.Type ->  S.Set TH.Name
getTyNames ty  = case ty of
    ForallT tvb cxt ty' -> getTyNames ty'
    VarT name -> S.empty
    ConT name -> S.singleton name
    TupleT i -> S.empty
    ArrowT -> S.empty
    ListT -> S.empty
    AppT t1 t2 -> (getTyNames t1) `S.union` (getTyNames t2)
    SigT ty kind -> getTyNames ty

getTyNamesFromCon :: TH.Con -> S.Set TH.Name
getTyNamesFromCon con = case con of
  (NormalC name stys) -> S.unions (map (\(_,ty)   -> getTyNames ty) stys)
  (RecC name vstys)   -> S.unions (map (\(_,_,ty) -> getTyNames ty) vstys)
  (InfixC st1 name st2) -> (getTyNames(snd st1)) `S.union` (getTyNames(snd st2))
  (ForallC tvb cxt con) -> getTyNamesFromCon con



getNamedTys :: TH.Name -> Q [TH.Name]
getNamedTys ty_name = do 
   result <- getNamedTys' S.empty (S.singleton ty_name)
   return (S.toList result)


getNamedTys' :: S.Set TH.Name -> S.Set TH.Name -> Q (S.Set TH.Name)
getNamedTys' answers worklist = 
 if S.null worklist then return answers
 else do
   { let (ty_name, worklist') = S.deleteFindMin worklist
   ; let answers' = S.insert ty_name answers
   ; info <- reify ty_name
   ; case info of
        TyConI (NewtypeD [] ty_name' [] con derives) -> do
           { let all_nested = getTyNamesFromCon con
           ; let new_nested = all_nested `S.difference` answers'
           ; let new_worklist = worklist' `S.union` new_nested
           ; getNamedTys' answers' new_worklist
           }
        TyConI (DataD [] ty_name' [] cons derives) -> do  
           { let all_nested = S.unions (map getTyNamesFromCon cons)
           ; let new_nested = all_nested `S.difference` answers'
           ; let new_worklist = worklist' `S.union` new_nested
           ; getNamedTys' answers' new_worklist
           }
        TyConI (TySynD _ _ _ ) -> do {report True ("getTyNames: unimplemented TySynD case " ++ (nameBase ty_name)); return answers'} 
        TyConI (ForeignD _) -> do {report True ("getTyNames: unimplemented ForeignD case " ++ (nameBase ty_name)); return answers'} 
        PrimTyConI _ _ _ -> return answers
        otherwise -> do {report True ("getTyNames: pattern didn't match for " ++ (nameBase ty_name)); return answers'} 
   }

baseTypeNames = S.fromList [ ''Pint, ''Pchar, ''Pdigit, ''Ptext, ''Pstring, ''PstringFW, ''PstringME 
                           , ''PstringSE, ''String, ''Char, ''COff, ''EpochTime, ''FileMode, ''Int, ''Word, ''Int64
                           , ''Language.Pads.Errors.ErrInfo, ''Bool, ''Pbinary, ''Pre, ''Base_md, ''UTCTime, ''TimeZone
                           ]

mkPrettyInstance :: TH.Name -> Q [TH.Dec]
mkPrettyInstance ty_name = mkPrettyInstance' (S.singleton ty_name) baseTypeNames []

mkPrettyInstance' :: S.Set TH.Name -> S.Set TH.Name -> [TH.Dec] -> Q [TH.Dec]
mkPrettyInstance' worklist done decls = 
  if S.null worklist then return decls
  else do 
      let (ty_name, worklist') = S.deleteFindMin worklist
      if ty_name `S.member` done then mkPrettyInstance' worklist' done decls
         else do 
         let tyBaseName = nameBase ty_name
         let baseStr = strToLower tyBaseName
         let specificPprName = mkName (baseStr ++ "_ppr")
         let funName = mkName (strToLower (tyBaseName ++ "_ppr"))
         let inst = AppT (ConT ''Pretty) (ConT ty_name)   
         let genericPprName = mkName "ppr"
         let ppr_method = ValD (VarP genericPprName) (NormalB (VarE specificPprName)) []
         let instD = InstanceD [] inst [ppr_method]
         let newDone = S.insert ty_name done
         info <- reify ty_name
         (nestedTyNames, decls') <- case info of 
                   TyConI (NewtypeD [] ty_name' [] (NormalC ty_name'' [(NotStrict, AppT ListT ty)]) derives) -> do -- List
                     { let nestedTyNames = getTyNames ty
--                     ; report True ("list case " ++ (nameBase ty_name))
                     ; (itemsE,itemsP) <- doGenPE "list"
                     ; let mapE  = AppE (AppE (VarE 'map) (VarE 'ppr)) itemsE
                     ; let bodyE = AppE (AppE (VarE 'namedlist_ppr) (nameToStrLit ty_name)) mapE
                     ; let argP = ConP (mkName tyBaseName) [itemsP]
                     ; let clause = Clause [argP] (NormalB bodyE) []
                     ; return (nestedTyNames, [instD, FunD specificPprName [clause]])
                     }
                   TyConI (NewtypeD [] ty_name' [] (NormalC ty_name'' [(NotStrict, AppT (AppT (ConT ty_con_name) ty_arg1) ty_arg2) ]) derives) -> do  -- curry rep (Map)
                     { let nestedTyNames = getTyNames ty_arg2
                     ; (argP, body) <- mkPatBody tyBaseName pprCon2E
--                     ; report True ("curry rep case " ++ (nameBase ty_name))
                     ; let clause = Clause [argP] body []
                     ; return (nestedTyNames, [instD, FunD specificPprName [clause]]) 
                     }
                   TyConI (NewtypeD [] ty_name' [] (NormalC ty_name'' [(NotStrict, AppT (ConT ty_con_name) ty_arg) ]) derives) -> do  -- con rep (Set)
                     { let nestedTyNames = getTyNames ty_arg
                     ; (argP, body) <- mkPatBody tyBaseName pprCon1E
--                     ; report True ("con rep case " ++ (nameBase ty_name))
                     ; let clause = Clause [argP] body []
                     ; return (nestedTyNames, [instD, FunD specificPprName [clause]]) 
                     }
                   TyConI (NewtypeD [] ty_name' [] (NormalC ty_name'' [(NotStrict, ConT core_name)]) derives) -> do  -- App, Typedef
                     { (argP, body) <- mkPatBody tyBaseName pprE
--                     ; report True ("app, typedef case " ++ (nameBase ty_name))
                     ; let clause = Clause [argP] body []
                     ; return (S.singleton core_name, [instD, FunD specificPprName [clause]]) 
                     }
                   TyConI (NewtypeD [] ty_name' [] (NormalC ty_name'' [(NotStrict, ty)]) derives) | isTuple ty -> do    -- Tuple
                     { let nestedTyNames = getTyNames ty
--                     ; report True ("tuple case " ++ (nameBase ty_name))
                     ; let (len, tys) = tupleTyToListofTys ty
                     ; (exps, pats) <- doGenPEs len "tuple"
                     ; let bodyE = AppE (AppE (VarE 'namedtuple_ppr) (LitE (StringL tyBaseName)))  (pprListEs exps)
                     ; let argP = ConP (mkName tyBaseName) [TupP pats]
                     ; let clause = Clause [argP] (NormalB bodyE) []
                     ; return (nestedTyNames, [instD, FunD specificPprName [clause]])
                     }
                   TyConI (DataD [] ty_name' [] cons  derives) | isDataType cons -> do
                     { let nestedTyNames = S.unions (map getTyNamesFromCon cons)
                     ; (exp, pat) <- doGenPE "case_arg"
                     ; matches <- mapM mkClause cons
                     ; let caseE = CaseE exp matches
                     ; let clause = Clause [pat] (NormalB caseE) []
                     ; return (nestedTyNames, [instD, FunD specificPprName [clause]] )
                     } 
                   TyConI (DataD [] ty_name' [] cons  derives) | isRecordType cons -> do
                     { let nestedTyNames = S.unions (map getTyNamesFromCon cons)
--                   ; report (length cons /= 1) ("GenPretty: record " ++ (nameBase ty_name')  ++ " did not have a single constructor.")
                     ; clause <- mkRecord (L.head cons)
                     ; return (nestedTyNames, [instD, FunD specificPprName [clause]])
                     } 
                   TyConI (DataD _ ty_name' _ cons  derives) -> do
                    {
--                      report True ("DataD pattern didn't match for"++(nameBase ty_name)) 
                    ; return (S.empty, [])} 
                   TyConI (TySynD ty_name' [] ty) -> do 
                     { let nestedTyNames = getTyNames ty
--                     ; report True ("tysyn for"++(nameBase ty_name)) 
                     ; return (nestedTyNames, [])} 
                   TyConI (TySynD ty_name' tyVarBndrs ty) -> do 
                     { let nestedTyNames = getTyNames ty
--                     ; report True ("tysyn for"++(nameBase ty_name)) 
                     ; return (nestedTyNames, [])} 
                   TyConI dec -> do {report True ("otherwise; tyconI case "++(nameBase ty_name)) ; return (S.empty, [])} 
                   otherwise -> do {report True ("pattern didn't match for "++(nameBase ty_name)) ; return (S.empty, [])} 
         let newWorklist = worklist `S.union` nestedTyNames
         let newDecls = decls'++decls
         mkPrettyInstance' newWorklist newDone newDecls

isTuple ty = case ty of
  TupleT n -> True
  (AppT ty arg_ty) -> isTuple ty

isDataType cons = case cons of
  [] -> False
  (NormalC _ _ ) : rest -> True
  otherwise -> False

isRecordType cons = case cons of
  [] -> False
  (RecC _ _ ) : rest -> True
  otherwise -> False

mkPatBody core_name_str pprE = do
  { (exp,pat) <- doGenPE "arg"
  ; let bodyE = AppE (AppE (VarE 'namedty_ppr) (LitE (StringL core_name_str)))  (pprE exp)
  ; let argP = ConP (mkName core_name_str) [pat]
  ; return (argP, (NormalB bodyE))
  }

mkPatBodyNoArg core_name_str = do
  { let bodyE = AppE (VarE 'text) (LitE (StringL core_name_str))  
  ; let argP = ConP (mkName core_name_str) []
  ; return (argP, (NormalB bodyE))
  }

mkClause con = case con of
     NormalC name [] -> do
        { (argP, body) <- mkPatBodyNoArg (nameBase name)
        ; return (Match argP body [])
        }
     NormalC name ty_args -> do
        { (argP, body) <- mkPatBody (nameBase name) pprE
        ; return (Match argP body [])
        }
     otherwise -> error "mkClause not implemented for this kind of constructor."

mkRecord (RecC rec_name fields) = do 
  { fieldInfo <- mapM mkField fields
  ; let (recPs, recEs) = unzip fieldInfo
  ; let recP = RecP rec_name recPs
  ; let bodyE = AppE (AppE (VarE 'record_ppr) (nameToStrLit rec_name)) (ListE recEs)
  ; return (Clause [recP] (NormalB bodyE) [])
  }

mkField (field_name, _, ty) = do 
  { (expE, pat) <- doGenPE (nameBase field_name)
  ; let fieldE = AppE (AppE (VarE 'field_ppr) (nameToStrLit field_name)) (pprE expE)
  ; return ((field_name, pat), fieldE)
  }

nameToStrLit name = LitE (StringL (nameBase name))


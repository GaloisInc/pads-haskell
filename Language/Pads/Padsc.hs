{-
** *********************************************************************
*                                                                      *
*         (c)  Kathleen Fisher <kathleen.fisher@gmail.com>             *
*              John Launchbury <john.launchbury@gmail.com>             *
*                                                                      *
************************************************************************
-}

module Language.Pads.Padsc (
     {- FIX: Languages.Pads.Source exports "take", which clashes with 
        the function of the same name in Prelude -} 
     module Language.Pads.Source,
     module Language.Pads.RegExp,
     module Language.Pads.Errors,
     module Language.Pads.PadsParser,
     module Language.Pads.MetaData,
     module Language.Pads.Generic,
     module Language.Pads.CoreBaseTypes,
     module Language.Pads.Quote,
     module Language.Pads.BaseTypes,
     module Language.Pads.Pretty,
     module Language.Pads.LazyList,
     module Data.Data,
     ppr, pretty
  ) 
  where

import Language.Pads.Source 
import Language.Pads.RegExp
import Language.Pads.Errors  hiding (msg)
import Language.Pads.PadsParser
import Language.Pads.MetaData
import Language.Pads.Generic
import Language.Pads.CoreBaseTypes
import Language.Pads.Quote
import Language.Pads.BaseTypes
import Language.Pads.Pretty
import Language.Pads.LazyList

import Data.Data
import Text.PrettyPrint.Mainland hiding (line,  dot)

numErrors = Language.Pads.MetaData.numErrors




  






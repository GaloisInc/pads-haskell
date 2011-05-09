{-# LANGUAGE MultiParamTypeClasses, FunctionalDependencies, ScopedTypeVariables, FlexibleContexts, Rank2Types, FlexibleInstances #-}

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

module Language.Pads.Generic 

where

import Language.Pads.MetaData
import Language.Pads.PadsParser
import qualified Language.Pads.Errors as E
import qualified Language.Pads.Source as S
import Language.Pads.LazyList
import qualified Data.ByteString.Lazy.Char8 as B
import qualified Control.Exception as CE
import Data.Data
import Data.Generics.Aliases (extB, ext1B)
import Data.Map
import Data.Set

import System.Posix.Types
import Foreign.C.Types
import System.CPUTime


class (Data rep, PadsMD md) => Pads rep md | rep -> md  where
  def :: rep
  def = gdef
  parsePP  :: PadsParser(rep,md)
  printFL :: (rep,md) -> FList

parseS   :: Pads rep md => String -> ((rep, md), String) 
parseS cs = parseStringInput parsePP cs 

parseFile :: Pads rep md => FilePath -> IO (rep, md)
parseFile file = parseFileWith parsePP file

printS :: Pads rep md => (rep,md) -> String
printS = B.unpack . printBS

printBS :: Pads rep md => (rep,md) -> B.ByteString
printBS r = printFL r B.empty

printFile :: Pads rep md => FilePath -> (rep,md) -> IO ()
printFile filepath r = B.writeFile filepath (printBS r)



class (Data rep, PadsMD md) => Pads1 arg rep md | rep->md, rep->arg where
  def1 :: arg -> rep
  def1 =  \_ -> gdef
  parsePP1  :: arg -> PadsParser(rep,md)
  printFL1 :: arg -> (rep,md) -> FList

parseS1 :: Pads1 arg rep md => arg -> String -> ((rep, md), String) 
parseS1 arg cs = parseStringInput (parsePP1 arg) cs

parseFile1 :: Pads1 arg rep md => arg-> FilePath -> IO (rep, md)
parseFile1 arg file = parseFileWith (parsePP1 arg) file

printS1 :: Pads1 arg rep md => arg -> (rep,md) -> String
printS1 arg (rep,md) = B.unpack (printBS1 arg (rep,md))

printBS1 :: Pads1 arg rep md => arg -> (rep,md) -> B.ByteString
printBS1 arg r = printFL1 arg r B.empty

printFile1 :: Pads1 arg rep md => arg -> FilePath -> (rep,md) -> IO ()
printFile1 arg filepath r = B.writeFile filepath (printBS1 arg r)


parseFileWith  :: (Data rep, PadsMD md) => PadsParser (rep,md) -> FilePath -> IO (rep,md)
parseFileWith p file = do
   result <- CE.try (parseFileWithRaw p file)
   case result of
     Left (e::CE.SomeException) -> return (gdef, replace_md_header gdef
                                                 (mkErrBasePD (E.FileError (show e) file) Nothing))
     Right r -> return r

parseFileWithRaw :: PadsParser (rep,md) -> FilePath -> IO (rep,md)
parseFileWithRaw p file = do
       { bs <- B.readFile file
       ; return (parseByteStringInput p bs)
       }



{- Generic function for computing the default for any type supporting Data a interface -}
getConstr :: DataType -> Constr
getConstr ty = 
   case dataTypeRep ty of
        AlgRep cons -> head cons
        IntRep      -> mkIntegralConstr ty 0
        FloatRep    -> mkRealConstr ty 0.0 
        CharRep     -> mkCharConstr ty '\NUL'
        NoRep       -> error "PADSC: Unexpected NoRep in PADS type"

gdef :: Data a => a
gdef = def_help 
  where
    def_help
     =   let ty = dataTypeOf (def_help)
             constr = getConstr ty
         in fromConstrB gdef constr 

ext2 :: (Data a, Typeable2 t)
     => c a
     -> (forall d1 d2. (Data d1, Data d2) => c (t d1 d2))
     -> c a
ext2 def ext = maybe def id (dataCast2 ext)

newtype B x = B {unB :: x}

ext2B :: (Data a, Typeable2 t)
      => a
      -> (forall b1 b2. (Data b1, Data b2) => t b1 b2)
      -> a
ext2B def ext = unB ((B def) `ext2` (B ext))


myempty :: forall a. Data a => a
myempty = general 
      `extB` char 
      `extB` int
      `extB` integer
      `extB` float 
      `extB` double 
      `extB` coff
      `extB` epochTime
      `extB` fileMode
      `ext2B` map
      `ext1B` list where
  -- Generic case
  general :: Data a => a
  general = fromConstrB myempty (indexConstr (dataTypeOf general) 1)
  
  -- Base cases
  char    = '\NUL'
  int     = 0      :: Int
  integer = 0      :: Integer
  float   = 0.0    :: Float
  double  = 0.0    :: Double
  coff    = 0      :: COff
  epochTime = 0    :: EpochTime
  fileMode = 0     :: FileMode
  list :: Data b => [b]
  list    = []
  map :: Data.Map.Map k v
  map = Data.Map.empty


doTime a = do
 { begin <- getCPUTime
 ; v <- a
 ; end <- getCPUTime
 ; return (v, end-begin)
 }

class BuildContainer2 c item where
  buildContainer2 :: [(FilePath,item)] -> c FilePath item
  toList2         :: c FilePath item -> [(FilePath,item)]

instance BuildContainer2 Map a  where
  buildContainer2 = Data.Map.fromList
  toList2         = Data.Map.toList

class BuildContainer1 c item where
  buildContainer1 :: [(FilePath,item)] -> c (FilePath, item)
  toList1         :: c (FilePath, item) ->  [(FilePath,item)]

instance Ord a => BuildContainer1 Set a  where
  buildContainer1 = Data.Set.fromList
  toList1         = Data.Set.toList


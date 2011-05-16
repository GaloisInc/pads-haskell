module Language.Pads.LazyList where

import qualified Data.ByteString as B
import qualified Language.Pads.Source as S
import qualified Data.List as List

-- Lazy append-lists 

type FList = B.ByteString -> B.ByteString

(+++) :: FList -> FList -> FList 
p +++ q = \ws -> p (q ws)

nil :: FList 
nil = \ws -> ws

concatFL :: [FList] -> FList
concatFL (f:fs) = f +++ (concatFL fs)
concatFL [] = nil

--cons :: a -> FList a -> FList a
--cons x q = \ws -> x : q ws

fshow :: Show a => a -> FList 
fshow x = \ws -> B.append (S.strToByteString (show x)) ws

addString :: String -> FList 
addString s = \ws -> B.append (S.strToByteString s)  ws

printEOR :: FList
printEOR = addString ['\n']

printEOF :: FList
printEOF = addString []

printNothing :: FList
printNothing ws = ws

endRecord :: FList -> FList
endRecord fst = fst +++ printEOR

addBString :: B.ByteString -> FList 
addBString bs = \ws -> B.append bs  ws

printF :: FList -> IO ()
printF q = Prelude.print (B.unpack (q B.empty))



--------------------------------------------------



printList :: ((r,m) -> FList) -> FList -> FList -> ([r], (b,[m])) -> FList
printList printItem printSep printTerm (reps, (_,mds)) = 
   (concatFL (List.intersperse printSep (map printItem (zip reps mds))) )
   +++ printTerm


{-



type IntPair = (Int,"|",Int)

=====>

type IntPair    = (Int, Int)
type IntPair_md = (Base_md, (Base_md, Base_md))

intPair_parseM
       = let
           f_rep x1 x3 = (x1, x3)
           f_md x1 x2 x3
             = (mergeBaseMDs
                  [get_md_header x1, get_md_header x2, get_md_header x3], 
                (x1, x3))
         in
           (((return (f_rep, f_md) =@= int_parseM) =@ strLit_parseM "|")
          =@=
            int_parseM)

intPair_parseS = parseStringInput intPair_parseM]

intPair_printFL (r,m)
  = case (r,m) of
      ((r1,r2),(_,(m1,m2)))
        -> int_PrintFL (r1,m1) +++
           addString "|" +++
           int_PrintFL (r2,m2)



















-}












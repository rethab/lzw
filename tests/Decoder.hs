{-# LANGUAGE TemplateHaskell #-}

module Decoder where

import Test.QuickCheck
import Test.QuickCheck.All
import Test.HUnit
import Data.List     ((\\), nubBy)
import Data.Word     (Word32)
import Control.Monad (liftM2)
import Data.Monoid   (mappend)

import qualified Data.HashMap.Strict       as M
import qualified Data.ByteString           as S
import qualified Data.Binary.Strict.BitGet as BitGet

import Compression.Huffman.Decoder


main = runhunit >> $quickCheckAll

data MkDecoderIn = MkDecoderIn BTree [Word32] deriving (Show)

instance Arbitrary MkDecoderIn where
    arbitrary = do btree <- suchThat arbitrary (\tree -> leaves tree > 0 && leaves tree < 1000)
                   words <- suchThat (vector (leaves btree)) unique
                   return $ MkDecoderIn btree words 
                     where unique vals = nubBy (==) vals == vals

instance Arbitrary BTree where
    arbitrary = oneof [return Leaf, liftM2 Node arbitrary arbitrary]

leaves :: BTree -> Int
leaves Leaf = 1
leaves (Node l r) = leaves l + leaves r

nodes :: BTree -> Int
nodes Leaf = 0
nodes (Node l r) = 1 + (nodes l) + (nodes r)

prop_bits_in_hashmap (MkDecoderIn tree words) = 
    let dec = mkDecoder tree words
        elems = M.elems dec
    in null (words \\ elems) && null (elems \\ words)

runhunit = mapM_ runTestTT $  map (\(lbl, test) -> TestLabel lbl test) units'
    where units' = [ ("blackbox_serialize", TestCase blackbox_deserialize) 
                   , ("decode_bintree1", TestCase decode_bintree1)
                   , ("decode_bintree2", TestCase decode_bintree2)
                   ]

blackbox_deserialize = let size = S.pack [0, 0, 0, 0, 0, 0, 0, 4]
                           leaves = S.pack [0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0, 5, 0, 0, 0, 6]
                           structure = S.pack [200]
                           following = S.pack [42, 125] 
                           (dec, rest) = deserialize (size `mappend` leaves `mappend` structure `mappend` following)
                       in do M.lookup "11" dec @?= Just 3
                             M.lookup "10" dec @?= Just 4
                             M.lookup "01" dec @?= Just 5
                             M.lookup "00" dec @?= Just 6
                             rest @?= following

decode_bintree1 = let bits = S.pack [200]
                      tree = case BitGet.runBitGet bits readTree of
                               Left e -> error e
                               Right v -> v
                 in do nodes tree @?= 3
                       leaves tree @?= 4

decode_bintree2 = let bits = S.pack [168]
                      tree = case BitGet.runBitGet bits readTree of
                               Left e -> error e
                               Right v -> v
                 in do nodes tree @?= 3
                       leaves tree @?= 4

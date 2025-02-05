{-# LANGUAGE DeriveGeneric, DeriveDataTypeable, DeriveFunctor, DeriveTraversable, DeriveFoldable #-}

module Conjure.Language.Expression.Op.Indexing where

import Conjure.Prelude
import Conjure.Language.Expression.Op.Internal.Common

import qualified Data.Aeson as JSON             -- aeson
import qualified Data.HashMap.Strict as M       -- unordered-containers
import qualified Data.Vector as V               -- vector

-- pretty
import qualified Text.PrettyPrint as Pr ( cat )


data OpIndexing x = OpIndexing x x
    deriving (Eq, Ord, Show, Data, Functor, Traversable, Foldable, Typeable, Generic)

instance Serialize x => Serialize (OpIndexing x)
instance Hashable  x => Hashable  (OpIndexing x)
instance ToJSON    x => ToJSON    (OpIndexing x) where toJSON = genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpIndexing x) where parseJSON = genericParseJSON jsonOptions

instance (TypeOf x, Pretty x, ExpressionLike x, ReferenceContainer x) => TypeOf (OpIndexing x) where
    typeOf p@(OpIndexing m i) = do
        tyM <- typeOf m
        tyI <- typeOf i
        case tyM of
            TypeMatrix tyIndex inn
                | typesUnify [tyIndex, tyI] -> return inn
                | otherwise -> fail $ "Indexing with inappropriate type:" <++> vcat
                    [ "The expression:"  <+> pretty p
                    , "Indexing:"        <+> pretty m
                    , "Expected type of index:" <+> pretty tyIndex
                    , "Actual type of index  :" <+> pretty tyI
                    ]
            TypeList inn
                | typesUnify [TypeInt TagInt, tyI] -> return inn
                | otherwise -> fail $ "Indexing with inappropriate type:" <++> vcat
                    [ "The expression:"  <+> pretty p
                    , "Indexing:"        <+> pretty m
                    , "Expected type of index:" <+> pretty (TypeInt TagInt)
                    , "Actual type of index  :" <+> pretty tyI
                    ]
            TypeTuple inns   -> do
                TypeInt t <- typeOf i
                case t of
                    TagInt -> return ()
                    _ -> fail $ "Tuples cannot be indexed by enums/unnameds:" <++> pretty p
                case intOut "OpIndexing" i of
                    Nothing -> fail $ "Tuples can only be indexed by constants:" <++> pretty p
                    Just iInt | iInt <= 0 || iInt > genericLength inns ->
                                    fail $ "Out of bounds tuple indexing:" <++> pretty p
                              | otherwise -> return (at inns (fromInteger (iInt-1)))
            TypeRecord inns  -> do
                nm <- nameOut i
                case lookup nm inns of
                    Nothing -> fail $ "Record indexing with non-member field:" <++> vcat
                        [ "The expression:" <+> pretty p
                        , "Indexing:"       <+> pretty m
                        , "With type:"      <+> pretty tyM
                        ]
                    Just ty -> return ty
            TypeVariant inns -> do
                nm <- nameOut i
                case lookup nm inns of
                    Nothing -> fail $ "Variant indexing with non-member field:" <++> vcat
                        [ "The expression:" <+> pretty p
                        , "Indexing:"       <+> pretty m
                        , "With type:"      <+> pretty tyM
                        ]
                    Just ty -> return ty
            _ -> fail $ "Indexing something other than a matrix or a tuple:" <++> vcat
                    [ "The expression:" <+> pretty p
                    , "Indexing:"       <+> pretty m
                    , "With type:"      <+> pretty tyM
                    ]

instance SimplifyOp OpIndexing x where
    simplifyOp _ = na "simplifyOp{OpIndexing}"

instance Pretty x => Pretty (OpIndexing x) where
    prettyPrec _ (OpIndexing a b) = Pr.cat [pretty a, nest 4 (prBrackets (pretty b))]

instance VarSymBreakingDescription x => VarSymBreakingDescription (OpIndexing x) where
    varSymBreakingDescription (OpIndexing a b) = JSON.Object $ M.fromList
        [ ("type", JSON.String "OpIndexing")
        , ("children", JSON.Array $ V.fromList
            [ varSymBreakingDescription a
            , varSymBreakingDescription b
            ])
        ]

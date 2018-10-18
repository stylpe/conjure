{-# LANGUAGE DeriveGeneric, DeriveDataTypeable, DeriveFunctor, DeriveTraversable, DeriveFoldable, ViewPatterns #-}

module Conjure.Language.Expression.Op.Slicing where

import Conjure.Prelude
import Conjure.Language.Expression.Op.Internal.Common

import qualified Data.Aeson as JSON             -- aeson
import qualified Data.HashMap.Strict as M       -- unordered-containers
import qualified Data.Vector as V               -- vector


data OpSlicing x = OpSlicing x (Maybe x) (Maybe x)
    deriving (Eq, Ord, Show, Data, Functor, Traversable, Foldable, Typeable, Generic)

instance Serialize x => Serialize (OpSlicing x)
instance Hashable  x => Hashable  (OpSlicing x)
instance ToJSON    x => ToJSON    (OpSlicing x) where toJSON = genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (OpSlicing x) where parseJSON = genericParseJSON jsonOptions

instance (TypeOf x, Pretty x) => TypeOf (OpSlicing x) where
    typeOf p@(OpSlicing m _ _) = do
        ty <- typeOf m
        case ty of
            TypeMatrix{} -> return ()
            TypeList{} -> return ()
            _ -> raiseTypeError p
        return ty

instance EvaluateOp OpSlicing where
    evaluateOp (OpSlicing (viewConstantMatrix -> Just (DomainInt _ index, vals)) lb ub) = do
        indexVals <- valuesInIntDomain index
        outVals   <- fmap catMaybes $ forM (zip indexVals vals) $ \ (thisIndex, thisVal) ->
            case lb of
                Just (ConstantInt Nothing lower) | lower > thisIndex -> return Nothing
                _ -> case ub of
                    Just (ConstantInt Nothing upper) | upper < thisIndex -> return Nothing
                    _ -> return $ Just (thisIndex, thisVal)
        let outDomain = DomainInt Nothing $ map (RangeSingle . ConstantInt Nothing . fst) outVals
        return $ ConstantAbstract $ AbsLitMatrix outDomain (map snd outVals)
    evaluateOp op = na $ "evaluateOp{OpSlicing}:" <++> pretty (show op)

instance SimplifyOp OpSlicing x where
    simplifyOp _ = na "simplifyOp{OpSlicing}"

instance Pretty x => Pretty (OpSlicing x) where
    prettyPrec _ (OpSlicing m a b) = pretty m <> prBrackets (pretty a <> ".." <> pretty b)

instance VarSymBreakingDescription x => VarSymBreakingDescription (OpSlicing x) where
    varSymBreakingDescription (OpSlicing a b c) = JSON.Object $ M.fromList
        [ ("type", JSON.String "OpSlicing")
        , ("children", JSON.Array $ V.fromList
            [ varSymBreakingDescription a
            , maybe JSON.Null varSymBreakingDescription b
            , maybe JSON.Null varSymBreakingDescription c
            ])
        ]

{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ParallelListComp #-}

module Conjure.RefineParam ( refineSingleParam, refineParam ) where

-- conjure
import Conjure.UpDown
import Language.E.Imports
import Language.E.Definition

-- containers
import Data.Tree ( Tree(..) )


-- | Refining a single high level value with (and a given high level domain) to a low level value (and the low level domain).
--   A tree of representations is taken as an argument. Values in this tree give representations for each level of nesting for the domain.
refineSingleParam
    :: MonadError UpDownError m
    => Tree Representation
    ->    (Text, Domain Constant, Constant)
    -> m [(Text, Domain Constant, Constant)]
refineSingleParam (Node representation representations) (name, highDomain, highValue) = do
    (lowDomainsGen, lowNamesGen, _, lowValuesGen, _) <- upDown representation highDomain
    let lowNames = map ($ name) lowNamesGen
    lowDomains <- lowDomainsGen
    lowValues  <- lowValuesGen highValue
    if null representations
        then 
            return [ (n,d,v)
                | n <- lowNames
                | d <- lowDomains
                | v <- lowValues
                ]
        else
            liftM concat $ sequence [ refineSingleParam r (n,d,v)
                | r <- representations
                | n <- lowNames
                | d <- lowDomains
                | v <- lowValues
                ]


refineParam
    :: MonadError UpDownError m
    => Spec                         -- ^ Essence
    -> Maybe Spec                   -- ^ Essence Parameter
    -> Spec                         -- ^ Essence'
    -> m Spec                       -- ^ Essence' Parameter
refineParam = error "refineParam"


{-
 - Module      : Conjure.Process.StrengthenVariables
 - Description : Strengthen variables using type- and domain-inference.
 - Copyright   : Billy Brown 2017
 - License     : BSD3
 
 Processing step that attempts to strengthen variables at the Essence class level, using methods described in the "Reformulating Essence Specifications for Robustness" paper.
-}

module Conjure.Process.StrengthenVariables
  (
    strengthenVariables
  ) where

import Data.List ( intersect, union )
import Data.Maybe ( mapMaybe )

import Conjure.Prelude
import Conjure.Language
import Conjure.Language.NameResolution ( resolveNames )
-- These two are needed together
import Conjure.Language.Expression.DomainSizeOf ()
import Conjure.Language.DomainSizeOf ( domainSizeOf )

-- | Strengthen the variables in a model using type- and domain-inference.
strengthenVariables :: (MonadFail m, MonadLog m, MonadUserError m)
                    => Model -> m Model
strengthenVariables = runNameGen . (resolveNames >=> core)
  where core model = do model' <- foldM folded model [ functionAttributes
                                                     ]
                        if model == model'
                           then return model'
                           else core model'
        -- Apply the function to every statement and fold it into the model
        folded m@Model { mStatements = stmts } f
          = foldM (\m' s -> do
                    s' <- f m s
                    -- This is map, but unwraps the value from the monad
                    return m' { mStatements = s' : mStatements m' })
                  m { mStatements = [] }
                  (reverse stmts)

-- | Make the attributes of function variables as constrictive as possible.
functionAttributes :: (MonadFail m, MonadLog m)
                   => Model       -- ^ Model as context.
                   -> Statement   -- ^ Statement to constrain.
                   -> m Statement -- ^ Possibly updated statement.
functionAttributes m (Declaration (FindOrGiven forg n d@DomainFunction{})) = do
  d' <- constrainFunctionDomain n d m
  return $ Declaration (FindOrGiven forg n d')
functionAttributes m (Declaration (Letting n (Domain d@DomainFunction{}))) = do
  d' <- constrainFunctionDomain n d m
  return $ Declaration (Letting n (Domain d'))
functionAttributes _ s = return s

-- | Constrain the domain of a function given the context of a model.
constrainFunctionDomain :: (MonadFail m, MonadLog m)
                        => Name                     -- ^ Name of the function.
                        -> Domain () Expression     -- ^ Current domain of the function.
                        -> Model                    -- ^ Context of the model.
                        -> m (Domain () Expression) -- ^ Possibly modified domain.
constrainFunctionDomain n d@DomainFunction{} m
  = surjectiveIsTotalBijective d  >>=
    totalInjectiveIsBijective     >>=
    definedForAllIsTotal n (suchThat m)
constrainFunctionDomain _ d _ = return d

-- | Extract the such that expressions from a model.
suchThat :: Model -> [Expression]
suchThat = foldr fromSuchThat [] . mStatements
  where fromSuchThat (SuchThat es) a = a `union` es
        fromSuchThat _             a = a

-- | If a function is surjective or bijective and its domain and codomain
--   are of equal size, then it is total and bijective.
surjectiveIsTotalBijective :: (MonadFail m, MonadLog m)
                           => Domain () Expression      -- ^ Domain of the function.
                           -> m (Domain () Expression)  -- ^ Possibly modified domain.
surjectiveIsTotalBijective d@(DomainFunction r (FunctionAttr s PartialityAttr_Partial j) from to)
  | j == JectivityAttr_Surjective || j == JectivityAttr_Bijective = do
    (fromSize, toSize) <- functionDomainSizes from to
    if fromSize == toSize
       then return $ DomainFunction r (FunctionAttr s PartialityAttr_Total JectivityAttr_Bijective) from to
       else return d
surjectiveIsTotalBijective d = return d

-- | If a function is total and injective, and its domain and codomain
--   are of equal size, then it is bijective.
totalInjectiveIsBijective :: (MonadFail m, MonadLog m)
                          => Domain () Expression
                          -> m (Domain () Expression)
totalInjectiveIsBijective d@(DomainFunction r (FunctionAttr s p@PartialityAttr_Total JectivityAttr_Injective) from to) = do
  (fromSize, toSize) <- functionDomainSizes from to
  if fromSize == toSize
     then return $ DomainFunction r (FunctionAttr s p JectivityAttr_Bijective) from to
     else return d
totalInjectiveIsBijective d = return d

-- | Calculate the sizes of the domain and codomain of a function.
functionDomainSizes :: (MonadFail m)
                    => Domain () Expression       -- ^ The function's domain.
                    -> Domain () Expression       -- ^ The function's codomain.
                    -> m (Expression, Expression) -- ^ The sizes of the two.
functionDomainSizes from to = do
  fromSize <- domainSizeOf from
  toSize   <- domainSizeOf to
  return (fromSize, toSize)

-- | If a function is defined for all values in its domain, then it is total.
definedForAllIsTotal :: (MonadFail m, MonadLog m)
                     => Name                      -- ^ Name of the function.
                     -> [Expression]              -- ^ Such that constraints.
                     -> Domain () Expression      -- ^ Domain of the function.
                     -> m (Domain () Expression)  -- ^ Possibly modified domain.
definedForAllIsTotal n cs (DomainFunction r (FunctionAttr s PartialityAttr_Partial j) from to)
  | any definedForAll cs
    = return $ DomainFunction r (FunctionAttr s PartialityAttr_Total j) from to
  where
        -- Is there at least one forAll expression that uses the variable?
        definedForAll (Op (MkOpAnd (OpAnd (Comprehension e gorcs))))
          = functionCalledWithParam e n gorcs from && -- the function in question is called with the correct generated parameter
            hasNoImplications e &&                    -- no implications to ignore domain values
            hasNoConditions gorcs                     -- no conditions to ignore domain values
        definedForAll _ = False
        -- Make sure that there are no implications in an expression
        hasNoImplications = not . any isImplies . universe
        isImplies (Op (MkOpImply OpImply{})) = True
        isImplies _                          = False
        -- Make sure that there are no conditions in a list of generators or conditions
        hasNoConditions = not . any isCondition
        isCondition Condition{} = True
        isCondition _           = False
definedForAllIsTotal _ _ d = return d

-- | Determine whether the given function is called with a value generated from its domain.
functionCalledWithParam :: Expression             -- ^ Expression being checked for the function call.
                        -> Name                   -- ^ Name of the function being called.
                        -> [GeneratorOrCondition] -- ^ Generated variables and conditions of the comprehension.
                        -> Domain () Expression   -- ^ Domain of the function.
                        -> Bool                   -- ^ Whether or not the function is called with a value generated from the domain.
functionCalledWithParam e n gorcs from = let funCalls = filter isFunctionCall $ universe e
                                             in any (functionCallsWithParam generatedVariables) funCalls
  where
        -- Get the names of the generated variables
        generatedVariables = mapMaybe getGeneratedName $ filter isGenerator gorcs
        isGenerator (Generator GenDomainNoRepr{}) = True
        isGenerator _                             = False
        getGeneratedName (Generator (GenDomainNoRepr (Single n') _)) = Just n'
        getGeneratedName _                                           = Nothing
        isFunctionCall (Op (MkOpRelationProj OpRelationProj{})) = True
        isFunctionCall _                                        = False
        -- Determine whether the function is called with a generated parameter
        functionCallsWithParam ps (Op (MkOpRelationProj (OpRelationProj (Reference n' _) args)))
          | n' == n = not $ null $ ps `intersect` mapMaybe getArgName (filter domainArg args)
        functionCallsWithParam _  _ = False
        domainArg (Just (Reference _ d)) = d `domainEquals` from
        domainArg _                      = False
        domainEquals (Just (DeclNoRepr _ _ d1 _)) d2 = d1 == d2
        domainEquals _                            _  = False
        getArgName (Just (Reference n' _)) = Just n'
        getArgName _                       = Nothing

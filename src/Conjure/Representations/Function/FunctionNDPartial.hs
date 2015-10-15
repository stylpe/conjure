{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ViewPatterns #-}

module Conjure.Representations.Function.FunctionNDPartial ( functionNDPartial ) where

-- conjure
import Conjure.Prelude
import Conjure.Bug
import Conjure.Language.Definition
import Conjure.Language.Domain
import Conjure.Language.Pretty
import Conjure.Language.TH
import Conjure.Language.Lenses
import Conjure.Language.ZeroVal ( zeroVal )
import Conjure.Representations.Internal
import Conjure.Representations.Common
import Conjure.Representations.Function.Function1D ( domainValues )


functionNDPartial :: forall m . (MonadFail m, NameGen m) => Representation m
functionNDPartial = Representation chck downD structuralCons downC up

    where

        viewAsDomainTuple (DomainTuple doms) = Just doms
        viewAsDomainTuple (DomainRecord doms) = Just (doms |> sortBy (comparing fst) |> map snd)
        viewAsDomainTuple _ = Nothing

        -- domain -> (how to make abslit, how to inspect abslit)
        mkLensAsDomainTuple (DomainTuple _) =
            Just
                ( \ vals -> ConstantAbstract (AbsLitTuple vals)
                , \ val -> case val of
                        ConstantAbstract (AbsLitTuple vals) -> Just vals
                        _ -> Nothing
                )
        mkLensAsDomainTuple (DomainRecord doms) =
            let names = doms |> sortBy (comparing fst) |> map fst
            in  Just
                ( \ vals -> ConstantAbstract (AbsLitRecord (zip names vals))
                , \ val -> case val of
                        ConstantAbstract (AbsLitRecord vals) -> Just (vals |> sortBy (comparing fst) |> map snd)
                        _ -> Nothing
                )
        mkLensAsDomainTuple _ = Nothing

        chck :: TypeOf_ReprCheck
        chck f (DomainFunction _
                    attrs@(FunctionAttr _ PartialityAttr_Partial _)
                    innerDomainFr@(viewAsDomainTuple -> Just innerDomainFrs)
                    innerDomainTo) | all domainCanIndexMatrix innerDomainFrs =
            DomainFunction "FunctionNDPartial" attrs
                <$> f innerDomainFr
                <*> f innerDomainTo
        chck _ _ = []

        nameFlags  name = mconcat [name, "_", "FunctionNDPartial_Flags"]
        nameValues name = mconcat [name, "_", "FunctionNDPartial_Values"]

        downD :: TypeOf_DownD m
        downD (name, DomainFunction "FunctionNDPartial"
                    (FunctionAttr _ PartialityAttr_Partial _)
                    (viewAsDomainTuple -> Just innerDomainFrs)
                    innerDomainTo) | all domainCanIndexMatrix innerDomainFrs = do
            let unroll is j = foldr DomainMatrix j is
            return $ Just
                [ ( nameFlags name
                  , unroll (map forgetRepr innerDomainFrs) DomainBool
                  )
                , ( nameValues name
                  , unroll (map forgetRepr innerDomainFrs) innerDomainTo
                  )
                ]
        downD _ = na "{downD} FunctionNDPartial"

        structuralCons :: TypeOf_Structural m
        structuralCons f downX1
            (DomainFunction "FunctionNDPartial"
                (FunctionAttr sizeAttr PartialityAttr_Partial jectivityAttr)
                innerDomainFr@(viewAsDomainTuple -> Just innerDomainFrs)
                innerDomainTo) | all domainCanIndexMatrix innerDomainFrs = do
            let
                kRange = case innerDomainFr of
                        DomainTuple ts  -> map fromInt [1 .. genericLength ts]
                        DomainRecord rs -> map (fromName . fst) rs
                        _ -> bug $ vcat [ "FunctionNDPartial.structuralCons"
                                        , "innerDomainFr:" <+> pretty innerDomainFr
                                        ]
                toIndex x = [ [essence| &x[&k] |] | k <- kRange ]
                index x m = make opMatrixIndexing m (toIndex x)

            let injectiveCons flags values = do
                    (iPat, i) <- quantifiedVar
                    (jPat, j) <- quantifiedVar
                    let flagsIndexedI  = index i flags
                    let valuesIndexedI = index i values
                    let flagsIndexedJ  = index j flags
                    let valuesIndexedJ = index j values
                    return $ return $ -- list
                        [essence|
                            and([ &valuesIndexedI != &valuesIndexedJ
                                | &iPat : &innerDomainFr
                                , &jPat : &innerDomainFr
                                , &i .< &j
                                , &flagsIndexedI
                                , &flagsIndexedJ
                                ])
                        |]

            let surjectiveCons flags values = do
                    (iPat, i) <- quantifiedVar
                    (jPat, j) <- quantifiedVar

                    let flagsIndexed  = index j flags
                    let valuesIndexed = index j values
                    return $ return $ -- list
                        [essence|
                            forAll &iPat : &innerDomainTo .
                                exists &jPat : &innerDomainFr .
                                    &flagsIndexed /\ &valuesIndexed = &i
                        |]

            let jectivityCons flags values = case jectivityAttr of
                    JectivityAttr_None       -> return []
                    JectivityAttr_Injective  -> injectiveCons  flags values
                    JectivityAttr_Surjective -> surjectiveCons flags values
                    JectivityAttr_Bijective  -> (++) <$> injectiveCons  flags values
                                                     <*> surjectiveCons flags values

            let cardinality flags = do
                    (iPat, i) <- quantifiedVar
                    let flagsIndexed  = index i flags
                    return [essence| sum &iPat : &innerDomainFr . toInt(&flagsIndexed) |]

            let dontCareInactives flags values = do
                    (iPat, i) <- quantifiedVar
                    let flagsIndexed  = index i flags
                    let valuesIndexed = index i values
                    return $ return $ -- list
                        [essence|
                            forAll &iPat : &innerDomainFr . &flagsIndexed = false ->
                                dontCare(&valuesIndexed)
                        |]

            let innerStructuralCons flags values = do
                    (iPat, i) <- quantifiedVar
                    let flagsIndexed  = index i flags
                    let valuesIndexed = index i values
                    let activeZone b = [essence| forAll &iPat : &innerDomainFr . &flagsIndexed -> &b |]

                    -- preparing structural constraints for the inner guys
                    innerStructuralConsGen <- f innerDomainTo

                    let inLoop = valuesIndexed
                    outs <- innerStructuralConsGen inLoop
                    return (map activeZone outs)

            return $ \ rel -> do
                refs <- downX1 rel
                case refs of
                    [flags,values] ->
                        concat <$> sequence
                            [ jectivityCons flags values
                            , dontCareInactives flags values
                            , mkSizeCons sizeAttr <$> cardinality flags
                            , innerStructuralCons flags values
                            ]
                    _ -> na "{structuralCons} FunctionNDPartial"

        structuralCons _ _ _ = na "{structuralCons} FunctionNDPartial"

        downC :: TypeOf_DownC m
        downC ( name
              , DomainFunction "FunctionNDPartial"
                    (FunctionAttr _ PartialityAttr_Partial _)
                    innerDomainFr@(viewAsDomainTuple -> Just innerDomainFrs)
                    innerDomainTo
              , ConstantAbstract (AbsLitFunction vals)
              ) | all domainCanIndexMatrix innerDomainFrs
                , Just (_mk, inspect) <- mkLensAsDomainTuple innerDomainFr = do
            z <- zeroVal innerDomainTo
            let
                check :: [Constant] -> Maybe Constant
                check indices = listToMaybe [ v
                                            | (inspect -> Just k, v) <- vals
                                            , k == indices
                                            ]

            let
                unrollD :: [Domain () Constant] -> Domain r Constant -> Domain r Constant
                unrollD is j = foldr DomainMatrix j is

            let
                unrollC :: MonadFail m
                        => [Domain () Constant]
                        -> [Constant]               -- indices
                        -> m (Constant, Constant)
                unrollC [i] prevIndices = do
                    domVals <- domainValues i
                    let active val = check $ prevIndices ++ [val]
                    return ( ConstantAbstract $ AbsLitMatrix i
                                [ case active val of
                                    Nothing -> ConstantBool False
                                    Just{}  -> ConstantBool True
                                | val <- domVals ]
                           , ConstantAbstract $ AbsLitMatrix i
                                [ fromMaybe z (active val)
                                | val <- domVals ]
                           )
                unrollC (i:is) prevIndices = do
                    domVals <- domainValues i
                    (matrixFlags, matrixVals) <- fmap unzip $ forM domVals $ \ val ->
                        unrollC is (prevIndices ++ [val])
                    return ( ConstantAbstract $ AbsLitMatrix i matrixFlags
                           , ConstantAbstract $ AbsLitMatrix i matrixVals
                           )
                unrollC is prevIndices = fail $ vcat [ "FunctionNDPartial.up.unrollC"
                                                     , "    is         :" <+> vcat (map pretty is)
                                                     , "    prevIndices:" <+> pretty (show prevIndices)
                                                     ]

            (outFlags, outValues) <- unrollC (map forgetRepr innerDomainFrs) []
            return $ Just
                [ ( nameFlags name
                  , unrollD (map forgetRepr innerDomainFrs) DomainBool
                  , outFlags
                  )
                , ( nameValues name
                  , unrollD (map forgetRepr innerDomainFrs) innerDomainTo
                  , outValues
                  )
                ]

        downC _ = na "{downC} FunctionNDPartial"

        up :: TypeOf_Up m
        up ctxt (name, domain@(DomainFunction "FunctionNDPartial"
                                (FunctionAttr _ PartialityAttr_Partial _)
                                innerDomainFr@(viewAsDomainTuple -> Just innerDomainFrs) _))

            | Just (mk, _inspect) <- mkLensAsDomainTuple innerDomainFr =

            case (lookup (nameFlags name) ctxt, lookup (nameValues name) ctxt) of
                (Just flagMatrix, Just valuesMatrix) -> do
                    let
                        allIndices :: (MonadFail m, Pretty r) => [Domain r Constant] -> m [[Constant]]
                        allIndices = fmap sequence . mapM domainValues

                        index :: MonadFail m => Constant -> [Constant] -> m Constant
                        index m [] = return m
                        index (ConstantAbstract (AbsLitMatrix indexDomain vals)) (i:is) = do
                            froms <- domainValues indexDomain
                            case lookup i (zip froms vals) of
                                Nothing -> fail "Value not found. FunctionNDPartial.up.index"
                                Just v  -> index v is
                        index m is = bug ("RelationAsMatrix.up.index" <+> pretty m <+> pretty (show is))

                    indices  <- allIndices innerDomainFrs
                    vals     <- forM indices $ \ these -> do
                        flag  <- index flagMatrix   these
                        value <- index valuesMatrix these
                        case flag of
                            ConstantBool False -> return Nothing
                            ConstantBool True  -> return (Just (mk these, value))
                            _ -> fail $ vcat
                                [ "Expecting a boolean literal, but got:" <+> pretty flag
                                , "                           , and    :" <+> pretty value
                                , "When working on:" <+> pretty name
                                , "With domain:" <+> pretty domain
                                ]
                    return ( name
                           , ConstantAbstract $ AbsLitFunction $ catMaybes vals
                           )

                (Nothing, _) -> fail $ vcat $
                    [ "(in FunctionNDPartial up 1)"
                    , "No value for:" <+> pretty (nameFlags name)
                    , "When working on:" <+> pretty name
                    , "With domain:" <+> pretty domain
                    ] ++
                    ("Bindings in context:" : prettyContext ctxt)
                (_, Nothing) -> fail $ vcat $
                    [ "(in FunctionNDPartial up 2)"
                    , "No value for:" <+> pretty (nameValues name)
                    , "When working on:" <+> pretty name
                    , "With domain:" <+> pretty domain
                    ] ++
                    ("Bindings in context:" : prettyContext ctxt)
        up _ _ = na "{up} FunctionNDPartial"

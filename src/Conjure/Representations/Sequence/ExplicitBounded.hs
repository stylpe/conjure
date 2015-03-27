{-# LANGUAGE QuasiQuotes #-}

module Conjure.Representations.Sequence.ExplicitBounded ( sequenceExplicitBounded ) where

-- conjure
import Conjure.Prelude
import Conjure.Language.Definition
import Conjure.Language.Domain
import Conjure.Language.TH
import Conjure.Language.Pretty
import Conjure.Language.ZeroVal ( zeroVal )
import Conjure.Representations.Internal
import Conjure.Representations.Common


sequenceExplicitBounded :: forall m . (MonadFail m, NameGen m) => Representation m
sequenceExplicitBounded = Representation chck downD structuralCons downC up

    where

        chck :: TypeOf_ReprCheck
        chck f (DomainSequence _ attrs@(SequenceAttr sizeAttr _) innerDomain) | hasMaxSize sizeAttr =
            DomainSequence "ExplicitBounded" attrs <$> f innerDomain
        chck _ _ = []

        nameMarker name = mconcat [name, "_", "ExplicitBounded", "_Length"]
        nameValues name = mconcat [name, "_", "ExplicitBounded", "_Values" ]

        hasMaxSize SizeAttr_Size{} = True
        hasMaxSize SizeAttr_MaxSize{} = True
        hasMaxSize SizeAttr_MinMaxSize{} = True
        hasMaxSize _ = False

        getMaxSize (SizeAttr_MaxSize x) = return x
        getMaxSize (SizeAttr_MinMaxSize _ x) = return x
        getMaxSize _ = fail "Unknown maxSize"

        downD :: TypeOf_DownD m
        downD (name, DomainSequence "ExplicitBounded" (SequenceAttr (SizeAttr_Size size) _) innerDomain) =
            return $ Just
                [ ( nameMarker name
                  , DomainInt [RangeBounded size size]
                  )
                , ( nameValues name
                  , DomainMatrix
                      (DomainInt [RangeBounded 1 size])
                      innerDomain
                  ) ]
        downD (name, DomainSequence "ExplicitBounded" (SequenceAttr sizeAttr _) innerDomain) = do
            maxSize <- getMaxSize sizeAttr
            return $ Just
                [ ( nameMarker name
                  , DomainInt [RangeBounded 0 maxSize]
                  )
                , ( nameValues name
                  , DomainMatrix
                      (DomainInt [RangeBounded 1 maxSize])
                      innerDomain
                  ) ]
        downD _ = na "{downD} ExplicitBounded"

        structuralCons :: TypeOf_Structural m
        structuralCons f downX1 (DomainSequence "ExplicitBounded" (SequenceAttr (SizeAttr_Size size) _) innerDomain) = do
            let
                innerStructuralCons values = do
                    (iPat, i) <- quantifiedVar
                    let activeZone b = [essence| forAll &iPat : int(1..&size) . &b |]

                    -- preparing structural constraints for the inner guys
                    innerStructuralConsGen <- f innerDomain

                    let inLoop = [essence| &values[&i] |]
                    outs <- innerStructuralConsGen inLoop
                    return (map activeZone outs)

            return $ \ sequ -> do
                refs <- downX1 sequ
                case refs of
                    [_marker,values] -> do
                        isc <- innerStructuralCons values
                        return $ concat [ isc
                                        ]
                    _ -> na "{structuralCons} ExplicitBounded"
        structuralCons f downX1 (DomainSequence "ExplicitBounded" (SequenceAttr sizeAttr _) innerDomain) = do
            maxSize <- getMaxSize sizeAttr
            let
                dontCareAfterMarker marker values = do
                    (iPat, i) <- quantifiedVar
                    return $ return $ -- list
                        [essence|
                            forAll &iPat : int(1..&maxSize) . &i > &marker ->
                                dontCare(&values[&i])
                        |]

                innerStructuralCons marker values = do
                    (iPat, i) <- quantifiedVar
                    let activeZone b = [essence| forAll &iPat : int(1..&maxSize) . &i <= &marker -> &b |]

                    -- preparing structural constraints for the inner guys
                    innerStructuralConsGen <- f innerDomain

                    let inLoop = [essence| &values[&i] |]
                    outs <- innerStructuralConsGen inLoop
                    return (map activeZone outs)

            return $ \ sequ -> do
                refs <- downX1 sequ
                case refs of
                    [marker,values] ->
                        concat <$> sequence
                            [ dontCareAfterMarker marker values
                            , return (mkSizeCons sizeAttr marker)
                            , innerStructuralCons marker values
                            ]
                    _ -> na "{structuralCons} ExplicitBounded"

        structuralCons _ _ _ = na "{structuralCons} ExplicitBounded"

        downC :: TypeOf_DownC m
        downC ( name
              , DomainSequence _ (SequenceAttr (SizeAttr_Size size) _) innerDomain
              , ConstantAbstract (AbsLitSequence constants)
              ) =
            return $ Just
                [ ( nameMarker name
                  , DomainInt [RangeBounded size size]
                  , ConstantInt (genericLength constants)
                  )
                , ( nameValues name
                  , DomainMatrix (DomainInt [RangeBounded 1 size]) innerDomain
                  , ConstantAbstract $ AbsLitMatrix (DomainInt [RangeBounded 1 size]) constants
                  )
                ]
        downC ( name
              , domain@(DomainSequence _ (SequenceAttr sizeAttr _) innerDomain)
              , ConstantAbstract (AbsLitSequence constants)
              ) = do
            maxSize <- getMaxSize sizeAttr
            let indexDomain i = mkDomainIntB (fromInt i) maxSize
            maxSizeInt <-
                case maxSize of
                    ConstantInt x -> return x
                    _ -> fail $ vcat
                            [ "Expecting an integer for the maxSize attribute."
                            , "But got:" <+> pretty maxSize
                            , "When working on:" <+> pretty name
                            , "With domain:" <+> pretty domain
                            ]
            z <- zeroVal innerDomain
            let zeroes = replicate (fromInteger (maxSizeInt - genericLength constants)) z
            return $ Just
                [ ( nameMarker name
                  , defRepr (indexDomain 0)
                  , ConstantInt (genericLength constants)
                  )
                , ( nameValues name
                  , DomainMatrix (indexDomain 1) innerDomain
                  , ConstantAbstract $ AbsLitMatrix (indexDomain 1) (constants ++ zeroes)
                  )
                ]
        downC _ = na "{downC} ExplicitBounded"

        up :: TypeOf_Up m
        up ctxt (name, domain) =
            case (lookup (nameMarker name) ctxt, lookup (nameValues name) ctxt) of
                (Just marker, Just constantMatrix) ->
                    case marker of
                        ConstantInt card ->
                            case constantMatrix of
                                ConstantAbstract (AbsLitMatrix _ vals) ->
                                    return (name, ConstantAbstract (AbsLitSequence (genericTake card vals)))
                                _ -> fail $ vcat
                                        [ "Expecting a matrix literal for:" <+> pretty (nameValues name)
                                        , "But got:" <+> pretty constantMatrix
                                        , "When working on:" <+> pretty name
                                        , "With domain:" <+> pretty domain
                                        ]
                        _ -> fail $ vcat
                                [ "Expecting an integer literal for:" <+> pretty (nameMarker name)
                                , "But got:" <+> pretty marker
                                , "When working on:" <+> pretty name
                                , "With domain:" <+> pretty domain
                                ]
                (Nothing, _) -> fail $ vcat $
                    [ "No value for:" <+> pretty (nameMarker name)
                    , "When working on:" <+> pretty name
                    , "With domain:" <+> pretty domain
                    ] ++
                    ("Bindings in context:" : prettyContext ctxt)
                (_, Nothing) -> fail $ vcat $
                    [ "No value for:" <+> pretty (nameValues name)
                    , "When working on:" <+> pretty name
                    , "With domain:" <+> pretty domain
                    ] ++
                    ("Bindings in context:" : prettyContext ctxt)

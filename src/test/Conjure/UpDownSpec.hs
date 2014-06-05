{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}

module Conjure.UpDownSpec ( spec ) where

-- conjure
import Language.E.Imports
import Language.E.Definition hiding ( Spec )
import Conjure.UpDown ( downDomain, downConstant, upConstant, UpDownError(..) )

-- hspec
import Test.Hspec ( Spec, describe, it, shouldBe )

-- QuickCheck
import Test.QuickCheck ( property, (==>), NonNegative(..) )


spec :: Spec
spec = do

    describe "enum" $ do

        let enumValues = ["apple", "orange", "peach", "melon"]
        let enumDomainDefn = DomainDefnEnum "fruits" enumValues
        let enumDomain = DomainEnum enumDomainDefn []
        let intDomain = DomainInt [RangeBounded (ConstantInt 1) (ConstantInt 4)]

        it "can convert enum domains into int domains" $ do
            downDomain NoRepresentation enumDomain `shouldBe` Right [intDomain]

        it "can convert enum values into int values" $ do
            let tDown a b = downConstant NoRepresentation enumDomain a `shouldBe` b
            tDown (ConstantEnum enumDomainDefn "apple") (Right [ConstantInt 1])
            tDown (ConstantEnum enumDomainDefn "peach") (Right [ConstantInt 3])
            tDown (ConstantEnum enumDomainDefn "plum" ) (Left (ConstantDownError "[Conjure.UpDown.upDownEnum] This identifier isn't a member of the enum: plum"))

        it "can reconstruct enum values from int values" $ do
            let tUp a b = upConstant NoRepresentation enumDomain a `shouldBe` b
            tUp [ConstantInt 1] (Right (ConstantEnum enumDomainDefn "apple"))
            tUp [ConstantInt 3] (Right (ConstantEnum enumDomainDefn "peach"))
            tUp [ConstantInt 0] (Left (ConstantUpError "[Conjure.UpDown.upDownEnum] Integer constant out of range for enum: 0"))

        it "enum down&up with quickcheck" $ property $
            let downAndUp = downConstant NoRepresentation enumDomain >=>
                            upConstant   NoRepresentation enumDomain
            in  \ (NonNegative i) -> i < length enumValues ==>
                    let e = ConstantEnum enumDomainDefn (enumValues !! i)
                    in  downAndUp e `shouldBe` Right e

    describe "Set Explicit" $ do

        it "Set Explicit (downDomain)" $
            let
                sizeAttr = DANameValue "size" (ConstantInt 4)
                indexDomain = DomainInt [RangeBounded (ConstantInt 1) (ConstantInt 4)]
                innerDomain = DomainInt [RangeBounded (ConstantInt 1) (ConstantInt 9)]
                setDomain = DomainSet (DomainAttributes [sizeAttr]) innerDomain
                matrixDomain = DomainMatrix indexDomain innerDomain
            in
                downDomain (Representation "Explicit") setDomain `shouldBe` Right [matrixDomain]

        it "Set Explicit (downConstant)" $
            let
                sizeAttr = DANameValue "size" (ConstantInt 4)
                indexDomain = DomainInt [RangeBounded (ConstantInt 1) (ConstantInt 4)]
                innerDomain = DomainInt [RangeBounded (ConstantInt 1) (ConstantInt 9)]
                setDomain = DomainSet (DomainAttributes [sizeAttr]) innerDomain
                setConstant = ConstantSet [ConstantInt 1, ConstantInt 3, ConstantInt 5]
                matrixConstant = ConstantMatrix indexDomain [ConstantInt 1, ConstantInt 3, ConstantInt 5]
            in
                downConstant (Representation "Explicit") setDomain setConstant `shouldBe` Right [matrixConstant]

        it "Set Explicit (upConstant)" $
            let
                sizeAttr = DANameValue "size" (ConstantInt 4)
                indexDomain = DomainInt [RangeBounded (ConstantInt 1) (ConstantInt 4)]
                innerDomain = DomainInt [RangeBounded (ConstantInt 1) (ConstantInt 9)]
                setDomain = DomainSet (DomainAttributes [sizeAttr]) innerDomain
                setConstant = ConstantSet [ConstantInt 1, ConstantInt 3, ConstantInt 5]
                matrixConstant = ConstantMatrix indexDomain [ConstantInt 1, ConstantInt 3, ConstantInt 5]
            in
                upConstant (Representation "Explicit") setDomain [matrixConstant] `shouldBe` Right setConstant

        it "Set Explicit (downAndUp)" $
            let
                sizeAttr = DANameValue "size" (ConstantInt 4)
                innerDomain = DomainInt [RangeBounded (ConstantInt 1) (ConstantInt 9)]
                setDomain = DomainSet (DomainAttributes [sizeAttr]) innerDomain
                setConstant = ConstantSet [ConstantInt 1, ConstantInt 3, ConstantInt 5]

                downAndUp = downConstant (Representation "Explicit") setDomain >=>
                            upConstant   (Representation "Explicit") setDomain

            in
                downAndUp setConstant `shouldBe` Right setConstant

    describe "regression 1" $ do

        it "regression 1 (downDomain)" $ do
            downDomain
                (Representation "Explicit")
                (DomainSet (DomainAttributes [DANameValue (Name "size") (ConstantInt 1)])
                    (DomainTuple
                        [ DomainBool
                        , DomainInt [RangeBounded (ConstantInt 95) (ConstantInt 171)]
                        , DomainInt [RangeBounded (ConstantInt 33) (ConstantInt 85)]])
                )
                `shouldBe` Right [ DomainMatrix (DomainInt [RangeBounded (ConstantInt 1) (ConstantInt 1)]) 
                                    (DomainTuple
                                        [ DomainBool
                                        , DomainInt [RangeBounded (ConstantInt 95) (ConstantInt 171)]
                                        , DomainInt [RangeBounded (ConstantInt 33) (ConstantInt 85)]])
                                 ]

        it "regression 1 (downConstant)" $ do
            downConstant
                (Representation "Explicit")
                (DomainSet (DomainAttributes [DANameValue (Name "size") (ConstantInt 1)])
                    (DomainTuple
                        [ DomainBool
                        , DomainInt [RangeBounded (ConstantInt 95) (ConstantInt 171)]
                        , DomainInt [RangeBounded (ConstantInt 33) (ConstantInt 85)]])
                )
                (ConstantSet [ConstantTuple [ConstantBool False,ConstantInt 118,ConstantInt 79]])
                `shouldBe` Right [ ConstantMatrix (DomainInt [RangeBounded (ConstantInt 1) (ConstantInt 1)])
                                    [ConstantTuple [ConstantBool False,ConstantInt 118,ConstantInt 79]]
                                 ]

        it "regression 1 (upConstant)" $ do
            upConstant
                (Representation "Explicit")
                (DomainSet (DomainAttributes [DANameValue (Name "size") (ConstantInt 1)])
                    (DomainTuple
                        [ DomainBool
                        , DomainInt [RangeBounded (ConstantInt 95) (ConstantInt 171)]
                        , DomainInt [RangeBounded (ConstantInt 33) (ConstantInt 85)]])
                )
                [ ConstantMatrix (DomainInt [RangeBounded (ConstantInt 1) (ConstantInt 1)])
                    [ConstantTuple [ConstantBool False,ConstantInt 118,ConstantInt 79]]
                ]
                `shouldBe` Right (ConstantSet [ConstantTuple [ConstantBool False,ConstantInt 118,ConstantInt 79]])

    describe "matrix of bool" $ do

        let domainMatrixOfBool =
                DomainMatrix
                    (DomainInt [RangeBounded (ConstantInt 1) (ConstantInt 4)])
                    DomainBool

        let constantMatrixOfBool =
                ConstantMatrix
                    (DomainInt [RangeBounded (ConstantInt 1) (ConstantInt 4)])
                    [ConstantBool False, ConstantBool False, ConstantBool True, ConstantBool True]

        it "downDomain" $ do
            downDomain
                NoRepresentation
                domainMatrixOfBool
                `shouldBe` Right [domainMatrixOfBool]

        it "downConstant" $ do
            downConstant
                NoRepresentation
                domainMatrixOfBool
                constantMatrixOfBool
                `shouldBe` Right [constantMatrixOfBool]

        it "upConstant" $ do
            upConstant
                NoRepresentation
                domainMatrixOfBool
                [constantMatrixOfBool]
                `shouldBe` Right constantMatrixOfBool

    describe "matrix of Set Explicit" $ do

        let domainMatrixOfSet =
                DomainMatrix
                    (DomainInt [RangeBounded (ConstantInt 1) (ConstantInt 2)])
                    (DomainSet
                        (DomainAttributes [DANameValue "size" (ConstantInt 3)])
                        (DomainInt [RangeBounded (ConstantInt 1) (ConstantInt 9)]))

        let constantMatrixOfSet =
                ConstantMatrix
                    (DomainInt [RangeBounded (ConstantInt 1) (ConstantInt 2)])
                    [ ConstantSet [ConstantInt 1, ConstantInt 3, ConstantInt 4]
                    , ConstantSet [ConstantInt 1, ConstantInt 3, ConstantInt 5]
                    ]

        it "downDomain" $ do
            downDomain
                NoRepresentation
                domainMatrixOfSet
                `shouldBe` Right [domainMatrixOfSet]

        it "downConstant" $ do
            downConstant
                NoRepresentation
                domainMatrixOfSet
                constantMatrixOfSet
                `shouldBe` Right [constantMatrixOfSet]

        it "upConstant" $ do
            upConstant
                NoRepresentation
                domainMatrixOfSet
                [constantMatrixOfSet]
                `shouldBe` Right constantMatrixOfSet

    describe "set of set of int -- Explicit [Explicit [∅]]" $ do

        let domainSetOfSet =
                DomainSet
                    (DomainAttributes [DANameValue "size" (ConstantInt 2)])
                    (DomainSet
                        (DomainAttributes [DANameValue "size" (ConstantInt 1)])
                        DomainBool)

        let domainMatrixOfSet =
                DomainMatrix
                    (DomainInt [RangeBounded (ConstantInt 1) (ConstantInt 2)])
                    (DomainSet
                        (DomainAttributes [DANameValue "size" (ConstantInt 1)])
                        DomainBool)

        let constantSetOfSet =
                ConstantSet
                    [ ConstantSet [ConstantBool False]
                    , ConstantSet [ConstantBool True]
                    ]

        let constantMatrixOfSet =
                ConstantMatrix
                    (DomainInt [RangeBounded (ConstantInt 1) (ConstantInt 2)])
                    [ ConstantSet [ConstantBool False]
                    , ConstantSet [ConstantBool True]
                    ]

        it "downDomain" $ do
            downDomain
                (Representation "Explicit")
                domainSetOfSet
                `shouldBe` Right [domainMatrixOfSet]

        it "downConstant" $ do
            downConstant
                (Representation "Explicit")
                domainSetOfSet
                constantSetOfSet
                `shouldBe` Right [constantMatrixOfSet]

        it "upConstant" $ do
            upConstant
                (Representation "Explicit")
                domainSetOfSet
                [constantMatrixOfSet]
                `shouldBe` Right constantSetOfSet


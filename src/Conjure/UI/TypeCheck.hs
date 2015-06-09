{-# LANGUAGE TupleSections #-}
{-# LANGUAGE LambdaCase #-}

module Conjure.UI.TypeCheck ( typeCheckModel_StandAlone, typeCheckModel ) where

-- conjure
import Conjure.Prelude
import Conjure.UserError
import Conjure.Language.Definition
import Conjure.Language.Type
import Conjure.Language.TypeOf
import Conjure.Language.Pretty
import Conjure.Language.Lenses
import Conjure.Process.Enums ( removeEnumsFromModel )
import Conjure.Process.Unnameds ( removeUnnamedsFromModel )
import Conjure.Language.NameResolution ( resolveNames )
import Conjure.Process.Sanity ( sanityChecks )



typeCheckModel_StandAlone
    :: ( MonadFail m
       , MonadUserError m
       , MonadLog m
       , NameGen m
       )
    => Model
    -> m Model
typeCheckModel_StandAlone model0 = do
    model1 <- return model0             >>= logDebugId "[input]"
          >>= removeUnnamedsFromModel   >>= logDebugId "[removeUnnamedsFromModel]"
          >>= removeEnumsFromModel      >>= logDebugId "[removeEnumsFromModel]"
          >>= resolveNames              >>= logDebugId "[resolveNames]"
          >>= sanityChecks              >>= logDebugId "[sanityChecks]"
          >>= typeCheckModel            >>= logDebugId "[typeCheckModel]"
    return model1


typeCheckModel
    :: ( MonadFail m
       , MonadUserError m
       , MonadLog m
       , NameGen m
       )
    => Model
    -> m Model
typeCheckModel model1 = do
    let model2 = fixRelationProj model1
    errs <- execWriterT $ forM (mStatements model2) $ \ st ->
        case st of
            Declaration{} -> return ()
            SearchOrder xs -> forM_ xs $ \case
                BranchingOn{} -> return ()                      -- TODO: check if the name is defined
                Cut x -> do
                    mty <- runExceptT $ typeOf x
                    case mty of
                        Right TypeBool{} -> return ()
                        Left err -> tell $ return $ vcat
                            [ "In a 'branching on' statement:" <++> pretty x
                            , "Error:" <++> pretty err
                            ]
                        Right ty -> tell $ return $ vcat
                            [ "In a 'branching on' statement:" <++> pretty x
                            , "Expected type `bool`, but got:" <++> pretty ty
                            ]
            Where xs -> forM_ xs $ \ x -> do
                mty <- runExceptT $ typeOf x
                case mty of
                    Right TypeBool{} -> return ()
                    Left err -> tell $ return $ vcat
                        [ "In a 'where' statement:" <++> pretty x
                        , "Error:" <++> pretty err
                        ]
                    Right ty -> tell $ return $ vcat
                        [ "In a 'where' statement:" <++> pretty x
                        , "Expected type `bool`, but got:" <++> pretty ty
                        ]
            Objective _ x -> do
                mty <- runExceptT $ typeOf x
                case mty of
                    Right TypeInt{} -> return ()
                    Left err -> tell $ return $ vcat
                        [ "In the objective:" <++> pretty st
                        , "Error:" <++> pretty err
                        ]
                    Right ty -> tell $ return $ vcat
                        [ "In the objective:" <++> pretty st
                        , "Expected type `int`, but got:" <++> pretty ty
                        ]
            SuchThat xs -> forM_ xs $ \ x -> do
                mty <- runExceptT $ typeOf x
                case mty of
                    Right TypeBool{} -> return ()
                    Left err -> tell $ return $ vcat
                        [ "In a 'such that' statement:" <++> pretty x
                        , "Error:" <++> pretty err
                        ]
                    Right ty -> tell $ return $ vcat
                        [ "In a 'such that' statement:" <++> pretty x
                        , "Expected type `bool`, but got:" <++> pretty ty
                        ]
    unless (null errs) (userErr errs)

    return model2


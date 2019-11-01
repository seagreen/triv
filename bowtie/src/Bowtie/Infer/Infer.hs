-- | Based on <doc.md#HeerenHagePaper>
module Bowtie.Infer.Infer where

import Bowtie.Infer.Assumptions
import Bowtie.Infer.BottomUp
import Bowtie.Infer.Constraints
import Bowtie.Infer.Solve
import Bowtie.Infer.Substitution
import Bowtie.Lib.Environment
import Bowtie.Lib.Id
import Bowtie.Lib.Prelude
import Bowtie.Surface.AST
import Control.Monad.Except
import Control.Monad.State.Class
import Control.Monad.Trans.State

import qualified Bowtie.Infer.Assumptions as Assumptions
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Set as Set

data TypeError
  = SolveError SolveError
  | AssumptionsRemain [(Id, Set Type)]
  deriving (Eq, Show)

newtype Infer a
  = Infer (StateT Int (Either TypeError) a)
  deriving newtype (Functor, Applicative, Monad, MonadError TypeError, MonadState Int)

runInfer :: Infer a -> Either TypeError a
runInfer (Infer g) =
  evalStateT g 0

inferType
  :: (MonadState Int m, MonadError TypeError m)
  => Environment
  -> Expr
  -> m (Substitution, Type)
inferType env expr = do
  (constraints, typ) <- gatherConstraints env expr
  s <- mapError SolveError (solve constraints)
  -- Heeren paper doesn't do the substType here:
  pure (s, substType s typ)

gatherConstraints
  :: (MonadState Int m, MonadError TypeError m)
  => Environment
  -> Expr
  -> m (Constraints, Type)
gatherConstraints env expr = do
  (a, c, t) <- bottomUp env mempty expr

  -- if dom A not a subset of domain env then undefined variables exist
  let
    Assumptions aX = a
  _ <- case HashMap.toList (HashMap.difference aX (unEnvironment env)) of
         [] -> pure ()
         ks -> throwError (AssumptionsRemain ks)

  pure (c <> explicitConstraintOnSet env a, t)

-- | Heeren Section 4.5
explicitConstraintOnSet :: Environment -> Assumptions -> Constraints
explicitConstraintOnSet env a =
  Constraints (Set.fromList f)
  where
    f :: [Constraint]
    f = do
      (id, typ) <- Assumptions.toList a
      (id2, ts) <- environmentToList env
      guard (id == id2)
      pure (ExplicitInstanceConstraint typ ts)
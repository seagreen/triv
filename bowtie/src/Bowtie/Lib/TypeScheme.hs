module Bowtie.Lib.TypeScheme where

import Bowtie.Lib.FreeVars
import Bowtie.Lib.Prelude
import Bowtie.Surface.AST
import qualified Data.Set as Set

-- | Quantitied over the variables in @Set Id@.
data TypeScheme
  = TypeScheme
      (Set Id)
      Type
  deriving (Eq, Ord, Show)

instance FreeVars TypeScheme where
  freeVars :: TypeScheme -> Set Id
  freeVars (TypeScheme polyVars typ) =
    Set.difference (freeVars typ) polyVars

module Bowtie.Surface.Desugar
  ( dsg
  , desugarResult
  , desugarLet'
  ) where

import Bowtie.Lib.FreeVars
import Bowtie.Lib.Id
import Bowtie.Lib.OrderedMap (OrderedMap)
import Bowtie.Lib.Prelude hiding (all, rem)
import Bowtie.Surface.AST

import qualified Bowtie.Core.Expr as Core
import qualified Bowtie.Lib.Builtin as Builtin
import qualified Bowtie.Lib.OrderedMap as OrderedMap
import qualified Data.Graph as Graph
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Set as Set
import qualified Data.Text as Text

desugarResult :: OrderedMap Id (Expr, Type) -> Expr
desugarResult decls =
  case OrderedMap.lookup (Id "result") decls of
    Nothing ->
      panic "result id not found"

    Just (resultExpr, _typ) ->
      let
        withoutRes :: OrderedMap Id (Expr, Type)
        withoutRes =
          OrderedMap.delete (Id "result") decls
      in
        Let withoutRes resultExpr

dsg :: Expr -> Core.Expr
dsg topExpr =
  case topExpr of
    Var i ->
      Core.Var i

    Lam id mType e ->
      case mType of
        Nothing ->
          panic "dsg type is Nothing"

        Just typ ->
          Core.Lam id typ (dsg e)

    App e1 e2 ->
      Core.App (dsg e1) (dsg e2)

    Let decls e ->
      desugarLet decls e

    Construct tag ->
      Core.Construct tag

    Case e matches ->
      let
        f :: Alt -> Core.Alt
        f (Alt i i2 expr) =
          Core.Alt i i2 (dsg expr)
      in
        Core.Case (dsg e) (fmap f matches)

    EInt n ->
      Core.EInt n

    EText t ->
      desugarText t

-- | See 'showIntBuiltin' for a similar function.
--
-- I tried to factor out the common logic into:
--
-- @Builtin.text :: forall expr. (expr -> expr -> expr) -> (Id -> expr) -> [expr] -> expr@
--
-- But the way untyped constructors are defined as @Construct Id [Expr]@
-- instead of @Construct Id@ made this difficult (and I'm not sure it was worth it anyway).
desugarText :: Text -> Core.Expr
desugarText =
  Core.App (Core.Construct Builtin.unicode) . toList'
  where
    toList' :: Text -> Core.Expr
    toList' =
      Text.foldr consCodepoint (Core.Construct Builtin.nil)

    consCodepoint :: Char -> Core.Expr -> Core.Expr
    consCodepoint c expr =
      let
        consCodePoint :: Core.Expr
        consCodePoint =
          Core.App
            (Core.Construct Builtin.cons)
            (Core.EInt (fromIntegral (charToCodepoint c)))
      in
        Core.App consCodePoint expr

-- This one is used by both inferece and desugaring to core
desugarLet' :: OrderedMap Id (Expr, Type) -> [(Id, (Expr, Type))]
desugarLet' decls =
  foldr f mempty components
  where
    components :: [Graph.SCC ((Expr, Type), Id, [Id])]
    components =
      Graph.stronglyConnCompR (fmap g (OrderedMap.toList decls))
      where
        g :: (Id, (Expr, Type)) -> ((Expr, Type), Id, [Id])
        g (id, (expr, typ)) =
          ((expr, typ), id, Set.toList (freeVars expr))

    f :: Graph.SCC ((Expr, Type), Id, ids) -> [(Id, (Expr, Type))] -> [(Id, (Expr, Type))]
    f grph acc =
      case grph of
        Graph.AcyclicSCC (expr, id, _) ->
          (id, expr) : acc

        Graph.CyclicSCC [(expr, id, _)] ->
          -- Was
          --
          --   panic "cyclic"
          --
          -- I believe this needs to be let through though so that
          -- functions can refer to themselves.
          (id, expr) : acc

        _ ->
          panic "desugarLet'"

-- This one isn't used for inference, but just going to core
desugarLet :: OrderedMap Id (Expr, Type) -> Expr -> Core.Expr
desugarLet decls e =
  foldr
    (\(i, (e2, typ)) acc ->
      let
        e3 :: Core.Expr
        e3 =
          -- Intercept builtins, and replace their current
          -- definition (panic) with something else.
          --
          -- By doing this here we replace their definitions in the
          -- source code with a new value.
          -- The old way of doing it was to case on id in the Lam
          -- case of dsg, which replaced the call sites instead of
          -- the function definitions.
          case i of
            Id "compare" ->
              let
                a = Id "a"
                b = Id "b"
                aType = TVariable (Id "a")
              in
                Core.Lam
                  a
                  aType
                  (Core.Lam
                    b
                    aType
                    (Core.EOp
                      (Core.Compare
                        (Core.Var a)
                        (Core.Var b))))

            Id "plus" ->
              let
                a = Id "a"
                b = Id "b"
                iType = TConstructor Builtin.int
              in
                Core.Lam
                  a
                  iType
                  (Core.Lam
                    b
                    iType
                    (Core.EOp
                      (Core.Plus
                        (Core.Var a)
                        (Core.Var b))))

            Id "multiply" ->
              let
                a = Id "a"
                b = Id "b"
                iType = TConstructor Builtin.int
              in
                Core.Lam
                  a
                  iType
                  (Core.Lam
                    b
                    iType
                    (Core.EOp
                      (Core.Multiply
                        (Core.Var a)
                        (Core.Var b))))

            Id "showInt" ->
              let
                a = Id "a"
                arrTyp = TArrow (TConstructor Builtin.int) (TConstructor Builtin.text)
              in
                Core.Lam
                  a
                  arrTyp
                  (Core.EOp
                    (Core.ShowInt
                      (Core.Var a)))

            Id "panic" ->
              let
                a = Id "a"
                textType = TConstructor Builtin.text
              in
                Core.Lam
                  a
                  textType
                  (Core.EOp
                    (Core.Panic
                      (Core.Var a)))

            _ ->
              dsg e2
      in
        Core.Let (HashMap.singleton i (e3, typ)) acc)
    (dsg e)
    (desugarLet' decls)
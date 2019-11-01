module Bowtie.JS.Imperativize where

import Bowtie.JS.AST
import Bowtie.Lib.Environment
import Bowtie.Lib.Id
import Bowtie.Lib.OrderedMap (OrderedMap)
import Bowtie.Lib.Prelude
import Bowtie.Lib.TypeScheme
import Bowtie.Type.AST (Type(..))

import qualified Bowtie.Core.Expr as Core
import qualified Bowtie.JS.AST as JS
import qualified Bowtie.Lib.OrderedMap as OrderedMap
import qualified Data.HashMap.Strict as HashMap
import qualified Data.List as List

makeImp :: Environment -> Core.Expr -> JS.AST
makeImp (Environment env) expr =
  Block (conFuncs <> bindings <> [result]) -- PERFORMANCE
  where
    conFuncs :: [JS.AST]
    conFuncs =
      fmap conTypeToFunction (List.sortOn fst (HashMap.toList env))

    (coreBindings, coreExpr) = packageUp expr

    bindings = fmap assign (OrderedMap.toList coreBindings)

    assign (id, e) =
      Assignment (Var (unId id)) (coreToImp e)

    result = assign (Id "result", coreExpr)

coreToImp :: Core.Expr -> JS.AST
coreToImp topExpr =
  case topExpr of
    Core.Var id ->
      Var (unId id)

    Core.Lam id _typ expr ->
      Lam (unId id) ((coreToImp expr))

    Core.App e1 e2 ->
      App (coreToImp e1) (coreToImp e2)

    Core.Let bindings body ->
      let
        f :: (Id, (Core.Expr, typ)) -> AST
        f (id, (expr, _)) =
          Assignment (Var (unId id)) (coreToImp expr)
      in
        Block
          (  fmap f (List.sortOn fst (HashMap.toList bindings))
          <> [coreToImp body] -- PERFORMANCE
          )

    Core.Construct id ->
      Var (unId id)

    Core.Case expr alts ->
      Case (coreToImp expr) (fmap altToImp alts)

    Core.EInt n ->
      JSInt n

    Core.EOp op ->
      JSOp (coreOperationToImp op)

altToImp :: Core.Alt -> Alt
altToImp (Core.Alt id bindings body) =
  Alt (unId id) (fmap unId bindings) (coreToImp body)

coreOperationToImp :: Core.Operation -> JS.Operation
coreOperationToImp op =
  case op of
    Core.Compare e1 e2 ->
      Compare (coreToImp e1) (coreToImp e2)

    Core.Plus e1 e2 ->
      Plus (coreToImp e1) (coreToImp e2)

    Core.Multiply e1 e2 ->
      Multiply (coreToImp e1) (coreToImp e2)

    Core.ShowInt expr ->
      ShowInt (coreToImp expr)

    Core.Panic expr ->
      Panic (coreToImp expr)

conTypeToFunction :: (Id, TypeScheme) -> JS.AST
conTypeToFunction (id, TypeScheme _ tsType) =
  Assignment (Var (unId id)) (addLambdas xs (Array (JSString (unId id) : fmap Var xs)))
  where
    addLambdas :: [Text] -> JS.AST -> JS.AST
    addLambdas [] ast = ast
    addLambdas (y:ys) ast = Lam y (addLambdas ys ast)

    xs :: [Text]
    xs =
      f 1 tsType

    f :: Natural -> Type -> [Text]
    f n typ =
      case typ of
        TVariable _ ->
          panic ("construct unexpected type" <> show typ)

        TConstructor _ ->
          []

        TArrow _ t2 ->
          "arg" <> show n : f (n + 1) t2

        TypeApp _ _ -> -- eg List a
          []

-- | I initially though packageUp's purpose would be to make sure
-- it's being passed a full program, which should be a Let,
-- and it would return Nothing otherwise.
--
-- Then I realized that even full programs can be non-Lets,
-- because if the whole program is:
--
-- result : Int -> Int
-- result =
--   (\n. n)
--
-- then it desugars to
--
-- Lambda n (Id n)
--
-- with no Let in sight (basically any program that has a single "result"
-- definition doesn't have to be a Let).
packageUp :: Core.Expr -> (OrderedMap Id Core.Expr, Core.Expr)
packageUp expr =
  case expr of
    Core.Let bindings body ->
      case OrderedMap.fromList (HashMap.toList (fmap fst bindings)) of
        Left _ ->
          panic "shouldn't happen"

        Right oBindings ->
          let (more, finalBody) = packageUp body
          in case OrderedMap.append oBindings more of
            Left _ ->
              panic "also shouldn't happen"

            Right res ->
              (res, finalBody)

    _ ->
      (OrderedMap.empty, expr)

module Bowtie.JS.Imperativize
  ( makeImp,
  )
where

import qualified Bowtie.Core.Expr as Core
import Bowtie.JS.AST
import qualified Bowtie.JS.AST as JS
import Bowtie.Lib.Environment
import Bowtie.Lib.OrderedMap (OrderedMap)
import qualified Bowtie.Lib.OrderedMap as OrderedMap
import Bowtie.Lib.Prelude
import Bowtie.Lib.TypeScheme
import Bowtie.Type.AST (Type (..))
import qualified Data.HashMap.Strict as HashMap

makeImp :: Environment -> Core.Expr -> JS.AST
makeImp (Environment env) expr =
  Block (conFuncs <> bindings <> [result]) -- PERFORMANCE
  where
    conFuncs :: [JS.AST]
    conFuncs =
      fmap conTypeToFunction (hashmapToSortedList env)
    (coreBindings, coreExpr) = packageUp expr
    bindings = fmap assign (OrderedMap.toList coreBindings)
    assign (id, e) =
      Assignment (Var id) (coreToImp e)
    result = assign (Id "result", coreExpr)

coreToImp :: Core.Expr -> JS.AST
coreToImp topExpr =
  case topExpr of
    Core.Var id ->
      Var id
    Core.Lam id _typ expr ->
      Lam id ((coreToImp expr))
    Core.App e1 e2 ->
      App (coreToImp e1) (coreToImp e2)
    Core.Let bindings body ->
      let f :: (Id, (Core.Expr, typ)) -> AST
          f (id, (expr, _)) =
            Assignment (Var id) (coreToImp expr)
       in LambdaUnit
            ( Block
                ( addReturn
                    ( fmap f (hashmapToSortedList bindings)
                        <> [coreToImp body] -- PERFORMANCE
                    )
                )
            )
    Core.Construct id ->
      Var id
    Core.Case expr alts ->
      let mkAssign :: (Natural, Id) -> AST
          mkAssign (n, id) =
            Assignment (Var id) (IndexArray (Var (Id "$1")) n)
          altToImp :: Core.Alt -> AST
          altToImp (Core.Alt id args body) =
            IfThen
              ( Equal
                  (IndexArray (Var (Id "$1")) 0)
                  (conToString id)
              )
              ( Block $
                  addReturn
                    ( fmap mkAssign (zip [1 ..] args)
                        <> [coreToImp body] -- PERFORMANCE
                    )
              )
       in LambdaUnit
            ( Block
                ( Assignment (Var (Id "$1")) (coreToImp expr)
                    : fmap altToImp alts
                    <> [Else (Throw (JSString "no match"))]
                )
            )
    Core.PrimInt n ->
      JSInt n
    Core.PrimOp op ->
      coreOperationToImp op

coreOperationToImp :: Core.Operation -> JS.AST
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
      LambdaUnit (Throw (coreToImp expr))

-- eg ["Maybe", 5], not [Maybe, 5]
conToString :: Id -> JS.AST
conToString =
  JSString . unId

conTypeToFunction :: (Id, TypeScheme) -> JS.AST
conTypeToFunction (id, TypeScheme _ tsType) =
  Assignment
    (Var id)
    (addLambdas args (Array (conToString id : fmap Var args)))
  where
    addLambdas :: [Id] -> JS.AST -> JS.AST
    addLambdas [] ast = ast
    addLambdas (y : ys) ast = Lam y (addLambdas ys ast)
    args :: [Id]
    args =
      f 1 tsType
    f :: Natural -> Type -> [Id]
    f n typ =
      case typ of
        TVariable _ ->
          panic ("construct unexpected type" <> show typ)
        TConstructor _ ->
          []
        TArrow _ t2 ->
          Id ("arg" <> show n) : f (n + 1) t2
        TypeApp _ _ ->
          -- eg List a
          []

addReturn :: [JS.AST] -> [JS.AST]
addReturn ys =
  case reverse ys of
    y : rest ->
      reverse rest <> [Return y] -- PERFORMANCE
    _ ->
      ys

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

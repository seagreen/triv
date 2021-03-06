{-# LANGUAGE QuasiQuotes #-}

module Main where

import qualified Bowtie.Example
import Bowtie.Interpret
import Bowtie.JS
import Bowtie.Lib.Prelude
import Data.String.QQ (s)
import qualified Data.Text.IO as TIO
import System.FilePath ((</>))
import Test.Hspec

main :: IO ()
main = do
  libFiles <- readDirectoryFiles "../example-lib"
  hspec do
    describe
      "well-typed-examples"
      (for_ Bowtie.Example.wellTyped runWellTyped)

    describe
      "applications"
      (testApps libFiles)

runWellTyped :: (FilePath, Text) -> Spec
runWellTyped (name, src) =
  it name do
    js <- case transpile src of
      Left e ->
        exitWithError (prettyError e)
      Right a ->
        pure (appendConsoleLog a)

    res <- runTextCommand "node" js
    let annotatedRes = res <> "\n\n/*\n" <> js <> "\n*/\n"
    TIO.writeFile ("test/well-typed-golden-files" </> name) annotatedRes

testApps :: HashMap FilePath Text -> Spec
testApps libFiles =
  it "lunar-lander" do
    appSource <- TIO.readFile "../example-app/lunar-lander.bowtie"
    js <- case sourcesToCore libFiles ("../example-app/lunar-lander.bowtie", appSource) of
      Left e ->
        exitWithError (prettyError e)
      Right (env, coreExpr) ->
        pure (transpileCore env coreExpr <> exerciseLunarLander)
    runTextCommand "node" js
      `shouldReturn` "[ 'Step',\n  [ 'Pictures', [ 'Cons', [Array], [Array] ] ],\n  [Function] ]\n"

exerciseLunarLander :: Text
exerciseLunarLander =
  [s|
const $res1 = _result[2](["Tick"])
const $res2 = $res1[2](["KeyDown", 119]) // TODO: this and the one below can be changed without failing the test
const $res3 = $res2[2](["KeyUp", 119])
console.log($res3);
|]

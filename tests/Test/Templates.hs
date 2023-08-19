{-# LANGUAGE OverloadedStrings #-}

module Test.Templates where

import Test.Common
import Test.Import

spec :: Spec
spec =
  describe "template API" $ do
    it "can create a template" $
      withTestEnv $ do
        let idxTpl = IndexTemplate [IndexPattern "tweet-*"] (Just (IndexSettings (ShardCount 1) (ReplicaCount 1) defaultIndexMappingsLimits)) (toJSON TweetMapping)
        resp <- performBHRequest $ putTemplate idxTpl (TemplateName "tweet-tpl")
        liftIO $ resp `shouldBe` Acknowledged True

    it "can detect if a template exists" $
      withTestEnv $ do
        exists <- performBHRequest $ templateExists (TemplateName "tweet-tpl")
        liftIO $ exists `shouldBe` True

    it "can delete a template" $
      withTestEnv $ do
        resp <- performBHRequest $ deleteTemplate (TemplateName "tweet-tpl")
        liftIO $ resp `shouldBe` Acknowledged True

    it "can detect if a template doesn't exist" $
      withTestEnv $ do
        exists <- performBHRequest $ templateExists (TemplateName "tweet-tpl")
        liftIO $ exists `shouldBe` False

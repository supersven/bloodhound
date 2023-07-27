{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
#if __GLASGOW_HASKELL__ >= 802
{-# LANGUAGE MonoLocalBinds #-}
#endif
module Main where

import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import qualified Test.Aggregation as Aggregation
import qualified Test.BulkAPI as Bulk
import Test.Common
import qualified Test.Count as Count
import qualified Test.Documents as Documents
import qualified Test.Highlights as Highlights
import Test.Import
import qualified Test.Indices as Indices
import qualified Test.JSON as JSON
import qualified Test.Query as Query
import qualified Test.Script as Script
import qualified Test.Snapshots as Snapshots
import qualified Test.Sorting as Sorting
import qualified Test.SourceFiltering as SourceFiltering
import qualified Test.Suggest as Suggest
import qualified Test.Templates as Templates
import Prelude

main :: IO ()
main = hspec $ do
  Aggregation.spec
  Bulk.spec
  Documents.spec
  Highlights.spec
  Indices.spec
  JSON.spec
  Query.spec
  Script.spec
  Snapshots.spec
  Sorting.spec
  SourceFiltering.spec
  Suggest.spec
  Templates.spec
  Count.spec

  describe "error parsing" $
    it "can parse EsErrors for >= 2.0" $
      withTestEnv $ do
        errorResp <- tryEsError $ verifySnapshotRepo (SnapshotRepoName "bogus")
        liftIO (errorResp `shouldBe` Left (EsError 404 "[bogus] missing"))

  describe "Monoid (SearchHits a)" $
    prop "abides the monoid laws" $
      eq $
        prop_Monoid (T :: T (SearchHits ()))

  describe "mkDocVersion" $
    prop "can never construct an out of range docVersion" $ \i ->
      let res = mkDocVersion i
       in case res of
            Nothing -> property True
            Just dv ->
              (dv >= minBound)
                .&&. (dv <= maxBound)
                .&&. docVersionNumber dv
                === i

  describe "getNodesInfo" $
    it "fetches the responding node when LocalNode is used" $
      withTestEnv $ do
        NodesInfo {..} <- getNodesInfo LocalNode
        -- This is really just a smoke test for response
        -- parsing. Node info is so variable, there's not much I can
        -- assert here.
        liftIO $ length nodesInfo `shouldBe` 1

  describe "getNodesStats" $
    it "fetches the responding node when LocalNode is used" $
      withTestEnv $ do
        NodesStats {..} <- getNodesStats LocalNode
        -- This is really just a smoke test for response
        -- parsing. Node stats is so variable, there's not much I can
        -- assert here.
        liftIO $ length nodesStats `shouldBe` 1

  describe "Enum DocVersion" $
    it "follows the laws of Enum, Bounded" $ do
      evaluate (succ maxBound :: DocVersion) `shouldThrow` anyErrorCall
      evaluate (pred minBound :: DocVersion) `shouldThrow` anyErrorCall
      evaluate (toEnum 0 :: DocVersion) `shouldThrow` anyErrorCall
      evaluate (toEnum 9200000000000000001 :: DocVersion) `shouldThrow` anyErrorCall
      enumFrom (pred maxBound :: DocVersion) `shouldBe` [pred maxBound, maxBound]
      enumFrom (pred maxBound :: DocVersion) `shouldBe` [pred maxBound, maxBound]
      enumFromThen minBound (pred maxBound :: DocVersion) `shouldBe` [minBound, pred maxBound]

  describe "Scan & Scroll API" $
    it "returns documents using the scan&scroll API" $
      withTestEnv $ do
        _ <- insertData
        _ <- insertOther
        let search =
              ( mkSearch
                  (Just $ MatchAllQuery Nothing)
                  Nothing
              )
                { size = Size 1
                }
        regular_search <- searchTweet search
        scan_search' <- scanSearch testIndex search :: BH IO [Hit Tweet]
        let scan_search = map hitSource scan_search'
        liftIO $
          regular_search `shouldBe` Right exampleTweet -- Check that the size restrtiction is being honored
        liftIO $
          scan_search `shouldMatchList` [Just exampleTweet, Just otherTweet]

  describe "Point in time (PIT) API" $ do
    it "returns a single document using the point in time (PIT) API" $
      withTestEnv $ do
        _ <- insertData
        _ <- insertOther
        let search =
              ( mkSearch
                  (Just $ MatchAllQuery Nothing)
                  Nothing
              )
                { size = Size 1
                }
        regular_search <- searchTweet search
        pit_search' <- pitSearch testIndex search :: BH IO [Hit Tweet]
        let pit_search = map hitSource pit_search'
        liftIO $
          regular_search `shouldBe` Right exampleTweet -- Check that the size restriction is being honored
        liftIO $
          pit_search `shouldMatchList` [Just exampleTweet] -- TODO
    it "returns many documents using the point in time (PIT) API" $
      withTestEnv $ do
        resetIndex
        let ids = [1 .. 1000]
        let docs = map exampleTweetWithAge ids
        let docIds = map (Text.pack . show) ids
        mapM_ (uncurry insertTweetWithDocId) (docs `zip` docIds)
        let sort = mkSort (FieldName "postDate") Ascending
        let search =
              ( mkSearch
                  (Just $ MatchAllQuery Nothing)
                  Nothing
              )
                { sortBody = Just [DefaultSortSpec sort]
                }
        scan_search' <- scanSearch testIndex search :: BH IO [Hit Tweet]
        let scan_search = map hitSource scan_search'
        pit_search' <- pitSearch testIndex search :: BH IO [Hit Tweet]
        let pit_search = map hitSource pit_search'
        let expectedHits = map Just docs
        liftIO $
          scan_search `shouldMatchList` expectedHits
        liftIO $
          pit_search `shouldMatchList` expectedHits
  describe "Search After API" $
    it "returns document for search after query" $
      withTestEnv $ do
        _ <- insertData
        _ <- insertOther
        let sortSpec = DefaultSortSpec $ mkSort (FieldName "user") Ascending
            searchAfterKey = [Aeson.toJSON ("bitemyapp" :: String)]
            search =
              Search
                { queryBody = Nothing,
                  filterBody = Nothing,
                  sortBody = Just [sortSpec],
                  aggBody = Nothing,
                  highlight = Nothing,
                  trackSortScores = False,
                  from = From 0,
                  size = Size 10,
                  searchType = SearchTypeDfsQueryThenFetch,
                  searchAfterKey = Just searchAfterKey,
                  fields = Nothing,
                  scriptFields = Nothing,
                  source = Nothing,
                  suggestBody = Nothing,
                  pointInTime = Nothing
                }
        result <- searchTweets search
        let myTweet = result >>= grabFirst
        liftIO $
          myTweet `shouldBe` Right otherTweet

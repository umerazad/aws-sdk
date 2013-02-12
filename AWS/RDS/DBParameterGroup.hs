{-# LANGUAGE FlexibleContexts #-}

module AWS.RDS.DBParameterGroup
    ( describeDBParameterGroups
    , createDBParameterGroup
    ) where

import Control.Applicative ((<$>), (<*>))
import Data.Conduit (GLSink, MonadBaseControl, MonadResource, MonadThrow)
import Data.Text (Text)
import Data.XML.Types (Event)

import AWS.Lib.Parser (getT, element)
import AWS.Lib.Query ((|=), (|=?))
import AWS.RDS.Internal (RDS, rdsQuery, elements)
import AWS.RDS.Types hiding (Event)
import AWS.Util (toText)

describeDBParameterGroups
    :: (MonadBaseControl IO m, MonadResource m)
    => Maybe Text -- ^ DBParameterGroupName
    -> Maybe Text -- ^ Marker
    -> Maybe Int -- ^ MaxRecords
    -> RDS m [DBParameterGroup]
describeDBParameterGroups name marker maxRecords =
    rdsQuery "DescribeDBParameterGroups" params $
        elements "DBParameterGroup" dbParameterGroupSink
  where
    params =
        [ "DBParameterGroupName" |=? name
        , "Marker" |=? marker
        , "MaxRecords" |=? toText <$> maxRecords
        ]

dbParameterGroupSink
    :: MonadThrow m
    => GLSink Event m DBParameterGroup
dbParameterGroupSink = DBParameterGroup
    <$> getT "DBParameterGroupFamily"
    <*> getT "Description"
    <*> getT "DBParameterGroupName"

createDBParameterGroup
    :: (MonadBaseControl IO m, MonadResource m)
    => Text -- ^ DBParameterGroupFamily
    -> Text -- ^ DBParameterGroupName
    -> Text -- ^ Description
    -> RDS m DBParameterGroup
createDBParameterGroup family name desc =
    rdsQuery "CreateDBParameterGroup" params $
        element "DBParameterGroup" dbParameterGroupSink
  where
    params =
        [ "DBParameterGroupFamily" |= family
        , "DBParameterGroupName" |= name
        , "Description" |= desc
        ]

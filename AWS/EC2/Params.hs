module AWS.EC2.Params where

import Control.Applicative
import Data.Text (Text)
import qualified Data.Text as T

import AWS.EC2.Query (QueryParam(..))
import AWS.EC2.Types
import AWS.Util

data BlockDeviceMappingParam
    = BlockDeviceMappingParamEBS
        { bdmpEbsDeviceName :: Text
        , bdmpEbsNoDevice :: Maybe Bool
        , bdmpEbsSource :: EbsSource
        , bdmpEbsDeleteOnTermination :: Maybe Bool
        , bdmpEbsVolumeType :: Maybe VolumeType
        }
    | BlockDeviceMappingParamInstanceStore
        { bdmpIsDeviceName :: Text
        , bdmpIsNoDevice :: Maybe Bool
        , bdmpIsVirtualName :: Maybe Text
        }
  deriving (Show)

blockDeviceMappingParams
    :: [BlockDeviceMappingParam] -> QueryParam
blockDeviceMappingParams =
    StructArrayParams "BlockDeviceMapping" . map kvs
  where
    kvs (BlockDeviceMappingParamEBS name dev src dot vtype) = 
        [ ("Ebs.DeviceName", name)
        , ebsSource src
        ] ++ vtparam vtype ++ (uncurry f =<<
            [ ("Ebs.NoDevice", boolToText <$> dev)
            , ("Ebs.DeleteOnTermination", boolToText <$> dot)
            ])
    kvs (BlockDeviceMappingParamInstanceStore name dev vname) =
        [("Ebs.DeviceName", name)] ++ (uncurry f =<<
            [ ("Ebs.NoDevice", boolToText <$> dev)
            , ("Ebs.VirtualName", vname)
            ])

    ebsSource (EbsSnapshotId sid) = ("Ebs.SnapshotId", sid)
    ebsSource (EbsVolumeSize size) =
        ("Ebs.VolumeSize", T.pack $ show size)

    f n = maybe [] (\a -> [(n, a)])
    vtparam Nothing = []
    vtparam (Just Standard) = [("Ebs.VolumeType", "standard")]
    vtparam (Just (IO1 iops)) =
        [ ("Ebs.VolumeType", "io1")
        , ("Ebs.Iops", T.pack $ show iops)
        ]

data EbsSource
    = EbsSnapshotId Text
    | EbsVolumeSize Int
  deriving (Show)
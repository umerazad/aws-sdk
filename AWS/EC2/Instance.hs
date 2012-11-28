{-# LANGUAGE FlexibleContexts, RankNTypes #-}

module AWS.EC2.Instance
    ( describeInstances
    , runInstances
    , defaultRunInstancesRequest
    , terminateInstances
    , startInstances
    , stopInstances
    , rebootInstances
    , getConsoleOutput
    , getPasswordData
    , describeInstanceStatus
    , describeInstanceAttribute
    , resetInstanceAttribute
    , modifyInstanceAttribute
    ) where

import Data.Text (Text)
import Data.XML.Types (Event)
import Data.Conduit
import Control.Monad.Trans.Control (MonadBaseControl)
import Control.Applicative
import Data.Maybe (fromJust)
import qualified Data.Map as Map

import AWS.EC2.Convert
import AWS.EC2.Internal
import AWS.EC2.Types
import AWS.EC2.Params
import AWS.EC2.Query
import AWS.Lib.Parser
import AWS.Util

------------------------------------------------------------
-- DescribeInstances
------------------------------------------------------------
describeInstances
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ InstanceIds
    -> [Filter] -- ^ Filters
    -> EC2 m (ResumableSource m Reservation)
describeInstances instances filters = do
    ec2QuerySource "DescribeInstances" params $
        itemConduit "reservationSet" reservationSink
  where
    params =
        [ ArrayParams "InstanceId" instances
        , FilterParams filters
        ]

reservationSink :: MonadThrow m
    => GLSink Event m Reservation
reservationSink =
    Reservation
    <$> getT "reservationId"
    <*> getT "ownerId"
    <*> groupSetSink
    <*> instanceSetSink
    <*> getMT "requesterId"

groupSetSink :: MonadThrow m => GLSink Event m [Group]
groupSetSink = itemsSet "groupSet" $ Group
    <$> getT "groupId"
    <*> getT "groupName"

instanceSetSink :: MonadThrow m
    => GLSink Event m [Instance]
instanceSetSink = itemsSet "instancesSet" $
    Instance
    <$> getT "instanceId"
    <*> getT "imageId"
    <*> instanceStateSink "instanceState"
    <*> getT "privateDnsName"
    <*> getT "dnsName"
    <*> getT "reason"
    <*> getMT "keyName"
    <*> getT "amiLaunchIndex"
    <*> productCodeSink
    <*> getT "instanceType"
    <*> getF "launchTime" textToTime
    <*> element "placement" (
        Placement
        <$> getT "availabilityZone"
        <*> getT "groupName"
        <*> getT "tenancy"
        )
    <*> getMT "kernelId"
    <*> getMT "ramdiskId"
    <*> getMT "platform"
    <*> element "monitoring" (getF "state" instanceMonitoringState)
    <*> getMT "subnetId"
    <*> getMT "vpcId"
    <*> getMT "privateIpAddress"
    <*> getMT "ipAddress"
    <*> getM "sourceDestCheck" (textToBool <$>)
    <*> groupSetSink
    <*> stateReasonSink
    <*> getF "architecture" architecture
    <*> getF "rootDeviceType" rootDeviceType
    <*> getMT "rootDeviceName"
    <*> instanceBlockDeviceMappingsSink
    <*> getM "instanceLifecycle" instanceLifecycle
    <*> getMT "spotInstanceRequestId"
    <*> getF "virtualizationType" virtualizationType
    <*> getT "clientToken"
    <*> resourceTagSink
    <*> getF "hypervisor" hypervisor
    <*> networkInterfaceSink
    <*> elementM "iamInstanceProfile" (
        IamInstanceProfile
        <$> getT "arn"
        <*> getT "id"
        )
    <*> getF "ebsOptimized" textToBool

instanceBlockDeviceMappingsSink :: MonadThrow m
    => GLSink Event m [InstanceBlockDeviceMapping]
instanceBlockDeviceMappingsSink = itemsSet "blockDeviceMapping" (
    InstanceBlockDeviceMapping
    <$> getT "deviceName"
    <*> element "ebs" (
        EbsInstanceBlockDevice
        <$> getT "volumeId"
        <*> getF "status" attachmentSetItemResponseStatus'
        <*> getF "attachTime" textToTime
        <*> getF "deleteOnTermination" textToBool
        )
    )

instanceStateSink :: MonadThrow m
    => Text -> GLSink Event m InstanceState
instanceStateSink label = element label $
    codeToState
    <$> getF "code" textToInt
    <* getT "name"

networkInterfaceSink :: MonadThrow m
    => GLSink Event m [InstanceNetworkInterface]
networkInterfaceSink = itemsSet "networkInterfaceSet" $
    InstanceNetworkInterface
    <$> getT "networkInterfaceId"
    <*> getT "subnetId"
    <*> getT "vpcId"
    <*> getM "description" orEmpty
    <*> getT "ownerId"
    <*> getT "status"
    <*> getT "privateIpAddress"
    <*> getMT "privateDnsName"
    <*> getF "sourceDestCheck" textToBool
    <*> groupSetSink
    <*> element "attachment" (
        NetworkInterfaceAttachment
        <$> getT "attachmentId"
        <*> getF "deviceIndex" textToInt
        <*> getT "status"
        <*> getF "attachTime" textToTime
        <*> getF "deleteOnTermination" textToBool
        )
    <*> niAssociationSink
    <*> itemsSet "privateIpAddressesSet" (
        InstancePrivateIpAddress
        <$> getT "privateIpAddress"
        <*> getF "primary" textToBool
        <*> niAssociationSink
        )

niAssociationSink :: MonadThrow m
    => GLSink Event m (Maybe NetworkInterfaceAssociation)
niAssociationSink = elementM "association" $
    NetworkInterfaceAssociation
    <$> getT "publicIp"
    <*> getT "ipOwnerId"

------------------------------------------------------------
-- DescribeInstanceStatus
------------------------------------------------------------
-- | raise 'ResponseParserException'('NextToken' token)
describeInstanceStatus
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ InstanceIds
    -> Bool  -- ^ is all instance? 'False': running instance only.
    -> [Filter] -- ^ Filters
    -> Maybe Text -- ^ next token
    -> EC2 m (ResumableSource m InstanceStatus)
describeInstanceStatus instanceIds isAll filters token =
    ec2QuerySource' "DescribeInstanceStatus" params token instanceStatusSet
  where
    params =
        [ ArrayParams "InstanceId" instanceIds
        , ValueParam "IncludeAllInstances" $ boolToText isAll
        , FilterParams filters
        ]

instanceStatusSet :: MonadThrow m
    => GLConduit Event m InstanceStatus
instanceStatusSet = do
    itemConduit "instanceStatusSet" $
        InstanceStatus
        <$> getT "instanceId"
        <*> getT "availabilityZone"
        <*> itemsSet "eventsSet" (
            InstanceStatusEvent
            <$> getF "code" instanceStatusEventCode'
            <*> getT "description"
            <*> getM "notBefore" (textToTime <$>)
            <*> getM "notAfter" (textToTime <$>)
            )
        <*> instanceStateSink "instanceState"
        <*> instanceStatusTypeSink "systemStatus"
        <*> instanceStatusTypeSink "instanceStatus"

instanceStatusTypeSink :: MonadThrow m
    => Text -> GLSink Event m InstanceStatusType
instanceStatusTypeSink name = element name $
    InstanceStatusType
    <$> getF "status" instanceStatusTypeStatus'
    <*> itemsSet "details" (
        InstanceStatusDetail
        <$> getT "name"
        <*> getT "status"
        <*> getM "impairedSince" (textToTime <$>)
        )

------------------------------------------------------------
-- StartInstances
------------------------------------------------------------
startInstances
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ InstanceIds
    -> EC2 m (ResumableSource m InstanceStateChange)
startInstances instanceIds =
    ec2QuerySource "StartInstances" params instanceStateChangeSet
  where
    params = [ArrayParams "InstanceId" instanceIds]

instanceStateChangeSet
    :: (MonadResource m, MonadBaseControl IO m)
    => Conduit Event m InstanceStateChange
instanceStateChangeSet = itemConduit "instancesSet" $ do
    InstanceStateChange
    <$> getT "instanceId"
    <*> instanceStateSink "currentState"
    <*> instanceStateSink "previousState"

------------------------------------------------------------
-- StopInstances
------------------------------------------------------------
stopInstances
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ InstanceIds
    -> Bool -- ^ Force
    -> EC2 m (ResumableSource m InstanceStateChange)
stopInstances instanceIds force =
    ec2QuerySource "StopInstances" params instanceStateChangeSet
  where
    params =
        [ ArrayParams "InstanceId" instanceIds
        , ValueParam "Force" $ boolToText force]

------------------------------------------------------------
-- RebootInstances
------------------------------------------------------------
rebootInstances
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ InstanceIds
    -> EC2 m Bool
rebootInstances instanceIds =
    ec2Query "RebootInstances" params returnBool
  where
    params = [ArrayParams "InstanceId" instanceIds]

------------------------------------------------------------
-- TerminateInstances
------------------------------------------------------------
terminateInstances
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ InstanceIds
    -> EC2 m (ResumableSource m InstanceStateChange)
terminateInstances instanceIds =
    ec2QuerySource "TerminateInstances" params
        instanceStateChangeSet
  where
    params = [ArrayParams "InstanceId" instanceIds]

------------------------------------------------------------
-- RunInstances
------------------------------------------------------------
-- | 'RunInstancesParam' is genereted with 'defaultRunInstancesParam'
runInstances
    :: (MonadResource m, MonadBaseControl IO m)
    => RunInstancesRequest
    -> EC2 m Reservation
runInstances param =
    ec2Query "RunInstances" params reservationSink
  where
    params =
        [ ValueParam "ImageId" $ runInstancesRequestImageId param
        , ValueParam "MinCount"
            $ toText $ runInstancesRequestMinCount param
        , ValueParam "MaxCount"
            $ toText $ runInstancesRequestMaxCount param
        , ArrayParams "SecurityGroupId"
            $ runInstancesRequestSecurityGroupIds param
        , ArrayParams "SecurityGroup"
            $ runInstancesRequestSecurityGroups param
        , blockDeviceMappingParams
            $ runInstancesRequestBlockDeviceMappings param
        ] ++ maybeParams
            [ ("KeyName", runInstancesRequestKeyName param)
            , ("UserData"
              , bsToText <$> runInstancesRequestUserData param
              )
            , ("InstanceType"
              , runInstancesRequestInstanceType param
              )
            , ("Placement.AvailabilityZone"
              , runInstancesRequestAvailabilityZone param
              )
            , ("Placement.GroupName"
              , runInstancesRequestPlacementGroup param
              )
            , ("Placement.Tenancy"
              , runInstancesRequestTenancy param
              )
            , ("KernelId", runInstancesRequestKernelId param)
            , ("RamdiskId", runInstancesRequestRamdiskId param)
            , ("Monitoring.Enabled"
              , boolToText
                <$> runInstancesRequestMonitoringEnabled param
              )
            , ("SubnetId", runInstancesRequestSubnetId param)
            , ("DisableApiTermination"
              , boolToText
                <$> runInstancesRequestDisableApiTermination param
              )
            , ("InstanceInitiatedShutdownBehavior"
              , sbToText
                <$> runInstancesRequestShutdownBehavior param
              )
            , ("PrivateIpAddress"
              , runInstancesRequestPrivateIpAddress param
              )
            , ("ClientToken", runInstancesRequestClientToken param)
            , ("IamInstanceProfile.Arn"
              , iamInstanceProfileArn
                <$> runInstancesRequestIamInstanceProfile param
              )
            , ("IamInstanceProfile.Name"
              , iamInstanceProfileId
                <$> runInstancesRequestIamInstanceProfile param
              )
            , ("EbsOptimized"
              , boolToText
                <$> runInstancesRequestEbsOptimized param
              )
            ]

-- | RunInstances parameter utility
defaultRunInstancesRequest
    :: Text -- ^ ImageId
    -> Int -- ^ MinCount
    -> Int -- ^ MaxCount
    -> RunInstancesRequest
defaultRunInstancesRequest iid minCount maxCount
    = RunInstancesRequest
        iid
        minCount
        maxCount
        Nothing
        []
        []
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        []
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        []
        Nothing
        Nothing

sbToText :: ShutdownBehavior -> Text
sbToText ShutdownBehaviorStop      = "stop"
sbToText ShutdownBehaviorTerminate = "terminate"

------------------------------------------------------------
-- GetConsoleOutput
------------------------------------------------------------
getConsoleOutput
    :: (MonadResource m, MonadBaseControl IO m)
    => Text -- ^ InstanceId
    -> EC2 m ConsoleOutput
getConsoleOutput iid =
    ec2Query "GetConsoleOutput" [ValueParam "InstanceId" iid] $
        ConsoleOutput
        <$> getT "instanceId"
        <*> getF "timestamp" textToTime
        <*> getT "output"

------------------------------------------------------------
-- GetPasswordData
------------------------------------------------------------
getPasswordData
    :: (MonadResource m, MonadBaseControl IO m)
    => Text -- ^ InstanceId
    -> EC2 m PasswordData
getPasswordData iid =
    ec2Query "GetPasswordData" [ValueParam "InstanceId" iid] $
        PasswordData
        <$> getT "instanceId"
        <*> getF "timestamp" textToTime
        <*> getT "passwordData"

describeInstanceAttribute
    :: (MonadResource m, MonadBaseControl IO m)
    => Text -- ^ InstanceId
    -> InstanceAttributeRequest -- ^ Attribute
    -> EC2 m InstanceAttribute
describeInstanceAttribute iid attr =
    ec2Query "DescribeInstanceAttribute" params
        $ getT "instanceId" *> f attr
  where
    str = iar attr
    params =
        [ ValueParam "InstanceId" iid
        , ValueParam "Attribute" str
        ]
    f InstanceAttributeRequestBlockDeviceMapping = instanceBlockDeviceMappingsSink
        >>= return . InstanceAttributeBlockDeviceMapping
    f InstanceAttributeRequestProductCodes =
        productCodeSink >>= return . InstanceAttributeProductCodes
    f InstanceAttributeRequestGroupSet =
        (itemsSet str $ getT "groupId")
        >>= return . InstanceAttributeGroupSet
    f req = valueSink str (fromJust $ Map.lookup req h)
    h = Map.fromList
        [ (InstanceAttributeRequestInstanceType,
           InstanceAttributeInstanceType . fromJust)
        , (InstanceAttributeRequestKernelId, InstanceAttributeKernelId)
        , (InstanceAttributeRequestRamdiskId, InstanceAttributeRamdiskId)
        , (InstanceAttributeRequestUserData, InstanceAttributeUserData)
        , (InstanceAttributeRequestDisableApiTermination,
           InstanceAttributeDisableApiTermination
           . textToBool . fromJust)
        , (InstanceAttributeRequestShutdownBehavior,
           InstanceAttributeShutdownBehavior
           . shutdownBehavior . fromJust)
        , (InstanceAttributeRequestRootDeviceName, InstanceAttributeRootDeviceName)
        , (InstanceAttributeRequestSourceDestCheck,
           InstanceAttributeSourceDestCheck . (textToBool <$>))
        , (InstanceAttributeRequestEbsOptimized,
           InstanceAttributeEbsOptimized . textToBool . fromJust)
        ]
    valueSink name val =
        (element name $ getMT "value") >>= return . val

iar :: InstanceAttributeRequest -> Text
iar InstanceAttributeRequestInstanceType          = "instanceType"
iar InstanceAttributeRequestKernelId              = "kernel"
iar InstanceAttributeRequestRamdiskId             = "ramdisk"
iar InstanceAttributeRequestUserData              = "userData"
iar InstanceAttributeRequestDisableApiTermination = "disableApiTermination"
iar InstanceAttributeRequestShutdownBehavior      = "instanceInitiatedShutdownBehavior"
iar InstanceAttributeRequestRootDeviceName        = "rootDeviceName"
iar InstanceAttributeRequestBlockDeviceMapping    = "blockDeviceMapping"
iar InstanceAttributeRequestSourceDestCheck       = "sourceDestCheck"
iar InstanceAttributeRequestGroupSet              = "groupSet"
iar InstanceAttributeRequestProductCodes          = "productCodes"
iar InstanceAttributeRequestEbsOptimized          = "ebsOptimized"

riap :: ResetInstanceAttributeRequest -> Text
riap ResetInstanceAttributeRequestKernel          = "kernel"
riap ResetInstanceAttributeRequestRamdisk         = "ramdisk"
riap ResetInstanceAttributeRequestSourceDestCheck = "sourceDestCheck"

resetInstanceAttribute
    :: (MonadResource m, MonadBaseControl IO m)
    => Text -- ^ InstanceId
    -> ResetInstanceAttributeRequest
    -> EC2 m Bool
resetInstanceAttribute iid attr =
    ec2Query "ResetInstanceAttribute" params returnBool
  where
    params =
        [ ValueParam "InstanceId" iid
        , ValueParam "Attribute" $ riap attr
        ]

-- | not tested
modifyInstanceAttribute
    :: (MonadResource m, MonadBaseControl IO m)
    => Text -- ^ InstanceId
    -> [ModifyInstanceAttributeRequest]
    -> EC2 m Bool
modifyInstanceAttribute iid attrs =
    ec2Query "ModifyInstanceAttribute" params returnBool
  where
    params = ValueParam "InstanceId" iid:concatMap miap attrs

miap :: ModifyInstanceAttributeRequest -> [QueryParam]
miap (ModifyInstanceAttributeRequestInstanceType a) =
    [ValueParam "InstanceType.Value" a]
miap (ModifyInstanceAttributeRequestKernelId a) =
    [ValueParam "Kernel.Value"  a]
miap (ModifyInstanceAttributeRequestRamdiskId a) =
    [ValueParam "Ramdisk.Value" a]
miap (ModifyInstanceAttributeRequestUserData a) =
    [ValueParam "UserData.Value" a]
miap (ModifyInstanceAttributeRequestDisableApiTermination a) =
    [ValueParam "DisableApiTermination.Value" $ toText a]
miap (ModifyInstanceAttributeRequestShutdownBehavior a) =
    [ValueParam "InstanceInitiatedShutdownBehavior.Value"
     $ sbToText a]
miap (ModifyInstanceAttributeRequestRootDeviceName a) =
    [ValueParam "RootDeviceName" a]
miap (ModifyInstanceAttributeRequestBlockDeviceMapping a) =
    [blockDeviceMappingParams a]
miap (ModifyInstanceAttributeRequestSourceDestCheck a) =
    [ValueParam "SourceDestCheck.Value" $ toText a]
miap (ModifyInstanceAttributeRequestGroupSet a) =
    [ArrayParams "GroupId" a]
miap (ModifyInstanceAttributeRequestEbsOptimized a) =
    [ValueParam "EbsOptimized" $ toText a]

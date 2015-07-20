Param($InstanceID, $Region="us-west-2")

Function Get-AttachedVols {
   Param($I, $R)
    $blockdevices = (Get-EC2Instance -Region $R -Instance $I |ForEach-Object {$PSItem.RunningInstance}).BlockDeviceMappings
    $volumes = ($blockdevices).Ebs |Select-Object -Property VolumeID
    $volumes | Get-EC2Volume |Select-Object -Property VolumeID,VolumeType,State, @{n='Instance';e={"$($_.Attachments.InstanceID)"}},Encrypted,IOPs,Size,CreateTime
    
}

Get-AttachedVols $InstanceID $Region

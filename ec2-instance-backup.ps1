param(
    [parameter(mandatory=$false)][string]$Region = "us-west-2",
    [parameter(mandatory=$false)][string]$AccountID = "<our account id goes here>"
)

# Import the AWS module so we have access to the EC2 objects required to create filters before an AWS cmdlet auto loads the module 
Import-Module AwsPowerShell

Function CreateSnapshots($Region)
{
    $created = @()
    
    $Filter = New-Object Amazon.EC2.Model.Filter
    $Filter.Name = 'tag:backup_enabled'
    $Filter.Value = '*'
    Get-EC2Volume -Region $Region -Filter $Filter | ForEach-Object {
        
        #If this volume is attached to an instance, let's record the information in the comments
        if($_.Attachment){
            $Device = $_.Attachment[0].Device
            $InstanceId = $_.Attachment[0].InstanceId
            $Reservation = Get-EC2Instance $InstanceId
            $Instance = $Reservation.RunningInstance | Where-Object {$_.InstanceId -eq $InstanceId}
            $Name = ($Instance.Tag | Where-Object { $_.Key -eq 'Name' }).Value
            $Owner = ($Instance.Tag | Where-Object { $_.Key -eq 'owner' }).Value
            $BillingContact = ($Instance.Tag | Where-Object { $_.Key -eq 'billing_contact' }).Value
            $Description = "Backup of $($_.VolumeID), attached to instance $Name ($InstanceId) as $Device"
            $RetentionDays = [int]((Get-EC2Volume -VolumeId $_.VolumeId).Tags| Where-Object { $_.Key -eq 'backup_enabled' }).Value
                
            #Create the backup
            $Volume = $_.VolumeId
	        Write-Host -Foreground Green "Creating $Description"
            $Snapshot = New-EC2Snapshot -Region $Region $Volume -Description $Description 

            #Add a tag so we can distinguish this snapshot from all the others
            $Tag = New-Object amazon.EC2.Model.Tag
            $Tag.Key = 'owner'
            $Tag.Value = $Owner
            New-EC2Tag -Region $Region -ResourceId $Snapshot.SnapshotID -Tag $Tag

            $Tag = New-Object amazon.EC2.Model.Tag
            $Tag.Key = 'billing_contact'
            $Tag.Value = $BillingContact
            New-EC2Tag -Region $Region -ResourceId $Snapshot.SnapshotID -Tag $Tag

            $Tag = New-Object amazon.EC2.Model.Tag
            $Tag.Key = 'Name'
            $Tag.Value = $Name
            New-EC2Tag -Region $Region -ResourceId $Snapshot.SnapshotID -Tag $Tag

            $Tag = New-Object amazon.EC2.Model.Tag
            $Tag.Key = 'backup_date'
            $Tag.Value = [DateTime]::Now
            New-EC2Tag -Region $Region -ResourceId $Snapshot.SnapshotID -Tag $Tag

            $Tag = New-Object amazon.EC2.Model.Tag
            $Tag.Key = 'retention_date'
            $Tag.Value = ([DateTime]::Now).AddDays($RetentionDays)
            New-EC2Tag -Region $Region -ResourceId $Snapshot.SnapshotID -Tag $Tag

            #$created += "Instance: $Name ($InstanceId), Snapshot: $($Snapshot.SnapshotID), Volume: $Volume, Device: $Device, RetentionDays: $RetentionDays"
            $snap = ""| Select-Object -Property InstanceName, InstanceID, Snapshot, Volume, Device, RetentionDays
            $snap.InstanceName = $Name
            $snap.InstanceID = $InstanceId
            $snap.Snapshot = $($Snapshot.SnapshotID)
            $snap.Volume = $Volume
            $snap.Device = $Device
            $snap.RetentionDays = $RetentionDays
            
            $created += $snap
           
           }
    }
    return $created
}

Function PurgeSnapshots($Region)
{
    $purged = @()
    
    #Delete and snapshots created by this tool, that are older than the specified number of days
    $Filter = New-Object Amazon.EC2.Model.Filter
    $Filter.Name = 'tag:retention_date'
    $Filter.Value = '*'

    #$now = ([DateTime]::Now).AddMinutes(300000)
    $now = ([DateTime]::Now).AddMinutes(10)

    Get-EC2Snapshot -Region $Region -OwnerId $AccountID -Filter $Filter | ForEach-Object {
       
    $RetentionDate = [datetime]::Parse((( Get-EC2Snapshot -Region $Region -SnapshotId $_.SnapshotId).Tags| Where-Object { $_.Key -eq 'retention_date' }).Value)
    $Name = ($_.Tags | Where-Object { $_.Key -eq 'Name' }).Value
    $SnapDate = ($_.Tags | Where-Object { $_.Key -eq 'backup_date' }).Value

    if ($now -ge $RetentionDate){
        Write-Host -Foreground Yellow "Deleting snapshot: $($_.SnapshotId)"
        Remove-EC2Snapshot -Region $Region -SnapshotId $_.SnapshotId -Force
        #$purged += "Instance: $Name, Device: $device, Snapshot: $($_.SnapshotId), Created: $SnapDate"
        $purge = ""| Select-Object -Property InstanceName, Snapshot, SnapDate
        $purge.InstanceName = $Name
        $purge.Snapshot = $($_.SnapshotId)
        $purge.SnapDate = $SnapDate
        $purged += $purge
    }
    
    }

    return $purged
}


$created = CreateSnapshots $Region
Start-Sleep -Seconds 10
$purged = PurgeSnapshots $Region


if ($created -or $purged) {

    $ReportC = $created| ConvertTo-Html -Fragment
    $ReportP = $purged| ConvertTo-Html -Fragment

    $Report = @"
        <html>
        <head>
        <title>EC2 Instance Backup Report</title>
        <style>
             table {
             border-collapse: collapse;
             }
             table, td, th {
                 border: 1px solid gray;
             }
             td, th {
                 padding: 3px;
                 text-align: left;

             }
             th {
                  background-color: black;
                  color: white;
             }
        </style>
        </head>
        <body>
        <p><h3>The following snapshots were created</h3><p>
        $ReportC
        <p><h3>The following snapshots were purged</h3><p>
        $ReportP
        </body></html>
"@

Send-MailMessage -SmtpServer "mx.fhcrc.org" -From "ec2-backupservice@fredhutch.org" -BodyAsHtml $Report -Subject "EC2 Instance Backup Report: $(Get-Date)" -To "rmcdermo@fredhutch.org"

}
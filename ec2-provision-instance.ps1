Param(
    [string]$Region = "us-west-2",
    [string]$AvailibilityZone = "us-west-2a",
    [string]$Vpc = "vpc-f3e23496",
    [string]$SubnetId = "subnet-ae8555d9",
    [string]$InstanceType = "t2.small",
    [array]$SecurityGroupIds = "sg-9e3a7cfb",
    [Parameter(Mandatory=$true)]
    [String]$Name,
    [string]$KeyName = "$Name.pem",
    [string]$AmiName = "WINDOWS_2012R2_BASE",
    [Parameter(Mandatory=$true)]
    [string]$Owner,
    #[string]$Owner = "_adm/solarch",
    [Parameter(Mandatory=$true)]
    [string]$TechContact,
    [Parameter(Mandatory=$true)]
    [string]$BillingContact,
    [string]$Description = "Provisioned by $([Environment]::UserDomainName)\$([Environment]::UserName) On: $(Get-Date)",
    [string]$BusinessHours = "?",
    [string]$GrantCritical = "?",
    [string]$Phi = "?",
    [string]$Pii = "?",
    [string]$PubliclyAccessible = "?",
    [string]$Password = ([char[]](Get-Random -Input $(48..57 + 65..90 + 97..122) -Count 12)) -join "",
    [int]$DailySnapshotRetention = 0,
    [string]$RootVolSize = "50",
    [string]$RootVolDelOnTerminate = "true",
    [string]$RootVolType = "gp2", #'gp2' for GP SSD, 'io1' for provisioned iops (also requires -Iops parameter), "standard" for magenetic disks
    [string]$DataVolSize = $False,
    [string]$DataVolDelOnTerminate = "true",
    [string]$DataVolEncrypted = "false",
    [string]$DataVolType = "gp2", #'gp2' for GP SSD, 'io1' for provisioned iops (also requires -Iops parameter), "standard" for magenetic disks
    [string]$RegisterDNS = "false",
    [string]$AlertsEnabled = "false"
     
)


# Build the SLE (service level expectations) metadata tag value 
$Sle = "business_hours=$BusinessHours / grant_critical=$GrantCritical / phi=$Phi / pii=$Pii / publicly_accessible=$PubliclyAccessible"

# This script supports multiple security groupids (sg-123020,sg-202002) so create an array if there are multiples 
$SecurityGroupIds = $SecurityGroupIds -split ","


# Import the AWS module so we have access to the EC2 objects required to create the volumes and device mappings 
Import-Module AwsPowerShell

Write-Host ""
Write-Host "Configuring $RootVolSize GB Root (OS) Volume..."
# Create and configure the root volume
$RootVol = New-Object Amazon.EC2.Model.EbsBlockDevice
$RootVol.DeleteOnTermination = ($RootVolDelOnTerminate -eq "true")
$RootVol.VolumeSize = $RootVolSize
$RootVol.VolumeType = $RootVolType
$RootVolMapping = New-Object Amazon.EC2.Model.BlockDeviceMapping
$RootVolMapping.DeviceName = '/dev/sda1'
$RootVolMapping.Ebs = $RootVol

# Create and configure the optional data volume
if ($DataVolSize -ne $False){
    Write-Host "Configuring $DataVolSize GB Data Volume..."
    $DataVol = New-Object Amazon.EC2.Model.EbsBlockDevice
    $DataVol.DeleteOnTermination = ($DataVolDelOnTerminate -eq "true")
    $DataVol.VolumeSize = $DataVolSize
    $DataVol.VolumeType = $DataVolType
    if ($DataVolEncrypted -ne "false"){
        $DataVol.Encrypted = "true"
    }
    $DataVolMapping = New-Object Amazon.EC2.Model.BlockDeviceMapping
    $DataVolMapping.DeviceName = 'xvdf'
    $DataVolMapping.Ebs = $DataVol
} 

# Create a new temporary key for the instance
Write-Host "Generating Temporary Key-Pair $KeyName..."
$Key = New-EC2KeyPair -KeyName $KeyName -Region $Region
$Key.KeyMaterial|Out-File -FilePath "C:\Temp\$KeyName"

# Grab the latest AMI image by name (I think this only works for Windows AMIs, need to modify this to also work with Linux)
Write-Host "Selecting Latest AMI Image..." 
$Ami = Get-EC2ImageByName -Name $AmiName -Region $Region
Write-Host "Selected AMI: $($Ami[0].ImageId)" -ForegroundColor Green

# This is the User-Data script that will be exected the first time an instance is booted. This script needs to be modifed to support Linux
$UserData = @"
<powershell>
# Set the local Administrator password
`$ComputerName = `$env:COMPUTERNAME
`$user = [adsi]"WinNT://`$ComputerName/Administrator,user"
`$user.setpassword("$Password")
# Disable the Windows Firewall
Get-NetFirewallProfile | Set-NetFirewallProfile –Enabled False -Confirm:`$false
# Set the logon banner notice 
`$LegalNotice = "***  Warning  *** This system is for the exclusive use of authorized Fred Hutchinson Cancer Research Center employees and associates. Anyone using this system without authority, or in excess of their authority, is subject to having all of their activities on this system monitored and recorded by system administration staff. In the course of monitoring individuals improperly using this system, or in the course of system maintenance, the activities of authorized users may also be monitored. Anyone using this system expressly consents to such monitoring and is advised that if such monitoring reveals possible evidence of criminal activity, system administration staff may provide the evidence from such monitoring to law enforcement officials XXX."
[string]`$reg = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-ItemProperty -Path `$reg -Name disablecad -Value 00000000 -Type DWORD -Force
Set-ItemProperty -Path `$reg -Name dontdisplaylastusername -Value 00000001 -Type DWORD -Force
Set-ItemProperty -Path `$reg -Name shutdownwithoutlogon -Value 00000000 -Type DWORD -Force
Set-ItemProperty -Path `$reg -Name legalnoticecaption -Type STRING -Value "FHCRC Network Access Warning"  -Force
Set-ItemProperty -Path `$reg -Name legalnoticetext -Type STRING -Value `$LegalNotice -Force
# Rename the computer to match the provided instance name are reboot
Rename-Computer -NewName $Name -Force
Restart-Computer -Force
</powershell> 
"@
# The user-data needs to be Base64 encoded
$UserData = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($UserData))

# Lets create the instance
Write-Host "Attempting to Create EC2 Instance..."
Try {
If ($DataVolSize -eq $False){
    $Reservation = New-EC2Instance -Region $Region -ImageId $Ami[0].ImageId -Monitoring_Enabled $True -KeyName $KeyName -InstanceType $InstanceType -MinCount 1 -MaxCount 1 -UserData $UserData -SubnetId $SubnetId -SecurityGroupIds $securityGroupIds -BlockDeviceMapping $RootVolMapping
    Write-Host "Successfully Launched Instance!" -ForegroundColor Green
}
Else {
    $Reservation = New-EC2Instance -Region $Region -ImageId $Ami[0].ImageId -Monitoring_Enabled $True -KeyName $KeyName -InstanceType $InstanceType -MinCount 1 -MaxCount 1 -UserData $UserData -SubnetId $SubnetId -SecurityGroupIds $securityGroupIds -BlockDeviceMapping $RootVolMapping, $DataVolMapping
    Write-Host "Successfully Launched Instance!" -ForegroundColor Green
}
# Wait a bit for the system to catch up, ran into occasional tagging errors without this
Write-Host "Waiting for instance to boot..."
Start-Sleep -Seconds 15
}
Catch {
   Write-Host "Error Creating Instance:`n$($_.Exception.Message)" -ForegroundColor Red
   Exit(1)
}

$Instance = $Reservation.RunningInstance[0]
$InstanceId = $Instance.InstanceId


# Tag the new instance
Write-Host "Tagging the Instance..."
$NameTag = New-Object Amazon.EC2.Model.Tag
$NameTag.Key = "Name"
$NameTag.Value = $Name
New-EC2Tag -Resources $Instance.InstanceID -Tag $NameTag -Region $region

$OwnerTag = New-Object Amazon.EC2.Model.Tag
$OwnerTag.Key = "owner"
$OwnerTag.Value = $Owner
New-EC2Tag -Resources $Instance.InstanceID -Tag $OwnerTag -Region $region

$TechContactTag = New-Object Amazon.EC2.Model.Tag
$TechContactTag.Key = "technical_contact"
$TechContactTag.Value = $TechContact
New-EC2Tag -Resources $Instance.InstanceID -Tag $TechContactTag -Region $region

$DescriptionTag = New-Object Amazon.EC2.Model.Tag
$DescriptionTag.Key = "description"
$DescriptionTag.Value = $Description
New-EC2Tag -Resources $Instance.InstanceID -Tag $DescriptionTag -Region $region

$BillingContactTag = New-Object Amazon.EC2.Model.Tag
$BillingContactTag.Key = "billing_contact"
$BillingContactTag.Value = $BillingContact
New-EC2Tag -Resources $Instance.InstanceID -Tag $BillingContactTag -Region $region

$SleTag = New-Object Amazon.EC2.Model.Tag
$SleTag.Key = "sle"
$SleTag.Value = $Sle
New-EC2Tag -Resources $Instance.InstanceID -Tag $SleTag -Region $region

If ($DailySnapshotRetention -gt 0){
    Write-Host "Enabling Snapshot Schedule On All Attached Volumes..."
    $BackupTag = New-Object Amazon.EC2.Model.Tag
    $BackupTag.Key = "backup_enabled"
    $BackupTag.Value = $DailySnapshotRetention
    New-EC2Tag -Resources $Instance.InstanceID -Tag $BackupTag -Region $region
}
# Done Tagging instance 


# gather some information about the instance with the instance-info script
Set-Location C:\Users\rmcdermo\Documents\powershell-code
$InstanceInfo = & ".\ec2-instance-info.ps1" |Where-Object {$_.InstanceID -eq $InstanceId}
$ReportBody = $InstanceInfo|Out-String
$PrivateIp = $InstanceInfo|Select-Object -ExpandProperty PrivateIpAddress

if ($RegisterDNS -ne "false"){
    Write-Host "Registering Instance in DNS ($Name.fredhutch.center)..." -ForegroundColor Green
    $Zone = "fredhutch.center."
    $IP = $PrivateIp
    $Type = "A"
    $TTL = 300
    $HostedZone = Get-R53HostedZones |Where-Object {$_.Name -eq $Zone}

    $FQDN = $Name + "." + $Zone
    $ResourceRecordSet = New-Object -TypeName Amazon.Route53.Model.ResourceRecordSet
    $ResourceRecordSet.Name = $FQDN
    $ResourceRecordSet.Type = $Type
    $ResourceRecordSet.ResourceRecords.Add($IP)
    $ResourceRecordSet.TTL = $TTL
    #$ResourceRecordSet.Weight = 0

    $Change = New-Object -TypeName Amazon.Route53.Model.Change
    $Change.Action = "UPSERT"
    $Change.ResourceRecordSet = $ResourceRecordSet
    Write-Host "Registering host '$Name' in the 'fredhutch.center' DNS Zone..."
    Try {
        $Result = Edit-R53ResourceRecordSet -HostedZoneId $HostedZone.Id -ChangeBatch_Change $Change
        Write-Host "DNS Registration Successful!" -ForegroundColor Green
    }
    Catch {
        Write-Host "Error registering instance in Route53 DNS:`n$($_.Exception.Message)" -ForegroundColor Red
    }


}


# Add and Alert to this instance
if ($AlertsEnabled -ne 'false'){
    Write-Host "Setting up CloudWatch monitoring and Alerting..."
    $Dimension = New-Object "Amazon.CloudWatch.Model.Dimension"
    $Dimension.Name = 'InstanceId'
    $Dimension.Value = $InstanceId
    Write-CWMetricAlarm -AlarmName "${Name}_CPU" `
                               -AlarmDescription "Alert if CPU utilization exceeds 90% for 5 minutes" `
                               -Namespace "AWS/EC2" `
                               -MetricName 'CPUUtilization' `
                               -Statistic "Average" `
                               -Threshold 90 `
                               -Unit 'Percent' `
                               -ComparisonOperator "GreaterThanOrEqualToThreshold" `
                               -EvaluationPeriods 5 `
                               -Period 60 `
                               -AlarmActions 'arn:aws:sns:us-west-2:458818213009:US-WEST-2_EC2' `
                               -OKActions 'arn:aws:sns:us-west-2:458818213009:US-WEST-2_EC2' `
                               -Dimension $Dimension

} 


if ($RegisterDNS -ne "false"){
# Create an send an RDP profile if it's a new Window Instance
$RdpProfile = @"
auto connect:i:1
full address:s:$Name.fredhutch.center
username:s:Administrator
"@
    $RdpFile = "C:\Temp\$Name.rdp"
    Set-Content -Path $RdpFile -Value $RdpProfile
# This is the report that will be sent to the technical contact
$Report = @"
<html><head><title>EC2 Instance Provisioned</title></head>
<body>
<p>EC2 instance $Name ($InstanceID) has been created. The instance should be ready for service 5 minutes after receiving this email.</p>

<p>If this was a Windows instance an RDP connection file has been attached to this email named "$Name.rdp"</p>

<p>This instance has been registered in DNS with the folloing FQDN: $Name.fredhutch.center</p>

<p>Please login as "Administrator" with the temporary password of "$Password". Please change this password as soon as possible.</p>

Here are the details of this new instance:<br>

<pre>$ReportBody</pre>
</body></html>
"@
}
Else {
# Create an send an RDP profile if it's a new Window Instance
$RdpProfile = @"
auto connect:i:1
full address:s:$PrivateIp
username:s:Administrator
"@
    $RdpFile = "C:\Temp\$Name.rdp"
    Set-Content -Path $RdpFile -Value $RdpProfile

# This is the report that will be sent to the technical contact
$Report = @"
<html><head><title>EC2 Instance Provisioned</title></head>
<body>
<p>EC2 instance $Name ($InstanceID) has been created. The instance should be ready for service 5 minutes after receiving this email.</p>

<p>If this was a Windows instance an RDP connection file has been attached to this email named "$Name.rdp"</p>

<p>Please login as "Administrator" with the temporary password of "$Password". Please change this password as soon as possible.</p>

Here are the details of this new instance:<br>

<pre>$ReportBody</pre>
</body></html>
"@
}


# Provide some feedback and send email report to Technical contact
Write-Host "Successfully created EC2 instance $Name ($InstanceId)" -ForegroundColor Green
Send-MailMessage -To $TechContact -From "EC2provisioner@fredhutch.org" -BodyAsHtml $Report -SmtpServer "mx.fhcrc.org" -Subject "Amazon EC2 Instance $Name ($InstanceId) Provisioned: $(Get-Date)" -Attachments $RdpFile 
Write-Host "Sent and email to the Technical Contact ($TechContact) with the instance details" -ForegroundColor Green

#$State = Stop-EC2Instance -Instance $InstanceId -Terminate -Force

# Remove the temp key we don't need (since we set the Administrator password)
Write-Host "Removing Temporary Key-Pair..."
Remove-EC2KeyPair -KeyName $KeyName -Region $Region -Force

Write-Host ""
Write-Host "This instance is now configuring itself with the base configuration provided by the 'UserData' script" -ForegroundColor Yellow 
Write-Host "After configuration is complete the instance will reboot." -ForegroundColor Yellow
Write-Host "Please wait 5 minutes before attempting to connect to this instance." -ForegroundColor Yellow

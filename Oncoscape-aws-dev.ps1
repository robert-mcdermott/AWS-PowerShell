Param(

    [string]$Region = 'us-west-2',
    [string]$VPCID = 'vpc-ea72568f',
    [string]$AZaSubId = 'subnet-64dc8213',
    [string]$AZbSubId = 'subnet-3188b054',
    [string]$EnvName = 'oncoscape-dev',
    [string]$InstanceType = 't2.medium',
    [string]$RootVolSize = "100",
    [string]$RootVolType = "gp2",
    [string]$RootVolDelOnTerminate = "true",
    [string]$Password = "********",

    
    [ValidatePattern('^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/([0-9]|[1-2][0-9]|3[0-2]))$')]
    [string]$Public = '0.0.0.0/0',
    
    [ValidatePattern('^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/([0-9]|[1-2][0-9]|3[0-2]))$')]
    [string]$Center = '140.107.0.0/16'

)

Import-Module AwsPowerShell

Write-Host "Start: $(Get-Date)" -ForegroundColor White -BackgroundColor Black

# Creating ELB Security Group and rules
Write-Host "Creating $EnvName ELB Security Group and Rules (Firewall)"
$hush = New-EC2SecurityGroup -Region $Region -Description "Oncoscape ELB SG" -GroupName "${EnvName}_elb_sg" -VpcId $VPCID
$ElbSG = Get-EC2SecurityGroup -Region $Region |Where-Object {$_.GroupName -eq "${EnvName}_elb_sg"}
$ElbSGID = $ElbSG.GroupId
$ElbRule1 = New-Object Amazon.EC2.Model.IpPermission
$ElbRule1.IpProtocol='tcp'
$ElbRule1.FromPort = 80
$ElbRule1.ToPort = 80
$ElbRule1.IpRanges = $Public
$ElbRule2 = New-Object Amazon.EC2.Model.IpPermission
$ElbRule2.IpProtocol='tcp'
$ElbRule2.FromPort = 443
$ElbRule2.ToPort = 443
$ElbRule2.IpRanges = $Public
Grant-EC2SecurityGroupIngress -Region $Region -GroupId $ElbSGID -IpPermissions $ElbRule1, $ElbRule2
Start-sleep -Seconds 5
$NameTag = New-Object Amazon.EC2.Model.Tag
$NameTag.Key = "Name"
$NameTag.Value = "$EnvName ELB SG"
New-EC2Tag -Resources $ElbSGID -Tag $NameTag -Region $Region


# Creating Oncoscape host Security Group and rules
Write-Host "Creating $EnvName Host Security Group and Rules (Firewall)"
$hush = New-EC2SecurityGroup -Region $Region -Description "Oncoscape Host SG" -GroupName "${EnvName}_host_sg" -VpcId $VPCID
$HostSG = Get-EC2SecurityGroup -Region $Region |Where-Object {$_.GroupName -eq "${EnvName}_host_sg"}
$HostSGID = $HostSG.GroupId
$HostRule1 = New-Object Amazon.EC2.Model.IpPermission
$HostRule1.IpProtocol='-1'
$HostRule1.FromPort = 0
$HostRule1.ToPort = 65535
$HostRule1.IpRanges = $Center

$ElbGrp = New-Object Amazon.EC2.Model.UserIdGroupPair
$ElbGrp.GroupId = $ElbSGID
$HostRule2 = New-Object Amazon.EC2.Model.IpPermission
$HostRule2.IpProtocol='tcp'
$HostRule2.FromPort = 80
$HostRule2.ToPort = 80
$HostRule2.UserIdGroupPair = $ElbGrp
$HostGrp = New-Object Amazon.EC2.Model.UserIdGroupPair
$HostGrp.GroupId = $HostSGID
$HostRule3 = New-Object Amazon.EC2.Model.IpPermission
$HostRule3.IpProtocol='-1'
$HostRule3.FromPort = 0
$HostRule3.ToPort = 65535
$HostRule3.UserIdGroupPair = $HostGrp
$HostRule4 = New-Object Amazon.EC2.Model.IpPermission
$HostRule4.IpProtocol='tcp'
$HostRule4.FromPort = 443
$HostRule4.ToPort = 443
$HostRule4.UserIdGroupPair = $ElbGrp
Grant-EC2SecurityGroupIngress -Region $Region -GroupId $HostSGID -IpPermissions $HostRule1, $HostRule2, $HostRule3, $HostRule4
Start-sleep -Seconds 5
$NameTag = New-Object Amazon.EC2.Model.Tag
$NameTag.Key = "Name"
$NameTag.Value = "$EnvName Host SG"
New-EC2Tag -Resources $HostSGID -Tag $NameTag -Region $Region
Start-Sleep -Seconds 15

# Create a new temporary key for the instance
Write-Host "Generating Temporary Key-Pair $EnvName.pem..."
$Key = New-EC2KeyPair -KeyName "$EnvName.pem" -Region $Region
$Key.KeyMaterial|Out-File -FilePath "C:\Temp\$EnvName.pem"

Write-Host "Creating Oncoscape hosts now..."

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


# Find latest Unbuntu 14.04 AMI
Write-Host "Finding latest Unbuntu 14.04 AMI..."
$ImageID = Get-EC2Image -Region $Region|
    Where-Object {$_.RootDeviceType -eq 'ebs' -and $_.Name -like "ubuntu/images/hvm-ssd/ubuntu-trusty-14.04-amd64-server-*" -and $_.State -eq 'available'}|
    Sort-Object -Property CreationDate -Descending|
    Select-Object -First 1 -ExpandProperty ImageID
Write-Host "Selected Ubuntu 14.04 AMI: $ImageID"



# Creating first Oncoscape Host
# Userdata script to configure servers
$UserData = (Invoke-WebRequest -Uri https://raw.githubusercontent.com/robert-mcdermott/AWS-PowerShell/master/user-data/base-ubuntu.txt).content
$UserData = $UserData -replace "<password>","$Password"
$UserData = $UserData -replace "<hostname>","$EnvName-a"
# The user-data needs to be Base64 encoded
$UserData = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($UserData))


Write-Host "Attempting to create the first $EnvName host..."
Try {
    $ReservationA = New-EC2Instance -Region $Region -ImageId $ImageID -Monitoring_Enabled $True -KeyName "$EnvName.pem" -InstanceType $InstanceType -MinCount 1 -MaxCount 1 -UserData $UserData -SubnetId $AZaSubId -SecurityGroupIds $HostSGID -BlockDeviceMapping $RootVolMapping
    Write-Host "Successfully launched the first $EnvName host!" -ForegroundColor Green

    # Wait a bit for the system to catch up, ran into occasional tagging errors without this
    Write-Host "Waiting for instance to boot..."
    Start-Sleep -Seconds 15
}
Catch {
   Write-Host "Error Creating Instance:`n$($_.Exception.Message)" -ForegroundColor Red
   Exit(1)
}

$HostA = $ReservationA.RunningInstance[0]
$HostIdA = $HostA.InstanceId

Start-Sleep -Seconds 10

# Tag the new instance
Write-Host "Tagging the Instance..."
$NameTag = New-Object Amazon.EC2.Model.Tag
$NameTag.Key = "Name"
$NameTag.Value = "oncoscape-dev-a"
New-EC2Tag -Resources $HostIdA -Tag $NameTag -Region $Region

$OwnerTag = New-Object Amazon.EC2.Model.Tag
$OwnerTag.Key = "owner"
$OwnerTag.Value = "_hb/sttr"
New-EC2Tag -Resources $HostIdA -Tag $OwnerTag -Region $Region

$TechContactTag = New-Object Amazon.EC2.Model.Tag
$TechContactTag.Key = "technical_contact"
$TechContactTag.Value = "rmcdermo@fredhutch.org"
New-EC2Tag -Resources $HostIdA -Tag $TechContactTag -Region $Region

$BillingContactTag = New-Object Amazon.EC2.Model.Tag
$BillingContactTag.Key = "billing_contact"
$BillingContactTag.Value = "cloudops@fredhutch.org"
New-EC2Tag -Resources $HostIdA -Tag $BillingContactTag -Region $Region

$DescriptionTag = New-Object Amazon.EC2.Model.Tag
$DescriptionTag.Key = "description"
$DescriptionTag.Value = "Oncoscape public development host"
New-EC2Tag -Resources $HostIdA -Tag $DescriptionTag -Region $region

$Sle = "business_hours=24x7 / grant_critical=no / phi=no / pii=no / publicly_accessible=yes"
$SleTag = New-Object Amazon.EC2.Model.Tag
$SleTag.Key = "sle"
$SleTag.Value = $Sle
New-EC2Tag -Resources $HostIdA -Tag $SleTag -Region $region

# Add and Alert to this instance
Write-Host "Setting up CloudWatch monitoring and Alerting..."
$Dimension = New-Object "Amazon.CloudWatch.Model.Dimension"
$Dimension.Name = 'InstanceId'
$Dimension.Value = $HostIdA
Write-CWMetricAlarm -AlarmName "oncoscape-dev-a_CPU" `
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


# Creating second Oncoscape Host

# Userdata script to configure servers
$UserData = (Invoke-WebRequest -Uri https://raw.githubusercontent.com/robert-mcdermott/AWS-PowerShell/master/user-data/base-ubuntu.txt).content
$UserData = $UserData -replace "<password>","$Password"
$UserData = $UserData -replace "<hostname>","$EnvName-b"
# The user-data needs to be Base64 encoded
$UserData = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($UserData))


Write-Host "Attempting to create the second $EnvName host..."
Try {
    $ReservationB = New-EC2Instance -Region $Region -ImageId $ImageID -Monitoring_Enabled $True -KeyName "$EnvName.pem" -InstanceType $InstanceType -MinCount 1 -MaxCount 1 -UserData $UserData -SubnetId $AZbSubId -SecurityGroupIds $HostSGID -BlockDeviceMapping $RootVolMapping
    Write-Host "Successfully launched the Second $EnvName host!" -ForegroundColor Green

    # Wait a bit for the system to catch up, ran into occasional tagging errors without this
    Write-Host "Waiting for instance to boot..."
    Start-Sleep -Seconds 15
}
Catch {
   Write-Host "Error Creating Instance:`n$($_.Exception.Message)" -ForegroundColor Red
   Exit(1)
}

$HostB = $ReservationB.RunningInstance[0]
$HostIdB = $HostB.InstanceId

Start-Sleep -Seconds 10

# Tag the new instance
Write-Host "Tagging the Instance..."
$NameTag = New-Object Amazon.EC2.Model.Tag
$NameTag.Key = "Name"
$NameTag.Value = "oncoscape-dev-b"
New-EC2Tag -Resources $HostIdB -Tag $NameTag -Region $Region

$OwnerTag = New-Object Amazon.EC2.Model.Tag
$OwnerTag.Key = "owner"
$OwnerTag.Value = "_adm/solarch"
New-EC2Tag -Resources $HostIdB -Tag $OwnerTag -Region $Region

$TechContactTag = New-Object Amazon.EC2.Model.Tag
$TechContactTag.Key = "technical_contact"
$TechContactTag.Value = "rmcdermo@fredhutch.org"
New-EC2Tag -Resources $HostIdB -Tag $TechContactTag -Region $Region

$BillingContactTag = New-Object Amazon.EC2.Model.Tag
$BillingContactTag.Key = "billing_contact"
$BillingContactTag.Value = "cloudops@fredhutch.org"
New-EC2Tag -Resources $HostIdB -Tag $BillingContactTag -Region $Region

$DescriptionTag = New-Object Amazon.EC2.Model.Tag
$DescriptionTag.Key = "description"
$DescriptionTag.Value = "Oncoscape public development host"
New-EC2Tag -Resources $HostIdB -Tag $DescriptionTag -Region $region

$Sle = "business_hours=24x7 / grant_critical=no / phi=no / pii=no / publicly_accessible=yes"
$SleTag = New-Object Amazon.EC2.Model.Tag
$SleTag.Key = "sle"
$SleTag.Value = $Sle
New-EC2Tag -Resources $HostIdB -Tag $SleTag -Region $region

# Add and Alert to this instance
Write-Host "Setting up CloudWatch monitoring and Alerting..."
$Dimension = New-Object "Amazon.CloudWatch.Model.Dimension"
$Dimension.Name = 'InstanceId'
$Dimension.Value = $HostIdB
Write-CWMetricAlarm -AlarmName "oncoscape-dev-b_CPU" `
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


# Setting up ELB
Write-Host "Creating Elastic Load Balancer" 
$HTTP = New-Object "Amazon.ElasticLoadBalancing.Model.Listener"
$HTTP.Protocol = 'tcp'
$HTTP.LoadBalancerPort = 80
$HTTP.InstancePort = 80

$hush = New-ELBLoadBalancer -Region $Region -LoadBalancerName "$EnvName-elb" -Subnets $AZaSubId, $AZbSubId -Listeners $HTTP -SecurityGroups $ElbSGID
$ELB = Get-ELBLoadBalancer -Region $Region -LoadBalancerName "$EnvName-elb"
$ELBdns = $ELB.DNSName
$hush = Set-ELBHealthCheck -Region $Region -LoadBalancerName "$EnvName-elb" -HealthCheck_Target 'HTTP:80/' -HealthCheck_Interval 30 -HealthCheck_Timeout 10 -HealthCheck_HealthyThreshold 2 -HealthCheck_UnhealthyThreshold 2

# wait a bit so the load balancer is ready
Start-Sleep -Seconds 30
$hush = Register-ELBInstanceWithLoadBalancer -Region $Region -LoadBalancerName "$EnvName-elb" -Instances $HostIdA, $HostIdB

Write-Host "Registering ELB $ELBdns as CNAME 'dev01' in the 'sttrcancer.io' DNS Zone..."
$Zone = "sttrcancer.io."
$Type = "CNAME"
$HostedZone = Get-R53HostedZones |Where-Object {$_.Name -eq $Zone}

$ResourceRecordSet = New-Object -TypeName Amazon.Route53.Model.ResourceRecordSet
$ResourceRecordSet.Name = 'dev01.sttrcancer.io.'
$ResourceRecordSet.Type = $Type
$ResourceRecordSet.TTL = 10
$ResourceRecordSet.ResourceRecords.Add($ELBdns)

$Change = New-Object -TypeName Amazon.Route53.Model.Change
$Change.Action = "UPSERT"
$Change.ResourceRecordSet = $ResourceRecordSet
Try {
    $Result = Edit-R53ResourceRecordSet -HostedZoneId $HostedZone.Id -ChangeBatch_Change $Change
    Write-Host "DNS Registration Successful!" -ForegroundColor Green
}
Catch {
        Write-Host "Error registering instance in Route53 DNS:`n$($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "All Done! The Oncoscape development website will be availible at dev01.sttrcancer.io ($ELBdns) in about 15 minutes" -ForegroundColor Green

# Send a SMS message to Robert's iPhone
$Message = "$EnvName AWS build complete"
$hush = Publish-SNSMessage -Region us-east-1 -TopicArn "arn:aws:sns:us-east-1:458818213009:EC2_ALERT" -Message $Message

# Remove the temp key we don't need (since we set the Administrator password)
Write-Host "Removing Temporary Key-Pair..."
Remove-EC2KeyPair -KeyName "$EnvName.pem" -Region $Region -Force

Write-Host ""
Write-Host "This instance is now configuring itself with the base configuration provided by the 'UserData' script" -ForegroundColor Yellow 
Write-Host "After configuration is complete the instance will reboot." -ForegroundColor Yellow
Write-Host "Please wait at least 5 minutes before attempting to connect to this instance." -ForegroundColor Yellow

Write-Host "Stop: $(Get-Date)" -ForegroundColor White -BackgroundColor Black
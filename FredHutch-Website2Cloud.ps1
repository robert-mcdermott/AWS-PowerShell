Param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("us-east-1", "us-west-1", "us-west-2", 
                 "eu-west-1", "eu-central-1", "ap-northeast-1",
                 "ap-southeast-1", "ap-southeast-2", "sa-east-1")]
    
    [string]$Region,
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/([0-9]|[1-2][0-9]|3[0-2]))$')]
    [string]$CIDR,

    [ValidatePattern('^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/([0-9]|[1-2][0-9]|3[0-2]))$')]
    [string]$Firewall_Allow_CIDR = '140.107.0.0/16',

    [Parameter(Mandatory=$true)]
    [string]$VPCName
)

Write-Host "Start: $(Get-Date)" -ForegroundColor White -BackgroundColor Black
$AZs = Get-EC2AvailabilityZone -Region $Region|Sort-Object -Property ZoneName
$AZa = $AZs[0]|Select-Object -ExpandProperty ZoneName
$AZb = $AZs[1]|Select-Object -ExpandProperty ZoneName
#$AZc = AZs[2]|Select-Object -ExpandProperty ZoneName

$AZaCIDR = ($CIDR -split "/")[0] + "/23"
$AZbCIDR = (($AZaCIDR -split "\.")[0..1] -join ".") + ".2.0/23"
#$AZcCIDR = (($AZaCIDR -split "\.")[0..1] -join ".") + ".4.0/23"

# Create the VPC
Write-Host "Creating VPC"
$VPC = New-EC2Vpc -Region $Region -CidrBlock $CIDR
$VPCID = $VPC.VpcId
Start-Sleep -Seconds 2
$hush = Edit-EC2VpcAttribute -Region $Region -VpcId $VPCID -EnableDnsSupport $true
$hush = Edit-EC2VpcAttribute -Region $Region -VpcId $VPCID -EnableDnsHostnames $true
Start-sleep -Seconds 2
$NameTag = New-Object Amazon.EC2.Model.Tag
$NameTag.Key = "Name"
$NameTag.Value = $VPCName
New-EC2Tag -Resources $VPCID -Tag $NameTag -Region $Region
Start-Sleep -Seconds 15


# Create three subnets in the new VPC, one in each AZ
Write-Host "Creating Subnets"
$AZaSub = New-EC2Subnet -Region $Region -VpcId $VPCID -CidrBlock $AZaCIDR  -AvailabilityZone $AZa
$AZaSubId = $AZaSub.SubnetId
$hush = Edit-EC2SubnetAttribute -Region $Region -MapPublicIpOnLaunch $true -SubnetId $AZaSubId
Start-sleep -Seconds 5
$NameTag = New-Object Amazon.EC2.Model.Tag
$NameTag.Key = "Name"
$NameTag.Value = "$VPCName Public $($AZa[-1])"
New-EC2Tag -Resources $AZaSubId -Tag $NameTag -Region $Region


$AZbSub = New-EC2Subnet -Region $Region -VpcId $VPCID -CidrBlock $AZbCIDR -AvailabilityZone $AZb
$AZbSubId = $AZbSub.SubnetId
$hush = Edit-EC2SubnetAttribute -Region $Region -MapPublicIpOnLaunch $true -SubnetId $AZbSubId
Start-sleep -Seconds 5
$NameTag = New-Object Amazon.EC2.Model.Tag
$NameTag.Key = "Name"
$NameTag.Value = "$VPCName Public $($AZb[-1])"
New-EC2Tag -Resources $AZbSubId -Tag $NameTag -Region $Region

#$AZcSub = New-EC2Subnet -Region $Region -VpcId $VPCID -CidrBlock $AZcCIDR -AvailabilityZone $AZc
#$AZcSubId = $AZcSub.SubnetId
#$hush = Edit-EC2SubnetAttribute -Region $Region -MapPublicIpOnLaunch $true -SubnetId $AZcSubId
#Start-sleep -Seconds 5
#$NameTag = New-Object Amazon.EC2.Model.Tag
#$NameTag.Key = "Name"
#$NameTag.Value = "$VPCName Public $($AZc[-1])"
#New-EC2Tag -Resources $AZcSubId -Tag $NameTag -Region $Region
Start-Sleep -Seconds 15

# Create the Internet Gateway and attach to the VPC
Write-Host "Creating Internet Gateway"
$IG = New-EC2InternetGateway -Region $Region
$IGID = $IG.InternetGatewayId
Add-EC2InternetGateway -Region $Region -InternetGatewayId $IGID -VpcId $VPCID
Start-sleep -Seconds 5
$NameTag = New-Object Amazon.EC2.Model.Tag
$NameTag.Key = "Name"
$NameTag.Value = "$VPCName IGW"
New-EC2Tag -Resources $IGID -Tag $NameTag -Region $Region
Start-Sleep -Seconds 15

# Create new route table
$RT = New-EC2RouteTable -Region $Region -VpcId $VPCID
$RTID = $RT.RouteTableId
New-EC2Route -Region $Region -RouteTableId $RTID -DestinationCidrBlock '0.0.0.0/0' -GatewayId $IGID

$hush = Register-EC2RouteTable -Region $Region -RouteTableId $RTID -SubnetId $AZaSubId
$hush = Register-EC2RouteTable -Region $Region -RouteTableId $RTID -SubnetId $AZbSubId
#$hush = Register-EC2RouteTable -Region $Region -RouteTableId $RTID -SubnetId $AZcSubId
Start-sleep -Seconds 5
$NameTag = New-Object Amazon.EC2.Model.Tag
$NameTag.Key = "Name"
$NameTag.Value = "$VPCName RT"
New-EC2Tag -Resources $RTID -Tag $NameTag -Region $Region
Start-Sleep -Seconds 5

# Create Network ACL
Write-Host "Creating Network ACLs"
$NACL = New-EC2NetworkAcl -Region $Region -VpcId $VPCID
$NACLID = $NACL.NetworkAclId
# Outbound ACLs
#ICMP
New-EC2NetworkAclEntry -Region $Region -NetworkAclId $NACLID -RuleNumber 100 -CidrBlock '0.0.0.0/0' -Egress $true -PortRange_From 0 -PortRange_To 65535 -Protocol '1' -RuleAction 'Allow' -IcmpTypeCode_Code '-1' -IcmpTypeCode_Type '-1'
#TCP
New-EC2NetworkAclEntry -Region $Region -NetworkAclId $NACLID -RuleNumber 110 -CidrBlock '0.0.0.0/0' -Egress $true -PortRange_From 0 -PortRange_To 65535 -Protocol '6' -RuleAction 'Allow'
#UDP
New-EC2NetworkAclEntry -Region $Region -NetworkAclId $NACLID -RuleNumber 120 -CidrBlock '0.0.0.0/0' -Egress $true -PortRange_From 0 -PortRange_To 65535 -Protocol '17' -RuleAction 'Allow'
# Inbound ACLs
#ICMP
New-EC2NetworkAclEntry -Region $Region -NetworkAclId $NACLID -RuleNumber 100 -CidrBlock '0.0.0.0/0' -Egress $false -PortRange_From 0 -PortRange_To 65535 -Protocol '1' -RuleAction 'Allow' -IcmpTypeCode_Code '-1' -IcmpTypeCode_Type '-1'
#TCP
New-EC2NetworkAclEntry -Region $Region -NetworkAclId $NACLID -RuleNumber 110 -CidrBlock '0.0.0.0/0' -Egress $false -PortRange_From 0 -PortRange_To 65535 -Protocol '6' -RuleAction 'Allow'
#UDP
New-EC2NetworkAclEntry -Region $Region -NetworkAclId $NACLID -RuleNumber 120 -CidrBlock '0.0.0.0/0' -Egress $false -PortRange_From 0 -PortRange_To 65535 -Protocol '17' -RuleAction 'Allow'
Start-sleep -Seconds 5
$NameTag = New-Object Amazon.EC2.Model.Tag
$NameTag.Key = "Name"
$NameTag.Value = "$VPCName NACL"
New-EC2Tag -Resources $NACLID -Tag $NameTag -Region $Region
Start-Sleep -Seconds 15


# Associate the NACL with our Subnets
Write-Host "Associateing NACLs with our Subnets"
$VPCFilter = New-Object Amazon.EC2.Model.Filter
$VPCFilter.Name = 'vpc-id'
$VPCFilter.Value = $VPCID
$DefaultFilter = New-Object Amazon.EC2.Model.Filter
$DefaultFilter.Name = 'default'
$DefaultFilter.Value = 'true'
$CurACL = (Get-EC2NetworkAcl -Region $Region -Filter $VPCFilter, $DefaultFilter)
$CurAssociation_a = $CurACL.Associations |Where-Object {$_.SubnetId -eq $AZaSubId}
$CurAssociation_b = $CurACL.Associations |Where-Object {$_.SubnetId -eq $AZbSubId}
#$CurAssociation_c = $CurACL.Associations |Where-Object {$_.SubnetId -eq $AZcSubId}
$hush = Set-EC2NetworkAclAssociation -Region $Region -AssociationId $CurAssociation_a.NetworkAclAssociationId -NetworkAclId $NACLID
$hush = Set-EC2NetworkAclAssociation -Region $Region -AssociationId $CurAssociation_b.NetworkAclAssociationId -NetworkAclId $NACLID
#$hush = Set-EC2NetworkAclAssociation -Region $Region -AssociationId $CurAssociation_c.NetworkAclAssociationId -NetworkAclId $NACLID
Start-Sleep -Seconds 15

# Creating Security Group and rules
Write-Host "Greating Security Group and Rules (Firewall)"
$hush = New-EC2SecurityGroup -Region $Region -Description "Wide open from $Firewall_Allow_CIDR" -GroupName "$VPCName SG" -VpcId $VPCID
$SG = Get-EC2SecurityGroup -Region $Region |Where-Object {$_.GroupName -eq "$VPCName SG"}
$SGID = $SG.GroupId
$Rule1 = New-Object Amazon.EC2.Model.IpPermission
$Rule1.IpProtocol='-1'
$Rule1.FromPort = 0
$Rule1.ToPort = 65535
$Rule1.IpRanges = $Firewall_Allow_CIDR
Grant-EC2SecurityGroupIngress -Region $Region -GroupId $SGID -IpPermission $Rule1
Start-sleep -Seconds 5
$NameTag = New-Object Amazon.EC2.Model.Tag
$NameTag.Key = "Name"
$NameTag.Value = "$VPCName SG"
New-EC2Tag -Resources $SGID -Tag $NameTag -Region $Region
Start-Sleep -Seconds 15

# Creating DHCP options configuration
Write-Host "Creating and registering DHCP options"
$Domain = New-Object Amazon.EC2.Model.DhcpConfiguration
$Domain.Key = 'domain-name'
$Domain.Value = "${Region}.compute.internal"
$DNS = New-Object Amazon.EC2.Model.DhcpConfiguration
$DNS.Key = 'domain-name-servers'
$DNS.Value = 'AmazonProvidedDNS'
$DHCP = New-EC2DhcpOption -Region $Region -DhcpConfiguration $Domain, $DNS
$DHCPID = $DHCP.DhcpOptionsId
Register-EC2DhcpOption -Region $Region -DhcpOptionsId $DHCPID -VpcId $VPCID
Start-sleep -Seconds 5
$NameTag = New-Object Amazon.EC2.Model.Tag
$NameTag.Key = "Name"
$NameTag.Value = "$VPCName DHCP"
New-EC2Tag -Resources $DHCPID -Tag $NameTag -Region $Region

Write-Host "Virtual datacenter $VPCName complete!" -ForegroundColor Green
Write-Host "Creating webservers now..."

# Find latest Amazon Linux AMI
Write-Host "Finding latest Amazon Linux AMI..."
$ImageID = Get-EC2Image -Region $Region|
    Where-Object {$_.ImageOwnerAlias -eq "amazon" -and $_.VirtualizationType -eq 'hvm' -and $_.RootDeviceType -eq 'ebs' -and $_.Architecture -eq 'x86_64' -and $_.Description -like "Amazon Linux AMI 20*x86_64 HVM GP2" -and $_.State -eq 'available'}|
    Sort-Object -Property CreationDate -Descending|
    Select-Object -First 1 -ExpandProperty ImageID
Write-Host "Selected AMI Image: $ImageID"

# Create and configure the root volume
$RootVol = New-Object Amazon.EC2.Model.EbsBlockDevice
$RootVol.DeleteOnTermination = $true
$RootVol.VolumeSize = 15
$RootVol.VolumeType = 'gp2'
$RootVolMapping = New-Object Amazon.EC2.Model.BlockDeviceMapping
$RootVolMapping.DeviceName = '/dev/xvda'
$RootVolMapping.Ebs = $RootVol

# Create a key for the instances
$KeyName = "$VPCName.pem"
Write-Host "Generating Key-Pair $KeyName..."
$Key = New-EC2KeyPair -KeyName "$KeyName" -Region $Region
$Key.KeyMaterial|Out-File -FilePath "C:\Temp\$VPCName.pem"

# Userdata script to configure web servers
$UserData = @"
#!/bin/bash
/usr/bin/yum -y install nginx
/bin/sed -i 's/\/usr\/share\/nginx\/html/\/var\/www\/www.fredhutch.org/g' /etc/nginx/nginx.conf
/sbin/chkconfig nginx on
/bin/mkdir -p /var/www
cd /var/www
/usr/bin/wget https://s3-us-west-2.amazonaws.com/cloud-onramp/www.fredhutch.org-2015-07-17.tar.gz
/bin/tar -zxf www.fredhutch.org-2015-07-17.tar.gz
/sbin/service nginx start
"@
# The user-data needs to be Base64 encoded
$UserData = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($UserData))

# Lets create the first web server instance
Write-Host "Attempting to create the first web server instance..."
Try {
    $ReservationA = New-EC2Instance -Region $Region -ImageId $ImageID -Monitoring_Enabled $True -KeyName $KeyName -InstanceType t2.small -MinCount 1 -MaxCount 1 -UserData $UserData -SubnetId $AZaSubId -SecurityGroupIds $SGID -BlockDeviceMapping $RootVolMapping
    Write-Host "Successfully launched the first web server instance!" -ForegroundColor Green

    # Wait a bit for the system to catch up, ran into occasional tagging errors without this
    Write-Host "Waiting for instance to boot..."
    Start-Sleep -Seconds 15
}
Catch {
   Write-Host "Error Creating Instance:`n$($_.Exception.Message)" -ForegroundColor Red
   Exit(1)
}

$InstanceA = $ReservationA.RunningInstance[0]
$InstanceIdA = $InstanceA.InstanceId

Start-Sleep -Seconds 10

# Tag the new instance
Write-Host "Tagging the Instance..."
$NameTag = New-Object Amazon.EC2.Model.Tag
$NameTag.Key = "Name"
$NameTag.Value = "fredhutch-web-a"
New-EC2Tag -Resources $InstanceIdA -Tag $NameTag -Region $Region

$OwnerTag = New-Object Amazon.EC2.Model.Tag
$OwnerTag.Key = "owner"
$OwnerTag.Value = "_adm/solarch"
New-EC2Tag -Resources $InstanceIdA -Tag $OwnerTag -Region $Region

$TechContactTag = New-Object Amazon.EC2.Model.Tag
$TechContactTag.Key = "technical_contact"
$TechContactTag.Value = "rmcdermo@fredhutch.org"
New-EC2Tag -Resources $InstanceIdA -Tag $TechContactTag -Region $Region

$BillingContactTag = New-Object Amazon.EC2.Model.Tag
$BillingContactTag.Key = "billing_contact"
$BillingContactTag.Value = "cloudops@fredhutch.org"
New-EC2Tag -Resources $InstanceIdA -Tag $BillingContactTag -Region $Region


# Lets create the second web server instance
Write-Host "Attempting to create the second web server instance..."
Try {
    $ReservationB = New-EC2Instance -Region $Region -ImageId $ImageID -Monitoring_Enabled $True -KeyName $KeyName -InstanceType t2.small -MinCount 1 -MaxCount 1 -UserData $UserData -SubnetId $AZbSubId -SecurityGroupIds $SGID -BlockDeviceMapping $RootVolMapping
    Write-Host "Successfully Launched the Second Web Server Instance!" -ForegroundColor Green

    # Wait a bit for the system to catch up, ran into occasional tagging errors without this
    Write-Host "Waiting for instance to boot..."
    Start-Sleep -Seconds 15
}
Catch {
   Write-Host "Error Creating Instance:`n$($_.Exception.Message)" -ForegroundColor Red
   Exit(1)
}

$InstanceB = $ReservationB.RunningInstance[0]
$InstanceIdB = $InstanceB.InstanceId

Start-Sleep -Seconds 10

# Tag the new instance
Write-Host "Tagging the Instance..."
$NameTag = New-Object Amazon.EC2.Model.Tag
$NameTag.Key = "Name"
$NameTag.Value = "fredhutch-web-b"
New-EC2Tag -Resources $InstanceIdB -Tag $NameTag -Region $Region

$OwnerTag = New-Object Amazon.EC2.Model.Tag
$OwnerTag.Key = "owner"
$OwnerTag.Value = "_adm/solarch"
New-EC2Tag -Resources $InstanceIdB -Tag $OwnerTag -Region $Region

$TechContactTag = New-Object Amazon.EC2.Model.Tag
$TechContactTag.Key = "technical_contact"
$TechContactTag.Value = "rmcdermo@fredhutch.org"
New-EC2Tag -Resources $InstanceIdB -Tag $TechContactTag -Region $Region

$BillingContactTag = New-Object Amazon.EC2.Model.Tag
$BillingContactTag.Key = "billing_contact"
$BillingContactTag.Value = "cloudops@fredhutch.org"
New-EC2Tag -Resources $InstanceIdB -Tag $BillingContactTag -Region $Region

# Setting up ELB
Write-Host "Creating Elastic Load Balancer" 
$HTTP = New-Object "Amazon.ElasticLoadBalancing.Model.Listener"
$HTTP.Protocol = 'http'
$HTTP.LoadBalancerPort = 80
$HTTP.InstancePort = 80

$hush = New-ELBLoadBalancer -Region $Region -LoadBalancerName "$VPCName-LB" -Subnets $AZaSubId, $AZbSubId -Listeners $HTTP -SecurityGroups $SGID
$ELB = Get-ELBLoadBalancer -Region $Region -LoadBalancerName "$VPCName-LB"
$ELBdns = $ELB.DNSName
$hush = Set-ELBHealthCheck -Region $Region -LoadBalancerName "$VPCName-LB" -HealthCheck_Target 'HTTP:80/en.html' -HealthCheck_Interval 30 -HealthCheck_Timeout 5 -HealthCheck_HealthyThreshold 2 -HealthCheck_UnhealthyThreshold 2

# wait a bit so the load balancer is ready
Start-Sleep -Seconds 30
$hush = Register-ELBInstanceWithLoadBalancer -Region $Region -LoadBalancerName "$VPCName-LB" -Instances $InstanceIdA, $InstanceIdB

Write-Host "Registering ELB $ELBdns as CNAME 'www' in the 'fredhutch.center' DNS Zone..."
$Zone = "fredhutch.center."
$Type = "CNAME"
$HostedZone = Get-R53HostedZones |Where-Object {$_.Name -eq $Zone}

$ResourceRecordSet = New-Object -TypeName Amazon.Route53.Model.ResourceRecordSet
$ResourceRecordSet.Name = 'www.fredhutch.center.'
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

Write-Host "All Done! $VPCName datacenter is up and running, Fredhutch public website will be availible at www.fredhutch.center ($ELBdns) in about 10 minutes" -ForegroundColor Green

# Send a SMS message to Robert's iPhone
$Message = "$VPCName cloud based datacenter complete. The public Hutch website is now availible at www.fredhutch.center"
Publish-SNSMessage -Region us-east-1 -TopicArn "arn:aws:sns:us-east-1:458818213009:EC2_ALERT" -Message $Message

Write-Host "Stop: $(Get-Date)" -ForegroundColor White -BackgroundColor Black
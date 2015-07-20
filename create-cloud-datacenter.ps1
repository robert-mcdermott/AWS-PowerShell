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

Write-Host "Done!" -ForegroundColor Green
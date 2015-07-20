$region = "us-west-2"
$subject = "FredHutch AWS Tag Minder: found instances missing mandatory tags"
$from = "FredHutchAWSTagMinder@fredhutch.org"
$to = "rmcdermo@fredhutch.org"


$state = @{n="State"; e={$_.State.Name}}
$security = @{n="SecurityGrps"; e={ForEach-Object {$_.SecurityGroups| Select-Object -ExpandProperty GroupId}}}
$zone =  @{n="AvailabilityZone"; e={$_.Placement.AvailabilityZone}}
$tenancy =  @{n="Tenancy"; e={$_.Placement.Tenancy}}
$platform = @{n="Platform"; e={if ($_.Platform -eq "Windows") {"windows"} else {"linux"}}}


# our 8 custom tags
$name = @{n="Name"; e={ForEach-Object {$_.Tags| Where-Object {$_.key -eq "Name"}| Select-Object -ExpandProperty Value}}}
$owner = @{n="owner"; e={ForEach-Object {$_.Tags| Where-Object {$_.key -eq "owner"}| Select-Object -ExpandProperty Value}}}
#$service = @{n="service"; e={ForEach-Object {$_.Tags| Where-Object {$_.key -eq "service"}| Select-Object -ExpandProperty Value}}}
$sle = @{n="sle"; e={ForEach-Object {$_.Tags| Where-Object {$_.key -eq "sle"}| Select-Object -ExpandProperty Value}}}
$bill = @{n="billing_contact"; e={ForEach-Object {$_.Tags| Where-Object {$_.key -eq "billing_contact"}| Select-Object -ExpandProperty Value}}}
$tech = @{n="technical_contact"; e={ForEach-Object {$_.Tags| Where-Object {$_.key -eq "technical_contact"}| Select-Object -ExpandProperty Value}}}
#$environment = @{n="environment"; e={ForEach-Object {$_.Tags| Where-Object {$_.key -eq "environment"}| Select-Object -ExpandProperty Value}}}
$description = @{n="description"; e={ForEach-Object {$_.Tags| Where-Object {$_.key -eq "description"}| Select-Object -ExpandProperty Value}}}


$bad_instances = Get-EC2Instance -Region $region|
  ForEach-Object {$psitem.RunningInstance}|
  #Select-Object -Property $name, InstanceId, InstanceType, ImageId, $state, PrivateIpAddress, PublicIpAddress,
  #$security, $zone, SubnetId, VpcId, $owner, $service, $environment, $tech, $bill, $description, $sle, $tenancy, LaunchTime, KeyName, $platform| 
  Select-Object -Property $name, InstanceId, InstanceType, ImageId, $state, PrivateIpAddress, PublicIpAddress,
  $security, $zone, SubnetId, VpcId, $owner, $tech, $bill, $description, $sle, $tenancy, LaunchTime, KeyName, $platform|
  Sort-Object -Property State|
  Where-Object {($_.owner -eq $null) -or ($_.owner -eq ".") -or ($_.billing_contact -eq $null) -or ($_.billing_contact -eq ".") -or ($_.technical_contact -eq $null) -or ($_.technical_contact -eq ".")}|
  Where-Object {$_.State -eq "running" -or $_.State -eq "stopped" }|
  Select-Object -Property InstanceId,Name,owner,billing_contact,technical_contact,State,AvailabilityZone,KeyName|Format-Table -AutoSize|Out-String

$body = "The following EC2 instances were found to be missing mandatory tags (owner and/or billing_contact. Please add the missing madatory tags as soon as possible to prevent the intance from being terminated:`r`n`r`n"

if ($bad_instances.Length -gt 0){
    $body += $bad_instances
    Send-MailMessage -SmtpServer mx.fhcrc.org -From $from -To $to -Subject $subject -Body $body
}
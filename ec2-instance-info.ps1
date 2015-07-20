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


Get-EC2Instance -Region us-west-2|
  ForEach-Object {$psitem.RunningInstance}|
  #Select-Object -Property $name, InstanceId, InstanceType, ImageId, $state, PrivateIpAddress, PublicIpAddress,
  #$security, $zone, SubnetId, VpcId, $owner, $service, $environment, $tech, $bill, $description, $sle, $tenancy, LaunchTime, KeyName, $platform| 
  Select-Object -Property $name, InstanceId, InstanceType, ImageId, $state, PrivateIpAddress, PublicIpAddress,
  $security, $zone, SubnetId, VpcId, $owner, $tech, $bill, $description, $sle, $tenancy, LaunchTime, KeyName, $platform| 
  Sort-Object -Property State
  
  #Where-Object { $_.SecurityGrps -like "sg-981*"}
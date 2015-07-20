$AllTags = Get-EC2Tag -Region us-west-2
 
Function Rectify-Tag {
    #This function only updates a tag if the current value is not correct
    Param ($ResourceId, $Tag)
    #Find the current tag in the cached collection
    $OldTag = $AllTags | Where-Object {(($_.ResourceId -eq $ResourceId) -and ($_.Key -eq $Tag.Key))}
    If(($OldTag -eq $null) -or ($OldTag.Value -ne $Tag.Value)) {
        #The currrent tag is wrong, let's fix it.
        New-EC2Tag -Resources $ResourceId -Tag $Tag -Region us-west-2
    }
}
 
(Get-EC2Instance  -Region us-west-2).Instances | ForEach-Object {
 
    $Instance = $_
 
    #First, get the tags from each instance
    $Name = $Instance.Tags | Where-Object { $_.Key -eq 'Name' }
    $Owner = $Instance.Tags | Where-Object { $_.Key -eq 'owner' }
    #$Service = $Instance.Tags | Where-Object { $_.Key -eq 'service' }
    $TechContact = $Instance.Tags | Where-Object { $_.Key -eq 'technical_contact' }
    #$Environment = $Instance.Tags | Where-Object { $_.Key -eq 'environment' }
    $Description = $Instance.Tags | Where-Object { $_.Key -eq 'description' }
    $BillingContact = $Instance.Tags | Where-Object { $_.Key -eq 'billing_contact' }
    $Sle = $Instance.Tags | Where-Object { $_.Key -eq 'sle' }
    $BackupEnabled = $Instance.Tags | Where-Object { $_.Key -eq 'backup_enabled' }

 
    $Instance.BlockDeviceMappings | ForEach-Object {
        #Copy the tags to each volume
        If($Name -ne $null) {Rectify-Tag -ResourceId $_.Ebs.VolumeId -Tag $Name}
        If($Owner -ne $null) {Rectify-Tag -ResourceId $_.Ebs.VolumeId -Tag $Owner}
        #If($Service -ne $null) {Rectify-Tag -ResourceId $_.Ebs.VolumeId -Tag $Service}
        If($TechContact -ne $null) {Rectify-Tag -ResourceId $_.Ebs.VolumeId -Tag $TechContact}
        #If($Environment -ne $null) {Rectify-Tag -ResourceId $_.Ebs.VolumeId -Tag $Environment}
        If($Description -ne $null) {Rectify-Tag -ResourceId $_.Ebs.VolumeId -Tag $Description}
        If($BillingContact -ne $null) {Rectify-Tag -ResourceId $_.Ebs.VolumeId -Tag $BillingContact}
        If($Sle -ne $null) {Rectify-Tag -ResourceId $_.Ebs.VolumeId -Tag $Sle}
        If($BackupEnabled -ne $null) {Rectify-Tag -ResourceId $_.Ebs.VolumeId -Tag $BackupEnabled}
 
    }
 
    $Instance.NetworkInterfaces | ForEach-Object {
        #Copy the tags to each NIC
        If($Name -ne $null) {Rectify-Tag -ResourceId $_.NetworkInterfaceId -Tag $Name}
        If($Owner -ne $null) {Rectify-Tag -ResourceId $_.NetworkInterfaceId -Tag $Owner}
        #If($Service -ne $null) {Rectify-Tag -ResourceId $_.NetworkInterfaceId -Tag $Service}
        If($TechContact -ne $null) {Rectify-Tag -ResourceId $_.NetworkInterfaceId -Tag $TechContact}
        #If($Environment -ne $null) {Rectify-Tag -ResourceId $_.NetworkInterfaceId -Tag $Environment}
        If($Description -ne $null) {Rectify-Tag -ResourceId $_.NetworkInterfaceId -Tag $Description}
        If($BillingContact -ne $null) {Rectify-Tag -ResourceId $_.NetworkInterfaceId -Tag $BillingContact}
        If($Sle -ne $null) {Rectify-Tag -ResourceId $_.NetworkInterfaceId -Tag $Sle}
    }
}

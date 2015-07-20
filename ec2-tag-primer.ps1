$region = "us-west-2"
$subject = "FredHutch AWS Tagger: found untagged EC2 instances, tagging them"
$from = "FredHutchAWSTagger@fredhutch.org"
$to = "rmcdermo@fredhutch.org"

$report = @{}

(Get-EC2Instance  -Region $region).Instances | ForEach-Object {
 
    $seeded = @()
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


    If ($Name -eq $null -or $Name.Value -eq $null) {
        #The currrent tag is missing, lets create a stub.
        $NameTag = New-Object Amazon.EC2.Model.Tag
        $NameTag.Key = "Name"
        $NameTag.Value = "."
        New-EC2Tag -Resources $Instance.InstanceID -Tag $NameTag -Region $region
        $seeded += "Name" 
    }

    If ($Owner -eq $null -or $Owner.Value -eq $null) {
        #The currrent tag is missing, lets create a stub.
        $OwnerTag = New-Object Amazon.EC2.Model.Tag
        $OwnerTag.Key = "owner"
        $OwnerTag.Value = "."
        New-EC2Tag -Resources $Instance.InstanceID -Tag $OwnerTag -Region $region
        $seeded += "owner"
    }

    #If ($Service -eq $null -or $Service.Value -eq $null) {
    #    #The currrent tag is missing, lets create a stub.
    #    $ServiceTag = New-Object Amazon.EC2.Model.Tag
    #    $ServiceTag.Key = "service"
    #    $ServiceTag.Value = "."
    #    New-EC2Tag -Resources $Instance.InstanceID -Tag $ServiceTag -Region $region
    #    $seeded += "service"
    #}

    If ($TechContact -eq $null -or $TechContact.Value -eq $null) {
        #The currrent tag is missing, lets create a stub.
        $TechContactTag = New-Object Amazon.EC2.Model.Tag
        $TechContactTag.Key = "technical_contact"
        $TechContactTag.Value = "."
        New-EC2Tag -Resources $Instance.InstanceID -Tag $TechContactTag -Region $region
        $seeded += "technical_contact"
    }

    #If ($Environment -eq $null -or $Environment.Value -eq $null) {
    #    #The currrent tag is missing, lets create a stub.
    #    $EnvironmentTag = New-Object Amazon.EC2.Model.Tag
    #    $EnvironmentTag.Key = "environment"
    #    $EnvironmentTag.Value = "."
    #    New-EC2Tag -Resources $Instance.InstanceID -Tag $EnvironmentTag -Region $region
    #    $seeded += "environment"
    #}

    If ($Description -eq $null -or $Description.Value -eq $null) {
        #The currrent tag is missing, lets create a stub.
        $DescriptionTag = New-Object Amazon.EC2.Model.Tag
        $DescriptionTag.Key = "description"
        $DescriptionTag.Value = "."
        New-EC2Tag -Resources $Instance.InstanceID -Tag $DescriptionTag -Region $region
        $seeded += "description"
    }

    If ($BillingContact -eq $null -or $BillingContact.Value -eq $null) {
        #The currrent tag is missing, lets create a stub.
        $BillingContactTag = New-Object Amazon.EC2.Model.Tag
        $BillingContactTag.Key = "billing_contact"
        $BillingContactTag.Value = "."
        New-EC2Tag -Resources $Instance.InstanceID -Tag $BillingContactTag -Region $region
        $seeded += "billing_contact"
    }

    If ($Sle -eq $null -or $Sle.Value -eq $null) {
        #The currrent tag is missing, lets create a stub.
        $SleTag = New-Object Amazon.EC2.Model.Tag
        $SleTag.Key = "sle"
        $SleTag.Value = "business_hours=? / grant_critical=? / phi=? / pii=? / publicly_accessible=?"
        New-EC2Tag -Resources $Instance.InstanceID -Tag $SleTag -Region $region
        $seeded += "sle"
    }

    
    if ($seeded.count -gt 0){
        $report[$($Instance.InstanceID)] = $seeded
    }
 }

if ($report.Count -gt 0){
    $rpt = @()
    $body = "The following EC2 instances were found to be missing one or more base tags. The missing tags have been created with a placeholder value of '.'  Please update these tags with the appropriate values as soon as possible:`r`n`r`n"

    ForEach ($inst in $report.keys){
        $r = ""| Select-Object -Property InstanceID, Primed_Tags
        $r.InstanceID = $inst
        $r.Primed_Tags = $report[$inst] -join ", "
        $rpt += $r
    }
    $body += $rpt|Select-Object -Property InstanceID, Primed_Tags|Format-Table -AutoSize|Out-String
    
    Send-MailMessage -SmtpServer mx.fhcrc.org -From $from -To $to -Subject $subject -Body $body

}
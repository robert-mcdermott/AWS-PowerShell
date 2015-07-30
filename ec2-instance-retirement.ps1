param(
    [parameter(mandatory=$false)][string]$Region = "us-west-2"
)

# Import the AWS module so we have access to the EC2 objects required to create filters before an AWS cmdlet auto loads the module 
Import-Module AwsPowerShell

Function RetireInstances($Region)
{
    $retired = @()
    $scheduled = @()
    
    #Delete and snapshots created by this tool, that are older than the specified number of days
    $Filter = New-Object Amazon.EC2.Model.Filter
    $Filter.Name = 'tag:retirement_date'
    $Filter.Value = '*'

    #$now = ([DateTime]::Now).AddMinutes(300000)
    $now = ([DateTime]::Now).AddMinutes(10)

    Get-EC2Instance -Region $Region -Filter $Filter | ForEach-Object {
       
    $RetirementDate = [datetime]::Parse((( $_.Instances).Tags| Where-Object { $_.Key -eq 'retirement_date' }).Value)
    $Name = (($_.Instances).Tags | Where-Object { $_.Key -eq 'Name' }).Value
    $InstanceID = ($_.Instances).InstanceId

    if ($now -gt $RetirementDate){
        Write-Host -Foreground Yellow "Retiring Instance: $Name"
        # as-is below just stops the instance, add -terminate -force to add real teath to this script
        $hush = Stop-EC2Instance -Region $Region -Instance $InstanceID
        $retire = ""| Select-Object -Property InstanceName, InstanceID, Region, RetirementDate
        $retire.InstanceName = $Name
        $retire.InstanceID = $InstanceID
        $retire.Region = $Region
        $retire.RetirementDate = $RetirementDate
        $retired += $retire
    }
    elseif ($now -lt $RetirementDate){
        $schedule = ""| Select-Object -Property InstanceName, InstanceID, Region, RetirementDate
        $schedule.InstanceName = $Name
        $schedule.InstanceID = $InstanceID
        $schedule.Region = $Region
        $schedule.RetirementDate = $RetirementDate
        $scheduled += $schedule
    }

   }
    return $retired, $scheduled
}


#$created = CreateSnapshots $Region
Start-Sleep -Seconds 10
$retired, $scheduled  = RetireInstances $Region


if ($retired -or $scheduled) {

    $ReportS = $scheduled| ConvertTo-Html -Fragment
    $ReportR = $retired| ConvertTo-Html -Fragment

    $Report = @"
        <html>
        <head>
        <title>EC2 Instance Life Cycle Report</title>
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
        <p><h3>The following instances are scheduled to be retired in the future</h3><p>
        $ReportS
        <p><h3>The following instances have been retired</h3><p>
        $ReportR
        </body></html>
"@

Send-MailMessage -SmtpServer "mx.fhcrc.org" -From "ec2-lifecycle@fredhutch.org" -BodyAsHtml $Report -Subject "EC2 Instance Life Cycle Report: $(Get-Date)" -To "cloud-onramp@fredhutch.org"

}
function Get-PeaceHealthPatientStatusLegend{
    $url = 'https://app.peacehealth.org/SmarTrack/View.aspx?FacilityID=0&PatientID=0'
    $response = iwr -Method get -Uri $url
    $legendTBody = $response.ParsedHtml.getElementById('LegendListView_layoutTableTemplate')
    $legend = @()
    foreach($tr in $legendTBody.getElementsByTagName('tr')){
        $legend += [pscustomobject]@{
            ForegroundColor = $tr.style.color
            BackgroundColor = $tr.style.backgroundColor
            Status = $tr.innerText
        }
    }
    return $legend
}

function Get-PeaceHealthPatientStatus{
param(
    [parameter(Mandatory=$true)]
    [string]$FacilityId,
    [parameter(Mandatory=$false)]
    [string]$PatientId=0,
    [Parameter(Mandatory=$false)]
    [PSCustomobject[]]$StatusLegend=(Get-PeaceHealthPatientStatusLegend)
)
    $url = 'https://app.peacehealth.org/SmarTrack/Services/SmarTrackData.asmx/GetList'
    $body = @{facilityID = $FacilityId; patientID= $PatientId} | convertto-json -Compress
    $responses = Invoke-RestMethod -Method post -UseBasicParsing -Uri $url -Body $body -ContentType application/json | select -expand d
    if(-not $responses){ throw "Patient $PatientId not found at faciltiy $FacilityId" }
    if($responses -isnot [array]){ $responses = @($responses) }
    foreach($response in $responses){
        $status = $StatusLegend |?{$_.BackgroundColor -eq $response.BackgroundColor -and $_.ForegroundColor -eq $response.ForegroundColor} | select -ExpandProperty Status
        $readyForFamily = if($response.ReadyForFamily -eq 'Yes'){$true}else{$false}
        $timeInOr = if($response.TimeInOR){[datetime]($response.TimeInOR)}else{$null}
        [pscustomobject]@{
            PatientId = $response.PatientID;
            LocationId = $response.Location;
            TimeInOr = $timeInOr;
            Status = $status;
            Surgeon = $response.Surgeon;
            ReadyForFamily = $readyForFamily
        }
    }
}

function Wait-PeaceHealthPatientStatus{
param(
    [parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [string]$FacilityId,
    [parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [string]$PatientId,
    [parameter(Mandatory=$false)]
    [int]$PollSeconds = 30,
    [parameter(Mandatory=$false)]
    [string[]]$ExitStatus = @('Case Complete'),
    [parameter(Mandatory=$false)]
    [switch]$Beep=$false,
    [parameter(Mandatory=$false)]
    [switch]$ReportChanges=$false
)
begin{
    $timePolled = 0
    $statusLegend = Get-PeaceHealthPatientStatusLegend
}
process{
    Write-Host "Waiting for patient '$PatientId' in facility '$FacilityId' to have a status: $($ExitStatus -join ', ')"
    $oldStatus = Get-PeaceHealthPatientStatus -FacilityId $FacilityId -PatientId $PatientId -StatusLegend $statusLegend
    while($true){
        $status = Get-PeaceHealthPatientStatus -FacilityId $FacilityId -PatientId $PatientId -StatusLegend $statusLegend
        if($ReportChanges){
            $properties = $status | gm -MemberType NoteProperty | Select-Object -ExpandProperty Name
            $changes = @()
            foreach($prop in $properties){
                if($oldStatus."$prop" -ne $status."$prop"){
                    $changes += [pscustomobject]@{Property = $prod; OldValue = $oldStatus."$prop"; NewValue = $newStatus."$prop"}
                }
            }
            if($changes -and $Beep){ [console]::beep(500, 300) }
            $changes | %{Write-Host "$($_.Property) changed from '$($_.OldValue)' -> '$($_.NewValue)'"}
        }

        if($Status.status -in $ExitStatus){
            $timeWaited = New-TimeSpan -Seconds $timePolled
            Write-Host "Exit Status '$($status.Status)' found; stopping polling after $([int]($timeWaited.TotalMinutes)) minute(s)"
            if($Beep){ [console]::beep(500, 600) }
            return $status
        } 
        Start-Sleep -Seconds $PollSeconds
        $timePolled += $PollSeconds
        $oldStatus = $status
    }
}
end{}
}

function Find-PeaceHealthPatient{
    $response = iwr -Method get -Uri 'https://app.peacehealth.org/SmarTrack'
    $facility = $response.ParsedHtml.getElementsByTagName('a') | 
        ?{$_.href -imatch 'FacilityID='} |
        %{
            [pscustomobject]@{
                Name = $_.InnerText;
                Id = ($_.href -split 'FacilityID=')[-1];
            }
         } |
         Out-GridView -Title 'What Facility Are they in?' -OutputMode Single
    $patient = Get-PeaceHealthPatientStatus -FacilityId $facility.Id |
        Out-GridView -Title 'Which of these seems like the correct patient?' -OutputMode Single
    return [pscustomobject]@{FacilityId = $facility.Id; PatientId = $patient.PatientId}
}

<# Usage
Find-PeaceHealthPatient | Wait-PeaceHealthPatientStatus -ReportChanges -Beep
 #>
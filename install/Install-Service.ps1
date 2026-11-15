#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installiert oder aktualisiert den Windows-Dienst Vemas.MailRelay.

.DESCRIPTION
    - kopiert Vemas.MailRelay.exe (und appsettings.json, falls am Ziel noch keine existiert)
    - registriert die Ereignisquelle "Vemas.MailRelay" im Anwendungsprotokoll
    - legt den Dienst an (Autostart, Dienstkonto) bzw. aktualisiert ihn
    - konfiguriert automatischen Neustart nach Absturz
    - legt Firewall-Regeln für SMTP- und Web-Port an
    - startet den Dienst

    Vorher: Install-Database.sql auf der NextGen-Datenbank ausführen.

.PARAMETER ServiceAccount
    Dienstkonto, z.B. "DOMAENE\svc-mailrelay" oder ein gMSA "DOMAENE\gmsa-mailrelay$".
    Das Konto braucht das Recht "Als Dienst anmelden" (siehe README).

.PARAMETER SmtpAllowedRemoteAddress
    Optional: IPs/Netze, die den SMTP-Port erreichen dürfen (Firewall), z.B. "10.0.0.5","10.0.1.0/24".

.EXAMPLE
    .\Install-Service.ps1 -ServiceAccount "CONTOSO\svc-mailrelay" -SmtpAllowedRemoteAddress "10.0.0.5","10.0.0.6"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ServiceAccount,

    [string]$SourcePath = (Join-Path $PSScriptRoot '..\publish'),
    [string]$InstallPath = (Join-Path $env:ProgramFiles 'Vemas.MailRelay'),
    [int]$SmtpPort = 587,
    [int]$WebPort = 8587,
    [string[]]$SmtpAllowedRemoteAddress = @('Any'),
    [string[]]$WebAllowedRemoteAddress = @('Any')
)

$ErrorActionPreference = 'Stop'
$serviceName = 'Vemas.MailRelay'
$exeName = 'Vemas.MailRelay.exe'
$sourceExe = Join-Path $SourcePath $exeName
$targetExe = Join-Path $InstallPath $exeName

if (-not (Test-Path $sourceExe)) {
    throw "$exeName nicht gefunden in '$SourcePath'. Zuerst 'dotnet publish -c Release -o publish' ausführen oder -SourcePath angeben."
}

# 1. Laufenden Dienst stoppen (Update)
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service -and $service.Status -ne 'Stopped') {
    Write-Host "Stoppe Dienst $serviceName ..."
    Stop-Service -Name $serviceName -Force
    $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60))
}

# 2. Dateien kopieren - vorhandene appsettings.json bleibt erhalten
New-Item -ItemType Directory -Force -Path $InstallPath | Out-Null
Copy-Item $sourceExe $targetExe -Force
$targetSettings = Join-Path $InstallPath 'appsettings.json'
if (-not (Test-Path $targetSettings)) {
    Copy-Item (Join-Path $SourcePath 'appsettings.json') $targetSettings
    Write-Warning "appsettings.json wurde neu angelegt - bitte ConnectionString und Web:AdminGroup anpassen: $targetSettings"
}
else {
    Write-Host "Vorhandene appsettings.json bleibt unverändert."
}

# 3. Ereignisquelle registrieren (benötigt Adminrechte, daher hier und nicht im Dienst)
if (-not [System.Diagnostics.EventLog]::SourceExists($serviceName)) {
    [System.Diagnostics.EventLog]::CreateEventSource($serviceName, 'Application')
    Write-Host "Ereignisquelle '$serviceName' registriert."
}

# 4. Dienst anlegen bzw. aktualisieren
$isManagedServiceAccount = $ServiceAccount.EndsWith('$')
$binaryPath = "`"$targetExe`""

if (-not $service) {
    Write-Host "Lege Dienst $serviceName an ..."
    if ($isManagedServiceAccount) {
        New-Service -Name $serviceName -BinaryPathName $binaryPath -DisplayName 'Vemas MailRelay' -StartupType Automatic | Out-Null
        # gMSA: Konto ohne Passwort setzen (Passwort verwaltet Active Directory)
        $wmiService = Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'"
        $result = Invoke-CimMethod -InputObject $wmiService -MethodName Change -Arguments @{ StartName = $ServiceAccount; StartPassword = '' }
        if ($result.ReturnValue -ne 0) { throw "Dienstkonto konnte nicht gesetzt werden (Win32_Service.Change = $($result.ReturnValue))." }
    }
    else {
        $credential = Get-Credential -UserName $ServiceAccount -Message "Passwort für das Dienstkonto $ServiceAccount"
        New-Service -Name $serviceName -BinaryPathName $binaryPath -DisplayName 'Vemas MailRelay' -StartupType Automatic -Credential $credential | Out-Null
    }
}
else {
    Write-Host "Dienst existiert bereits - Konto und Pfad bleiben unverändert."
}

& sc.exe description $serviceName 'SMTP-Relay von SQL Server/SSRS zu Exchange Online (Microsoft Graph, OAuth).' | Out-Null
# Neustart nach Absturz: 1 min, 1 min, 5 min; Zähler nach 1 Tag zurücksetzen
& sc.exe failure $serviceName reset= 86400 actions= restart/60000/restart/60000/restart/300000 | Out-Null
& sc.exe failureflag $serviceName 1 | Out-Null

# 5. Firewall
$rules = @(
    @{ Name = 'Vemas.MailRelay SMTP'; Port = $SmtpPort; Remote = $SmtpAllowedRemoteAddress },
    @{ Name = 'Vemas.MailRelay Web';  Port = $WebPort;  Remote = $WebAllowedRemoteAddress }
)
foreach ($rule in $rules) {
    Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Protocol TCP -LocalPort $rule.Port `
        -RemoteAddress $rule.Remote -Action Allow -Profile Domain,Private | Out-Null
    Write-Host "Firewall-Regel '$($rule.Name)' (TCP $($rule.Port)) angelegt."
}

# 6. Starten
Write-Host "Starte Dienst $serviceName ..."
Start-Service -Name $serviceName
(Get-Service -Name $serviceName).WaitForStatus('Running', [TimeSpan]::FromSeconds(60))
Write-Host ""
Write-Host "Fertig. Weboberfläche: http://$($env:COMPUTERNAME):$WebPort/" -ForegroundColor Green
Write-Host "Meldungen: Ereignisanzeige > Windows-Protokolle > Anwendung, Quelle '$serviceName'."

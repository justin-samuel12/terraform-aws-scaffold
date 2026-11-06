$ErrorActionPreference = 'Stop'

$computer = Get-CimInstance -ClassName Win32_ComputerSystem
if ($computer.PartOfDomain -and $computer.Domain -ieq $DomainName) {
    Write-Output "$env:COMPUTERNAME is already a member of $DomainName"
    exit 0
}

$token = Invoke-RestMethod -Method Put -Uri 'http://169.254.169.254/latest/api/token' -Headers @{ 'X-aws-ec2-metadata-token-ttl-seconds' = '300' }
$server = Invoke-RestMethod -Uri 'http://169.254.169.254/latest/meta-data/tags/instance/Server' -Headers @{ 'X-aws-ec2-metadata-token' = $token }
if ($server -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$') {
    throw "the Server tag '$server' is not a Windows computer name (up to 15 letters, digits and hyphens)"
}

$secret = (Get-SECSecretValue -SecretId $SecretId).SecretString | ConvertFrom-Json
$password = ConvertTo-SecureString -String $secret.password -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $secret.username, $password

$join = @{
    DomainName = $DomainName
    OUPath     = $OrganizationalUnit
    Credential = $credential
    Force      = $true
}
if ($env:COMPUTERNAME -ine $server) {
    $join.NewName = $server
}
Add-Computer @join

Write-Output "$server joined $DomainName in $OrganizationalUnit; restarting to finish"
exit 3010

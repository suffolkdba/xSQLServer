#requires -Version 5
$StartTime = [System.Diagnostics.Stopwatch]::StartNew()

$computers = 'OHSQL9015'
$OutputPath = 'F:\DSCConfig'

$cim = New-CimSession -ComputerName $computers
Function check-even($num){[bool]!($num%2)}

[DSCLocalConfigurationManager()]
Configuration LCM_Push
{
    Param(
        [string[]]$ComputerName
    )
    Node $ComputerName
    {
    Settings
        {
            AllowModuleOverwrite = $True
            ConfigurationMode = 'ApplyAndAutoCorrect'
            RefreshMode = 'Push'
            RebootNodeIfNeeded = $True
        }
    }
}

foreach ($computer in $computers)
{
    $GUID = (New-Guid).Guid
    LCM_Push -ComputerName $Computer -OutputPath $OutputPath
    Set-DSCLocalConfigurationManager -Path $OutputPath  -CimSession $computer -Verbose
}

Configuration SQLBuild
{
    Import-DscResource –ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName xSQLServer


   Node $AllNodes.NodeName
   {

      # Set LCM to reboot if needed
      LocalConfigurationManager
      {
          AllowModuleOverwrite = $true
          RefreshMode = 'Push'
          ConfigurationMode = 'ApplyAndAutoCorrect'
          RebootNodeIfNeeded = $true
          DebugMode = "All"
      }

      WindowsFeature "NET"
      {
          Ensure = "Present"
          Name = "NET-Framework-Core"
          Source = $Node.NETPath
      }

      WindowsFeature "ADTools"
      {
          Ensure = "Present"
          Name = "RSAT-AD-PowerShell"
          Source = $Node.NETPath
      }

      if($Node.Features)
      {
         xSqlServerSetup ($Node.NodeName)
         {
             SourcePath = $Node.SourcePath
             SetupCredential = $Node.InstallerServiceAccount
             InstanceName = $Node.InstanceName
             Features = $Node.Features
             SQLSysAdminAccounts = $Node.AdminAccount
             SQLSvcAccount = $Node.InstallerServiceAccount
             InstallSharedDir = "G:\Program Files\Microsoft SQL Server"
             InstallSharedWOWDir = "G:\Program Files (x86)\Microsoft SQL Server"
             InstanceDir = "G:\Program Files\Microsoft SQL Server"
             InstallSQLDataDir = "G:\Program Files\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\Data"
             SQLUserDBDir = "G:\Program Files\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\Data"
             SQLUserDBLogDir = "L:\Program Files\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\Data"
             SQLTempDBDir = "T:\Program Files\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\Data"
             SQLTempDBLogDir = "L:\Program Files\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\Data"
             SQLBackupDir = "G:\Program Files\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\Data"

             DependsOn = '[WindowsFeature]NET'
         }

         xSqlServerFirewall ($Node.NodeName)
         {
             SourcePath = $Node.SourcePath
             InstanceName = $Node.InstanceName
             Features = $Node.Features

             DependsOn = ("[xSqlServerSetup]" + $Node.NodeName)
         }

         xSQLServerMemory ($Node.Nodename)
         {
             Ensure = "Present"
             DynamicAlloc = $True

             DependsOn = ("[xSqlServerSetup]" + $Node.NodeName)
         }
         xSQLServerMaxDop($Node.Nodename)
         {
             Ensure = "Present"
             DynamicAlloc = $true

             DependsOn = ("[xSqlServerSetup]" + $Node.NodeName)
         }
       }

       xSQLServerEndpoint($Node.Nodename)
       {
           Ensure = "Present"
           Port = 5022
           AuthorizedUser = "CORP\AutoSvc"
           EndPointName = "Hadr_endpoint"
           DependsOn = ("[xSqlServerSetup]" + $Node.NodeName)
       }

    }
}
$ConfigurationData = @{
    AllNodes = @(
        @{
            NodeName = "*"
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser =$true
            NETPath = "\\ohdc9000\SQLBuilds\SQLAutoInstall\WIN2012R2\sxs"
            SourcePath = "\\ohdc9000\SQLAutoBuilds\SQL2014\"
            InstallerServiceAccount = Get-Credential -UserName CORP\AutoSvc -Message "Credentials to Install SQL Server"
            AdminAccount = "CORP\user1"
        }
    )
}

ForEach ($computer in $computers) {
            $ConfigurationData.AllNodes += @{
            NodeName        = $computer
            InstanceName    = "MSSQLSERVER"
            Features        = "SQLENGINE,IS,SSMS,ADV_SSMS"
            }

    $Destination = "\\"+$computer+"\\c$\Program Files\WindowsPowerShell\Modules"
   if (Test-Path "$Destination\xSqlServer"){Remove-Item -Path "$Destination\xSqlServer"-Recurse -Force}
   Copy-Item 'C:\Program Files\WindowsPowerShell\Modules\xSqlServer' -Destination $Destination -Recurse -Force
}

SQLBuild -ConfigurationData $ConfigurationData -OutputPath $OutputPath

#Push################################

Workflow StartConfigs
{
    param([string[]]$computers,
        [System.string] $Path)

    foreach –parallel ($Computer in $Computers)
    {

        Start-DscConfiguration -ComputerName $Computer -Path $Path -Verbose -Wait -Force
    }
}

StartConfigs -Computers $computers -Path $OutputPath


#Ttest
Workflow TestConfigs
{
    param([string[]]$computers)
    foreach -parallel ($Computer in $Computers)
    {
        Write-verbose "$Computer :"
        test-dscconfiguration -ComputerName $Computer
    }
}

TestConfigs -computers $computers

$StartTime.Elapsed

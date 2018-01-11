#
# Copyright (c) .NET Foundation and contributors. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.
#

param(
    [string]$Configuration="Debug",
    [string]$Architecture="x64",
    # This is here just to eat away this parameter because CI still passes this in.
    [string]$Targets="Default",
    [switch]$NoPackage,
    [switch]$NoBuild,
    [switch]$Help,
    [Parameter(Position=0, ValueFromRemainingArguments=$true)]
    $ExtraParameters)

function GetVersionsPropsVersion([string[]] $Name) {
  $VersionsProps = Join-Path $PSScriptRoot "build\DependencyVersions.props"
  [xml]$Xml = Get-Content $VersionsProps

  foreach ($PropertyGroup in $Xml.Project.PropertyGroup) {
    if (Get-Member -InputObject $PropertyGroup -name $Name) {
        return $PropertyGroup.$Name
    }
  }

  throw "Failed to locate the $Name property"
}

if($Help)
{
    Write-Output "Usage: .\run-build.ps1 [-Configuration <CONFIGURATION>] [-Architecture <ARCHITECTURE>] [-NoPackage] [-Help]"
    Write-Output ""
    Write-Output "Options:"
    Write-Output "  -Configuration <CONFIGURATION>     Build the specified Configuration (Debug or Release, default: Debug)"
    Write-Output "  -Architecture <ARCHITECTURE>       Build the specified architecture (x64 or x86 (supported only on Windows), default: x64)"
    Write-Output "  -NoPackage                         Skip packaging targets"
    Write-Output "  -NoBuild                           Skip building the product"
    Write-Output "  -Help                              Display this help message"
    exit 0
}

$env:CONFIGURATION = $Configuration;
$RepoRoot = "$PSScriptRoot"
if(!$env:NUGET_PACKAGES){
  $env:NUGET_PACKAGES = "$RepoRoot\.nuget\packages"
}

if($NoPackage)
{
    $env:DOTNET_BUILD_SKIP_PACKAGING=1
}
else
{
    $env:DOTNET_BUILD_SKIP_PACKAGING=0
}

# Use a repo-local install directory for stage0 (but not the artifacts directory because that gets cleaned a lot
if (!$env:DOTNET_INSTALL_DIR)
{
    $env:DOTNET_INSTALL_DIR="$RepoRoot\.dotnet_stage0\$Architecture"
}

if (!(Test-Path $env:DOTNET_INSTALL_DIR))
{
    mkdir $env:DOTNET_INSTALL_DIR | Out-Null
}



# Disable first run since we want to control all package sources
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

# Don't resolve shared frameworks from user or global locations
$env:DOTNET_MULTILEVEL_LOOKUP=0

# Enable vs test console logging
$env:VSTEST_BUILD_TRACE=1
$env:VSTEST_TRACE_BUILD=1

# install a stage0
if (!$env:DOTNET_TOOL_DIR)
{
    $dotnetInstallPath = Join-Path $RepoRoot "scripts\obtain\dotnet-install.ps1"
    $dotnetCliVersion = GetVersionsPropsVersion -Name "DotNetCoreSdkLKGVersion"

    Write-Output "$dotnetInstallPath -InstallDir $env:DOTNET_INSTALL_DIR -Architecture ""$Architecture"" -Version ""$dotnetCliVersion"""
    Invoke-Expression "$dotnetInstallPath -InstallDir $env:DOTNET_INSTALL_DIR -Architecture ""$Architecture"" -Version ""$dotnetCliVersion"""
    if ($LastExitCode -ne 0)
    {
        Write-Output "The .NET CLI installation failed with exit code $LastExitCode"
        exit $LastExitCode
    }

    Invoke-Expression "$dotnetInstallPath -Version ""1.1.2"" -SharedRuntime -InstallDir $env:DOTNET_INSTALL_DIR -Architecture ""$Architecture"""
}
else
{
    Copy-Item -Recurse -Force $env:DOTNET_TOOL_DIR $env:DOTNET_INSTALL_DIR
}

# Put the stage0 on the path
$env:PATH = "$env:DOTNET_INSTALL_DIR;$env:PATH"

if ($NoBuild)
{
    Write-Output "Not building due to --nobuild"
    Write-Output "Command that would be run: 'dotnet msbuild build.proj /m /p:Architecture=$Architecture $ExtraParameters'"
}
else
{
    dotnet msbuild build.proj /m /v:normal /fl /flp:v=diag /p:Architecture=$Architecture $ExtraParameters
    if($LASTEXITCODE -ne 0) { throw "Failed to build" } 
}

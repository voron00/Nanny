reg add HKCU\Console\%%SystemRoot%%_system32_cmd.exe /v CodePage /t REG_DWORD /d 1251 /f
reg add HKCU\Console\%%SystemRoot%%_system32_cmd.exe /v FaceName /t REG_SZ /d "Lucida Console" /f
reg add HKCU\Console\%%SystemRoot%%_system32_cmd.exe /v FontFamily /t REG_DWORD /d 0x0000036 /f
reg add HKCU\Console\%%SystemRoot%%_system32_cmd.exe /v FontSize /t REG_DWORD /d 0x000c0000 /f
reg add HKCU\Console\%%SystemRoot%%_system32_cmd.exe /v FontWeight /t REG_DWORD /d 0x0000190 /f 
@pause
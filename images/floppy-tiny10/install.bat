@echo off
rem Suppress the network-location flyout on the first networked boot.
rem install.bat runs at first logon while the installer has NO NIC (setup-tiny10.sh
rem attaches no -netdev), so no network event has fired yet; these keys get
rem committed to the offline SYSTEM hive and are read by the network stack on the
rem next boot (run.sh), before the flyout would trigger. bootstrap.bat also sets
rem them each logon as a fallback. UAC is off (EnableLUA=false), so HKLM is writable.
reg add HKLM\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff /f >nul 2>&1
reg add HKLM\SYSTEM\CurrentControlSet\Control\Network\NetworkLocationWizard /v HideWizard /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v bootstrap /t REG_SZ /d "C:\OEM\bootstrap.bat" /f >nul 2>&1
shutdown -s -t 5

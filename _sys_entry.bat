@echo off
setlocal EnableExtensions DisableDelayedExpansion
color 0B
mode con cols=80 lines=38 >nul 2>&1

rem ------------------ BACKEND -------------
set "APP_TITLE=SCRCPY NEW UPDATE"
set "APP_VER=v2.0"
set "DIR_X86=mod_x86"
set "DIR_X64=mod_x64"
rem Teks pengumuman
set "ANN_FILE=pengumuman.txt"
rem Nama file pengaturan milik pengguna
set "CFG_NAME=setting.txt"
rem Port adb wireless dan jumlah percobaan connect
set "WL_PORT=5555"
set "WL_TRIES=1"
rem Argumen scrcpy default (dipakai saat setting.txt belum ada)
set "DEF_ARGS=--keyboard=uhid --mouse=uhid --video-codec=h264 --max-size=1024 --video-bit-rate=4M --max-fps=60 --no-audio --render-driver=opengl --video-buffer=0 --stay-awake"
rem ----------------------------------------------------------------------

rem Folder runtime = folder file ini berada (tanpa backslash akhir)
for %%I in ("%~dp0.") do set "RT=%%~fI"
if not defined SYS_HOME set "SYS_HOME=%RT%"
title %APP_TITLE% %APP_VER%

rem Pakai port server adb sendiri supaya tidak bentrok dengan adb lain milik
rem pengguna, dan kill-server di akhir tidak mematikan adb milik mereka.
set "ANDROID_ADB_SERVER_PORT=5038"
set "ADB=%RT%\adb.exe"
set "BIN_READY=0"
cd /d "%RT%"

rem ---------------- 1. Deteksi arsitektur OS ---------------------------
rem ARM64 dimasukkan ke 64-bit (Windows ARM mengemulasi x64).
set "ARCH=32"
if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" set "ARCH=64"
if /i "%PROCESSOR_ARCHITECTURE%"=="IA64"  set "ARCH=64"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "ARCH=64"
rem cmd 32-bit di atas Windows 64-bit
if defined PROCESSOR_ARCHITEW6432 set "ARCH=64"

set "BIN_SRC=%RT%\%DIR_X86%"
if "%ARCH%"=="64" set "BIN_SRC=%RT%\%DIR_X64%"

rem ---------------- 2. Pengaturan lokal pengguna -----------------------
call :cfg_load

goto menu

rem ====================================================================
rem  MENU UTAMA
rem ====================================================================
:menu
call :draw_header
echo    [1]  Koneksi Wireless
echo    [2]  Mulai Scrcpy
echo    [3]  Keluar
echo(
choice /c 123 /n /m "   Pilih menu [1-3] : "
if errorlevel 3 goto menu_exit
if errorlevel 2 (call :do_play & goto menu)
if errorlevel 1 (call :do_wireless & goto menu)
goto menu

:menu_exit
rem Matikan server adb milik kita (hanya jika binaries sempat disiapkan)
if "%BIN_READY%"=="1" adb kill-server >nul 2>&1
exit /b 0

rem ====================================================================
rem  MENU 1 : KONEKSI WIRELESS
rem  Alur: IP dibaca dari HP via USB, lalu tcpip, lalu adb connect.
rem ====================================================================
:do_wireless
call :draw_header
echo    [ KONEKSI WIRELESS ]
echo(
call :prep_bin
if errorlevel 1 goto wl_end
adb start-server >nul 2>&1
if errorlevel 1 goto wl_adb

call :scan_dev
if defined DEV_USB goto wl_usb
if defined DEV_NET goto wl_already
if defined DEV_BAD goto wl_unauth
echo    [!] HP tidak terdeteksi.
echo        1. Colok HP ke laptop dengan kabel USB data
echo        2. Aktifkan Opsi Pengembang ^> Debugging USB
echo        3. Izinkan pop-up "Allow USB debugging" di layar HP
goto wl_end

:wl_usb
echo    HP terdeteksi via USB : %DEV_USB%

rem Ambil IP WiFi HP (interface wlan) sebelum mode tcpip diaktifkan
set "PHONE_IP="
for /f "tokens=2" %%A in ('adb -s "%DEV_USB%" shell ip -f inet addr show 2^>nul ^| findstr /c:"inet " ^| findstr /i "wlan"') do if not defined PHONE_IP for /f "delims=/" %%B in ("%%A") do set "PHONE_IP=%%B"
if not defined PHONE_IP goto wl_noip
echo    IP WiFi HP            : %PHONE_IP%

echo    Mengaktifkan mode wireless pada port %WL_PORT% ...
adb -s "%DEV_USB%" tcpip %WL_PORT% >nul 2>&1
if errorlevel 1 goto wl_notcp
ping -n 4 127.0.0.1 >nul

set "TRY=0"
:wl_connect
adb connect %PHONE_IP%:%WL_PORT% 2>&1 | findstr /i /c:"connected to" >nul
if not errorlevel 1 goto wl_ok
set /a TRY+=1
if %TRY% GEQ %WL_TRIES% goto wl_fail
ping -n 3 127.0.0.1 >nul
goto wl_connect

:wl_ok
echo(
echo    [OK] Terhubung wireless ke %PHONE_IP%:%WL_PORT%
echo         Kabel USB sekarang boleh dicabut.
echo         Lanjut pilih menu [2] untuk mulai.
goto wl_end

:wl_already
echo    [OK] HP sudah terhubung via WiFi : %DEV_NET%
echo         Langsung pilih menu [2] untuk mulai.
goto wl_end

:wl_unauth
echo    [!] HP terdeteksi tetapi belum diizinkan atau status offline.
echo        Lihat layar HP, izinkan debugging USB, centang "Selalu izinkan",
echo        lalu coba lagi.
goto wl_end

:wl_noip
echo    [!] IP WiFi HP tidak ditemukan.
echo        Pastikan HP tersambung ke WiFi yang sama dengan laptop
echo        (bukan data seluler), lalu coba lagi.
goto wl_end

:wl_notcp
echo    [!] Gagal mengaktifkan mode wireless di HP. Cabut dan colok ulang kabel USB.
goto wl_end

:wl_fail
echo(
echo    [!] Gagal terhubung ke %PHONE_IP%:%WL_PORT%
echo        Pastikan HP dan laptop memakai jaringan WiFi yang sama,
echo        lalu coba lagi.
goto wl_end

:wl_adb
echo    [!] Server adb gagal dijalankan. Tutup aplikasi lain yang memakai adb,
echo        lalu coba lagi.
goto wl_end

:wl_end
call :wait_key
exit /b 0

rem ====================================================================
rem  MENU 2 : MULAI SCRCPY
rem ====================================================================
:do_play
call :draw_header
echo    [ MULAI SCRCPY ]
echo(
rem Baca ulang setting.txt supaya perubahan terbaru langsung dipakai
call :cfg_load
call :prep_bin
if errorlevel 1 goto pl_end
adb start-server >nul 2>&1
if errorlevel 1 goto pl_adb

set "TRY=0"
:pl_scan
call :scan_dev
if not defined DEV_USB goto pl_chk_net
set "TARGET=%DEV_USB%"
set "MODE=Kabel USB"
goto pl_run
:pl_chk_net
if not defined DEV_NET goto pl_retry
set "TARGET=%DEV_NET%"
set "MODE=WiFi"
goto pl_run
:pl_retry
set /a TRY+=1
if %TRY% GEQ 3 goto pl_none
ping -n 3 127.0.0.1 >nul
goto pl_scan

:pl_none
if defined DEV_BAD goto pl_unauth
echo    [!] HP tidak terdeteksi.
echo        - Pakai kabel : colok USB data dan aktifkan Debugging USB
echo        - Pakai WiFi  : pilih menu [1] lebih dulu
goto pl_end

:pl_unauth
echo    [!] HP terdeteksi tetapi belum diizinkan atau status offline.
echo        Lihat layar HP dan izinkan debugging USB, lalu coba lagi.
goto pl_end

:pl_adb
echo    [!] Server adb gagal dijalankan. Tutup aplikasi lain yang memakai adb.
goto pl_end

:pl_run
if not exist "%RT%\scrcpy.exe" goto pl_nobin
echo    Target     : %TARGET%  [%MODE%]
echo    Pengaturan : %CFG_NAME%
echo(
echo    Scrcpy sedang berjalan. Tutup jendela scrcpy untuk kembali ke menu.
echo    Tekan tombol ALT untuk melepas kursor mouse.
echo(
rem scrcpy.exe adalah aplikasi konsol, jadi skrip otomatis menunggu sampai
rem jendelanya ditutup sebelum baris berikutnya dijalankan.
scrcpy -s "%TARGET%" %USER_ARGS%
set "RC=%errorlevel%"
if "%RC%"=="0" exit /b 0
echo(
echo    [!] Scrcpy berhenti dengan kode %RC%.
echo        Kemungkinan HP terputus atau argumen di %CFG_NAME% tidak valid.
goto pl_end

:pl_nobin
echo    [!] scrcpy.exe tidak ditemukan pada modul. Hubungi pembuat tool.
goto pl_end

:pl_end
call :wait_key
exit /b 0

rem ====================================================================
rem  SUBRUTIN
rem ====================================================================

rem --- Gambar header + area pengumuman ---------------------------------
:draw_header
cls
echo ==============================================================================
echo    %APP_TITLE%  -  %APP_VER%
echo    Sistem terdeteksi : %ARCH%-bit
echo ==============================================================================
echo(
echo    [ PENGUMUMAN / UPDATE ]
echo    ------------------------------------------------------------------------
if not exist "%RT%\%ANN_FILE%" goto hd_noann
for /f "usebackq delims=" %%A in ("%RT%\%ANN_FILE%") do echo      %%A
goto hd_end
:hd_noann
echo      Belum ada pengumuman.
:hd_end
echo    ------------------------------------------------------------------------
echo(
exit /b 0

rem --- Tunggu tombol sebelum kembali ke menu ---------------------------
:wait_key
echo(
echo    Tekan tombol apa saja untuk kembali ke menu...
pause >nul
exit /b 0

rem --- Salin binaries sesuai arsitektur ke root runtime (sekali saja) --
:prep_bin
if "%BIN_READY%"=="1" exit /b 0
if not exist "%BIN_SRC%\adb.exe" goto pb_nosrc
echo    Menyiapkan modul %ARCH%-bit ...
xcopy "%BIN_SRC%\*" "%RT%\" /e /y /q /i >nul 2>&1
if not exist "%RT%\adb.exe" goto pb_fail
if not exist "%RT%\scrcpy.exe" goto pb_fail
set "BIN_READY=1"
exit /b 0
:pb_nosrc
echo    [!] Folder modul untuk sistem %ARCH%-bit tidak ditemukan.
echo        Hubungi pembuat tool.
exit /b 1
:pb_fail
echo    [!] Gagal menyiapkan modul. Pastikan antivirus tidak memblokir file.
exit /b 1

rem --- Pindai perangkat adb --------------------------------------------
rem  Hasil: DEV_USB = ID kabel USB, DEV_NET = ID IP:port WiFi,
rem         DEV_BAD = perangkat unauthorized atau offline
:scan_dev
set "DEV_USB="
set "DEV_NET="
set "DEV_BAD="
for /f "tokens=1,2" %%A in ('adb devices 2^>nul') do call :classify "%%A" "%%B"
exit /b 0

:classify
set "_id=%~1"
set "_st=%~2"
if "%_id:~0,1%"=="*" exit /b 0
if /i "%_id%"=="List" exit /b 0
if /i "%_id:~0,9%"=="emulator-" exit /b 0
if /i not "%_st%"=="device" goto cls_bad
rem ID yang mengandung titik dua adalah koneksi jaringan (IP:port)
set "_chk=%_id::=%"
if not "%_chk%"=="%_id%" goto cls_net
if not defined DEV_USB set "DEV_USB=%_id%"
exit /b 0
:cls_net
if not defined DEV_NET set "DEV_NET=%_id%"
exit /b 0
:cls_bad
set "DEV_BAD=%_id%"
exit /b 0

rem --- Muat atau buat setting.txt di folder asli pengguna --------
:cfg_load
set "CFG=%SYS_HOME%\%CFG_NAME%"
if exist "%CFG%" goto cfg_read
call :cfg_make "%CFG%"
if exist "%CFG%" goto cfg_read
rem Folder asli tidak bisa ditulis (mis. Program Files): pakai AppData
set "CFG=%APPDATA%\%CFG_NAME%"
if exist "%CFG%" goto cfg_read
call :cfg_make "%CFG%"
:cfg_read
set "USER_ARGS="
if not exist "%CFG%" goto cfg_def
rem Baris berawalan # dianggap komentar; baris pertama yang berisi dipakai
for /f "usebackq eol=# tokens=* delims=" %%L in ("%CFG%") do if not defined USER_ARGS set "USER_ARGS=%%L"
:cfg_def
if not defined USER_ARGS set "USER_ARGS=%DEF_ARGS%"
exit /b 0

:cfg_make
(
  echo # Pengaturan scrcpy. Baris berawalan # diabaikan.
  echo # Laptop spek rendah: kecilkan --max-size dan --video-bit-rate, turunkan --max-fps.
  echo # Hapus file ini untuk mengembalikan ke pengaturan awal.
  echo %DEF_ARGS%
) 2>nul >%1
exit /b 0

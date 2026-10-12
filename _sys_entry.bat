@echo off
setlocal EnableExtensions DisableDelayedExpansion
color 0B
mode con cols=80 lines=38 >nul 2>&1

rem ------------------ BACKEND -------------
set "APP_TITLE=SCRCPY NEW UPDATE"
set "APP_VER=v2.2"
rem Teks pengumuman (diunduh launcher dari repo)
set "ANN_FILE=pengumuman.txt"
rem Nama file pengaturan milik pengguna
set "CFG_NAME=setting.txt"
rem Port adb wireless dan jumlah percobaan connect
set "WL_PORT=5555"
set "WL_TRIES=3"
rem Argumen scrcpy default (dipakai saat setting.txt belum ada)
set "DEF_ARGS=--keyboard=uhid --mouse=uhid --video-codec=h264 --max-size=1000 --video-bit-rate=2M --max-fps=60 --video-buffer=30 --render-driver=direct3d --no-audio --turn-screen-off"
rem Argumen PAKSA: selalu ditaruh paling belakang, tidak bisa ditimpa setting.txt.
rem Mematikan shortcut Shift+klik (tengah=Home, kanan=Back) di mode uhid.
rem Butuh scrcpy 3.x. Kalau scrcpy lebih lama, kosongkan nilainya.
set "FORCE_ARGS=--mouse-bind=++++:++++"
rem Sumber paket modul (GitHub Releases) - dipakai kalau binaries belum ada
set "GITHUB_USER=frbyannqt"
set "REPO_NAME=sysmod-data"
set "PKG_X86=mod_x86.zip"
set "PKG_X64=mod_x64.zip"
rem ----------------------------------------------------------------------

rem Folder runtime = folder file ini berada (tanpa backslash akhir)
for %%I in ("%~dp0.") do set "RT=%%~fI"
if not defined SYS_HOME set "SYS_HOME=%RT%"
rem Arsitektur: pakai kiriman Launcher baru, kalau tidak ada deteksi sendiri
set "ARCH=32"
if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" set "ARCH=64"
if /i "%PROCESSOR_ARCHITECTURE%"=="IA64"  set "ARCH=64"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "ARCH=64"
if defined PROCESSOR_ARCHITEW6432 set "ARCH=64"
title %APP_TITLE% %APP_VER%

rem Port server adb sendiri supaya tidak bentrok dengan adb milik pengguna,
rem dan kill-server di akhir tidak mematikan adb milik mereka.
set "ANDROID_ADB_SERVER_PORT=5038"
cd /d "%RT%"

call :cfg_load

rem Siapkan adb + scrcpy (hasil: variabel BIN = folder yang berisi keduanya)
call :prep_bin
if errorlevel 1 goto boot_fail
set "ADB=%BIN%\adb.exe"
set "PATH=%BIN%;%PATH%"
goto menu

:boot_fail
echo(
echo    Tutup jendela ini lalu jalankan ulang Launcher.
echo    Kalau tetap gagal, hubungi pembuat tool.
pause >nul
exit /b 1

rem ====================================================================
rem  MENU UTAMA
rem ====================================================================
:menu
call :draw_header
echo    [1]  Koneksi Wireless
echo    [2]  Mulai Scrcpy
echo    [3]  Keluar
echo    [4]  Diagnosa ^(kalau ada masalah^)
echo(
choice /c 1234 /n /m "   Pilih menu [1-4] : "
if errorlevel 4 (call :do_diag & goto menu)
if errorlevel 3 goto menu_exit
if errorlevel 2 (call :do_play & goto menu)
if errorlevel 1 (call :do_wireless & goto menu)
goto menu

:menu_exit
rem Matikan server adb milik kita
adb kill-server >nul 2>&1
exit /b 0

rem ====================================================================
rem  MENU 1 : KONEKSI WIRELESS
rem  Alur: IP dibaca dari HP via USB, lalu tcpip, lalu adb connect.
rem ====================================================================
:do_wireless
call :draw_header
echo    [ KONEKSI WIRELESS ]
echo(
call :adb_up
if errorlevel 1 goto wl_adb

call :scan_dev
if defined DEV_USB goto wl_usb
if defined DEV_NET goto wl_already
if defined DEV_BAD goto wl_unauth
echo    [!] HP tidak terdeteksi.
echo        1. Colok HP ke laptop dengan kabel USB data ^(bukan kabel charger^)
echo        2. Aktifkan Opsi Pengembang ^> Debugging USB
echo        3. Izinkan pop-up "Allow USB debugging" di layar HP
call :show_adb
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
echo    Menghubungkan ke %PHONE_IP%:%WL_PORT% ...
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
call :show_adb
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
call :adb_up
if errorlevel 1 goto pl_adb

echo    Mencari HP ...
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
call :show_adb
goto pl_end

:pl_unauth
echo    [!] HP terdeteksi tetapi belum diizinkan atau status offline.
echo        Lihat layar HP dan izinkan debugging USB, lalu coba lagi.
call :show_adb
goto pl_end

:pl_adb
echo    [!] Server adb gagal dijalankan. Tutup aplikasi lain yang memakai adb.
goto pl_end

:pl_run
echo    Target     : %TARGET%  [%MODE%]
echo    Pengaturan : %CFG_NAME%
echo(
echo    Scrcpy sedang berjalan. Tutup jendela scrcpy untuk kembali ke menu.
echo    Tekan tombol ALT untuk melepas kursor mouse.
echo(
rem scrcpy.exe adalah aplikasi konsol, jadi skrip otomatis menunggu sampai
rem jendelanya ditutup. FORCE_ARGS sengaja paling belakang.
scrcpy -s "%TARGET%" %USER_ARGS% %FORCE_ARGS%
set "RC=%errorlevel%"
if "%RC%"=="0" exit /b 0
echo(
echo    [!] Scrcpy berhenti dengan kode %RC%.
echo        Kemungkinan HP terputus atau argumen di %CFG_NAME% tidak valid.
echo        Hapus file %CFG_NAME% untuk kembali ke pengaturan awal.
goto pl_end

:pl_end
call :wait_key
exit /b 0

rem ====================================================================
rem  MENU 4 : DIAGNOSA
rem ====================================================================
:do_diag
call :draw_header
echo    [ DIAGNOSA ]  ^(screenshot ini terus send ke wa gw di saluran kalo eror^)
echo(
echo    Arsitektur : %ARCH%-bit
echo    Tanggal/jam: %date% %time:~0,5%   ^(harus benar, kalau tidak unduhan bisa gagal^)
echo    Pengaturan : %CFG%
echo    Argumen    : %USER_ARGS% %FORCE_ARGS%
if defined SYS_LOG echo    Log        : %SYS_LOG%
echo(
echo    --- adb ---
adb version 2>&1 | findstr /i "version"
echo(
echo    --- scrcpy ---
scrcpy --version 2>&1 | findstr /b /i "scrcpy"
echo(
echo    --- perangkat ---
call :adb_up
call :show_adb
goto dg_end
:dg_end
call :wait_key
exit /b 0

rem ====================================================================
rem  SUBRUTIN
rem ====================================================================

rem --- Gambar header + area pengumuman ---------------------------------
:draw_header
cls
echo.
echo    %APP_TITLE%  -  %APP_VER%
echo    Arsitektur terdeteksi : %ARCH%-bit
echo.
echo(
echo    [ PENGUMUMAN / UPDATE ]
echo.
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

rem --- Siapkan modul: pakai yang sudah ada, kalau tidak unduh sesuai arsitektur
:prep_bin
rem 1) binaries sudah ada di folder ini (Launcher baru)
set "BIN=%RT%"
if exist "%BIN%\adb.exe" if exist "%BIN%\scrcpy.exe" exit /b 0
rem 2) folder mod_x86 / mod_x64 masih ada di repo (susunan lama)
set "BIN=%RT%\mod_x86"
if "%ARCH%"=="64" set "BIN=%RT%\mod_x64"
if exist "%BIN%\adb.exe" if exist "%BIN%\scrcpy.exe" exit /b 0
rem 3) unduh paket yang sesuai arsitektur dari GitHub Releases
set "PKG=%PKG_X86%"
if "%ARCH%"=="64" set "PKG=%PKG_X64%"
set "ZIPF=%RT%\mod_pkg.dat"
set "BIN=%RT%\bin"
echo(
echo    Sistem terdeteksi : %ARCH%-bit
echo    [1/2] Mengunduh modul %ARCH%-bit, mohon tunggu...
call :dl "https://github.com/%GITHUB_USER%/%REPO_NAME%/releases/latest/download/%PKG%" "%ZIPF%"
if not "%DL_RC%"=="0" goto pb_dlfail
echo    [2/2] Menyiapkan modul...
md "%BIN%" >nul 2>&1
where tar.exe >nul 2>&1
if errorlevel 1 goto pb_ps
tar.exe -xf "%ZIPF%" -C "%BIN%" >nul 2>&1
if not errorlevel 1 goto pb_find
:pb_ps
set "DL_OUT=%ZIPF%"
set "DL_DIR=%BIN%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "try{Add-Type -AssemblyName System.IO.Compression.FileSystem;[IO.Compression.ZipFile]::ExtractToDirectory($env:DL_OUT,$env:DL_DIR)}catch{try{Expand-Archive -LiteralPath $env:DL_OUT -DestinationPath $env:DL_DIR -Force}catch{exit 1}}" >nul 2>&1
if errorlevel 1 goto pb_bad
:pb_find
rem Isi ZIP bisa langsung di root atau di dalam 1 subfolder
if exist "%BIN%\scrcpy.exe" goto pb_chk
for /d %%D in ("%BIN%\*") do if exist "%%~fD\scrcpy.exe" set "BIN=%%~fD"
:pb_chk
if not exist "%BIN%\scrcpy.exe" goto pb_bad
if not exist "%BIN%\adb.exe" goto pb_bad
del "%ZIPF%" >nul 2>&1
exit /b 0

:pb_dlfail
echo(
if "%DL_RC%"=="6"  goto pb_net
if "%DL_RC%"=="7"  goto pb_net
if "%DL_RC%"=="28" goto pb_slow
if "%DL_RC%"=="22" goto pb_404
if "%DL_RC%"=="35" goto pb_ssl
if "%DL_RC%"=="51" goto pb_ssl
if "%DL_RC%"=="58" goto pb_ssl
if "%DL_RC%"=="60" goto pb_ssl
if "%DL_RC%"=="77" goto pb_ssl
echo    [!] Gagal mengunduh modul ^(kode %DL_RC%^).
echo        Periksa internet, matikan VPN/antivirus sementara, lalu coba lagi.
exit /b 1
:pb_net
echo    [!] Tidak ada koneksi internet atau GitHub tidak bisa dijangkau.
echo        Pastikan WiFi/internet aktif, lalu jalankan ulang.
exit /b 1
:pb_slow
echo    [!] Koneksi terlalu lambat sehingga unduhan terputus. Coba lagi.
exit /b 1
:pb_404
echo    [!] File modul tidak ditemukan di server. Hubungi pembuat tool.
exit /b 1
:pb_ssl
echo    [!] Koneksi aman gagal. Penyebab tersering: JAM LAPTOP SALAH.
echo        Cek tanggal dan jam laptop ^(aktifkan Set time automatically^),
echo        lalu jalankan ulang.
exit /b 1
:pb_bad
echo    [!] Modul rusak atau tidak lengkap. Jalankan ulang.
echo        Kalau tetap gagal, matikan antivirus sementara.
exit /b 1

rem --- Unduh: %1=URL  %2=file tujuan  -> hasil di DL_RC (0 = sukses) ----
:dl
set "DL_URL=%~1"
set "DL_OUT=%~2"
set "DL_RC=0"
where curl.exe >nul 2>&1
if errorlevel 1 goto dl_ps
curl.exe -L -f -sS --connect-timeout 15 --max-time 240 --retry 2 -o "%DL_OUT%" "%DL_URL%" 2>nul
set "DL_RC=%errorlevel%"
goto dl_chk
:dl_ps
powershell -NoProfile -ExecutionPolicy Bypass -Command "try{[Net.ServicePointManager]::SecurityProtocol=3072;(New-Object Net.WebClient).DownloadFile($env:DL_URL,$env:DL_OUT)}catch{exit 1}" >nul 2>&1
set "DL_RC=%errorlevel%"
:dl_chk
if not "%DL_RC%"=="0" exit /b 0
if not exist "%DL_OUT%" set "DL_RC=99"
exit /b 0

rem --- Nyalakan server adb (dengan pesan supaya tidak terlihat macet) --
:adb_up
echo    Menyalakan adb, mohon tunggu...
adb start-server >nul 2>&1
exit /b %errorlevel%

rem --- Tampilkan daftar perangkat mentah dari adb ----------------------
:show_adb
echo(
echo    Daftar perangkat menurut adb:
adb devices -l 2>&1
exit /b 0

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
  echo # Laptop spek rendah: kecilin --max-size dan --video-bit-rate, turunkan --max-fps.
  echo # semakin kecil ukuran nya itu semakin enteng tapi kualitas nya turun
  echo # sebaliknya semakin gede ukuran nya semakin hd, tapi semakin berat ^(tes dulu aja^)
  echo(
  echo # Hapus file ini untuk mengembalikan ke pengaturan awal.
  echo(
  echo # UBAH SETINGAN NYA DIBAWAH SINI
  echo %DEF_ARGS%
) 2>nul >%1
exit /b 0

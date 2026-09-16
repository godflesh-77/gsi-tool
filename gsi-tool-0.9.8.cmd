@echo off
chcp 1251 >nul
setlocal enabledelayedexpansion

set "TOOL_VERSION=0.9.8"

if "%~1"=="--version" ( echo !TOOL_VERSION! & exit /b 0 )
if "%~1"=="-v"        ( echo !TOOL_VERSION! & exit /b 0 )
if "%~1"=="--help"    ( goto show_help )
if "%~1"=="-h"        ( goto show_help )
goto skip_help

:show_help
echo GSI Flash Tool !TOOL_VERSION!
echo Использование: %~nx0 [опции]
echo   -h, --help     Показать эту справку
echo   -v, --version  Показать версию утилиты
exit /b 0

:skip_help

title GSI Flash Tool !TOOL_VERSION! (Windows) by GODFLESH

set "WAIT_TIMEOUT=15"
set "REBOOT_TIMEOUT=10"
set "MARGIN_MB=256"
set "HELPER=%~dp0gsi-tool-helper-!TOOL_VERSION!.ps1"

if not exist "%HELPER%" (
    echo ОШИБКА: не найден gsi-tool-helper-!TOOL_VERSION!.ps1 рядом со скриптом!
    pause & exit /b 1
)

set "LOG_DIR=logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
for /f "usebackq delims=" %%t in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Mode timestamp`) do set "log_ts=%%t"
if "!log_ts!"=="" (
    for /f "tokens=1-4 delims=/: " %%a in ("%date%_%time%") do set "log_ts=%%d%%c%%b_%%a"
)
set "LOG=%LOG_DIR%\gsi-tool_!TOOL_VERSION!_!log_ts!.log"
echo === SESSION START %date% %time% === >> "%LOG%"

set "tools_found=1"
where adb      >nul 2>&1 & if errorlevel 1 if not exist "adb.exe"      set "tools_found=0"
where fastboot >nul 2>&1 & if errorlevel 1 if not exist "fastboot.exe" set "tools_found=0"
if "%tools_found%"=="0" goto missing_tools

call :find_7zip
if !errorlevel! neq 0 (
    echo [ВНИМАНИЕ] 7-Zip не найден ^(нужны 7z.exe + 7z.dll^).
    set "SEVENZIP="
)

set "IS_AB_DEVICE=yes"
set "CURRENT_SLOT=a"

:: ============================================================
:main_menu
cls
echo ========================================================
echo   GSI Flash Tool !TOOL_VERSION! (Windows)
echo   Лог: %LOG%
echo ========================================================
echo    1. Проверить устройства (ADB / Fastboot)
echo    2. Android  -^> Fastbootd
echo    3. Recovery -^> Fastbootd
echo    4. Bootloader -^> Fastbootd
echo    5. Уже в Fastbootd
echo    6. СЕРВИСНОЕ МЕНЮ
echo    0. Выход
echo ========================================================
set "cs="
set /p "cs=Ввод: "

if "%cs%"=="0" exit /b 0
if "%cs%"=="6" ( call :service_menu & goto main_menu )
if "%cs%"=="5" ( call :wait_for_fastboot
                if !errorlevel! neq 0 ( echo Нет fastboot. & pause & goto main_menu )
                goto after_state )
if "%cs%"=="4" ( call :wait_for_fastboot
                if !errorlevel! neq 0 ( echo Не в Bootloader! & pause & goto main_menu )
                call :reboot_to_fastbootd
                if !errorlevel! neq 0 ( pause & goto main_menu )
                goto after_state )
if "%cs%"=="3" goto reboot_via_adb
if "%cs%"=="2" goto reboot_via_adb
if "%cs%"=="1" ( adb devices & fastboot devices & pause & goto main_menu )
goto main_menu

:reboot_via_adb
call :wait_for_adb
if !errorlevel! neq 0 ( echo ADB не отвечает. & pause & goto main_menu )
echo Перезагрузка в Fastbootd...
call :fb_reboot_adb fastboot
if !errorlevel! neq 0 ( pause & goto main_menu )
call :wait_for_fastboot
if !errorlevel! neq 0 ( echo Fastbootd не поднялся. & pause & goto main_menu )
goto after_state

:after_state
echo Проверка загрузчика...
call :check_bootloader_unlocked
if !errorlevel! neq 0 ( pause & goto main_menu )
call :detect_ab_device
call :get_current_slot
echo Активный слот: !CURRENT_SLOT!  [A/B: !IS_AB_DEVICE!]
goto action_menu

:: ============================================================
:action_menu
cls
echo ========================================================
echo  Активный слот: !CURRENT_SLOT!  [A/B: !IS_AB_DEVICE!]
echo ========================================================
echo    1. Обновить систему
echo    2. Сброс и прошивка (Full Wipe)
echo    3. Прошить в указанный слот (A/B)
echo    4. Переключить активный слот
echo    5. Грязная прошивка
echo    0. Назад
echo ========================================================
set "ca="
set /p "ca=Ввод: "

if "%ca%"=="0" goto main_menu
if "%ca%"=="4" goto switch_slot
if "%ca%"=="3" goto flash_slot
if "%ca%"=="2" goto reset_flash
if "%ca%"=="1" goto update_system
if "%ca%"=="5" goto dirty_flash
goto action_menu

:switch_slot
if not "!IS_AB_DEVICE!"=="yes" ( echo Устройство не A/B. & pause & goto action_menu )
if "!CURRENT_SLOT!"=="a" ( set "NS=b" ) else ( set "NS=a" )
fastboot set_active !NS! >> "%LOG%" 2>&1
set "CURRENT_SLOT=!NS!"
echo Текущий слот: !CURRENT_SLOT!
pause & goto action_menu

:flash_slot
call :select_system_img || ( pause & goto action_menu )
set "sc="
set /p "sc=Слот (a/b): "
if /i not "!sc!"=="a" if /i not "!sc!"=="b" set "sc=!CURRENT_SLOT!"
call :check_and_flash_vbmeta || goto action_menu
call :free_super_space !sc! || goto action_menu
call :get_sys_part !sc!
call :fb_flash flash !SYS_PART! "!SYSTEM_IMG!" || ( pause & goto action_menu )
fastboot erase cache >> "%LOG%" 2>&1
if "!IS_AB_DEVICE!"=="yes" fastboot set_active !sc! >> "%LOG%" 2>&1
call :fb_reboot
if !errorlevel! neq 0 echo [i] Автоматический reboot не сработал. Запустите "fastboot reboot" вручную.
echo Готово.
pause & exit /b 0

:reset_flash
call :select_system_img || ( pause & goto action_menu )
call :check_and_flash_vbmeta || goto action_menu
call :free_super_space !CURRENT_SLOT! || goto action_menu
fastboot -w >> "%LOG%" 2>&1
if !errorlevel! neq 0 (
    echo ВНИМАНИЕ: fastboot -w ^(wipe^) провалился.
    set "c="
    set /p "c=Продолжить без wipe? (y/N): "
    if /i not "!c!"=="y" goto action_menu
)
call :get_sys_part !CURRENT_SLOT!
call :fb_flash flash !SYS_PART! "!SYSTEM_IMG!" || ( pause & goto action_menu )
call :fb_reboot
if !errorlevel! neq 0 echo [i] Автоматический reboot не сработал. Запустите "fastboot reboot" вручную.
echo Готово.
pause & exit /b 0

:update_system
call :select_system_img || ( pause & goto action_menu )
call :check_and_flash_vbmeta || goto action_menu
call :free_super_space !CURRENT_SLOT! || goto action_menu
call :get_sys_part !CURRENT_SLOT!
call :fb_flash flash !SYS_PART! "!SYSTEM_IMG!" || ( pause & goto action_menu )
fastboot erase cache >> "%LOG%" 2>&1
call :fb_reboot
if !errorlevel! neq 0 echo [i] Автоматический reboot не сработал. Запустите "fastboot reboot" вручную.
echo Готово.
pause & exit /b 0

:dirty_flash
call :select_system_img || ( pause & goto action_menu )
call :check_bootloader_unlocked || ( pause & goto action_menu )
call :get_sys_part !CURRENT_SLOT!
call :fb_flash flash !SYS_PART! "!SYSTEM_IMG!" || ( pause & goto action_menu )
call :fb_reboot
if !errorlevel! neq 0 echo [i] Автоматический reboot не сработал. Запустите "fastboot reboot" вручную.
echo Готово.
pause & exit /b 0

:: ============================================================
:get_sys_part
if "!IS_AB_DEVICE!"=="yes" ( set "SYS_PART=system_%~1" ) else ( set "SYS_PART=system" )
exit /b 0

:: ============================================================
:fb_flash
fastboot %* >> "%LOG%" 2>&1
if !errorlevel! neq 0 (
    echo ========================================================
    echo ОШИБКА: fastboot %* - ПРОВАЛ!
    echo Подробности в логе: %LOG%
    echo НЕ ПЕРЕЗАГРУЖАЙТЕ устройство.
    echo ========================================================
    exit /b 1
)
exit /b 0

:: ============================================================
:fb_reboot
set "REBOOT_EXTRA=%~1"
set "REBOOT_RES="
for /f "usebackq delims=" %%s in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Mode reboot -Path "!REBOOT_EXTRA!" -Timeout %REBOOT_TIMEOUT%`) do set "REBOOT_RES=%%s"
if "!REBOOT_RES!"=="timeout" (
    echo [ВНИМАНИЕ] fastboot reboot: timeout за %REBOOT_TIMEOUT% сек
    echo Устройство, скорее всего, все равно перезагрузится.
    echo Проверьте лог: %LOG%
) else if "!REBOOT_RES!"=="error" (
    echo [ВНИМАНИЕ] fastboot reboot: не удалось запустить fastboot
    echo Проверьте, что fastboot.exe есть в PATH или рядом со скриптом.
    echo Устройство НЕ перезагружено. Лог: %LOG%
    exit /b 1
) else (
    echo [fastboot reboot] OK.
)
exit /b 0

:: ============================================================
:fb_reboot_adb
set "REBOOT_EXTRA=%~1"
set "REBOOT_RES="
for /f "usebackq delims=" %%s in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Mode adb_reboot -Path "!REBOOT_EXTRA!" -Timeout %REBOOT_TIMEOUT%`) do set "REBOOT_RES=%%s"
if "!REBOOT_RES!"=="timeout" (
    echo [ВНИМАНИЕ] adb reboot: timeout за %REBOOT_TIMEOUT% сек
    echo Устройство, скорее всего, все равно перезагрузится.
) else if "!REBOOT_RES!"=="error" (
    echo [ВНИМАНИЕ] adb reboot: не удалось запустить adb
    echo Проверьте, что adb.exe есть в PATH или рядом со скриптом.
    echo Устройство НЕ перезагружено.
    exit /b 1
)
exit /b 0

:: ============================================================
:detect_ab_device
set "IS_AB_DEVICE=yes"
fastboot getvar slot-count 2>&1 | findstr /r /c:"slot-count:[ ]*1" >nul
if !errorlevel! equ 0 set "IS_AB_DEVICE=no"
echo [A/B detection] !IS_AB_DEVICE!
exit /b 0

:: ============================================================
:check_bootloader_unlocked
set "bl_ok=0"
for /f "tokens=2 delims=: " %%i in ('fastboot getvar unlocked 2^>^&1 ^| findstr /c:"unlocked"') do (
    set "v=%%i"
    if /i "!v!"=="yes" set "bl_ok=1"
)
if "!bl_ok!"=="0" (
    for /f "tokens=2 delims=: " %%i in ('fastboot getvar secure 2^>^&1 ^| findstr /c:"secure"') do (
        set "v=%%i"
        if /i "!v!"=="no" set "bl_ok=1"
    )
)
if "!bl_ok!"=="0" (
    set "ga="
    for /f "tokens=2 delims=: " %%i in ('fastboot flashing get_unlock_ability 2^>^&1 ^| findstr /c:"get_unlock_ability"') do set "ga=%%i"
    if "!ga!"=="0" (
        echo ========================================================
        echo ОШИБКА: OEM Unlock выключен в Android!
        echo Включите 'OEM unlocking' в настройках разработчика.
        echo ========================================================
        exit /b 1
    )
)
if "!bl_ok!"=="0" (
    echo ========================================================
    echo КРИТИЧЕСКАЯ ОШИБКА: Загрузчик заблокирован ^(Locked^)!
    echo Прошивка Dynamic Partitions невозможна.
    echo ========================================================
    exit /b 1
)
echo Загрузчик: РАЗБЛОКИРОВАН.
exit /b 0

:: ============================================================
:wait_for_adb
set "c=0"
echo|set /p="Ожидание ADB"
:wa
if !c! geq %WAIT_TIMEOUT% ( echo  [ТАЙМ-АУТ] & exit /b 1 )
set "ok=0"
for /f "skip=1 tokens=1,2" %%a in ('adb devices 2^>nul') do (
    if "%%b"=="device"   set "ok=1"
    if "%%b"=="recovery" set "ok=1"
)
if !ok!==1 ( echo  [OK] & exit /b 0 )
echo|set /p="."
timeout /t 1 /nobreak >nul
set /a c+=1
goto wa

:wait_for_fastboot
set "c=0"
echo|set /p="Ожидание Fastboot"
:wf
if !c! geq %WAIT_TIMEOUT% ( echo  [ТАЙМ-АУТ] & exit /b 1 )
set "ok=0"
for /f "tokens=2" %%a in ('fastboot devices 2^>nul') do (
    if "%%a"=="fastboot" set "ok=1"
)
if !ok!==1 ( echo  [OK] & exit /b 0 )
echo|set /p="."
timeout /t 1 /nobreak >nul
set /a c+=1
goto wf

:get_current_slot
set "CURRENT_SLOT=a"
for /f "tokens=2 delims=: " %%i in ('fastboot getvar current-slot 2^>^&1 ^| findstr /c:"current-slot"') do (
    set "raw=%%i"
    set "f=!raw:~0,1!"
    if "!f!"=="a" set "CURRENT_SLOT=a"
    if "!f!"=="b" set "CURRENT_SLOT=b"
)
exit /b 0

:get_userspace
set "is_userspace=no"
for /f "tokens=2 delims=: " %%i in ('fastboot getvar is-userspace 2^>^&1 ^| findstr /c:"is-userspace"') do (
    set "raw=%%i"
    set "p=!raw:~0,3!"
    if /i "!p!"=="yes" set "is_userspace=yes"
)
exit /b 0

:detect_image_size
set "IMG_SIZE=0"
for /f "usebackq delims=" %%s in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Mode size -Path "%~1"`) do set "IMG_SIZE=%%s"
if "!IMG_SIZE!"=="" set "IMG_SIZE=0"
exit /b 0

:verify_sparse_integrity
set "VI_RESULT="
for /f "usebackq delims=" %%s in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Mode sparse_integrity -Path "%~1"`) do set "VI_RESULT=%%s"
if "!VI_RESULT!"=="" (
    echo [ВНИМАНИЕ] Не удалось проверить целостность образа.
    exit /b 0
)
echo !VI_RESULT! | findstr /b /c:"suspect:" >nul
if !errorlevel! equ 0 (
    echo --------------------------------------------------------
    echo ВНИМАНИЕ: sparse-образ подозрительно мал.
    echo !VI_RESULT!
    echo --------------------------------------------------------
    set "vi_ok="
    set /p "vi_ok=Продолжить? (y/N): "
    if /i not "!vi_ok!"=="y" exit /b 1
)
exit /b 0

:calculate_partition_size
set "part_size=0"
for /f "usebackq delims=" %%s in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Mode calculate_partition -Path "%~1" -Margin !MARGIN_MB!`) do set "part_size=%%s"
if "!part_size!"=="" set "part_size=0"
exit /b 0

:check_disk_space_mb
set "free_mb=0"
for /f "usebackq delims=" %%s in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Mode disk_free_mb -Path "%~1"`) do set "free_mb=%%s"
if "!free_mb!"=="" set "free_mb=0"
exit /b 0

:need_mb_for_xz
set "need_mb=0"
for /f "usebackq delims=" %%s in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Mode need_mb_x3 -Path "%~1"`) do set "need_mb=%%s"
if "!need_mb!"=="" set "need_mb=0"
exit /b 0

:need_mb_for_gz
set "need_mb=0"
for /f "usebackq delims=" %%s in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Mode need_mb_x4 -Path "%~1"`) do set "need_mb=%%s"
if "!need_mb!"=="" set "need_mb=0"
exit /b 0

:: ============================================================
:resolve_system_img
echo !SYSTEM_IMG! | findstr /i /e ".img.xz" >nul
if !errorlevel! equ 0 (
    if not defined SEVENZIP ( echo Нужен 7-Zip для .xz! & exit /b 1 )
    set "out=!SYSTEM_IMG:~0,-3!"
    if not exist "!out!" (
        for %%f in ("!out!") do set "target_dir=%%~dpf"
        if "!target_dir!"=="" set "target_dir=."
        call :check_disk_space_mb "!target_dir!"
        call :need_mb_for_xz "!SYSTEM_IMG!"
        if !free_mb! lss !need_mb! (
            echo ОШИБКА: мало места ^(нужно ~!need_mb! МБ, свободно !free_mb! МБ^)
            exit /b 1
        )
        echo Распаковка !SYSTEM_IMG! -^> !out! ^(нужно ~!need_mb! МБ, свободно !free_mb! МБ^)
        set "unp="
        set /p "unp=Продолжить? (y/N): "
        if /i not "!unp!"=="y" exit /b 1
        "%SEVENZIP%" x -y -bso0 -bsp1 "!SYSTEM_IMG!"
        if !errorlevel! neq 0 ( echo ОШИБКА: распаковка .xz! & exit /b 1 )
    )
    set "SYSTEM_IMG=!out!"
)
echo !SYSTEM_IMG! | findstr /i /e ".img.gz" >nul
if !errorlevel! equ 0 (
    if not defined SEVENZIP ( echo Нужен 7-Zip для .gz! & exit /b 1 )
    set "out=!SYSTEM_IMG:~0,-3!"
    if not exist "!out!" (
        for %%f in ("!out!") do set "target_dir=%%~dpf"
        if "!target_dir!"=="" set "target_dir=."
        call :check_disk_space_mb "!target_dir!"
        call :need_mb_for_gz "!SYSTEM_IMG!"
        if !free_mb! lss !need_mb! (
            echo ОШИБКА: мало места ^(нужно ~!need_mb! МБ, свободно !free_mb! МБ^)
            exit /b 1
        )
        echo Распаковка !SYSTEM_IMG! -^> !out! ^(нужно ~!need_mb! МБ, свободно !free_mb! МБ^)
        set "unp="
        set /p "unp=Продолжить? (y/N): "
        if /i not "!unp!"=="y" exit /b 1
        "%SEVENZIP%" x -y -bso0 -bsp1 "!SYSTEM_IMG!"
        if !errorlevel! neq 0 ( echo ОШИБКА: распаковка .gz! & exit /b 1 )
    )
    set "SYSTEM_IMG=!out!"
)
echo !SYSTEM_IMG! | findstr /i /e ".img.zst" >nul
if !errorlevel! equ 0 (
    if not defined SEVENZIP ( echo Нужен 7-Zip для .zst! & exit /b 1 )
    set "out=!SYSTEM_IMG:~0,-4!"
    if not exist "!out!" (
        for %%f in ("!out!") do set "target_dir=%%~dpf"
        if "!target_dir!"=="" set "target_dir=."
        call :check_disk_space_mb "!target_dir!"
        call :need_mb_for_gz "!SYSTEM_IMG!"
        if !free_mb! lss !need_mb! (
            echo ОШИБКА: мало места ^(нужно ~!need_mb! МБ, свободно !free_mb! МБ^)
            exit /b 1
        )
        echo Распаковка !SYSTEM_IMG! -^> !out! ^(нужно ~!need_mb! МБ, свободно !free_mb! МБ^)
        set "unp="
        set /p "unp=Продолжить? (y/N): "
        if /i not "!unp!"=="y" exit /b 1
        "%SEVENZIP%" x -y -bso0 -bsp1 "!SYSTEM_IMG!"
        if !errorlevel! neq 0 ( echo ОШИБКА: распаковка .zst! & exit /b 1 )
    )
    set "SYSTEM_IMG=!out!"
)
if not exist "!SYSTEM_IMG!" ( echo После распаковки не найден: !SYSTEM_IMG! & exit /b 1 )
exit /b 0

:: ============================================================
:select_system_img
set "SYSTEM_IMG="
set "s_count=0"
for /f "delims=" %%f in ('dir /b *.img *.img.xz *.img.gz *.img.zst 2^>nul') do (
    set "skip=0"
    echo %%f | findstr /i /c:"vbmeta" /c:"boot" /c:"vendor" /c:"recovery" /c:"super" /c:"dtbo" /c:"userdata" /c:"metadata" /c:"system_dlkm" >nul && set "skip=1"
    if !skip!==0 (
        set /a s_count+=1
        set "sysimg_!s_count!=%%f"
        echo    !s_count!^) %%f
    )
)
if !s_count!==0 ( echo Образы системы не найдены! & exit /b 1 )
if !s_count!==1 (
    set "SYSTEM_IMG=!sysimg_1!"
    echo Найден: !SYSTEM_IMG!
    call :resolve_system_img || exit /b 1
    exit /b 0
)
:sloop
set "sc="
set /p "sc=Номер (0 = отмена): "
if "!sc!"=="0" exit /b 1
echo !sc!| findstr /r "^[0-9][0-9]*$" >nul
if !errorlevel! neq 0 ( echo Неверно. & goto sloop )
if !sc! lss 1 ( echo Неверно. & goto sloop )
if !sc! gtr !s_count! ( echo Неверно. & goto sloop )
call set "SYSTEM_IMG=%%sysimg_!sc!%%"
echo Выбран: !SYSTEM_IMG!
call :resolve_system_img || exit /b 1
exit /b 0

:: ============================================================
:check_and_flash_vbmeta
if not exist "vbmeta.img" (
    echo ВНИМАНИЕ: vbmeta.img не найден! Возможен bootloop из-за AVB.
    set "c="
    set /p "c=Продолжить без vbmeta? (y/N): "
    if /i "!c!"=="y" exit /b 0
    exit /b 1
)
call :get_userspace
if "!is_userspace!"=="yes" (
    echo ВНИМАНИЕ: вы в Fastbootd. Прошивка vbmeta ^(физический раздел^)
    echo может не работать на некоторых устройствах.
)
echo Прошиваю vbmeta...
call :fb_flash --disable-verity --disable-verification flash vbmeta vbmeta.img
if !errorlevel! neq 0 (
    set "c="
    set /p "c=Продолжить без vbmeta? (y/N): "
    if /i not "!c!"=="y" exit /b 1
)
exit /b 0

:: ============================================================
:free_super_space
set "slot=%~1"
if "!slot!"=="" set "slot=!CURRENT_SLOT!"

if "!SYSTEM_IMG!"=="" ( echo ОШИБКА: SYSTEM_IMG не задан. & exit /b 1 )
if not exist "!SYSTEM_IMG!" ( echo ОШИБКА: !SYSTEM_IMG! не найден. & exit /b 1 )

call :verify_sparse_integrity "!SYSTEM_IMG!" || exit /b 1

call :detect_image_size "!SYSTEM_IMG!"
if "!IMG_SIZE!"=="0" ( echo Не удалось определить размер. & exit /b 1 )
echo Raw размер: !IMG_SIZE! байт

call :calculate_partition_size "!IMG_SIZE!"
if "!part_size!"=="0" ( echo Не удалось вычислить размер партиции. & exit /b 1 )
echo Размер партиции: !part_size! байт ^(margin=%MARGIN_MB% МБ^)

:: --- SHA256 verification (0.9.8) ---
echo --------------------------------------------------------
echo ВЕРИФИКАЦИЯ ЦЕЛОСТНОСТИ ОБРАЗА ^(SHA256^):
set "USER_HASH="
if exist "!SYSTEM_IMG!.sha256" (
    echo [INFO] Найден локальный файл контрольной суммы.
    set "USER_HASH=file"
) else (
    echo Скопируйте хеш SHA256 со страницы релиза GitHub
    echo и вставьте его сюда ^(или Enter - пропустить^).
    set /p "USER_HASH=Вставьте хеш: "
)

if not "!USER_HASH!"=="" (
    if /i not "!USER_HASH!"=="file" (
        echo Вычисляю SHA256 образа, подождите...
    )
    set "SHA_RES="
    for /f "usebackq delims=" %%s in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Mode verify_sha256 -Path "!SYSTEM_IMG!" -Hash "!USER_HASH!"`) do set "SHA_RES=%%s"

    echo !SHA_RES! | findstr /b /c:"mismatch" >nul
    if !errorlevel! equ 0 (
        echo ========================================================
        echo ОШИБКА: Контрольная сумма SHA256 НЕ СОВПАДАЕТ!
        echo   Реальный: !SHA_RES!
        echo Образ поврежден. Прошивка приведет к Bootloop.
        echo ========================================================
        set "sha_ok="
        set /p "sha_ok=Продолжить установку на свой риск? (y/N): "
        if /i not "!sha_ok!"=="y" exit /b 1
    ) else if /i "!SHA_RES!"=="ok" (
        echo [SHA256] OK. Образ целостен.
    ) else if /i "!SHA_RES!"=="missing" (
        echo [SHA256] Хеш не распознан ^(ожидалось 64 hex-символа^). Пропуск.
    ) else if /i "!SHA_RES!"=="error_file_too_large" (
        echo [SHA256] Файл .sha256 слишком велик ^(^>4 КБ^). Пропуск.
    ) else if /i "!SHA_RES!"=="error" (
        echo [SHA256] Ошибка при расчете хеша. Пропуск.
    ) else (
        echo [SHA256] Неизвестный ответ хелпера: !SHA_RES!
    )
) else (
    echo [SHA256] Проверка пропущена пользователем.
)
echo --------------------------------------------------------

call :get_sys_part !slot!
set "tpart=!SYS_PART!"

call :get_userspace
if not "!is_userspace!"=="yes" (
    echo Перезагрузка в Fastbootd...
    call :fb_reboot fastboot
    if !errorlevel! neq 0 ( echo Не удалось запустить fastboot. & exit /b 1 )
    call :wait_for_fastboot
    if !errorlevel! neq 0 ( echo Fastbootd не поднялся. & exit /b 1 )
)

echo --------------------------------------------------------
echo РЕКОНСТРУКЦИЯ SUPER:
echo   Тип:         A/B=!IS_AB_DEVICE!
echo   Целевой:     !tpart!
echo   Партиция:    !part_size! байт
echo   НЕ трогаем:  vendor / odm / vendor_dlkm / system_dlkm
echo --------------------------------------------------------
set "c="
set /p "c=Выполнить? (y/N): "
if /i not "!c!"=="y" (
    echo Реконструкция отменена пользователем.
    exit /b 1
)

for /f "usebackq delims=" %%b in (`powershell -NoProfile -Command "if ([UInt64]!part_size! -gt 4GB) { 'yes' } else { 'no' }"`) do set "big=%%b"
if /i "!big!"=="yes" (
    echo ВНИМАНИЕ: ^>4 ГБ. Возможен overflow на MTK.
    set "bo="
    set /p "bo=Продолжить? (y/N): "
    if /i not "!bo!"=="y" exit /b 1
)

if "!IS_AB_DEVICE!"=="yes" (
    if "!slot!"=="a" ( set "opp=b" ) else ( set "opp=a" )
    for %%s in (!slot! !opp!) do (
        for %%p in (system product system_ext) do fastboot delete-logical-partition %%p_%%s >> "%LOG%" 2>&1
    )
) else (
    for %%p in (system product system_ext) do fastboot delete-logical-partition %%p >> "%LOG%" 2>&1
)

echo Создаю !tpart! размером !part_size! байт...
fastboot create-logical-partition !tpart! !part_size! >> "%LOG%" 2>&1
if !errorlevel! neq 0 (
    echo ========================================================
    echo КРИТИЧЕСКАЯ ОШИБКА: create-logical-partition !tpart! провалился.
    echo super без system/product/system_ext. НЕ перезагружайте.
    echo ========================================================
    exit /b 1
)
exit /b 0

:: ============================================================
:backup_data_stream
cls
echo === БЭКАП [%date% %time%] ===
call :wait_for_adb
if !errorlevel! neq 0 ( echo ADB не отвечает. & pause & exit /b 1 )

echo --------------------------------------------------------
adb shell "mount | grep -E '/data|/mnt|f2fs|ext4' || true"
echo --------------------------------------------------------
set "m="
set /p "m=Раздел /data смонтирован? (y/N): "
if /i not "!m!"=="y" ( pause & exit /b 1 )
set "s="
set /p "s=Запустить поток? (y/N): "
if /i not "!s!"=="y" exit /b 1

for /f "usebackq delims=" %%t in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Mode timestamp`) do set "ts=%%t"
set "bdir=backups\data_!ts!"
if not exist "!bdir!" mkdir "!bdir!"
set "bfile=!bdir!\userdata_backup"

if not defined SEVENZIP goto fallback_backup

set "SZ_RUN=%SEVENZIP%"
set "SZ_OUT=!bfile!.tar.7z"
set "ADB_CMD=tar -cf - -C /data --exclude=media --exclude=dalvik-cache --exclude=tombstones --exclude=dropbox ."
echo [%time%] Поток через 7-Zip ^(PS-контроль обоих процессов^)...
set "STREAM_RES="
for /f "usebackq delims=" %%s in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Mode stream_backup -SevenZip "!SZ_RUN!" -Output "!SZ_OUT!" -AdbCmd "!ADB_CMD!"`) do set "STREAM_RES=%%s"

if /i not "!STREAM_RES!"=="ok" (
    echo [ОШИБКА] Поток бэкапа провалился: !STREAM_RES!
    del /f /q "!SZ_OUT!" 2>nul
    pause & exit /b 1
)

"%SZ_RUN%" t "!SZ_OUT!" >nul 2>&1
if !errorlevel! neq 0 ( echo [ОШИБКА] Архив поврежден! & pause & exit /b 1 )

for %%I in ("!SZ_OUT!") do set "arc_size=%%~zI"
if !arc_size! lss 1024 ( echo [ОШИБКА] Архив подозрительно мал ^(^<1KB^)! & pause & exit /b 1 )

for %%I in ("!SZ_OUT!") do echo Готово: !SZ_OUT! [%%~zI байт]
pause
exit /b 0

:fallback_backup
echo [ВНИМАНИЕ] 7-Zip нет. Fallback через adb pull.
set "fb="
set /p "fb=Продолжить? (y/N): "
if /i not "!fb!"=="y" exit /b 1

echo [%time%] Создание архива на устройстве...
adb shell "tar -czf /data/local/tmp/userdata_backup.tar.gz -C /data --exclude=media --exclude=dalvik-cache --exclude=tombstones --exclude=dropbox ." >> "%LOG%" 2>&1
if !errorlevel! neq 0 ( echo [ОШИБКА] tar fail! & pause & exit /b 1 )

echo [%time%] Скачивание...
adb pull /data/local/tmp/userdata_backup.tar.gz "!bfile!.tar.gz" >> "%LOG%" 2>&1
if !errorlevel! neq 0 ( echo [ОШИБКА] adb pull fail! & pause & exit /b 1 )

for %%I in ("!bfile!.tar.gz") do set "arc_size=%%~zI"
if "!arc_size!"=="0" ( echo [ОШИБКА] Архив пустой! & pause & exit /b 1 )

adb shell "rm -f /data/local/tmp/userdata_backup.tar.gz" >> "%LOG%" 2>&1
if !errorlevel! neq 0 (
    echo [ВНИМАНИЕ] не удалось удалить временный архив на устройстве.
    echo Это не критично - файл останется в /data/local/tmp.
)
for %%I in ("!bfile!.tar.gz") do echo Готово: !bfile!.tar.gz [%%~zI байт]
pause
exit /b 0

:: ============================================================
:flash_gki_cores
cls
echo === GKI FLASH [%date% %time%] ===
call :interactive_file_select "boot*.img" "Выберите BOOT:"
if !errorlevel! neq 0 ( pause & exit /b 1 )
set "boot_file=!SELECTED_FILE!"
call :interactive_file_select "vendor_boot*.img" "Выберите VENDOR_BOOT:"
if !errorlevel! neq 0 ( pause & exit /b 1 )
set "vendor_file=!SELECTED_FILE!"

call :wait_for_adb
if !errorlevel! neq 0 ( echo ADB недоступен. & pause & exit /b 1 )
call :fb_reboot_adb bootloader
if !errorlevel! neq 0 ( pause & exit /b 1 )
call :wait_for_fastboot
if !errorlevel! neq 0 ( echo Fastboot не появился. & pause & exit /b 1 )
call :check_bootloader_unlocked || ( pause & exit /b 1 )

call :get_current_slot
set "g="
set /p "g=Прошить в _!CURRENT_SLOT!? (y/N): "
if /i not "!g!"=="y" ( pause & exit /b 0 )
call :fb_flash flash boot_!CURRENT_SLOT! "!boot_file!"        || ( pause & exit /b 1 )
call :fb_flash flash vendor_boot_!CURRENT_SLOT! "!vendor_file!" || ( pause & exit /b 1 )
fastboot erase cache >> "%LOG%" 2>&1
pause & exit /b 0

:: ============================================================
:emergency_slot_fix
cls
echo === EMERGENCY DUAL-SLOT RESTORE [%date% %time%] ===
call :interactive_file_select "boot*.img" "Стабильный BOOT:"
if !errorlevel! neq 0 ( pause & exit /b 1 )
set "b=!SELECTED_FILE!"
call :interactive_file_select "vendor_boot*.img" "Стабильный VENDOR_BOOT:"
if !errorlevel! neq 0 ( pause & exit /b 1 )
set "v=!SELECTED_FILE!"
call :wait_for_fastboot
if !errorlevel! neq 0 ( echo Нет fastboot. & pause & exit /b 1 )
call :check_bootloader_unlocked || ( pause & exit /b 1 )

call :fb_flash flash boot_a        "!b!" || ( pause & exit /b 1 )
call :fb_flash flash vendor_boot_a "!v!" || ( pause & exit /b 1 )
call :fb_flash flash boot_b        "!b!" || ( pause & exit /b 1 )
call :fb_flash flash vendor_boot_b "!v!" || ( pause & exit /b 1 )
fastboot set_active a >> "%LOG%" 2>&1
echo Разметка стабилизирована.
call :fb_reboot
if !errorlevel! neq 0 echo [i] Автоматический reboot не сработал. Запустите "fastboot reboot" вручную.
exit /b 0

:: ============================================================
:interactive_file_select
set "mask=%~1"
set "prompt=%~2"
set "SELECTED_FILE="
set "count=0"
for /f "delims=" %%f in ('dir /b %mask% 2^>nul') do (
    set /a count+=1
    set "file_!count!=%%f"
    echo    !count!^) %%f
)
if !count!==0 ( echo Файлы %mask% не найдены! & exit /b 1 )
if !count!==1 ( set "SELECTED_FILE=!file_1!" & exit /b 0 )
:iloop
set "choice="
set /p "choice=Номер (0 = отмена): "
if "!choice!"=="0" exit /b 1
echo !choice!| findstr /r "^[0-9][0-9]*$" >nul
if !errorlevel! neq 0 ( echo Неверно. & goto iloop )
if !choice! lss 1 ( echo Неверно. & goto iloop )
if !choice! gtr !count! ( echo Неверно. & goto iloop )
call set "SELECTED_FILE=%%file_!choice!%%"
exit /b 0

:: ============================================================
:service_menu
cls
echo ========================================================
echo       СЕРВИСНЫЙ МОДУЛЬ
echo ========================================================
echo    1. ADB-Stream бэкап /data (7-Zip stream)
echo    2. GKI-ядра в активный слот
echo    3. Экстренный откат (оба слота + A)
echo    0. Назад
echo ========================================================
set "s="
set /p "s=Ввод: "
if "%s%"=="0" exit /b 0
if "%s%"=="1" call :backup_data_stream
if "%s%"=="2" call :flash_gki_cores
if "%s%"=="3" call :emergency_slot_fix
goto service_menu

:: ============================================================
:find_7zip
set "SEVENZIP="
if not exist "%~dp07z.exe" goto :f7zip_pf
if not exist "%~dp07z.dll" (
    echo [ВНИМАНИЕ] 7z.exe рядом со скриптом, но 7z.dll отсутствует.
    goto :f7zip_pf
)
set "SEVENZIP=%~dp07z.exe"
exit /b 0

:f7zip_pf
if not exist "%ProgramFiles%\7-Zip\7z.exe" goto :f7zip_pf86
if not exist "%ProgramFiles%\7-Zip\7z.dll" goto :f7zip_pf86
set "SEVENZIP=%ProgramFiles%\7-Zip\7z.exe"
exit /b 0

:f7zip_pf86
if not exist "%ProgramFiles(x86)%\7-Zip\7z.exe" goto :f7zip_notfound
if not exist "%ProgramFiles(x86)%\7-Zip\7z.dll" goto :f7zip_notfound
set "SEVENZIP=%ProgramFiles(x86)%\7-Zip\7z.exe"
exit /b 0

:f7zip_notfound
exit /b 1

:: ============================================================
:reboot_to_fastbootd
echo Перезагрузка в Fastbootd...
call :fb_reboot fastboot
if !errorlevel! neq 0 ( exit /b 1 )
call :wait_for_fastboot
exit /b !errorlevel!

:missing_tools
echo ОШИБКА: adb.exe / fastboot.exe не найдены!
pause
exit /b 1
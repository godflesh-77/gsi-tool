# TODO

## 0.9.9 (PowerShell порт)
- [ ] Каркас gsi-tool.ps1 (шапка, i18n, version check, заглушки функций)
- [ ] Портировать main_menu, action_menu, service_menu
- [ ] Портировать функции flash (fb_flash, fb_reboot, ...)
- [ ] Портировать free_super_space с SHA256-блоком
- [ ] Портировать backup_data_stream через Write-Progress
- [ ] Упростить launcher .cmd до 5 строк
- [ ] Удалить helper.ps1 (слить в основной)
- [ ] Проверка версий adb/fastboot/7z
- [ ] i18n EN/RU
- [ ] Architecture check (x86_64/aarch64)

## 1.0.0
- [ ] lpmake для случаев, когда GSI не влезает
- [ ] -s serial для нескольких устройств
- [ ] set -u в Linux
- [ ] Финальный smoke на живом GSI
- [ ] Публикация репо

## Идеи (не срочно)
- [ ] Прогресс-бар decompress через pv на Linux
- [ ] Backup critical partitions (nvram/persist/modemst)
- [ ] Предупреждение про IMEI в backup_data_stream
- [ ] Унификация шапок всех скриптов
- [ ] Объединение helper-вызовов в super_prep (Linux)
- [ ] -Admin

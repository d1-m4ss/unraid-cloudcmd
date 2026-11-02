# cloudcmd

Cloud Commander (https://github.com/coderaiser/cloudcmd, MIT) в контейнере. Порт 8765 (внутри контейнера 8000), конфиг в /mnt/user/appdata/cloudcmd.
Доступ: логин и пароль заданы владельцем в настройках Cloud Commander (хранятся в appdata/cloudcmd/.cloudcmd.json). Не задавать CLOUDCMD_AUTH в `.env`: переменная перебивает сохранённый конфиг.
Смонтированы только /mnt/user, /mnt/disks, /mnt/remotes (ro); /mnt/diskN и /mnt/cache намеренно не монтируются.
Вкладка на странице Main: плагин `cloudcmd.main`.
Иконка: логотип проекта, лицензия MIT.
Клавиши: Right = войти в папку, Left = подняться на уровень выше. Реализовано патчем `appdata/cloudcmd/patch/user-keys.js` + копией `dist/index.html` образа с добавленным `<script>` (при обновлении образа пересоздать копию: `docker cp cloudcmd:/usr/src/cloudcmd/dist/index.html ...` и снова добавить тег после `cloudcmd.js`).
F5/F6 внутри фрейма на странице Main: задачи копирования/перемещения на сервере (rsync от nobody:users), описания задач на флешке `/boot/config/plugins/cloudcmd.main/jobs/<id>.json`, рабочее состояние в RAM `/var/local/cloudcmd.main/jobs/<id>/` (вне /mnt/user, контейнер до него не дотягивается). Видны списком на Main, переживают закрытие вкладки; Cancel / Resume (rsync докачивает) / Remove. Задачи идут по очереди (flock). После перезапуска контейнера или Unraid задача получает статус interrupted (прогресс в % после перезагрузки теряется) и возобновляется кнопкой Resume. Вне фрейма (отдельная вкладка :8765) F5/F6 работают штатно, без сохранения состояния.
Исходники плагина: plugin/src (jobs.php, job-run.sh, CloudCommander.page), сборка plugin/build.sh.

# Cloud Commander для Unraid

Двухпанельный файловый менеджер ([Cloud Commander](https://github.com/coderaiser/cloudcmd), MIT) внутри интерфейса Unraid.
Состоит из двух частей:

1. **Контейнер** `cloudcmd` (compose-стек для плагина Compose Manager).
2. **Плагин GUI** `cloudcmd.main`: секция «Cloud Commander» на вкладке **Main** перед Boot Device. По умолчанию свёрнута, чтобы случайно ничего не удалить. Копирование и перемещение (F5/F6) выполняются на сервере как фоновые задачи с прогрессом, отменой и возобновлением.

Проверено на Unraid 7.3.4. Нужны: Docker, плагин Compose Manager, rsync (входит в Unraid).

## Что получаешь

- Секция на Main между пулами (ZFS Director) и Boot Device, кнопка **Open Cloud Commander** создаёт фрейм, **Collapse** уничтожает.
- Клавиши: Up/Down, **Right** войти в папку, **Left** подняться выше, F3 просмотр, F4 правка, F7 новая папка, F8 удаление, F9 меню, F10 настройки.
- **F5/F6 во фрейме** запускают задачи на сервере (rsync от `nobody:users`). Список задач виден на Main, переживает закрытие вкладки. Кнопки: Cancel, Resume, Remove, Clear finished. Задачи идут по очереди.
- Если в назначении уже есть такие имена, страница спрашивает отдельно: перезаписать или слить.

## Установка

Дальше `P=/boot/config/plugins/compose.manager/projects/cloudcmd`, команды выполняются на Unraid (SSH) из каталога репозитория.

### 1. Контейнер

```bash
P=/boot/config/plugins/compose.manager/projects/cloudcmd
mkdir -p $P /mnt/user/appdata/cloudcmd/patch
cp compose/docker-compose.yml compose/docker-compose.override.yml compose/description compose/icon_url \
   compose/name compose/project_name compose/autostart compose/profiles compose/README.md $P/
cp compose/.env.example $P/.env
chown -R 99:100 /mnt/user/appdata/cloudcmd
```

Патч интерфейса (скрипт клавиш и тег в `index.html`; он монтируется в контейнер только для чтения):

```bash
A=/mnt/user/appdata/cloudcmd/patch
docker run --rm --entrypoint cat coderaiser/cloudcmd:latest /usr/src/cloudcmd/dist/index.html > $A/index.html
sed -i 's#<script src="{{ prefix }}/dist/cloudcmd.js"></script>#&<script src="{{ prefix }}/dist/user-keys.js?v=1"></script>#' $A/index.html
cp compose/user-keys.js $A/user-keys.js
chown 99:100 $A/*; chmod 644 $A/*
```

Запуск (или кнопка Compose Up в Docker → Compose):

```bash
cd $P && docker compose -p cloudcmd --project-directory $P -f docker-compose.yml -f docker-compose.override.yml --env-file .env up -d
```

Порт хоста **8765** (внутри контейнера 8000), конфиг в `/mnt/user/appdata/cloudcmd`. Смонтированы `/mnt/user`, `/mnt/disks`, `/mnt/remotes` (только чтение). Отдельные диски `/mnt/diskN` и `/mnt/cache` не монтируются намеренно: не смешивать пользовательские шары и диски.

### 2. Пароль

Контейнер без пароля открывает запись в шары всей сети. Задайте логин и пароль: откройте `http://IP:8765/`, **F10** → включите Auth, укажите логин и пароль, сохраните. Пароль хранится хешем в `/mnt/user/appdata/cloudcmd/.cloudcmd.json`. Не задавайте `CLOUDCMD_AUTH` в `.env`: переменная перекрывает сохранённый конфиг.

### 3. Плагин GUI

```bash
cp plugin/cloudcmd.main.plg /boot/config/plugins/cloudcmd.main.plg
plugin install /boot/config/plugins/cloudcmd.main.plg
```

Если плагин той же версии уже стоит, `plugin install` ничего не делает: сначала `plugin remove cloudcmd.main.plg` (копию файла сохраните вне `/boot/config/plugins`), затем установка. Плагин ставится при каждой загрузке из `/boot/config/plugins`.

Файл `.plg` собирается из `plugin/src/` скриптом `plugin/build.sh <версия>` (нужны bash и xmllint).

## Использование

1. Откройте **Main**, секция Cloud Commander. **Первый раз** нажмите «Open in new tab» и войдите: браузер не показывает окно логина внутри фрейма с другого порта, после входа в новой вкладке браузер обычно запоминает логин для этого порта, и фрейм открывается.
2. Нажмите **Open Cloud Commander**, кликните внутрь фрейма. Панели: Tab переключает, Right/Left ходят по папкам.
3. Выделите файлы (Insert или пробел) и нажмите **F5** (копировать) или **F6** (переместить) в активной панели, цель: папка в другой панели. Подтвердите. Под плашкой появится строка задачи.
4. Задачу можно отменить и позже возобновить: rsync докачивает с места остановки. Завершённые задачи удаляются кнопкой Remove или Clear finished.
5. Удаление (F8) и переименование выполняются сразу, корзины нет.

Что важно знать:

- Если открыть Cloud Commander отдельной вкладкой (`:8765`), F5/F6 работают штатно, но без сохранения прогресса: окно прогресса живёт только во вкладке.
- Если Unraid открыт по HTTPS (например через Tailscale), браузер не встроит HTTP-фрейм. Страница покажет подсказку, используйте «Open in new tab».
- Перемещение копирует файлы по-настоящему (`--ignore-times`) и удаляет источник только после успешной передачи.
- Операции выполняются от `nobody:users` (99:100): файлы, недоступные этому пользователю, не скопируются.

## Где хранится состояние

| Что | Где |
| --- | --- |
| Описание задач (переживает перезагрузку) | `/boot/config/plugins/cloudcmd.main/jobs/<id>.json` |
| Рабочее состояние, прогресс, лог rsync (RAM) | `/var/local/cloudcmd.main/jobs/<id>/` |
| Конфиг и пароль Cloud Commander | `/mnt/user/appdata/cloudcmd/.cloudcmd.json` |
| Патч интерфейса | `/mnt/user/appdata/cloudcmd/patch/` |

Состояние намеренно хранится вне `/mnt/user`: контейнер может писать в шары и не должен подменять файлы, с которыми работает код плагина от root. После перезагрузки Unraid запущенная копия прерывается, задача показывается как `interrupted` без процента, Resume докачивает.

## Изменение настроек

- **Порт:** `ports` в `docker-compose.yml` и `$cc_port` в `plugin/src/CloudCommander.page`, затем `plugin/build.sh <новая версия>` и переустановка плагина.
- **Новая версия образа:** `docker compose ... pull && up -d`. Копию `patch/index.html` пересоздайте командами из шага 1, иначе будет использоваться старая страница.
- **Изменили `user-keys.js`:** увеличьте число в `?v=` в `patch/index.html`, иначе браузер возьмёт старый скрипт из кэша.

## Удаление

```bash
plugin remove cloudcmd.main.plg
cd $P && docker compose -p cloudcmd --project-directory $P -f docker-compose.yml -f docker-compose.override.yml down
rm -rf $P /mnt/user/appdata/cloudcmd /boot/config/plugins/cloudcmd.main /var/local/cloudcmd.main
```

## Если не работает

- **Фрейм пустой или белый:** выполните вход в новой вкладке (`http://IP:8765/`), проверьте `docker ps` и обновите страницу (Ctrl+F5).
- **F5/F6 ничего не делают, копирование идёт «по-старому»:** браузер держит старый `user-keys.js`. Увеличьте `?v=` и перезапустите контейнер, затем Ctrl+F5.
- **Задача висит в `interrupted`:** процесс остановили (перезапуск контейнера, перезагрузка, kill). Нажмите Resume. Лог: `/var/local/cloudcmd.main/jobs/<id>/w/rsync.err`.
- **Задача в `failed`:** сообщение показано в строке задачи и в её подсказке (rsync, права, место на диске).
- **Секция не появилась на Main:** `ls /usr/local/emhttp/plugins/cloudcmd.main`, права каталога должны быть `755`, затем `plugin install`.

## Состав репозитория

```
compose/    docker-compose.yml, override с метками и иконкой, метаданные Compose Manager,
            user-keys.js (стрелки, F5/F6), .env.example
plugin/     cloudcmd.main.plg (собранный), build.sh, CHANGES.txt
plugin/src/ CloudCommander.page (секция на Main), jobs.php (API задач), job-run.sh (раннер rsync)
```

## Безопасность

- Логин и пароль обязательны. Контейнер открывает на запись `/mnt/user`, а консоль Cloud Commander включена.
- `jobs.php` работает от root в webGUI и запускается только по сессии Unraid с CSRF-токеном. Пути проверяются по списку корней, имена с управляющими символами отклоняются, rsync получает `--` и абсолютные пути, раннер запускается с правами `nobody:users` без привилегий.
- Страница принимает сообщения только от своего фрейма (проверка источника и origin).

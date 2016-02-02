Nanny
========
Это кастомная русская версия программы NannyBot для игры Call of Duty 2. Оригинальным автором этой программы является smugllama. Написана полностью на Perl.
Оригинал можно скачать по этой ссылке http://smaert.com/nannybot.zip

По сравнению с оригиналом, все сообщения были переведены на русский язык,
также было исправлено много ошибок, оптимизирован код, переработаны некоторые функции, добавлено много новых !команд и т.д

Примечание:

Так как русская версия Call of Duty 2 использует кодировку Windows-1251, то любые изменения в конфиг-файле
или самой программе должны быть применены с учетом этой кодировки. Командная строка или терминал по умолчанию
не используют данную кодировку, как добавить ее поддержку описано ниже.

Поддержка кодировки Windows-1251:

В Windows чтобы отображался русский язык необходимо в свойствах командной строки указать шрифт "Lucida Console"

В Linux в параметрах терминала установить кодировку Windows-1251

В Mac OSX поддержки кодировки нет

Интсрукция по запуску в Windows:

1. Скачать и установить Strawberry Perl http://strawberryperl.com или ActivePerl http://www.activestate.com/activeperl/downloads
2. Настроить необходимые параметры в nanny.cfg
3. Запустить. В Windows можно запускать через nanny.bat

Интсрукция по запуску в *nix:

1. Установить через CPAN (http://www.cpan.org/modules/INSTALL.html) зависимые модули: DBI, DBD::SQLite, Time::HiRes, LWP::Simple (Некоторые могут уже быть установлены, зависит от дистрибутива)
2. Настроить необходимые параметры в nanny.cfg
3. Запустить в терминале. В *nix можно запускать через nanny.sh

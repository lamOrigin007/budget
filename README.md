# Family Budget

## Обзор
Система учёта расходов членов семьи и ведения семейного бюджета. Решает задачи совместного планирования, контроля лимитов, учёта долгов, накоплений и обмена финансовыми данными между участниками семьи.

### Цели
- Предоставить единую платформу для семей с 2–10 пользователями.
- Обеспечить доступ с веба (десктоп/мобайл), Android и iOS.
- Поддержать локализацию (RU, подготовка к EN) и мультивалютность.

### Пользователи
- Владелец семьи — управляет настройками, лимитами, членами семьи.
- Взрослый участник — добавляет операции, бюджеты, управляет счётами.
- Подросток/гость — ограниченные права, видимость только разрешённых данных.

---

## Архитектура системы
```
┌─────────────┐    REST + WebSocket    ┌────────────────────┐
│  Next.js    │◄──────────────────────►│       Go API       │
│  Frontend   │                        │ (Echo/Fiber, sqlc) │
└─────────────┘                        └─────────┬──────────┘
        ▲                                      Background
        │ GraphQL/REST SDK                     Workers/Jobs
        │                                            │
┌─────────────┐                                    ▼
│ Android/iOS │◄────────────── Sync/API ─────────┌───────┐
│  Клиенты    │                                  │Redis? │
└─────────────┘                                  └───────┘
        │                                            │
        └─────────────── gRPC/HTTP ──────────────────┘
                         │
                     ┌───────┐
                     │Postgre│
                     │  SQL  │
                     └───────┘
```
- **Backend**: модульный сервис на Go (Echo или Fiber), REST API + WebSocket, фоновые задачи, Redis/NATS при необходимости.
- **Frontend**: Next.js + TypeScript, Zustand/Redux Toolkit, React Query, WebSocket/SSE для реалтайм-обновлений.
- **Мобильные клиенты**: Kotlin (Android, Jetpack Compose, Room, WorkManager), Swift (iOS, SwiftUI, CoreData/SQLite, BackgroundTasks).
- **Хранилище**: PostgreSQL ≥14, миграции через golang-migrate, кэш Redis.
- **Инфраструктура**: Docker/Compose/Helm, окружения dev/stage/prod, деплой в облако (Fly.io/Render/Kubernetes).

---

## Ключевые возможности
- Совместные и личные бюджеты с лимитами по категориям и переносом остатка.
- Категории с иерархией, конверты и цели накоплений.
- Импорт банковских выписок (CSV/Excel) с маппингом колонок и предпросмотром.
- Регулярные операции, напоминания, учёт долгов и займов.
- Мультивалютность с хранением исторических курсов и перерасчётом в базовой валюте семьи.
- Аналитика (дашборды, отчёты, фильтры) и экспорт в CSV/PDF.
- Офлайн-режим на мобильных устройствах с последующей синхронизацией.
- Уведомления (push/email) и реалтайм-события (WebSocket).
- RBAC, аудит действий и безопасность (Argon2id/BCrypt, JWT, rate limiting).

---

## Модель данных (основные сущности)
- **users**: id, family_id, email, password_hash, name, role [owner|adult|junior], locale, currency_default, created_at, updated_at.
- **families**: id, name, country, currency_base, created_at.
- **accounts**: id, family_id, name, type [cash|card|bank|e-wallet], currency, balance (расчётный), is_archived, created_at.
- **categories**: id, family_id, parent_id, name, type [expense|income|transfer], color, is_system.
- **budgets**: id, family_id, period [month|week|custom], start_date, end_date, total_limit, currency.
- **budget_items**: id, budget_id, category_id, limit_amount, carryover [bool].
- **transactions**: id, family_id, account_id, category_id, user_id, type [expense|income|transfer], amount_minor, currency, exchange_rate, amount_base_minor, description, merchant, tags[], occurred_at, created_at, updated_at, recurrence_id.
- **recurrences**: id, family_id, rule (RRULE/cron-like), next_run_at, template_json.
- **envelopes**: id, family_id, name, currency, target_amount_minor, current_amount_minor, auto_fill_rule.
- **goals**: id, family_id, name, target_amount_minor, due_date, priority.
- **debts**: id, family_id, counterparty, direction [we_owe|they_owe], amount_minor, currency, due_date, notes.
- **attachments**: id, family_id, transaction_id, file_url, mime, size.
- **audit_logs**: id, family_id, user_id, action, entity, entity_id, payload_json, created_at.
- **invites**: id, family_id, email, role, token, expires_at, accepted_at.
- **exchange_rates**: id, base, quote, rate, as_of.

Замечания:
- Денежные суммы — в minor units (целые числа) для точности.
- Дублирование сумм в базовой валюте семьи (amount_base_minor) по курсу на дату операции.
- Полнотекстовый поиск по описанию/тегам транзакций (pg_trgm / FTS).

---

## Функциональные возможности
### Управление пользователями и семьями
- Регистрация/вход, восстановление пароля, приглашение в семью по роли.
- Редактирование профиля, смена базовой валюты/языка (пересчёт на клиенте).

### Счета и категории
- CRUD счетов, типы, архивация.
- Древовидные категории, системные + пользовательские.

### Операции и импорт
- CRUD транзакций, вложения (чеки), теги, мерчант.
- Переводы между счетами (двойная запись).
- Импорт CSV/Excel, регулярные операции, мультивалютность.

### Бюджеты, конверты, цели, долги
- Периодические бюджеты, перенос остатка, конверты с авто-пополнением.
- Цели накоплений и долги с напоминаниями.

### Аналитика и отчёты
- Дашборды, фильтры, экспорт отчётов, сохранённые пресеты.

### Уведомления и события
- Push/email, реалтайм WebSocket для ключевых событий (лимит достигнут, операция создана и т. д.).

### Офлайн-режим
- Кэш справочников, очередь локальных изменений, стратегия «последняя правка выигрывает».

---

## Нефункциональные требования
- **Производительность**: p95 < 150 мс на основные API, импорт 5–10k строк < 60 сек (background).
- **Масштабируемость**: горизонтальное масштабирование API, шардирование по family_id в будущем.
- **Надёжность**: SLO доступности 99.9%, ежедневные бэкапы (30 дней хранения).
- **Безопасность**: Argon2id/BCrypt, JWT с ротацией refresh, RBAC, RLS/фильтрация по family_id, CSRF защита, rate limiting.
- **Конфиденциальность**: шифрование at-rest (S3/KMS), TLS in-transit, минимизация PII в логах.
- **Локализация**: i18n, формат дат/валют по локали.

---

## Архитектурные рекомендации
- Строгая типизация денег, единый модуль валют.
- Мягкое удаление (deleted_at) для справочников и операций.
- Идемпотентность импортов (idempotency-key).
- OpenAPI-спека и автогенерация клиентов (TS/Kotlin/Swift).
- Время: `TIMESTAMPTZ` (UTC), отображение по локали на клиенте.
- Идентификаторы: UUID v4.

---

## Архитектура CI/CD и качество
- GitHub Actions: линтеры, тесты, миграции, сборка Docker-образов, деплой.
- Тестирование: юнит (>70% доменной логики), интеграционные (API+БД), контрактные (OpenAPI), E2E (Playwright, Detox/Compose), нагрузочные (k6/JMeter).
- Логирование: JSON, OpenTelemetry, аудит CRUD.
- Мониторинг: Prometheus, алерты по SLO/SLA, очередям задач.

---

## Badges
- CI: _TODO (GitHub Actions badge)_
- Линтеры: _TODO_
- Тесты: _TODO_

---

## Документация
- [Импорт выписок](docs/imports.md)
- [Мультивалютность](docs/currency.md)
- [Каталог событий](docs/events.md)
- [Офлайн-синхронизация](docs/offline-sync.md)
- [API Governance](docs/api-governance.md)
- [Бюджеты и Carryover](docs/budgets.md)
- Дополнительно: `openapi.yaml`, директория миграций `/migrations`.

---

## Запуск локально
1. **Docker Compose**
   ```bash
   docker compose up --build
   ```
   Приложение поднимется на `http://localhost:8080`.

2. **Проверка API**
   - http://localhost:8080/healthz
   - http://localhost:8080/swagger/

3. **Только БД + миграции**
   ```bash
   docker run --name fb-postgres -p 5432:5432 \
     -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=family_budget -d postgres:15

   docker run --rm -v $(pwd):/repo --network host migrate/migrate \
     -path=/repo/migrations \
     -database "postgres://postgres:postgres@localhost:5432/family_budget?sslmode=disable" up
   ```

4. **Запуск backend вручную**
   ```bash
   cd backend
   go run ./cmd/api
   ```

5. **Запуск веб-клиента**
   ```bash
   cd web
   npm install
   npm run dev
   ```
   В браузере приложение будет доступно по адресу `http://localhost:3000`. Бекенд ожидается на `http://localhost:8080` (можно переопределить через переменную окружения `NEXT_PUBLIC_API_BASE`).

6. **Мобильные клиенты**
   - **Android**: открыть проект в Android Studio (`mobile/android`), синхронизировать Gradle и запустить `app` на эмуляторе. Используется Compose UI, запросы отправляются на `http://10.0.2.2:8080` (эмулятор Android).
   - **iOS**: открыть `mobile/ios/FamilyBudget` в Xcode, выбрать симулятор и запустить. Клиент обращается к API на `http://localhost:8080`.

---

## Разработка
- **OpenAPI**: `openapi.yaml` в корне репозитория. Генерация:
  ```bash
  npx openapi-typescript openapi.yaml -o web/src/lib/api.ts
  ```
  Для Kotlin/Swift используйте OpenAPI Generator.
- **Миграции**: `/migrations`, выполняются через `golang-migrate`.
- **CI/CD**: GitHub Actions — lint/test/build/deploy (см. `.github/workflows/*`).
- **Структура проекта (рекомендация)**:
  ```
  backend/
    cmd/api/
    internal/
      http/
      auth/
      domain/
      store/
      migrate/
  web/
    app/
    components/
  mobile/
    android/
    ios/
  migrations/
  openapi.yaml
  ```

---

## Развёртывание
- Версионирование API: `/api/v1` с подготовкой к `/v2`.
- Rollout: Blue-Green/Canary (Kubernetes), сборка Docker-образов для API/отчётного сервиса.
- Секреты: .env для dev, KMS/Secret Manager для prod.
- Резервное копирование БД и проверка восстановления еженедельно.

---

## Лицензия
Проект распространяется под лицензией MIT. См. [LICENSE](LICENSE).


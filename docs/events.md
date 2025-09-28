# Каталог событий

## Каналы доставки
- **WebSocket**: подписка на `/ws?token=...`, формат сообщений — JSON.
- **Push**: Firebase/APNS, payload с сокращённым набором полей.
- **Email**: шаблоны в `templates/email/*`, отправка через очередь.

## Гарантии доставки
- WebSocket — at-most-once, восстановление через повторную подписку.
- Push — best effort (повтор через экспоненциальный backoff).
- Email — гарантированная доставка, повтор до 5 раз, DLQ после.

## Таблица событий
| Код | Канал | Триггер | Payload | Версия |
|-----|-------|---------|---------|--------|
| `transaction.created` | WS/Push | Создана транзакция | См. JSON ниже | v1 |
| `transaction.updated` | WS | Изменена транзакция | См. JSON ниже | v1 |
| `budget.limit_reached` | WS/Push/Email | Потрачено ≥ 100% лимита | `budget_id`, `category_id`, `percent` | v1 |
| `budget.warning` | WS/Push | Потрачено ≥ 80% лимита | `budget_id`, `category_id`, `percent` | v1 |
| `goal.completed` | WS/Push/Email | Достижение цели накопления | `goal_id`, `name`, `completed_at` | v1 |
| `import.completed` | Email | Импорт завершён | `import_id`, `total`, `duplicates`, `warnings` | v1 |
| `import.failed` | Email | Ошибка импорта | `import_id`, `error_code`, `message` | v1 |
| `exchange_rate.delayed` | Email | SLA обновления курсов нарушен | `base`, `quote`, `delayed_minutes` | v1 |
| `debt.due_soon` | Push/Email | До срока долга ≤3 дня | `debt_id`, `due_date`, `amount` | v1 |
| `invite.accepted` | WS/Email | Новый участник присоединился | `family_id`, `user_id`, `role` | v1 |

## Формат сообщений
```json
{
  "event": "transaction.created",
  "version": "v1",
  "timestamp": "2024-06-20T08:01:23.456Z",
  "family_id": "fam_01HZZ...",
  "payload": {
    "transaction_id": "txn_01HZZ...",
    "account_id": "acc_01HZZ...",
    "category_id": "cat_food",
    "amount_minor": -15990,
    "currency": "RUB",
    "occurred_at": "2024-06-19T18:45:00Z",
    "created_by": "usr_01HZZ..."
  }
}
```

### Push payload (сжатый)
```json
{
  "event": "budget.limit_reached",
  "version": "v1",
  "data": {
    "budget_id": "bud_2024_06",
    "category_id": "cat_transport",
    "percent": 104
  }
}
```

### Email шаблон
- Используется `event` как ключ шаблона (`emails/budget.limit_reached.html`).
- Параметры передаются в контекст шаблона, поддерживается i18n.

## Версионирование событий
- Каждое событие имеет поле `version`.
- При изменении структуры payload увеличиваем версию (`v2`), клиенты могут подписаться на конкретную версию.
- Для обратной совместимости допускается дублирование события с разными версиями до sunset периода.


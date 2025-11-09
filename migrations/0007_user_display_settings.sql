-- Добавляем хранение пользовательских настроек отображения
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS display_settings JSONB NOT NULL DEFAULT jsonb_build_object(
        'theme', 'system',
        'density', 'comfortable',
        'show_archived', false,
        'show_totals_in_family_currency', true
    );

-- Обновляем существующие записи, у которых настройки ещё пустые
UPDATE users
SET display_settings = jsonb_build_object(
        'theme', 'system',
        'density', 'comfortable',
        'show_archived', false,
        'show_totals_in_family_currency', true
    )
WHERE display_settings = '{}'::jsonb;

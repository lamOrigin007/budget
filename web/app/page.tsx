'use client';

import { FormEvent, useMemo, useState } from 'react';
import {
  Category,
  CategoryPayload,
  RegisterResponse,
  Transaction
} from '../src/lib/api';
import {
  registerUser,
  fetchCategories,
  createTransaction,
  fetchTransactions,
  createCategory,
  updateCategory,
  setCategoryArchived
} from '../src/lib/api';

type Step = 'register' | 'dashboard';

export default function Home() {
  const [step, setStep] = useState<Step>('register');
  const [registerError, setRegisterError] = useState<string | null>(null);
  const [userData, setUserData] = useState<RegisterResponse | null>(null);
  const [categories, setCategories] = useState<Category[]>([]);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [createError, setCreateError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isCategorySubmitting, setIsCategorySubmitting] = useState(false);
  const [categoryError, setCategoryError] = useState<string | null>(null);
  const [editingCategoryId, setEditingCategoryId] = useState<string | null>(null);
  const [categoryForm, setCategoryForm] = useState<{
    name: string;
    type: 'income' | 'expense' | 'transfer';
    color: string;
    description: string;
    parent_id: string;
  }>({
    name: '',
    type: 'expense',
    color: '#0ea5e9',
    description: '',
    parent_id: ''
  });

  const activeCategories = useMemo(
    () => categories.filter((category) => !category.is_archived),
    [categories]
  );
  const archivedCategories = useMemo(
    () => categories.filter((category) => category.is_archived),
    [categories]
  );

  async function handleRegister(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
      setRegisterError(null);
      const formData = new FormData(event.currentTarget);
      setIsSubmitting(true);
      try {
        const response = await registerUser({
        email: String(formData.get('email') ?? ''),
        password: String(formData.get('password') ?? ''),
        name: String(formData.get('name') ?? ''),
        currency: String(formData.get('currency') ?? 'RUB'),
        locale: String(formData.get('locale') ?? 'ru-RU'),
        family_name: String(formData.get('family_name') ?? '')
      });
      setUserData(response);
      const cats = await fetchCategories(response.user.id);
      setCategories(cats);
      const tx = await fetchTransactions(response.user.id);
      setTransactions(tx);
      setStep('dashboard');
      event.currentTarget.reset();
    } catch (error) {
      setRegisterError(error instanceof Error ? error.message : 'Не удалось зарегистрироваться');
    } finally {
      setIsSubmitting(false);
      }
  }

  async function handleCreateTransaction(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!userData) return;
    setCreateError(null);
    const formData = new FormData(event.currentTarget);
    setIsSubmitting(true);
    try {
      const transaction = await createTransaction({
        user_id: userData.user.id,
        category_id: String(formData.get('category_id') ?? ''),
        type: String(formData.get('type') ?? 'expense') as 'income' | 'expense',
        amount_minor: Number(formData.get('amount_minor') ?? 0),
        currency: userData.user.currency_default,
        description: String(formData.get('description') ?? ''),
        occurred_at: new Date(String(formData.get('occurred_at') ?? new Date().toISOString())).toISOString()
      });
      setTransactions((prev) => [transaction, ...prev]);
      event.currentTarget.reset();
    } catch (error) {
      setCreateError(error instanceof Error ? error.message : 'Не удалось создать операцию');
    } finally {
      setIsSubmitting(false);
    }
  }

  function resetCategoryForm() {
    setCategoryForm({ name: '', type: 'expense', color: '#0ea5e9', description: '', parent_id: '' });
    setEditingCategoryId(null);
  }

  function sortCategories(list: Category[]) {
    return [...list].sort((a, b) => {
      if (a.is_archived !== b.is_archived) {
        return a.is_archived ? 1 : -1;
      }
      return a.name.localeCompare(b.name, 'ru');
    });
  }

  async function handleCategorySubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!userData) return;
    setCategoryError(null);
    setIsCategorySubmitting(true);
    const payload: CategoryPayload = {
      name: categoryForm.name.trim(),
      type: categoryForm.type,
      color: categoryForm.color,
      description: categoryForm.description.trim(),
      parent_id: categoryForm.parent_id ? categoryForm.parent_id : null
    };

    try {
      let category: Category;
      if (editingCategoryId) {
        category = await updateCategory(userData.user.id, editingCategoryId, payload);
      } else {
        category = await createCategory(userData.user.id, payload);
      }
      setCategories((prev) => {
        const next = editingCategoryId
          ? prev.map((item) => (item.id === category.id ? category : item))
          : [...prev, category];
        return sortCategories(next);
      });
      resetCategoryForm();
    } catch (error) {
      setCategoryError(error instanceof Error ? error.message : 'Не удалось сохранить категорию');
    } finally {
      setIsCategorySubmitting(false);
    }
  }

  function handleCategoryEdit(category: Category) {
    setEditingCategoryId(category.id);
    setCategoryForm({
      name: category.name,
      type: category.type,
      color: category.color,
      description: category.description ?? '',
      parent_id: category.parent_id ?? ''
    });
  }

  async function handleCategoryArchive(category: Category, archived: boolean) {
    if (!userData) return;
    setCategoryError(null);
    setIsCategorySubmitting(true);
    try {
      const updated = await setCategoryArchived(userData.user.id, category.id, { archived });
      setCategories((prev) => sortCategories(prev.map((item) => (item.id === updated.id ? updated : item))));
      if (editingCategoryId === category.id && archived) {
        resetCategoryForm();
      }
    } catch (error) {
      setCategoryError(error instanceof Error ? error.message : 'Не удалось обновить статус категории');
    } finally {
      setIsCategorySubmitting(false);
    }
  }

  const availableParents = useMemo(() => {
    return activeCategories.filter((category) => category.id !== editingCategoryId);
  }, [activeCategories, editingCategoryId]);

  if (step === 'register') {
    return (
      <main className="view">
        <div className="shell">
          <h1 className="title">Создайте семейный профиль</h1>
          <p className="subtitle">
            Зарегистрируйте владельца семьи, чтобы начать вести общий бюджет. Все операции будут привязаны к созданному пользователю.
          </p>
          <form onSubmit={handleRegister} className="form-grid">
            <div className="input-group">
              <label htmlFor="name">Имя</label>
              <input id="name" name="name" required className="input" />
            </div>
            <div className="input-group">
              <label htmlFor="email">Email</label>
              <input id="email" name="email" type="email" required className="input" />
            </div>
            <div className="input-group">
              <label htmlFor="password">Пароль</label>
              <input id="password" name="password" type="password" required className="input" />
            </div>
            <div className="form-grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))' }}>
              <div className="input-group">
                <label htmlFor="currency">Базовая валюта</label>
                <input id="currency" name="currency" defaultValue="RUB" className="input" />
              </div>
              <div className="input-group">
                <label htmlFor="locale">Локаль</label>
                <input id="locale" name="locale" defaultValue="ru-RU" className="input" />
              </div>
            </div>
            <div className="input-group">
              <label htmlFor="family_name">Название семьи</label>
              <input id="family_name" name="family_name" placeholder="Семья Ивановых" className="input" />
            </div>
            {registerError && <p className="error">{registerError}</p>}
            <button type="submit" disabled={isSubmitting} className="button">
              {isSubmitting ? 'Создание...' : 'Создать семью'}
            </button>
          </form>
        </div>
      </main>
    );
  }

  return (
    <main className="dashboard">
      <section className="panel">
        <div className="panel-header">
          <div>
            <h1 className="title" style={{ fontSize: '2.25rem', marginBottom: '0.25rem' }}>{userData?.family.name}</h1>
            <p className="meta">Валюта семьи: {userData?.family.currency_base}</p>
          </div>
          <div className="meta" style={{ textAlign: 'right' }}>
            <div>Владелец</div>
            <div style={{ fontWeight: 600, color: '#e2e8f0' }}>{userData?.user.name}</div>
            <div style={{ fontSize: '0.75rem' }}>{userData?.user.email}</div>
          </div>
        </div>
        <p className="highlight">
          Активные статьи бюджета: {activeCategories.map((category) => category.name).join(', ') || 'добавьте первую категорию'}
        </p>
      </section>

      <div className="dashboard-columns">
        <article className="panel">
          <h2>{editingCategoryId ? 'Редактирование категории' : 'Новая категория'}</h2>
          <form onSubmit={handleCategorySubmit} className="form-grid">
            <div className="input-group">
              <label htmlFor="category_name">Название статьи</label>
              <input
                id="category_name"
                name="category_name"
                className="input"
                value={categoryForm.name}
                onChange={(event) => setCategoryForm((prev) => ({ ...prev, name: event.target.value }))}
                required
              />
            </div>
            <div className="input-group">
              <label htmlFor="category_type">Тип движения</label>
              <select
                id="category_type"
                name="category_type"
                className="select"
                value={categoryForm.type}
                onChange={(event) =>
                  setCategoryForm((prev) => ({ ...prev, type: event.target.value as CategoryPayload['type'] }))
                }
              >
                <option value="expense">Расход</option>
                <option value="income">Доход</option>
                <option value="transfer">Перевод</option>
              </select>
            </div>
            <div className="input-group">
              <label htmlFor="category_color">Цвет</label>
              <input
                id="category_color"
                name="category_color"
                className="input"
                value={categoryForm.color}
                onChange={(event) => setCategoryForm((prev) => ({ ...prev, color: event.target.value }))}
                placeholder="#0ea5e9"
              />
            </div>
            <div className="input-group">
              <label htmlFor="category_parent">Родительская статья</label>
              <select
                id="category_parent"
                name="category_parent"
                className="select"
                value={categoryForm.parent_id}
                onChange={(event) => setCategoryForm((prev) => ({ ...prev, parent_id: event.target.value }))}
              >
                <option value="">Без родителя</option>
                {availableParents.map((category) => (
                  <option key={category.id} value={category.id}>
                    {category.name}
                  </option>
                ))}
              </select>
            </div>
            <div className="input-group" style={{ gridColumn: '1 / -1' }}>
              <label htmlFor="category_description">Описание статьи</label>
              <textarea
                id="category_description"
                name="category_description"
                className="textarea"
                rows={3}
                value={categoryForm.description}
                onChange={(event) => setCategoryForm((prev) => ({ ...prev, description: event.target.value }))}
                placeholder="Например: регулярные траты на обучение или спортивные секции"
              />
            </div>
            {categoryError && <p className="error">{categoryError}</p>}
            <div style={{ display: 'flex', gap: '0.75rem' }}>
              <button type="submit" className="button" disabled={isCategorySubmitting}>
                {isCategorySubmitting ? 'Сохранение...' : editingCategoryId ? 'Сохранить изменения' : 'Создать категорию'}
              </button>
              {editingCategoryId && (
                <button type="button" className="button" onClick={resetCategoryForm} disabled={isCategorySubmitting}>
                  Отмена
                </button>
              )}
            </div>
          </form>
        </article>

        <article className="panel">
          <h2>Новая операция</h2>
          <form onSubmit={handleCreateTransaction} className="form-grid">
            <div className="input-group">
              <label htmlFor="type">Тип</label>
              <select id="type" name="type" className="select">
                <option value="expense">Расход</option>
                <option value="income">Доход</option>
              </select>
            </div>
            <div className="input-group">
              <label htmlFor="category_id">Категория</label>
              <select id="category_id" name="category_id" className="select">
                {activeCategories.map((category) => (
                  <option key={category.id} value={category.id}>
                    {category.name}
                  </option>
                ))}
              </select>
            </div>
            <div className="input-group">
              <label htmlFor="amount_minor">Сумма (в копейках)</label>
              <input id="amount_minor" name="amount_minor" type="number" min="1" required className="input" />
            </div>
            <div className="input-group">
              <label htmlFor="occurred_at">Дата операции</label>
              <input id="occurred_at" name="occurred_at" type="datetime-local" className="input" />
            </div>
            <div className="input-group">
              <label htmlFor="description">Описание</label>
              <textarea id="description" name="description" rows={3} className="textarea" />
            </div>
            {createError && <p className="error">{createError}</p>}
            <button type="submit" disabled={isSubmitting} className="button">
              {isSubmitting ? 'Сохранение...' : 'Добавить операцию'}
            </button>
          </form>
        </article>

        <article className="panel">
          <h2>Операции пользователя</h2>
          {transactions.length === 0 && <p className="highlight">Пока нет операций. Добавьте первую операцию.</p>}
          <ul className="transactions">
            {transactions.map((transaction) => {
              const category = categories.find((cat) => cat.id === transaction.category_id);
              const amount = (transaction.amount_minor / 100).toFixed(2);
              const sign = transaction.type === 'income' ? '+' : '-';
              const color = transaction.type === 'income' ? '#34d399' : '#f87171';
              return (
                <li key={transaction.id} className="transaction-item">
                  <div>
                    <p style={{ fontWeight: 600, color: category?.color ?? '#e2e8f0' }}>{category?.name ?? 'Категория'}</p>
                    <p className="meta">{new Date(transaction.occurred_at).toLocaleString()}</p>
                    {transaction.description && <p className="highlight" style={{ color: '#e2e8f0', marginTop: '0.35rem' }}>{transaction.description}</p>}
                  </div>
                  <div className="amount" style={{ color }}>
                    {sign}
                    {amount} {transaction.currency}
                  </div>
                </li>
              );
            })}
          </ul>
        </article>
      </div>

      <section className="panel">
        <h2>Справочник категорий</h2>
        {categories.length === 0 && <p className="highlight">Добавьте первую статью движения средств для семьи.</p>}
        {activeCategories.length > 0 && (
          <div style={{ marginBottom: '1.5rem' }}>
            <h3 style={{ fontSize: '1rem', marginBottom: '0.5rem' }}>Активные</h3>
            <ul className="transactions">
              {activeCategories.map((category) => (
                <li key={category.id} className="transaction-item" style={{ alignItems: 'flex-start' }}>
                  <div>
                    <p style={{ fontWeight: 600, color: category.color }}>{category.name}</p>
                    <p className="meta">Тип: {category.type === 'income' ? 'Доход' : category.type === 'expense' ? 'Расход' : 'Перевод'}</p>
                    {category.description && <p className="highlight">{category.description}</p>}
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                    <button className="button" onClick={() => handleCategoryEdit(category)} disabled={isCategorySubmitting}>
                      Изменить
                    </button>
                    {!category.is_system && (
                      <button
                        className="button"
                        onClick={() => handleCategoryArchive(category, true)}
                        disabled={isCategorySubmitting}
                      >
                        Архивировать
                      </button>
                    )}
                  </div>
                </li>
              ))}
            </ul>
          </div>
        )}
        {archivedCategories.length > 0 && (
          <div>
            <h3 style={{ fontSize: '1rem', marginBottom: '0.5rem' }}>Архив</h3>
            <ul className="transactions">
              {archivedCategories.map((category) => (
                <li key={category.id} className="transaction-item" style={{ alignItems: 'flex-start' }}>
                  <div>
                    <p style={{ fontWeight: 600, color: '#94a3b8' }}>{category.name}</p>
                    <p className="meta">Тип: {category.type === 'income' ? 'Доход' : category.type === 'expense' ? 'Расход' : 'Перевод'}</p>
                    {category.description && <p className="highlight">{category.description}</p>}
                  </div>
                  <div>
                    <button
                      className="button"
                      onClick={() => handleCategoryArchive(category, false)}
                      disabled={isCategorySubmitting}
                    >
                      Вернуть в работу
                    </button>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        )}
      </section>
    </main>
  );
}

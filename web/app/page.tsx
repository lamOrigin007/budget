'use client';

import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';

function startOfCurrentMonth(): Date {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
}

function formatDateInput(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function toRFC3339FromDateInput(value: string, endOfDay = false): string | undefined {
  if (!value) {
    return undefined;
  }
  const time = endOfDay ? '23:59:59.999' : '00:00:00.000';
  const iso = `${value}T${time}Z`;
  const parsed = new Date(iso);
  if (Number.isNaN(parsed.getTime())) {
    return undefined;
  }
  return parsed.toISOString();
}

function isWithinPeriod(occurredAt: string, start: string, end: string): boolean {
  const occurred = new Date(occurredAt).getTime();
  if (Number.isNaN(occurred)) {
    return false;
  }
  const startTime = start ? new Date(`${start}T00:00:00.000Z`).getTime() : Number.NEGATIVE_INFINITY;
  const endTime = end ? new Date(`${end}T23:59:59.999Z`).getTime() : Number.POSITIVE_INFINITY;
  return occurred >= startTime && occurred <= endTime;
}
import {
  Account,
  AccountPayload,
  Category,
  CategoryPayload,
  FamilyMember,
  PlannedOperation,
  PlannedOperationPayload,
  PlannedOperationRecurrence,
  RegisterResponse,
  Transaction
} from '../src/lib/api';
import {
  registerUser,
  fetchAccounts,
  createTransaction,
  fetchTransactions,
  createCategory,
  updateCategory,
  setCategoryArchived,
  createAccount,
  fetchFamilyMembers,
  fetchPlannedOperations,
  createPlannedOperation,
  completePlannedOperation
} from '../src/lib/api';

type Step = 'register' | 'dashboard';

const accountTypeLabels: Record<Account['type'], string> = {
  cash: 'Наличные',
  card: 'Карта',
  bank: 'Банковский счёт',
  deposit: 'Вклад',
  wallet: 'Электронный кошелёк'
};

export default function Home() {
  const [step, setStep] = useState<Step>('register');
  const [registerError, setRegisterError] = useState<string | null>(null);
  const [userData, setUserData] = useState<RegisterResponse | null>(null);
  const [categories, setCategories] = useState<Category[]>([]);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [familyMembers, setFamilyMembers] = useState<FamilyMember[]>([]);
  const [selectedAccountId, setSelectedAccountId] = useState<string>('');
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [createError, setCreateError] = useState<string | null>(null);
  const [transactionsError, setTransactionsError] = useState<string | null>(null);
  const [isRegistering, setIsRegistering] = useState(false);
  const [isSavingTransaction, setIsSavingTransaction] = useState(false);
  const [isTransactionsLoading, setIsTransactionsLoading] = useState(false);
  const [membersError, setMembersError] = useState<string | null>(null);
  const [isCategorySubmitting, setIsCategorySubmitting] = useState(false);
  const [categoryError, setCategoryError] = useState<string | null>(null);
  const [editingCategoryId, setEditingCategoryId] = useState<string | null>(null);
  const [isAccountSubmitting, setIsAccountSubmitting] = useState(false);
  const [accountError, setAccountError] = useState<string | null>(null);
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
  const [accountForm, setAccountForm] = useState<{
    name: string;
    type: Account['type'];
    currency: string;
    initial_balance_minor: string;
    shared: boolean;
  }>({
    name: '',
    type: 'cash',
    currency: '',
    initial_balance_minor: '',
    shared: true
  });
  const [periodStart, setPeriodStart] = useState(() => formatDateInput(startOfCurrentMonth()));
  const [periodEnd, setPeriodEnd] = useState(() => formatDateInput(new Date()));
  const [filterType, setFilterType] = useState<'income' | 'expense' | ''>('');
  const [filterCategoryId, setFilterCategoryId] = useState<string>('');
  const [filterAccountId, setFilterAccountId] = useState<string>('');
  const [filterUserId, setFilterUserId] = useState<string>('');
  const [plannedOperations, setPlannedOperations] = useState<PlannedOperation[]>([]);
  const [completedPlannedOperations, setCompletedPlannedOperations] = useState<PlannedOperation[]>([]);
  const [plannedError, setPlannedError] = useState<string | null>(null);
  const [isPlannedLoading, setIsPlannedLoading] = useState(false);
  const [isPlannedSubmitting, setIsPlannedSubmitting] = useState(false);
  const [completingPlanId, setCompletingPlanId] = useState<string | null>(null);
  const [plannedForm, setPlannedForm] = useState<{
    account_id: string;
    category_id: string;
    type: 'income' | 'expense';
    title: string;
    amount_minor: string;
    due_date: string;
    comment: string;
    recurrence: PlannedOperationRecurrence;
  }>(() => ({
    account_id: '',
    category_id: '',
    type: 'expense',
    title: '',
    amount_minor: '',
    due_date: formatDateInput(new Date()),
    comment: '',
    recurrence: ''
  }));

  const activeCategories = useMemo(
    () => categories.filter((category) => !category.is_archived),
    [categories]
  );
  const archivedCategories = useMemo(
    () => categories.filter((category) => category.is_archived),
    [categories]
  );
  const plannedAvailableCategories = useMemo(
    () => activeCategories.filter((category) => category.type === plannedForm.type),
    [activeCategories, plannedForm.type]
  );
  const hasAccounts = accounts.length > 0;
  const canPlanOperations = hasAccounts && plannedAvailableCategories.length > 0;

  useEffect(() => {
    if (filterCategoryId && !categories.some((category) => category.id === filterCategoryId)) {
      setFilterCategoryId('');
    }
  }, [categories, filterCategoryId]);

  useEffect(() => {
    if (filterAccountId && !accounts.some((account) => account.id === filterAccountId)) {
      setFilterAccountId('');
    }
  }, [accounts, filterAccountId]);

  useEffect(() => {
    if (filterUserId && !familyMembers.some((member) => member.id === filterUserId)) {
      setFilterUserId('');
    }
  }, [familyMembers, filterUserId]);

  useEffect(() => {
    setPlannedForm((prev) => ({
      ...prev,
      account_id:
        prev.account_id && accounts.some((account) => account.id === prev.account_id)
          ? prev.account_id
          : accounts[0]?.id ?? ''
    }));
  }, [accounts]);

  useEffect(() => {
    setPlannedForm((prev) => {
      const hasCategory =
        prev.category_id &&
        activeCategories.some((category) => category.id === prev.category_id && category.type === prev.type);
      return {
        ...prev,
        category_id: hasCategory ? prev.category_id : plannedAvailableCategories[0]?.id ?? ''
      };
    });
  }, [activeCategories, plannedAvailableCategories]);

  useEffect(() => {
    if (!userData) {
      setFamilyMembers([]);
      setMembersError(null);
      setPlannedOperations([]);
      setCompletedPlannedOperations([]);
      setPlannedError(null);
      return;
    }
    void refreshMembers(userData.user.id);
    void refreshPlannedOperationsList(userData.user.id);
  }, [refreshMembers, refreshPlannedOperationsList, userData?.user.id]);

  function sortAccounts(list: Account[]) {
    return [...list].sort((left, right) => left.name.localeCompare(right.name, 'ru'));
  }

  function formatMoney(valueMinor: number, currency: string) {
    const value = valueMinor / 100;
    return `${value.toLocaleString('ru-RU', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ${currency}`;
  }

  function formatRole(role: string) {
    switch (role) {
      case 'owner':
        return 'владелец';
      case 'adult':
        return 'участник';
      case 'junior':
        return 'гость';
      default:
        return role;
    }
  }

  function sortPlannedList(list: PlannedOperation[]) {
    return [...list].sort(
      (left, right) => new Date(left.due_at).getTime() - new Date(right.due_at).getTime()
    );
  }

  function sortCompletedPlannedList(list: PlannedOperation[]) {
    return [...list].sort((left, right) => {
      const leftDate = new Date(left.last_completed_at ?? left.updated_at).getTime();
      const rightDate = new Date(right.last_completed_at ?? right.updated_at).getTime();
      return rightDate - leftDate;
    });
  }

  function formatRecurrenceLabel(recurrence?: string | null) {
    if (!recurrence || recurrence === '' || recurrence === 'none') {
      return 'Единожды';
    }
    switch (recurrence) {
      case 'weekly':
        return 'Еженедельно';
      case 'monthly':
        return 'Ежемесячно';
      case 'yearly':
        return 'Ежегодно';
      default:
        return recurrence;
    }
  }

  function getAccountName(accountId: string) {
    return accounts.find((account) => account.id === accountId)?.name ?? 'Неизвестный счёт';
  }

  function getCategoryName(categoryId: string) {
    return categories.find((category) => category.id === categoryId)?.name ?? 'Неизвестная категория';
  }

  const refreshMembers = useCallback(
    async (userId: string) => {
      try {
        const list = await fetchFamilyMembers(userId);
        setFamilyMembers(list);
        setMembersError(null);
      } catch (error) {
        setMembersError(error instanceof Error ? error.message : 'Не удалось загрузить участников семьи');
      }
    },
    []
  );

  const refreshPlannedOperationsList = useCallback(
    async (userId: string) => {
      setIsPlannedLoading(true);
      try {
        const data = await fetchPlannedOperations(userId);
        const upcoming = [...data.planned_operations].sort(
          (left, right) => new Date(left.due_at).getTime() - new Date(right.due_at).getTime()
        );
        const completed = [...data.completed_operations].sort((left, right) => {
          const leftDate = new Date(left.last_completed_at ?? left.updated_at).getTime();
          const rightDate = new Date(right.last_completed_at ?? right.updated_at).getTime();
          return rightDate - leftDate;
        });
        setPlannedOperations(upcoming);
        setCompletedPlannedOperations(completed);
        setPlannedError(null);
      } catch (error) {
        setPlannedError(
          error instanceof Error ? error.message : 'Не удалось загрузить запланированные операции'
        );
      } finally {
        setIsPlannedLoading(false);
      }
    },
    []
  );

  async function refreshAccounts(userId: string, preferredAccountId?: string) {
    const list = sortAccounts(await fetchAccounts(userId));
    setAccounts(list);
    setSelectedAccountId((current) => {
      if (preferredAccountId && list.some((account) => account.id === preferredAccountId)) {
        return preferredAccountId;
      }
      if (current && list.some((account) => account.id === current)) {
        return current;
      }
      return list[0]?.id ?? '';
    });
    setFilterAccountId((current) => {
      if (current && list.some((account) => account.id === current)) {
        return current;
      }
      return '';
    });
  }

  async function loadTransactionsForCurrentPeriod(userId: string) {
    const startIso = toRFC3339FromDateInput(periodStart);
    const endIso = toRFC3339FromDateInput(periodEnd, true);
    if (startIso && endIso && new Date(startIso).getTime() > new Date(endIso).getTime()) {
      setTransactionsError('Дата начала должна быть не позже даты окончания');
      setTransactions([]);
      return;
    }

    setTransactionsError(null);
    setIsTransactionsLoading(true);
    try {
      const tx = await fetchTransactions(userId, {
        ...(startIso ? { start_date: startIso } : {}),
        ...(endIso ? { end_date: endIso } : {}),
        ...(filterType ? { type: filterType } : {}),
        ...(filterCategoryId ? { category_id: filterCategoryId } : {}),
        ...(filterAccountId ? { account_id: filterAccountId } : {}),
        ...(filterUserId ? { user_id: filterUserId } : {})
      });
      setTransactions(sortTransactions(tx));
    } catch (error) {
      setTransactionsError(error instanceof Error ? error.message : 'Не удалось загрузить операции');
    } finally {
      setIsTransactionsLoading(false);
    }
  }

  function sortTransactions(list: Transaction[]) {
    return [...list].sort(
      (left, right) => new Date(right.occurred_at).getTime() - new Date(left.occurred_at).getTime()
    );
  }

  function matchesTransactionFilters(transaction: Transaction) {
    if (filterType && transaction.type !== filterType) {
      return false;
    }
    if (filterCategoryId && transaction.category_id !== filterCategoryId) {
      return false;
    }
    if (filterAccountId && transaction.account_id !== filterAccountId) {
      return false;
    }
    if (filterUserId && transaction.author.id !== filterUserId) {
      return false;
    }
    return true;
  }

  async function handleRegister(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setRegisterError(null);
    const formData = new FormData(event.currentTarget);
    setIsRegistering(true);
    try {
      const response = await registerUser({
        email: String(formData.get('email') ?? ''),
        password: String(formData.get('password') ?? ''),
        name: String(formData.get('name') ?? ''),
        currency: String(formData.get('currency') ?? 'RUB'),
        locale: String(formData.get('locale') ?? 'ru-RU'),
        family_name: String(formData.get('family_name') ?? ''),
        family_id: String(formData.get('family_id') ?? '')
      });
      setUserData(response);
      setFamilyMembers(response.members);
      setMembersError(null);
      setCategories(sortCategories(response.categories));
      await refreshAccounts(response.user.id);
      setAccountForm((prev) => ({
        ...prev,
        currency: response.user.currency_default
      }));
      await loadTransactionsForCurrentPeriod(response.user.id);
      await refreshMembers(response.user.id);
      await refreshPlannedOperationsList(response.user.id);
      setStep('dashboard');
      event.currentTarget.reset();
    } catch (error) {
      setRegisterError(error instanceof Error ? error.message : 'Не удалось зарегистрироваться');
    } finally {
      setIsRegistering(false);
    }
  }

  async function handleCreateTransaction(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!userData) return;
    setCreateError(null);
    if (!selectedAccountId) {
      setCreateError('Сначала добавьте счёт');
      return;
    }
    const account = accounts.find((item) => item.id === selectedAccountId);
    if (!account) {
      setCreateError('Выбранный счёт недоступен');
      return;
    }
    const formData = new FormData(event.currentTarget);
    setIsSavingTransaction(true);
    try {
      const occurredInput = String(formData.get('occurred_at') ?? '');
      const occurredAt = occurredInput ? new Date(occurredInput).toISOString() : new Date().toISOString();
      const amountMinor = Number(formData.get('amount_minor') ?? 0);
      if (!Number.isFinite(amountMinor) || amountMinor <= 0) {
        throw new Error('Сумма должна быть больше нуля');
      }
      const transaction = await createTransaction({
        user_id: userData.user.id,
        account_id: account.id,
        category_id: String(formData.get('category_id') ?? ''),
        type: String(formData.get('type') ?? 'expense') as 'income' | 'expense',
        amount_minor: amountMinor,
        currency: account.currency,
        comment: String(formData.get('comment') ?? '').trim(),
        occurred_at: occurredAt
      });
      if (
        isWithinPeriod(transaction.occurred_at, periodStart, periodEnd) &&
        matchesTransactionFilters(transaction)
      ) {
        setTransactions((prev) => sortTransactions([transaction, ...prev]));
      }
      await refreshAccounts(userData.user.id, account.id);
      event.currentTarget.reset();
    } catch (error) {
      setCreateError(error instanceof Error ? error.message : 'Не удалось создать операцию');
    } finally {
      setIsSavingTransaction(false);
    }
  }

  async function handlePlannedOperationSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!userData) {
      return;
    }
    setPlannedError(null);

    const account = accounts.find((item) => item.id === plannedForm.account_id);
    if (!account) {
      setPlannedError('Выберите счёт для планирования');
      return;
    }
    if (!plannedForm.category_id) {
      setPlannedError('Выберите категорию');
      return;
    }
    const title = plannedForm.title.trim();
    if (!title) {
      setPlannedError('Название операции обязательно');
      return;
    }
    const amountMinor = Number(plannedForm.amount_minor);
    if (!Number.isFinite(amountMinor) || amountMinor <= 0) {
      setPlannedError('Сумма должна быть больше нуля');
      return;
    }
    const dueIso = toRFC3339FromDateInput(plannedForm.due_date);
    if (!dueIso) {
      setPlannedError('Укажите корректную дату выполнения');
      return;
    }

    const payload: PlannedOperationPayload = {
      account_id: account.id,
      category_id: plannedForm.category_id,
      type: plannedForm.type,
      title,
      amount_minor: amountMinor,
      currency: account.currency,
      due_at: dueIso
    };
    const comment = plannedForm.comment.trim();
    if (comment) {
      payload.comment = comment;
    }
    if (plannedForm.recurrence && plannedForm.recurrence !== '') {
      payload.recurrence = plannedForm.recurrence;
    }

    setIsPlannedSubmitting(true);
    try {
      const created = await createPlannedOperation(userData.user.id, payload);
      setPlannedOperations((prev) => sortPlannedList([...prev, created]));
      setPlannedError(null);
      setPlannedForm((prev) => ({
        ...prev,
        title: '',
        amount_minor: '',
        comment: ''
      }));
    } catch (error) {
      setPlannedError(
        error instanceof Error ? error.message : 'Не удалось создать запланированную операцию'
      );
    } finally {
      setIsPlannedSubmitting(false);
    }
  }

  async function handleCompletePlannedOperation(plan: PlannedOperation) {
    if (!userData) {
      return;
    }
    setPlannedError(null);
    setCompletingPlanId(plan.id);
    try {
      const result = await completePlannedOperation(userData.user.id, plan.id);
      const updatedPlan = result.planned_operation;
      const transaction = result.transaction;
      setPlannedOperations((prev) => {
        const remaining = prev.filter((item) => item.id !== plan.id);
        if (updatedPlan.is_completed) {
          return remaining;
        }
        return sortPlannedList([...remaining, updatedPlan]);
      });
      setCompletedPlannedOperations((prev) => {
        const filtered = prev.filter((item) => item.id !== plan.id);
        if (updatedPlan.is_completed) {
          return sortCompletedPlannedList([...filtered, updatedPlan]);
        }
        return filtered;
      });
      if (
        isWithinPeriod(transaction.occurred_at, periodStart, periodEnd) &&
        matchesTransactionFilters(transaction)
      ) {
        setTransactions((prev) => sortTransactions([transaction, ...prev]));
      }
      await refreshAccounts(userData.user.id, plan.account_id);
    } catch (error) {
      setPlannedError(
        error instanceof Error ? error.message : 'Не удалось отметить выполнение операции'
      );
    } finally {
      setCompletingPlanId(null);
    }
  }

  async function handlePeriodSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!userData) return;
    await loadTransactionsForCurrentPeriod(userData.user.id);
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

  async function handleAccountSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!userData) return;
    setAccountError(null);
    setIsAccountSubmitting(true);

    const payload: AccountPayload = {
      name: accountForm.name.trim(),
      type: accountForm.type,
      shared: accountForm.shared
    };
    const currency = accountForm.currency.trim();
    if (currency) {
      payload.currency = currency.toUpperCase();
    }
    const initialBalance = Number(accountForm.initial_balance_minor);
    if (Number.isFinite(initialBalance) && initialBalance !== 0) {
      payload.initial_balance_minor = initialBalance;
    }

    try {
      const account = await createAccount(userData.user.id, payload);
      await refreshAccounts(userData.user.id, account.id);
      setAccountForm({
        name: '',
        type: 'cash',
        currency: account.currency,
        initial_balance_minor: '',
        shared: true
      });
    } catch (error) {
      setAccountError(error instanceof Error ? error.message : 'Не удалось создать счёт');
    } finally {
      setIsAccountSubmitting(false);
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
            <div className="input-group">
              <label htmlFor="family_id">ID существующей семьи</label>
              <input
                id="family_id"
                name="family_id"
                placeholder="Введите UUID, чтобы присоединиться"
                className="input"
              />
              <p className="meta">Оставьте поле пустым, если создаёте новую семью.</p>
            </div>
            {registerError && <p className="error">{registerError}</p>}
            <button type="submit" disabled={isRegistering} className="button">
              {isRegistering ? 'Создание...' : 'Создать или присоединиться'}
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
        <div style={{ marginTop: '1.25rem' }}>
          <h3 style={{ fontSize: '1rem', marginBottom: '0.5rem' }}>Участники семьи</h3>
          {membersError && <p className="error">{membersError}</p>}
          {familyMembers.length === 0 ? (
            <p className="highlight">Пригласите родственников, чтобы делиться общим бюджетом.</p>
          ) : (
            <ul className="transactions">
              {familyMembers.map((member) => {
                const isCurrent = member.id === userData?.user.id;
                return (
                  <li key={member.id} className="transaction-item" style={{ alignItems: 'flex-start' }}>
                    <div>
                      <p style={{ fontWeight: 600, color: '#e2e8f0' }}>
                        {member.name} {isCurrent ? '· это вы' : ''}
                      </p>
                      <p className="meta">{member.email}</p>
                      <p className="meta">Роль: {formatRole(member.role)}</p>
                    </div>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </section>

      <section className="panel">
        <h2>Счета и кошельки</h2>
        <div
          className="form-grid"
          style={{ gridTemplateColumns: 'minmax(260px, 2fr) minmax(240px, 1fr)', gap: '1.5rem', alignItems: 'flex-start' }}
        >
          <div>
            {accounts.length === 0 ? (
              <p className="highlight">Создайте первый счёт, чтобы учитывать движения по наличным, карте или вкладу.</p>
            ) : (
              <ul className="transactions">
                {accounts.map((account) => {
                  const isSelected = account.id === selectedAccountId;
                  const balance = formatMoney(account.balance_minor, account.currency);
                  const balanceColor = account.balance_minor >= 0 ? '#34d399' : '#f87171';
                  return (
                    <li key={account.id} className="transaction-item">
                      <div>
                        <p style={{ fontWeight: 600, color: '#e2e8f0' }}>{account.name}</p>
                        <p className="meta">{accountTypeLabels[account.type]}</p>
                        <p className="meta">Валюта: {account.currency}</p>
                        <p className="meta">{account.is_shared ? 'Общий счёт семьи' : 'Личный счёт'}</p>
                        {isSelected && <p className="highlight">Активный счёт для новых операций</p>}
                      </div>
                      <div className="amount" style={{ color: balanceColor }}>
                        {balance}
                      </div>
                    </li>
                  );
                })}
              </ul>
            )}
          </div>
          <form onSubmit={handleAccountSubmit} className="form-grid" style={{ gap: '0.75rem' }}>
            <div className="input-group">
              <label htmlFor="account_name">Название счёта</label>
              <input
                id="account_name"
                name="account_name"
                className="input"
                value={accountForm.name}
                onChange={(event) => setAccountForm((prev) => ({ ...prev, name: event.target.value }))}
                placeholder="Например, Наличные"
                required
              />
            </div>
            <div className="input-group">
              <label htmlFor="account_type">Тип</label>
              <select
                id="account_type"
                name="account_type"
                className="select"
                value={accountForm.type}
                onChange={(event) =>
                  setAccountForm((prev) => ({ ...prev, type: event.target.value as Account['type'] }))
                }
              >
                <option value="cash">Наличные</option>
                <option value="card">Карта</option>
                <option value="bank">Банковский счёт</option>
                <option value="deposit">Вклад</option>
                <option value="wallet">Электронный кошелёк</option>
              </select>
            </div>
            <div className="input-group">
              <label htmlFor="account_currency">Валюта</label>
              <input
                id="account_currency"
                name="account_currency"
                className="input"
                value={accountForm.currency}
                onChange={(event) => setAccountForm((prev) => ({ ...prev, currency: event.target.value }))}
                placeholder={userData?.user.currency_default ?? 'RUB'}
              />
            </div>
            <div className="input-group">
              <label htmlFor="account_initial">Начальный баланс (в копейках)</label>
              <input
                id="account_initial"
                name="account_initial"
                className="input"
                type="number"
                value={accountForm.initial_balance_minor}
                onChange={(event) => setAccountForm((prev) => ({ ...prev, initial_balance_minor: event.target.value }))}
                placeholder="0"
              />
            </div>
            <div className="input-group" style={{ display: 'flex', flexDirection: 'column', gap: '0.35rem' }}>
              <label htmlFor="account_shared" style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <input
                  id="account_shared"
                  name="account_shared"
                  type="checkbox"
                  checked={accountForm.shared}
                  onChange={(event) => setAccountForm((prev) => ({ ...prev, shared: event.target.checked }))}
                />
                Общий счёт семьи
              </label>
              <span className="meta">Снимите флажок, чтобы сделать счёт личным.</span>
            </div>
            {accountError && <p className="error" style={{ gridColumn: '1 / -1' }}>{accountError}</p>}
            <button type="submit" className="button" disabled={isAccountSubmitting} style={{ gridColumn: '1 / -1' }}>
              {isAccountSubmitting ? 'Сохранение...' : 'Добавить счёт'}
            </button>
          </form>
        </div>
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
          <h2>Планирование операций</h2>
          <p style={{ color: '#4b5563', marginBottom: '1rem' }}>
            Запланируйте будущие или регулярные платежи и отмечайте выполнение. Баланс счёта обновится
            автоматически.
          </p>
          <form
            onSubmit={handlePlannedOperationSubmit}
            className="form-grid"
            style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', marginBottom: '1rem' }}
          >
            <div className="input-group">
              <label htmlFor="planned_type">Тип операции</label>
              <select
                id="planned_type"
                className="select"
                value={plannedForm.type}
                onChange={(event) =>
                  setPlannedForm((prev) => ({
                    ...prev,
                    type: event.target.value as 'income' | 'expense'
                  }))
                }
                disabled={!hasAccounts}
              >
                <option value="expense">Расход</option>
                <option value="income">Доход</option>
              </select>
            </div>
            <div className="input-group">
              <label htmlFor="planned_account">Счёт</label>
              <select
                id="planned_account"
                className="select"
                value={plannedForm.account_id}
                onChange={(event) =>
                  setPlannedForm((prev) => ({ ...prev, account_id: event.target.value }))
                }
                disabled={!hasAccounts}
              >
                {accounts.map((account) => (
                  <option key={account.id} value={account.id}>
                    {account.name} · {account.currency}
                  </option>
                ))}
              </select>
            </div>
            <div className="input-group">
              <label htmlFor="planned_category">Категория</label>
              <select
                id="planned_category"
                className="select"
                value={plannedForm.category_id}
                onChange={(event) =>
                  setPlannedForm((prev) => ({ ...prev, category_id: event.target.value }))
                }
                disabled={!canPlanOperations}
              >
                {plannedAvailableCategories.map((category) => (
                  <option key={category.id} value={category.id}>
                    {category.name}
                  </option>
                ))}
              </select>
            </div>
            <div className="input-group">
              <label htmlFor="planned_title">Название</label>
              <input
                id="planned_title"
                className="input"
                value={plannedForm.title}
                onChange={(event) => setPlannedForm((prev) => ({ ...prev, title: event.target.value }))}
                placeholder="Например: Коммунальные платежи"
                disabled={!canPlanOperations}
                required
              />
            </div>
            <div className="input-group">
              <label htmlFor="planned_amount">Сумма (в копейках)</label>
              <input
                id="planned_amount"
                className="input"
                type="number"
                min="1"
                value={plannedForm.amount_minor}
                onChange={(event) =>
                  setPlannedForm((prev) => ({ ...prev, amount_minor: event.target.value }))
                }
                disabled={!canPlanOperations}
                required
              />
            </div>
            <div className="input-group">
              <label htmlFor="planned_due">Дата выполнения</label>
              <input
                id="planned_due"
                className="input"
                type="date"
                value={plannedForm.due_date}
                onChange={(event) => setPlannedForm((prev) => ({ ...prev, due_date: event.target.value }))}
                disabled={!canPlanOperations}
                required
              />
            </div>
            <div className="input-group">
              <label htmlFor="planned_recurrence">Повторение</label>
              <select
                id="planned_recurrence"
                className="select"
                value={plannedForm.recurrence}
                onChange={(event) =>
                  setPlannedForm((prev) => ({ ...prev, recurrence: event.target.value as PlannedOperationRecurrence }))
                }
                disabled={!canPlanOperations}
              >
                <option value="">Один раз</option>
                <option value="weekly">Каждую неделю</option>
                <option value="monthly">Каждый месяц</option>
                <option value="yearly">Каждый год</option>
              </select>
            </div>
            <div className="input-group" style={{ gridColumn: '1 / -1' }}>
              <label htmlFor="planned_comment">Комментарий</label>
              <textarea
                id="planned_comment"
                className="textarea"
                rows={2}
                value={plannedForm.comment}
                onChange={(event) => setPlannedForm((prev) => ({ ...prev, comment: event.target.value }))}
                placeholder="Дополнительная информация или получатель"
                disabled={!canPlanOperations}
              />
            </div>
            {!hasAccounts && (
              <p className="highlight" style={{ gridColumn: '1 / -1' }}>
                Добавьте счёт, чтобы планировать операции.
              </p>
            )}
            {hasAccounts && plannedAvailableCategories.length === 0 && (
              <p className="highlight" style={{ gridColumn: '1 / -1' }}>
                Создайте категорию типа «{plannedForm.type === 'expense' ? 'Расход' : 'Доход'}», чтобы добавить план.
              </p>
            )}
            {plannedError && (
              <p className="error" style={{ gridColumn: '1 / -1' }}>
                {plannedError}
              </p>
            )}
            <button type="submit" className="button" disabled={isPlannedSubmitting || !canPlanOperations}>
              {isPlannedSubmitting ? 'Сохранение...' : 'Сохранить план'}
            </button>
          </form>
          <div
            style={{
              display: 'grid',
              gap: '1.5rem',
              gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))'
            }}
          >
            <section>
              <h3>Ближайшие операции</h3>
              {isPlannedLoading ? (
                <p>Загрузка...</p>
              ) : plannedOperations.length === 0 ? (
                <p style={{ color: '#4b5563' }}>Нет запланированных операций.</p>
              ) : (
                <ul style={{ listStyle: 'none', padding: 0, margin: 0, display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
                  {plannedOperations.map((operation) => (
                    <li
                      key={operation.id}
                      style={{
                        border: '1px solid #e2e8f0',
                        borderRadius: '0.75rem',
                        padding: '0.75rem 1rem',
                        background: '#f8fafc'
                      }}
                    >
                      <div style={{ display: 'flex', justifyContent: 'space-between', gap: '1rem', flexWrap: 'wrap' }}>
                        <div style={{ flex: '1 1 200px' }}>
                          <strong>{operation.title}</strong>
                          <div style={{ color: '#4b5563', marginTop: '0.25rem' }}>
                            Счёт: {getAccountName(operation.account_id)}
                          </div>
                          <div style={{ color: '#4b5563' }}>Категория: {getCategoryName(operation.category_id)}</div>
                          <div style={{ color: '#4b5563' }}>Ответственный: {operation.creator.name}</div>
                          {operation.last_completed_at && (
                            <div style={{ color: '#4b5563' }}>
                              Последнее выполнение:{' '}
                              {new Date(operation.last_completed_at).toLocaleString('ru-RU')}
                            </div>
                          )}
                        </div>
                        <div style={{ textAlign: 'right' }}>
                          <div style={{ fontWeight: 600 }}>{formatMoney(operation.amount_minor, operation.currency)}</div>
                          <div>К оплате: {new Date(operation.due_at).toLocaleDateString('ru-RU')}</div>
                          <div>{formatRecurrenceLabel(operation.recurrence)}</div>
                          <button
                            type="button"
                            className="button"
                            style={{ marginTop: '0.5rem' }}
                            onClick={() => handleCompletePlannedOperation(operation)}
                            disabled={completingPlanId === operation.id}
                          >
                            {completingPlanId === operation.id ? 'Отмечаем...' : 'Отметить выполненной'}
                          </button>
                        </div>
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </section>
            <section>
              <h3>Завершённые операции</h3>
              {isPlannedLoading ? (
                <p>Загрузка...</p>
              ) : completedPlannedOperations.length === 0 ? (
                <p style={{ color: '#4b5563' }}>Пока нет завершённых операций.</p>
              ) : (
                <ul style={{ listStyle: 'none', padding: 0, margin: 0, display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
                  {completedPlannedOperations.map((operation) => (
                    <li
                      key={operation.id}
                      style={{
                        border: '1px solid #e2e8f0',
                        borderRadius: '0.75rem',
                        padding: '0.75rem 1rem'
                      }}
                    >
                      <div style={{ display: 'flex', justifyContent: 'space-between', gap: '1rem', flexWrap: 'wrap' }}>
                        <div style={{ flex: '1 1 200px' }}>
                          <strong>{operation.title}</strong>
                          <div style={{ color: '#4b5563', marginTop: '0.25rem' }}>
                            Счёт: {getAccountName(operation.account_id)}
                          </div>
                          <div style={{ color: '#4b5563' }}>Категория: {getCategoryName(operation.category_id)}</div>
                          <div style={{ color: '#4b5563' }}>Ответственный: {operation.creator.name}</div>
                        </div>
                        <div style={{ textAlign: 'right' }}>
                          <div style={{ fontWeight: 600 }}>{formatMoney(operation.amount_minor, operation.currency)}</div>
                          <div>
                            Завершено:{' '}
                            {new Date(operation.last_completed_at ?? operation.updated_at).toLocaleString('ru-RU')}
                          </div>
                          <div>{formatRecurrenceLabel(operation.recurrence)}</div>
                        </div>
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </section>
          </div>
        </article>

        <article className="panel">
          <h2>Новая операция</h2>
          <form onSubmit={handleCreateTransaction} className="form-grid">
            <div className="input-group">
              <label htmlFor="account_id">Счёт</label>
              <select
                id="account_id"
                name="account_id"
                className="select"
                value={selectedAccountId}
                onChange={(event) => setSelectedAccountId(event.target.value)}
                disabled={!hasAccounts}
              >
                {accounts.map((account) => (
                  <option key={account.id} value={account.id}>
                    {account.name} · {account.currency}
                  </option>
                ))}
              </select>
            </div>
            <div className="input-group">
              <label htmlFor="type">Тип</label>
              <select id="type" name="type" className="select" disabled={!hasAccounts}>
                <option value="expense">Расход</option>
                <option value="income">Доход</option>
              </select>
            </div>
            <div className="input-group">
              <label htmlFor="category_id">Категория</label>
              <select id="category_id" name="category_id" className="select" disabled={!hasAccounts}>
                {activeCategories.map((category) => (
                  <option key={category.id} value={category.id}>
                    {category.name}
                  </option>
                ))}
              </select>
            </div>
            <div className="input-group">
              <label htmlFor="amount_minor">Сумма (в копейках)</label>
              <input id="amount_minor" name="amount_minor" type="number" min="1" required className="input" disabled={!hasAccounts} />
            </div>
            <div className="input-group">
              <label htmlFor="occurred_at">Дата операции</label>
              <input id="occurred_at" name="occurred_at" type="datetime-local" className="input" disabled={!hasAccounts} />
            </div>
            <div className="input-group">
              <label htmlFor="comment">Комментарий</label>
              <textarea id="comment" name="comment" rows={3} className="textarea" disabled={!hasAccounts} />
            </div>
            {!hasAccounts && (
              <p className="highlight" style={{ gridColumn: '1 / -1' }}>
                Добавьте счёт, чтобы фиксировать операции.
              </p>
            )}
            {createError && <p className="error">{createError}</p>}
            <button type="submit" disabled={isSavingTransaction || !hasAccounts} className="button">
              {isSavingTransaction ? 'Сохранение...' : 'Добавить операцию'}
            </button>
          </form>
        </article>

        <article className="panel">
          <h2>Операции пользователя</h2>
          <form
            onSubmit={handlePeriodSubmit}
            className="form-grid"
            style={{
              marginBottom: '1rem',
              gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))'
            }}
          >
            <div className="input-group">
              <label htmlFor="period_start">Начало периода</label>
              <input
                id="period_start"
                name="period_start"
                type="date"
                className="input"
                value={periodStart}
                onChange={(event) => setPeriodStart(event.target.value)}
              />
            </div>
            <div className="input-group">
              <label htmlFor="period_end">Окончание периода</label>
              <input
                id="period_end"
                name="period_end"
                type="date"
                className="input"
                value={periodEnd}
                onChange={(event) => setPeriodEnd(event.target.value)}
              />
            </div>
            <div className="input-group">
              <label htmlFor="filter_type">Тип операции</label>
              <select
                id="filter_type"
                name="filter_type"
                className="select"
                value={filterType}
                onChange={(event) => setFilterType(event.target.value as 'income' | 'expense' | '')}
              >
                <option value="">Все типы</option>
                <option value="expense">Расходы</option>
                <option value="income">Доходы</option>
              </select>
            </div>
            <div className="input-group">
              <label htmlFor="filter_category">Категория</label>
              <select
                id="filter_category"
                name="filter_category"
                className="select"
                value={filterCategoryId}
                onChange={(event) => setFilterCategoryId(event.target.value)}
              >
                <option value="">Все категории</option>
                {categories.map((category) => (
                  <option key={category.id} value={category.id}>
                    {category.name}
                    {category.is_archived ? ' · архив' : ''}
                  </option>
                ))}
              </select>
            </div>
            <div className="input-group">
              <label htmlFor="filter_account">Счёт</label>
              <select
                id="filter_account"
                name="filter_account"
                className="select"
                value={filterAccountId}
                onChange={(event) => setFilterAccountId(event.target.value)}
              >
                <option value="">Все счета</option>
                {accounts.map((account) => (
                  <option key={account.id} value={account.id}>
                    {account.name} · {account.currency}
                  </option>
                ))}
              </select>
            </div>
            <div className="input-group">
              <label htmlFor="filter_user">Участник</label>
              <select
                id="filter_user"
                name="filter_user"
                className="select"
                value={filterUserId}
                onChange={(event) => setFilterUserId(event.target.value)}
              >
                <option value="">Все участники</option>
                {familyMembers.map((member) => (
                  <option key={member.id} value={member.id}>
                    {member.name} · {formatRole(member.role)}
                  </option>
                ))}
              </select>
            </div>
            <div className="input-group" style={{ alignSelf: 'flex-end' }}>
              <button type="submit" className="button" disabled={isTransactionsLoading}>
                {isTransactionsLoading ? 'Загрузка...' : 'Обновить период'}
              </button>
            </div>
          </form>
          {transactionsError && <p className="error">{transactionsError}</p>}
          {isTransactionsLoading && <p className="highlight">Загрузка операций...</p>}
          {!isTransactionsLoading && !transactionsError && transactions.length === 0 && (
            <p className="highlight">Пока нет операций. Добавьте первую операцию.</p>
          )}
          <ul className="transactions">
            {transactions.map((transaction) => {
              const category = categories.find((cat) => cat.id === transaction.category_id);
              const account = accounts.find((acc) => acc.id === transaction.account_id);
              const amount = (transaction.amount_minor / 100).toFixed(2);
              const sign = transaction.type === 'income' ? '+' : '-';
              const color = transaction.type === 'income' ? '#34d399' : '#f87171';
              return (
                <li key={transaction.id} className="transaction-item">
                  <div>
                    <p style={{ fontWeight: 600, color: category?.color ?? '#e2e8f0' }}>{category?.name ?? 'Категория'}</p>
                    <p className="meta">{new Date(transaction.occurred_at).toLocaleString()}</p>
                    <p className="meta">Счёт: {account?.name ?? 'недоступно'}</p>
                    <p className="meta">
                      Автор: {transaction.author.name}
                      {transaction.author.id === userData?.user.id ? ' · это вы' : ''} ({formatRole(transaction.author.role)})
                    </p>
                    {transaction.comment && (
                      <p className="highlight" style={{ color: '#e2e8f0', marginTop: '0.35rem' }}>{transaction.comment}</p>
                    )}
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

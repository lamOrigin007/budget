export interface RegisterRequest {
  email: string;
  password: string;
  name: string;
  locale?: string;
  currency: string;
  family_name?: string;
}

export interface User {
  id: string;
  family_id: string;
  email: string;
  name: string;
  role: string;
  locale: string;
  currency_default: string;
  created_at: string;
  updated_at: string;
}

export interface Family {
  id: string;
  name: string;
  currency_base: string;
  created_at: string;
}

export interface Category {
  id: string;
  family_id: string;
  parent_id?: string | null;
  name: string;
  type: 'income' | 'expense' | 'transfer';
  color: string;
  description?: string;
  is_system: boolean;
  is_archived: boolean;
  created_at: string;
  updated_at: string;
}

export interface Account {
  id: string;
  family_id: string;
  name: string;
  type: 'cash' | 'card' | 'bank' | 'deposit' | 'wallet';
  currency: string;
  balance_minor: number;
  is_archived: boolean;
  created_at: string;
  updated_at: string;
}

export interface CategoryPayload {
  name: string;
  type: 'income' | 'expense' | 'transfer';
  color: string;
  description?: string;
  parent_id?: string | null;
}

export interface CategoryArchivePayload {
  archived: boolean;
}

export interface Transaction {
  id: string;
  user_id: string;
  family_id: string;
  account_id: string;
  category_id: string;
  type: 'income' | 'expense';
  amount_minor: number;
  currency: string;
  comment?: string;
  occurred_at: string;
  created_at: string;
  updated_at: string;
}

export interface RegisterResponse {
  user: User;
  family: Family;
  categories: Category[];
  accounts: Account[];
}

export interface TransactionRequest {
  user_id: string;
  account_id: string;
  category_id: string;
  type: 'income' | 'expense';
  amount_minor: number;
  currency: string;
  comment?: string;
  occurred_at: string;
}

export interface AccountPayload {
  name: string;
  type: 'cash' | 'card' | 'bank' | 'deposit' | 'wallet';
  currency?: string;
  initial_balance_minor?: number;
}

export interface TransactionFilters {
  start_date?: string;
  end_date?: string;
  type?: 'income' | 'expense';
  category_id?: string;
  account_id?: string;
}

const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? 'http://localhost:8080';

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE}${url}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(init?.headers ?? {})
    }
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(errorBody || response.statusText);
  }

  return (await response.json()) as T;
}

export async function registerUser(payload: RegisterRequest): Promise<RegisterResponse> {
  return request<RegisterResponse>('/api/v1/users', {
    method: 'POST',
    body: JSON.stringify(payload)
  });
}

export async function fetchCategories(userId: string): Promise<Category[]> {
  const data = await request<{ categories: Category[] }>(`/api/v1/users/${userId}/categories`);
  return data.categories;
}

export async function createCategory(userId: string, payload: CategoryPayload): Promise<Category> {
  const data = await request<{ category: Category }>(`/api/v1/users/${userId}/categories`, {
    method: 'POST',
    body: JSON.stringify(payload)
  });
  return data.category;
}

export async function fetchAccounts(userId: string): Promise<Account[]> {
  const data = await request<{ accounts: Account[] }>(`/api/v1/users/${userId}/accounts`);
  return data.accounts;
}

export async function createAccount(userId: string, payload: AccountPayload): Promise<Account> {
  const data = await request<{ account: Account }>(`/api/v1/users/${userId}/accounts`, {
    method: 'POST',
    body: JSON.stringify(payload)
  });
  return data.account;
}

export async function updateCategory(userId: string, categoryId: string, payload: CategoryPayload): Promise<Category> {
  const data = await request<{ category: Category }>(`/api/v1/users/${userId}/categories/${categoryId}`, {
    method: 'PUT',
    body: JSON.stringify(payload)
  });
  return data.category;
}

export async function setCategoryArchived(
  userId: string,
  categoryId: string,
  payload: CategoryArchivePayload
): Promise<Category> {
  const data = await request<{ category: Category }>(`/api/v1/users/${userId}/categories/${categoryId}/archive`, {
    method: 'POST',
    body: JSON.stringify(payload)
  });
  return data.category;
}

export async function createTransaction(payload: TransactionRequest): Promise<Transaction> {
  const data = await request<{ transaction: Transaction }>('/api/v1/transactions', {
    method: 'POST',
    body: JSON.stringify(payload)
  });
  return data.transaction;
}

export async function fetchTransactions(userId: string, filters?: TransactionFilters): Promise<Transaction[]> {
  const search = new URLSearchParams();
  if (filters?.start_date) {
    search.set('start_date', filters.start_date);
  }
  if (filters?.end_date) {
    search.set('end_date', filters.end_date);
  }
  if (filters?.type) {
    search.set('type', filters.type);
  }
  if (filters?.category_id) {
    search.set('category_id', filters.category_id);
  }
  if (filters?.account_id) {
    search.set('account_id', filters.account_id);
  }
  const query = search.toString();
  const url = `/api/v1/users/${userId}/transactions${query ? `?${query}` : ''}`;
  const data = await request<{ transactions: Transaction[] }>(url);
  return data.transactions;
}

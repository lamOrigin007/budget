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
  name: string;
  type: 'income' | 'expense';
  color: string;
  is_system: boolean;
  created_at: string;
}

export interface Transaction {
  id: string;
  user_id: string;
  family_id: string;
  category_id: string;
  type: 'income' | 'expense';
  amount_minor: number;
  currency: string;
  description?: string;
  occurred_at: string;
  created_at: string;
  updated_at: string;
}

export interface RegisterResponse {
  user: User;
  family: Family;
  categories: Category[];
}

export interface TransactionRequest {
  user_id: string;
  category_id: string;
  type: 'income' | 'expense';
  amount_minor: number;
  currency: string;
  description?: string;
  occurred_at: string;
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

export async function createTransaction(payload: TransactionRequest): Promise<Transaction> {
  const data = await request<{ transaction: Transaction }>('/api/v1/transactions', {
    method: 'POST',
    body: JSON.stringify(payload)
  });
  return data.transaction;
}

export async function fetchTransactions(userId: string): Promise<Transaction[]> {
  const data = await request<{ transactions: Transaction[] }>(`/api/v1/users/${userId}/transactions`);
  return data.transactions;
}

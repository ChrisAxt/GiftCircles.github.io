// src/lib/__mocks__/supabase.ts
const sampleUser = {
  id: 'user-1',
  email: 'me@example.com',
  user_metadata: { name: 'Me' },
};

type Row = Record<string, any>;

function seed(table: string): Row[] {
  switch (table) {
    case 'events':
      return [{ id: 'ev1', title: 'Party', created_at: '2025-01-01', event_date: null }];
    case 'event_members':
      return [{ event_id: 'ev1', user_id: sampleUser.id }];
    case 'lists':
      return [{ id: 'list-1', event_id: 'ev1', name: 'Gifts' }];
    case 'items':
      return [{ id: 'item-1', list_id: 'list-1', name: 'Book' }];
    case 'claims':
      return []; // add rows here if a test needs pre-claimed items
    case 'profiles':
      return [{ id: sampleUser.id, display_name: 'Me' }];
    default:
      return [];
  }
}

type Filter =
  | { type: 'eq'; col: string; val: any }
  | { type: 'in'; col: string; vals: any[] };

class QueryBuilder {
  private _table: string;
  private _filters: Filter[] = [];
  private _selected: string | null = null;
  private _ordered: { col: string; asc: boolean } | null = null;

  constructor(table: string) {
    this._table = table;
  }

  // Make awaitable
  then = (onFulfilled: any, onRejected?: any) =>
    Promise.resolve(this.exec()).then(onFulfilled, onRejected);
  catch = (onRejected: any) =>
    Promise.resolve(this.exec()).catch(onRejected);
  finally = (onFinally: any) =>
    Promise.resolve(this.exec()).finally(onFinally);

  select = (cols: string) => { this._selected = cols; return this; };
  eq = (col: string, val: any) => { this._filters.push({ type: 'eq', col, val }); return this; };
  in = (col: string, vals: any[]) => { this._filters.push({ type: 'in', col, vals }); return this; };
  order = (col: string, opts?: { ascending?: boolean }) => { this._ordered = { col, asc: opts?.ascending !== false }; return this; };

  maybeSingle = async () => {
    const { data, error } = await this.exec();
    return { data: (data?.[0] ?? null), error };
  };

  private exec = (): { data: Row[]; error: any } => {
    let rows = seed(this._table);
    for (const f of this._filters) {
      if (f.type === 'eq') rows = rows.filter(r => r?.[f.col] === f.val);
      else if (f.type === 'in') rows = rows.filter(r => f.vals?.includes(r?.[f.col]));
    }
    if (this._ordered) {
      const { col, asc } = this._ordered;
      rows = [...rows].sort((a, b) => (a?.[col] > b?.[col] ? 1 : -1) * (asc ? 1 : -1));
    }
    return { data: rows, error: null };
  };
}


export const supabase = {
  auth: {
    getSession: jest.fn().mockResolvedValue({ data: { session: {} }, error: null }),
    getUser: jest.fn().mockResolvedValue({ data: { user: sampleUser }, error: null }),
  },

  from: jest.fn((table: string) => new QueryBuilder(table)),

  rpc: jest.fn().mockResolvedValue({ data: [], error: null }),

  channel: jest.fn(() => ({
    on: jest.fn().mockReturnThis(),
    subscribe: jest.fn(),
  })),
  removeChannel: jest.fn(),
};

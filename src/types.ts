export type MemberRole = 'giver' | 'recipient' | 'admin';

export type Profile = {
  id: string;
  display_name: string | null;
  avatar_url: string | null;
};

export type Event = {
  id: string;
  title: string;
  description: string | null;
  event_date: string | null;
  join_code: string;
  owner_id: string;
  created_at?: string;
  recurrence: 'none' | 'weekly' | 'monthly' | 'yearly';
};

export type EventMember = {
  event_id: string;
  user_id: string;
  role: MemberRole;
};

export type List = {
  id: string;
  event_id: string;
  name: string;
  created_by: string;
};

export type Item = {
  id: string;
  list_id: string;
  name: string;
  url: string | null;
  price: number | null;
  notes: string | null;
  created_by: string;
  created_at?: string;
  created_by?: string | null;
};

export type Claim = {
  id: string;
  item_id: string;
  claimer_id: string;
  quantity: number;
  note: string | null;
};

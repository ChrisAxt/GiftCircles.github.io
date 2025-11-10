export type MemberRole = 'giver' | 'recipient' | 'admin';

export type Profile = {
  id: string;
  display_name: string | null;
  avatar_url: string | null;
  notification_digest_enabled?: boolean;
  digest_time_hour?: number;
  digest_frequency?: 'daily' | 'weekly';
  digest_day_of_week?: number;
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
  admin_only_invites?: boolean;
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
  random_assignment_enabled?: boolean;
  random_assignment_mode?: 'one_per_member' | 'distribute_all';
  random_assignment_executed_at?: string;
  random_receiver_assignment_enabled?: boolean;
  for_everyone?: boolean;
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
  assigned_recipient_id?: string | null;
};

export type Claim = {
  id: string;
  item_id: string;
  claimer_id: string;
  quantity: number;
  note: string | null;
  assigned_to?: string | null;
};

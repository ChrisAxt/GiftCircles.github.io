// Event Invite Types

export interface EventInvite {
  id: string;
  event_id: string;
  inviter_id: string;
  invitee_email: string;
  invitee_id: string | null;
  status: 'pending' | 'accepted' | 'declined';
  invited_at: string;
  responded_at: string | null;
}

export interface PendingInvite {
  invite_id: string;
  event_id: string;
  event_title: string;
  event_date: string | null;
  inviter_name: string;
  invited_at: string;
}

export interface InviteNotification {
  type: 'event_invite';
  invite_id: string;
  event_id: string;
}

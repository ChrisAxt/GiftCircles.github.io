// Event Invite Functions
import { supabase } from './supabase';
import { EventInvite, PendingInvite } from '../types/invites';

/**
 * Send an event invite to a user by email
 */
export async function sendEventInvite(eventId: string, inviteeEmail: string): Promise<string> {
  const { data, error } = await supabase.rpc('send_event_invite', {
    p_event_id: eventId,
    p_invitee_email: inviteeEmail,
  });

  if (error) throw error;
  return data as string; // Returns invite_id
}

/**
 * Get all pending invites for the current user
 */
export async function getMyPendingInvites(): Promise<PendingInvite[]> {
  const { data, error } = await supabase.rpc('get_my_pending_invites');

  if (error) throw error;
  return data as PendingInvite[];
}

/**
 * Accept an event invite
 */
export async function acceptEventInvite(inviteId: string): Promise<void> {
  const { error } = await supabase.rpc('accept_event_invite', {
    p_invite_id: inviteId,
  });

  if (error) throw error;
}

/**
 * Decline an event invite
 */
export async function declineEventInvite(inviteId: string): Promise<void> {
  const { error } = await supabase.rpc('decline_event_invite', {
    p_invite_id: inviteId,
  });

  if (error) throw error;
}

/**
 * Get all invites for a specific event (for event organizers)
 */
export async function getEventInvites(eventId: string): Promise<EventInvite[]> {
  const { data, error } = await supabase
    .from('event_invites')
    .select('*')
    .eq('event_id', eventId)
    .order('invited_at', { ascending: false });

  if (error) throw error;
  return data;
}

/**
 * Cancel/delete an invite (for event organizers or the inviter)
 */
export async function cancelEventInvite(inviteId: string): Promise<void> {
  const { error } = await supabase
    .from('event_invites')
    .delete()
    .eq('id', inviteId);

  if (error) throw error;
}

/**
 * Subscribe to invite changes for realtime updates
 */
export function subscribeToInvites(
  userId: string,
  onInviteReceived: (invite: EventInvite) => void
) {
  return supabase
    .channel('event_invites')
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'event_invites',
        filter: `invitee_id=eq.${userId}`,
      },
      (payload) => {
        onInviteReceived(payload.new as EventInvite);
      }
    )
    .subscribe();
}

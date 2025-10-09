// List Recipient Functions with Email Support
import { supabase } from './supabase';

export interface ListRecipient {
  list_id: string;
  user_id: string | null;
  recipient_email: string;
  display_name: string;
  is_registered: boolean;
  is_event_member: boolean;
}

/**
 * Add a recipient to a list by email
 * Automatically invites them to the event if they're not a member
 */
export async function addListRecipient(
  listId: string,
  recipientEmail: string
): Promise<string | null> {
  const { data, error } = await supabase.rpc('add_list_recipient', {
    p_list_id: listId,
    p_recipient_email: recipientEmail,
  });

  if (error) throw error;
  return data; // Returns user_id if registered, null if not
}

/**
 * Get all recipients for a list (including non-registered users)
 */
export async function getListRecipients(listId: string): Promise<ListRecipient[]> {
  const { data, error } = await supabase.rpc('get_list_recipients', {
    p_list_id: listId,
  });

  if (error) throw error;
  return data as ListRecipient[];
}

/**
 * Remove a recipient from a list
 */
export async function removeListRecipient(
  listId: string,
  recipientEmail: string
): Promise<void> {
  const { error } = await supabase
    .from('list_recipients')
    .delete()
    .eq('list_id', listId)
    .eq('recipient_email', recipientEmail);

  if (error) throw error;
}

/**
 * Create a list with both user IDs and email recipients
 */
export async function createListWithRecipients(
  eventId: string,
  name: string,
  visibility: 'private' | 'shared' | 'public',
  customRecipientName: string | null,
  recipientUserIds: string[] = [],
  recipientEmails: string[] = [],
  viewerIds: string[] = [],
  exclusionIds: string[] = []
): Promise<string> {
  const { data, error } = await supabase.rpc('create_list_with_people', {
    p_event_id: eventId,
    p_name: name,
    p_visibility: visibility,
    p_custom_recipient_name: customRecipientName,
    p_recipient_user_ids: recipientUserIds.length > 0 ? recipientUserIds : null,
    p_recipient_emails: recipientEmails.length > 0 ? recipientEmails : null,
    p_viewer_ids: viewerIds.length > 0 ? viewerIds : null,
    p_exclusion_ids: exclusionIds.length > 0 ? exclusionIds : null,
  });

  if (error) throw error;
  return data as string; // Returns list_id
}

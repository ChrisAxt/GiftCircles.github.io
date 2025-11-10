// Split Claim Types

export interface ClaimSplitRequest {
  id: string;
  item_id: string;
  requester_id: string;
  original_claimer_id: string;
  status: 'pending' | 'accepted' | 'denied';
  created_at: string;
  responded_at: string | null;
}

export interface PendingSplitRequest {
  request_id: string;
  item_id: string;
  item_name: string;
  event_id: string;
  event_title: string;
  list_name: string;
  requester_id: string;
  requester_name: string;
  created_at: string;
}

export interface SplitRequestNotification {
  type: 'claim_split_request';
  request_id: string;
  item_id: string;
}

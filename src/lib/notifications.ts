// src/lib/notifications.ts
import * as Notifications from 'expo-notifications';
import { NavigationContainerRef } from '@react-navigation/native';

export type NotificationData = {
  type?: string;
  list_id?: string;
  event_id?: string;
  invite_id?: string;
  item_id?: string;
  [key: string]: any;
};

/**
 * Configure how notifications appear when the app is foregrounded
 */
export function configureNotificationHandler() {
  Notifications.setNotificationHandler({
    handleNotification: async () => ({
      shouldShowAlert: true,
      shouldPlaySound: true,
      shouldSetBadge: false,
      shouldShowBanner: true,
      shouldShowList: true,
    }),
  });
}

/**
 * Set up listener for when user taps a notification
 * @param navigationRef - The React Navigation ref to use for navigation
 * @returns Cleanup function to remove the listener
 */
export function setupNotificationResponseListener(
  navigationRef: React.RefObject<NavigationContainerRef<any>>
) {
  console.log('[Notification] Setting up notification response listener');

  const subscription = Notifications.addNotificationResponseReceivedListener((response) => {
    console.log('[Notification] ===== NOTIFICATION TAPPED =====');
    const data = response.notification.request.content.data as NotificationData;
    console.log('[Notification] Response received:', JSON.stringify(data, null, 2));
    console.log('[Notification] Full response:', JSON.stringify(response, null, 2));

    handleNotificationNavigation(navigationRef, data);
  });

  console.log('[Notification] Listener registered successfully');
  return () => {
    console.log('[Notification] Removing listener');
    subscription.remove();
  };
}

/**
 * Handle navigation based on notification type
 */
export function handleNotificationNavigation(
  navigationRef: React.RefObject<NavigationContainerRef<any>>,
  data: NotificationData
) {
  console.log('[Notification] handleNotificationNavigation called');
  console.log('[Notification] navigationRef.current:', navigationRef.current);
  console.log('[Notification] navigationRef.current?.isReady():', navigationRef.current?.isReady());

  if (!navigationRef.current?.isReady()) {
    console.warn('[Notification] Navigation not ready, will retry in 500ms');
    setTimeout(() => handleNotificationNavigation(navigationRef, data), 500);
    return;
  }

  const { type, list_id, event_id, invite_id, item_id } = data;

  console.log('[Notification] Navigation ready! Handling navigation:', { type, list_id, event_id, invite_id, item_id });

  switch (type) {
    case 'list_for_recipient':
      // User was added as a list recipient
      // Navigate to Events tab where they can see the PendingInvitesCard and accept/decline
      console.log('[Notification] Navigating to Home -> Events tab');
      try {
        navigationRef.current.navigate('Home', { screen: 'Events' });
        console.log('[Notification] Navigation successful!');
      } catch (error) {
        console.error('[Notification] Navigation failed:', error);
      }
      break;

    case 'item_claimed':
      // Someone claimed an item on user's list
      if (list_id) {
        navigationRef.current.navigate('ListDetail', { listId: list_id });
      }
      break;

    case 'item_unclaimed':
      // Someone unclaimed an item on user's list
      if (list_id) {
        navigationRef.current.navigate('ListDetail', { listId: list_id });
      }
      break;

    case 'event_invite':
      // User was invited to an event
      // Navigate to Events tab where they can see the PendingInvitesCard and accept/decline
      navigationRef.current.navigate('Home', { screen: 'Events' });
      break;

    case 'event_update':
      // Event details were updated
      if (event_id) {
        navigationRef.current.navigate('EventDetail', { eventId: event_id });
      }
      break;

    case 'list_created':
      // New list was created in an event
      if (list_id) {
        navigationRef.current.navigate('ListDetail', { listId: list_id });
      }
      break;

    case 'purchase_reminder':
      // Reminder to purchase claimed items
      navigationRef.current.navigate('Home', { screen: 'Claimed' });
      break;

    default:
      console.warn('[Notification] Unknown notification type:', type);
      // Default to home screen
      navigationRef.current.navigate('Home');
  }
}

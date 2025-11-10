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
  const subscription = Notifications.addNotificationResponseReceivedListener((response) => {
    const data = response.notification.request.content.data as NotificationData;
    handleNotificationNavigation(navigationRef, data);
  });

  return () => {
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
  if (!navigationRef.current?.isReady()) {
    setTimeout(() => handleNotificationNavigation(navigationRef, data), 500);
    return;
  }

  const { type, list_id, event_id, invite_id, item_id } = data;

  switch (type) {
    case 'list_for_recipient':
      // User was added as a list recipient
      // Navigate to Events tab where they can see the PendingInvitesCard and accept/decline
      try {
        navigationRef.current.navigate('Home', { screen: 'Events' });
      } catch (error) {
        // Navigation failed
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
      // Default to home screen for unknown notification types
      navigationRef.current.navigate('Home');
  }
}

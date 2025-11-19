// src/lib/upgradePrompt.ts
import { Alert } from 'react-native';
import { TFunction } from 'i18next';
import { navigate } from './navigationRef';

export type UpgradeReason = 'feature' | 'eventLimit' | 'joinLimit' | 'eventAccess';

interface UpgradePromptOptions {
  reason: UpgradeReason;
  t: TFunction;
  onUpgrade?: () => void;
}

/**
 * Shows a consistent upgrade/premium prompt across the app
 * @param options Configuration for the upgrade prompt
 */
export function showUpgradePrompt({ reason, t, onUpgrade }: UpgradePromptOptions): void {
  const title = t('premium.upgradeRequired.title', 'Upgrade Required');

  let message: string;
  switch (reason) {
    case 'feature':
      message = t(
        'premium.upgradeRequired.featureMessage',
        'This feature requires a premium subscription. Upgrade to unlock purchase reminders, activity digests, random assignment, and more!'
      );
      break;
    case 'eventLimit':
      message = t(
        'premium.upgradeRequired.eventLimitMessage',
        'You can create up to 3 events on the free plan. Upgrade to create unlimited events!'
      );
      break;
    case 'joinLimit':
      message = t(
        'premium.upgradeRequired.joinLimitMessage',
        'You can be a member of up to 3 events on the free plan. Upgrade to join unlimited events or leave an existing event first.'
      );
      break;
    case 'eventAccess':
      message = t(
        'premium.upgradeRequired.eventAccessMessage',
        'You can access up to 3 events on the free plan. This event is locked. Upgrade to access all your events.'
      );
      break;
    default:
      message = t(
        'premium.upgradeRequired.genericMessage',
        'This requires a premium subscription. Upgrade to unlock all features!'
      );
  }

  Alert.alert(title, message, [
    {
      text: t('premium.upgradeRequired.cancel', 'Cancel'),
      style: 'cancel',
    },
    {
      text: t('premium.upgradeRequired.upgrade', 'Upgrade'),
      onPress: () => {
        if (onUpgrade) {
          onUpgrade();
        } else {
          // Navigate to RevenueCat paywall
          navigate('Paywall');
        }
      },
    },
  ]);
}

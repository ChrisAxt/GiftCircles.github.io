import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TouchableOpacity,
  Alert,
  AppState,
  AppStateStatus,
} from 'react-native';
import { getMySplitRequests, acceptClaimSplit, denyClaimSplit } from '../lib/splitClaims';
import { PendingSplitRequest } from '../types/splitClaims';
import { useFocusEffect, useTheme } from '@react-navigation/native';
import * as Notifications from 'expo-notifications';
import { useTranslation } from 'react-i18next';

interface PendingSplitRequestsCardProps {
  onRequestAccepted?: () => void;
  refreshTrigger?: number; // Increment this to trigger a refresh
}

export const PendingSplitRequestsCard: React.FC<PendingSplitRequestsCardProps> = ({
  onRequestAccepted,
  refreshTrigger,
}) => {
  const { colors } = useTheme();
  const { t } = useTranslation();
  const [requests, setRequests] = useState<PendingSplitRequest[]>([]);
  const [loading, setLoading] = useState(false);
  const [processingId, setProcessingId] = useState<string | null>(null);

  // Reload requests every time the screen comes into focus
  useFocusEffect(
    React.useCallback(() => {
      loadRequests();
    }, [])
  );

  // Reload when refreshTrigger changes (e.g., when parent pulls to refresh)
  useEffect(() => {
    if (refreshTrigger !== undefined) {
      loadRequests();
    }
  }, [refreshTrigger]);

  // Also reload when a notification is received (while app is open)
  useEffect(() => {
    const subscription = Notifications.addNotificationReceivedListener((notification) => {
      loadRequests();
    });

    return () => {
      subscription.remove();
    };
  }, []);

  // Reload when app comes to foreground (after tapping notification from background)
  useEffect(() => {
    const subscription = AppState.addEventListener('change', (nextAppState: AppStateStatus) => {
      if (nextAppState === 'active') {
        loadRequests();
      }
    });

    return () => {
      subscription.remove();
    };
  }, []);

  const loadRequests = async () => {
    try {
      setLoading(true);
      const data = await getMySplitRequests();
      setRequests(data);
    } catch (error) {
      Alert.alert(
        t('splitRequest.errorTitle', 'Error'),
        t('splitRequest.loadError', 'Failed to load split requests')
      );
    } finally {
      setLoading(false);
    }
  };

  const handleAccept = async (requestId: string) => {
    try {
      setProcessingId(requestId);
      await acceptClaimSplit(requestId);
      // Remove from list
      setRequests((prev) => prev.filter((req) => req.request_id !== requestId));
      Alert.alert(
        t('splitRequest.accepted.title', 'Request Accepted'),
        t('splitRequest.accepted.body', 'Split claim request accepted!')
      );
      // Trigger refresh of events/lists
      if (onRequestAccepted) {
        onRequestAccepted();
      }
    } catch (error: any) {
      Alert.alert(
        t('splitRequest.errorTitle', 'Error'),
        error?.message || t('splitRequest.acceptError', 'Failed to accept request')
      );
    } finally {
      setProcessingId(null);
    }
  };

  const handleDeny = async (requestId: string) => {
    try {
      setProcessingId(requestId);
      await denyClaimSplit(requestId);
      // Remove from list
      setRequests((prev) => prev.filter((req) => req.request_id !== requestId));
      Alert.alert(
        t('splitRequest.denied.title', 'Request Denied'),
        t('splitRequest.denied.body', 'Split claim request denied')
      );
    } catch (error: any) {
      Alert.alert(
        t('splitRequest.errorTitle', 'Error'),
        error?.message || t('splitRequest.denyError', 'Failed to deny request')
      );
    } finally {
      setProcessingId(null);
    }
  };

  const renderRequest = ({ item }: { item: PendingSplitRequest }) => {
    const isProcessing = processingId === item.request_id;

    return (
      <View
        style={[
          styles.requestCard,
          { backgroundColor: colors.background, borderLeftColor: colors.primary },
        ]}
      >
        <View style={styles.requestInfo}>
          <Text style={[styles.itemName, { color: colors.text }]}>{item.item_name}</Text>
          <Text style={[styles.eventTitle, { color: colors.text, opacity: 0.7 }]}>
            {item.event_title}
          </Text>
          <Text style={[styles.requesterName, { color: colors.text, opacity: 0.7 }]}>
            {t('splitRequest.fromLabel', 'From: {{name}}', { name: item.requester_name })}
          </Text>
          <Text style={[styles.listName, { color: colors.text, opacity: 0.5 }]}>
            {t('splitRequest.listLabel', 'List: {{name}}', { name: item.list_name })}
          </Text>
        </View>
        <View style={styles.actions}>
          <TouchableOpacity
            style={[styles.button, styles.acceptButton]}
            onPress={() => handleAccept(item.request_id)}
            disabled={isProcessing}
          >
            <Text style={styles.buttonText}>{t('splitRequest.accept', 'Accept')}</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.button, styles.denyButton]}
            onPress={() => handleDeny(item.request_id)}
            disabled={isProcessing}
          >
            <Text style={styles.buttonText}>{t('splitRequest.deny', 'Deny')}</Text>
          </TouchableOpacity>
        </View>
      </View>
    );
  };

  // Don't show card if no requests (even while loading)
  if (requests.length === 0) {
    return null;
  }

  return (
    <View style={[styles.container, { backgroundColor: colors.card }]}>
      <Text style={[styles.header, { color: colors.text }]}>
        {t('splitRequest.pending', 'Pending Split Requests')} ({requests.length})
      </Text>
      <FlatList
        data={requests}
        renderItem={renderRequest}
        keyExtractor={(item) => item.request_id}
        contentContainerStyle={styles.listContainer}
      />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    borderRadius: 12,
    padding: 16,
    marginVertical: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  header: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 12,
  },
  listContainer: {
    gap: 12,
  },
  requestCard: {
    borderRadius: 8,
    padding: 12,
    borderLeftWidth: 4,
  },
  requestInfo: {
    marginBottom: 12,
  },
  itemName: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 4,
  },
  eventTitle: {
    fontSize: 14,
    marginBottom: 2,
  },
  requesterName: {
    fontSize: 14,
    marginBottom: 2,
  },
  listName: {
    fontSize: 13,
  },
  actions: {
    flexDirection: 'row',
    gap: 8,
  },
  button: {
    flex: 1,
    paddingVertical: 10,
    paddingHorizontal: 16,
    borderRadius: 6,
    alignItems: 'center',
  },
  acceptButton: {
    backgroundColor: '#34C759',
  },
  denyButton: {
    backgroundColor: '#FF3B30',
  },
  buttonText: {
    color: '#fff',
    fontWeight: '600',
    fontSize: 14,
  },
});

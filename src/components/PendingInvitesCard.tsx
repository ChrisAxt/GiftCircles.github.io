import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, FlatList, TouchableOpacity, Alert, AppState, AppStateStatus } from 'react-native';
import { getMyPendingInvites, acceptEventInvite, declineEventInvite } from '../lib/invites';
import { PendingInvite } from '../types/invites';
import { useFocusEffect, useTheme } from '@react-navigation/native';
import * as Notifications from 'expo-notifications';

interface PendingInvitesCardProps {
  onInviteAccepted?: () => void;
  refreshTrigger?: number; // Increment this to trigger a refresh
}

export const PendingInvitesCard: React.FC<PendingInvitesCardProps> = ({ onInviteAccepted, refreshTrigger }) => {
  const { colors } = useTheme();
  const [invites, setInvites] = useState<PendingInvite[]>([]);
  const [loading, setLoading] = useState(false);
  const [processingId, setProcessingId] = useState<string | null>(null);

  // Reload invites every time the screen comes into focus
  useFocusEffect(
    React.useCallback(() => {
      loadInvites();
    }, [])
  );

  // Reload when refreshTrigger changes (e.g., when parent pulls to refresh)
  useEffect(() => {
    if (refreshTrigger !== undefined) {
      loadInvites();
    }
  }, [refreshTrigger]);

  // Also reload when a notification is received (while app is open)
  useEffect(() => {
    const subscription = Notifications.addNotificationReceivedListener((notification) => {
      loadInvites();
    });

    return () => {
      subscription.remove();
    };
  }, []);

  // Reload when app comes to foreground (after tapping notification from background)
  useEffect(() => {
    const subscription = AppState.addEventListener('change', (nextAppState: AppStateStatus) => {
      if (nextAppState === 'active') {
        loadInvites();
      }
    });

    return () => {
      subscription.remove();
    };
  }, []);

  const loadInvites = async () => {
    try {
      setLoading(true);
      const data = await getMyPendingInvites();
      setInvites(data);
    } catch (error) {
      Alert.alert('Error', 'Failed to load invites');
    } finally {
      setLoading(false);
    }
  };

  const handleAccept = async (inviteId: string) => {
    try {
      setProcessingId(inviteId);
      await acceptEventInvite(inviteId);
      // Remove from list
      setInvites((prev) => prev.filter((inv) => inv.invite_id !== inviteId));
      Alert.alert('Success', 'Invite accepted!');
      // Trigger refresh of events list
      if (onInviteAccepted) {
        onInviteAccepted();
      }
    } catch (error: any) {
      // Check for free tier limit error
      if (error?.message?.includes('free_limit_reached')) {
        Alert.alert(
          'Upgrade Required',
          'You can only be a member of 3 events on the free plan. Upgrade to join more events or leave an existing event first.',
          [{ text: 'OK' }]
        );
      } else {
        Alert.alert('Error', error?.message || 'Failed to accept invite');
      }
    } finally {
      setProcessingId(null);
    }
  };

  const handleDecline = async (inviteId: string) => {
    try {
      setProcessingId(inviteId);
      await declineEventInvite(inviteId);
      // Remove from list
      setInvites((prev) => prev.filter((inv) => inv.invite_id !== inviteId));
    } catch (error) {
      Alert.alert('Error', 'Failed to decline invite');
    } finally {
      setProcessingId(null);
    }
  };

  const renderInvite = ({ item }: { item: PendingInvite }) => {
    const isProcessing = processingId === item.invite_id;
    const inviteDate = item.event_date
      ? new Date(item.event_date).toLocaleDateString()
      : 'No date set';

    return (
      <View style={[styles.inviteCard, { backgroundColor: colors.background, borderLeftColor: colors.primary }]}>
        <View style={styles.inviteInfo}>
          <Text style={[styles.eventTitle, { color: colors.text }]}>{item.event_title}</Text>
          <Text style={[styles.inviterName, { color: colors.text, opacity: 0.7 }]}>From: {item.inviter_name}</Text>
          <Text style={[styles.eventDate, { color: colors.text, opacity: 0.5 }]}>{inviteDate}</Text>
        </View>
        <View style={styles.actions}>
          <TouchableOpacity
            style={[styles.button, styles.acceptButton]}
            onPress={() => handleAccept(item.invite_id)}
            disabled={isProcessing}
          >
            <Text style={styles.buttonText}>Accept</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={[styles.button, styles.declineButton]}
            onPress={() => handleDecline(item.invite_id)}
            disabled={isProcessing}
          >
            <Text style={styles.buttonText}>Decline</Text>
          </TouchableOpacity>
        </View>
      </View>
    );
  };

  // Don't show card if no invites (even while loading)
  if (invites.length === 0) {
    return null;
  }

  return (
    <View style={[styles.container, { backgroundColor: colors.card }]}>
      <Text style={[styles.header, { color: colors.text }]}>Pending Invitations ({invites.length})</Text>
      <FlatList
        data={invites}
        renderItem={renderInvite}
        keyExtractor={(item) => item.invite_id}
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
  inviteCard: {
    borderRadius: 8,
    padding: 12,
    borderLeftWidth: 4,
  },
  inviteInfo: {
    marginBottom: 12,
  },
  eventTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 4,
  },
  inviterName: {
    fontSize: 14,
    marginBottom: 2,
  },
  eventDate: {
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
  declineButton: {
    backgroundColor: '#FF3B30',
  },
  buttonText: {
    color: '#fff',
    fontWeight: '600',
    fontSize: 14,
  },
});

import React, { useState, useMemo } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  Modal,
  StyleSheet,
  KeyboardAvoidingView,
  Platform,
  ActivityIndicator,
} from 'react-native';
import { useTheme } from '@react-navigation/native';
import { useTranslation } from 'react-i18next';
import { supabase } from '../lib/supabase';
import { toast } from '../lib/toast';
import type { Event } from '../types';

interface RolloverModalProps {
  visible: boolean;
  event: Event;
  onClose: () => void;
  onRolloverComplete: () => void;
}

function calculateNextDate(currentDate: string, recurrence: string): Date {
  const date = new Date(currentDate + 'T00:00:00');
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  let nextDate = new Date(date);

  while (nextDate <= today) {
    switch (recurrence) {
      case 'weekly':
        nextDate.setDate(nextDate.getDate() + 7);
        break;
      case 'monthly':
        nextDate.setMonth(nextDate.getMonth() + 1);
        break;
      case 'yearly':
        nextDate.setFullYear(nextDate.getFullYear() + 1);
        break;
      default:
        return nextDate;
    }
  }

  return nextDate;
}

function formatDate(date: Date): string {
  return date.toLocaleDateString(undefined, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

export const RolloverModal: React.FC<RolloverModalProps> = ({
  visible,
  event,
  onClose,
  onRolloverComplete,
}) => {
  const { colors } = useTheme();
  const { t } = useTranslation();
  const [loading, setLoading] = useState(false);

  const nextDate = useMemo(() => {
    if (!event?.event_date || !event?.recurrence) return null;
    return calculateNextDate(event.event_date, event.recurrence);
  }, [event?.event_date, event?.recurrence]);

  const handleRollover = async () => {
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('rollover_event_manual', {
        p_event_id: event.id,
      });

      if (error) throw error;

      toast.success(t('rollover.success'));
      onRolloverComplete();
      onClose();
    } catch (error: any) {
      console.error('Rollover error:', error);
      toast.error(t('rollover.error'), {
        text2: error.message || t('rollover.errorBody')
      });
    } finally {
      setLoading(false);
    }
  };

  const handleClose = () => {
    if (!loading) {
      onClose();
    }
  };

  if (!nextDate) return null;

  return (
    <Modal
      visible={visible}
      animationType="slide"
      transparent={true}
      onRequestClose={handleClose}
    >
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.modalBackdrop}
      >
        <TouchableOpacity
          style={styles.backdropTouchable}
          activeOpacity={1}
          onPress={handleClose}
        >
          <TouchableOpacity activeOpacity={1} onPress={(e) => e.stopPropagation()}>
            <View style={[styles.modalContent, { backgroundColor: colors.card }]}>
              <Text style={[styles.title, { color: colors.text }]}>
                {t('rollover.title')}
              </Text>

              {/* Date Display */}
              <View style={styles.dateContainer}>
                <View style={styles.dateRow}>
                  <Text style={[styles.dateLabel, { color: colors.text, opacity: 0.7 }]}>
                    {t('rollover.currentDate')}:
                  </Text>
                  <Text style={[styles.dateValue, { color: colors.text }]}>
                    {formatDate(new Date(event.event_date + 'T00:00:00'))}
                  </Text>
                </View>
                <View style={[styles.arrow, { borderTopColor: colors.text }]} />
                <View style={styles.dateRow}>
                  <Text style={[styles.dateLabel, { color: colors.text, opacity: 0.7 }]}>
                    {t('rollover.nextDate')}:
                  </Text>
                  <Text style={[styles.dateValue, { color: '#2e95f1', fontWeight: '700' }]}>
                    {formatDate(nextDate)}
                  </Text>
                </View>
              </View>

              {/* Warning */}
              <View
                style={{
                  backgroundColor: '#FFF3CD',
                  borderRadius: 8,
                  padding: 12,
                  marginBottom: 16,
                  borderWidth: 1,
                  borderColor: '#FFC107',
                }}
              >
                <Text style={{ fontSize: 14, color: '#856404', fontWeight: '600' }}>
                  {t('rollover.warning')}
                </Text>
              </View>

              {/* Buttons */}
              <View style={styles.buttonContainer}>
                <TouchableOpacity
                  style={[
                    styles.button,
                    styles.cancelButton,
                    {
                      backgroundColor: colors.background,
                      borderWidth: 1,
                      borderColor: colors.border
                    },
                  ]}
                  onPress={handleClose}
                  disabled={loading}
                >
                  <Text style={[styles.cancelButtonText, { color: colors.text }]}>
                    {t('rollover.cancel')}
                  </Text>
                </TouchableOpacity>
                <TouchableOpacity
                  style={[
                    styles.button,
                    styles.confirmButton,
                    loading && styles.buttonDisabled,
                  ]}
                  onPress={handleRollover}
                  disabled={loading}
                >
                  {loading ? (
                    <ActivityIndicator color="#fff" />
                  ) : (
                    <Text style={styles.confirmButtonText}>
                      {t('rollover.confirm')}
                    </Text>
                  )}
                </TouchableOpacity>
              </View>
            </View>
          </TouchableOpacity>
        </TouchableOpacity>
      </KeyboardAvoidingView>
    </Modal>
  );
};

const styles = StyleSheet.create({
  modalBackdrop: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  backdropTouchable: {
    flex: 1,
    width: '100%',
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 16,
  },
  modalContent: {
    width: '100%',
    maxWidth: 380,
    borderRadius: 12,
    padding: 20,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 4,
    elevation: 5,
  },
  title: {
    fontSize: 20,
    fontWeight: 'bold',
    marginBottom: 16,
    textAlign: 'center',
  },
  dateContainer: {
    marginBottom: 20,
  },
  dateRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 8,
  },
  dateLabel: {
    fontSize: 14,
    fontWeight: '600',
  },
  dateValue: {
    fontSize: 14,
    fontWeight: '600',
  },
  arrow: {
    width: 0,
    height: 0,
    borderLeftWidth: 8,
    borderRightWidth: 8,
    borderTopWidth: 12,
    borderStyle: 'solid',
    backgroundColor: 'transparent',
    borderLeftColor: 'transparent',
    borderRightColor: 'transparent',
    alignSelf: 'center',
    marginVertical: 4,
  },
  optionsTitle: {
    fontSize: 15,
    fontWeight: '700',
    marginBottom: 12,
  },
  radioOption: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    borderWidth: 1,
    borderRadius: 8,
    padding: 12,
    marginBottom: 10,
  },
  radioCircle: {
    width: 20,
    height: 20,
    borderRadius: 10,
    borderWidth: 2,
    borderColor: '#2e95f1',
    marginRight: 12,
    marginTop: 2,
    justifyContent: 'center',
    alignItems: 'center',
  },
  radioSelected: {
    width: 10,
    height: 10,
    borderRadius: 5,
    backgroundColor: '#2e95f1',
  },
  radioLabel: {
    fontSize: 15,
    fontWeight: '600',
    marginBottom: 2,
  },
  radioDesc: {
    fontSize: 13,
  },
  buttonContainer: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 8,
  },
  button: {
    flex: 1,
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  cancelButton: {
    backgroundColor: '#f0f0f0',
  },
  confirmButton: {
    backgroundColor: '#FFC107',
  },
  buttonDisabled: {
    opacity: 0.5,
  },
  cancelButtonText: {
    color: '#333',
    fontWeight: '600',
    fontSize: 16,
  },
  confirmButtonText: {
    color: '#000',
    fontWeight: '700',
    fontSize: 16,
  },
});

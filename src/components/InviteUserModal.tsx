import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  Modal,
  StyleSheet,
  Alert,
  KeyboardAvoidingView,
  Platform,
  Share,
  ScrollView,
} from 'react-native';
import { useTheme } from '@react-navigation/native';
import { useTranslation } from 'react-i18next';
import { sendEventInvite } from '../lib/invites';

interface InviteUserModalProps {
  visible: boolean;
  eventId: string;
  eventTitle: string;
  joinCode: string;
  onClose: () => void;
  onInviteSent?: () => void;
}

export const InviteUserModal: React.FC<InviteUserModalProps> = ({
  visible,
  eventId,
  eventTitle,
  joinCode,
  onClose,
  onInviteSent,
}) => {
  const { colors } = useTheme();
  const { t } = useTranslation();
  const [email, setEmail] = useState('');
  const [loading, setLoading] = useState(false);

  const handleShareCode = async () => {
    try {
      await Share.share({
        message: t('eventDetail.invite.shareMessage', { title: eventTitle, code: joinCode }),
        title: t('eventDetail.invite.shareTitle', { title: eventTitle }),
      });
    } catch (error) {
      // Error sharing
    }
  };

  const handleSendInvite = async () => {
    if (!email.trim()) {
      Alert.alert(
        t('eventDetail.invite.missingEmailTitle'),
        t('eventDetail.invite.missingEmailBody')
      );
      return;
    }

    // Basic email validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      Alert.alert(
        t('eventDetail.invite.invalidEmailTitle'),
        t('eventDetail.invite.invalidEmailBody')
      );
      return;
    }

    try {
      setLoading(true);
      await sendEventInvite(eventId, email.trim());
      Alert.alert(
        t('eventDetail.invite.sentTitle'),
        t('eventDetail.invite.sentBody', { email })
      );
      setEmail('');
      onInviteSent?.();
      onClose();
    } catch (error: any) {
      Alert.alert(
        t('eventDetail.invite.sendFailedTitle'),
        error.message || t('eventDetail.invite.sendFailedBody')
      );
    } finally {
      setLoading(false);
    }
  };

  const handleClose = () => {
    setEmail('');
    onClose();
  };

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
        keyboardVerticalOffset={Platform.OS === 'ios' ? 0 : 20}
      >
        <TouchableOpacity
          style={styles.backdropTouchable}
          activeOpacity={1}
          onPress={handleClose}
        >
          <TouchableOpacity activeOpacity={1} onPress={(e) => e.stopPropagation()}>
            <View style={[styles.modalContent, { backgroundColor: colors.card }]}>
                <Text style={[styles.title, { color: colors.text }]}>
                  {t('eventDetail.invite.title', { title: eventTitle })}
                </Text>
                <Text style={[styles.subtitle, { color: colors.text, opacity: 0.7 }]}>
                  {t('eventDetail.invite.subtitle')}
                </Text>

                <TextInput
                  style={[styles.input, {
                    borderColor: colors.border,
                    backgroundColor: colors.background,
                    color: colors.text
                  }]}
                  placeholder={t('eventDetail.invite.emailPlaceholder')}
                  placeholderTextColor={colors.text + '80'}
                  value={email}
                  onChangeText={setEmail}
                  keyboardType="email-address"
                  autoCapitalize="none"
                  autoCorrect={false}
                  editable={!loading}
                />

                <View style={styles.buttonContainer}>
                  <TouchableOpacity
                    style={[styles.button, styles.cancelButton, { backgroundColor: colors.background, borderWidth: 1, borderColor: colors.border }]}
                    onPress={handleClose}
                    disabled={loading}
                  >
                    <Text style={[styles.cancelButtonText, { color: colors.text }]}>
                      {t('eventDetail.invite.cancel')}
                    </Text>
                  </TouchableOpacity>
                  <TouchableOpacity
                    style={[styles.button, styles.sendButton, loading && styles.buttonDisabled]}
                    onPress={handleSendInvite}
                    disabled={loading}
                  >
                    <Text style={styles.sendButtonText}>
                      {loading ? t('eventDetail.invite.sending') : t('eventDetail.invite.sendInvite')}
                    </Text>
                  </TouchableOpacity>
                </View>

                <View style={styles.divider}>
                  <View style={[styles.dividerLine, { backgroundColor: colors.border }]} />
                  <Text style={[styles.dividerText, { color: colors.text, opacity: 0.7 }]}>
                    {t('eventDetail.invite.or')}
                  </Text>
                  <View style={[styles.dividerLine, { backgroundColor: colors.border }]} />
                </View>

                <TouchableOpacity
                  style={[styles.button, styles.shareButton]}
                  onPress={handleShareCode}
                  disabled={loading}
                >
                  <Text style={styles.shareButtonText}>
                    {t('eventDetail.invite.shareCode')}
                  </Text>
                </TouchableOpacity>
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
    maxWidth: 340,
    borderRadius: 12,
    padding: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 4,
    elevation: 5,
  },
  title: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 6,
  },
  subtitle: {
    fontSize: 13,
    marginBottom: 12,
  },
  input: {
    borderWidth: 1,
    borderRadius: 8,
    padding: 10,
    fontSize: 15,
    marginBottom: 12,
  },
  buttonContainer: {
    flexDirection: 'row',
    gap: 12,
  },
  button: {
    flex: 1,
    paddingVertical: 10,
    borderRadius: 8,
    alignItems: 'center',
  },
  cancelButton: {
    backgroundColor: '#f0f0f0',
  },
  sendButton: {
    backgroundColor: '#007AFF',
  },
  buttonDisabled: {
    opacity: 0.5,
  },
  cancelButtonText: {
    color: '#333',
    fontWeight: '600',
    fontSize: 16,
  },
  sendButtonText: {
    color: '#fff',
    fontWeight: '600',
    fontSize: 16,
  },
  divider: {
    flexDirection: 'row',
    alignItems: 'center',
    marginVertical: 12,
  },
  dividerLine: {
    flex: 1,
    height: 1,
    backgroundColor: '#ddd',
  },
  dividerText: {
    marginHorizontal: 12,
    color: '#666',
    fontSize: 14,
    fontWeight: '600',
  },
  shareButton: {
    flex: 0,
    backgroundColor: '#4CAF50',
    paddingVertical: 12,
    alignSelf: 'stretch',
  },
  shareButtonText: {
    color: '#fff',
    fontWeight: '600',
    fontSize: 16,
    lineHeight: 20,
  },
});

// src/screens/AuthScreen.tsx
import React, { useState } from 'react';
import { View, Text, TextInput, Alert, Pressable, KeyboardAvoidingView, Platform, ScrollView, ActivityIndicator } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTheme } from '@react-navigation/native';
import { useTranslation } from 'react-i18next';
import { Ionicons } from '@expo/vector-icons';
import { supabase } from '../lib/supabase';

export default function AuthScreen() {
  const { colors } = useTheme();
  const { t } = useTranslation();
  const [mode, setMode] = useState<'signin' | 'signup' | 'forgot' | 'verify' | 'reset'>('signin');
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [verificationCode, setVerificationCode] = useState('');
  const [loading, setLoading] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);

  const signIn = async () => {
    setLoading(true);
    try {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) throw error;
    } catch (err: any) {
      Alert.alert(t('auth.errors.signInTitle'), err?.message ?? String(err));
    } finally {
      setLoading(false);
    }
  };

  const signUp = async () => {
    if (!name.trim()) {
      return Alert.alert(t('auth.errors.missingNameTitle'), t('auth.errors.missingNameBody'));
    }
    setLoading(true);
    try {
      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: { name: name.trim() }, // stored as user metadata; our DB trigger will use this
        },
      });
      if (error) throw error;

      if (data.session?.user) {
        await supabase.rpc('set_profile_name', { p_name: name.trim() });
      }

      // If email confirmation is ON, there won't be a session yet — the DB trigger will create the profile row
      if (!data.session) {
        Alert.alert(t('auth.errors.verifyEmailTitle'), t('auth.errors.verifyEmailBody'));
      }
      setMode('signin');
    } catch (err: any) {
      Alert.alert(t('auth.errors.signUpTitle'), err?.message ?? String(err));
    } finally {
      setLoading(false);
    }
  };

  const sendResetCode = async () => {
    if (!email.trim()) {
      return Alert.alert(t('auth.errors.enterEmailTitle'), t('auth.errors.enterEmailBody'));
    }
    setLoading(true);
    try {
      const { data, error } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: 'giftcircles://reset-password',
      });
      if (error) {
        throw error;
      }
      Alert.alert(t('auth.errors.resetCodeSentTitle'), t('auth.errors.resetCodeSentBody'));
      setMode('verify');
    } catch (err: any) {
      Alert.alert(
        t('auth.errors.resetCodeSendFailedTitle'),
        err?.message ?? String(err)
      );
    } finally {
      setLoading(false);
    }
  };

  const verifyCodeAndReset = async () => {
    if (!verificationCode.trim()) {
      return Alert.alert(t('auth.errors.enterCodeTitle'), t('auth.errors.enterCodeBody'));
    }
    if (!password.trim()) {
      return Alert.alert(t('auth.errors.enterPasswordTitle'), t('auth.errors.enterPasswordBody'));
    }
    if (password.length < 6) {
      return Alert.alert(t('auth.errors.passwordTooShortTitle'), t('auth.errors.passwordTooShortBody'));
    }
    if (password !== confirmPassword) {
      return Alert.alert(t('auth.errors.passwordMismatchTitle'), t('auth.errors.passwordMismatchBody'));
    }
    setLoading(true);
    try {
      // Verify the OTP code with recovery type
      const { data, error } = await supabase.auth.verifyOtp({
        email,
        token: verificationCode,
        type: 'recovery',
      });
      if (error) throw error;

      // Now that we're authenticated, update the password
      const { error: updateError } = await supabase.auth.updateUser({
        password: password,
      });
      if (updateError) throw updateError;

      Alert.alert(t('auth.errors.resetSuccessTitle'), t('auth.errors.resetSuccessBody'));

      // Clear form and return to signin
      setMode('signin');
      setPassword('');
      setConfirmPassword('');
      setVerificationCode('');
      setEmail('');
    } catch (err: any) {
      if (err?.message?.includes('invalid') || err?.message?.includes('expired') || err?.message?.includes('Token')) {
        Alert.alert(t('auth.errors.invalidCodeTitle'), t('auth.errors.invalidCodeBody'));
      } else {
        Alert.alert(t('auth.errors.resetFailedTitle'), err?.message ?? String(err));
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: colors.background }} edges={['top', 'left', 'right', 'bottom']}>
      <KeyboardAvoidingView
        style={{ flex: 1 }}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        keyboardVerticalOffset={Platform.OS === 'ios' ? 0 : 20}
      >
        <ScrollView
          contentContainerStyle={{ flexGrow: 1, justifyContent: 'center', padding: 16, gap: 12 }}
          keyboardShouldPersistTaps="handled"
        >
          <Text style={{ fontSize: 24, fontWeight: '600', marginBottom: 8, color: colors.text }}>
            {mode === 'forgot' || mode === 'verify' ? t('auth.resetPassword') : t('auth.appTitle')}
          </Text>

      {mode === 'signup' && (
        <TextInput
          placeholder={t('auth.fullNameLabel')}
          placeholderTextColor={colors.text + '80'}
          value={name}
          onChangeText={setName}
          autoCapitalize="words"
          style={{
            borderWidth: 1,
            borderColor: colors.border,
            padding: 10,
            borderRadius: 8,
            color: colors.text,
            backgroundColor: colors.card
          }}
        />
      )}

      {(mode === 'signin' || mode === 'signup' || mode === 'forgot' || mode === 'verify') && (
        <TextInput
          placeholder={t('auth.emailLabel')}
          placeholderTextColor={colors.text + '80'}
          autoCapitalize="none"
          keyboardType="email-address"
          value={email}
          onChangeText={setEmail}
          editable={mode !== 'verify'}
          style={{
            borderWidth: 1,
            borderColor: colors.border,
            padding: 10,
            borderRadius: 8,
            color: colors.text,
            backgroundColor: colors.card,
            opacity: mode === 'verify' ? 0.6 : 1
          }}
        />
      )}

      {mode === 'verify' && (
        <TextInput
          placeholder={t('auth.verificationCode')}
          placeholderTextColor={colors.text + '80'}
          autoCapitalize="none"
          keyboardType="number-pad"
          value={verificationCode}
          onChangeText={setVerificationCode}
          style={{
            borderWidth: 1,
            borderColor: colors.border,
            padding: 10,
            borderRadius: 8,
            color: colors.text,
            backgroundColor: colors.card
          }}
        />
      )}

      {(mode === 'signin' || mode === 'signup') && (
        <View style={{ position: 'relative' }}>
          <TextInput
            placeholder={t('auth.passwordLabel')}
            placeholderTextColor={colors.text + '80'}
            secureTextEntry={!showPassword}
            value={password}
            onChangeText={setPassword}
            style={{
              borderWidth: 1,
              borderColor: colors.border,
              padding: 10,
              paddingRight: mode === 'signup' ? 45 : 10,
              borderRadius: 8,
              color: colors.text,
              backgroundColor: colors.card
            }}
          />
          {mode === 'signup' && (
            <Pressable
              onPress={() => setShowPassword(!showPassword)}
              style={{
                position: 'absolute',
                right: 10,
                top: 0,
                bottom: 0,
                justifyContent: 'center',
                padding: 5
              }}
            >
              <Ionicons name={showPassword ? 'eye' : 'eye-off'} size={22} color={colors.text} />
            </Pressable>
          )}
        </View>
      )}

      {mode === 'verify' && (
        <>
          <View style={{ position: 'relative' }}>
            <TextInput
              placeholder={t('auth.newPassword')}
              placeholderTextColor={colors.text + '80'}
              secureTextEntry={!showPassword}
              value={password}
              onChangeText={setPassword}
              style={{
                borderWidth: 1,
                borderColor: colors.border,
                padding: 10,
                paddingRight: 45,
                borderRadius: 8,
                color: colors.text,
                backgroundColor: colors.card
              }}
            />
            <Pressable
              onPress={() => setShowPassword(!showPassword)}
              style={{
                position: 'absolute',
                right: 10,
                top: 0,
                bottom: 0,
                justifyContent: 'center',
                padding: 5
              }}
            >
              <Ionicons name={showPassword ? 'eye' : 'eye-off'} size={22} color={colors.text} />
            </Pressable>
          </View>
          <View style={{ position: 'relative' }}>
            <TextInput
              placeholder={t('auth.confirmPassword')}
              placeholderTextColor={colors.text + '80'}
              secureTextEntry={!showConfirmPassword}
              value={confirmPassword}
              onChangeText={setConfirmPassword}
              style={{
                borderWidth: 1,
                borderColor: colors.border,
                padding: 10,
                paddingRight: 45,
                borderRadius: 8,
                color: colors.text,
                backgroundColor: colors.card
              }}
            />
            <Pressable
              onPress={() => setShowConfirmPassword(!showConfirmPassword)}
              style={{
                position: 'absolute',
                right: 10,
                top: 0,
                bottom: 0,
                justifyContent: 'center',
                padding: 5
              }}
            >
              <Text style={{ fontSize: 20 }}>{showConfirmPassword ? '👁️' : '👁️‍🗨️'}</Text>
            </Pressable>
          </View>
        </>
      )}

      {mode === 'signin' ? (
        <>
          <Pressable
            onPress={signIn}
            disabled={loading}
            style={{
              backgroundColor: '#2e95f1',
              paddingVertical: 12,
              paddingHorizontal: 16,
              borderRadius: 10,
              alignItems: 'center',
              opacity: loading ? 0.7 : 1,
              marginTop: 8
            }}
          >
            {loading ? (
              <ActivityIndicator color="#fff" />
            ) : (
              <Text style={{ color: '#fff', fontWeight: '700', fontSize: 16 }}>{t('auth.signIn')}</Text>
            )}
          </Pressable>
          <Pressable onPress={() => setMode('signup')} style={{ padding: 8, alignItems: 'center' }}>
            <Text style={{ color: colors.primary }}>{t('auth.createAnAccount')}</Text>
          </Pressable>
          <Pressable onPress={() => setMode('forgot')} style={{ padding: 8, alignItems: 'center' }}>
            <Text style={{ color: colors.primary }}>{t('auth.forgotPassword')}</Text>
          </Pressable>
        </>
      ) : mode === 'signup' ? (
        <>
          <Pressable
            onPress={signUp}
            disabled={loading}
            style={{
              backgroundColor: '#2e95f1',
              paddingVertical: 12,
              paddingHorizontal: 16,
              borderRadius: 10,
              alignItems: 'center',
              opacity: loading ? 0.7 : 1,
              marginTop: 8
            }}
          >
            {loading ? (
              <ActivityIndicator color="#fff" />
            ) : (
              <Text style={{ color: '#fff', fontWeight: '700', fontSize: 16 }}>{t('auth.createAccount')}</Text>
            )}
          </Pressable>
          <Pressable onPress={() => setMode('signin')} style={{ padding: 8, alignItems: 'center' }}>
            <Text style={{ color: colors.primary }}>{t('auth.haveAccount')}</Text>
          </Pressable>
        </>
      ) : mode === 'forgot' ? (
        <>
          <Pressable
            onPress={sendResetCode}
            disabled={loading}
            style={{
              backgroundColor: '#2e95f1',
              paddingVertical: 12,
              paddingHorizontal: 16,
              borderRadius: 10,
              alignItems: 'center',
              opacity: loading ? 0.7 : 1,
              marginTop: 8
            }}
          >
            {loading ? (
              <ActivityIndicator color="#fff" />
            ) : (
              <Text style={{ color: '#fff', fontWeight: '700', fontSize: 16 }}>{t('auth.sendResetCode')}</Text>
            )}
          </Pressable>
          <Pressable onPress={() => setMode('signin')} style={{ padding: 8, alignItems: 'center' }}>
            <Text style={{ color: colors.primary }}>{t('auth.backToSignIn')}</Text>
          </Pressable>
        </>
      ) : mode === 'verify' ? (
        <>
          <Pressable
            onPress={verifyCodeAndReset}
            disabled={loading}
            style={{
              backgroundColor: '#2e95f1',
              paddingVertical: 12,
              paddingHorizontal: 16,
              borderRadius: 10,
              alignItems: 'center',
              opacity: loading ? 0.7 : 1,
              marginTop: 8
            }}
          >
            {loading ? (
              <ActivityIndicator color="#fff" />
            ) : (
              <Text style={{ color: '#fff', fontWeight: '700', fontSize: 16 }}>{t('auth.verifyCode')}</Text>
            )}
          </Pressable>
          <Pressable onPress={() => setMode('signin')} style={{ padding: 8, alignItems: 'center' }}>
            <Text style={{ color: colors.primary }}>{t('auth.backToSignIn')}</Text>
          </Pressable>
        </>
      ) : null}
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

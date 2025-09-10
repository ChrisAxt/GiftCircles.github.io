// src/components/LabeledInput.tsx
import React from 'react';
import { View, Text, TextInput, Pressable, ViewStyle, TextStyle } from 'react-native';

type BaseProps = {
  label: string;
  hint?: string;                 // optional small helper text under the field
  containerStyle?: ViewStyle;
  labelStyle?: TextStyle;
};

type InputProps = BaseProps & {
  value: string;
  onChangeText: (t: string) => void;
  placeholder?: string;          // e.g. "e.g. Bob’s Birthday"
  multiline?: boolean;
  keyboardType?: 'default' | 'email-address' | 'numeric' | 'decimal-pad' | 'number-pad' | 'phone-pad' | 'url';
  secureTextEntry?: boolean;
  editable?: boolean;
  autoCapitalize?: 'none' | 'sentences' | 'words' | 'characters';
};

export function LabeledInput({
  label,
  hint,
  containerStyle,
  labelStyle,
  ...rest
}: InputProps) {
  return (
    <View style={[{ marginBottom: 12 }, containerStyle]}>
      <Text style={[{ fontSize: 12, fontWeight: '700', opacity: 0.7, marginBottom: 6 }, labelStyle]}>{label}</Text>
      <TextInput
        {...rest}
        style={{
          borderWidth: 1,
          borderColor: '#e5e7eb',
          borderRadius: 10,
          paddingVertical: 10,
          paddingHorizontal: 12,
          backgroundColor: '#f9fafb',
        }}
        placeholderTextColor="#9aa3af"
      />
      {hint ? <Text style={{ marginTop: 6, fontSize: 12, color: '#6b7280' }}>{hint}</Text> : null}
    </View>
  );
}

type PressableFieldProps = BaseProps & {
  valueText?: string;            // what to show when selected
  placeholder?: string;          // e.g. "Select a date"
  onPress: () => void;
};

export function LabeledPressableField({
  label,
  hint,
  valueText,
  placeholder = 'Select',
  onPress,
  containerStyle,
  labelStyle,
}: PressableFieldProps) {
  const hasValue = !!valueText;
  return (
    <View style={[{ marginBottom: 12 }, containerStyle]}>
      <Text style={[{ fontSize: 12, fontWeight: '700', opacity: 0.7, marginBottom: 6 }, labelStyle]}>{label}</Text>
      <Pressable
        onPress={onPress}
        style={{
          borderWidth: 1,
          borderColor: '#e5e7eb',
          borderRadius: 10,
          paddingVertical: 12,
          paddingHorizontal: 12,
          backgroundColor: '#fff',
        }}
      >
        <Text style={{ color: hasValue ? '#111827' : '#9aa3af' }}>
          {hasValue ? valueText : placeholder}
        </Text>
      </Pressable>
      {hint ? <Text style={{ marginTop: 6, fontSize: 12, color: '#6b7280' }}>{hint}</Text> : null}
    </View>
  );
}

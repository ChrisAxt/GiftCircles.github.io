// src/components/LabeledInput.tsx
import React from 'react';
import { View, Text, TextInput, Pressable, ViewStyle, TextStyle } from 'react-native';
import { useTheme } from '@react-navigation/native';

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
  const { colors } = useTheme();

  return (
    <View style={[{ marginBottom: 12 }, containerStyle]}>
      <Text style={[{ fontSize: 12, fontWeight: '700', opacity: 0.7, marginBottom: 6, color: colors.text }, labelStyle]}>
        {label}
      </Text>
      <TextInput
        {...rest}
        style={{
          borderWidth: 1,
          borderColor: colors.border,
          borderRadius: 10,
          paddingVertical: 10,
          paddingHorizontal: 12,
          backgroundColor: colors.card,
          color: colors.text,
          // better cursor & layout for multiline in dark mode
          textAlignVertical: rest.multiline ? 'top' : 'center',
        }}
        placeholderTextColor={hexWithOpacity(colors.text, 0.45)}
      />
      {hint ? (
        <Text style={{ marginTop: 6, fontSize: 12, color: hexWithOpacity(colors.text, 0.7) }}>
          {hint}
        </Text>
      ) : null}
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
  const { colors } = useTheme();
  const hasValue = !!valueText;

  return (
    <View style={[{ marginBottom: 12 }, containerStyle]}>
      <Text style={[{ fontSize: 12, fontWeight: '700', opacity: 0.7, marginBottom: 6, color: colors.text }, labelStyle]}>
        {label}
      </Text>
      <Pressable
        onPress={onPress}
        style={{
          borderWidth: 1,
          borderColor: colors.border,
          borderRadius: 10,
          paddingVertical: 12,
          paddingHorizontal: 12,
          backgroundColor: colors.card,
        }}
      >
        <Text style={{ color: hasValue ? colors.text : hexWithOpacity(colors.text, 0.45) }}>
          {hasValue ? valueText : placeholder}
        </Text>
      </Pressable>
      {hint ? (
        <Text style={{ marginTop: 6, fontSize: 12, color: hexWithOpacity(colors.text, 0.7) }}>
          {hint}
        </Text>
      ) : null}
    </View>
  );
}

/** Utility: apply alpha to a theme text color (assumes hex or rgb(a)) */
function hexWithOpacity(textColor: string, opacity: number): string {
  // If it's already rgba, just replace the alpha
  if (textColor.startsWith('rgb')) {
    const parts = textColor.replace(/[rgba()\s]/g, '').split(',');
    const [r, g, b] = parts;
    return `rgba(${r}, ${g}, ${b}, ${opacity})`;
  }
  // Handle hex #rrggbb
  if (textColor.startsWith('#') && (textColor.length === 7 || textColor.length === 4)) {
    const hex = textColor.length === 4
      ? `#${textColor[1]}${textColor[1]}${textColor[2]}${textColor[2]}${textColor[3]}${textColor[3]}`
      : textColor;
    const r = parseInt(hex.slice(1, 3), 16);
    const g = parseInt(hex.slice(3, 5), 16);
    const b = parseInt(hex.slice(5, 7), 16);
    return `rgba(${r}, ${g}, ${b}, ${opacity})`;
  }
  // Fallback: default to 60% black/white based on theme text luminance
  return `rgba(127,127,127,${opacity})`;
}

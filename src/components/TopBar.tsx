import React from 'react';
import { View, Text, Pressable } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme, useNavigation } from '@react-navigation/native';

type TopBarProps = {
  title?: string;
  right?: React.ReactNode;  // optional right-side actions
  onBack?: () => void;      // override back behavior if needed
};

export default function TopBar({ title, right, onBack }: TopBarProps) {
  const { top } = useSafeAreaInsets();
  const { colors } = useTheme();
  const navigation = useNavigation();

  return (
    <View style={{ backgroundColor: colors.card }}>
      {/* Safe-area spacer */}
      <View style={{ height: top }} />
      {/* Bar */}
      <View
        style={{
          height: 56,
          borderBottomWidth: 1,
          borderColor: colors.border,
          flexDirection: 'row',
          alignItems: 'center',
          justifyContent: 'space-between',
          paddingHorizontal: 8,
        }}
      >
        <Pressable
          onPress={onBack || (() => (navigation.canGoBack() ? navigation.goBack() : navigation.navigate('Events' as never)))}
          hitSlop={12}
          style={{ padding: 6, minWidth: 40 }}
        >
          <Text style={{ fontSize: 30, color: colors.text }}>{'\u2039'}</Text>
        </Pressable>

        <Text style={{ flex: 1, textAlign: 'center', fontWeight: '700', color: colors.text }} numberOfLines={1}>
          {title || ''}
        </Text>

        <View style={{ minWidth: 40, alignItems: 'flex-end' }}>{right}</View>
      </View>
    </View>
  );
}

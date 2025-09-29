// src/components/Screen.tsx
import React from 'react';
import { View, ScrollView } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTheme } from '@react-navigation/native';

type BaseProps = {
  children: React.ReactNode;
  style?: any;
  backgroundColor?: string;       // if passed, overrides theme
  withTopSafeArea?: boolean;      // opt-in
};

/** For FlatList/SectionList pages (NO ScrollView here). */
export function Screen({
  children,
  style,
  backgroundColor,
  withTopSafeArea = false,
}: BaseProps) {
  const { colors } = useTheme();
  const bg = backgroundColor ?? colors.background;

  return (
    <SafeAreaView
      edges={withTopSafeArea ? ['top', 'left', 'right', 'bottom'] : ['left', 'right', 'bottom']}
      style={{ flex: 1, backgroundColor: bg, paddingBottom: 24 }}
    >
      <View style={[{ flex: 1 }, style]}>{children}</View>
    </SafeAreaView>
  );
}

/** For form/static pages that do use a ScrollView (no FlatList here). */
export function ScreenScroll({
  children,
  style,
  backgroundColor,
  withTopSafeArea = false,
  contentContainerStyle,
}: BaseProps & { contentContainerStyle?: any }) {
  const { colors } = useTheme();
  const bg = backgroundColor ?? colors.background;

  return (
    <SafeAreaView
      edges={withTopSafeArea ? ['top', 'left', 'right', 'bottom'] : ['left', 'right', 'bottom']}
      style={{ flex: 1, backgroundColor: bg }}
    >
      <ScrollView
        keyboardShouldPersistTaps="handled"
        contentInsetAdjustmentBehavior="never"
        automaticallyAdjustContentInsets={false}
        contentContainerStyle={[
          { paddingBottom: 24 },
          contentContainerStyle,
        ]}
        style={style}
      >
        {children}
      </ScrollView>
    </SafeAreaView>
  );
}

// src/components/Screen.tsx
import React from 'react';
import { View, ScrollView, KeyboardAvoidingView, Platform, StatusBar } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTheme } from '@react-navigation/native';

type BaseProps = {
  children: React.ReactNode;
  style?: any;
  backgroundColor?: string;       // if passed, overrides theme
  withTopSafeArea?: boolean;      // opt-in
  withKeyboardAvoid?: boolean;    // opt-in for keyboard handling
  noPaddingBottom?: boolean;      // opt-out of default bottom padding
};

/** For FlatList/SectionList pages (NO ScrollView here). */
export function Screen({
  children,
  style,
  backgroundColor,
  withTopSafeArea = false,
  withKeyboardAvoid = false,
  noPaddingBottom = false,
}: BaseProps) {
  const { colors, dark } = useTheme();
  const bg = backgroundColor ?? colors.background;

  const content = <View style={[{ flex: 1 }, style]}>{children}</View>;

  return (
    <SafeAreaView
      edges={withTopSafeArea ? ['top', 'left', 'right', 'bottom'] : ['left', 'right', 'bottom']}
      style={{ flex: 1, backgroundColor: bg, paddingBottom: noPaddingBottom ? 0 : 40 }}
    >
      <StatusBar barStyle={dark ? 'light-content' : 'dark-content'} />
      
      {withKeyboardAvoid ? (
        <KeyboardAvoidingView
          style={{ flex: 1 }}
          behavior={Platform.OS === 'ios' ? 'padding' : undefined}
          keyboardVerticalOffset={Platform.OS === 'ios' ? 0 : 0}
        >
          {content}
        </KeyboardAvoidingView>
      ) : (
        content
      )}
    </SafeAreaView>
  );
}

/** For form/static pages that do use a ScrollView (no FlatList here). */
export function ScreenScroll({
  children,
  style,
  backgroundColor,
  withTopSafeArea = false,
  withKeyboardAvoid = false,
  contentContainerStyle,
}: BaseProps & { contentContainerStyle?: any }) {
  const { colors, dark } = useTheme();
  const bg = backgroundColor ?? colors.background;

  const scrollContent = (
    <ScrollView
      keyboardShouldPersistTaps="handled"
      contentInsetAdjustmentBehavior="never"
      automaticallyAdjustContentInsets={false}
      contentContainerStyle={[
        { paddingBottom: 26 },
        contentContainerStyle,
      ]}
      style={style}
    >
      {children}
    </ScrollView>
  );

  return (
    <SafeAreaView
      edges={withTopSafeArea ? ['top', 'left', 'right', 'bottom'] : ['left', 'right', 'bottom']}
      style={{ flex: 1, backgroundColor: bg }}
    >
      <StatusBar barStyle={dark ? 'light-content' : 'dark-content'} />
      {withKeyboardAvoid ? (
        <KeyboardAvoidingView
          style={{ flex: 1 }}
          behavior={Platform.OS === 'ios' ? 'padding' : undefined}
          keyboardVerticalOffset={Platform.OS === 'ios' ? 0 : 0}
        >
          {scrollContent}
        </KeyboardAvoidingView>
      ) : (
        scrollContent
      )}
    </SafeAreaView>
  );
}

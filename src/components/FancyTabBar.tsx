// src/components/FancyTabBar.tsx
import React from 'react';
import { View, Text, Pressable } from 'react-native';
import { BottomTabBarProps } from '@react-navigation/bottom-tabs';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Ionicons from '@expo/vector-icons/Ionicons';

const ACTIVE = '#2e95f1';
const INACTIVE = '#7c8a9a';
const BG = '#ffffff';

const ICONS: Record<string, { active: keyof typeof Ionicons.glyphMap; inactive: keyof typeof Ionicons.glyphMap; label: string }> = {
  Events:   { active: 'calendar',         inactive: 'calendar-outline',         label: 'Events' },
  // Add more tabs below as you add screens:
  // Lists: { active: 'list',             inactive: 'list-outline',             label: 'Lists' },
  // Activity:{ active: 'notifications',  inactive: 'notifications-outline',    label: 'Activity' },
  Profile:  { active: 'person',           inactive: 'person-outline',           label: 'Profile' },
};

export default function FancyTabBar({ state, descriptors, navigation }: BottomTabBarProps) {
  const inset = useSafeAreaInsets();
  return (
    <View pointerEvents="box-none" style={{ position: 'absolute', left: 0, right: 0, bottom: 0, paddingBottom: inset.bottom + 8 }}>
      <View
        style={{
          marginHorizontal: 16,
          backgroundColor: BG,
          borderRadius: 20,
          paddingVertical: 10,
          paddingHorizontal: 12,
          shadowColor: '#000',
          shadowOpacity: 0.08,
          shadowRadius: 10,
          shadowOffset: { width: 0, height: 4 },
          elevation: 6,
          flexDirection: 'row',
          justifyContent: 'space-around',
          alignItems: 'center',
        }}
      >
        {state.routes.map((route, index) => {
          const isFocused = state.index === index;
          const onPress = () => {
            const event = navigation.emit({ type: 'tabPress', target: route.key, canPreventDefault: true });
            if (!isFocused && !event.defaultPrevented) navigation.navigate(route.name as never);
          };
          const onLongPress = () => navigation.emit({ type: 'tabLongPress', target: route.key });

          const iconMeta = ICONS[route.name] ?? {
            active: 'ellipse',
            inactive: 'ellipse-outline',
            label: route.name,
          };

          return (
            <Pressable
              key={route.key}
              onPress={onPress}
              onLongPress={onLongPress}
              style={{ flex: 1, alignItems: 'center', justifyContent: 'center', paddingVertical: 6 }}
            >
              <View style={{ alignItems: 'center' }}>
                <Ionicons
                  name={isFocused ? iconMeta.active : iconMeta.inactive}
                  size={22}
                  color={isFocused ? ACTIVE : INACTIVE}
                />
                <Text
                  style={{
                    marginTop: 4,
                    fontSize: 11,
                    fontWeight: isFocused ? '700' : '600',
                    color: isFocused ? ACTIVE : INACTIVE,
                  }}
                >
                  {iconMeta.label}
                </Text>
                {isFocused && (
                  <View
                    style={{
                      marginTop: 6,
                      width: 18,
                      height: 3,
                      borderRadius: 2,
                      backgroundColor: ACTIVE,
                    }}
                  />
                )}
              </View>
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}

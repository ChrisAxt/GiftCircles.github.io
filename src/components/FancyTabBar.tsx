import React from 'react';
import { View, Pressable, Text } from 'react-native';
import type { BottomTabBarProps } from '@react-navigation/bottom-tabs';
import { MaterialCommunityIcons, Feather } from '@expo/vector-icons';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

export default function FancyTabBar({ state, descriptors, navigation }: BottomTabBarProps) {
    const insets = useSafeAreaInsets();
  return (
      <SafeAreaView
            edges={['bottom']}                      // ← NEW
            style={{
              backgroundColor: 'white',
              borderTopWidth: 1,
              borderTopColor: '#edf1f5',
            }}
          >
    <View
      style={{
        flexDirection: 'row',
        backgroundColor: 'white',
        paddingVertical: 8,
        borderTopWidth: 1,
        borderTopColor: '#edf1f5',
      }}
    >
      {state.routes.map((route, index) => {
        const { options } = descriptors[route.key];
        const focused = state.index === index;
        const color = focused ? '#2e95f1' : '#9aa3af';
        const label =
          options.tabBarLabel !== undefined
            ? options.tabBarLabel
            : options.title !== undefined
            ? options.title
            : route.name;

        const onPress = () => {
          const event = navigation.emit({ type: 'tabPress', target: route.key, canPreventDefault: true });
          if (!focused && !event.defaultPrevented) {
            navigation.navigate(route.name as never);
          }
        };

        const icon = (() => {
          switch (route.name) {
            case 'Events':
              return <Feather name="calendar" size={22} color={color} />;
            case 'Lists':
              return (
                <MaterialCommunityIcons
                  name={focused ? 'clipboard-list' : 'clipboard-list-outline'}
                  size={24}
                  color={color}
                />
              );
            case 'Claimed':
              return (
                <MaterialCommunityIcons
                  name={focused ? 'checkbox-marked-circle' : 'checkbox-marked-circle-outline'}
                  size={24}
                  color={color}
                />
              );
            case 'Profile':
              return <Feather name="user" size={22} color={color} />;
            default:
              return <Feather name="circle" size={22} color={color} />;
          }
        })();

        return (
          <Pressable
            key={route.key}
            onPress={onPress}
            style={{ flex: 1, alignItems: 'center', justifyContent: 'center', paddingVertical: 6 }}
          >
            {icon}
            <Text style={{ fontSize: 12, marginTop: 2, color }}>{String(label)}</Text>
          </Pressable>
        );
      })}
    </View>
    </SafeAreaView>
  );
}

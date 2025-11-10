import React from 'react';
import { View, Pressable, Text } from 'react-native';
import type { MaterialTopTabBarProps } from '@react-navigation/material-top-tabs';
import { MaterialCommunityIcons, Feather } from '@expo/vector-icons';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '@react-navigation/native';

export default function FancyTabBar({ state, descriptors, navigation }: MaterialTopTabBarProps) {
  const insets = useSafeAreaInsets();
  const { colors } = useTheme();

  return (
    <SafeAreaView
      edges={['bottom']}
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        bottom: 0,
        backgroundColor: colors.card,   // theme surface
        borderTopWidth: 1,
        borderTopColor: colors.border,  // theme border
        zIndex: 100,
        elevation: 20,
        paddingBottom: 0,
      }}
    >
      <View
        style={{
          flexDirection: 'row',
          backgroundColor: colors.card, // theme surface
          paddingVertical: 8,
          borderTopWidth: 1,
          borderTopColor: colors.border, // theme border
        }}
      >
        {state.routes.map((route, index) => {
          const { options } = descriptors[route.key];
          const focused = state.index === index;

          const active = '#2e95f1';        // keep brand blue
          const inactive = colors.text;    // use theme text and dim label below
          const iconColor = focused ? active : inactive;

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
                return <Feather name="calendar" size={22} color={iconColor} />;
              case 'Lists':
                return (
                  <MaterialCommunityIcons
                    name={focused ? 'clipboard-list' : 'clipboard-list-outline'}
                    size={24}
                    color={iconColor}
                  />
                );
              case 'Claimed':
                return (
                  <MaterialCommunityIcons
                    name={focused ? 'checkbox-marked-circle' : 'checkbox-marked-circle-outline'}
                    size={24}
                    color={iconColor}
                  />
                );
              case 'Profile':
                return <Feather name="user" size={22} color={iconColor} />;
              default:
                return <Feather name="circle" size={22} color={iconColor} />;
            }
          })();

          return (
            <Pressable
              key={route.key}
              onPress={onPress}
              style={{ flex: 1, alignItems: 'center', justifyContent: 'center', paddingVertical: 6 }}
              hitSlop={{ top: 6, bottom: 6, left: 6, right: 6 }} // easier to press, no visual change
            >
              {icon}
              <Text style={{ fontSize: 12, marginTop: 2, color: iconColor, opacity: focused ? 1 : 0.6 }}>
                {String(label)}
              </Text>
            </Pressable>
          );
        })}
      </View>
    </SafeAreaView>
  );
}

// src/navigation/index.tsx
import React, { useEffect, useState, useRef } from 'react';
import { ActivityIndicator, View, Platform } from 'react-native';
import { NavigationContainer, DefaultTheme, DarkTheme, Theme, NavigationContainerRef  } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { createMaterialTopTabNavigator } from '@react-navigation/material-top-tabs';
import { Session } from '@supabase/supabase-js';
import { useTranslation } from 'react-i18next';
import { supabase } from '../lib/supabase';
import Constants from 'expo-constants';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { configureNotificationHandler, setupNotificationResponseListener } from '../lib/notifications';
import Toast, { BaseToast, ErrorToast } from 'react-native-toast-message';

// import { StatusBar } from 'expo-status-bar';

// Settings (wrap + hook for theme/lang)
import { SettingsProvider, useSettings } from '../theme/SettingsProvider';

// Screens
import AuthScreen from '../screens/AuthScreen';
import EventListScreen from '../screens/EventListScreen';
import EventDetailScreen from '../screens/EventDetailScreen';
import CreateEventScreen from '../screens/CreateEventScreen';
import JoinEventScreen from '../screens/JoinEventScreen';
import ListDetailScreen from '../screens/ListDetailScreen';
import AddItemScreen from '../screens/AddItemScreen';
import CreateListScreen from '../screens/CreateListScreen';
import EditListScreen from '../screens/EditListScreen';
import ProfileScreen from '../screens/ProfileScreen';
import EditEventScreen from '../screens/EditEventScreen';
import OnboardingScreen from '../screens/OnboardingScreen';
import AllListsScreen from '../screens/AllListsScreen';
import MyClaimsScreen from '../screens/MyClaimsScreen';
import EditItemScreen from '../screens/EditItemScreen';
import FancyTabBar from '../components/FancyTabBar';

const Stack = createNativeStackNavigator();
const Tab = createMaterialTopTabNavigator();
const CustomDarkTheme: Theme = {
  ...DarkTheme,
  colors: {
    ...DarkTheme.colors,
    primary: '#2e95f1',   // keep your brand blue
    background: '#161a1e',// app background (dark, not black)
    card: '#1e242a',      // surfaces/cards/tabbar/header
    text: '#e8eef5',      // primary text
    border: '#2a3138',    // dividers/borders
    notification: DarkTheme.colors.notification,
  },
};
/** Tabs with full-screen swipe (tab bar pinned to bottom) */
function Tabs() {
  const { t } = useTranslation();
  return (
    <Tab.Navigator
      screenOptions={{
        headerShown: false,
        tabBarHideOnKeyboard: false,
        tabBarPosition: 'bottom',
      }}
      tabBar={(p) => <FancyTabBar {...p} />}
    >
      <Tab.Screen name="Events" component={EventListScreen} options={{ title: t('navigation.tabs.events') }} />
      <Tab.Screen name="Lists" component={AllListsScreen} options={{ title: t('navigation.tabs.lists') }} />
      <Tab.Screen name="Claimed" component={MyClaimsScreen} options={{ title: t('navigation.tabs.claimed') }} />
      <Tab.Screen name="Profile" component={ProfileScreen} options={{ title: t('navigation.tabs.profile') }} />
    </Tab.Navigator>
  );
}

/** Inner navigator that *uses* Settings and provides themed NavigationContainer */
function InnerNavigator() {
  const { colorScheme } = useSettings();
  const theme = colorScheme === 'dark' ? CustomDarkTheme : DefaultTheme;
  const isDark = colorScheme === 'dark';
  const inExpoGo = Constants.appOwnership === 'expo';
  const isAndroid = Platform.OS === 'android';
  const navigationRef = useRef<NavigationContainerRef<any>>(null);

  // Toast config based on app theme
  const toastConfig = {
    success: (props: any) => (
      <BaseToast
        {...props}
        style={{
          borderLeftColor: '#10b981',
          backgroundColor: isDark ? '#1f2937' : '#ffffff',
        }}
        contentContainerStyle={{ paddingHorizontal: 15 }}
        text1Style={{
          fontSize: 16,
          fontWeight: '600',
          color: isDark ? '#ffffff' : '#000000',
        }}
        text2Style={{
          fontSize: 14,
          color: isDark ? '#d1d5db' : '#6b7280',
        }}
      />
    ),
    error: (props: any) => (
      <ErrorToast
        {...props}
        style={{
          borderLeftColor: '#ef4444',
          backgroundColor: isDark ? '#1f2937' : '#ffffff',
        }}
        contentContainerStyle={{ paddingHorizontal: 15 }}
        text1Style={{
          fontSize: 16,
          fontWeight: '600',
          color: isDark ? '#ffffff' : '#000000',
        }}
        text2Style={{
          fontSize: 14,
          color: isDark ? '#d1d5db' : '#6b7280',
        }}
      />
    ),
    info: (props: any) => (
      <BaseToast
        {...props}
        style={{
          borderLeftColor: '#3b82f6',
          backgroundColor: isDark ? '#1f2937' : '#ffffff',
        }}
        contentContainerStyle={{ paddingHorizontal: 15 }}
        text1Style={{
          fontSize: 16,
          fontWeight: '600',
          color: isDark ? '#ffffff' : '#000000',
        }}
        text2Style={{
          fontSize: 14,
          color: isDark ? '#d1d5db' : '#6b7280',
        }}
      />
    ),
  };

  // Configure notification handler (how they appear when app is foregrounded)
  useEffect(() => {
    console.log('[Navigation] Configuring notification handler');
    configureNotificationHandler();
  }, []);

  // Set up notification tap listener
  useEffect(() => {
    console.log('[Navigation] Setting up notification tap listener with navigationRef:', navigationRef);
    const cleanup = setupNotificationResponseListener(navigationRef);
    return () => {
      console.log('[Navigation] Cleaning up notification listener');
      cleanup();
    };
  }, []);


  const [session, setSession] = useState<Session | null>(null);
  const [loadingSession, setLoadingSession] = useState(true);

  const [checkingProfile, setCheckingProfile] = useState(false);
  const [needsOnboarding, setNeedsOnboarding] = useState(false);

  useEffect(() => {
    let mounted = true;

    supabase.auth.getSession().then(({ data }) => {
      if (!mounted) return;
      setSession(data.session ?? null);
      setLoadingSession(false);
    });

    const { data: sub } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession);
    });

    return () => {
      mounted = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    async function check() {
      if (!session) { setNeedsOnboarding(false); return; }
      setCheckingProfile(true);
      try {
        const { data: { user } } = await supabase.auth.getUser();
        if (!user) { setNeedsOnboarding(false); return; }

        const { data: prof } = await supabase
          .from('profiles')
          .select('onboarding_done')
          .eq('id', user.id)
          .maybeSingle();

        const done = !!prof?.onboarding_done;
        if (!cancelled) setNeedsOnboarding(!done);
      } finally {
        if (!cancelled) setCheckingProfile(false);
      }
    }
    check();
    return () => { cancelled = true; };
  }, [session]);

  if (loadingSession || (session && checkingProfile)) {
    return (
      <NavigationContainer theme={theme}>
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: theme.colors.background }}>
          <ActivityIndicator />
        </View>
      </NavigationContainer>
    );
  }

  const initialRoute = !session ? 'Auth' : (needsOnboarding ? 'Onboarding' : 'Home');

  return (
    <>
    <NavigationContainer ref={navigationRef} theme={theme}>
      <Stack.Navigator
          initialRouteName={initialRoute}
          key={initialRoute}
          screenOptions={{
            statusBarTranslucent: false,
            statusBarColor: theme.colors.card,
            statusBarStyle: colorScheme === 'dark' ? 'light' : 'dark',
            headerTopInsetEnabled: true,
            headerStyle: { backgroundColor: theme.colors.card },
            contentStyle: { backgroundColor: theme.colors.background },
          }}
        >
        {!session ? (
          <Stack.Screen name="Auth" component={AuthScreen} options={{ headerShown: false }} />
        ) : (
          <>
            <Stack.Screen name="Onboarding" component={OnboardingScreen} options={{ headerShown: false }} />
            <Stack.Screen name="Home" component={Tabs} options={{ headerShown: false }} />

            <Stack.Screen name="EventDetail" component={EventDetailScreen} options={{ title: 'Event', headerShown: false}} />
            <Stack.Screen name="CreateEvent" component={CreateEventScreen} options={{ title: 'Create Event', headerShown: false }} />
            <Stack.Screen name="JoinEvent" component={JoinEventScreen} options={{ title: 'Join Event', headerShown: false }} />
            <Stack.Screen name="EditEvent" component={EditEventScreen} options={{ title: 'Edit Event', headerShown: false  }} />
            <Stack.Screen name="ListDetail" component={ListDetailScreen} options={{ title: 'List', headerShown: false }} />
            <Stack.Screen name="AddItem" component={AddItemScreen} options={{ title: 'Add Item', headerShown: false }} />
            <Stack.Screen name="CreateList" component={CreateListScreen} options={{ title: 'Create List', headerShown: false }} />
            <Stack.Screen name="EditList" component={EditListScreen} options={{ title: 'Edit List', headerShown: false }} />
            <Stack.Screen name="EditItem" component={EditItemScreen} options={{ title: 'Edit Item', headerShown: false }} />
          </>
        )}
      </Stack.Navigator>
    </NavigationContainer>
    <Toast config={toastConfig} />
  </>
  );
}

/** Export a root that WRAPS everything in SettingsProvider */
export default function RootNavigator() {
  return (
    <SafeAreaProvider>
      <SettingsProvider>
        <InnerNavigator />
      </SettingsProvider>
    </SafeAreaProvider>
  );
}

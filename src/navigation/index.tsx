// src/navigation/index.tsx
import React, { useEffect, useState } from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { ActivityIndicator, View } from 'react-native';
import { Session } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';

import AuthScreen from '../screens/AuthScreen';
import EventListScreen from '../screens/EventListScreen';
import EventDetailScreen from '../screens/EventDetailScreen';
import CreateEventScreen from '../screens/CreateEventScreen';
import JoinEventScreen from '../screens/JoinEventScreen';
import ListDetailScreen from '../screens/ListDetailScreen';
import AddItemScreen from '../screens/AddItemScreen';
import CreateListScreen from '../screens/CreateListScreen';
import ProfileScreen from '../screens/ProfileScreen';
import EditEventScreen from '../screens/EditEventScreen';
import FancyTabBar from '../components/FancyTabBar';
import OnboardingScreen from '../screens/OnboardingScreen';
import AllListsScreen from '../screens/AllListsScreen';
import MyClaimsScreen from '../screens/MyClaimsScreen';

const Stack = createNativeStackNavigator();
const Tab = createBottomTabNavigator();

function Tabs() {
  return (
    <Tab.Navigator
      screenOptions={{
        headerShown: false,
        tabBarHideOnKeyboard: true, // ← NEW
      }}
      tabBar={(p) => <FancyTabBar {...p} />}
    >
      <Tab.Screen name="Events" component={EventListScreen} />
      <Tab.Screen name="Lists" component={AllListsScreen} />
      <Tab.Screen name="Claimed" component={MyClaimsScreen} />
      <Tab.Screen name="Profile" component={ProfileScreen} />
    </Tab.Navigator>
  );
}

export default function RootNavigator() {
  const [session, setSession] = useState<Session | null>(null);
  const [loadingSession, setLoadingSession] = useState(true);

  // NEW: onboarding flag
  const [checkingProfile, setCheckingProfile] = useState(false);
  const [needsOnboarding, setNeedsOnboarding] = useState(false);

  // Load session once
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

    return () => { mounted = false; sub.subscription.unsubscribe(); };
  }, []);

  // When signed in, check profile.onboarding_done
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

        // If profile row missing, treat as needs onboarding
        const done = !!prof?.onboarding_done;
        if (!cancelled) setNeedsOnboarding(!done);
      } finally {
        if (!cancelled) setCheckingProfile(false);
      }
    }
    check();
    return () => { cancelled = true; };
  }, [session]);

  // Loading gate
  if (loadingSession || (session && checkingProfile)) {
    return (
      <NavigationContainer>
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
          <ActivityIndicator />
        </View>
      </NavigationContainer>
    );
  }

  // Choose initial route
  const initialRoute = !session ? 'Auth' : (needsOnboarding ? 'Onboarding' : 'Tabs');

  return (
    <NavigationContainer>
      <Stack.Navigator initialRouteName={initialRoute} key={initialRoute /* force remount when it changes */}>
        {!session ? (
          <Stack.Screen name="Auth" component={AuthScreen} options={{ headerShown: false }} />
        ) : (
          <>
            {/* NEW: Onboarding as the first screen for brand-new users */}
            <Stack.Screen
              name="Onboarding"
              component={OnboardingScreen}
              options={{ headerShown: false }}
            />

            {/* App tabs and detail screens */}
            <Stack.Screen name="Tabs" component={Tabs} options={{ headerShown: false }} />

            <Stack.Screen name="EventDetail" component={EventDetailScreen} options={{ title: 'Event' }} />
            <Stack.Screen name="CreateEvent" component={CreateEventScreen} options={{ title: 'Create Event' }} />
            <Stack.Screen name="JoinEvent" component={JoinEventScreen} options={{ title: 'Join Event' }} />
            <Stack.Screen name="EditEvent" component={EditEventScreen} options={{ title: 'Edit Event' }} />
            <Stack.Screen name="ListDetail" component={ListDetailScreen} options={{ title: 'List' }} />
            <Stack.Screen name="AddItem" component={AddItemScreen} options={{ title: 'Add Item' }} />
            <Stack.Screen name="CreateList" component={CreateListScreen} options={{ title: 'Create List' }} />

          </>
        )}
      </Stack.Navigator>
    </NavigationContainer>
  );
}

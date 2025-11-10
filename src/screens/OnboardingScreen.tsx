// src/screens/OnboardingScreen.tsx
import React, { useMemo, useRef, useState } from 'react';
import { View, Text, Pressable, ScrollView, Dimensions, NativeScrollEvent, NativeSyntheticEvent, useWindowDimensions } from 'react-native';
import { supabase } from '../lib/supabase';
import { LinearGradient } from 'expo-linear-gradient';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';

/** ---------- Tiny UI primitives to draw mock screens ---------- */
function Card({ children, style = {} }: { children: React.ReactNode; style?: any }) {
  return (
    <View
      style={[{
        backgroundColor: 'white',
        borderRadius: 16,
        padding: 16,
        marginHorizontal: 16,
        shadowColor: '#000', shadowOpacity: 0.06, shadowRadius: 8, shadowOffset: { width: 0, height: 2 }, elevation: 2
      }, style]}
    >
      {children}
    </View>
  );
}

function SectionTitle({ children }: { children: React.ReactNode }) {
  return <Text style={{ fontSize: 16, fontWeight: '800', marginBottom: 8 }}>{children}</Text>;
}

function Label({ children }: { children: React.ReactNode }) {
  return <Text style={{ fontSize: 12, fontWeight: '700', opacity: 0.7, marginBottom: 6 }}>{children}</Text>;
}

function FakeInput({ placeholder, narrow = false }: { placeholder: string; narrow?: boolean }) {
  return (
    <View style={{
      borderWidth: 1, borderColor: '#e5e7eb', borderRadius: 10,
      paddingVertical: 10, paddingHorizontal: 12, backgroundColor: '#f9fafb',
      width: narrow ? '60%' : '100%'
    }}>
      <Text style={{ color: '#9aa3af' }}>{placeholder}</Text>
    </View>
  );
}

function FakeButton({
  title,
  tone = 'primary',
  style = {} as any,
}: {
  title: string;
  tone?: 'primary' | 'danger' | 'muted' | 'success' | 'link';
  style?: any;
}) {
  // colors
  const bg =
    tone === 'primary' ? '#2e95f1' :
      tone === 'danger' ? '#d9534f' :
        tone === 'success' ? '#21c36b' :
          tone === 'muted' ? '#eef2f7' :
            'transparent';           // link = transparent

  const fg =
    tone === 'link' ? '#2e95f1' :
      tone === 'muted' ? '#1f2937' : 'white';

  return (
    <View
      style={[
        {
          backgroundColor: bg,
          paddingVertical: tone === 'link' ? 0 : 10,   // tighter for link
          paddingHorizontal: tone === 'link' ? 0 : 16,
          borderRadius: tone === 'link' ? 0 : 999,
        },
        style,
      ]}
    >
      <Text
        style={{
          color: fg,
          fontWeight: tone === 'link' ? '600' : '800', // match Events screen text buttons
          fontSize: 14,
        }}
      >
        {title}
      </Text>
    </View>
  );
}


function Chip({ text }: { text: string }) {
  return (
    <View style={{ backgroundColor: '#eef2f7', paddingHorizontal: 10, paddingVertical: 6, borderRadius: 999, marginRight: 8, marginBottom: 8 }}>
      <Text style={{ fontWeight: '700', color: '#1f2937' }}>{text}</Text>
    </View>
  );
}

function Pill({ text, tone = 'gray' }: { text: string; tone?: 'gray' | 'green' | 'red' }) {
  const bg = tone === 'green' ? '#e9f8ec' : tone === 'red' ? '#fde8e8' : '#edf1f5';
  const fg = tone === 'green' ? '#1f9e4a' : tone === 'red' ? '#c0392b' : '#63707e';
  return (
    <View style={{ backgroundColor: bg, paddingHorizontal: 8, paddingVertical: 4, borderRadius: 999 }}>
      <Text style={{ color: fg, fontSize: 12, fontWeight: '700' }}>{text}</Text>
    </View>
  );
}

function FormButton({
  title,
  tone = 'primary',
  style = {} as any,
}: {
  title: string;
  tone?: 'primary' | 'muted';
  style?: any;
}) {
  const bg = tone === 'primary' ? '#2e95f1' : '#eef2f7';
  const fg = tone === 'primary' ? 'white' : '#1f2937';

  return (
    <View
      style={[{
        height: 44,
        borderRadius: 8,            // not pill
        backgroundColor: bg,
        justifyContent: 'center',
        alignItems: 'center',
        width: '100%',              // full-width like RN <Button/>
      }, style]}
    >
      <Text style={{ color: fg, fontWeight: '800', textAlign: 'center' }}>
        {title}
      </Text>
    </View>
  );
}

function MiniStat({ title, value }: { title: string; value: number | string }) {
  return (
    <View
      style={{
        flex: 1,
        backgroundColor: 'white',
        paddingVertical: 12,
        paddingHorizontal: 4,
        borderRadius: 14,
        alignItems: 'center',
        justifyContent: 'center',
        minHeight: 70,
      }}
    >
      <Text style={{ fontSize: 20, fontWeight: '800' }}>{String(value)}</Text>
      <Text style={{ marginTop: 4, opacity: 0.7, fontSize: 10, textAlign: 'center', lineHeight: 13 }}>{title}</Text>
    </View>
  );
}

/** ---------- Mock "screens" for the tour ---------- */
function CreateEventMock({ isSmall = false }: { isSmall?: boolean }) {
  const spacing = isSmall ? 6 : 10;
  const finalSpacing = isSmall ? 8 : 14;

  return (
    <Card>
      <SectionTitle>Create Event</SectionTitle>
      <Label>Title</Label>
      <FakeInput placeholder="e.g. Bob's Birthday" />
      <View style={{ height: spacing }} />
      <Label>Description (optional)</Label>
      <FakeInput placeholder="Add details for invitees" />
      <View style={{ height: spacing }} />
      <Label>Date</Label>
      <FakeInput placeholder="Wed, Dec 18, 2025" narrow />
      <View style={{ height: spacing }} />
      <Label>Recurs</Label>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', marginHorizontal: -4, marginTop: 2 }}>
        <FakeButton title="None" tone="muted" style={{ margin: 4 }} />
        <FakeButton title="Weekly" tone="muted" style={{ margin: 4 }} />
        <FakeButton title="Monthly" tone="muted" style={{ margin: 4 }} />
        <FakeButton title="Yearly" tone="muted" style={{ margin: 4 }} />
      </View>
      <View style={{ height: finalSpacing }} />
      <FormButton title="Create" />
    </Card>
  );
}

function CreateListMock() {
  return (
    <Card>
      <SectionTitle>Create List</SectionTitle>
      <Label>List name</Label>
      <FakeInput placeholder="e.g. Gifts for Bob" />
      <View style={{ height: 10 }} />
      <Label>Recipients</Label>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
        <Chip text="Bob" />
        <Chip text="Alice" />
      </View>
      <View style={{ height: 10 }} />
      <Label>Visibility</Label>
      <View style={{ flexDirection: 'row', gap: 8, flexWrap: 'wrap' }}>
        <FakeButton title="Everyone" tone="muted" />
        <FakeButton title="Selected people" tone="muted" />
      </View>
      <View style={{ height: 14 }} />
      <FormButton title="Create list" />
    </Card>
  );
}

function ListDetailMock() {
  return (
    <Card>
      <SectionTitle>List Detail</SectionTitle>
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
        <Text style={{ fontSize: 16, fontWeight: '800' }}>Gifts for Bob</Text>
        <FakeButton title="Add Item" />
      </View>

      {/* Item card */}
      <View style={{
        marginTop: 12, borderWidth: 1, borderColor: '#eef2f7', borderRadius: 12, padding: 12,
        shadowColor: '#000', shadowOpacity: 0.04, shadowRadius: 6, shadowOffset: { width: 0, height: 2 }
      }}>
        <Text style={{ fontWeight: '700' }}>Noise-canceling headphones</Text>
        <Text style={{ color: '#2e95f1', marginTop: 2 }}>https://example.com/headphones</Text>
        <Text style={{ marginTop: 2 }}>$149.99</Text>
        <View style={{ marginTop: 10, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
          <Text style={{ opacity: 0.7 }}>Claimed by: Alice</Text>
          <FakeButton title="Unclaim" tone="danger" />
        </View>
      </View>

      {/* Item card 2 */}
      <View style={{
        marginTop: 12, borderWidth: 1, borderColor: '#eef2f7', borderRadius: 12, padding: 12,
        shadowColor: '#000', shadowOpacity: 0.04, shadowRadius: 6, shadowOffset: { width: 0, height: 2 }
      }}>
        <Text style={{ fontWeight: '700' }}>Cookbook</Text>
        <Text style={{ opacity: 0.7, marginTop: 2 }}>Not claimed yet</Text>
        <View style={{ marginTop: 10, alignItems: 'flex-end' }}>
          <FakeButton title="Claim" tone="success" />
        </View>
      </View>
    </Card>
  );
}

function JoinEventMock() {
  return (
    <Card>
      <SectionTitle>Join Event</SectionTitle>
      <Label>Enter join code</Label>
      <FakeInput placeholder="e.g. 7G4K-MQ" narrow />
      <View style={{ height: 12 }} />
      <FakeButton title="Join" />
    </Card>
  );
}

function EventCardMock() {
  return (
    <Card style={{ padding: 14 }}>
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
        <Text style={{ fontSize: 16, fontWeight: '700' }}>Bob's Birthday</Text>
        <Pill text="in 12 days" />
      </View>
      <Text style={{ marginTop: 2, opacity: 0.7 }}>Tue, Nov 18, 2025</Text>
      <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 12, justifyContent: 'space-between' }}>
        <Text style={{ opacity: 0.7 }}>8 members</Text>
        <Text style={{ fontWeight: '600', color: '#63707e' }}>3/12 claimed</Text>
      </View>
    </Card>
  );
}

function MyClaimsMock({ isSmall = false }: { isSmall?: boolean }) {
  const itemPadding = isSmall ? 12 : 14;
  const titleSize = isSmall ? 15 : 16;
  const subtitleSize = isSmall ? 12 : 13;
  const buttonPadding = isSmall ? 5 : 6;
  const buttonTextSize = isSmall ? 11 : 12;

  return (
    <Card style={{ padding: 0 }}>
      {/* Header - matching actual screen */}
      <View style={{ padding: itemPadding, backgroundColor: '#f9fafb', borderTopLeftRadius: 16, borderTopRightRadius: 16 }}>
        <Text style={{ fontSize: isSmall ? 15 : 16, fontWeight: '700' }}>My claimed items</Text>
      </View>

      {/* Claimed item 1 - Not purchased (green button) */}
      <View style={{ padding: itemPadding, borderBottomWidth: 1, borderBottomColor: '#eef2f7' }}>
        <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <View style={{ flex: 1, paddingRight: 8 }}>
            <Text style={{ fontWeight: '700', fontSize: titleSize }}>Noise-canceling headphones</Text>
            <Text style={{ opacity: 0.75, fontSize: subtitleSize, marginTop: 4 }}>Bob's Birthday · Gifts for Bob</Text>
          </View>
          <Pressable
            style={{
              paddingVertical: buttonPadding,
              paddingHorizontal: isSmall ? 10 : 12,
              borderRadius: 999,
              backgroundColor: '#e9f8ec',
              borderWidth: 1,
              borderColor: '#bce9cb',
              alignSelf: 'flex-start',
            }}
          >
            <Text style={{ fontWeight: '800', fontSize: buttonTextSize, color: '#1f9e4a' }}>
              Mark purchased
            </Text>
          </Pressable>
        </View>
      </View>

      {/* Claimed item 2 - Purchased (red button) */}
      <View style={{ padding: itemPadding, borderBottomWidth: 1, borderBottomColor: '#eef2f7' }}>
        <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <View style={{ flex: 1, paddingRight: 8 }}>
            <Text style={{ fontWeight: '700', fontSize: titleSize }}>Cookbook</Text>
            <Text style={{ opacity: 0.75, fontSize: subtitleSize, marginTop: 4 }}>Bob's Birthday · Gifts for Bob</Text>
          </View>
          <Pressable
            style={{
              paddingVertical: buttonPadding,
              paddingHorizontal: isSmall ? 10 : 12,
              borderRadius: 999,
              backgroundColor: '#fde8e8',
              borderWidth: 1,
              borderColor: '#f8c7c7',
              alignSelf: 'flex-start',
            }}
          >
            <Text style={{ fontWeight: '800', fontSize: buttonTextSize, color: '#c0392b' }}>
              Mark not purchased
            </Text>
          </Pressable>
        </View>
      </View>

      {/* Claimed item 3 - Not purchased (green button) */}
      <View style={{ padding: itemPadding }}>
        <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <View style={{ flex: 1, paddingRight: 8 }}>
            <Text style={{ fontWeight: '700', fontSize: titleSize }}>Board game set</Text>
            <Text style={{ opacity: 0.75, fontSize: subtitleSize, marginTop: 4 }}>Family Xmas · Games</Text>
          </View>
          <Pressable
            style={{
              paddingVertical: buttonPadding,
              paddingHorizontal: isSmall ? 10 : 12,
              borderRadius: 999,
              backgroundColor: '#e9f8ec',
              borderWidth: 1,
              borderColor: '#bce9cb',
              alignSelf: 'flex-start',
            }}
          >
            <Text style={{ fontWeight: '800', fontSize: buttonTextSize, color: '#1f9e4a' }}>
              Mark purchased
            </Text>
          </Pressable>
        </View>
      </View>
    </Card>
  );
}

/** ---------- NEW: “Getting Started” visual with Create indicator ---------- */
function GettingStartedMock() {
  return (
    <Card style={{ padding: 0 }}>
      {/* Real gradient header to match the app */}
      <LinearGradient
        colors={['#21c36b', '#2e95f1']}
        start={{ x: 0, y: 0 }}
        end={{ x: 1, y: 0 }}
        style={{
          paddingTop: 20,
          paddingBottom: 12,
          paddingHorizontal: 16,
          borderTopLeftRadius: 16,
          borderTopRightRadius: 16,
        }}
      >
        <Text style={{ color: 'white', fontSize: 18, fontWeight: '800' }}>Welcome back</Text>
        <Text style={{ color: 'white', opacity: 0.9 }}>Coordinate gifts with ease</Text>

        {/* NEW: mini stat cards row (mock numbers) */}
        <View style={{ flexDirection: 'row', gap: 12, marginTop: 12 }}>
          <MiniStat title="Active Events" value={2} />
          <MiniStat title="Items Claimed" value={5} />
          <MiniStat title="To Purchase" value={3} />
        </View>
      </LinearGradient>

      {/* The Events toolbar row with Join + Create (link-style to match real UI) */}
      <View
        style={{
          paddingHorizontal: 16,
          paddingVertical: 12,
          flexDirection: 'row',
          justifyContent: 'space-between',
          alignItems: 'center',
        }}
      >
        <Text style={{ fontSize: 16, fontWeight: '700' }}>Your Events</Text>
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          <FakeButton title="Join" tone="link" style={{ marginRight: 16 }} />
          <View style={{ position: 'relative' }}>
            <FakeButton title="Create" tone="link" />
          </View>
        </View>
      </View>

      {/* Example event cards (unchanged) */}
      <View style={{ paddingHorizontal: 16, paddingBottom: 16 }}>
        <Card style={{ padding: 14, marginHorizontal: 0 }}>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
            <Text style={{ fontSize: 16, fontWeight: '700' }}>Bob’s Birthday</Text>
            <Pill text="in 12 days" />
          </View>
          <Text style={{ marginTop: 2, opacity: 0.7 }}>Tue, Nov 18, 2025</Text>
          <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 12, justifyContent: 'space-between' }}>
            <Text style={{ opacity: 0.7 }}>8 members</Text>
            <Text style={{ fontWeight: '600', color: '#63707e' }}>3/12 claimed</Text>
          </View>
        </Card>

        <Card style={{ padding: 14, marginTop: 10, marginHorizontal: 0 }}>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
            <Text style={{ fontSize: 16, fontWeight: '700' }}>Family Xmas</Text>
            <Pill text="in 34 days" />
          </View>
          <Text style={{ marginTop: 2, opacity: 0.7 }}>Sun, Dec 22, 2025</Text>
          <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 12, justifyContent: 'space-between' }}>
            <Text style={{ opacity: 0.7 }}>12 members</Text>
            <Text style={{ fontWeight: '600', color: '#63707e' }}>—</Text>
          </View>
        </Card>
      </View>
    </Card>
  );
}

/** ---------- NEW: Purchase Reminder Mock (Push Notification) ---------- */
function PurchaseReminderMock() {
  return (
    <View style={{ alignItems: 'center' }}>
      {/* Mock phone notification */}
      <View
        style={{
          backgroundColor: 'white',
          borderRadius: 16,
          padding: 16,
          marginHorizontal: 16,
          width: '100%',
          maxWidth: 380,
          shadowColor: '#000',
          shadowOpacity: 0.15,
          shadowRadius: 20,
          shadowOffset: { width: 0, height: 4 },
          elevation: 8,
        }}
      >
        {/* App header */}
        <View style={{ flexDirection: 'row', alignItems: 'center', marginBottom: 12 }}>
          <View
            style={{
              width: 28,
              height: 28,
              borderRadius: 8,
              backgroundColor: '#2e95f1',
              alignItems: 'center',
              justifyContent: 'center',
              marginRight: 10,
            }}
          >
            <Text style={{ color: 'white', fontWeight: '800', fontSize: 16 }}>G</Text>
          </View>
          <View style={{ flex: 1 }}>
            <Text style={{ fontSize: 12, fontWeight: '700', opacity: 0.7 }}>GiftCircles</Text>
            <Text style={{ fontSize: 11, opacity: 0.5 }}>now</Text>
          </View>
        </View>

        {/* Notification content */}
        <Text style={{ fontSize: 16, fontWeight: '800', marginBottom: 6 }}>
          Bob's Birthday is in 3 days! 🎂
        </Text>
        <Text style={{ fontSize: 14, opacity: 0.8 }}>
          You have 2 items to purchase. Don't forget!
        </Text>

        {/* Premium badge */}
        <View style={{ marginTop: 12, alignSelf: 'flex-start' }}>
          <View
            style={{
              backgroundColor: '#fef3c7',
              paddingHorizontal: 10,
              paddingVertical: 4,
              borderRadius: 999,
              borderWidth: 1,
              borderColor: '#fbbf24',
            }}
          >
            <Text style={{ fontSize: 11, fontWeight: '800', color: '#92400e' }}>✨ PREMIUM</Text>
          </View>
        </View>
      </View>
    </View>
  );
}

/** ---------- NEW: Daily Digest Mock (Push Notification) ---------- */
function DailyDigestMock() {
  return (
    <View style={{ alignItems: 'center' }}>
      {/* Mock phone notification */}
      <View
        style={{
          backgroundColor: 'white',
          borderRadius: 16,
          padding: 16,
          marginHorizontal: 16,
          width: '100%',
          maxWidth: 380,
          shadowColor: '#000',
          shadowOpacity: 0.15,
          shadowRadius: 20,
          shadowOffset: { width: 0, height: 4 },
          elevation: 8,
        }}
      >
        {/* App header */}
        <View style={{ flexDirection: 'row', alignItems: 'center', marginBottom: 12 }}>
          <View
            style={{
              width: 28,
              height: 28,
              borderRadius: 8,
              backgroundColor: '#21c36b',
              alignItems: 'center',
              justifyContent: 'center',
              marginRight: 10,
            }}
          >
            <Text style={{ color: 'white', fontWeight: '800', fontSize: 16 }}>G</Text>
          </View>
          <View style={{ flex: 1 }}>
            <Text style={{ fontSize: 12, fontWeight: '700', opacity: 0.7 }}>GiftCircles Digest</Text>
            <Text style={{ fontSize: 11, opacity: 0.5 }}>8:00 AM</Text>
          </View>
        </View>

        {/* Notification content */}
        <Text style={{ fontSize: 16, fontWeight: '800', marginBottom: 8 }}>
          Your Weekly Summary 📊
        </Text>

        {/* Stats */}
        <View style={{ backgroundColor: '#f9fafb', borderRadius: 12, padding: 12, marginBottom: 8 }}>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', marginBottom: 6 }}>
            <Text style={{ fontSize: 13, opacity: 0.7 }}>New items added:</Text>
            <Text style={{ fontSize: 13, fontWeight: '700' }}>5</Text>
          </View>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', marginBottom: 6 }}>
            <Text style={{ fontSize: 13, opacity: 0.7 }}>Items claimed:</Text>
            <Text style={{ fontSize: 13, fontWeight: '700' }}>8</Text>
          </View>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
            <Text style={{ fontSize: 13, opacity: 0.7 }}>Upcoming events:</Text>
            <Text style={{ fontSize: 13, fontWeight: '700' }}>2</Text>
          </View>
        </View>

        <Text style={{ fontSize: 13, opacity: 0.7 }}>
          Tap to view details in the app
        </Text>

        {/* Premium badge */}
        <View style={{ marginTop: 12, alignSelf: 'flex-start' }}>
          <View
            style={{
              backgroundColor: '#fef3c7',
              paddingHorizontal: 10,
              paddingVertical: 4,
              borderRadius: 999,
              borderWidth: 1,
              borderColor: '#fbbf24',
            }}
          >
            <Text style={{ fontSize: 11, fontWeight: '800', color: '#92400e' }}>✨ PREMIUM</Text>
          </View>
        </View>
      </View>
    </View>
  );
}


/** ---------- Slides data ---------- */
type Slide =
  | { kind: 'mock'; title: string; caption: string; render: () => React.ReactElement; cta?: { label: string; onPress: () => void } };

export default function OnboardingScreen({ navigation }: any) {
  const { t } = useTranslation();
  const scrollRef = useRef<ScrollView>(null);
  const [index, setIndex] = useState(0);
  const insets = useSafeAreaInsets();
  const { width, height } = useWindowDimensions();
  const isSmallScreen = height < 700; // Detect small screens

  const finish = async (navigateTo?: { name: string; params?: any }) => {
    try {
      await supabase.rpc('set_onboarding_done', { p_done: true });
    } catch {
      // ignore; keep UX flowing
    }
    if (navigateTo) {
      navigation.reset({ index: 0, routes: [{ name: 'Home' }, { name: navigateTo.name as any, params: navigateTo.params }] });
    } else {
      navigation.reset({ index: 0, routes: [{ name: 'Home' }] });
    }
  };

  const SLIDES: Slide[] = [
    {
      kind: 'mock',
      title: t('onboarding.slides.gettingStarted.title'),
      caption: t('onboarding.slides.gettingStarted.caption'),
      render: () => <GettingStartedMock />,
    },
    {
      kind: 'mock',
      title: t('onboarding.slides.createEvent.title'),
      caption: t('onboarding.slides.createEvent.caption'),
      render: () => <CreateEventMock isSmall={isSmallScreen} />,
    },
    {
      kind: 'mock',
      title: t('onboarding.slides.addList.title'),
      caption: t('onboarding.slides.addList.caption'),
      render: () => <CreateListMock />,
    },
    {
      kind: 'mock',
      title: t('onboarding.slides.claimItems.title'),
      caption: t('onboarding.slides.claimItems.caption'),
      render: () => <ListDetailMock />,
    },
    {
      kind: 'mock',
      title: t('onboarding.slides.purchaseReminders.title'),
      caption: t('onboarding.slides.purchaseReminders.caption'),
      render: () => <PurchaseReminderMock />,
    },
    {
      kind: 'mock',
      title: t('onboarding.slides.dailyDigest.title'),
      caption: t('onboarding.slides.dailyDigest.caption'),
      render: () => <DailyDigestMock />,
    },
    {
      kind: 'mock',
      title: t('onboarding.slides.myClaims.title'),
      caption: t('onboarding.slides.myClaims.caption'),
      render: () => <MyClaimsMock isSmall={isSmallScreen} />,
    },
  ];

  const canNext = index < SLIDES.length - 1;

  const onScroll = (e: NativeSyntheticEvent<NativeScrollEvent>) => {
    const i = Math.round(e.nativeEvent.contentOffset.x / width);
    if (i !== index) setIndex(i);
  };

  const goNext = () => {
    if (canNext) {
      scrollRef.current?.scrollTo({ x: (index + 1) * width, animated: true });
      setIndex(index + 1);
    }
  };

  const slide = SLIDES[index];

  const skipOrFinishLabel = useMemo(() => (canNext ? t('onboarding.actions.skip') : t('onboarding.actions.finish')), [canNext, t]);

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: '#0ea5e9' }} edges={['top', 'left', 'right']}>
      {/* Header - Responsive padding */}
      <View style={{ paddingTop: isSmallScreen ? 32 : 64, paddingHorizontal: 20 }}>
        <Text style={{ color: 'white', fontSize: isSmallScreen ? 22 : 28, fontWeight: '800' }}>
          {slide.title}
        </Text>
      </View>

      {/* Slides - Make scrollable with flex */}
      <ScrollView
        ref={scrollRef}
        horizontal
        pagingEnabled
        showsHorizontalScrollIndicator={false}
        onScroll={onScroll}
        scrollEventThrottle={16}
        style={{ marginTop: isSmallScreen ? 12 : 20, flex: 1 }}
      >
        {SLIDES.map((s, i) => (
          <View key={i} style={{ width, paddingHorizontal: 20 }}>
            <ScrollView
              showsVerticalScrollIndicator={false}
              contentContainerStyle={{ paddingBottom: isSmallScreen ? 80 : 20 }}
            >
              {s.render()}
              <Text style={{
                color: 'white',
                marginTop: 12,
                fontSize: isSmallScreen ? 13 : 14,
                lineHeight: isSmallScreen ? 18 : 20,
              }}>
                {s.caption}
              </Text>
            </ScrollView>
          </View>
        ))}
      </ScrollView>

      {/* Dots */}
      <View style={{ flexDirection: 'row', justifyContent: 'center', alignItems: 'center', marginTop: isSmallScreen ? 8 : 16 }}>
        {SLIDES.map((_, i) => (
          <View
            key={i}
            style={{
              width: 8, height: 8, borderRadius: 4,
              backgroundColor: i === index ? 'white' : 'rgba(255,255,255,0.5)',
              marginHorizontal: 4
            }}
          />
        ))}
      </View>

      {/* Actions */}
      <View style={{
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        paddingHorizontal: 20,
        marginTop: isSmallScreen ? 12 : 20,
        paddingBottom: Math.max(insets.bottom + 12, 32)
      }}>
        <Pressable onPress={() => finish()} style={{ paddingVertical: 12, paddingHorizontal: 16 }}>
          <Text style={{ color: 'white', fontWeight: '700', fontSize: isSmallScreen ? 14 : 16 }}>
            {skipOrFinishLabel}
          </Text>
        </Pressable>

        {/* Primary action: Next OR contextual CTA */}
        {canNext ? (
          SLIDES[index]['cta'] ? (
            <Pressable
              onPress={() => (SLIDES[index] as any).cta.onPress()}
              style={{ backgroundColor: 'white', paddingVertical: 12, paddingHorizontal: 20, borderRadius: 999 }}
            >
              <Text style={{ color: '#0ea5e9', fontWeight: '800', fontSize: isSmallScreen ? 14 : 16 }}>
                {(SLIDES[index] as any).cta.label}
              </Text>
            </Pressable>
          ) : (
            <Pressable
              onPress={goNext}
              style={{ backgroundColor: 'white', paddingVertical: 12, paddingHorizontal: 20, borderRadius: 999 }}
            >
              <Text style={{ color: '#0ea5e9', fontWeight: '800', fontSize: isSmallScreen ? 14 : 16 }}>
                {t('onboarding.actions.next')}
              </Text>
            </Pressable>
          )
        ) : (
          <Pressable
            onPress={() => finish()}
            style={{ backgroundColor: 'white', paddingVertical: 12, paddingHorizontal: 20, borderRadius: 999 }}
          >
            <Text style={{ color: '#0ea5e9', fontWeight: '800', fontSize: isSmallScreen ? 13 : 16 }}>
              {t('onboarding.actions.startUsing')}
            </Text>
          </Pressable>
        )}
      </View>
    </SafeAreaView>
  );
}

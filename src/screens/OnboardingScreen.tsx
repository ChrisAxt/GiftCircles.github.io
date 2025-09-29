// src/screens/OnboardingScreen.tsx
import React, { useMemo, useRef, useState } from 'react';
import { View, Text, Pressable, ScrollView, Dimensions, NativeScrollEvent, NativeSyntheticEvent } from 'react-native';
import { supabase } from '../lib/supabase';
import { LinearGradient } from 'expo-linear-gradient';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

const { width } = Dimensions.get('window');

/** ---------- Tiny UI primitives to draw mock screens ---------- */
function Card({ children, style = {} as any }) {
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
    tone === 'danger'  ? '#d9534f' :
    tone === 'success' ? '#21c36b' :
    tone === 'muted'   ? '#eef2f7' :
                         'transparent';           // link = transparent

  const fg =
    tone === 'link'   ? '#2e95f1' :
    tone === 'muted'  ? '#1f2937' : 'white';

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

function Pill({ text, tone = 'gray' as 'gray' | 'green' | 'red' }) {
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
        paddingVertical: 14,
        borderRadius: 14,
        alignItems: 'center',
        justifyContent: 'center',
      }}
    >
      <Text style={{ fontSize: 20, fontWeight: '800' }}>{String(value)}</Text>
      <Text style={{ marginTop: 4, opacity: 0.7 }}>{title}</Text>
    </View>
  );
}

/** ---------- Mock “screens” for the tour ---------- */
function CreateEventMock() {
  return (
    <Card>
      <SectionTitle>Create Event</SectionTitle>
      <Label>Title</Label>
      <FakeInput placeholder="e.g. Bob’s Birthday" />
      <View style={{ height: 10 }} />
      <Label>Description (optional)</Label>
      <FakeInput placeholder="Add details for invitees" />
      <View style={{ height: 10 }} />
      <Label>Date</Label>
      <FakeInput placeholder="Wed, Dec 18, 2025" narrow />
      <View style={{ height: 10 }} />
      <Label>Recurs</Label>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', marginHorizontal: -4, marginTop: 2 }}>
        <FakeButton title="None"    tone="muted" style={{ margin: 4 }} />
        <FakeButton title="Weekly"  tone="muted" style={{ margin: 4 }} />
        <FakeButton title="Monthly" tone="muted" style={{ margin: 4 }} />
        <FakeButton title="Yearly"  tone="muted" style={{ margin: 4 }} />
      </View>
      <View style={{ height: 14 }} />
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
        <Text style={{ fontSize: 16, fontWeight: '700' }}>Bob’s Birthday</Text>
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


/** ---------- Slides data ---------- */
type Slide =
  | { kind: 'mock'; title: string; caption: string; render: () => JSX.Element; cta?: { label: string; onPress: () => void } };

export default function OnboardingScreen({ navigation }: any) {
  const scrollRef = useRef<ScrollView>(null);
  const [index, setIndex] = useState(0);
  const insets = useSafeAreaInsets();

  const finish = async (navigateTo?: { name: string; params?: any }) => {
    try {
      await supabase.rpc('set_onboarding_done', { p_done: true });
    } catch {
      // ignore; keep UX flowing
    }
    if (navigateTo) {
      navigation.reset({ index: 0, routes: [{ name: 'Tabs' }, { name: navigateTo.name as any, params: navigateTo.params }] });
    } else {
      navigation.reset({ index: 0, routes: [{ name: 'Tabs' }] });
    }
  };

  const SLIDES: Slide[] = [
    {
      kind: 'mock',
      title: 'Getting Started',
      caption: 'This is your Events screen. Tap the “Create” button (top-right) to make your first event.',
      render: () => <GettingStartedMock />,
    },
    {
      kind: 'mock',
      title: 'Create an Event',
      caption: 'Give your event a title, optionally add a date and recurrence. You can invite others later with a join code.',
      render: () => <CreateEventMock />,
    },
    {
      kind: 'mock',
      title: 'Add a List & Recipients',
      caption: 'Inside an event, create lists for one or more recipients. You can also restrict list visibility to selected people.',
      render: () => <CreateListMock />,
    },
    {
      kind: 'mock',
      title: 'Claim Items (Recipients can’t see!)',
      caption: 'Givers claim an item so others don’t duplicate. Recipients never see who claimed, and claim counts can be hidden from them.',
      render: () => <ListDetailMock />,
    },
    {
      kind: 'mock',
      title: 'Join by Code',
      caption: 'Friends can join your event quickly using a short code you share.',
      render: () => <JoinEventMock />,
    },
    {
      kind: 'mock',
      title: 'Your Events',
      caption: 'Event tiles show the date status and safe claim counts (you won’t see claims on lists where you’re a recipient).',
      render: () => <EventCardMock />,
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

  const skipOrFinishLabel = useMemo(() => (canNext ? 'Skip' : 'Finish'), [canNext]);

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: '#0ea5e9' }} edges={['top', 'left', 'right']}>
      {/* Header */}
      <View style={{ paddingTop: 64, paddingHorizontal: 20 }}>
        <Text style={{ color: 'white', fontSize: 28, fontWeight: '800' }}>
          {slide.title}
        </Text>
        <Text style={{ color: 'white', opacity: 0.9, marginTop: 6 }}>
          Preview of the actual UI you’ll use
        </Text>
      </View>

      {/* Slides */}
      <ScrollView
        ref={scrollRef}
        horizontal
        pagingEnabled
        showsHorizontalScrollIndicator={false}
        onScroll={onScroll}
        scrollEventThrottle={16}
        style={{ marginTop: 20 }}
      >
        {SLIDES.map((s, i) => (
          <View key={i} style={{ width, paddingHorizontal: 20 }}>
            {s.render()}
            <Text style={{ color: 'white', marginTop: 12, marginHorizontal: 20 }}>{s.caption}</Text>
          </View>
        ))}
      </ScrollView>

      {/* Dots */}
      <View style={{ flexDirection: 'row', justifyContent: 'center', alignItems: 'center', marginTop: 16 }}>
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
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 20, marginTop: 20, marginBottom: 32 }}>
        <Pressable onPress={() => finish()} style={{ paddingVertical: 12, paddingHorizontal: 16 }}>
          <Text style={{ color: 'white', fontWeight: '700' }}>{skipOrFinishLabel}</Text>
        </Pressable>

        {/* Primary action: Next OR contextual CTA */}
        {canNext ? (
          SLIDES[index]['cta'] ? (
            <Pressable
              onPress={() => (SLIDES[index] as any).cta.onPress()}
              style={{ backgroundColor: 'white', paddingVertical: 12, paddingHorizontal: 20, borderRadius: 999 }}
            >
              <Text style={{ color: '#0ea5e9', fontWeight: '800' }}>
                {(SLIDES[index] as any).cta.label}
              </Text>
            </Pressable>
          ) : (
            <Pressable
              onPress={goNext}
              style={{ backgroundColor: 'white', paddingVertical: 12, paddingHorizontal: 20, borderRadius: 999 }}
            >
              <Text style={{ color: '#0ea5e9', fontWeight: '800' }}>Next</Text>
            </Pressable>
          )
        ) : (
          <Pressable
            onPress={() => finish()}
            style={{ backgroundColor: 'white', paddingVertical: 12, paddingHorizontal: 20, borderRadius: 999 }}
          >
            <Text style={{ color: '#0ea5e9', fontWeight: '800' }}>Start using GiftCircles</Text>
          </Pressable>
        )}
      </View>
    </SafeAreaView>
  );
}

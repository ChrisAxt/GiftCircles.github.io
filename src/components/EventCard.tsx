// src/components/EventCard.tsx
import React from 'react';
import { View, Text, Pressable } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useTheme } from '@react-navigation/native';
import { formatDateLocalized } from '../utils/date';

// Pretty “Mon, Jan 1, 2026”
function formatDate(iso?: string) {
  if (!iso) return '';
  const d = new Date(iso);
  return d.toLocaleDateString(undefined, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

// Whole-day difference: event_date - today
function daysDiffUTC(aISO: string, bISO: string) {
  const a = new Date(aISO); a.setHours(0, 0, 0, 0);
  const b = new Date(bISO); b.setHours(0, 0, 0, 0);
  const MS = 24 * 60 * 60 * 1000;
  return Math.round((a.getTime() - b.getTime()) / MS);
}

function humanizeDaysLeft(t: (k: string, o?: any) => string, daysLeft: number) {
  if (daysLeft === 0)  return t('eventList.eventCard.today');
  if (daysLeft === 1)  return t('eventList.eventCard.tomorrow');
  if (daysLeft > 1)    return t('eventList.eventCard.inDays',  { count: daysLeft });
  // daysLeft < 0
  return t('eventList.eventCard.daysAgo', { count: Math.abs(daysLeft) });
}

// Small pill
function Pill({ text, tone }: { text: string; tone: 'gray' | 'green' | 'red' }) {
  const { colors } = useTheme();
  let bg = colors.card;
  let fg = colors.text;
  let borderW = 1;
  let borderC = colors.border;

  if (tone === 'green') {
    bg = '#e9f8ec'; fg = '#1f9e4a'; borderW = 0; borderC = 'transparent';
  } else if (tone === 'red') {
    bg = '#fde8e8'; fg = '#c0392b'; borderW = 0; borderC = 'transparent';
  }

  return (
    <View style={{
      backgroundColor: bg,
      paddingHorizontal: 8,
      paddingVertical: 4,
      borderRadius: 999,
      borderWidth: borderW,
      borderColor: borderC,
    }}>
      <Text style={{ color: fg, fontSize: 12, fontWeight: '700', opacity: tone === 'gray' ? 0.85 : 1 }}>
        {text}
      </Text>
    </View>
  );
}

// Accepts either "A:userid" token or just a raw id
function Avatar({ id }: { id: string }) {
  let initial = id.slice(0, 1).toUpperCase();
  let colorId = id;
  if (id.includes(':')) {
    const [ch, rest] = id.split(':');
    if (ch) initial = ch.toUpperCase();
    if (rest) colorId = rest;
  }
  let hash = 0; for (let i = 0; i < colorId.length; i++) hash = (hash * 31 + colorId.charCodeAt(i)) | 0;
  const hue = Math.abs(hash) % 360;
  const bg = `hsl(${hue} 70% 45%)`;
  return (
    <View style={{ width: 22, height: 22, borderRadius: 11, backgroundColor: bg, alignItems: 'center', justifyContent: 'center' }}>
      <Text style={{ color: 'white', fontSize: 12, fontWeight: '700' }}>{initial}</Text>
    </View>
  );
}

export default function EventCard({
  title,
  date,         // event_date (ISO)
  createdAt,    // unused now, kept for prop compatibility
  members,
  memberCount,
  claimed,
  total,
  onPress,
}: {
  title: string;
  date?: string;
  createdAt?: string;
  members: string[];
  memberCount: number;
  claimed: number;
  total: number;
  onPress: () => void;
}) {
  const { t, i18n } = useTranslation();
  const { colors } = useTheme();

  const todayISO = new Date().toISOString();
  const hasDate = !!date;
  const daysLeft = hasDate ? daysDiffUTC(date as string, todayISO) : 0;

  // Status pill text & tone
  let tone: 'gray' | 'green' | 'red' = 'gray';
  let label = t('eventList.eventCard.noDate');
  if (hasDate) {
    if (daysLeft > 0)       { tone = 'gray';  label = humanizeDaysLeft(t, daysLeft); }
    else if (daysLeft === 0){ tone = 'green'; label = humanizeDaysLeft(t, daysLeft); }
    else                    { tone = 'red';   label = humanizeDaysLeft(t, daysLeft); }
  }

  return (
    <Pressable
      onPress={onPress}
      style={{
        backgroundColor: colors.card,
        padding: 14,
        borderRadius: 14,
        marginBottom: 12,
        shadowColor: '#000',
        shadowOpacity: 0.06,
        shadowRadius: 8,
        shadowOffset: { width: 0, height: 2 },
        elevation: 2,
        borderWidth: 1,
        borderColor: colors.border,
      }}
    >
      {/* Top row: title + status */}
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
        <Text style={{ fontSize: 16, fontWeight: '700', flexShrink: 1, color: colors.text }}>{title}</Text>
        <Pill text={label} tone={tone} />
      </View>

      {/* Date line */}
      {hasDate ? (
        <Text style={{ marginTop: 2, color: colors.text, opacity: 0.7 }}>
          {formatDateLocalized(date, i18n.language)}
        </Text>
      ) : (
        <Text style={{ marginTop: 2, color: colors.text, opacity: 0.5 }}>
          {t('eventList.eventCard.noDate')}
        </Text>
      )}

      {/* Bottom row: avatars + members + claimed/total */}
      <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 12, justifyContent: 'space-between' }}>
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          <View style={{ flexDirection: 'row' }}>
            {members.slice(0, 4).map((id, idx) => (
              <View key={id} style={{ marginLeft: idx === 0 ? 0 : -6 }}>
                <Avatar id={id} />
              </View>
            ))}
            {memberCount > 4 && (
              <View
                style={{
                  marginLeft: -6,
                  paddingHorizontal: 8,
                  height: 24,
                  borderRadius: 12,
                  backgroundColor: colors.card,
                  borderWidth: 1,
                  borderColor: colors.border,
                  alignItems: 'center',
                  justifyContent: 'center',
                }}
              >
                <Text style={{ fontWeight: '700', fontSize: 12, color: colors.text }}>
                  +{memberCount - 4}
                </Text>
              </View>
            )}
          </View>
          <Text style={{ marginLeft: 8, color: colors.text, opacity: 0.7 }}>
            {t('eventList.eventCard.members', { count: memberCount })}
          </Text>
        </View>

        <Text style={{ fontWeight: '600', color: colors.text, opacity: 0.8 }}>
          {t('eventList.eventCard.claimedShort', { claimed, total })}
        </Text>
      </View>
    </Pressable>
  );
}

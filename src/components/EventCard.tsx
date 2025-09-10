// src/components/EventCard.tsx
import React from 'react';
import { View, Text, Pressable } from 'react-native';

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

function humanizeDaysLeft(daysLeft: number) {
  if (daysLeft === 0) return 'Today';
  if (daysLeft === 1) return 'Tomorrow';
  if (daysLeft === -1) return 'Yesterday';
  if (daysLeft > 1) return `in ${daysLeft} days`;
  return `${Math.abs(daysLeft)} days ago`;
}

// Small pill
function Pill({ text, tone }: { text: string; tone: 'gray' | 'green' | 'red' }) {
  const bg = tone === 'green' ? '#e9f8ec' : tone === 'red' ? '#fde8e8' : '#edf1f5';
  const fg = tone === 'green' ? '#1f9e4a' : tone === 'red' ? '#c0392b' : '#63707e';
  return (
    <View style={{ backgroundColor: bg, paddingHorizontal: 8, paddingVertical: 4, borderRadius: 999 }}>
      <Text style={{ color: fg, fontSize: 12, fontWeight: '700' }}>{text}</Text>
    </View>
  );
}

// Simple colored initial bubble from user id
function Avatar({ id }: { id: string }) {
  const initial = id.slice(0, 1).toUpperCase();
  let hash = 0; for (let i = 0; i < id.length; i++) hash = (hash * 31 + id.charCodeAt(i)) | 0;
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
  const todayISO = new Date().toISOString();
  const hasDate = !!date;
  const daysLeft = hasDate ? daysDiffUTC(date as string, todayISO) : 0;

  // Status pill logic (no bar)
  let tone: 'gray' | 'green' | 'red' = 'gray';
  let label = 'No date';
  if (hasDate) {
    if (daysLeft > 0) { tone = 'gray'; label = humanizeDaysLeft(daysLeft); }
    else if (daysLeft === 0) { tone = 'green'; label = 'Today'; }
    else { tone = 'red'; label = humanizeDaysLeft(daysLeft); }
  }

  return (
    <Pressable
      onPress={onPress}
      style={{
        backgroundColor: 'white',
        padding: 14,
        borderRadius: 14,
        marginBottom: 12,
        shadowColor: '#000',
        shadowOpacity: 0.06,
        shadowRadius: 8,
        shadowOffset: { width: 0, height: 2 },
        elevation: 2,
      }}
    >
      {/* Top row: title + status */}
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
        <Text style={{ fontSize: 16, fontWeight: '700', flexShrink: 1 }}>{title}</Text>
        <Pill text={label} tone={tone} />
      </View>

      {/* Date line */}
      {hasDate ? (
        <Text style={{ marginTop: 2, opacity: 0.7 }}>{formatDate(date)}</Text>
      ) : (
        <Text style={{ marginTop: 2, opacity: 0.5 }}>No date set</Text>
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
                  backgroundColor: '#eef2f7',
                  alignItems: 'center',
                  justifyContent: 'center',
                }}
              >
                <Text style={{ fontWeight: '700', fontSize: 12 }}>+{memberCount - 4}</Text>
              </View>
            )}
          </View>
          <Text style={{ marginLeft: 8, opacity: 0.7 }}>{memberCount} members</Text>
        </View>

        <Text style={{ fontWeight: '600', color: '#63707e' }}>
          {claimed}/{total} claimed
        </Text>
      </View>
    </Pressable>
  );
}

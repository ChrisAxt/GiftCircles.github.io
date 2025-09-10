import React from 'react';
import { View, Text } from 'react-native';

function clamp(n: number, min: number, max: number) {
  return Math.max(min, Math.min(max, n));
}

export default function CountdownBar({
  daysLeft,
  totalWindowDays,
}: {
  daysLeft: number;        // can be negative if event is in the past
  totalWindowDays: number; // planning window; we’ll cap the bar to this
}) {
  const safeTotal = Math.max(1, totalWindowDays);
  const pct = clamp(daysLeft, 0, safeTotal) / safeTotal * 100;

  let label = '';
  if (daysLeft > 1) label = `${daysLeft} days left`;
  else if (daysLeft === 1) label = '1 day left';
  else if (daysLeft === 0) label = 'Today';
  else if (daysLeft === -1) label = '1 day ago';
  else label = `${Math.abs(daysLeft)} days ago`;

  return (
    <View>
      <View style={{ height: 8, backgroundColor: '#edf1f5', borderRadius: 999, overflow: 'hidden' }}>
        <View style={{ width: `${pct}%`, height: '100%', backgroundColor: '#2e95f1' }} />
      </View>
      <Text style={{ marginTop: 6, fontSize: 12, color: '#63707e' }}>{label}</Text>
    </View>
  );
}

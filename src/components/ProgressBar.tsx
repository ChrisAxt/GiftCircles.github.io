import { View } from 'react-native';

export default function ProgressBar({ value, total }: { value: number; total: number }) {
  const pct = total > 0 ? Math.min(100, Math.round((value / total) * 100)) : 0;
  return (
    <View style={{ height: 8, backgroundColor: '#edf1f5', borderRadius: 8, overflow: 'hidden' }}>
      <View style={{ width: `${pct}%`, height: '100%', backgroundColor: '#2e95f1' }} />
    </View>
  );
}

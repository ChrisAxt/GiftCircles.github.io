// src/components/StatCard.tsx
import { View, Text } from 'react-native';

export default function StatCard({ title, value }: { title: string; value: number | string }) {
  return (
    <View style={{
      flex: 1,
      backgroundColor: 'white',
      paddingVertical: 14,
      borderRadius: 14,
      alignItems: 'center',
      justifyContent: 'center'
    }}>
      <Text style={{ fontSize: 20, fontWeight: '800' }}>{String(value)}</Text>
      <Text style={{ marginTop: 4, opacity: 0.7 }}>{title}</Text>
    </View>
  );
}

import { View, Text } from 'react-native';
import { Item } from '../types';
export default function ItemRow({ item }: { item: Item }) {
  return (
    <View style={{ padding: 16 }}>
      <Text style={{ fontSize: 16, fontWeight: '600' }}>{item.name}</Text>
      {item.url ? <Text selectable>{item.url}</Text> : null}
      {item.price != null ? <Text>${item.price.toFixed(2)}</Text> : null}
    </View>
  );
}

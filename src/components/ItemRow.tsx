import { View, Text } from 'react-native';
import { Item } from '../types';
import { formatPrice } from '../lib/currency';
import { useUserCurrency } from '../hooks/useUserCurrency';

export default function ItemRow({ item }: { item: Item }) {
  const currency = useUserCurrency();

  return (
    <View style={{ padding: 16 }}>
      <Text style={{ fontSize: 16, fontWeight: '600' }}>{item.name}</Text>
      {item.url ? <Text selectable>{item.url}</Text> : null}
      {item.price != null ? <Text>{formatPrice(item.price, currency)}</Text> : null}
    </View>
  );
}

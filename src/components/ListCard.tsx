// src/components/ListCard.tsx
import { View, Text, Pressable } from 'react-native';
import { useTheme } from '@react-navigation/native';

export default function ListCard({
  name,
  recipients,          // array of display names (strings)
  itemCount,
  claimedCount,        // number when visible; undefined/null when hidden
  onPress,
}: {
  name: string;
  recipients: string[];
  itemCount: number;
  claimedCount?: number | null;
  onPress: () => void;
}) {
  const { colors } = useTheme();

  const recipientsLine =
    recipients.length === 0
      ? '—'
      : recipients.length === 1
      ? recipients[0]
      : recipients.slice(0, 3).join(', ') + (recipients.length > 3 ? ` +${recipients.length - 3}` : '');

  const claimedRight = typeof claimedCount === 'number'
    ? `${claimedCount}/${itemCount} claimed`
    : 'Claimed: hidden';

  return (
    <Pressable
      onPress={onPress}
      style={{
        backgroundColor: colors.card,   // theme surface
        padding: 14,
        borderRadius: 14,
        marginBottom: 12,
        shadowColor: '#000',
        shadowOpacity: 0.06,
        shadowRadius: 8,
        shadowOffset: { width: 0, height: 2 },
        elevation: 2,
        borderWidth: 1,
        borderColor: colors.border,     // subtle border for dark mode definition
      }}
    >
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
        <Text style={{ fontSize: 16, fontWeight: '700', color: colors.text }}>{name}</Text>
        <Text style={{ fontWeight: '600', color: colors.text, opacity: 0.7 }}>{claimedRight}</Text>
      </View>

      {/* recipients */}
      <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 8 }}>
        <Text style={{ color: colors.text, opacity: 0.7, marginRight: 6 }}>For:</Text>
        <Text style={{ fontWeight: '600', color: colors.text }}>{recipientsLine}</Text>
      </View>
    </Pressable>
  );
}

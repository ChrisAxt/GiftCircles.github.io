export const EVENT_THEME_IMAGES: Record<string, any> = {
  christmas: require('../../assets/event-themes/christmas.png'),
  birthday: require('../../assets/event-themes/birthday.png'),
  baby: require('../../assets/event-themes/baby-shower.png'),
  wedding: require('../../assets/event-themes/wedding.png'),
  default: require('../../assets/event-themes/default.png'),
};

export function pickEventImage(title?: string) {
  const t = (title || '').toLowerCase();

  if (/(x-?mas|christmas|noel)/.test(t)) return EVENT_THEME_IMAGES.christmas;
  if (/(birthday|b-?day|bday)/.test(t)) return EVENT_THEME_IMAGES.birthday;
  if (/(baby(?:\s|-)?shower|baby)/.test(t)) return EVENT_THEME_IMAGES.baby;
  if (/(wedding|marriage|anniversary)/.test(t)) return EVENT_THEME_IMAGES.wedding;

  // Fallback if no theme matched:
  return EVENT_THEME_IMAGES.default;
}

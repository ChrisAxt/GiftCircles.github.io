import * as Localization from 'expo-localization';

const mapLang = (lang?: string) => {
  // Map your i18n codes to full BCP-47 tags
  if (!lang) return Localization.getLocales?.()[0]?.languageTag;
  if (lang.includes('-')) return lang;        // already a tag
  if (lang === 'sv') return 'sv-SE';
  if (lang === 'en') return 'en-GB';          // or 'en-US' if you prefer
  return Localization.getLocales?.()[0]?.languageTag; // fallback
};

export function formatDateLocalized(iso?: string, lang?: string) {
  if (!iso) return '';
  const d = new Date(iso);
  const locale = mapLang(lang);
  return new Intl.DateTimeFormat(locale, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  }).format(d);
}
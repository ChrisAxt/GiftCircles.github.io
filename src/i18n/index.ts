// src/i18n/index.ts
import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';
import * as Localization from 'expo-localization';
import * as locales from './locales';

// Accept both export shapes
const normalize = (mod: any) => {
  const dict = mod?.default ?? mod;
  return dict?.translation ? dict : { translation: dict };
};

const resources = Object.fromEntries(
  Object.entries(locales).map(([code, mod]) => [code, normalize(mod)])
);

export const SUPPORTED_LANGS = Object.keys(resources); // e.g. ['en','sv','de','fr','es','it']

// Use expo-localization to pick the best supported language
export function detectSystemLanguage(): string {
  try {
    const langCode =
      (Localization.getLocales?.()[0]?.languageCode ||
       (Localization as any).locale?.split?.('-')?.[0] ||
       'en');

    return SUPPORTED_LANGS.includes(langCode) ? langCode : 'en';
  } catch {
    return 'en';
  }
}

i18n
  .use(initReactI18next)
  .init({
    resources,
    fallbackLng: 'en',
    lng: detectSystemLanguage(),      // set initial language to system
    load: 'languageOnly',             // map en-US -> en, sv-SE -> sv
    interpolation: { escapeValue: false },
  });

export default i18n;

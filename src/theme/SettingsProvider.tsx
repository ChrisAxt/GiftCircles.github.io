import React, { createContext, useContext, useEffect, useMemo, useState } from 'react';
import { Appearance } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import i18n from '../i18n'; // adjust if needed

type ThemePref = 'light' | 'dark';

type SettingsContextType = {
  // theme
  themePref: ThemePref;
  setThemePref: (pref: ThemePref) => void;
  colorScheme: ThemePref; // effective scheme == pref

  // language (unchanged — still supports 'system')
  langPref: string;
  setLangPref: (code: string) => void;
};

const SettingsContext = createContext<SettingsContextType | undefined>(undefined);

export function SettingsProvider({ children }: { children: React.ReactNode }) {
  // If nothing saved, initialize to the device scheme once, then persist
  const device = Appearance.getColorScheme();
  const [themePref, setThemePrefState] = useState<ThemePref>('light');
  const [langPref, setLangPrefState] = useState<string>('system');

  // Load saved prefs once
  useEffect(() => {
    (async () => {
      try {
        const [storedTheme, storedLang] = await Promise.all([
          AsyncStorage.getItem('pref.theme'),
          AsyncStorage.getItem('pref.lang'),
        ]);

        // Map any legacy value 'system' to a one-time device choice
        if (storedTheme === 'light' || storedTheme === 'dark') {
          setThemePrefState(storedTheme);
        } else if (storedTheme === 'system') {
          setThemePrefState(initialTheme);
          AsyncStorage.setItem('pref.theme', initialTheme).catch(() => {});
        }

        if (storedLang) {
          setLangPrefState(storedLang);
          if (storedLang !== 'system') {
            i18n.changeLanguage(storedLang).catch(() => {});
          }
        }
      } catch {}
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Setters (persist)
  const setThemePref = (pref: ThemePref) => {
    setThemePrefState(pref);
    AsyncStorage.setItem('pref.theme', pref).catch(() => {});
  };

  const setLangPref = (code: string) => {
    setLangPrefState(code);
    AsyncStorage.setItem('pref.lang', code).catch(() => {});
    if (code !== 'system') i18n.changeLanguage(code).catch(() => {});
  };

  const colorScheme: ThemePref = useMemo(() => themePref, [themePref]);

  const value = useMemo<SettingsContextType>(() => ({
    themePref,
    setThemePref,
    colorScheme,
    langPref,
    setLangPref,
  }), [themePref, colorScheme, langPref]);

  return <SettingsContext.Provider value={value}>{children}</SettingsContext.Provider>;
}

export function useSettings() {
  const ctx = useContext(SettingsContext);
  if (!ctx) throw new Error('useSettings must be used within SettingsProvider');
  return ctx;
}

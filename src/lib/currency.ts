// Currency formatting utilities

export interface Currency {
  code: string;
  symbol: string;
  name: string;
  locale?: string;
}

// Common currencies with their symbols and locales for formatting
export const CURRENCIES: Record<string, Currency> = {
  USD: { code: 'USD', symbol: '$', name: 'US Dollar', locale: 'en-US' },
  EUR: { code: 'EUR', symbol: '€', name: 'Euro', locale: 'de-DE' },
  GBP: { code: 'GBP', symbol: '£', name: 'British Pound', locale: 'en-GB' },
  CAD: { code: 'CAD', symbol: 'CA$', name: 'Canadian Dollar', locale: 'en-CA' },
  AUD: { code: 'AUD', symbol: 'A$', name: 'Australian Dollar', locale: 'en-AU' },
  JPY: { code: 'JPY', symbol: '¥', name: 'Japanese Yen', locale: 'ja-JP' },
  CNY: { code: 'CNY', symbol: '¥', name: 'Chinese Yuan', locale: 'zh-CN' },
  INR: { code: 'INR', symbol: '₹', name: 'Indian Rupee', locale: 'en-IN' },
  CHF: { code: 'CHF', symbol: 'CHF', name: 'Swiss Franc', locale: 'de-CH' },
  SEK: { code: 'SEK', symbol: 'kr', name: 'Swedish Krona', locale: 'sv-SE' },
  NOK: { code: 'NOK', symbol: 'kr', name: 'Norwegian Krone', locale: 'nb-NO' },
  DKK: { code: 'DKK', symbol: 'kr', name: 'Danish Krone', locale: 'da-DK' },
  NZD: { code: 'NZD', symbol: 'NZ$', name: 'New Zealand Dollar', locale: 'en-NZ' },
  MXN: { code: 'MXN', symbol: 'MX$', name: 'Mexican Peso', locale: 'es-MX' },
  BRL: { code: 'BRL', symbol: 'R$', name: 'Brazilian Real', locale: 'pt-BR' },
  ZAR: { code: 'ZAR', symbol: 'R', name: 'South African Rand', locale: 'en-ZA' },
  KRW: { code: 'KRW', symbol: '₩', name: 'South Korean Won', locale: 'ko-KR' },
  SGD: { code: 'SGD', symbol: 'S$', name: 'Singapore Dollar', locale: 'en-SG' },
  HKD: { code: 'HKD', symbol: 'HK$', name: 'Hong Kong Dollar', locale: 'zh-HK' },
  PLN: { code: 'PLN', symbol: 'zł', name: 'Polish Złoty', locale: 'pl-PL' },
  THB: { code: 'THB', symbol: '฿', name: 'Thai Baht', locale: 'th-TH' },
  IDR: { code: 'IDR', symbol: 'Rp', name: 'Indonesian Rupiah', locale: 'id-ID' },
  MYR: { code: 'MYR', symbol: 'RM', name: 'Malaysian Ringgit', locale: 'ms-MY' },
  PHP: { code: 'PHP', symbol: '₱', name: 'Philippine Peso', locale: 'fil-PH' },
  CZK: { code: 'CZK', symbol: 'Kč', name: 'Czech Koruna', locale: 'cs-CZ' },
  HUF: { code: 'HUF', symbol: 'Ft', name: 'Hungarian Forint', locale: 'hu-HU' },
  RUB: { code: 'RUB', symbol: '₽', name: 'Russian Ruble', locale: 'ru-RU' },
  TRY: { code: 'TRY', symbol: '₺', name: 'Turkish Lira', locale: 'tr-TR' },
};

// Get sorted list of all currencies for dropdown
export const getAllCurrencies = (): Currency[] => {
  return Object.values(CURRENCIES).sort((a, b) => a.name.localeCompare(b.name));
};

/**
 * Format a price with the given currency
 * @param amount - The numeric amount
 * @param currencyCode - ISO 4217 currency code (e.g., 'USD', 'EUR')
 * @param options - Formatting options
 */
export const formatPrice = (
  amount: number | null | undefined,
  currencyCode: string = 'USD',
  options?: {
    showSymbol?: boolean;
    showCode?: boolean;
    decimals?: number;
  }
): string => {
  if (amount === null || amount === undefined) {
    return '';
  }

  const currency = CURRENCIES[currencyCode.toUpperCase()] || CURRENCIES.USD;
  const {
    showSymbol = true,
    showCode = false,
    decimals,
  } = options || {};

  // Determine decimal places
  let decimalPlaces = decimals;
  if (decimalPlaces === undefined) {
    // Currencies like JPY and KRW typically don't use decimals
    decimalPlaces = ['JPY', 'KRW', 'IDR'].includes(currency.code) ? 0 : 2;
  }

  const formattedNumber = amount.toFixed(decimalPlaces);

  if (!showSymbol && !showCode) {
    return formattedNumber;
  }

  if (showCode) {
    return `${formattedNumber} ${currency.code}`;
  }

  // Most currencies put symbol before amount (e.g., $10.00)
  // Some put it after (e.g., 10.00 kr)
  const symbolAfter = ['SEK', 'NOK', 'DKK', 'CZK', 'PLN', 'HUF'].includes(currency.code);

  if (symbolAfter) {
    return `${formattedNumber} ${currency.symbol}`;
  }

  return `${currency.symbol}${formattedNumber}`;
};

/**
 * Detect user's currency based on their locale/region
 * Falls back to USD if detection fails
 */
export const detectUserCurrency = (): string => {
  try {
    // Try to detect from system locale
    const locale = Intl.DateTimeFormat().resolvedOptions().locale || 'en-US';

    // Map common locales to currencies
    const localeToCurrency: Record<string, string> = {
      'en-US': 'USD',
      'en-GB': 'GBP',
      'en-CA': 'CAD',
      'en-AU': 'AUD',
      'en-NZ': 'NZD',
      'en-IN': 'INR',
      'en-ZA': 'ZAR',
      'de': 'EUR',
      'de-DE': 'EUR',
      'de-CH': 'CHF',
      'fr': 'EUR',
      'fr-FR': 'EUR',
      'fr-CH': 'CHF',
      'it': 'EUR',
      'it-IT': 'EUR',
      'es': 'EUR',
      'es-ES': 'EUR',
      'es-MX': 'MXN',
      'pt-BR': 'BRL',
      'pt-PT': 'EUR',
      'ja': 'JPY',
      'ja-JP': 'JPY',
      'zh-CN': 'CNY',
      'zh-HK': 'HKD',
      'zh-SG': 'SGD',
      'ko': 'KRW',
      'ko-KR': 'KRW',
      'sv': 'SEK',
      'sv-SE': 'SEK',
      'no': 'NOK',
      'nb-NO': 'NOK',
      'da': 'DKK',
      'da-DK': 'DKK',
      'pl': 'PLN',
      'pl-PL': 'PLN',
      'cs': 'CZK',
      'cs-CZ': 'CZK',
      'hu': 'HUF',
      'hu-HU': 'HUF',
      'ru': 'RUB',
      'ru-RU': 'RUB',
      'tr': 'TRY',
      'tr-TR': 'TRY',
      'th': 'THB',
      'th-TH': 'THB',
      'id': 'IDR',
      'id-ID': 'IDR',
      'ms': 'MYR',
      'ms-MY': 'MYR',
      'fil': 'PHP',
      'fil-PH': 'PHP',
    };

    // Try exact match first
    if (localeToCurrency[locale]) {
      return localeToCurrency[locale];
    }

    // Try language code only (e.g., 'en' from 'en-US')
    const langCode = locale.split('-')[0];
    if (localeToCurrency[langCode]) {
      return localeToCurrency[langCode];
    }

    // Default to USD
    return 'USD';
  } catch (error) {
    // Failed to detect currency, defaulting to USD
    return 'USD';
  }
};

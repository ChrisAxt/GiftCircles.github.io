# User-Friendly Error Handling - Implementation Guide

## Overview

A centralized error handling system has been implemented to provide consistent, user-friendly, **fully translated** error messages across the GiftCircles app.

## What Changed

### ✅ Created: `src/lib/errorHandler.ts`

A utility that converts technical Supabase errors into user-friendly, translated messages.

**Key Features:**
- Parses error codes and messages from Supabase
- Returns friendly title + message using i18n translations
- Categorizes errors by severity (error, warning, info)
- Helper functions to check error types
- **Fully integrated with react-i18next** for multi-language support

### ✅ Updated Translation Files

Added `errors` section to `src/i18n/locales/en.ts` with all error messages organized by category:
- `errors.auth.*` - Authentication and authorization errors
- `errors.limits.*` - Free tier limit errors
- `errors.validation.*` - Input validation errors
- `errors.items.*` - Item/claim related errors
- `errors.database.*` - Database constraint errors
- `errors.network.*` - Network/connection errors
- `errors.generic.*` - Generic fallback errors

### ✅ Updated Screens

The following screens now use the error handler:
1. **CreateEventScreen.tsx** - Event creation errors
2. **JoinEventScreen.tsx** - Join code errors
3. **CreateListScreen.tsx** - List creation errors

## Error Message Mappings

### Authentication Errors
| Technical Error | User-Friendly Message |
|----------------|----------------------|
| `not_authenticated` | "Sign in required" - "Please sign in to continue" |

### Authorization Errors
| Technical Error | User-Friendly Message |
|----------------|----------------------|
| `not_authorized` | "Access denied" - "You don't have permission to do that" |
| `must_be_event_member` | "Not a member" - "You must be a member of this event to do that" |
| `not_an_event_member` | "Not a member" - "You are not a member of this event" |

### Free Tier Limits
| Technical Error | User-Friendly Message |
|----------------|----------------------|
| `free_limit_reached` | "Upgrade required" - "You can create up to 3 events on the free plan. Upgrade to create more." |

### Validation Errors
| Technical Error | User-Friendly Message |
|----------------|----------------------|
| `invalid_parameter: title_required` | "Title required" - "Please enter a title for your event" |
| `invalid_parameter: name_required` | "Name required" - "Please enter a name" |
| `invalid_parameter: code_required` | "Code required" - "Please enter a join code" |
| `invalid_parameter: invalid_recurrence` | "Invalid recurrence" - "Please select a valid recurrence option" |
| `invalid_parameter: invalid_visibility` | "Invalid visibility" - "Please select a valid visibility option" |
| `invalid_parameter: event_date_must_be_future` | "Invalid date" - "Event date must be today or in the future" |
| `invalid_join_code` | "Invalid code" - "This join code is not valid. Please check and try again." |

### Database Errors
| Technical Error | User-Friendly Message |
|----------------|----------------------|
| Code `23505` (unique violation) | "Duplicate entry" - "This item already exists" |
| Code `23503` (FK violation) | "Invalid reference" - "Cannot complete action due to missing reference" |
| Code `23502` (not null violation) | "Missing required field" - "Please fill in all required fields" |

### Other Errors
| Technical Error | User-Friendly Message |
|----------------|----------------------|
| `has_claims` | "Cannot delete" - "This item has claims and cannot be deleted" |
| `not_found` | "Not found" - "The item you requested could not be found" |
| Network errors | "Connection error" - "Please check your internet connection and try again" |
| Unknown errors | "Something went wrong" - "An unexpected error occurred. Please try again." |

## How to Use in Other Screens

### Example 1: Simple Error Handling with Toast

```typescript
import { parseSupabaseError } from '../lib/errorHandler';
import { toast } from '../lib/toast';
import { useTranslation } from 'react-i18next';

export default function MyScreen() {
  const { t } = useTranslation(); // Get translation function

  const handleAction = async () => {
    try {
      const { data, error } = await supabase.rpc('some_function', { ...params });

      if (error) {
        const errorDetails = parseSupabaseError(error, t); // Pass t function
        toast.error(errorDetails.title, errorDetails.message);
        return;
      }

      // Success handling...
    } catch (err: any) {
      const errorDetails = parseSupabaseError(err, t); // Pass t function
      toast.error(errorDetails.title, errorDetails.message);
    }
  };
}
```

### Example 2: Using Alert for Errors

```typescript
import { parseSupabaseError } from '../lib/errorHandler';
import { Alert } from 'react-native';
import { useTranslation } from 'react-i18next';

export default function MyScreen() {
  const { t } = useTranslation();

  const handleAction = async () => {
    try {
      const { data, error } = await supabase.rpc('some_function', { ...params });

      if (error) {
        const errorDetails = parseSupabaseError(error, t);
        Alert.alert(errorDetails.title, errorDetails.message);
        return;
      }
    } catch (err: any) {
      const errorDetails = parseSupabaseError(err, t);
      Alert.alert(errorDetails.title, errorDetails.message);
    }
  };
}
```

### Example 3: Checking Specific Error Types

```typescript
import { parseSupabaseError, isAuthError, isFreeLimitError } from '../lib/errorHandler';
import { useTranslation } from 'react-i18next';

export default function MyScreen() {
  const { t } = useTranslation();

  const handleAction = async () => {
    try {
      const { error } = await supabase.rpc('create_something', { ...params });

      if (error) {
        if (isAuthError(error)) {
          // Redirect to sign in
          navigation.navigate('Auth');
          return;
        }

        if (isFreeLimitError(error)) {
          // Show upgrade modal
          setShowUpgradeModal(true);
          return;
        }

        // Generic error handling with translations
        const errorDetails = parseSupabaseError(error, t);
        toast.error(errorDetails.title, errorDetails.message);
      }
    } catch (err: any) {
      // Handle unexpected errors
    }
  };
}
```

## Remaining Screens to Update

The following screens still have inline error handling that could be improved:

- [ ] `AddItemScreen.tsx`
- [ ] `AuthScreen.tsx`
- [ ] `EditEventScreen.tsx`
- [ ] `EventDetailScreen.tsx`
- [x] `EventListScreen.tsx` ✅ Uses translated errors in onPressCreate (2025-10-02)
- [ ] `ListDetailScreen.tsx`
- [ ] `OnboardingScreen.tsx`
- [ ] `ProfileScreen.tsx`

## Benefits

✅ **Consistency** - All errors follow the same format
✅ **User-Friendly** - Technical jargon replaced with clear messages
✅ **Maintainable** - Error logic centralized in one place
✅ **Fully Translated** - All errors use i18n translation system
✅ **Multi-Language Ready** - Easy to translate to other languages
✅ **Extensible** - Easy to add new error types

## Adding Translations for Other Languages

To translate error messages to other languages (e.g., Swedish, French):

1. Copy the `errors` section from `src/i18n/locales/en.ts`
2. Paste into other locale files (e.g., `src/i18n/locales/sv.ts`)
3. Translate all the message values while keeping the keys the same

**Example for Swedish (`sv.ts`):**

```typescript
errors: {
  auth: {
    notAuthenticatedTitle: 'Inloggning krävs',
    notAuthenticatedMessage: 'Vänligen logga in för att fortsätta',
    // ... etc
  },
  // ... rest of translations
}
```

## Testing

To test error messages:

1. **Try creating an event with empty title** → Should show "Title required"
2. **Try joining with invalid code** → Should show "Invalid code"
3. **Try creating a 4th event on free plan** → Should show "Upgrade required"
4. **Disconnect internet and try an action** → Should show "Connection error"

## Future Improvements

1. ~~**Add i18n support**~~ ✅ DONE - All errors fully translated
2. **Add error logging** - Send errors to analytics/monitoring service
3. **Add retry logic** - For network errors, offer "Retry" button
4. **Add contextual help** - Link to help docs for specific errors
5. **Translate to other languages** - Add Swedish, French, German, etc. translations

---

**Created**: 2025-10-02
**Updated**: 2025-10-02 (Added full i18n support)
**Status**: ✅ Implemented with full translation support

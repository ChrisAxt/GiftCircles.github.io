/**
 * Centralized error handling for Supabase RPC and database errors
 *
 * Converts technical error codes into user-friendly messages using i18n translations
 */

import type { TFunction } from 'i18next';

export interface ErrorDetails {
  title: string;
  message: string;
  severity: 'error' | 'warning' | 'info';
}

/**
 * Parse Supabase error and return user-friendly details
 * @param error - The error object from Supabase
 * @param t - Translation function from useTranslation()
 */
export function parseSupabaseError(error: any, t: TFunction): ErrorDetails {
  const errorMessage = String(error?.message || error || '').toLowerCase();
  const errorCode = error?.code;

  // Authentication errors
  if (errorMessage.includes('not_authenticated') || errorMessage.includes('not authenticated')) {
    return {
      title: t('errors.auth.notAuthenticatedTitle', 'Sign in required'),
      message: t('errors.auth.notAuthenticatedMessage', 'Please sign in to continue'),
      severity: 'warning'
    };
  }

  // Authorization errors
  if (errorMessage.includes('not_authorized') || errorMessage.includes('not authorized')) {
    return {
      title: t('errors.auth.notAuthorizedTitle', 'Access denied'),
      message: t('errors.auth.notAuthorizedMessage', "You don't have permission to do that"),
      severity: 'warning'
    };
  }

  if (errorMessage.includes('must_be_event_member')) {
    return {
      title: t('errors.auth.mustBeMemberTitle', 'Not a member'),
      message: t('errors.auth.mustBeMemberMessage', 'You must be a member of this event to do that'),
      severity: 'warning'
    };
  }

  if (errorMessage.includes('not_an_event_member') || errorMessage.includes('not_member')) {
    return {
      title: t('errors.auth.notMemberTitle', 'Not a member'),
      message: t('errors.auth.notMemberMessage', 'You are not a member of this event'),
      severity: 'warning'
    };
  }

  // Free tier limit errors
  if (errorMessage.includes('free_limit_reached')) {
    return {
      title: t('errors.limits.freeLimitTitle', 'Upgrade required'),
      message: t('errors.limits.freeLimitMessage', 'You can create up to 3 events on the free plan. Upgrade to create more.'),
      severity: 'info'
    };
  }

  // Invalid parameter errors
  if (errorMessage.includes('invalid_parameter')) {
    if (errorMessage.includes('title_required')) {
      return {
        title: t('errors.validation.titleRequiredTitle', 'Title required'),
        message: t('errors.validation.titleRequiredMessage', 'Please enter a title for your event'),
        severity: 'warning'
      };
    }

    if (errorMessage.includes('name_required')) {
      return {
        title: t('errors.validation.nameRequiredTitle', 'Name required'),
        message: t('errors.validation.nameRequiredMessage', 'Please enter a name'),
        severity: 'warning'
      };
    }

    if (errorMessage.includes('code_required')) {
      return {
        title: t('errors.validation.codeRequiredTitle', 'Code required'),
        message: t('errors.validation.codeRequiredMessage', 'Please enter a join code'),
        severity: 'warning'
      };
    }

    if (errorMessage.includes('invalid_recurrence')) {
      return {
        title: t('errors.validation.invalidRecurrenceTitle', 'Invalid recurrence'),
        message: t('errors.validation.invalidRecurrenceMessage', 'Please select a valid recurrence option'),
        severity: 'warning'
      };
    }

    if (errorMessage.includes('invalid_visibility')) {
      return {
        title: t('errors.validation.invalidVisibilityTitle', 'Invalid visibility'),
        message: t('errors.validation.invalidVisibilityMessage', 'Please select a valid visibility option'),
        severity: 'warning'
      };
    }

    if (errorMessage.includes('event_date_must_be_future')) {
      return {
        title: t('errors.validation.invalidDateTitle', 'Invalid date'),
        message: t('errors.validation.invalidDateMessage', 'Event date must be today or in the future'),
        severity: 'warning'
      };
    }

    // Generic invalid parameter
    return {
      title: t('errors.validation.invalidInputTitle', 'Invalid input'),
      message: t('errors.validation.invalidInputMessage', 'Please check your input and try again'),
      severity: 'warning'
    };
  }

  // Join code errors
  if (errorMessage.includes('invalid_join_code')) {
    return {
      title: t('errors.validation.invalidJoinCodeTitle', 'Invalid code'),
      message: t('errors.validation.invalidJoinCodeMessage', 'This join code is not valid. Please check and try again.'),
      severity: 'warning'
    };
  }

  // Item/claim errors
  if (errorMessage.includes('has_claims')) {
    return {
      title: t('errors.items.hasClaimsTitle', 'Cannot delete'),
      message: t('errors.items.hasClaimsMessage', 'This item has claims and cannot be deleted'),
      severity: 'warning'
    };
  }

  if (errorMessage.includes('not_found')) {
    return {
      title: t('errors.items.notFoundTitle', 'Not found'),
      message: t('errors.items.notFoundMessage', 'The item you requested could not be found'),
      severity: 'warning'
    };
  }

  // Database constraint errors
  if (errorCode === '23505') { // Unique constraint violation
    if (errorMessage.includes('email')) {
      return {
        title: t('errors.database.emailTakenTitle', 'Email already registered'),
        message: t('errors.database.emailTakenMessage', 'This email is already in use'),
        severity: 'warning'
      };
    }
    return {
      title: t('errors.database.duplicateTitle', 'Duplicate entry'),
      message: t('errors.database.duplicateMessage', 'This item already exists'),
      severity: 'warning'
    };
  }

  if (errorCode === '23503') { // Foreign key violation
    return {
      title: t('errors.database.invalidReferenceTitle', 'Invalid reference'),
      message: t('errors.database.invalidReferenceMessage', 'Cannot complete action due to missing reference'),
      severity: 'error'
    };
  }

  if (errorCode === '23502') { // Not null violation
    return {
      title: t('errors.database.missingFieldTitle', 'Missing required field'),
      message: t('errors.database.missingFieldMessage', 'Please fill in all required fields'),
      severity: 'warning'
    };
  }

  // Network/connection errors
  if (errorMessage.includes('fetch') || errorMessage.includes('network')) {
    return {
      title: t('errors.network.connectionTitle', 'Connection error'),
      message: t('errors.network.connectionMessage', 'Please check your internet connection and try again'),
      severity: 'error'
    };
  }

  // Generic fallback
  return {
    title: t('errors.generic.title', 'Something went wrong'),
    message: t('errors.generic.message', 'An unexpected error occurred. Please try again.'),
    severity: 'error'
  };
}

/**
 * Check if error is a specific type
 * (These don't need translation since they're just for logic)
 */
export function isAuthError(error: any): boolean {
  const msg = String(error?.message || error || '').toLowerCase();
  return msg.includes('not_authenticated') || msg.includes('not authenticated');
}

export function isAuthorizationError(error: any): boolean {
  const msg = String(error?.message || error || '').toLowerCase();
  return msg.includes('not_authorized') ||
         msg.includes('not_an_event_member') ||
         msg.includes('must_be_event_member');
}

export function isFreeLimitError(error: any): boolean {
  const msg = String(error?.message || error || '').toLowerCase();
  return msg.includes('free_limit_reached');
}

export function isValidationError(error: any): boolean {
  const msg = String(error?.message || error || '').toLowerCase();
  return msg.includes('invalid_parameter') ||
         msg.includes('invalid_join_code') ||
         msg.includes('_required');
}

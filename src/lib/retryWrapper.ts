// retryWrapper.ts
// Retry logic with exponential backoff for database operations
// Helps handle transient network errors and connection issues

export interface RetryOptions {
  maxRetries?: number;
  initialDelayMs?: number;
  maxDelayMs?: number;
  backoffMultiplier?: number;
  retryableErrors?: string[];
}

const DEFAULT_OPTIONS: Required<RetryOptions> = {
  maxRetries: 3,
  initialDelayMs: 1000,
  maxDelayMs: 10000,
  backoffMultiplier: 2,
  retryableErrors: [
    'PGRST301', // Connection timeout
    'PGRST504', // Gateway timeout
    'FetchError', // Network error
    'timeout', // Request timeout
    'ECONNREFUSED', // Connection refused
    'ENOTFOUND', // DNS lookup failed
    'ETIMEDOUT', // Connection timed out
  ],
};

/**
 * Checks if an error is retryable based on error message/code
 */
function isRetryableError(error: any, retryableErrors: string[]): boolean {
  if (!error) return false;

  const errorString = String(error.message || error.code || error);

  return retryableErrors.some(retryable =>
    errorString.toLowerCase().includes(retryable.toLowerCase())
  );
}

/**
 * Delay helper with exponential backoff
 */
function delay(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Wraps a Supabase query with retry logic and exponential backoff
 *
 * @example
 * const { data, error } = await withRetry(
 *   () => supabase.from('events').select('*'),
 *   { maxRetries: 3 }
 * );
 */
export async function withRetry<T>(
  operation: () => Promise<T>,
  options: RetryOptions = {}
): Promise<T> {
  const opts = { ...DEFAULT_OPTIONS, ...options };
  let lastError: any;
  let currentDelay = opts.initialDelayMs;

  for (let attempt = 0; attempt <= opts.maxRetries; attempt++) {
    try {
      return await operation();
    } catch (error: any) {
      lastError = error;

      // Don't retry if this is the last attempt
      if (attempt >= opts.maxRetries) {
        break;
      }

      // Don't retry if error is not retryable
      if (!isRetryableError(error, opts.retryableErrors)) {
        throw error;
      }

      // Wait before retrying
      await delay(currentDelay);

      // Increase delay for next attempt (exponential backoff)
      currentDelay = Math.min(
        currentDelay * opts.backoffMultiplier,
        opts.maxDelayMs
      );
    }
  }

  // All retries exhausted
  throw lastError;
}

/**
 * Circuit breaker pattern to prevent overwhelming the database
 * Opens circuit after consecutive failures, closes after cooldown
 */
class CircuitBreaker {
  private failureCount = 0;
  private lastFailureTime: number | null = null;
  private isOpen = false;

  constructor(
    private readonly threshold = 5,
    private readonly cooldownMs = 60000 // 1 minute
  ) {}

  async execute<T>(operation: () => Promise<T>): Promise<T> {
    // Check if circuit is open
    if (this.isOpen) {
      const timeSinceLastFailure = Date.now() - (this.lastFailureTime || 0);

      if (timeSinceLastFailure < this.cooldownMs) {
        throw new Error(
          `Circuit breaker is open. Try again in ${Math.ceil((this.cooldownMs - timeSinceLastFailure) / 1000)}s`
        );
      }

      // Cooldown period passed, attempt to close circuit
      this.isOpen = false;
      this.failureCount = 0;
    }

    try {
      const result = await operation();

      // Success - reset failure count
      if (this.failureCount > 0) {
        this.failureCount = 0;
      }

      return result;
    } catch (error) {
      this.failureCount++;
      this.lastFailureTime = Date.now();

      // Open circuit if threshold exceeded
      if (this.failureCount >= this.threshold) {
        this.isOpen = true;
      }

      throw error;
    }
  }

  reset(): void {
    this.failureCount = 0;
    this.lastFailureTime = null;
    this.isOpen = false;
  }

  getStatus(): { isOpen: boolean; failureCount: number } {
    return {
      isOpen: this.isOpen,
      failureCount: this.failureCount,
    };
  }
}

// Global circuit breaker instance for all database operations
export const globalCircuitBreaker = new CircuitBreaker(5, 60000);

/**
 * Combines retry logic with circuit breaker pattern
 *
 * @example
 * const { data, error } = await withRetryAndCircuitBreaker(
 *   () => supabase.from('events').select('*')
 * );
 */
export async function withRetryAndCircuitBreaker<T>(
  operation: () => Promise<T>,
  retryOptions: RetryOptions = {}
): Promise<T> {
  return globalCircuitBreaker.execute(() =>
    withRetry(operation, retryOptions)
  );
}

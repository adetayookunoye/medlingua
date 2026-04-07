---
description: "Use when: writing or editing service classes in lib/services/. Enforces consistent try-catch error handling, custom exceptions, logging, and async patterns for DatabaseService, GemmaService, and VoiceService."
applyTo: "lib/services/**/*.dart"
---

# Service Error Handling Standards

## Exception Pattern

Wrap all public async methods in try-catch. Catch specific exceptions, log them, and rethrow as typed service exceptions:

```dart
Future<T> someMethod() async {
  try {
    // ... implementation
  } on SpecificException catch (e) {
    debugPrint('ServiceName.someMethod: $e');
    throw ServiceException('Human-readable message', cause: e);
  } catch (e, stackTrace) {
    debugPrint('ServiceName.someMethod unexpected: $e\n$stackTrace');
    throw ServiceException('Unexpected error in someMethod', cause: e);
  }
}
```

## Rules

- Every public async method MUST have a try-catch block
- NEVER use empty catch blocks (`catch (_) {}`) — always log and rethrow or return a typed error
- Use `debugPrint` for all error logging with the format: `'ClassName.methodName: $error'`
- Use try-finally ONLY when cleanup is needed (e.g., resetting `_isProcessing`); combine with catch, not instead of it
- Catch specific exception types before the generic `catch (e)` fallback
- For database operations: catch `DatabaseException` specifically
- For voice operations: catch `PlatformException` specifically
- For model operations: catch `Exception` and include model state in the log

## State Reset

When a method manages state flags (like `_isProcessing`), always reset in `finally`:

```dart
try {
  _isProcessing = true;
  // ...work...
} catch (e) {
  debugPrint('...');
  rethrow; // or throw typed exception
} finally {
  _isProcessing = false;
}
```

## Return Types on Failure

- Methods returning `Future<T?>` — return `null` on expected failures, throw on unexpected
- Methods returning `Future<List<T>>` — return empty list on expected failures, throw on unexpected
- Methods returning `Future<void>` — always throw on failure (caller must handle)

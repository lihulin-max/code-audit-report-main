# XAML WPF Audit Reference

Use for WPF XAML, MVVM applications, bindings, resources, and UI-layer C# interaction. Refer to Microsoft WPF guidance, .NET design guidelines, MVVM practices, and accessibility guidance.

## Architecture

- Keep UI behavior in ViewModels or commands; avoid business logic in code-behind.
- Use clear resource dictionaries and avoid duplicated styles.
- Keep bindings traceable and fail-fast in development.
- Separate design-time data from production data.

## Coding Standards

- Name controls only when they are referenced.
- Use commands instead of click handlers for MVVM flows.
- Avoid deeply nested visual trees when a template or user control is clearer.
- Prefer `StaticResource` where runtime changes are not needed.
- Keep converters small, deterministic, and tested.

## Reliability

- Check binding paths, nullability, and fallback values.
- Avoid memory leaks from event subscriptions, timers, static events, and behaviors.
- Dispose unmanaged resources held by controls or view models.
- Avoid UI-thread blocking operations.

## Security

- Do not bind sensitive data into logs, tooltips, clipboard, or debug UI.
- Validate file paths and drag/drop inputs.
- Avoid loading untrusted XAML or loose resources.

## Tooling

Recommended tools:

- `dotnet build` with WPF analyzers
- Visual Studio XAML diagnostics
- Roslyn analyzers
- UI automation or integration tests for critical flows

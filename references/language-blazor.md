# Blazor Audit Reference

Use for Blazor Server, Blazor WebAssembly, Razor components, and related ASP.NET Core projects. Refer to Microsoft ASP.NET Core Blazor guidance, .NET coding conventions, OWASP, and enterprise frontend practices.

## Architecture

- Distinguish Blazor Server and WebAssembly trust boundaries.
- Keep UI components thin; move business logic to services.
- Use dependency injection lifetimes appropriate to hosting model.
- Avoid direct data access from components.
- Keep component state explicit and resilient to rerendering.

## Coding Standards

- Use PascalCase for components and public members.
- Avoid oversized `.razor` files; split reusable components.
- Prefer strongly typed parameters and `EventCallback<T>`.
- Avoid `async void` except event handlers where required.
- Dispose subscriptions, timers, JS object references, and `IDisposable` services.

## Security Hotspots

- Do not trust client-side WebAssembly authorization checks.
- Validate all server calls and enforce authorization on APIs.
- Avoid rendering untrusted markup through `MarkupString`.
- Protect JS interop boundaries and do not pass secrets to the browser.
- For Blazor Server, consider circuit state, CSRF, authentication, and SignalR exposure.

## Reliability And UX

- Handle cancellation, loading, error, and reconnection states.
- Avoid blocking calls in UI event handlers.
- Prevent duplicate submissions and race conditions during async UI updates.

## Tooling

Recommended tools:

- `dotnet build` with analyzers
- `dotnet test`
- `dotnet format --verify-no-changes`
- Roslyn/SonarAnalyzer/SecurityCodeScan
- Playwright or bUnit for component tests

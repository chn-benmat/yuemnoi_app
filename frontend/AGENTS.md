# Project Context: Yuemnoi App

## 1. Overview

- This application manages equipment rentals and returns.

## 2. Tech Stack

- Language: Dart
- Framework: Flutter
- Database and authentication: Supabase

## 3. Architecture and File Structure

- `lib/` is the root directory for application source code.
  - `main.dart` is the application entry point. Keep startup and dependency initialization here.
  - `app.dart` contains the root application widget and app-level lifecycle or configuration.
- `lib/core/` contains shared, feature-independent application functionality.
  - `constants/` contains application-wide constant values. Do not put mutable state here.
  - `errors/` contains shared exceptions and failures used to communicate errors across layers.
  - `navigation/` contains route definitions and application-wide navigation helpers.
  - `network/` contains shared API clients, Supabase clients, authentication sessions, and network configuration.
  - `theme/` contains application-wide colors, typography, and Flutter theme configuration.
  - `utils/` contains reusable, feature-independent technical transformations and helpers, such as image compression. Keep utilities stateless and free of UI state, BLoC state, navigation, and feature business rules.
  - `widgets/` contains feature-independent widgets reusable across multiple pages or features (`core/widgets/`). Shared widgets own common visual behavior such as styling, loading, disabled, and error states; pages provide labels, callbacks, and feature state.
- `lib/features/` contains feature modules. Keep code inside the feature that owns its business responsibility.
  - `<feature>/data/` handles external and local data and transforms it for the domain layer.
    - `datasources/` connects directly to APIs, Supabase, or local storage and retrieves raw data. Separate remote and local data sources when applicable.
    - `models/` contains DTOs that match API or database responses and convert themselves to domain entities with methods such as `toEntity()`.
    - `repositories/` contains implementations of repository interfaces defined by the domain layer. It coordinates data sources, including cache selection when applicable, and returns domain entities.
  - `<feature>/domain/` contains the feature's core business logic. It must not depend on Flutter, databases, or external libraries.
    - `entities/` contains domain objects and the feature's core business rules.
    - `repositories/` defines interfaces and contracts for the data operations required by the application. The data layer provides their implementations.
    - `usecases/` coordinates application business logic. It applies domain rules and invokes repository operations.
  - `<feature>/presentation/` contains the user interface, presentation state, and user interactions.
    - `bloc/` contains BLoCs, events, and states for presentation state management.
    - `pages/` contains application screens and route-level widgets.
    - `widgets/` contains widgets used only by a specific page in that feature (`presentation/widgets/`).
    - `mock/` contains temporary presentation-only mock data. Production data access belongs in the data layer.
- Store UI image assets in `assets/images/`.

## 4. Development Rules

- Write code comments in clear, easy-to-understand Thai.
- Preserve the existing BLoC and Clean Architecture approach. Do not introduce a competing state-management pattern.
- Do not modify, redesign, or alter existing UI/UX layouts, styling, screens, or components unless explicitly requested by the user. When implementing new logic, connecting APIs, or integrating features, keep the existing UI design intact.
- Before writing a widget, field decoration, button style, or repeated layout, search the feature's `presentation/widgets/`, `core/widgets/`, and `core/theme/` for an existing implementation.
- Reuse or extend an existing shared widget with backward-compatible options when the same feature-independent UI behavior is needed. Keep the shared visual logic in one source of truth instead of recreating it in pages.
- Place UI that is reusable only inside one feature in that feature's `presentation/widgets/`. Promote it to `core/widgets/` only when it is feature-independent and reused across pages or features.

## 5. Current Status and Next Steps

- The current focus is the Flutter frontend written in Dart.
- The authentication frontend has been implemented.

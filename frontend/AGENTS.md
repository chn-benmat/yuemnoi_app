# Project Context: Yuemnoi App

## 1. Overview

- This application manages equipment rentals and returns.

## 2. Tech Stack

- Language: Dart
- Framework: Flutter
- Database and authentication: Supabase

## 3. Architecture and File Structure

- The `features/` directory contains the application's feature modules.
- Within each feature, the `data/` directory handles and transforms raw data from APIs and local storage.
  - `datasources/` connects directly to external data sources and retrieves raw data. Separate remote and local data sources when applicable.
  - `models/` contains DTOs that match API or database responses and convert themselves to domain entities with methods such as `toEntity()`.
  - `repositories/` contains implementations of repository interfaces defined by the domain layer. It coordinates data sources, including cache selection when applicable, and returns domain entities.
- The `domain/` directory contains the feature's core business logic. It must not depend on Flutter, databases, or external libraries.
  - `entities/` contains data objects and the feature's core business rules.
  - `repositories/` defines interfaces and contracts for the data operations required by the application. The data layer provides their implementations.
  - `usecases/` coordinates application business logic. It receives input from the presentation layer, applies domain rules, and invokes repository operations.
- The `presentation/` directory contains the user interface and user interactions.
  - Put reusable feature-level widgets in `widgets/`.
  - Put application screens in `pages/`.
- The `core/` directory contains shared application functionality.
- Store UI image assets in `assets/images/`.

## 4. Development Rules

- Write code comments in clear, easy-to-understand Thai.
- Preserve the existing BLoC and Clean Architecture approach. Do not introduce a competing state-management pattern.
- Prefer shared, reusable widgets for behavior or layouts used by more than one page.

## 5. Current Status and Next Steps

- The current focus is the Flutter frontend written in Dart.
- The authentication frontend has been implemented.

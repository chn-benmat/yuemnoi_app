# Project Context: Yuemnoi App

## 1. Overview

- This application is a C2C equipment rental platform managing equipment rentals, returns, real-time messaging, wallet payments, location tracking, and an AI assistant.

## 2. Tech Stack

- Language: Dart
- Framework: Flutter
- State Management: `flutter_bloc` (BLoC / Cubit), `equatable`
- Navigation: `go_router`
- Networking: `dio` (Go Backend REST API), `supabase_flutter` (Auth, Realtime streams, Storage)
- Push Notifications: `firebase_messaging`, `flutter_local_notifications`
- Maps & Geolocation: `flutter_map`, `latlong2`, `geolocator`
- Code Generation: `build_runner`, `json_serializable`
- External Services:
  - Database, Auth & Realtime: Supabase
  - Core Backend: Go (Gin, Hexagonal Architecture)
  - AI Assistant Service: Python (FastAPI)

## 3. Architecture and File Structure

- `lib/` is the root directory for application source code.
  - `main.dart` is the application entry point. Keep startup and dependency initialization here.
  - `app.dart` contains the root application widget and app-level lifecycle or configuration.
- `lib/core/` contains shared, feature-independent application functionality.
  - `config/`: Application-wide environment and runtime configuration.
  - `constants/`: Global constant values (e.g., `colors.dart`). Do not put mutable state here.
  - `errors/`: Shared exceptions and failures used to communicate errors across layers.
  - `navigation/`: Route definitions (`app_routes.dart`), deep link handling, and app-wide navigation helpers.
  - `network/`: Dio API client (`api_client.dart`), Supabase client wrapper, and auth session management.
  - `services/`: Singleton and global application services (FCM, location, presence, permissions, sound/media, booking confirmation trackers).
  - `theme/`: Theme configuration, typography (`Prompt` font), and design tokens.
  - `utils/`: Reusable, feature-independent technical transformations and helpers (such as image compression, formatting). Keep utilities stateless.
  - `widgets/`: Feature-independent widgets reusable across multiple pages or features (`core/widgets/`).
- `lib/features/` contains feature modules (`auth`, `booking`, `chat`, `chatbot`, `home`, `item_detail`, `payment`, `profile`, `rental_item`, `wallet`).
  - Follow Clean Architecture within each feature:
    - `<feature>/data/`: handles external and local data.
      - `datasources/`: connects directly to REST APIs, Supabase, or local storage.
      - `models/`: DTOs matching API or database responses, converting to domain entities via `toEntity()`.
      - `repositories/`: implementations of repository interfaces defined by the domain layer.
    - `<feature>/domain/`: contains core business logic without dependencies on Flutter or external libraries.
      - `entities/`: domain objects and business models.
      - `repositories/`: interfaces and contracts for required data operations.
      - `usecases/`: application use cases coordinating business rules and repository operations.
    - `<feature>/presentation/`: user interface and presentation state.
      - `bloc/`: BLoCs / Cubits, events, and states for state management.
      - `pages/`: application screens and route-level widgets.
      - `widgets/`: widgets used specifically within that feature.
- UI image assets and media:
  - `assets/images/`: Images and illustrations.
  - `assets/icons/`: Icon assets.
  - `assets/sounds/`: Notification and alert sound files.
  - `assets/fonts/`: Prompt font files.

## 4. Development Rules

- Write code comments in clear, easy-to-understand Thai.
- Preserve the existing BLoC/Cubit and Clean Architecture approach. Do not introduce a competing state-management pattern.
- Do not modify, redesign, or alter existing UI/UX layouts, styling, screens, or components unless explicitly requested by the user. When implementing new logic, connecting APIs, or integrating features, keep the existing UI design intact.
- Before writing a widget, field decoration, button style, or repeated layout, search the feature's `presentation/widgets/`, `core/widgets/`, and `core/theme/` for an existing implementation.
- Reuse or extend an existing shared widget with backward-compatible options when the same feature-independent UI behavior is needed. Keep the shared visual logic in one source of truth instead of recreating it in pages.
- Place UI that is reusable only inside one feature in that feature's `presentation/widgets/`. Promote it to `core/widgets/` only when it is feature-independent and reused across pages or features.
- When modifying models with `@JsonSerializable`, always run `dart run build_runner build --delete-conflicting-outputs`.
- Support Guest browsing where applicable; enforce authentication checks and display the login dialog before sensitive mutations (e.g., requesting rental, chatting, listing items, wallet transactions).
- Maintain unit and widget tests under `test/features/<feature>/` and `test/core/` when adding or refactoring business logic.

## 5. Backend vs Frontend Architecture & Supabase Security

To maintain security, data integrity, and scalability, follow the **Hybrid Architecture** guidelines:

### 5.1 Backend Responsibilities (Go Backend via REST API)
- **Core CRUD & Business Logic**: All product/item feeds, item creation, updates, and rental transactions must route through Go backend APIs (`/api/items`, `/api/rentals`).
- **AI Chatbot Gateway**: AI queries and streaming route through `/api/chat-ai` and `/api/chat-ai/stream`, which coordinates with the Python AI service.
- **Sensitive User Data & Authorization**: Profile updates, contact phone number lookup (`/api/chat/contact`), KYC verifications, and FCM token synchronization (`profile_tb`) must be processed and validated through the Go backend to enforce strict authorization and prevent direct client-side table leaks.
- **Server-Side Image & Data Validation**: Multi-table joins, pagination, input validation, search ranking, and media storage coordination should be handled by the backend rather than in-memory client joins.

### 5.2 Frontend Direct Supabase Usage (Realtime & Client SDK)
- **Supabase Realtime Streams**: Live chat messaging streams (`chat_room:*`), typing indicators, and presence tracking may connect directly via Supabase WebSockets for optimal low latency.
- **Client Auth Lifecycle**: Supabase Auth client handles Google OAuth (PKCE), session restore, and token refreshing.
- **Direct Client Storage**: Permitted only for low-risk realtime chat attachments with appropriate RLS policies.

### 5.3 Security Rules for Agents
- Do NOT perform raw SQL queries or direct client-side table joins on sensitive tables (`profile_tb`, `review_tb`, cross-user data) in Flutter when a backend endpoint is available or appropriate.
- All mutating business transactions must include the Bearer JWT token in the `Authorization` header when calling Go backend endpoints.

## 6. Current Status and Next Steps

- **Implemented Features**:
  - **Auth & Guest Mode**: Email/Password, Google OAuth, guest browsing mode with login guards on interactive actions.
  - **Home & Discovery Feed**: Item recommendation feed (popularity + recency + category balancing), search, category filters, and skeleton animations.
  - **Item Management**: Item listing/editing, multi-category selection, image picking with compression.
  - **Rental Lifecycle**: Rental booking requests, payment deduction, handover confirmation modal, return modal, tracking map with distance calculation, and reviews.
  - **Payment & Wallet**: Wallet balance, top-up, payment deduction, and transaction history.
  - **Communication**: Supabase Realtime chat with media attachments and storage cleanup; AI Chatbot with SSE streaming, message editing, and user feedback.
  - **Background & Push Services**: FCM push notifications (foreground & background), notification action routing, and user presence tracking.
- **Testing**:
  - Unit and widget tests are set up across all 10 feature modules in `test/features/` and `test/core/`.

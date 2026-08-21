# Graph Report - .  (2026-08-21)

## Corpus Check
- 97 files · ~131,554 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 860 nodes · 1002 edges · 43 communities detected
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 15 edges (avg confidence: 0.85)
- Token cost: 165,195 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Device Identity & Core Services|Device Identity & Core Services]]
- [[_COMMUNITY_Employee Terminal Charge Flow|Employee Terminal Charge Flow]]
- [[_COMMUNITY_Graphify Meta & Compliance Audit Log|Graphify Meta & Compliance Audit Log]]
- [[_COMMUNITY_Kiosk Screen UI|Kiosk Screen UI]]
- [[_COMMUNITY_App Entry & Theming|App Entry & Theming]]
- [[_COMMUNITY_Kiosk Background & Connectivity|Kiosk Background & Connectivity]]
- [[_COMMUNITY_Settings Panes & Navigation|Settings Panes & Navigation]]
- [[_COMMUNITY_Customer Display Bridge|Customer Display Bridge]]
- [[_COMMUNITY_Fiscal Reports Pane|Fiscal Reports Pane]]
- [[_COMMUNITY_Production Audit Findings|Production Audit Findings]]
- [[_COMMUNITY_Thermal Printer Receipt|Thermal Printer Receipt]]
- [[_COMMUNITY_Addon Picker Sheet|Addon Picker Sheet]]
- [[_COMMUNITY_About Pane|About Pane]]
- [[_COMMUNITY_SoftPay Android Plugin|SoftPay Android Plugin]]
- [[_COMMUNITY_Order Status Display Board|Order Status Display Board]]
- [[_COMMUNITY_Kiosk Background Video Widget|Kiosk Background Video Widget]]
- [[_COMMUNITY_Dev Setup & Build Commands|Dev Setup & Build Commands]]
- [[_COMMUNITY_Convex Backend Migration Plan|Convex Backend Migration Plan]]
- [[_COMMUNITY_Display Bridge Native Interface|Display Bridge Native Interface]]
- [[_COMMUNITY_Cart & Menu Item Models|Cart & Menu Item Models]]
- [[_COMMUNITY_Display Bridge Android Plugin|Display Bridge Android Plugin]]
- [[_COMMUNITY_Dual Display Launcher (Android)|Dual Display Launcher (Android)]]
- [[_COMMUNITY_SoftPay Client Provider (Android)|SoftPay Client Provider (Android)]]
- [[_COMMUNITY_Dual Display Presentation (Android)|Dual Display Presentation (Android)]]
- [[_COMMUNITY_Order Payment Event Model|Order Payment Event Model]]
- [[_COMMUNITY_SoftPay Models & Exceptions|SoftPay Models & Exceptions]]
- [[_COMMUNITY_Order Model|Order Model]]
- [[_COMMUNITY_Journal Entry Model|Journal Entry Model]]
- [[_COMMUNITY_Fiscal Report Models|Fiscal Report Models]]
- [[_COMMUNITY_Kiosk Background Video Asset|Kiosk Background Video Asset]]
- [[_COMMUNITY_Flutter Plugin Registrant|Flutter Plugin Registrant]]
- [[_COMMUNITY_Main Activity (Android)|Main Activity (Android)]]
- [[_COMMUNITY_TCS Fiscal Result Models|TCS Fiscal Result Models]]
- [[_COMMUNITY_Gradle Local Property Loader|Gradle Local Property Loader]]
- [[_COMMUNITY_Gradle SoftPay Property Loader|Gradle SoftPay Property Loader]]
- [[_COMMUNITY_Device Info Model|Device Info Model]]
- [[_COMMUNITY_Transaction Snapshot Model|Transaction Snapshot Model]]
- [[_COMMUNITY_Device Cart Item Model|Device Cart Item Model]]
- [[_COMMUNITY_Menu Item Addon Model|Menu Item Addon Model]]
- [[_COMMUNITY_Order Item Model|Order Item Model]]
- [[_COMMUNITY_Gradle Settings File|Gradle Settings File]]
- [[_COMMUNITY_App Mode Flavor Constant|App Mode Flavor Constant]]
- [[_COMMUNITY_README Architecture Overview|README Architecture Overview]]

## God Nodes (most connected - your core abstractions)
1. `package:flutter/material.dart` - 32 edges
2. `package:convex_flutter/convex_flutter.dart` - 16 edges
3. `SoftPayPlugin` - 14 edges
4. `DeviceIdentityService` - 14 edges
5. `EmployeeTerminalScreen` - 12 edges
6. `TCS-D Certification Request/Response Log` - 12 edges
7. `dart:async` - 11 edges
8. `DisplayBridge` - 10 edges
9. `dart:convert` - 10 edges
10. `SubscriptionLoadingState Widget` - 9 edges

## Surprising Connections (you probably didn't know these)
- `Centralized Dart Data-Access Layer` --references--> `DeviceIdentityService`  [INFERRED]
  /Users/yashraj/Yashraj/proxie-studio/projects/FlutterApps/NorrOne/pos/plan.md → /Users/yashraj/Yashraj/proxie-studio/projects/FlutterApps/NorrOne/pos/README.md
- `Flutter-Side Convex-Call Timeout Fixes` --implements--> `Bounded Timeout Pattern for Convex Calls`  [EXTRACTED]
  /Users/yashraj/Yashraj/proxie-studio/projects/FlutterApps/NorrOne/pos/plan.md → /Users/yashraj/Yashraj/proxie-studio/projects/FlutterApps/NorrOne/pos/README.md
- `TCS Checklist Cross-Reference` --conceptually_related_to--> `TCS Certification Test Coverage`  [INFERRED]
  /Users/yashraj/Yashraj/proxie-studio/projects/FlutterApps/NorrOne/pos/TCS_Certification_Request_Response_Log.txt → /Users/yashraj/Yashraj/proxie-studio/projects/FlutterApps/NorrOne/pos/README.md
- `Test Case 8: Receipt Copy (Kopia)` --conceptually_related_to--> `One-Copy-Only Kopia Enforcement (SKVFS Ch.6 §3)`  [INFERRED]
  /Users/yashraj/Yashraj/proxie-studio/projects/FlutterApps/NorrOne/pos/TCS_Certification_Request_Response_Log.txt → /Users/yashraj/Yashraj/proxie-studio/projects/FlutterApps/NorrOne/pos/plan.md
- `flutter run/build Flavor Commands` --conceptually_related_to--> `Three Build Flavors`  [INFERRED]
  /Users/yashraj/Yashraj/proxie-studio/projects/FlutterApps/NorrOne/pos/help.txt → /Users/yashraj/Yashraj/proxie-studio/projects/FlutterApps/NorrOne/pos/README.md

## Hyperedges (group relationships)
- **POS Charge, SoftPay, and TCS-D Fiscalization Flow** — readme_employee_terminal_charge_flow, readme_softpay_service, readme_pos_payments_service, readme_order_event_outbox, readme_tcs_d_fiscalization [EXTRACTED 1.00]
- **Receipt Redesign Followed By Currency Bug Fix** — plan_receipt_redesign_changelog, plan_skvfs_ch7_missing_fields, plan_currency_kr_leak_bug, plan_display_vs_payment_currency_split, readme_currency_split_rationale [EXTRACTED 1.00]
- **Backend Unification: Devices, Data Layer, Retirement** — plan_unify_backend_plan, plan_devices_table, plan_centralized_dart_data_layer, plan_kds_pos_backend_retirement, readme_device_identity_service [EXTRACTED 1.00]

## Communities

### Community 0 - "Device Identity & Core Services"

Cohesion: 0.02
Nodes (98): ../Core/app_mode.dart, ../../Core/connectivity/connectivity_service.dart, ../Core/theme/theme_controller.dart, dart:async, dart:convert, dart:io, device_hardware.dart, ../device_identity_service.dart (+90 more)

### Community 1 - "Employee Terminal Charge Flow"

Cohesion: 0.02
Nodes (87): ../../../Database/models/transaction_snapshot.dart, error_state.dart, build, _CartLine, Column, ConnectivityBanner, _decrementLine, didChangeDependencies (+79 more)

### Community 2 - "Graphify Meta & Compliance Audit Log"

Cohesion: 0.04
Nodes (85): Graphify Project Rules, Graphify Interactive Graph Visualization, Graphify GRAPH_REPORT Summary, Graph Report Community Hubs (Navigation), Graph Report God Nodes, Abandoned Device-Order Cancellation Cron Fix, High: Transient Fiscalization Failure Costs Original Receipt, Auto-Refund on Unconfirmed Fiscalization (Ch.4 §9) (+77 more)

### Community 3 - "Kiosk Screen UI"

Cohesion: 0.03
Nodes (68): kiosk_screen.dart, _AddToCartPill, AnimatedSwitcher, _AreYouStillThereDialog, _AreYouStillThereDialogState, build, _buildBody, Center (+60 more)

### Community 4 - "App Entry & Theming"

Cohesion: 0.03
Nodes (55): app_colors.dart, customer_app.dart, package:flutter/material.dart, package:flutter_svg/flutter_svg.dart, package:flutter_test/flutter_test.dart, package:kds_pos/app.dart, package:kds_pos/Core/app_mode.dart, package:kds_pos/Core/connectivity/connectivity_service.dart (+47 more)

### Community 5 - "Kiosk Background & Connectivity"

Cohesion: 0.05
Nodes (42): kiosk_background_video.dart, kiosk_menu_screen.dart, package:kds_pos/Core/theme/app_colors.dart, package:kds_pos/Widgets/connectivity_banner.dart, build, ColoredBox, ConnectivityBanner, Container (+34 more)

### Community 6 - "Settings Panes & Navigation"

Cohesion: 0.05
Nodes (39): About/about_pane.dart, customer_display_screen.dart, FiscalReports/fiscal_reports_pane.dart, Journal/journal_pane.dart, package:kds_pos/Core/navigation/route_observer.dart, package:kds_pos/Core/theme/app_theme.dart, package:kds_pos/Core/theme/theme_controller.dart, package:kds_pos/Database/pairing_screen.dart (+31 more)

### Community 7 - "Customer Display Bridge"

Cohesion: 0.05
Nodes (38): customer_display_bridge.dart, dart:math, ../../../Database/models/cart_entry.dart, ../../../Database/models/menu_item.dart, ../EmployeeTerminal/error_state.dart, ../EmployeeTerminal/softpay_models.dart, ../EmployeeTerminal/softpay_service.dart, package:flutter/services.dart (+30 more)

### Community 8 - "Fiscal Reports Pane"

Cohesion: 0.06
Nodes (32): fiscal_report_models.dart, journal_entry.dart, build, Card, Column, dispose, FiscalReportsPane, _FiscalReportsPaneState (+24 more)

### Community 9 - "Production Audit Findings"

Cohesion: 0.09
Nodes (31): Bugsink DSN for Error Reporting, Blocker: Release APK Signed with Debug Keystore, Blocker: No Per-Restaurant Fiscal Identity Override, High: Observability Only Covers SoftPay Failures, Medium: Silent Sandbox Fallback, Medium: SOFTPAY_INTEGRATOR_SECRET Hardcoded Fallback, BETTER_AUTH_SECRET Hardcoded Fallback Risk, Full Compliance + Operational Sweep (2026-08-20) (+23 more)

### Community 10 - "Thermal Printer Receipt"

Cohesion: 0.09
Nodes (22): dart:typed_data, dart:ui, _formatCents, _formatDateTime, Function, onDefPrinter, pad, PrinterException (+14 more)

### Community 11 - "Addon Picker Sheet"

Cohesion: 0.09
Nodes (21): package:kds_pos/Database/models/menu_item_addon.dart, package:kds_pos/Database/models/menu_item.dart, _AddonPickerSheet, _AddonPickerSheetState, AddonSelection, _AddonTile, build, Container (+13 more)

### Community 12 - "About Pane"

Cohesion: 0.09
Nodes (20): package:kds_pos/Database/device_identity_service.dart, package:package_info_plus/package_info_plus.dart, AboutPane, _AboutPaneState, build, Card, Center, _InfoRow (+12 more)

### Community 13 - "SoftPay Android Plugin"

Cohesion: 0.13
Nodes (1): SoftPayPlugin

### Community 14 - "Order Status Display Board"

Cohesion: 0.13
Nodes (14): ../../Database/models/order.dart, ../../Database/repositories/order_repository.dart, _Board, build, _Column, Container, dispose, initState (+6 more)

### Community 15 - "Kiosk Background Video Widget"

Cohesion: 0.13
Nodes (14): ../../Database/device_identity_service.dart, ../../Database/remote_asset_cache.dart, package:video_player/video_player.dart, AnimatedBuilder, build, ClipRect, ConstrainedBox, DecoratedBox (+6 more)

### Community 16 - "Dev Setup & Build Commands"

Cohesion: 0.14
Nodes (14): claude --resume Session ID, help.txt Dev Notes (SoftPay Login, Run Commands, Resume ID, Bugsink DSN), flutter run/build Flavor Commands, SoftPay Developer Portal Login, appMode Constant, Build Setup & Known Issues, Self-Hosted Convex Deployment Config, convex_flutter 3.0.1 Cargokit/Gradle Patch Requirement (+6 more)

### Community 17 - "Convex Backend Migration Plan"

Cohesion: 0.15
Nodes (13): Centralized Dart Data-Access Layer, orders.createDeviceOrder Mutation, deviceAuthz.ts (deviceQuery/deviceMutation), Device Token Hash-Only Storage Rationale, devices Table Schema Addition, devices.ts Staff/Device Functions, Suggested Implementation Order, kds_pos_backend Retirement (+5 more)

### Community 18 - "Display Bridge Native Interface"

Cohesion: 0.18
Nodes (1): DisplayBridge

### Community 19 - "Cart & Menu Item Models"

Cohesion: 0.18
Nodes (8): device_cart_item.dart, menu_item_addon.dart, menu_item.dart, CartEntry, copyWith, toDeviceCartItem, MenuCategory, MenuItem

### Community 20 - "Display Bridge Android Plugin"

Cohesion: 0.2
Nodes (2): DisplayBridgePlugin, DisplayBridgeRole

### Community 21 - "Dual Display Launcher (Android)"

Cohesion: 0.29
Nodes (1): DualDisplayLauncher

### Community 22 - "SoftPay Client Provider (Android)"

Cohesion: 0.4
Nodes (1): SoftPayClientProvider

### Community 23 - "Dual Display Presentation (Android)"

Cohesion: 0.4
Nodes (1): CustomerDisplayPresentation

### Community 24 - "Order Payment Event Model"

Cohesion: 0.4
Nodes (4): transaction_snapshot.dart, ArgumentError, OrderPaymentEvent, _typeFromJson

### Community 25 - "SoftPay Models & Exceptions"

Cohesion: 0.4
Nodes (4): PaymentStatusUpdate, SoftPayException, toString, TransactionResult

### Community 26 - "Order Model"

Cohesion: 0.5
Nodes (3): order_item.dart, order_payment_event.dart, Order

### Community 27 - "Journal Entry Model"

Cohesion: 0.5
Nodes (3): ArgumentError, JournalEntry, _kindFromJson

### Community 28 - "Fiscal Report Models"

Cohesion: 0.5
Nodes (3): FiscalReport, PaymentMethodTotal, VatBreakdownEntry

### Community 29 - "Kiosk Background Video Asset"

Cohesion: 0.5
Nodes (4): Kiosk Background Video Placeholder Instructions, KioskBackgroundVideo, kiosk_screen.dart, RemoteAssetCache

### Community 30 - "Flutter Plugin Registrant"

Cohesion: 0.67
Nodes (1): GeneratedPluginRegistrant

### Community 31 - "Main Activity (Android)"

Cohesion: 0.67
Nodes (1): MainActivity

### Community 32 - "TCS Fiscal Result Models"

Cohesion: 0.67
Nodes (2): TcsResult, TcsVatBand

### Community 33 - "Gradle Local Property Loader"

Cohesion: 1.0
Nodes (0): 

### Community 34 - "Gradle SoftPay Property Loader"

Cohesion: 1.0
Nodes (0): 

### Community 35 - "Device Info Model"

Cohesion: 1.0
Nodes (1): DeviceInfo

### Community 36 - "Transaction Snapshot Model"

Cohesion: 1.0
Nodes (1): TransactionSnapshot

### Community 37 - "Device Cart Item Model"

Cohesion: 1.0
Nodes (1): DeviceCartItem

### Community 38 - "Menu Item Addon Model"

Cohesion: 1.0
Nodes (1): MenuItemAddon

### Community 39 - "Order Item Model"

Cohesion: 1.0
Nodes (1): OrderItem

### Community 40 - "Gradle Settings File"

Cohesion: 1.0
Nodes (0): 

### Community 41 - "App Mode Flavor Constant"

Cohesion: 1.0
Nodes (0): 

### Community 42 - "README Architecture Overview"

Cohesion: 1.0
Nodes (1): Architecture at a Glance

## Knowledge Gaps
- **577 isolated node(s):** `main`, `package:flutter_test/flutter_test.dart`, `DisplayBridgeRole`, `package:kds_pos/Database/convex_client.dart`, `package:kds_pos/Database/repositories/order_event_outbox.dart` (+572 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Gradle Local Property Loader`** (2 nodes): `localProperty()`, `build.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Gradle SoftPay Property Loader`** (2 nodes): `softpayProperty()`, `build.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Device Info Model`** (2 nodes): `device_info.dart`, `DeviceInfo`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Transaction Snapshot Model`** (2 nodes): `transaction_snapshot.dart`, `TransactionSnapshot`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Device Cart Item Model`** (2 nodes): `device_cart_item.dart`, `DeviceCartItem`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Menu Item Addon Model`** (2 nodes): `menu_item_addon.dart`, `MenuItemAddon`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Order Item Model`** (2 nodes): `order_item.dart`, `OrderItem`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Gradle Settings File`** (1 nodes): `settings.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `App Mode Flavor Constant`** (1 nodes): `app_mode.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `README Architecture Overview`** (1 nodes): `Architecture at a Glance`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `package:flutter/material.dart` connect `App Entry & Theming` to `Device Identity & Core Services`, `Employee Terminal Charge Flow`, `Kiosk Screen UI`, `Kiosk Background & Connectivity`, `Settings Panes & Navigation`, `Customer Display Bridge`, `Fiscal Reports Pane`, `Addon Picker Sheet`, `About Pane`, `Order Status Display Board`, `Kiosk Background Video Widget`?**
  _High betweenness centrality (0.266) - this node is a cross-community bridge._
- **Why does `package:convex_flutter/convex_flutter.dart` connect `Device Identity & Core Services` to `Fiscal Reports Pane`, `Employee Terminal Charge Flow`, `Kiosk Screen UI`, `Order Status Display Board`?**
  _High betweenness centrality (0.092) - this node is a cross-community bridge._
- **Why does `dart:async` connect `Device Identity & Core Services` to `Employee Terminal Charge Flow`, `Kiosk Screen UI`, `Customer Display Bridge`?**
  _High betweenness centrality (0.056) - this node is a cross-community bridge._
- **What connects `main`, `package:flutter_test/flutter_test.dart`, `DisplayBridgeRole` to the rest of the system?**
  _577 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Device Identity & Core Services` be split into smaller, more focused modules?**
  _Cohesion score 0.02 - nodes in this community are weakly interconnected._
- **Should `Employee Terminal Charge Flow` be split into smaller, more focused modules?**
  _Cohesion score 0.02 - nodes in this community are weakly interconnected._
- **Should `Graphify Meta & Compliance Audit Log` be split into smaller, more focused modules?**
  _Cohesion score 0.04 - nodes in this community are weakly interconnected._
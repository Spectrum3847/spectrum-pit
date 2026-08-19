import 'dart:async' show unawaited;

import 'package:firebase_core/firebase_core.dart';
import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';
import 'src/app.dart';
import 'src/services/borrow_sync_service.dart';
import 'src/services/container_photo_sync_service.dart';
import 'src/services/desktop_auth_service.dart';
import 'src/services/desktop_borrow_sync_service.dart';
import 'src/services/desktop_container_photo_sync_service.dart';
import 'src/services/desktop_inventory_sync_service.dart';
import 'src/services/desktop_map_diagram_sync_service.dart';
import 'src/services/desktop_map_location_sync_service.dart';
import 'src/services/desktop_packing_sync_service.dart';
import 'src/services/desktop_pit_shift_sync_service.dart';
import 'src/services/desktop_firestore_cache_stub.dart'
    if (dart.library.io) 'src/services/desktop_firestore_cache_io.dart'
    as firestore_cache_factory;
import 'src/services/desktop_user_role_service.dart';
import 'src/services/inventory_sync_service.dart';
import 'src/services/local_only_services.dart';
import 'src/services/issue_report_service.dart';
import 'src/services/map_image_store.dart';
import 'src/services/map_diagram_sync_service.dart';
import 'src/services/map_location_sync_service.dart';
import 'src/services/packing_sync_service.dart';
import 'src/services/photo_disk_cache.dart';
import 'src/services/photo_service.dart';
import 'src/services/synced_map_image_store.dart';
import 'src/services/pit_shift_sync_service.dart';
import 'src/services/telemetry_service.dart';
import 'src/services/http_timeout_client.dart';
import 'src/services/spectrum_auth_service.dart';
import 'src/services/user_role_service.dart';
import 'src/services/user_role_service_interface.dart';
import 'src/services/web_auth_domain.dart';
import 'src/state/borrow_controller.dart';
import 'src/state/inventory_controller.dart';
import 'src/state/map_location_controller.dart';
import 'src/state/packing_controller.dart';
import 'src/state/pit_shift_controller.dart';
import 'src/state/theme_controller.dart';
import 'src/state/user_role_controller.dart';

const String _oauthClientId = String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');

const String _oauthClientSecret = String.fromEnvironment(
  'GOOGLE_OAUTH_CLIENT_SECRET',
);

bool get _isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var firebaseReady = false;
  try {
    final options = kIsWeb
        ? webFirebaseOptionsForHost(
            Uri.base.host,
            DefaultFirebaseOptions.currentPlatform,
          )
        : DefaultFirebaseOptions.currentPlatform;
    await Firebase.initializeApp(options: options);
    firebaseReady = true;
  } catch (error) {
    debugPrint('Firebase unavailable: $error');
  }

  final SpectrumAuthService authService;
  final UserRoleService roleService;
  final InventorySyncService inventorySyncService;
  final PackingSyncService packingSyncService;
  final BorrowSyncService borrowSyncService;
  final MapLocationSyncService mapLocationSyncService;
  final MapDiagramSyncService mapDiagramSyncService;
  final ContainerPhotoSyncService containerPhotoSyncService;
  final PitShiftSyncService pitShiftSyncService;
  IssueReportService? issueReportService;
  TelemetryService? telemetryService;

  if (firebaseReady && !_isDesktop) {
    authService = FirebaseSpectrumAuthService();
    roleService = FirestoreUserRoleService();
    inventorySyncService = FirestoreInventorySyncService();
    packingSyncService = FirestorePackingSyncService();
    borrowSyncService = FirestoreBorrowSyncService();
    mapLocationSyncService = FirestoreMapLocationSyncService();
    mapDiagramSyncService = FirestoreMapDiagramSyncService();
    containerPhotoSyncService = FirestoreContainerPhotoSyncService();
    pitShiftSyncService = FirestorePitShiftSyncService();
    telemetryService = TelemetryService();
  } else if (_isDesktop && _oauthClientId.isNotEmpty) {
    final desktopAuth = DesktopAuthService(
      clientId: _oauthClientId,
      clientSecret: _oauthClientSecret,
      firebaseApiKey: DefaultFirebaseOptions.web.apiKey,
      launch: (url) => launchUrl(url, mode: LaunchMode.externalApplication),
    );

    final restFirestore = fc.Firestore(
      projectId: DefaultFirebaseOptions.web.projectId,
      idTokenProvider: desktopAuth.idToken,

      httpClient: TimeoutHttpClient(),
      cache: await firestore_cache_factory.createDesktopFirestoreCache(
        () => desktopAuth.currentUser?.uid,
      ),
    );

    desktopAuth.onSessionEnded =
        firestore_cache_factory.clearDesktopFirestoreCacheFor;
    authService = desktopAuth;
    roleService = DesktopUserRoleService(firestore: restFirestore);
    inventorySyncService = DesktopInventorySyncService(
      firestore: restFirestore,
    );
    packingSyncService = DesktopPackingSyncService(firestore: restFirestore);
    borrowSyncService = DesktopBorrowSyncService(firestore: restFirestore);
    mapLocationSyncService = DesktopMapLocationSyncService(
      firestore: restFirestore,
    );
    mapDiagramSyncService = DesktopMapDiagramSyncService(
      firestore: restFirestore,
    );
    containerPhotoSyncService = DesktopContainerPhotoSyncService(
      firestore: restFirestore,
    );
    pitShiftSyncService = DesktopPitShiftSyncService(firestore: restFirestore);

    issueReportService = IssueReportService(
      write: (path, data) => restFirestore.setDocument(path, data),
    );

    telemetryService = TelemetryService(
      write: (path, data) => restFirestore.setDocument(path, data),
    );
  } else {
    authService = LocalOnlyAuthService();
    roleService = LocalUserRoleService();
    inventorySyncService = LocalInventorySyncService();
    packingSyncService = LocalPackingSyncService();
    borrowSyncService = LocalBorrowSyncService();
    mapLocationSyncService = LocalMapLocationSyncService();
    mapDiagramSyncService = LocalMapDiagramSyncService();
    containerPhotoSyncService = LocalContainerPhotoSyncService();
    pitShiftSyncService = LocalPitShiftSyncService();
  }

  final themeController = ThemeController();
  final userRoleController = UserRoleController(
    authService: authService,
    roleService: roleService,
  );
  final inventoryController = InventoryController(
    authService: authService,
    syncService: inventorySyncService,
  );
  final packingController = PackingController(
    authService: authService,
    syncService: packingSyncService,
  );
  final borrowController = BorrowController(
    authService: authService,
    syncService: borrowSyncService,
  );
  final mapLocationController = MapLocationController(
    authService: authService,
    syncService: mapLocationSyncService,
  );
  final pitShiftController = PitShiftController(
    authService: authService,
    syncService: pitShiftSyncService,
  );

  final photoService = PhotoService(
    idToken: authService.idToken,
    diskCache: PhotoDiskCache(),
  );

  final MapImageStore mapImageStore;
  if ((firebaseReady && !_isDesktop) ||
      (_isDesktop && _oauthClientId.isNotEmpty)) {
    mapImageStore = SyncedMapImageStore(
      photoService: photoService,
      diagramSync: mapDiagramSyncService,
    );
  } else {
    mapImageStore = LocalMapImageStore();
  }

  final telemetry = telemetryService;
  if (telemetry != null) {
    unawaited(telemetry.logEvent('app_open'));
  }

  runApp(
    StrategyApp(
      authService: authService,
      themeController: themeController,
      userRoleController: userRoleController,
      inventoryController: inventoryController,
      packingController: packingController,
      borrowController: borrowController,
      mapLocationController: mapLocationController,
      mapImageStore: mapImageStore,
      containerPhotoSyncService: containerPhotoSyncService,
      photoService: photoService,
      pitShiftController: pitShiftController,
      issueReportService: issueReportService,
      telemetryService: telemetryService,
    ),
  );
}

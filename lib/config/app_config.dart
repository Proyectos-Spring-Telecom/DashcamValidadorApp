/// Configuración centralizada de la aplicación
/// Contiene URLs, timeouts y otras constantes de configuración
class AppConfig {
  // URLs de la API
  static const String apiBaseUrl = 'https://dashcampay.com/apipay';
  static const String localDeviceApiUrl = 'http://localhost:8080';
  static const int localDeviceApiPort = 8080;

  // Timeouts para peticiones HTTP
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);

  // Timeouts para servicios locales del dispositivo
  static const Duration localDeviceTimeout = Duration(seconds: 5);
  static const Duration nfcReadTimeout = Duration(seconds: 3);
  static const Duration nfcCardReadTimeout = Duration(seconds: 10); // Timeout para lectura de tarjeta NFC

  // Configuración de reintentos
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(milliseconds: 500);

  // Configuración de código
  static const List<int> allowedCodigoLengths = [6, 8];
  static const int defaultCodigoLength = 6;

  // Configuración de GPS
  static const double maxGpsAccuracy = 500.0; // metros
  static const double maxGpsJumpDistance = 1000.0; // metros
  static const Duration positionSendInterval = Duration(minutes: 3); // Intervalo para enviar posiciones GPS
  static const Duration positionInitialDelay = Duration(seconds: 5); // Delay inicial antes de enviar primera posición

  // Configuración de Tarifa Dinámica
  static const double dynamicFareBase = 16.0; // Tarifa base por el primer kilómetro (pesos)
  static const double dynamicFareFirstKilometer = 1000.0; // Primer kilómetro en metros
  static const double dynamicFareIncrementDistance = 100.0; // Incremento cada X metros
  static const double dynamicFareIncrementAmount = 1.0; // Incremento de tarifa (pesos)

  // Configuración de splash screen
  static const Duration minSplashDuration = Duration(seconds: 2);
  static const Duration maxSplashDuration = Duration(seconds: 5);

  // Configuración de caché
  static const Duration defaultCacheDuration = Duration(minutes: 5);

  // Headers por defecto
  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
  };

  // Endpoints de la API
  static const String endpointLogin = '/login';
  static const String endpointLoginWithPin = '/login/operador/login';
  static const String endpointLoginMe = '/login/me';
  static const String endpointLoginRefresh = '/login/refresh';
  static const String endpointUpdateValidador = '/usuarios/actualizar/validador';
  static const String endpointGeneratePin = '/usuarios/generar/pin';
  static const String endpointListOperadores = '/usuarios/list/rol/operador'; // GET /usuarios/list/rol/operador/{cliente}
  static const String endpointPositions = '/posiciones';
  static const String endpointWalletBySerie = '/monederos/numero/serie';
  static const String endpointPassenger = '/pasajeros';
  static const String endpointDebitTransaction = '/transacciones/debito';
  static const String endpointDebitTransactionUpdate = '/transacciones/debito'; // PATCH para actualizar transacción

  // Endpoints del API para turnos
  static const String startTurn = '/turnos';
  static const String endpointStartTurn = '/turnos';
  static const String endpointEndTurn = '/turnos/';
  static const String endTurn = '/turnos/{id}';


  // Endpoints del API para viajes
  static const String startTrip = '/viajes';
  static const String endpointStartTrip = '/viajes';
  static const String endpointEndTrip = '/viajes/';
  static const String endTrip = '/viajes/{id}';

  // Endpoints recargar monedero
  static const String endpointRechargeWallet = '/transacciones/recarga';

  //endpoints del api actividad
  static const String endpointActivity = '/viajes/viajes-ultima-semana/';

  //endpoints del api para zonas
  static const String endpointListZones = '/zonas/list';

 //endpoint del api para  rutas
 static const String endpointListRoads = '/rutas/by-zona/{idZona}';

 //endpoint del api para variantes
 static const String endpointListVariants = '/variantes/by-ruta/{idRuta}';

  // Prevenir instanciación
  AppConfig._();
}


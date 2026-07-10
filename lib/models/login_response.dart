class LoginResponse {
  final String message;
  final int id;
  final String nombre;
  final String apellidoPaterno;
  final String apellidoMaterno;
  final int idCliente;
  final String nombreCliente;
  final String apellidoPaternoCliente;
  final String apellidoMaternoCliente;
  final String telefono;
  final String ultimoLogin;
  final String fechaCreacion;
  final String fotoPerfil;
  final String userName;
  final UserRole rol;
  /// Token JWT (opcional en `/login/me`; llega de login y se inyecta al parsear).
  final String token;
  final String refreshToken;
  final List<UserPermission> permisos;
  final String? fechaNacimiento;
  final String? identificacion;
  final String? comprobanteDomicilioOperador;
  final String? certificadoMedicoOperador;
  final String? antecedentesNoPenalesOperador;
  final int estatusOperador;
  final String? logotipo;
  final String? deviceId;
  final int pinExist;
  final List<UserLicense> licencias;
  /// Validador ID (numeroSerieValidador) - guardado desde login
  final String? validadorId;
  /// ID del turno activo - null si no hay turno
  final String? idTurno;
  /// ID del viaje activo
  final String? idViaje;

  LoginResponse({
    required this.message,
    required this.id,
    required this.nombre,
    required this.apellidoPaterno,
    required this.apellidoMaterno,
    required this.idCliente,
    required this.nombreCliente,
    required this.apellidoPaternoCliente,
    required this.apellidoMaternoCliente,
    required this.telefono,
    required this.ultimoLogin,
    required this.fechaCreacion,
    required this.fotoPerfil,
    required this.userName,
    required this.rol,
    this.token = '',
    this.refreshToken = '',
    required this.permisos,
    this.fechaNacimiento,
    this.identificacion,
    this.comprobanteDomicilioOperador,
    this.certificadoMedicoOperador,
    this.antecedentesNoPenalesOperador,
    this.estatusOperador = 0,
    this.logotipo,
    this.deviceId,
    this.pinExist = 0,
    this.licencias = const [],
    this.validadorId,
    this.idTurno,
    this.idViaje,
  });

  /// Parsea la respuesta de `/login/me` (perfil de sesión).
  /// [token] y [refreshToken] se pasan desde el login previo.
  factory LoginResponse.fromJson(
    Map<String, dynamic> json, {
    String token = '',
    String refreshToken = '',
  }) {
    return LoginResponse(
      message: json['message'] ?? '',
      id: json['id'] ?? 0,
      nombre: json['nombre'] ?? '',
      apellidoPaterno: json['apellidoPaterno'] ?? '',
      apellidoMaterno: json['apellidoMaterno'] ?? '',
      idCliente: json['idCliente'] ?? 0,
      nombreCliente: json['nombreCliente'] ?? '',
      apellidoPaternoCliente: json['apellidoPaternoCliente'] ?? '',
      apellidoMaternoCliente: json['apellidoMaternoCliente'] ?? '',
      telefono: json['telefono'] ?? '',
      ultimoLogin: json['ultimoLogin'] ?? '',
      fechaCreacion: json['fechaCreacion'] ?? '',
      fotoPerfil: json['fotoPerfil'] ?? '',
      userName: json['userName'] ?? '',
      rol: UserRole.fromJson(json['rol'] ?? {}),
      token: token.isNotEmpty ? token : (json['token']?.toString() ?? ''),
      refreshToken: refreshToken.isNotEmpty
          ? refreshToken
          : (json['refreshToken']?.toString() ?? ''),
      permisos: (json['permisos'] as List<dynamic>?)
              ?.map((p) => UserPermission.fromJson(p))
              .toList() ??
          [],
      fechaNacimiento: json['fechaNacimiento'],
      identificacion: json['identificacion'],
      comprobanteDomicilioOperador: json['comprobanteDomicilioOperador'],
      certificadoMedicoOperador: json['certificadoMedicoOperador'],
      antecedentesNoPenalesOperador: json['antecedentesNoPenalesOperador'],
      estatusOperador: json['estatusOperador'] ?? 0,
      logotipo: json['logotipo'],
      deviceId: json['deviceId'],
      pinExist: json['pinExist'] ?? 0,
      licencias: (json['Licencias'] as List<dynamic>?)
              ?.map((l) => UserLicense.fromJson(l))
              .toList() ??
          [],
      validadorId: json['validadorId']?.toString(),
      idTurno: json['idTurno']?.toString(),
      idViaje: json['idViaje']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'message': message,
      'id': id,
      'nombre': nombre,
      'apellidoPaterno': apellidoPaterno,
      'apellidoMaterno': apellidoMaterno,
      'idCliente': idCliente,
      'nombreCliente': nombreCliente,
      'apellidoPaternoCliente': apellidoPaternoCliente,
      'apellidoMaternoCliente': apellidoMaternoCliente,
      'telefono': telefono,
      'ultimoLogin': ultimoLogin,
      'fechaCreacion': fechaCreacion,
      'fotoPerfil': fotoPerfil,
      'userName': userName,
      'rol': rol.toJson(),
      'token': token,
      'refreshToken': refreshToken,
      'permisos': permisos.map((p) => p.toJson()).toList(),
      'fechaNacimiento': fechaNacimiento,
      'identificacion': identificacion,
      'comprobanteDomicilioOperador': comprobanteDomicilioOperador,
      'certificadoMedicoOperador': certificadoMedicoOperador,
      'antecedentesNoPenalesOperador': antecedentesNoPenalesOperador,
      'estatusOperador': estatusOperador,
      'logotipo': logotipo,
      'deviceId': deviceId,
      'pinExist': pinExist,
      'Licencias': licencias.map((l) => l.toJson()).toList(),
      'validadorId': validadorId,
      'idTurno': idTurno,
      'idViaje': idViaje,
    };
  }

  String get nombreCompleto => '$nombre $apellidoPaterno $apellidoMaterno';
  String get nombreClienteCompleto => '$nombreCliente $apellidoPaternoCliente $apellidoMaternoCliente';
  
  /// Verifica si el usuario tiene el rol de Operador
  bool get esOperador => rol.nombre.toLowerCase() == 'operador';
  bool get tieneCodigo => pinExist == 1;
}

class UserRole {
  final String id;
  final String nombre;
  final String descripcion;
  final String fechaCreacion;
  final String fechaActualizacion;
  final int estatus;

  UserRole({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.fechaCreacion,
    required this.fechaActualizacion,
    required this.estatus,
  });

  factory UserRole.fromJson(Map<String, dynamic> json) {
    return UserRole(
      id: json['id']?.toString() ?? '',
      nombre: json['nombre'] ?? '',
      descripcion: json['descripcion'] ?? '',
      fechaCreacion: json['fechaCreacion'] ?? '',
      fechaActualizacion: json['fechaActualizacion'] ?? '',
      estatus: json['estatus'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'descripcion': descripcion,
      'fechaCreacion': fechaCreacion,
      'fechaActualizacion': fechaActualizacion,
      'estatus': estatus,
    };
  }
}

class UserPermission {
  final String idPermiso;

  UserPermission({required this.idPermiso});

  factory UserPermission.fromJson(Map<String, dynamic> json) {
    return UserPermission(
      idPermiso: json['idPermiso']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idPermiso': idPermiso,
    };
  }
}

class UserLicense {
  final String licencia;
  final int idLicencia;
  final int idTipoLicencia;
  final String numeroLicencia;
  final String fechaExpedicion;
  final String fechaVencimiento;
  final int idCategoriaLicencia;

  UserLicense({
    required this.licencia,
    required this.idLicencia,
    required this.idTipoLicencia,
    required this.numeroLicencia,
    required this.fechaExpedicion,
    required this.fechaVencimiento,
    required this.idCategoriaLicencia,
  });

  factory UserLicense.fromJson(Map<String, dynamic> json) {
    return UserLicense(
      licencia: json['Licencia'] ?? '',
      idLicencia: json['IdLicencia'] ?? 0,
      idTipoLicencia: json['IdTipoLicencia'] ?? 0,
      numeroLicencia: json['NumeroLicencia'] ?? '',
      fechaExpedicion: json['FechaExpedicion'] ?? '',
      fechaVencimiento: json['FechaVencimiento'] ?? '',
      idCategoriaLicencia: json['IdCategoriaLicencia'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Licencia': licencia,
      'IdLicencia': idLicencia,
      'IdTipoLicencia': idTipoLicencia,
      'NumeroLicencia': numeroLicencia,
      'FechaExpedicion': fechaExpedicion,
      'FechaVencimiento': fechaVencimiento,
      'IdCategoriaLicencia': idCategoriaLicencia,
    };
  }
}

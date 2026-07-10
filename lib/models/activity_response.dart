/// Modelos para la respuesta del endpoint de actividad

/// Respuesta completa del endpoint de actividad
class ActivityResponse {
  final ActivityData data;

  ActivityResponse({required this.data});

  factory ActivityResponse.fromJson(Map<String, dynamic> json) {
    // Validar que existe el campo 'data'
    if (!json.containsKey('data') || json['data'] == null) {
      throw FormatException('El campo "data" es requerido en ActivityResponse');
    }
    
    final dataJson = json['data'];
    if (dataJson is! Map<String, dynamic>) {
      throw FormatException('El campo "data" debe ser un Map, pero es: ${dataJson.runtimeType}');
    }
    
    return ActivityResponse(
      data: ActivityData.fromJson(dataJson),
    );
  }
}

/// Datos de la actividad (viajes y última posición)
class ActivityData {
  final List<Viaje> viajes;
  final UltimaPosicion? ultimaPosicion;

  ActivityData({
    required this.viajes,
    this.ultimaPosicion,
  });

  factory ActivityData.fromJson(Map<String, dynamic> json) {
    // Parsear viajes
    List<Viaje> viajesList = [];
    if (json.containsKey('viajes') && json['viajes'] != null) {
      final viajesData = json['viajes'];
      if (viajesData is List) {
        try {
          viajesList = viajesData
              .whereType<Map<String, dynamic>>()
              .map((v) {
                try {
                  return Viaje.fromJson(v);
                } catch (e) {
                  print('❌ Error al parsear viaje: $e');
                  print('   - Datos del viaje: $v');
                  rethrow;
                }
              })
              .toList();
        } catch (e) {
          print('❌ Error al parsear lista de viajes: $e');
          print('   - Datos de viajes: $viajesData');
          rethrow;
        }
      } else {
        print('⚠️ "viajes" no es una List, es: ${viajesData.runtimeType}');
      }
    } else {
      print('⚠️ No se encontró "viajes" en el JSON o es null');
    }
    
    // Parsear ultimaPosicion
    UltimaPosicion? ultimaPosicion;
    if (json.containsKey('ultimaPosicion') && json['ultimaPosicion'] != null) {
      final ultimaPosicionData = json['ultimaPosicion'];
      if (ultimaPosicionData is Map<String, dynamic>) {
        try {
          ultimaPosicion = UltimaPosicion.fromJson(ultimaPosicionData);
        } catch (e) {
          print('❌ Error al parsear ultimaPosicion: $e');
          print('   - Datos de ultimaPosicion: $ultimaPosicionData');
          rethrow;
        }
      } else {
        print('⚠️ "ultimaPosicion" no es un Map, es: ${ultimaPosicionData.runtimeType}');
      }
    } else {
      print('ℹ️ No se encontró "ultimaPosicion" en el JSON o es null (esto es normal si no hay posición)');
    }
    
    return ActivityData(
      viajes: viajesList,
      ultimaPosicion: ultimaPosicion,
    );
  }
}

/// Modelo para un viaje
class Viaje {
  final int idViaje;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;
  final String? nombreVariante;
  final Turno? turno;
  final Instalacion? instalacion;

  Viaje({
    required this.idViaje,
    this.fechaInicio,
    this.fechaFin,
    this.nombreVariante,
    this.turno,
    this.instalacion,
  });

  factory Viaje.fromJson(Map<String, dynamic> json) {
    // Validar idViaje
    if (!json.containsKey('idViaje')) {
      throw FormatException('El campo "idViaje" es requerido en Viaje');
    }
    
    return Viaje(
      idViaje: (json['idViaje'] as num).toInt(),
      fechaInicio: json['fechaInicio'] != null && json['fechaInicio'] is String
          ? DateTime.parse(json['fechaInicio'] as String)
          : null,
      fechaFin: json['fechaFin'] != null && json['fechaFin'] is String
          ? DateTime.parse(json['fechaFin'] as String)
          : null,
      nombreVariante: json['nombreVariante'] as String?,
      turno: json['turno'] != null && json['turno'] is Map<String, dynamic>
          ? Turno.fromJson(json['turno'] as Map<String, dynamic>)
          : null,
      instalacion: json['instalacion'] != null && json['instalacion'] is Map<String, dynamic>
          ? Instalacion.fromJson(json['instalacion'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Modelo para un turno
class Turno {
  final int idTurno;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;

  Turno({
    required this.idTurno,
    this.fechaInicio,
    this.fechaFin,
  });

  factory Turno.fromJson(Map<String, dynamic> json) {
    return Turno(
      idTurno: json['idTurno'] as int,
      fechaInicio: json['fechaInicio'] != null
          ? DateTime.parse(json['fechaInicio'] as String)
          : null,
      fechaFin: json['fechaFin'] != null
          ? DateTime.parse(json['fechaFin'] as String)
          : null,
    );
  }
}

/// Modelo para una instalación
class Instalacion {
  final int idInstalacion;
  final Vehiculo? vehiculo;

  Instalacion({
    required this.idInstalacion,
    this.vehiculo,
  });

  factory Instalacion.fromJson(Map<String, dynamic> json) {
    return Instalacion(
      idInstalacion: json['idInstalacion'] as int,
      vehiculo: json['vehiculo'] != null
          ? Vehiculo.fromJson(json['vehiculo'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Modelo para un vehículo
class Vehiculo {
  final int idVehiculo;
  final String? placa;
  final String? marca;
  final String? modelo;

  Vehiculo({
    required this.idVehiculo,
    this.placa,
    this.marca,
    this.modelo,
  });

  factory Vehiculo.fromJson(Map<String, dynamic> json) {
    return Vehiculo(
      idVehiculo: json['idVehiculo'] as int,
      placa: json['placa'] as String?,
      marca: json['marca'] as String?,
      modelo: json['modelo'] as String?,
    );
  }
}

/// Modelo para la última posición
class UltimaPosicion {
  final int id;
  final double latitud;
  final double longitud;
  final double velocidad;
  final double direccion;
  final DateTime fechaHora;
  final String exactitud;
  final int estado;

  UltimaPosicion({
    required this.id,
    required this.latitud,
    required this.longitud,
    required this.velocidad,
    required this.direccion,
    required this.fechaHora,
    required this.exactitud,
    required this.estado,
  });

  factory UltimaPosicion.fromJson(Map<String, dynamic> json) {
    // Validar campos requeridos
    if (!json.containsKey('id') || !json.containsKey('latitud') || 
        !json.containsKey('longitud') || !json.containsKey('fechaHora')) {
      throw FormatException('Campos requeridos faltantes en UltimaPosicion');
    }
    
    return UltimaPosicion(
      id: (json['id'] as num).toInt(),
      latitud: (json['latitud'] as num).toDouble(),
      longitud: (json['longitud'] as num).toDouble(),
      velocidad: json['velocidad'] != null ? (json['velocidad'] as num).toDouble() : 0.0,
      direccion: json['direccion'] != null ? (json['direccion'] as num).toDouble() : 0.0,
      fechaHora: DateTime.parse(json['fechaHora'] as String),
      exactitud: json['exactitud'] as String? ?? 'N',
      estado: json['estado'] != null ? (json['estado'] as num).toInt() : 0,
    );
  }
}

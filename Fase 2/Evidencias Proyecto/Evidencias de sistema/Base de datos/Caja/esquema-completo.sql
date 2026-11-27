-- esquema-completo.sql — Walkan Caja (on-premise)
-- Todas las migraciones de migrations/ juntas y en orden, para crear la base de cero de una sola vez.
-- Ojo: es una copia armada desde migrations/. Si se agrega una migración nueva, hay que volver a generarlo.
-- Al final se anotan las migraciones en _migraciones, así la app no las vuelve a correr al arrancar.
-- Se corre con: node base-de-datos/crear-bd.js  (o con el cliente sqlite3: sqlite3 data/xxx.db < base-de-datos/esquema-completo.sql)

CREATE TABLE IF NOT EXISTS _migraciones (nombre TEXT PRIMARY KEY, aplicada_en TEXT NOT NULL);

-- ============================================================
-- 001_init.sql
-- ============================================================
-- 001_init.sql — Esquema inicial Walkan on-premise (Fase 1 aprobada).
-- Convenciones: dinero INTEGER (CLP), fechas TEXT ISO-8601 UTC, booleanos 0/1,
-- enums TEXT + CHECK, tenant_id TEXT en toda tabla (mono-tenant, paridad cloud).
-- IDs: UUID TEXT en entidades raíz; INTEGER AUTOINCREMENT en filas hijas.

-- ============================ OPERACIÓN ============================

CREATE TABLE cajeros (
  id         TEXT    PRIMARY KEY,
  tenant_id  TEXT    NOT NULL,
  nombre     TEXT    NOT NULL,
  pin_hash   TEXT    NOT NULL,
  activo     INTEGER NOT NULL DEFAULT 1,
  created_at TEXT    NOT NULL,
  updated_at TEXT    NOT NULL
);

CREATE TABLE productos (
  id            TEXT    PRIMARY KEY,
  tenant_id     TEXT    NOT NULL,
  codigo        TEXT    NOT NULL,
  codigo_barras TEXT,
  nombre        TEXT    NOT NULL,
  descripcion   TEXT,
  precio_venta  INTEGER NOT NULL DEFAULT 0,
  unidad        TEXT    NOT NULL DEFAULT 'UN',
  stock         INTEGER NOT NULL DEFAULT 0,
  stock_minimo  INTEGER NOT NULL DEFAULT 0,
  exento        INTEGER NOT NULL DEFAULT 0,
  activo        INTEGER NOT NULL DEFAULT 1,
  created_at    TEXT    NOT NULL,
  updated_at    TEXT    NOT NULL
);
CREATE UNIQUE INDEX uq_productos_codigo  ON productos(tenant_id, codigo);
CREATE INDEX        idx_productos_barras ON productos(tenant_id, codigo_barras);
CREATE INDEX        idx_productos_nombre ON productos(tenant_id, nombre);

CREATE TABLE cajas_sesion (
  id             TEXT    PRIMARY KEY,
  tenant_id      TEXT    NOT NULL,
  cajero_id      TEXT    NOT NULL REFERENCES cajeros(id),
  monto_apertura INTEGER NOT NULL DEFAULT 0,
  monto_cierre   INTEGER,
  estado         TEXT    NOT NULL DEFAULT 'ABIERTA'
                   CHECK (estado IN ('ABIERTA','CERRADA')),
  fecha_apertura TEXT    NOT NULL,
  fecha_cierre   TEXT,
  created_at     TEXT    NOT NULL,
  updated_at     TEXT    NOT NULL
);
CREATE INDEX idx_caja_cajero ON cajas_sesion(cajero_id);
-- Invariante: una sola caja abierta a la vez en el terminal.
CREATE UNIQUE INDEX uq_caja_abierta ON cajas_sesion(tenant_id) WHERE estado = 'ABIERTA';

-- dte_emitidos se crea antes que ventas porque ventas la referencia.
-- venta_id acá es columna simple (sin FK) para romper la referencia circular
-- ventas <-> dte_emitidos; el vínculo autoritativo es ventas.dte_emitido_id.

CREATE TABLE dte_emitidos (
  id             TEXT    PRIMARY KEY,
  tenant_id      TEXT    NOT NULL,
  venta_id       TEXT,
  tipo_dte       TEXT    NOT NULL,
  folio          INTEGER NOT NULL,
  caf_id         TEXT,
  rut_receptor   TEXT,
  razon_receptor TEXT,
  neto           INTEGER NOT NULL DEFAULT 0,
  iva            INTEGER NOT NULL DEFAULT 0,
  exento         INTEGER NOT NULL DEFAULT 0,
  total          INTEGER NOT NULL DEFAULT 0,
  fecha_emision  TEXT    NOT NULL,
  items_json     TEXT    NOT NULL,
  xml            TEXT,
  track_id       TEXT,
  estado_sii     TEXT    NOT NULL DEFAULT 'EMITIDO'
                   CHECK (estado_sii IN ('EMITIDO','ACEPTADO','RECHAZADO')),
  created_at     TEXT    NOT NULL,
  updated_at     TEXT    NOT NULL,
  UNIQUE (tenant_id, tipo_dte, folio)
);
CREATE INDEX idx_dte_estado ON dte_emitidos(estado_sii);
CREATE INDEX idx_dte_venta  ON dte_emitidos(venta_id);

CREATE TABLE ventas (
  id             TEXT    PRIMARY KEY,
  tenant_id      TEXT    NOT NULL,
  caja_sesion_id TEXT    NOT NULL REFERENCES cajas_sesion(id),
  dte_emitido_id TEXT    NOT NULL REFERENCES dte_emitidos(id),
  tipo_dte       TEXT    NOT NULL,
  medio_pago     TEXT    NOT NULL
                   CHECK (medio_pago IN ('EFECTIVO','TARJETA','TRANSFERENCIA')),
  neto           INTEGER NOT NULL DEFAULT 0,
  iva            INTEGER NOT NULL DEFAULT 0,
  exento         INTEGER NOT NULL DEFAULT 0,
  total          INTEGER NOT NULL DEFAULT 0,
  created_at     TEXT    NOT NULL
);
CREATE INDEX idx_ventas_caja  ON ventas(caja_sesion_id);
CREATE INDEX idx_ventas_fecha ON ventas(tenant_id, created_at);

CREATE TABLE venta_items (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  tenant_id       TEXT    NOT NULL,
  venta_id        TEXT    NOT NULL REFERENCES ventas(id),
  producto_id     TEXT    NOT NULL REFERENCES productos(id),
  descripcion     TEXT    NOT NULL,
  cantidad        INTEGER NOT NULL,
  precio_unitario INTEGER NOT NULL,
  exento          INTEGER NOT NULL DEFAULT 0,
  total_linea     INTEGER NOT NULL
);
CREATE INDEX idx_venta_items_venta ON venta_items(venta_id);

CREATE TABLE movimientos_stock (
  id               TEXT    PRIMARY KEY,
  tenant_id        TEXT    NOT NULL,
  producto_id      TEXT    NOT NULL REFERENCES productos(id),
  tipo             TEXT    NOT NULL CHECK (tipo IN ('ENTRADA','SALIDA','AJUSTE')),
  motivo           TEXT    NOT NULL CHECK (motivo IN
                     ('INVENTARIO_INICIAL','RECEPCION_COMPRA','VENTA',
                      'AJUSTE_MANUAL','MERMA','DEVOLUCION')),
  cantidad         INTEGER NOT NULL,
  stock_resultante INTEGER NOT NULL,
  referencia       TEXT,
  comentario       TEXT,
  created_at       TEXT    NOT NULL
);
CREATE INDEX idx_mov_producto ON movimientos_stock(producto_id);
CREATE INDEX idx_mov_fecha    ON movimientos_stock(tenant_id, created_at);

-- ============================ FACTURACIÓN ============================

CREATE TABLE caf (
  id              TEXT    PRIMARY KEY,
  tenant_id       TEXT    NOT NULL,
  tipo_dte        TEXT    NOT NULL,
  folio_desde     INTEGER NOT NULL,
  folio_hasta     INTEGER NOT NULL,
  folio_siguiente INTEGER NOT NULL,
  activo          INTEGER NOT NULL DEFAULT 1,
  xml             TEXT,
  fecha_carga     TEXT    NOT NULL,
  created_at      TEXT    NOT NULL,
  updated_at      TEXT    NOT NULL,
  CHECK (folio_hasta >= folio_desde),
  CHECK (folio_siguiente BETWEEN folio_desde AND folio_hasta + 1)
);
CREATE UNIQUE INDEX uq_caf_activo ON caf(tenant_id, tipo_dte) WHERE activo = 1;

CREATE TABLE folios_usados (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  tenant_id      TEXT    NOT NULL,
  caf_id         TEXT    NOT NULL REFERENCES caf(id),
  tipo_dte       TEXT    NOT NULL,
  folio          INTEGER NOT NULL,
  dte_emitido_id TEXT    REFERENCES dte_emitidos(id),
  venta_id       TEXT    REFERENCES ventas(id),
  created_at     TEXT    NOT NULL,
  UNIQUE (caf_id, folio),
  UNIQUE (tenant_id, tipo_dte, folio)
);
CREATE INDEX idx_folios_dte ON folios_usados(dte_emitido_id);

CREATE TABLE dte_cola (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  tenant_id       TEXT    NOT NULL,
  dte_emitido_id  TEXT    NOT NULL REFERENCES dte_emitidos(id),
  estado          TEXT    NOT NULL DEFAULT 'PENDIENTE'
                    CHECK (estado IN
                      ('PENDIENTE','ENVIANDO','ENVIADO','ACEPTADO','RECHAZADO','REINTENTAR')),
  intentos        INTEGER NOT NULL DEFAULT 0,
  proximo_intento TEXT,
  ultimo_error    TEXT,
  created_at      TEXT    NOT NULL,
  updated_at      TEXT    NOT NULL
);
CREATE INDEX idx_dtecola_pick ON dte_cola(estado, proximo_intento);

-- ============================ SINCRONIZACIÓN ============================

CREATE TABLE sync_outbox (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  tenant_id       TEXT    NOT NULL,
  entidad         TEXT    NOT NULL,
  entidad_id      TEXT    NOT NULL,
  operacion       TEXT    NOT NULL CHECK (operacion IN ('INSERT','UPDATE','DELETE')),
  payload         TEXT    NOT NULL,
  estado          TEXT    NOT NULL DEFAULT 'PENDIENTE'
                    CHECK (estado IN ('PENDIENTE','ENVIANDO','ENVIADO','REINTENTAR')),
  intentos        INTEGER NOT NULL DEFAULT 0,
  proximo_intento TEXT,
  ultimo_error    TEXT,
  created_at      TEXT    NOT NULL,
  updated_at      TEXT    NOT NULL
);
CREATE INDEX idx_outbox_pick ON sync_outbox(estado, id);

CREATE TABLE sync_estado (
  id             INTEGER PRIMARY KEY CHECK (id = 1),
  tenant_id      TEXT    NOT NULL,
  ultima_sync_ok TEXT,
  ultimo_cursor  INTEGER NOT NULL DEFAULT 0,
  online         INTEGER NOT NULL DEFAULT 0,
  ultimo_error   TEXT,
  updated_at     TEXT
);

-- ============================================================
-- 002_dispositivo.sql
-- ============================================================
-- Vínculo del dispositivo (esta caja) con la nube Walkan. Fila única (id=1).
-- El token se obtiene una sola vez desde la pantalla de bienvenida
-- (POST a la nube /api/cajas/registrar con las credenciales de la cuenta).
-- La caja guarda SOLO el token, nunca la contraseña.
CREATE TABLE dispositivo (
  id           INTEGER PRIMARY KEY CHECK (id = 1),
  caja_id      TEXT,
  token        TEXT,
  nombre       TEXT,
  nube_url     TEXT,
  -- Kill-switch antirrobo: si la nube marca la caja como robada, se protege el
  -- acceso a los datos del negocio (la app se bloquea; el equipo sigue encendido).
  bloqueada    INTEGER NOT NULL DEFAULT 0,
  vinculada_at TEXT,
  updated_at   TEXT NOT NULL
);

INSERT OR IGNORE INTO dispositivo (id, updated_at) VALUES (1, '1970-01-01T00:00:00.000Z');

-- ============================================================
-- 003_id_nube.sql
-- ============================================================
-- Enlace estable con el producto de la nube. La caja reconocía los productos por SKU, así que si en el panel
-- se cambiaba el SKU (= código de barras) aparecía un producto duplicado en la caja. Con el id de la web,
-- que nunca cambia, la caja actualiza el código del mismo producto. Los existentes se enlazan solos en la
-- siguiente sincronización del catálogo (por su SKU actual).
ALTER TABLE productos ADD COLUMN id_nube TEXT;
CREATE INDEX idx_productos_id_nube ON productos(tenant_id, id_nube);

-- ============================================================
-- 004_cajeros_nube.sql
-- ============================================================
-- Cajeros administrados desde el panel web. id_nube enlaza el cajero local con el de la nube (que no cambia aunque
-- se renombre o cambie el PIN). Los cajeros sin id_nube son los creados en la propia caja al instalarla: se usan
-- mientras la nube no tenga cajeros; cuando el dueño crea el primero en el panel, la lista de la nube manda.
ALTER TABLE cajeros ADD COLUMN id_nube TEXT;
CREATE INDEX idx_cajeros_id_nube ON cajeros(tenant_id, id_nube);

-- ============================================================
-- 005_ajustes.sql
-- ============================================================
-- Ajustes que llegan de la nube con el catálogo (clave → JSON). Por ahora 'negocio': nombre y RUT para el
-- encabezado del comprobante, y los datos de transferencia que la caja muestra (con QR) al cobrar.
CREATE TABLE ajustes (
  clave      TEXT PRIMARY KEY,
  valor      TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- ============================================================
-- 006_venta_generica.sql
-- ============================================================
-- C1 (P5): vender un código que no está en el catálogo local como línea "genérica" (descripción y precio a mano).
-- Una venta nunca se bloquea ni se pierde por un código desconocido: queda registrada, no descuenta stock local y
-- la nube la deja en la bandeja "Vendido sin catálogo" del panel para que el dueño cree o vincule el producto.
-- SQLite no permite quitar un NOT NULL: se rehace la tabla (nadie la referencia) con los mismos datos.
CREATE TABLE venta_items_n (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  tenant_id       TEXT    NOT NULL,
  venta_id        TEXT    NOT NULL REFERENCES ventas(id),
  producto_id     TEXT    REFERENCES productos(id),   -- NULL = línea genérica
  codigo_leido    TEXT,                               -- código que se escaneó (solo en líneas genéricas)
  descripcion     TEXT    NOT NULL,
  cantidad        INTEGER NOT NULL,
  precio_unitario INTEGER NOT NULL,
  exento          INTEGER NOT NULL DEFAULT 0,
  total_linea     INTEGER NOT NULL,
  CHECK (producto_id IS NOT NULL OR codigo_leido IS NOT NULL)
);
INSERT INTO venta_items_n (id, tenant_id, venta_id, producto_id, descripcion, cantidad, precio_unitario, exento, total_linea)
  SELECT id, tenant_id, venta_id, producto_id, descripcion, cantidad, precio_unitario, exento, total_linea FROM venta_items;
DROP TABLE venta_items;
ALTER TABLE venta_items_n RENAME TO venta_items;
CREATE INDEX idx_venta_items_venta ON venta_items(venta_id);

-- Registro de migraciones aplicadas (para que el migrador de la app no las repita).
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('001_init.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('002_dispositivo.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('003_id_nube.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('004_cajeros_nube.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('005_ajustes.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('006_venta_generica.sql', '2026-01-01T00:00:00.000Z');

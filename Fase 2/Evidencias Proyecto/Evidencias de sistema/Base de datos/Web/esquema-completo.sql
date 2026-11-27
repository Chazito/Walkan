-- esquema-completo.sql — Walkan Web (nube)
-- Todas las migraciones de migrations/ juntas y en orden, para crear la base de cero de una sola vez.
-- Ojo: es una copia armada desde migrations/. Si se agrega una migración nueva, hay que volver a generarlo.
-- Al final se anotan las migraciones en _migraciones, así la app no las vuelve a correr al arrancar.
-- Se corre con: node base-de-datos/crear-bd.js  (o con el cliente sqlite3: sqlite3 data/xxx.db < base-de-datos/esquema-completo.sql)

CREATE TABLE IF NOT EXISTS _migraciones (nombre TEXT PRIMARY KEY, aplicada_en TEXT NOT NULL);

-- ============================================================
-- 001_init.sql
-- ============================================================
-- Solicitudes de alta (leads) del embudo comercial.
CREATE TABLE solicitudes (
  id            TEXT    PRIMARY KEY,
  negocio       TEXT    NOT NULL,
  contacto      TEXT    NOT NULL,
  email         TEXT    NOT NULL,
  telefono      TEXT,
  comuna        TEXT,
  plan          TEXT    NOT NULL,
  mensaje       TEXT,
  -- Etapa del embudo: va de 'Nueva' hasta 'Activa' (o 'Descartada' si se cae el trato).
  estado        TEXT    NOT NULL DEFAULT 'Nueva'
                  CHECK (estado IN ('Nueva','Contactada','En evaluación','Contrato firmado',
                                    'Certificado cargado','CAF cargado','Activa','Descartada')),
  pago_estado   TEXT    NOT NULL DEFAULT 'Pendiente'
                  CHECK (pago_estado IN ('Pendiente','Pagado','Rechazado')),
  -- Datos del cobro en Flow: orden y token con que se vuelve a consultar el pago.
  flow_order    TEXT,
  flow_token    TEXT,
  monto         INTEGER NOT NULL DEFAULT 0,
  created_at    TEXT    NOT NULL,
  updated_at    TEXT    NOT NULL
);
-- Índices para filtrar por etapa y para ubicar la solicitud cuando Flow avisa con su token.
CREATE INDEX idx_solicitudes_estado ON solicitudes(estado);
CREATE INDEX idx_solicitudes_token  ON solicitudes(flow_token);

-- ============================================================
-- 002_catalogo.sql
-- ============================================================
-- Catálogo: proveedores y productos (persistencia del panel del cliente).
CREATE TABLE proveedores (
  id          TEXT    PRIMARY KEY,
  nombre      TEXT    NOT NULL,
  tel         TEXT,
  email       TEXT,
  rubro       TEXT,
  created_at  TEXT    NOT NULL,
  updated_at  TEXT    NOT NULL
);

CREATE TABLE productos (
  id            TEXT    PRIMARY KEY,
  nombre        TEXT    NOT NULL,
  sku           TEXT,
  categoria     TEXT    NOT NULL DEFAULT 'General',
  -- Precio y costo en pesos enteros (CLP no usa decimales).
  precio        INTEGER NOT NULL DEFAULT 0,
  costo         INTEGER NOT NULL DEFAULT 0,
  stock         INTEGER NOT NULL DEFAULT 0,
  vence         TEXT,
  -- Si se borra el proveedor, el producto queda sin proveedor en vez de borrarse.
  proveedor_id  TEXT    REFERENCES proveedores(id) ON DELETE SET NULL,
  emoji         TEXT,
  img           TEXT,
  created_at    TEXT    NOT NULL,
  updated_at    TEXT    NOT NULL
);
CREATE INDEX idx_productos_prov ON productos(proveedor_id);

-- ============================================================
-- 003_usuarios.sql
-- ============================================================
-- Usuarios del panel (dueños / cajeros). Contraseña con scrypt (salt:hash hex).
CREATE TABLE usuarios (
  id            TEXT    PRIMARY KEY,
  email         TEXT    NOT NULL UNIQUE,
  nombre        TEXT    NOT NULL,
  negocio       TEXT,
  password_hash TEXT    NOT NULL,
  rol           TEXT    NOT NULL DEFAULT 'admin' CHECK (rol IN ('staff','admin','cajero')),
  created_at    TEXT    NOT NULL,
  updated_at    TEXT    NOT NULL
);
CREATE INDEX idx_usuarios_email ON usuarios(email);

-- ============================================================
-- 004_sync.sql
-- ============================================================
-- Receptor de sincronización: dispositivos (cajas) y ventas subidas desde la caja.
CREATE TABLE cajas (
  id          TEXT    PRIMARY KEY,
  nombre      TEXT    NOT NULL,
  token       TEXT    NOT NULL UNIQUE,
  usuario_id  TEXT    REFERENCES usuarios(id),
  estado      TEXT    NOT NULL DEFAULT 'activa' CHECK (estado IN ('activa','bloqueada')),
  ultimo_seq  INTEGER NOT NULL DEFAULT 0,
  ultima_sync TEXT,
  created_at  TEXT    NOT NULL,
  updated_at  TEXT    NOT NULL
);

CREATE TABLE ventas (
  id          TEXT    PRIMARY KEY,
  caja_id     TEXT    NOT NULL REFERENCES cajas(id),
  seq         INTEGER NOT NULL,
  folio       TEXT    NOT NULL,
  fecha       TEXT    NOT NULL,
  cajero      TEXT,
  medio_pago  TEXT,
  neto        INTEGER NOT NULL DEFAULT 0,
  iva         INTEGER NOT NULL DEFAULT 0,
  total       INTEGER NOT NULL DEFAULT 0,
  sii_estado  TEXT    NOT NULL DEFAULT 'Aceptada',
  items_json  TEXT    NOT NULL,
  created_at  TEXT    NOT NULL,
  UNIQUE (caja_id, seq)
);
CREATE INDEX idx_ventas_caja  ON ventas(caja_id);
CREATE INDEX idx_ventas_fecha ON ventas(fecha);

-- Sin cajas sembradas: cada caja se da de alta sola desde su pantalla de bienvenida
-- (POST /api/cajas/registrar con las credenciales de la cuenta -> devuelve token).

-- ============================================================
-- 005_compras.sql
-- ============================================================
-- Pedidos a proveedores y compras (recepciones / compras externas).
CREATE TABLE pedidos (
  id           TEXT    PRIMARY KEY,
  proveedor_id TEXT    REFERENCES proveedores(id) ON DELETE SET NULL,
  fecha        TEXT    NOT NULL,
  estado       TEXT    NOT NULL DEFAULT 'Enviado' CHECK (estado IN ('Enviado','Recibido')),
  nota         TEXT,
  items_json   TEXT    NOT NULL,
  created_at   TEXT    NOT NULL,
  updated_at   TEXT    NOT NULL
);

CREATE TABLE compras (
  id         TEXT    PRIMARY KEY,
  proveedor  TEXT    NOT NULL,
  tipo       TEXT    NOT NULL CHECK (tipo IN ('Pedido','Externa','Manual')),
  fecha      TEXT    NOT NULL,
  items      INTEGER NOT NULL DEFAULT 0,
  total      INTEGER NOT NULL DEFAULT 0,
  created_at TEXT    NOT NULL
);

-- ============================================================
-- 006_multitenant.sql
-- ============================================================
-- Multi-tenant: clientes (tenants) + cliente_id en todas las tablas del negocio.
-- El staff de Walkan (rol 'staff') administra clientes; cada cliente es un tenant
-- con su dueño (rol 'admin') y sus datos aislados por cliente_id.

CREATE TABLE clientes (
  id         TEXT PRIMARY KEY,
  negocio    TEXT NOT NULL,
  rut        TEXT,
  comuna     TEXT,
  email      TEXT,
  telefono   TEXT,
  plan       TEXT NOT NULL DEFAULT 'Kiosko',
  estado     TEXT NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo','suspendido','pendiente')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Agregar cliente_id a usuarios (el rol 'staff' ya está permitido desde 003_usuarios.sql).
ALTER TABLE usuarios ADD COLUMN cliente_id TEXT;
CREATE INDEX idx_usuarios_cliente ON usuarios(cliente_id);

-- cliente_id en las tablas del negocio (aislamiento por tenant).
ALTER TABLE proveedores ADD COLUMN cliente_id TEXT;
ALTER TABLE productos   ADD COLUMN cliente_id TEXT;
ALTER TABLE cajas       ADD COLUMN cliente_id TEXT;
ALTER TABLE ventas      ADD COLUMN cliente_id TEXT;
ALTER TABLE pedidos     ADD COLUMN cliente_id TEXT;
ALTER TABLE compras     ADD COLUMN cliente_id TEXT;

CREATE INDEX idx_productos_cliente   ON productos(cliente_id);
CREATE INDEX idx_proveedores_cliente ON proveedores(cliente_id);
CREATE INDEX idx_cajas_cliente       ON cajas(cliente_id);
CREATE INDEX idx_ventas_cliente      ON ventas(cliente_id);
CREATE INDEX idx_pedidos_cliente     ON pedidos(cliente_id);
CREATE INDEX idx_compras_cliente     ON compras(cliente_id);

-- ============================================================
-- 007_fix_rol_usuarios.sql
-- ============================================================
-- Arregla el CHECK de rol en bases creadas con el 003 antiguo (rol IN ('admin','cajero')),
-- que rechazaba el rol 'staff'. No se puede alterar un CHECK en SQLite, así que se
-- recrea la tabla. Se evita RENAME de usuarios (reescribiría la FK cajas.usuario_id):
-- se crea usuarios_new, se copian los datos, se DROPEA usuarios y se renombra
-- usuarios_new -> usuarios (nada referencia a usuarios_new, no hay reescritura de FK).
CREATE TABLE usuarios_new (
  id            TEXT PRIMARY KEY,
  email         TEXT NOT NULL UNIQUE,
  nombre        TEXT NOT NULL,
  negocio       TEXT,
  cliente_id    TEXT,
  password_hash TEXT NOT NULL,
  rol           TEXT NOT NULL DEFAULT 'admin' CHECK (rol IN ('staff','admin','cajero')),
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);
INSERT INTO usuarios_new (id,email,nombre,negocio,cliente_id,password_hash,rol,created_at,updated_at)
  SELECT id,email,nombre,negocio,cliente_id,password_hash,rol,created_at,updated_at FROM usuarios;
DROP TABLE usuarios;
ALTER TABLE usuarios_new RENAME TO usuarios;
CREATE INDEX idx_usuarios_email   ON usuarios(email);
CREATE INDEX idx_usuarios_cliente ON usuarios(cliente_id);

-- ============================================================
-- 008_items.sql
-- ============================================================
-- Módulo de ítems: kardex de stock, archivo de productos, SKU único por cliente
-- y lead time de proveedores (base para la predicción de inventario).

-- Kardex: todo cambio de stock queda registrado aquí (cantidad con signo).
CREATE TABLE movimientos_stock (
  id TEXT PRIMARY KEY,
  cliente_id TEXT NOT NULL,
  producto_id TEXT NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
  tipo TEXT NOT NULL CHECK (tipo IN ('inicial','venta','recepcion','compra','ajuste')),
  cantidad INTEGER NOT NULL,
  costo_unit INTEGER,
  ref_id TEXT,
  motivo TEXT,
  fecha TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_mov_cliente_prod_fecha ON movimientos_stock(cliente_id, producto_id, fecha);
CREATE INDEX idx_mov_cliente_tipo_fecha ON movimientos_stock(cliente_id, tipo, fecha);

ALTER TABLE productos ADD COLUMN activo INTEGER NOT NULL DEFAULT 1;
ALTER TABLE productos ADD COLUMN stock_minimo INTEGER;
ALTER TABLE proveedores ADD COLUMN lead_time_dias INTEGER NOT NULL DEFAULT 3;

-- SKU único por cliente: vacíos pasan a NULL y los duplicados existentes se
-- limpian (se conserva el primero) antes de crear el índice.
UPDATE productos SET sku = NULL WHERE TRIM(COALESCE(sku, '')) = '';
UPDATE productos SET sku = NULL
  WHERE sku IS NOT NULL AND rowid NOT IN (
    SELECT MIN(rowid) FROM productos WHERE sku IS NOT NULL GROUP BY cliente_id, sku);
CREATE UNIQUE INDEX ux_productos_cliente_sku ON productos(cliente_id, sku) WHERE sku IS NOT NULL;

-- El stock que ya existe entra al kardex como movimiento inicial.
INSERT INTO movimientos_stock (id, cliente_id, producto_id, tipo, cantidad, costo_unit, fecha, created_at)
  SELECT lower(hex(randomblob(16))), cliente_id, id, 'inicial', stock, costo, created_at, created_at
  FROM productos WHERE stock <> 0 AND cliente_id IS NOT NULL;

-- ============================================================
-- 008_suscripciones.sql
-- ============================================================
-- Registro autoservicio + suscripción (pago del plan).
-- Un cliente nuevo nace 'pendiente'; al confirmarse el pago de su suscripción pasa a 'activo'.
CREATE TABLE suscripciones (
  id             TEXT    PRIMARY KEY,
  cliente_id     TEXT    NOT NULL REFERENCES clientes(id),
  plan           TEXT    NOT NULL,
  monto          INTEGER NOT NULL,
  estado         TEXT    NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente','pagada','rechazada')),
  flow_token     TEXT,
  flow_order     TEXT,
  periodo_inicio TEXT,
  periodo_fin    TEXT,
  created_at     TEXT    NOT NULL,
  updated_at     TEXT    NOT NULL
);
CREATE INDEX idx_suscripciones_cliente ON suscripciones(cliente_id);
CREATE INDEX idx_suscripciones_token   ON suscripciones(flow_token);

-- ============================================================
-- 009_lotes.sql
-- ============================================================
-- Lotes con vencimiento (FEFO) y flujo de compras Pedido -> Ingreso.
-- Ver docs/plan/plan-lotes-compras.md.

-- Indicador por producto: si está activo, cada entrada de stock pide vencimiento y crea un lote.
ALTER TABLE productos ADD COLUMN controla_vence INTEGER NOT NULL DEFAULT 0;

-- Lote = unidades que entraron juntas con el mismo vencimiento. `cantidad` es lo que queda.
CREATE TABLE lotes (
  id               TEXT PRIMARY KEY,
  cliente_id       TEXT NOT NULL,
  producto_id      TEXT NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
  codigo           TEXT,
  vence            TEXT,
  cantidad_inicial INTEGER NOT NULL,
  cantidad         INTEGER NOT NULL,
  created_at       TEXT NOT NULL
);
CREATE INDEX idx_lotes_cliente_prod ON lotes(cliente_id, producto_id, vence);
CREATE INDEX idx_lotes_cliente_vence ON lotes(cliente_id, vence);

-- Cada porción del kardex que tocó un lote lo anota (una venta puede partirse en varios lotes).
ALTER TABLE movimientos_stock ADD COLUMN lote_id TEXT;

-- Pedidos: estado 'Borrador' y enlace al ingreso (fila de compras) que generó al recibirse.
-- SQLite no altera un CHECK: se recrea la tabla (nada la referencia, igual que en 007).
CREATE TABLE pedidos_new (
  id           TEXT    PRIMARY KEY,
  proveedor_id TEXT    REFERENCES proveedores(id) ON DELETE SET NULL,
  fecha        TEXT    NOT NULL,
  estado       TEXT    NOT NULL DEFAULT 'Enviado' CHECK (estado IN ('Borrador','Enviado','Recibido')),
  nota         TEXT,
  items_json   TEXT    NOT NULL,
  cliente_id   TEXT,
  compra_id    TEXT,
  created_at   TEXT    NOT NULL,
  updated_at   TEXT    NOT NULL
);
INSERT INTO pedidos_new (id,proveedor_id,fecha,estado,nota,items_json,cliente_id,created_at,updated_at)
  SELECT id,proveedor_id,fecha,estado,nota,items_json,cliente_id,created_at,updated_at FROM pedidos;
DROP TABLE pedidos;
ALTER TABLE pedidos_new RENAME TO pedidos;
CREATE INDEX idx_pedidos_cliente ON pedidos(cliente_id);

-- Datos existentes: quien tenía vencimiento pasa a controlarlo, con un lote inicial por su stock.
UPDATE productos SET controla_vence = 1 WHERE TRIM(COALESCE(vence, '')) <> '';
INSERT INTO lotes (id, cliente_id, producto_id, codigo, vence, cantidad_inicial, cantidad, created_at)
  SELECT lower(hex(randomblob(16))), cliente_id, id, NULL, vence, stock, stock, updated_at
  FROM productos WHERE controla_vence = 1 AND stock > 0 AND cliente_id IS NOT NULL;

-- ============================================================
-- 010_kardex_usuario.sql
-- ============================================================
-- Quién hizo cada movimiento de stock (auditoría, ISO 27002 8.15). NULL = la caja (sync) o un script.
ALTER TABLE movimientos_stock ADD COLUMN usuario_id TEXT;

-- ============================================================
-- 011_precios_historial.sql
-- ============================================================
-- Historial de precio y costo por producto. Lo llenan triggers: así queda registrado venga el cambio
-- de una edición en el panel, de una compra o de una recepción (que actualizan el costo), sin tocar cada ruta.
CREATE TABLE precios_historial (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  cliente_id  TEXT NOT NULL,
  producto_id TEXT NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
  precio      INTEGER,
  costo       INTEGER,
  fecha       TEXT NOT NULL
);
CREATE INDEX idx_precios_cliente_prod ON precios_historial(cliente_id, producto_id, id);

CREATE TRIGGER trg_precios_ins AFTER INSERT ON productos WHEN NEW.cliente_id IS NOT NULL
BEGIN
  INSERT INTO precios_historial (cliente_id, producto_id, precio, costo, fecha)
  VALUES (NEW.cliente_id, NEW.id, NEW.precio, NEW.costo, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
END;

CREATE TRIGGER trg_precios_upd AFTER UPDATE OF precio, costo ON productos
  WHEN NEW.cliente_id IS NOT NULL AND (NEW.precio IS NOT OLD.precio OR NEW.costo IS NOT OLD.costo)
BEGIN
  INSERT INTO precios_historial (cliente_id, producto_id, precio, costo, fecha)
  VALUES (NEW.cliente_id, NEW.id, NEW.precio, NEW.costo, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
END;

-- Punto de partida: el precio y costo actuales de lo que ya existe.
INSERT INTO precios_historial (cliente_id, producto_id, precio, costo, fecha)
  SELECT cliente_id, id, precio, costo, updated_at FROM productos WHERE cliente_id IS NOT NULL;

-- ============================================================
-- 012_config_inventario.sql
-- ============================================================
-- Parámetros de inventario por negocio (plan de ítems §I). Sin fila = valores por defecto (10, 2 y 7).
CREATE TABLE config_inventario (
  cliente_id     TEXT PRIMARY KEY,
  umbral_bajo    INTEGER NOT NULL DEFAULT 10, -- stock bajo cuando el producto no tiene mínimo propio
  dias_seguridad INTEGER NOT NULL DEFAULT 2,  -- colchón sobre los días de entrega del proveedor
  dias_cobertura INTEGER NOT NULL DEFAULT 7,  -- días de venta que debe cubrir un pedido además de la entrega
  updated_at     TEXT NOT NULL
);

-- ============================================================
-- 013_sku_archivado.sql
-- ============================================================
-- Al archivar un producto su SKU se libera (para reutilizarlo); acá se guarda para poder devolverlo si se restaura.
ALTER TABLE productos ADD COLUMN sku_archivado TEXT;

-- ============================================================
-- 014_dias_visita.sql
-- ============================================================
-- Días en que pasa el preventista o vendedor del proveedor ("1,4" = lunes y jueves; 0 = domingo, como getDay()).
-- Ese día el panel recuerda revisar el pedido sugerido.
ALTER TABLE proveedores ADD COLUMN dias_visita TEXT;

-- ============================================================
-- 015_sesion_version.sql
-- ============================================================
-- Versión de sesión por usuario: al cambiar o restablecer la contraseña (o cerrar sesión)
-- se incrementa y todas las cookies anteriores de ese usuario dejan de servir.
ALTER TABLE usuarios ADD COLUMN sesion_version INTEGER NOT NULL DEFAULT 0;

-- ============================================================
-- 016_sesiones.sql
-- ============================================================
-- Sesiones por dispositivo: cada inicio de sesión crea una fila con un identificador aleatorio
-- (es lo que va en la cookie firmada). Cerrar sesión borra solo esa fila; cambiar la clave borra
-- las demás; restablecerla borra todas. Las sesiones con "Recordarme" duran 30 días y se renuevan
-- solas mientras se usen; sin "Recordarme", 12 horas.
CREATE TABLE sesiones (
  id          TEXT    PRIMARY KEY,
  usuario_id  TEXT    NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  recordar    INTEGER NOT NULL DEFAULT 1,
  creada      TEXT    NOT NULL,
  expira      TEXT    NOT NULL,
  ultimo_uso  TEXT    NOT NULL
);
CREATE INDEX idx_sesiones_usuario ON sesiones(usuario_id);

-- ============================================================
-- 017_codigo_interno.sql
-- ============================================================
-- Pan, fruta, verdura y otros productos sin código de barras: la caja vende por código, así que sin SKU no se
-- podían vender ni descontar. Ahora ProductosService les asigna un código interno al crearlos; esto hace lo mismo
-- con los que ya existen. EAN-13 con prefijo GS1 20 (circulación restringida: ningún producto del comercio lo usa)
-- + correlativo por negocio (sigue después del mayor "20…" que ya tenga) + dígito verificador.
WITH base AS (
  SELECT cliente_id, MAX(CAST(substr(c, 3, 10) AS INTEGER)) AS n FROM (
    SELECT cliente_id, sku AS c FROM productos UNION ALL SELECT cliente_id, sku_archivado FROM productos)
  WHERE c GLOB '20[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' GROUP BY cliente_id
), n AS (
  SELECT p.id, '20' || printf('%010d', COALESCE(b.n, 0) + ROW_NUMBER() OVER (PARTITION BY p.cliente_id ORDER BY p.created_at, p.id)) AS d
  FROM productos p LEFT JOIN base b ON b.cliente_id = p.cliente_id
  WHERE p.activo = 1 AND p.sku IS NULL AND p.cliente_id IS NOT NULL
)
UPDATE productos SET sku = (SELECT d || ((10 - (
    (substr(d,1,1) + substr(d,3,1) + substr(d,5,1) + substr(d,7,1) + substr(d,9,1) + substr(d,11,1))
    + 3 * (substr(d,2,1) + substr(d,4,1) + substr(d,6,1) + substr(d,8,1) + substr(d,10,1) + substr(d,12,1))) % 10) % 10)
  FROM n WHERE n.id = productos.id)
WHERE id IN (SELECT id FROM n);

-- ============================================================
-- 018_granel_devoluciones.sql
-- ============================================================
-- Productos a granel, vida útil, proveedores archivados, IVA del costo y devoluciones a proveedor.

-- Unidad de venta: 'un' (unidades enteras) o 'kg' (se vende pesado, stock con hasta 3 decimales).
-- plu = número corto (1..99999) que se programa en la balanza; va dentro del código que imprime la balanza.
ALTER TABLE productos ADD COLUMN unidad TEXT NOT NULL DEFAULT 'un' CHECK (unidad IN ('un','kg'));
ALTER TABLE productos ADD COLUMN plu INTEGER;
CREATE UNIQUE INDEX ux_productos_cliente_plu ON productos(cliente_id, plu) WHERE plu IS NOT NULL;
-- Días que dura el producto desde que entra (pan = 1). Si está, el vencimiento del lote se calcula solo.
ALTER TABLE productos ADD COLUMN vida_util_dias INTEGER;

-- Un proveedor con historial se archiva en vez de borrarse: así los pedidos viejos conservan su nombre.
ALTER TABLE proveedores ADD COLUMN activo INTEGER NOT NULL DEFAULT 1;

-- 1 = los costos se ingresan con IVA (boleta del mayorista); 0 = netos (factura). Los precios de venta siempre con IVA.
ALTER TABLE config_inventario ADD COLUMN costo_con_iva INTEGER NOT NULL DEFAULT 0;

-- Kardex: nuevo tipo 'devolucion' (mercadería que vuelve al proveedor; no es merma). SQLite no altera un CHECK:
-- se recrea la tabla (nada la referencia). cantidad pasa a REAL para el granel.
CREATE TABLE movimientos_stock_new (
  id          TEXT PRIMARY KEY,
  cliente_id  TEXT NOT NULL,
  producto_id TEXT NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
  tipo        TEXT NOT NULL CHECK (tipo IN ('inicial','venta','recepcion','compra','ajuste','devolucion')),
  cantidad    REAL NOT NULL,
  costo_unit  INTEGER,
  ref_id      TEXT,
  motivo      TEXT,
  fecha       TEXT NOT NULL,
  created_at  TEXT NOT NULL,
  lote_id     TEXT,
  usuario_id  TEXT
);
INSERT INTO movimientos_stock_new (id,cliente_id,producto_id,tipo,cantidad,costo_unit,ref_id,motivo,fecha,created_at,lote_id,usuario_id)
  SELECT id,cliente_id,producto_id,tipo,cantidad,costo_unit,ref_id,motivo,fecha,created_at,lote_id,usuario_id FROM movimientos_stock;
DROP TABLE movimientos_stock;
ALTER TABLE movimientos_stock_new RENAME TO movimientos_stock;
CREATE INDEX idx_mov_cliente_prod_fecha ON movimientos_stock(cliente_id, producto_id, fecha);
CREATE INDEX idx_mov_cliente_tipo_fecha ON movimientos_stock(cliente_id, tipo, fecha);

-- La devolución queda también en el historial de ingresos (tipo 'Devolucion', total negativo = crédito del proveedor).
CREATE TABLE compras_new (
  id         TEXT    PRIMARY KEY,
  proveedor  TEXT    NOT NULL,
  tipo       TEXT    NOT NULL CHECK (tipo IN ('Pedido','Externa','Manual','Devolucion')),
  fecha      TEXT    NOT NULL,
  items      INTEGER NOT NULL DEFAULT 0,
  total      INTEGER NOT NULL DEFAULT 0,
  created_at TEXT    NOT NULL,
  cliente_id TEXT
);
INSERT INTO compras_new (id,proveedor,tipo,fecha,items,total,created_at,cliente_id)
  SELECT id,proveedor,tipo,fecha,items,total,created_at,cliente_id FROM compras;
DROP TABLE compras;
ALTER TABLE compras_new RENAME TO compras;
CREATE INDEX idx_compras_cliente ON compras(cliente_id);

-- ============================================================
-- 019_cajeros.sql
-- ============================================================
-- Cajeros administrados desde el panel. Cada caja del negocio los recibe junto con el catálogo (GET /api/catalogo)
-- y valida el PIN localmente, así que el PIN se guarda SOLO como hash scrypt (mismo formato que la caja:
-- scrypt$<salt>$<hash>). Nunca se guarda ni se envía el PIN en claro.
CREATE TABLE cajeros (
  id         TEXT PRIMARY KEY,
  cliente_id TEXT NOT NULL REFERENCES clientes(id) ON DELETE CASCADE,
  nombre     TEXT NOT NULL,
  pin_hash   TEXT NOT NULL,
  activo     INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX idx_cajeros_cliente ON cajeros(cliente_id);

-- ============================================================
-- 020_cobros_y_correo.sql
-- ============================================================
-- Cobro por transferencia: datos bancarios del negocio (JSON: banco, tipoCuenta, numero, titular, rut, email).
-- La caja los recibe con el catálogo y los muestra, con un QR, cuando el cliente paga por transferencia.
ALTER TABLE clientes ADD COLUMN transferencia_json TEXT;

-- Detalle del pago que informa la caja: autorización de la máquina de tarjetas, monto recibido y vuelto, etc.
ALTER TABLE ventas ADD COLUMN pago_json TEXT;

-- Comprobantes enviados por correo. La caja (offline-first) encola el pedido; la nube envía el correo al sincronizar.
CREATE TABLE comprobantes_correo (
  id         TEXT PRIMARY KEY,
  venta_id   TEXT REFERENCES ventas(id) ON DELETE CASCADE,
  cliente_id TEXT NOT NULL,
  email      TEXT NOT NULL,
  estado     TEXT NOT NULL CHECK (estado IN ('pendiente','enviado','simulado','error')),
  detalle    TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_correo_venta ON comprobantes_correo(venta_id);
CREATE INDEX idx_correo_cliente ON comprobantes_correo(cliente_id);

-- ============================================================
-- 021_flow_negocio.sql
-- ============================================================
-- Pago automático con QR vía Flow (opcional, por negocio). Cada negocio conecta SU cuenta Flow:
-- la plata llega a su cuenta, nunca a la de Walkan. La secretKey se guarda cifrada (AES-256-GCM).
ALTER TABLE clientes ADD COLUMN flow_api_key TEXT;
ALTER TABLE clientes ADD COLUMN flow_secret_cifrada TEXT;
ALTER TABLE clientes ADD COLUMN flow_entorno TEXT; -- 'sandbox' | 'produccion'

-- Cobros con QR creados por las cajas. La caja muestra el QR (url de pago de Flow) y consulta el estado.
CREATE TABLE cobros_qr (
  id             TEXT PRIMARY KEY,
  cliente_id     TEXT NOT NULL,
  caja_id        TEXT NOT NULL,
  commerce_order TEXT NOT NULL UNIQUE,
  token          TEXT,
  url            TEXT,
  monto          INTEGER NOT NULL,
  estado         TEXT NOT NULL CHECK (estado IN ('pendiente','pagado','rechazado','anulado')),
  flow_order     TEXT,
  medio          TEXT,
  created_at     TEXT NOT NULL,
  updated_at     TEXT NOT NULL
);
CREATE INDEX idx_cobros_qr_token ON cobros_qr(token);

-- ============================================================
-- 022_idx_ventas_cliente_fecha.sql
-- ============================================================
-- Las ventas del panel se piden por negocio y ordenadas por fecha (las últimas 100 cada 30 s por pestaña, y por
-- rango en analíticas). Con índices separados SQLite filtraba por negocio y después ordenaba en una tabla temporal.
-- El índice compuesto sirve para las dos cosas y reemplaza al de solo cliente_id (es su prefijo).
CREATE INDEX IF NOT EXISTS idx_ventas_cliente_fecha ON ventas(cliente_id, fecha);
DROP INDEX IF EXISTS idx_ventas_cliente;

-- ============================================================
-- 023_ubicacion_clientes.sql
-- ============================================================
-- Ubicación normalizada del local (opcional). `comuna` (texto) se mantiene por compatibilidad y ahora
-- guarda el nombre oficial; `comuna_cut` es el Código Único Territorial (5 dígitos) y permite agrupar
-- o filtrar por comuna/región más adelante (instalaciones, soporte en terreno, reportes por zona).
-- Lista oficial en public/geo/territorio-cl.json. Número 023 porque la rama Franco ya usa el 022.
ALTER TABLE clientes ADD COLUMN comuna_cut TEXT;
ALTER TABLE clientes ADD COLUMN region TEXT;
ALTER TABLE clientes ADD COLUMN direccion TEXT;

-- ============================================================
-- 024_consentimientos.sql
-- ============================================================
-- Registro de consentimientos (Ley 21.719): prueba de que la persona aceptó, qué texto exacto
-- (versión + hash), cuándo, desde dónde y con qué navegador/IP. Es un historial de SOLO INSERCIÓN:
-- retirar un consentimiento agrega una fila nueva con aceptado=0; nunca se edita ni se borra una fila.
CREATE TABLE consentimientos (
  id          TEXT PRIMARY KEY,
  email       TEXT NOT NULL,             -- titular (en minúsculas)
  usuario_id  TEXT,                      -- si tiene cuenta
  cliente_id  TEXT,                      -- negocio al que pertenece (si aplica)
  tipo        TEXT NOT NULL CHECK (tipo IN ('privacidad', 'marketing')),
  aceptado    INTEGER NOT NULL CHECK (aceptado IN (0, 1)),
  version     TEXT NOT NULL,             -- versión de la política vigente al aceptar
  texto_hash  TEXT NOT NULL,             -- sha256 del texto aceptado (política + casilla)
  origen      TEXT NOT NULL,             -- registro | contacto | ingreso | mi-cuenta
  ip          TEXT,
  user_agent  TEXT,
  created_at  TEXT NOT NULL
);
CREATE INDEX idx_consentimientos_email ON consentimientos (email, tipo, created_at);
CREATE INDEX idx_consentimientos_usuario ON consentimientos (usuario_id, tipo, created_at);

CREATE TRIGGER consentimientos_sin_update BEFORE UPDATE ON consentimientos
BEGIN SELECT RAISE(ABORT, 'consentimientos es un historial de solo inserción'); END;
CREATE TRIGGER consentimientos_sin_delete BEFORE DELETE ON consentimientos
BEGIN SELECT RAISE(ABORT, 'consentimientos es un historial de solo inserción'); END;

-- ============================================================
-- 025_apariencia.sql
-- ============================================================
-- Apariencia del panel por negocio (Ajustes › Apariencia). Solo cambia cómo se ve, no qué hace.
-- estilo: nitido | suave | consola · modo: auto (según el equipo) | claro | oscuro · acento: color de la marca (#RRGGBB).
ALTER TABLE clientes ADD COLUMN apariencia_estilo TEXT NOT NULL DEFAULT 'nitido';
ALTER TABLE clientes ADD COLUMN apariencia_modo TEXT NOT NULL DEFAULT 'auto';
ALTER TABLE clientes ADD COLUMN apariencia_acento TEXT NOT NULL DEFAULT '#1E3A8A';

-- ============================================================
-- 026_apariencia_verde.sql
-- ============================================================
-- 026: el color por defecto de la apariencia pasa a ser el verde de Walkan (#0B7C4E) en vez del azul marino.
-- Los negocios que seguían con el azul por defecto (la función salió el 10-nov-2026) pasan al verde.
UPDATE clientes SET apariencia_acento = '#0B7C4E' WHERE apariencia_acento = '#1E3A8A';

-- SQLite no deja cambiar el DEFAULT de una columna: los negocios nuevos se crean con el azul de la 025
-- y este trigger los deja en verde apenas se insertan.
CREATE TRIGGER IF NOT EXISTS clientes_apariencia_verde AFTER INSERT ON clientes
WHEN NEW.apariencia_acento = '#1E3A8A'
BEGIN
  UPDATE clientes SET apariencia_acento = '#0B7C4E' WHERE id = NEW.id;
END;

-- ============================================================
-- 027_renovacion_y_baja.sql
-- ============================================================
-- Renovación mensual del plan y baja voluntaria de la cuenta.
--   cancelado_en      el dueño canceló el plan: no se le avisa ni se le cobra más y mantiene el acceso hasta el
--                     fin del período ya pagado.
--   eliminar_en       el dueño pidió eliminar su cuenta: queda cerrada de inmediato y sus datos se borran en esta
--                     fecha (30 días para arrepentirse).
--   eliminado_en      los datos ya se borraron. La fila queda vacía solo porque el registro de pagos
--                     (suscripciones) la referencia.
--   aviso_renovacion  último aviso de vencimiento enviado por correo: "<periodo_fin>|previo" o "<periodo_fin>|vencido".
ALTER TABLE clientes ADD COLUMN cancelado_en TEXT;
ALTER TABLE clientes ADD COLUMN eliminar_en TEXT;
ALTER TABLE clientes ADD COLUMN eliminado_en TEXT;
ALTER TABLE clientes ADD COLUMN aviso_renovacion TEXT;

-- Hasta ahora nadie revisaba el vencimiento. Para que ninguna cuenta existente quede en pausa de un día para
-- otro, las que ya tenían el período vencido parten con 30 días desde esta migración (se les avisa antes de vencer).
UPDATE suscripciones
   SET periodo_fin = strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '+30 days')
 WHERE estado = 'pagada'
   AND periodo_fin < strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
   AND periodo_fin = (SELECT MAX(s2.periodo_fin) FROM suscripciones s2 WHERE s2.cliente_id = suscripciones.cliente_id AND s2.estado = 'pagada');

-- ============================================================
-- 028_cambio_de_plan.sql
-- ============================================================
-- Cambio de plan desde el panel (Mi cuenta → Mi plan).
--   clientes.plan_siguiente  plan al que el dueño pidió pasar en la próxima renovación: bajar de plan, o cualquier
--                            cambio pedido con el período ya vencido. Se aplica cuando paga esa renovación.
--   suscripciones.tipo       'periodo' = pago de un mes (primer pago o renovación);
--                            'cambio'  = diferencia prorrateada por subir de plan a mitad de mes. No mueve el
--                            vencimiento: su periodo_fin es el del período que ya estaba pagado.
ALTER TABLE clientes ADD COLUMN plan_siguiente TEXT;
ALTER TABLE suscripciones ADD COLUMN tipo TEXT NOT NULL DEFAULT 'periodo';

-- ============================================================
-- 029_ventas_pendientes.sql
-- ============================================================
-- B1 (P5/P6, I1, I2, I4, C3, C4): ventas de la caja que no se pudieron aplicar del todo, guardadas para resolverlas en el panel.
-- (La 029 la reservó la Ronda 2 de docs/plan/coordinacion-franco-alvaro.md.)

-- Líneas de venta con un código que el catálogo no conoce. Antes solo se contaban y quedaban en el log: el stock nunca se
-- descontaba, ni siquiera después de crear el producto. Ahora quedan acá hasta que el dueño crea o vincula el producto
-- (se descuenta una sola vez, con la fecha de la venta) o las ignora.
CREATE TABLE ventas_pendientes (
  id           TEXT    PRIMARY KEY,
  cliente_id   TEXT    NOT NULL REFERENCES clientes(id),
  venta_id     TEXT    NOT NULL REFERENCES ventas(id),
  caja_id      TEXT,
  sku          TEXT,                -- código leído en la caja (puede faltar)
  nombre       TEXT    NOT NULL,
  cantidad     REAL    NOT NULL,
  precio       REAL    NOT NULL DEFAULT 0,
  fecha        TEXT    NOT NULL,    -- fecha de la venta (el descuento de stock usa esta)
  estado       TEXT    NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente','aplicada','ignorada')),
  producto_id  TEXT,                -- con qué producto se resolvió
  resuelta_en  TEXT,
  resuelta_por TEXT,                -- usuario del panel (NULL = automático al crear el producto)
  created_at   TEXT    NOT NULL
);
CREATE INDEX idx_vp_cliente_estado ON ventas_pendientes(cliente_id, estado);
CREATE INDEX idx_vp_cliente_sku    ON ventas_pendientes(cliente_id, sku, estado);

-- Eventos de la caja que la nube rechazó (I4). Antes ultimo_seq avanzaba y se perdían sin rastro. Solo se guarda lo
-- necesario para revisarlos (tipo, motivo, folio y total): nada del pago ni correos (minimización, Ley 21.719).
CREATE TABLE sync_rechazos (
  id          TEXT    PRIMARY KEY,
  cliente_id  TEXT    REFERENCES clientes(id),
  caja_id     TEXT    NOT NULL,
  seq         INTEGER NOT NULL,
  tipo        TEXT    NOT NULL,
  motivo      TEXT    NOT NULL,
  folio       TEXT,
  total       INTEGER,
  revisado    INTEGER NOT NULL DEFAULT 0,
  created_at  TEXT    NOT NULL
);
CREATE INDEX idx_sync_rechazos_cliente ON sync_rechazos(cliente_id, revisado);

-- C3: id propio de cada evento de la caja (el id de la venta en la caja). Con él la nube distingue un reenvío (ya lo tiene)
-- de una caja que reinició su numeración (seq ya usado, pero evento nuevo): antes esas ventas se descartaban en silencio.
ALTER TABLE ventas ADD COLUMN uid TEXT;
CREATE UNIQUE INDEX idx_ventas_caja_uid ON ventas(caja_id, uid) WHERE uid IS NOT NULL;

-- ============================================================
-- 030_planes_nuevos.sql
-- ============================================================
-- Planes nuevos (14-nov-2026): Kiosko → Esencial, Minimarket → Profesional, Minisúper → Empresa.
-- Precios, cupos y funciones viven en src/config/configuracion.ts (PLANES_DEF); acá solo se renombra lo guardado.
-- (La 029 queda reservada para las ventas pendientes de Franco.)
UPDATE clientes SET plan = CASE plan WHEN 'Kiosko' THEN 'Esencial' WHEN 'Minimarket' THEN 'Profesional'
  WHEN 'Minisúper' THEN 'Empresa' WHEN 'Minisuper' THEN 'Empresa' ELSE plan END;
UPDATE clientes SET plan_siguiente = CASE plan_siguiente WHEN 'Kiosko' THEN 'Esencial' WHEN 'Minimarket' THEN 'Profesional'
  WHEN 'Minisúper' THEN 'Empresa' WHEN 'Minisuper' THEN 'Empresa' ELSE plan_siguiente END
 WHERE plan_siguiente IS NOT NULL;
UPDATE suscripciones SET plan = CASE plan WHEN 'Kiosko' THEN 'Esencial' WHEN 'Minimarket' THEN 'Profesional'
  WHEN 'Minisúper' THEN 'Empresa' WHEN 'Minisuper' THEN 'Empresa' ELSE plan END;
UPDATE solicitudes SET plan = CASE plan WHEN 'Kiosko' THEN 'Esencial' WHEN 'Minimarket' THEN 'Profesional'
  WHEN 'Minisúper' THEN 'Empresa' WHEN 'Minisuper' THEN 'Empresa' ELSE plan END
 WHERE plan IS NOT NULL;

-- Caja adicional en arriendo: la primera caja de cada negocio va incluida; desde la segunda se paga una cuota
-- mensual junto con la renovación hasta completar las cuotas (configuracion.ts → cajaAdicional).
--   cajas.adicional       1 = caja en arriendo (no es la incluida)
--   cajas.cuotas_pagadas  cuotas ya cobradas en renovaciones pagadas
--   suscripciones.cajas_json  ids de las cajas cuya cuota va en ese cobro (al pagarse, a cada una se le suma 1)
ALTER TABLE cajas ADD COLUMN adicional INTEGER NOT NULL DEFAULT 0;
ALTER TABLE cajas ADD COLUMN cuotas_pagadas INTEGER NOT NULL DEFAULT 0;
ALTER TABLE suscripciones ADD COLUMN cajas_json TEXT;
-- Cajas que ya existían: en cada negocio, todas menos la primera registrada pasan a ser adicionales (su primera
-- cuota se cobra en la próxima renovación).
UPDATE cajas SET adicional = 1
 WHERE cliente_id IS NOT NULL
   AND id <> (SELECT c2.id FROM cajas c2 WHERE c2.cliente_id = cajas.cliente_id ORDER BY c2.created_at, c2.id LIMIT 1);

-- ============================================================
-- 031_cobro_automatico.sql
-- ============================================================
-- Cobro automático con tarjeta (Flow "Cargo Automático") y pagos registrados por el staff.
--   clientes.flow_customer_id   cliente creado en Flow (customer/create); se conserva aunque quite la tarjeta
--   clientes.tarjeta_marca / tarjeta_ultimos4 / tarjeta_desde   tarjeta inscrita (Walkan no guarda el número)
--   clientes.cobro_auto_intento / cobro_auto_error              último intento de cobro automático y su error
--   suscripciones.medio   'flow' (pago en línea), 'tarjeta' (cobro automático) o 'manual' (registrado por el staff)
--   suscripciones.nota    detalle del pago manual (p. ej. "transferencia 14-nov") y quién lo registró
ALTER TABLE clientes ADD COLUMN flow_customer_id TEXT;
ALTER TABLE clientes ADD COLUMN tarjeta_marca TEXT;
ALTER TABLE clientes ADD COLUMN tarjeta_ultimos4 TEXT;
ALTER TABLE clientes ADD COLUMN tarjeta_desde TEXT;
ALTER TABLE clientes ADD COLUMN cobro_auto_intento TEXT;
ALTER TABLE clientes ADD COLUMN cobro_auto_error TEXT;
ALTER TABLE suscripciones ADD COLUMN medio TEXT NOT NULL DEFAULT 'flow';
ALTER TABLE suscripciones ADD COLUMN nota TEXT;
CREATE INDEX IF NOT EXISTS idx_clientes_flow_customer ON clientes(flow_customer_id);

-- ============================================================
-- 032_recuperacion_y_dos_pasos.sql
-- ============================================================
-- Recuperar la contraseña por correo y verificación en dos pasos con app de códigos (16-nov-2026).

-- Enlace "¿Olvidaste tu contraseña?": un token de un solo uso por pedido. Se guarda solo su hash (sha256):
-- quien vea la base no puede usar los enlaces que estén vigentes.
CREATE TABLE IF NOT EXISTS recuperaciones (
  id          TEXT PRIMARY KEY,
  usuario_id  TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL UNIQUE,
  expira      TEXT NOT NULL,
  usado_en    TEXT,
  creado_en   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_recuperaciones_usuario ON recuperaciones(usuario_id);

-- Verificación en dos pasos (TOTP). El secreto va cifrado con una clave derivada de SESSION_SECRET.
ALTER TABLE usuarios ADD COLUMN totp_secreto TEXT;          -- activo (NULL = sin verificación en dos pasos)
ALTER TABLE usuarios ADD COLUMN totp_pendiente TEXT;        -- mientras se configura la app, aún sin confirmar
ALTER TABLE usuarios ADD COLUMN totp_desde TEXT;            -- cuándo se activó
ALTER TABLE usuarios ADD COLUMN totp_ultimo_paso INTEGER;   -- último código aceptado: no se acepta dos veces
ALTER TABLE usuarios ADD COLUMN totp_respaldo TEXT;         -- JSON con los hashes de los códigos de respaldo sin usar

-- ============================================================
-- 033_super_admin_y_bitacora.sql
-- ============================================================
-- Equipo Walkan: super admin, cuentas de staff desactivables y bitácora de acciones (17-nov-2026).

-- super_admin = 1: además de lo del staff, crea/desactiva cuentas del equipo y ve la bitácora.
-- desactivado_en: la cuenta no puede entrar (no se borra, para que la bitácora conserve quién hizo qué).
ALTER TABLE usuarios ADD COLUMN super_admin INTEGER NOT NULL DEFAULT 0;
ALTER TABLE usuarios ADD COLUMN desactivado_en TEXT;

-- El staff más antiguo (staff@walkan.cl, creado al partir) queda como primer super admin.
UPDATE usuarios SET super_admin = 1
 WHERE id = (SELECT id FROM usuarios WHERE rol = 'staff' ORDER BY created_at, id LIMIT 1);

-- Quién hizo qué en el panel de administración. Se guarda el correo además del id por si la cuenta cambia.
CREATE TABLE IF NOT EXISTS bitacora_staff (
  id           TEXT PRIMARY KEY,
  fecha        TEXT NOT NULL,
  actor_id     TEXT,
  actor_email  TEXT NOT NULL,
  accion       TEXT NOT NULL,
  detalle      TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_bitacora_staff_fecha ON bitacora_staff(fecha);

-- ============================================================
-- 034_invitaciones.sql
-- ============================================================
-- Invitaciones por correo (17-nov-2026): las cuentas creadas desde /admin ya no reciben una clave temporal.
-- Llega un enlace para crear la contraseña; mientras no la cree, clave_pendiente = 1 (la clave guardada es
-- aleatoria y nadie la conoce).
ALTER TABLE usuarios ADD COLUMN clave_pendiente INTEGER NOT NULL DEFAULT 0;

-- ============================================================
-- 035_dispositivos_y_soporte.sql
-- ============================================================
-- Dispositivos recordados y soporte (17-nov-2026).

-- "Recordar este dispositivo por 30 días" (solo dueños, nunca el equipo Walkan): con la cookie de ese navegador no se
-- pide el código de la app al entrar (la contraseña sí). Se guarda solo el hash del token.
CREATE TABLE IF NOT EXISTS dispositivos_confiables (
  id          TEXT PRIMARY KEY,
  usuario_id  TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL UNIQUE,
  expira      TEXT NOT NULL,
  creado_en   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_dispositivos_usuario ON dispositivos_confiables(usuario_id);

-- Tickets de soporte: desde el panel (con sesión) o desde /ayuda/contacto (sin sesión, p. ej. perdió el 2FA).
CREATE TABLE IF NOT EXISTS tickets (
  id              TEXT PRIMARY KEY,
  numero          INTEGER NOT NULL UNIQUE,
  origen          TEXT NOT NULL CHECK (origen IN ('panel','publico')),
  cliente_id      TEXT,                 -- negocio (si se sabe)
  usuario_id      TEXT,                 -- quien lo abrió con sesión
  nombre          TEXT NOT NULL,
  email           TEXT NOT NULL,
  rut             TEXT,                 -- lo escribe quien no tiene sesión (verificación)
  orden_pago      TEXT,                 -- n.º de orden de un pago de Flow (verificación)
  categoria       TEXT NOT NULL,
  asunto          TEXT NOT NULL,
  estado          TEXT NOT NULL DEFAULT 'abierto' CHECK (estado IN ('abierto','en_curso','resuelto')),
  asignado_a      TEXT,                 -- usuario del equipo Walkan
  creado_en       TEXT NOT NULL,
  actualizado_en  TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_tickets_estado ON tickets(estado, actualizado_en);
CREATE INDEX IF NOT EXISTS idx_tickets_cliente ON tickets(cliente_id);

CREATE TABLE IF NOT EXISTS ticket_mensajes (
  id           TEXT PRIMARY KEY,
  ticket_id    TEXT NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  cliente_id   TEXT,                    -- copia del negocio del ticket: así "Descargar mis datos" y el borrado de la cuenta lo cubren
  autor        TEXT NOT NULL CHECK (autor IN ('cliente','equipo','sistema')),
  autor_nombre TEXT NOT NULL,
  texto        TEXT NOT NULL,
  creado_en    TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ticket_mensajes_ticket ON ticket_mensajes(ticket_id, creado_en);

-- Registro de migraciones aplicadas (para que el migrador de la app no las repita).
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('001_init.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('002_catalogo.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('003_usuarios.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('004_sync.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('005_compras.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('006_multitenant.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('007_fix_rol_usuarios.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('008_items.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('008_suscripciones.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('009_lotes.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('010_kardex_usuario.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('011_precios_historial.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('012_config_inventario.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('013_sku_archivado.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('014_dias_visita.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('015_sesion_version.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('016_sesiones.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('017_codigo_interno.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('018_granel_devoluciones.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('019_cajeros.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('020_cobros_y_correo.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('021_flow_negocio.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('022_idx_ventas_cliente_fecha.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('023_ubicacion_clientes.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('024_consentimientos.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('025_apariencia.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('026_apariencia_verde.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('027_renovacion_y_baja.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('028_cambio_de_plan.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('029_ventas_pendientes.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('030_planes_nuevos.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('031_cobro_automatico.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('032_recuperacion_y_dos_pasos.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('033_super_admin_y_bitacora.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('034_invitaciones.sql', '2026-01-01T00:00:00.000Z');
INSERT INTO _migraciones (nombre, aplicada_en) VALUES ('035_dispositivos_y_soporte.sql', '2026-01-01T00:00:00.000Z');

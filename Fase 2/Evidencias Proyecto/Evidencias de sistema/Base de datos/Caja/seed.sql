-- seed.sql — Datos de prueba para la caja (on-premise)
-- Deja la caja lista para vender sin tener que vincularla a la web:
--   - un cajero "Cajero Demo" con PIN 1234
--   - unos cuantos productos típicos de almacén, con stock inicial
--   - un rango de folios (CAF) de prueba para boletas (tipo 39), del 1 al 1000
-- Todo va con tenant_id 'local', que es el TENANT_ID por defecto de la caja.
-- Ojo: si después vinculas la caja a la web, el catálogo y los cajeros del panel mandan sobre estos.
-- Se corre con: node base-de-datos/crear-bd.js --seed

-- El PIN va hasheado con scrypt (mismo formato que src/modules/cajeros/pin.ts). Este hash es del PIN 1234.
INSERT INTO cajeros (id, tenant_id, nombre, pin_hash, activo, created_at, updated_at) VALUES
  ('cajero-demo-0001', 'local', 'Cajero Demo',
   'scrypt$dk/zippr+3HHz6utxg2Q8g==$DwECaC/b0rxaX/LErnbOyihmibsxcpC5QJQIKnjPOpo=', 1,
   '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');

-- Productos: precio en pesos con IVA incluido (precio de góndola). codigo_barras es lo que lee la pistola.
INSERT INTO productos (id, tenant_id, codigo, codigo_barras, nombre, precio_venta, unidad, stock, stock_minimo, exento, activo, created_at, updated_at) VALUES
  ('prod-demo-0001', 'local', 'P001', '7801610001196', 'Coca-Cola 1.5 L',          1990, 'UN', 40, 10, 0, 1, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z'),
  ('prod-demo-0002', 'local', 'P002', '7802820005509', 'Leche entera 1 L',          1150, 'UN', 30,  8, 0, 1, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z'),
  ('prod-demo-0003', 'local', 'P003', '7801505000877', 'Arroz grado 1 1 kg',        1490, 'UN', 25,  5, 0, 1, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z'),
  ('prod-demo-0004', 'local', 'P004', '7802575220110', 'Fideos spaghetti 400 g',     890, 'UN', 35,  8, 0, 1, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z'),
  ('prod-demo-0005', 'local', 'P005', '7801320240106', 'Aceite maravilla 1 L',      2690, 'UN', 15,  4, 0, 1, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z'),
  ('prod-demo-0006', 'local', 'P006', '7802215501012', 'Galletas de agua 210 g',     790, 'UN', 50, 10, 0, 1, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z'),
  ('prod-demo-0007', 'local', 'P007', '7801552000013', 'Pan de molde blanco',       2190, 'UN', 12,  4, 0, 1, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z'),
  ('prod-demo-0008', 'local', 'P008', '7802950006605', 'Detergente líquido 3 L',    5990, 'UN', 10,  3, 0, 1, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z'),
  ('prod-demo-0009', 'local', 'P009', '7801234567897', 'Huevos docena',             3290, 'UN', 20,  5, 0, 1, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z'),
  ('prod-demo-0010', 'local', 'P010', '7804567890128', 'Agua mineral sin gas 1.6 L', 990, 'UN', 45, 10, 0, 1, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');

-- Cada stock inicial deja su movimiento en el kardex, igual que si se hubiera cargado a mano.
INSERT INTO movimientos_stock (id, tenant_id, producto_id, tipo, motivo, cantidad, stock_resultante, comentario, created_at)
  SELECT 'mov-ini-' || id, tenant_id, id, 'ENTRADA', 'INVENTARIO_INICIAL', stock, stock, 'Carga inicial (seed)', created_at
  FROM productos WHERE id LIKE 'prod-demo-%';

-- Folios de prueba para boletas. En producción el CAF lo entrega el SII; acá el envío al SII va simulado.
INSERT INTO caf (id, tenant_id, tipo_dte, folio_desde, folio_hasta, folio_siguiente, activo, xml, fecha_carga, created_at, updated_at) VALUES
  ('caf-demo-0001', 'local', '39', 1, 1000, 1, 1, NULL,
   '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');

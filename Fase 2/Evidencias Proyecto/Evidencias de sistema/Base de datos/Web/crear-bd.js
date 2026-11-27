// crear-bd.js — Crea la base de datos de la web de cero, sin tener que arrancar la app.
// Corre esquema-completo.sql (todas las migraciones juntas, en orden).
//
// Uso (desde la carpeta de la app, con npm install ya hecho):
//   node base-de-datos/crear-bd.js
//
// Los datos de prueba van en dos pasos, porque las claves se hashean en la app:
//   1. Al arrancar la app (fuera de producción) se crean solas las cuentas demo:
//      staff@walkan.cl (equipo Walkan) y admin@walkan.cl (dueño del negocio demo), las dos con clave walkan123.
//   2. Con la app corriendo: npm run demo:seed  → proveedores, productos y ~3 meses de ventas para los gráficos.
//
// La ruta sale de DB_PATH (igual que la app); si no está, usa ./data/walkan-web.db.
// Ojo: si la base ya existe no hace nada, para no pisar datos. Bórrala a mano si quieres partir de cero.
const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');

const dbPath = path.resolve(process.env.DB_PATH || './data/walkan-web.db');
if (fs.existsSync(dbPath)) {
  console.error(`Ya existe ${dbPath}. Bórrala primero si quieres crearla de nuevo.`);
  process.exit(1);
}
fs.mkdirSync(path.dirname(dbPath), { recursive: true });

const db = new Database(dbPath);
db.pragma('journal_mode = WAL'); // mismo modo que usa la app al abrirla
db.pragma('foreign_keys = ON');
// Todo en una transacción: o queda la base completa o no queda nada a medias.
db.transaction(() => db.exec(fs.readFileSync(path.join(__dirname, 'esquema-completo.sql'), 'utf8')))();
db.close();
console.log(`Base creada en ${dbPath}. Arranca la app y después corre "npm run demo:seed" para los datos de prueba.`);

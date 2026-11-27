// crear-bd.js — Crea la base de datos de la caja de cero, sin tener que arrancar la app.
// Corre esquema-completo.sql (todas las migraciones juntas) y, si le pasas --seed, también seed.sql.
//
// Uso (desde la carpeta de la app, con npm install ya hecho):
//   node base-de-datos/crear-bd.js           → solo las tablas
//   node base-de-datos/crear-bd.js --seed    → tablas + datos de prueba (cajero PIN 1234, productos, folios)
//
// La ruta sale de DB_PATH (igual que la app); si no está, usa ./data/walkan.db.
// Ojo: si la base ya existe no hace nada, para no pisar datos. Bórrala a mano si quieres partir de cero.
const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');

const dbPath = path.resolve(process.env.DB_PATH || './data/walkan.db');
if (fs.existsSync(dbPath)) {
  console.error(`Ya existe ${dbPath}. Bórrala primero si quieres crearla de nuevo.`);
  process.exit(1);
}
fs.mkdirSync(path.dirname(dbPath), { recursive: true });

const db = new Database(dbPath);
db.pragma('journal_mode = WAL'); // mismo modo que usa la app al abrirla
db.pragma('foreign_keys = ON');
const correr = (archivo) => db.exec(fs.readFileSync(path.join(__dirname, archivo), 'utf8'));

// Todo en una transacción: o queda la base completa o no queda nada a medias.
db.transaction(() => {
  correr('esquema-completo.sql');
  if (process.argv.includes('--seed')) correr('seed.sql');
})();
db.close();
console.log(`Base creada en ${dbPath}${process.argv.includes('--seed') ? ' (con datos de prueba)' : ''}`);

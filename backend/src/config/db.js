const mysql = require('mysql2');
const dotenv = require('dotenv');

dotenv.config();

// A connection pool is created once and reused across the app.
// `.promise()` exposes the async/await API used by the models.
const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'mindwell',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});

const db = pool.promise();

/**
 * Verifies the DB is reachable and ensures the `users` table exists.
 * Called once on server startup so a fresh machine works out of the box.
 */
async function initDb() {
  // Throws if credentials/host are wrong — surfaced by the caller.
  const connection = await db.getConnection();
  try {
    await connection.query(`
      CREATE TABLE IF NOT EXISTS users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        full_name VARCHAR(255) NOT NULL,
        email VARCHAR(255) UNIQUE NOT NULL,
        password VARCHAR(255) NOT NULL,
        role ENUM('student','admin') DEFAULT 'student',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
  } finally {
    connection.release();
  }
}

module.exports = db;
module.exports.initDb = initDb;

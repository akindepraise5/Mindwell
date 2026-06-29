const db = require('../config/db');

/**
 * Insert a new user. Expects an already-hashed password.
 * @returns {Promise<number>} the new user's id
 */
async function createUser({ fullName, email, password, role = 'student' }) {
  const [result] = await db.execute(
    'INSERT INTO users (full_name, email, password, role) VALUES (?, ?, ?, ?)',
    [fullName, email, password, role]
  );
  return result.insertId;
}

/**
 * Find a user by email — includes the password hash (used for login).
 * @returns {Promise<object|undefined>}
 */
async function findUserByEmail(email) {
  const [rows] = await db.execute(
    'SELECT id, full_name, email, password, role, created_at FROM users WHERE email = ? LIMIT 1',
    [email]
  );
  return rows[0];
}

/**
 * Find a user by id — never returns the password hash (safe for /me).
 * @returns {Promise<object|undefined>}
 */
async function findUserById(id) {
  const [rows] = await db.execute(
    'SELECT id, full_name, email, role, created_at FROM users WHERE id = ? LIMIT 1',
    [id]
  );
  return rows[0];
}

module.exports = {
  createUser,
  findUserByEmail,
  findUserById,
};

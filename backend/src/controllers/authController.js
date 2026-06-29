const bcrypt = require('bcryptjs');
const { createUser, findUserByEmail, findUserById } = require('../models/userModel');
const generateToken = require('../utils/generateToken');

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const VALID_ROLES = ['student', 'admin'];

/**
 * Shape a DB user row into a safe public object (never includes password).
 */
function publicUser(row) {
  return {
    id: row.id,
    fullName: row.full_name,
    email: row.email,
    role: row.role,
    createdAt: row.created_at,
  };
}

/**
 * POST /api/auth/register
 * Validates input, hashes the password, stores the user, returns a JWT.
 */
async function register(req, res, next) {
  try {
    let { fullName, full_name, email, password, role } = req.body || {};
    fullName = (fullName || full_name || '').trim();
    email = (email || '').trim().toLowerCase();

    // --- Validation ---
    if (!fullName || !email || !password) {
      return res.status(400).json({
        success: false,
        message: 'Full name, email and password are required',
      });
    }
    if (fullName.length < 2) {
      return res.status(400).json({ success: false, message: 'Full name is too short' });
    }
    if (!EMAIL_REGEX.test(email)) {
      return res.status(400).json({ success: false, message: 'Please provide a valid email address' });
    }
    if (String(password).length < 6) {
      return res
        .status(400)
        .json({ success: false, message: 'Password must be at least 6 characters' });
    }

    // Only allow known roles; default to student.
    const safeRole = VALID_ROLES.includes(role) ? role : 'student';

    // --- Uniqueness check ---
    const existing = await findUserByEmail(email);
    if (existing) {
      return res
        .status(409)
        .json({ success: false, message: 'An account with this email already exists' });
    }

    // --- Hash password ---
    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash(password, salt);

    // --- Save ---
    const userId = await createUser({
      fullName,
      email,
      password: hashedPassword,
      role: safeRole,
    });

    const user = await findUserById(userId);
    const token = generateToken(userId);

    return res.status(201).json({
      success: true,
      message: 'Account created successfully',
      token,
      user: publicUser(user),
    });
  } catch (err) {
    // Handle the race condition where the unique index rejects a duplicate.
    if (err && err.code === 'ER_DUP_ENTRY') {
      return res
        .status(409)
        .json({ success: false, message: 'An account with this email already exists' });
    }
    next(err);
  }
}

/**
 * POST /api/auth/login
 * Validates credentials and returns a JWT on success.
 */
async function login(req, res, next) {
  try {
    let { email, password } = req.body || {};
    email = (email || '').trim().toLowerCase();

    if (!email || !password) {
      return res
        .status(400)
        .json({ success: false, message: 'Email and password are required' });
    }

    const user = await findUserByEmail(email);
    // Use the same generic message for "no user" and "wrong password"
    // so we don't leak which emails are registered.
    if (!user) {
      return res.status(401).json({ success: false, message: 'Invalid email or password' });
    }

    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      return res.status(401).json({ success: false, message: 'Invalid email or password' });
    }

    const token = generateToken(user.id);

    return res.status(200).json({
      success: true,
      message: 'Logged in successfully',
      token,
      user: publicUser(user),
    });
  } catch (err) {
    next(err);
  }
}

/**
 * GET /api/auth/me  (protected)
 * Returns the currently authenticated user. `req.user` is set by `protect`.
 */
async function getMe(req, res) {
  return res.status(200).json({
    success: true,
    user: publicUser(req.user),
  });
}

module.exports = {
  register,
  login,
  getMe,
};

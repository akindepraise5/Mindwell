const jwt = require('jsonwebtoken');
const { findUserById } = require('../models/userModel');

/**
 * Protect routes by requiring a valid `Authorization: Bearer <token>` header.
 * On success, attaches the authenticated user (no password) to `req.user`.
 */
async function protect(req, res, next) {
  try {
    const authHeader = req.headers.authorization || '';

    if (!authHeader.startsWith('Bearer ')) {
      return res
        .status(401)
        .json({ success: false, message: 'Not authorized, no token provided' });
    }

    const token = authHeader.split(' ')[1];

    let decoded;
    try {
      decoded = jwt.verify(token, process.env.JWT_SECRET);
    } catch (err) {
      return res
        .status(401)
        .json({ success: false, message: 'Not authorized, token invalid or expired' });
    }

    // Ensure the user still exists (e.g. not deleted after token was issued).
    const user = await findUserById(decoded.id);
    if (!user) {
      return res
        .status(401)
        .json({ success: false, message: 'Not authorized, user no longer exists' });
    }

    req.user = user;
    next();
  } catch (err) {
    next(err);
  }
}

module.exports = { protect };

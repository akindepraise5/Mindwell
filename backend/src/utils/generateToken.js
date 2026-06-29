const jwt = require('jsonwebtoken');

/**
 * Sign a JWT for the given user id. Token expires in 7 days.
 * @param {number} userId
 * @returns {string} signed JWT
 */
function generateToken(userId) {
  if (!process.env.JWT_SECRET) {
    throw new Error('JWT_SECRET is not set in environment variables');
  }

  return jwt.sign({ id: userId }, process.env.JWT_SECRET, {
    expiresIn: '7d',
  });
}

module.exports = generateToken;

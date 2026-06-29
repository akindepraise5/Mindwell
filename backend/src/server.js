const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');

dotenv.config();

const { initDb } = require('./config/db');
const authRoutes = require('./routes/authRoutes');

const app = express();

// --- Core middleware ---
const allowedOrigins = (process.env.CLIENT_ORIGIN || '')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

app.use(
  cors({
    origin: allowedOrigins.length ? allowedOrigins : '*',
    credentials: true,
  })
);
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// --- Health check ---
app.get('/api/health', (req, res) => {
  res.status(200).json({ success: true, message: 'MindWell API is running' });
});

// --- Routes ---
app.use('/api/auth', authRoutes);

// --- 404 handler ---
app.use((req, res) => {
  res.status(404).json({ success: false, message: 'Route not found' });
});

// --- Central error handler ---
// Any `next(err)` from controllers/middleware lands here.
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ success: false, message: 'Internal server error' });
});

const PORT = process.env.PORT || 5000;

// Start the server only after the DB connection is verified.
(async () => {
  try {
    await initDb();
    console.log('✓ Database connected and ready');
    app.listen(PORT, () => {
      console.log(`✓ MindWell API listening on http://localhost:${PORT}`);
    });
  } catch (err) {
    console.error('✗ Failed to start server — database connection error:');
    const detail = err.sqlMessage || err.message || err.code || String(err);
    console.error(`  ${err.code ? '[' + err.code + '] ' : ''}${detail}`);
    console.error('  Check your .env DB_* values and that MySQL is running.');
    process.exit(1);
  }
})();

module.exports = app;

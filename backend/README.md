# MindWell — Authentication Backend

Express + MySQL + JWT authentication API for MindWell.

## Stack
- **Express** — HTTP server
- **mysql2** — MySQL driver (promise pool)
- **bcryptjs** — password hashing
- **jsonwebtoken** — JWT (expires in 7 days)
- **cors**, **dotenv**

## Setup

1. **Install dependencies**
   ```bash
   cd backend
   npm install
   ```

2. **Configure environment**
   Copy `.env.example` to `.env` and adjust if needed:
   ```env
   PORT=5000
   JWT_SECRET=change_this_secret
   DB_HOST=localhost
   DB_USER=root
   DB_PASSWORD=
   DB_NAME=mindwell
   ```
   > Use a long random `JWT_SECRET` in production.

3. **Create the database**
   Either run the schema file:
   ```bash
   mysql -u root -p < schema.sql
   ```
   …or just create the `mindwell` database — the server auto-creates the
   `users` table on startup.

4. **Run**
   ```bash
   npm run dev    # nodemon (development)
   npm start      # node (production)
   ```
   Server: `http://localhost:5000`

## API

Base URL: `http://localhost:5000/api/auth`

### `POST /register`
```json
{ "fullName": "Tunde Okoro", "email": "tunde@student.edu.ng", "password": "secret123", "role": "student" }
```
`201` → `{ success, message, token, user }`

### `POST /login`
```json
{ "email": "tunde@student.edu.ng", "password": "secret123" }
```
`200` → `{ success, message, token, user }`

### `GET /me`  (protected)
Header: `Authorization: Bearer <token>`
`200` → `{ success, user }`

### `GET /api/health`
`200` → `{ success, message }`

## Notes
- Passwords are hashed with bcrypt (salt rounds: 10) and never returned.
- Login uses a generic "Invalid email or password" message to avoid leaking which emails are registered.
- Tokens expire after 7 days.

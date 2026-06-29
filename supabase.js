// ============================================================
//  MindWell — Supabase client
//  Single-page static app (no bundler): loaded as an ES module.
//  The bare "@supabase/supabase-js" specifier is resolved by the
//  <script type="importmap"> in mindwell-landing.html (-> esm.sh CDN).
// ============================================================
import { createClient } from '@supabase/supabase-js';

// 🔑 Fill these in from your Supabase project:
//    Project Settings → API → Project URL  /  Project API keys (anon public)
const supabaseUrl = 'https://nvjsorcwftjlrqwpegcv.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im52anNvcmN3ZnRqbHJxd3BlZ2N2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI1MjEzNTYsImV4cCI6MjA5ODA5NzM1Nn0.5wX4eU1JH0Js8SOrFqvNJWVPqzinLPnbhhjSb6JMqvE';

// Where auth emails (e.g. email confirmation) should send users back to.
// Email confirmation is DISABLED for the demo, so this is unused right now,
// but it is kept configurable for future deployment. For production, set this
// to your deployed origin (e.g. 'https://mindwell.app'); locally it just uses
// the current origin so it never points at a stray dev-server directory listing.
window.MINDWELL_REDIRECT_URL = window.location.origin;

// The anon key is safe to expose in a client app — Row Level Security
// is what actually protects the data.
window.supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,       // keep the session in localStorage
    autoRefreshToken: true,     // refresh the JWT automatically
    detectSessionInUrl: false,  // email confirmation is off — no URL tokens to parse
  },
});

// True only when real credentials have been provided.
window.SUPABASE_CONFIGURED =
  supabaseUrl !== 'YOUR_SUPABASE_URL' &&
  supabaseAnonKey !== 'YOUR_SUPABASE_ANON_KEY' &&
  !!supabaseUrl && !!supabaseAnonKey;

if (!window.SUPABASE_CONFIGURED) {
  console.warn(
    '[MindWell] Supabase is not configured yet. ' +
    'Edit supabase.js and set supabaseUrl + supabaseAnonKey.'
  );
}

// Let the main script know the client is ready.
window.__supabaseReady = true;
document.dispatchEvent(new Event('supabase-ready'));

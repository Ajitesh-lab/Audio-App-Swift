import express from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import Database from 'better-sqlite3';
import passport from 'passport';
import { Strategy as GoogleStrategy } from 'passport-google-oauth20';
import session from 'express-session';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const router = express.Router();

// JWT Secret (in production, use environment variable)
const JWT_SECRET = process.env.JWT_SECRET || 'your-super-secret-jwt-key-change-this-in-production';
const JWT_EXPIRES_IN = '30d'; // Token expires in 30 days

// Initialize SQLite database - use persistent volume on Fly.io
const dbPath = process.env.FLY_APP_NAME
  ? '/data/users.db'
  : join(__dirname, 'users.db');

console.log(`Using database at: ${dbPath}`);
const db = new Database(dbPath);

// Create users table
db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT UNIQUE NOT NULL,
    password TEXT,
    name TEXT,
    google_id TEXT UNIQUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  )
`);

// Create license keys table
db.exec(`
  CREATE TABLE IF NOT EXISTS license_keys (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    license_key TEXT UNIQUE NOT NULL,
    used_by_user_id INTEGER,
    max_devices INTEGER DEFAULT 2,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    used_at DATETIME,
    FOREIGN KEY (used_by_user_id) REFERENCES users(id)
  )
`);

// Create devices table
db.exec(`
  CREATE TABLE IF NOT EXISTS devices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    device_id TEXT NOT NULL,
    device_name TEXT,
    last_active DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, device_id),
    FOREIGN KEY (user_id) REFERENCES users(id)
  )
`);

// Middleware to verify JWT token
export const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN

  if (!token) {
    return res.status(401).json({ error: 'Access token required' });
  }

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) {
      return res.status(403).json({ error: 'Invalid or expired token' });
    }
    req.user = user;
    next();
  });
};

// Optional auth - adds user if token is present, but doesn't require it
export const optionalAuth = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (token) {
    jwt.verify(token, JWT_SECRET, (err, user) => {
      if (!err) {
        req.user = user;
      }
    });
  }
  next();
};

// Register with email/password
router.post('/register', async (req, res) => {
  try {
    const { email, password, name, licenseKey, deviceId, deviceName } = req.body;

    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password required' });
    }

    if (!licenseKey) {
      return res.status(400).json({ error: 'License key is required to register' });
    }

    // Check if license key exists and is unused
    const license = db.prepare('SELECT * FROM license_keys WHERE license_key = ?').get(licenseKey);
    if (!license) {
      return res.status(400).json({ error: 'Invalid license key' });
    }

    if (license.used_by_user_id) {
      return res.status(400).json({ error: 'This license key has already been used' });
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return res.status(400).json({ error: 'Invalid email format' });
    }

    // Validate password length
    if (password.length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters' });
    }

    // Check if user already exists
    const existingUser = db.prepare('SELECT * FROM users WHERE email = ?').get(email);
    if (existingUser) {
      return res.status(409).json({ error: 'User already exists' });
    }

    // Hash password
    const hashedPassword = await bcrypt.hash(password, 10);

    // Insert user
    const result = db.prepare(
      'INSERT INTO users (email, password, name) VALUES (?, ?, ?)'
    ).run(email, hashedPassword, name || null);

    const userId = result.lastInsertRowid;

    // Mark license key as used
    db.prepare("UPDATE license_keys SET used_by_user_id = ?, used_at = datetime('now') WHERE license_key = ?")
      .run(userId, licenseKey);

    // Register device if provided
    if (deviceId) {
      db.prepare('INSERT OR REPLACE INTO devices (user_id, device_id, device_name) VALUES (?, ?, ?)')
        .run(userId, deviceId, deviceName || 'Unknown Device');
    }

    // Generate JWT token
    const token = jwt.sign(
      { id: userId, email },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRES_IN }
    );

    res.status(201).json({
      message: 'User registered successfully',
      token,
      user: {
        id: userId,
        email,
        name: name || null
      }
    });
  } catch (error) {
    console.error('Registration error:', error);
    res.status(500).json({ error: 'Registration failed' });
  }
});

// Login with email/password
router.post('/login', async (req, res) => {
  try {
    const { email, password, deviceId, deviceName } = req.body;

    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password required' });
    }

    // Find user
    const user = db.prepare('SELECT * FROM users WHERE email = ?').get(email);
    if (!user || !user.password) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Verify password
    const validPassword = await bcrypt.compare(password, user.password);
    if (!validPassword) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Check device if provided
    if (deviceId) {
      // Get user's license info
      const license = db.prepare('SELECT max_devices FROM license_keys WHERE used_by_user_id = ?').get(user.id);
      const maxDevices = license ? license.max_devices : 2;

      // Check if device exists
      const existingDevice = db.prepare('SELECT * FROM devices WHERE user_id = ? AND device_id = ?').get(user.id, deviceId);
      
      if (!existingDevice) {
        // Check device count
        const deviceCount = db.prepare('SELECT COUNT(*) as count FROM devices WHERE user_id = ?').get(user.id).count;
        
        if (deviceCount >= maxDevices) {
          return res.status(403).json({ 
            error: 'Device limit reached',
            message: `This account is limited to ${maxDevices} devices. Please contact support to manage your devices.`
          });
        }

        // Add new device
        db.prepare('INSERT INTO devices (user_id, device_id, device_name) VALUES (?, ?, ?)')
          .run(user.id, deviceId, deviceName || 'Unknown Device');
      } else {
        // Update last active
        db.prepare("UPDATE devices SET last_active = datetime('now') WHERE user_id = ? AND device_id = ?")
          .run(user.id, deviceId);
      }
    }

    // Generate JWT token
    const token = jwt.sign(
      { id: user.id, email: user.email },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRES_IN }
    );

    res.json({
      message: 'Login successful',
      token,
      user: {
        id: user.id,
        email: user.email,
        name: user.name
      }
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Login failed' });
  }
});

// Forgot password endpoint
router.post('/forgot-password', async (req, res) => {
  try {
    const { email } = req.body;

    if (!email) {
      return res.status(400).json({ error: 'Email is required' });
    }

    // Check if user exists
    const user = db.prepare('SELECT * FROM users WHERE email = ?').get(email);
    
    // Always return success to prevent email enumeration
    // In production, you would send an actual email here
    if (user) {
      // Generate a password reset token
      const resetToken = jwt.sign(
        { id: user.id, email: user.email, type: 'password-reset' },
        JWT_SECRET,
        { expiresIn: '1h' }
      );

      // In production, send email with reset link containing the token
      // For now, just log it (you'll need to implement email sending)
      console.log(`Password reset token for ${email}: ${resetToken}`);
      console.log(`Reset link would be: ${process.env.SERVER_URL}/reset-password?token=${resetToken}`);
      
      // TODO: Send email with reset instructions
      // Example: await sendEmail(email, 'Password Reset', `Click here to reset: ${resetLink}`);
    }

    // Always return success message
    res.json({ 
      message: 'If an account exists with this email, you will receive password reset instructions.',
      success: true
    });
  } catch (error) {
    console.error('Forgot password error:', error);
    res.status(500).json({ error: 'Failed to process request' });
  }
});

// Get current user profile
router.get('/me', authenticateToken, (req, res) => {
  try {
    const user = db.prepare('SELECT id, email, name, created_at FROM users WHERE id = ?').get(req.user.id);
    
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json({ user });
  } catch (error) {
    console.error('Get user error:', error);
    res.status(500).json({ error: 'Failed to get user' });
  }
});

// Update user profile
router.put('/me', authenticateToken, async (req, res) => {
  try {
    const { name, currentPassword, newPassword } = req.body;
    const userId = req.user.id;

    // If changing password, verify current password first
    if (newPassword) {
      if (!currentPassword) {
        return res.status(400).json({ error: 'Current password required to change password' });
      }

      const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
      if (!user.password) {
        return res.status(400).json({ error: 'Cannot change password for Google account' });
      }

      const validPassword = await bcrypt.compare(currentPassword, user.password);
      if (!validPassword) {
        return res.status(401).json({ error: 'Current password is incorrect' });
      }

      if (newPassword.length < 6) {
        return res.status(400).json({ error: 'New password must be at least 6 characters' });
      }

      const hashedPassword = await bcrypt.hash(newPassword, 10);
      db.prepare('UPDATE users SET password = ? WHERE id = ?').run(hashedPassword, userId);
    }

    // Update name if provided
    if (name !== undefined) {
      db.prepare('UPDATE users SET name = ? WHERE id = ?').run(name, userId);
    }

    const updatedUser = db.prepare('SELECT id, email, name, created_at FROM users WHERE id = ?').get(userId);
    res.json({ message: 'Profile updated', user: updatedUser });
  } catch (error) {
    console.error('Update user error:', error);
    res.status(500).json({ error: 'Failed to update profile' });
  }
});

// Admin endpoints for license key management
// Generate random license key
function generateLicenseKey() {
  const chars = '0123456789';
  let key = '';
  for (let i = 0; i < 4; i++) {
    key += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return key;
}

// Create license keys (protected endpoint - you should add admin auth)
router.post('/admin/generate-keys', (req, res) => {
  try {
    const { count = 1, maxDevices = 2, adminSecret } = req.body;
    
    // Simple admin protection
    if (adminSecret !== process.env.ADMIN_SECRET) {
      return res.status(403).json({ error: 'Unauthorized' });
    }

    const keys = [];
    for (let i = 0; i < count; i++) {
      const licenseKey = generateLicenseKey();
      db.prepare('INSERT INTO license_keys (license_key, max_devices) VALUES (?, ?)')
        .run(licenseKey, maxDevices);
      keys.push(licenseKey);
    }

    res.json({ 
      message: `Generated ${count} license keys`,
      keys 
    });
  } catch (error) {
    console.error('Generate keys error:', error);
    res.status(500).json({ error: 'Failed to generate keys' });
  }
});

// List all license keys (admin only)
router.get('/admin/keys', (req, res) => {
  try {
    const { adminSecret } = req.query;
    
    if (adminSecret !== process.env.ADMIN_SECRET) {
      return res.status(403).json({ error: 'Unauthorized' });
    }

    const keys = db.prepare(`
      SELECT 
        lk.id,
        lk.license_key,
        lk.max_devices,
        lk.created_at,
        lk.used_at,
        u.email as used_by_email,
        (SELECT COUNT(*) FROM devices WHERE user_id = lk.used_by_user_id) as device_count
      FROM license_keys lk
      LEFT JOIN users u ON lk.used_by_user_id = u.id
      ORDER BY lk.created_at DESC
    `).all();

    res.json({ keys });
  } catch (error) {
    console.error('List keys error:', error);
    res.status(500).json({ error: 'Failed to list keys' });
  }
});

// Google OAuth setup
export const setupGoogleOAuth = (app) => {
  const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
  const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
  const SERVER_URL = process.env.SERVER_URL || 'http://localhost:3001';

  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET) {
    console.log('⚠️  Google OAuth not configured. Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in .env');
    return;
  }

  app.use(session({
    secret: process.env.SESSION_SECRET || 'your-session-secret-change-this',
    resave: false,
    saveUninitialized: false,
    cookie: { secure: process.env.NODE_ENV === 'production' }
  }));

  app.use(passport.initialize());
  app.use(passport.session());

  passport.use(new GoogleStrategy({
    clientID: GOOGLE_CLIENT_ID,
    clientSecret: GOOGLE_CLIENT_SECRET,
    callbackURL: `${SERVER_URL}/api/auth/google/callback`,
    proxy: true
  }, async (accessToken, refreshToken, profile, done) => {
    try {
      const email = profile.emails && profile.emails[0] ? profile.emails[0].value : null;
      const name = profile.displayName;
      const googleId = profile.id;

      if (!email) {
        return done(new Error('No email found in Google profile'), null);
      }

      // Check if user exists with this Google ID
      let user = db.prepare('SELECT * FROM users WHERE google_id = ?').get(googleId);
      
      if (!user) {
        // Check if email exists (link accounts)
        user = db.prepare('SELECT * FROM users WHERE email = ?').get(email);
        
        if (user) {
          // Link Google account to existing user
          db.prepare('UPDATE users SET google_id = ? WHERE id = ?').run(googleId, user.id);
        } else {
          // For Google OAuth, we'll allow registration without license key
          // But mark it as Google-authenticated account
          const result = db.prepare(
            'INSERT INTO users (email, name, google_id) VALUES (?, ?, ?)'
          ).run(email, name, googleId);
          
          user = {
            id: result.lastInsertRowid,
            email,
            name,
            google_id: googleId
          };
        }
      }

      done(null, user);
    } catch (error) {
      console.error('Google OAuth error:', error);
      done(error, null);
    }
  }));

  passport.serializeUser((user, done) => {
    done(null, user.id);
  });

  passport.deserializeUser((id, done) => {
    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(id);
    done(null, user);
  });

  // Google OAuth routes
  app.get('/api/auth/google',
    passport.authenticate('google', { scope: ['profile', 'email'] })
  );

  app.get('/api/auth/google/callback',
    passport.authenticate('google', { failureRedirect: '/api/auth/google/failure' }),
    (req, res) => {
      // Generate JWT token
      const token = jwt.sign(
        { id: req.user.id, email: req.user.email },
        JWT_SECRET,
        { expiresIn: JWT_EXPIRES_IN }
      );

      // Redirect to app with token (you'll need to handle this in your iOS app)
      res.redirect(`musicapp://auth?token=${token}`);
    }
  );

  app.get('/api/auth/google/failure', (req, res) => {
    res.status(401).json({ error: 'Google authentication failed' });
  });

  console.log('✅ Google OAuth configured');
};

export default router;

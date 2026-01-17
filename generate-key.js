#!/usr/bin/env node

// Simple script to generate production license keys
// Usage: node generate-key.js

const ADMIN_SECRET = 'your-super-secret-admin-key-2026';
const SERVER_URL = 'https://audio-rough-water-3069.fly.dev';

async function generateKey() {
  console.log('\n🔑 Generating license key...\n');

  try {
    const response = await fetch(`${SERVER_URL}/api/auth/admin/generate-keys`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        count: 1,
        maxDevices: 2,
        adminSecret: ADMIN_SECRET
      })
    });

    if (!response.ok) {
      const error = await response.json();
      console.error('❌ Error:', error.error);
      process.exit(1);
    }

    const result = await response.json();
    const key = result.keys[0];
    
    console.log('✅ License Key Generated!\n');
    console.log('═══════════════════════════════════════════');
    console.log(`   ${key}`);
    console.log('═══════════════════════════════════════════\n');
    console.log('💡 This key works for 2 devices');
    console.log('📋 Copy and give to your customer!\n');

  } catch (error) {
    console.error('❌ Network error:', error.message);
    console.log('\n⚠️  Make sure the server is running!');
    process.exit(1);
  }
}

generateKey();

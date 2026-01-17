// Simple script to generate license keys
// Usage: node generate-keys.js [count] [maxDevices]

import 'dotenv/config';

const ADMIN_SECRET = process.env.ADMIN_SECRET || 'your-super-secret-admin-key-2026';
const SERVER_URL = process.env.SERVER_URL || 'http://localhost:3001';

const count = parseInt(process.argv[2]) || 1;
const maxDevices = parseInt(process.argv[3]) || 2;

console.log(`\n🔑 Generating ${count} license key(s) with max ${maxDevices} devices each...\n`);

async function generateKeys() {
  try {
    const response = await fetch(`${SERVER_URL}/api/auth/admin/generate-keys`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        count,
        maxDevices,
        adminSecret: ADMIN_SECRET
      })
    });

    if (!response.ok) {
      const error = await response.json();
      console.error('❌ Error:', error.error);
      process.exit(1);
    }

    const result = await response.json();
    console.log('✅ Success!\n');
    console.log('Generated Keys:');
    console.log('═══════════════════════════════════════════');
    result.keys.forEach((key, index) => {
      console.log(`${index + 1}. ${key}`);
    });
    console.log('═══════════════════════════════════════════\n');
    console.log(`💡 Each key can be used for ${maxDevices} device(s)`);
    console.log('📋 Give these keys to your customers!\n');

  } catch (error) {
    console.error('❌ Network error:', error.message);
    console.log('\n⚠️  Make sure the server is running!');
    process.exit(1);
  }
}

generateKeys();

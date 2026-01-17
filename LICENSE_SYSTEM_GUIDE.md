# License Key System - Quick Guide

## How It Works

Your app now has a **license key system** to prevent file sharing:

1. **Each customer needs a unique license key to register**
2. **Each license key can only be used once** (one account per key)
3. **Each account is limited to 2 devices** (can be changed per key)
4. **Device tracking prevents sharing** - users can't share their login on unlimited devices

## Selling Your App

### When You Make a Sale:
1. Generate a license key
2. Send the key to the customer
3. Customer downloads the app file (IPA)
4. Customer installs the app
5. Customer registers with the license key

### Why This Prevents Sharing:

- **File sharing doesn't work** because the app file is useless without a valid license key
- **Account sharing is limited** to 2 devices max (you control this number)
- **Each key works only once** - can't be reused by multiple people

## Generating License Keys

### For Each Sale:
```bash
node generate-keys.js 1 2
```
This generates **1 key** that allows **2 devices**.

### Bulk Generation (for 10 sales):
```bash
node generate-keys.js 10 2
```

### Want to allow more devices per customer?
```bash
node generate-keys.js 1 5
```
This creates a key that allows **5 devices** (premium option, charge more!)

## Checking License Keys

You can view all license keys and their status:

```bash
curl "https://audio-rough-water-3069.fly.dev/api/auth/admin/keys?adminSecret=your-super-secret-admin-key-2026"
```

This shows:
- All generated keys
- Which keys have been used
- Who used each key (email)
- How many devices each user has

## Customer Registration Flow

1. Customer opens the app
2. Clicks "Create Account"
3. Enters:
   - Name (optional)
   - Email
   - **License Key** (the key you gave them)
   - Password
   - Confirm Password
4. Taps "Create Account"

### If License Key is Invalid:
- Already used → Error: "This license key has already been used"
- Doesn't exist → Error: "Invalid license key"
- Missing → Error: "License key is required to register"

## Device Limits

When a user tries to login on a **new device** and they've reached their limit:
- Error: "Device limit reached. This account is limited to 2 devices."
- They must contact you to manage devices

### How Device Tracking Works:
- First login on iPhone 1 ✅ (1/2 devices)
- Login on iPad ✅ (2/2 devices)
- Login on iPhone 2 ❌ (Device limit reached!)
- Login again on iPhone 1 ✅ (Already registered device)

## Pricing Strategy Ideas

### Basic License ($X):
- 1 license key
- 2 devices max
- Standard support

### Premium License ($X+):
- 1 license key
- 5 devices max
- Priority support

Generate premium keys with:
```bash
node generate-keys.js 1 5
```

## Security Features

✅ **License keys are single-use** - can't be shared with friends
✅ **Device limits** - can't share account with unlimited people
✅ **Unique device IDs** - tracks each device separately
✅ **Email verification** - proper user accounts
✅ **Server-side validation** - can't be bypassed

## Example Sale Workflow

1. **Customer DMs you on TikTok**: "I want to buy the app!"
2. **You generate a key**: `node generate-keys.js 1 2`
3. **You get**: `7P1G-E7XD-UQ7P-7RV0`
4. **You send customer**:
   - App file (IPA)
   - License key: `7P1G-E7XD-UQ7P-7RV0`
   - Instructions: "Install the app, register with this key"
5. **Customer registers** with the key
6. **Done!** ✅

If they try to share the key with someone else:
- ❌ Error: "This license key has already been used"

If they try to share their login on 3+ devices:
- ❌ Error: "Device limit reached"

## Admin Secret

⚠️ **KEEP THIS SECRET!** ⚠️

Your admin secret is: `your-super-secret-admin-key-2026`

This is used to:
- Generate license keys
- View all keys and users
- Manage the system

Don't share this with anyone!

## Testing Before Selling

1. Generate a test key: `node generate-keys.js 1 2`
2. Install the app on your iPhone
3. Register with the test key
4. Try to register again with the same key → Should fail
5. Login on a second device → Should work
6. Try to login on a third device → Should be blocked

## Support Questions

When customers have issues:

**"My license key doesn't work!"**
- Check if they typed it correctly (case-insensitive but no spaces)
- Check if key was already used (curl the admin endpoint)

**"I can't login on my new phone!"**
- They hit the device limit
- You can either:
  - Reset their devices (requires manual database access)
  - Sell them a premium license with more devices

**"Can I share with my family?"**
- Yes, within the device limit (2 devices)
- If they need more, sell them a premium license

## Next Steps

1. ✅ Generate 5-10 test keys
2. ✅ Test the registration flow yourself
3. ✅ Post on TikTok with your offer
4. ✅ When you make a sale, generate a key
5. ✅ Send customer the app + key
6. 💰 Profit!

---

**Quick Commands Reference:**

```bash
# Generate 1 key (basic - 2 devices)
node generate-keys.js 1 2

# Generate 10 keys (for bulk sales)
node generate-keys.js 10 2

# Generate 1 premium key (5 devices)
node generate-keys.js 1 5

# View all keys
curl "https://audio-rough-water-3069.fly.dev/api/auth/admin/keys?adminSecret=your-super-secret-admin-key-2026"
```
